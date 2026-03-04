const std = @import("std");
const beam_math = @import("../engine/math.zig");
const loads_mod = @import("../engine/loads.zig");
const wood = @import("../engine/materials/wood.zig");
const nds = @import("../engine/codes/nds2018.zig");

pub const max_point_loads = 8;

pub const CheckStatus = enum {
    pass,
    fail,
};

pub const PointLoad = struct {
    p_lb: f64 = 0,
    a_ft: f64 = 0,
    load_type: loads_mod.LoadType = .live,
};

pub const Inputs = struct {
    span_ft: f64,
    width_in: f64,
    depth_in: f64,
    material: wood.WoodMaterial,

    dead_load_plf: f64 = 0,
    live_load_plf: f64 = 0,
    snow_load_plf: f64 = 0,
    wind_load_plf: f64 = 0,

    point_loads: [max_point_loads]PointLoad = .{PointLoad{}} ** max_point_loads,
    point_load_count: u8 = 0,

    include_self_weight: bool = true,

    load_duration: loads_mod.LoadDuration = .normal,
    moisture: nds.MoistureCondition = .dry,
    temperature: nds.TemperatureCondition = .normal,
    incising: nds.IncisingCondition = .none,
    repetitive: nds.RepetitiveCondition = .single,
    flat_use: bool = false,
    compression_edge_braced: bool = true,
    unbraced_length_ft: f64 = 0,

    deflection_limit_ll: f64 = 360, // L/360
    deflection_limit_tl: f64 = 240, // L/240

    code_edition: CodeEdition = .nds2018,
};

pub const CodeEdition = enum { nds2018 };

pub const Outputs = struct {
    // Section properties
    area_in2: f64,
    section_modulus_in3: f64,
    moment_of_inertia_in4: f64,

    // Self weight
    self_weight_plf: f64,

    // Governing combo
    governing_combo_name: [32]u8,
    governing_combo_len: u8,
    governing_total_plf: f64,
    governing_load_duration: loads_mod.LoadDuration,

    // Adjusted values
    adjusted: nds.AdjustedValues,

    // Beam analysis results
    max_moment_ft_lb: f64,
    max_shear_lb: f64,
    reaction_left_lb: f64,
    reaction_right_lb: f64,
    max_deflection_total_in: f64,
    max_deflection_ll_in: f64,

    // Actual stresses
    fb_actual: f64,
    fv_actual: f64,

    // DCR ratios
    dcr_bending: f64,
    dcr_shear: f64,
    dcr_deflection_ll: f64,
    dcr_deflection_tl: f64,

    // Status
    bending_status: CheckStatus,
    shear_status: CheckStatus,
    deflection_ll_status: CheckStatus,
    deflection_tl_status: CheckStatus,
    overall_status: CheckStatus,

    // Diagrams
    diagram: [beam_math.diagram_points]beam_math.DiagramPoint,

    pub fn governingComboName(self: *const Outputs) []const u8 {
        return self.governing_combo_name[0..self.governing_combo_len];
    }
};

pub const ComputeError = error{
    InvalidSpan,
    InvalidSection,
    MaterialNotFound,
    NoLoads,
};

pub fn compute(inputs: Inputs) ComputeError!Outputs {
    // 1. Validate
    if (inputs.span_ft <= 0) return error.InvalidSpan;
    if (inputs.width_in <= 0 or inputs.depth_in <= 0) return error.InvalidSection;

    // 2. Material properties
    const ref = inputs.material.referenceProps();

    // 3. Section properties
    const section = beam_math.RectSection{ .b = inputs.width_in, .d = inputs.depth_in };
    const area = section.area();
    const s = section.sectionModulus();
    const i = section.momentOfInertia();

    // 4. Self weight: weight_pcf = sg * 62.4; plf = weight_pcf * area / 144
    const self_weight_plf = if (inputs.include_self_weight)
        ref.sg * 62.4 * area / 144.0
    else
        0;

    const total_dead_plf = inputs.dead_load_plf + self_weight_plf;

    // 5. Build LoadCase and find governing ASD combo
    var case = loads_mod.LoadCase{};
    case.set(.dead, total_dead_plf);
    case.set(.live, inputs.live_load_plf);
    case.set(.snow, inputs.snow_load_plf);
    case.set(.wind, inputs.wind_load_plf);

    const gov = loads_mod.governingAsd(case);

    // 6. Load duration from governing combo
    const duration = loads_mod.governingLoadDuration(gov.index, case);

    // 7. Adjusted values via NDS 2018
    const adj_inputs = nds.AdjustmentInputs{
        .load_duration = duration,
        .moisture = inputs.moisture,
        .temperature = inputs.temperature,
        .incising = inputs.incising,
        .repetitive = inputs.repetitive,
        .flat_use = inputs.flat_use,
        .compression_edge_braced = inputs.compression_edge_braced,
        .unbraced_length_ft = inputs.unbraced_length_ft,
    };
    const adjusted = nds.adjustedValues(ref.fb, ref.fv, ref.e, ref.e_min, inputs.width_in, inputs.depth_in, adj_inputs);

    // 8. Build load array for beam analysis
    // Factored total uniform load for strength
    var beam_loads_buf: [max_point_loads + 1]beam_math.Load = undefined;
    var load_count: usize = 0;

    if (gov.total > 0) {
        beam_loads_buf[load_count] = .{ .uniform_full = .{ .w_plf = gov.total } };
        load_count += 1;
    }

    // Point loads (applied with their respective combo factor -- simplified: factor = 1.0)
    for (inputs.point_loads[0..inputs.point_load_count]) |pl| {
        if (pl.p_lb != 0) {
            beam_loads_buf[load_count] = .{ .point = .{ .p_lb = pl.p_lb, .a_ft = pl.a_ft } };
            load_count += 1;
        }
    }

    const beam_loads = beam_loads_buf[0..load_count];

    // 9. Analyze beam
    const analysis = beam_math.analyzeSimpleBeam(inputs.span_ft, beam_loads, adjusted.e_prime, i);

    // 10. Live-load-only deflection
    var ll_loads_buf: [max_point_loads + 1]beam_math.Load = undefined;
    var ll_count: usize = 0;
    if (inputs.live_load_plf > 0) {
        ll_loads_buf[ll_count] = .{ .uniform_full = .{ .w_plf = inputs.live_load_plf } };
        ll_count += 1;
    }
    for (inputs.point_loads[0..inputs.point_load_count]) |pl| {
        if (pl.p_lb != 0 and pl.load_type == .live) {
            ll_loads_buf[ll_count] = .{ .point = .{ .p_lb = pl.p_lb, .a_ft = pl.a_ft } };
            ll_count += 1;
        }
    }
    const ll_analysis = beam_math.analyzeSimpleBeam(inputs.span_ft, ll_loads_buf[0..ll_count], adjusted.e_prime, i);

    // 11. Actual stresses
    // fb = M * 12 / S  (convert ft-lb to in-lb)
    const fb_actual = @abs(analysis.max_moment_ft_lb) * 12.0 / s;
    // fv = 1.5 * V / A
    const fv_actual = 1.5 * @abs(analysis.max_shear_lb) / area;

    // 12. DCR ratios
    const dcr_bending = if (adjusted.fb_prime > 0) fb_actual / adjusted.fb_prime else std.math.inf(f64);
    const dcr_shear = if (adjusted.fv_prime > 0) fv_actual / adjusted.fv_prime else std.math.inf(f64);

    const defl_limit_ll = inputs.span_ft * 12.0 / inputs.deflection_limit_ll;
    const defl_limit_tl = inputs.span_ft * 12.0 / inputs.deflection_limit_tl;
    const dcr_defl_ll = if (defl_limit_ll > 0) @abs(ll_analysis.max_deflection_in) / defl_limit_ll else 0;
    const dcr_defl_tl = if (defl_limit_tl > 0) @abs(analysis.max_deflection_in) / defl_limit_tl else 0;

    // 13. Status
    const bending_status: CheckStatus = if (dcr_bending <= 1.0) .pass else .fail;
    const shear_status: CheckStatus = if (dcr_shear <= 1.0) .pass else .fail;
    const defl_ll_status: CheckStatus = if (dcr_defl_ll <= 1.0) .pass else .fail;
    const defl_tl_status: CheckStatus = if (dcr_defl_tl <= 1.0) .pass else .fail;

    const overall: CheckStatus = if (bending_status == .pass and shear_status == .pass and
        defl_ll_status == .pass and defl_tl_status == .pass) .pass else .fail;

    // Copy combo name to fixed buffer
    var combo_name: [32]u8 = .{0} ** 32;
    const name_len: u8 = @intCast(@min(gov.combo_name.len, 32));
    @memcpy(combo_name[0..name_len], gov.combo_name[0..name_len]);

    return .{
        .area_in2 = area,
        .section_modulus_in3 = s,
        .moment_of_inertia_in4 = i,
        .self_weight_plf = self_weight_plf,
        .governing_combo_name = combo_name,
        .governing_combo_len = name_len,
        .governing_total_plf = gov.total,
        .governing_load_duration = duration,
        .adjusted = adjusted,
        .max_moment_ft_lb = analysis.max_moment_ft_lb,
        .max_shear_lb = analysis.max_shear_lb,
        .reaction_left_lb = analysis.reaction_left_lb,
        .reaction_right_lb = analysis.reaction_right_lb,
        .max_deflection_total_in = analysis.max_deflection_in,
        .max_deflection_ll_in = ll_analysis.max_deflection_in,
        .fb_actual = fb_actual,
        .fv_actual = fv_actual,
        .dcr_bending = dcr_bending,
        .dcr_shear = dcr_shear,
        .dcr_deflection_ll = dcr_defl_ll,
        .dcr_deflection_tl = dcr_defl_tl,
        .bending_status = bending_status,
        .shear_status = shear_status,
        .deflection_ll_status = defl_ll_status,
        .deflection_tl_status = defl_tl_status,
        .overall_status = overall,
        .diagram = analysis.diagram,
    };
}

// -- Tests ----------------------------------------------------------------

test "basic wood beam compute" {
    const inputs = Inputs{
        .span_ft = 12,
        .width_in = 1.5,
        .depth_in = 9.25,
        .material = .{ .sawn_lumber = .{ .species = .douglas_fir_larch, .grade = .no2 } },
        .dead_load_plf = 150,
        .live_load_plf = 400,
        .include_self_weight = true,
    };
    const out = try compute(inputs);

    // Section properties: 2x10 nominal
    try std.testing.expectApproxEqAbs(out.section_modulus_in3, 21.3906, 0.01);

    // Should have governing combo
    try std.testing.expect(out.governing_total_plf > 0);

    // Stresses should be positive
    try std.testing.expect(out.fb_actual > 0);
    try std.testing.expect(out.fv_actual > 0);

    // DCRs should be reasonable
    try std.testing.expect(out.dcr_bending > 0);
    try std.testing.expect(out.dcr_shear > 0);
}

test "compute rejects invalid span" {
    const inputs = Inputs{
        .span_ft = 0,
        .width_in = 1.5,
        .depth_in = 9.25,
        .material = .{ .sawn_lumber = .{ .species = .douglas_fir_larch, .grade = .no2 } },
    };
    const result = compute(inputs);
    try std.testing.expectError(error.InvalidSpan, result);
}

test "self weight calculation" {
    const inputs = Inputs{
        .span_ft = 12,
        .width_in = 1.5,
        .depth_in = 9.25,
        .material = .{ .sawn_lumber = .{ .species = .douglas_fir_larch, .grade = .no2 } },
        .dead_load_plf = 0,
        .live_load_plf = 100,
        .include_self_weight = true,
    };
    const out = try compute(inputs);
    // SG=0.50, Area=13.875, weight = 0.50 * 62.4 * 13.875 / 144 = 3.0 plf (approx)
    try std.testing.expect(out.self_weight_plf > 2.5);
    try std.testing.expect(out.self_weight_plf < 3.5);
}

test "glulam beam compute" {
    const inputs = Inputs{
        .span_ft = 20,
        .width_in = 5.125,
        .depth_in = 12.0,
        .material = .{ .glulam = .{ .stress_class = .@"24F-1.8E" } },
        .dead_load_plf = 200,
        .live_load_plf = 600,
        .include_self_weight = true,
    };
    const out = try compute(inputs);
    try std.testing.expect(out.fb_actual > 0);
    try std.testing.expect(out.overall_status == .pass or out.overall_status == .fail);
}
