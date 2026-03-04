const std = @import("std");
const beam_math = @import("../engine/math.zig");
const loads_mod = @import("../engine/loads.zig");
const wood = @import("../engine/materials/wood.zig");
const nds = @import("../engine/codes/nds2018.zig");

pub const CheckStatus = enum {
    pass,
    fail,
};

pub const CodeEdition = enum { nds2018 };

pub const Inputs = struct {
    height_ft: f64,
    width_in: f64, // b (smaller dimension for non-square)
    depth_in: f64, // d (larger dimension for non-square)
    material: wood.WoodMaterial,

    // Axial loads
    axial_dead_lb: f64 = 0,
    axial_live_lb: f64 = 0,
    axial_snow_lb: f64 = 0,
    axial_wind_lb: f64 = 0,

    // Applied moments (at column ends or midheight)
    moment_x_dead_ft_lb: f64 = 0, // strong-axis bending
    moment_x_live_ft_lb: f64 = 0,
    moment_y_dead_ft_lb: f64 = 0, // weak-axis bending
    moment_y_live_ft_lb: f64 = 0,

    include_self_weight: bool = true,

    // Effective length factors (default pinned-pinned)
    ke_x: f64 = 1.0,
    ke_y: f64 = 1.0,

    moisture: nds.MoistureCondition = .dry,
    temperature: nds.TemperatureCondition = .normal,
    incising: nds.IncisingCondition = .none,

    code_edition: CodeEdition = .nds2018,
};

pub const Outputs = struct {
    // Section properties
    area_in2: f64,
    ix_in4: f64,
    iy_in4: f64,
    sx_in3: f64,
    sy_in3: f64,
    rx_in: f64,
    ry_in: f64,

    // Self weight
    self_weight_lb: f64,

    // Governing combo
    governing_combo_name: [32]u8,
    governing_combo_len: u8,
    governing_axial_lb: f64,
    governing_moment_x_ft_lb: f64,
    governing_moment_y_ft_lb: f64,
    governing_load_duration: loads_mod.LoadDuration,

    // Adjusted values (from governing combo)
    adjusted: nds.ColumnAdjustedValues,

    // Slenderness
    le_d_x: f64,
    le_d_y: f64,

    // Actual stresses (from governing combo)
    fc_actual: f64,
    fbx_actual: f64,
    fby_actual: f64,

    // DCR ratios
    dcr_compression: f64, // fc / Fc'
    dcr_interaction: f64, // NDS Eq. 3.9-3

    // Status
    compression_status: CheckStatus,
    interaction_status: CheckStatus,
    overall_status: CheckStatus,

    pub fn governingComboName(self: *const Outputs) []const u8 {
        return self.governing_combo_name[0..self.governing_combo_len];
    }
};

pub const ComputeError = error{
    InvalidHeight,
    InvalidSection,
    SlendernessExceeded,
};

pub fn compute(inputs: Inputs) ComputeError!Outputs {
    // 1. Validate geometry
    if (inputs.height_ft <= 0) return error.InvalidHeight;
    if (inputs.width_in <= 0 or inputs.depth_in <= 0) return error.InvalidSection;

    // 2. Section properties
    const section = beam_math.RectSection{ .b = inputs.width_in, .d = inputs.depth_in };
    const area = section.area();
    const ix = section.momentOfInertia();
    const iy = section.momentOfInertiaWeak();
    const sx = section.sectionModulus();
    const sy = section.sectionModulusWeak();
    const rx = section.radiusOfGyration();
    const ry = section.radiusOfGyrationWeak();

    // 3. Effective lengths
    const le_x_in = inputs.ke_x * inputs.height_ft * 12.0;
    const le_y_in = inputs.ke_y * inputs.height_ft * 12.0;

    // Check le/d <= 50 (NDS 3.7.1.4)
    const le_d_x = le_x_in / inputs.depth_in;
    const le_d_y = le_y_in / inputs.width_in;
    if (le_d_x > 50.0 or le_d_y > 50.0) return error.SlendernessExceeded;

    // 4. Material properties
    const ref = inputs.material.referenceProps();
    const buckling_c = inputs.material.bucklingC();

    // 5. Self weight = sg * 62.4 * A / 144 * height_ft (total lbs)
    const self_weight_lb = if (inputs.include_self_weight)
        ref.sg * 62.4 * area / 144.0 * inputs.height_ft
    else
        0;

    // 6. Build load cases for axial, moment_x, moment_y
    var axial_case = loads_mod.LoadCase{};
    axial_case.set(.dead, inputs.axial_dead_lb + self_weight_lb);
    axial_case.set(.live, inputs.axial_live_lb);
    axial_case.set(.snow, inputs.axial_snow_lb);
    axial_case.set(.wind, inputs.axial_wind_lb);

    var mx_case = loads_mod.LoadCase{};
    mx_case.set(.dead, inputs.moment_x_dead_ft_lb);
    mx_case.set(.live, inputs.moment_x_live_ft_lb);

    var my_case = loads_mod.LoadCase{};
    my_case.set(.dead, inputs.moment_y_dead_ft_lb);
    my_case.set(.live, inputs.moment_y_live_ft_lb);

    // 7. Evaluate all 21 ASD combos -- track worst interaction ratio
    var worst_interaction: f64 = 0;
    var worst_idx: usize = 0;
    var worst_p: f64 = 0;
    var worst_mx: f64 = 0;
    var worst_my: f64 = 0;
    var worst_fc_actual: f64 = 0;
    var worst_fbx_actual: f64 = 0;
    var worst_fby_actual: f64 = 0;
    var worst_dcr_comp: f64 = 0;
    var worst_adj: nds.ColumnAdjustedValues = undefined;
    var worst_duration: loads_mod.LoadDuration = .normal;

    for (loads_mod.asd_combinations, 0..) |c, i| {
        const p = c.apply(axial_case);
        const mx = c.apply(mx_case);
        const my = c.apply(my_case);

        // Skip combos with no load (or net tension -- not handled here)
        if (p <= 0 and mx == 0 and my == 0) continue;

        // Load duration for this combo
        const duration = loads_mod.governingLoadDuration(i, axial_case);

        // Adjusted values with this combo's load duration
        const adj = nds.columnAdjustedValues(
            ref.fc,
            ref.fc_perp,
            ref.fb,
            ref.fv,
            ref.e,
            ref.e_min,
            inputs.width_in,
            inputs.depth_in,
            .{
                .load_duration = duration,
                .moisture = inputs.moisture,
                .temperature = inputs.temperature,
                .incising = inputs.incising,
                .le_x_in = le_x_in,
                .le_y_in = le_y_in,
                .buckling_c = buckling_c,
            },
        );

        // Actual stresses
        const fc_act = if (p > 0) p / area else 0;
        const fbx_act = if (mx != 0) @abs(mx) * 12.0 / sx else 0;
        const fby_act = if (my != 0) @abs(my) * 12.0 / sy else 0;

        // DCR compression
        const dcr_comp = if (adj.fc_prime > 0) fc_act / adj.fc_prime else 0;

        // NDS 2018 Eq. 3.9-3 interaction:
        // (fc/Fc')^2 + fb1/(Fb1'*(1 - fc/FcE1)) + fb2/(Fb2'*(1 - fc/FcE2 - (fb1/FbE)^2)) <= 1.0
        var interaction: f64 = 0;

        if (p > 0 and adj.fc_prime > 0) {
            interaction += (fc_act / adj.fc_prime) * (fc_act / adj.fc_prime);
        }

        if (fbx_act > 0 and adj.fb_prime > 0) {
            // Amplification: 1 - fc/FcE1 (FcE for strong axis)
            var amp_x: f64 = 1.0;
            if (adj.fce_x > 0 and fc_act > 0) {
                amp_x = 1.0 - fc_act / adj.fce_x;
            }
            if (amp_x <= 0) amp_x = 0.001; // prevent division by zero
            interaction += fbx_act / (adj.fb_prime * amp_x);
        }

        if (fby_act > 0 and adj.fb_prime > 0) {
            // Amplification: 1 - fc/FcE2 - (fb1/FbE)^2
            // FbE = 1.20 * E'min / RB^2 where RB for lateral-torsional buckling
            // For columns, simplified: use FcE for weak axis
            var amp_y: f64 = 1.0;
            if (adj.fce_y > 0 and fc_act > 0) {
                amp_y = 1.0 - fc_act / adj.fce_y;
            }
            // Subtract (fb1/FbE)^2 term if strong-axis bending present
            if (adj.fce_x > 0 and fbx_act > 0) {
                // FbE approximation using critical buckling stress for lateral stability
                // For rectangular columns: FbE = 1.20 * E'min / RB^2
                // RB = sqrt(le_x * d / b^2) -- but for column bending stability,
                // use the simpler FcE-based approach per NDS commentary
                const fbe = 1.20 * adj.e_min_prime * inputs.width_in * inputs.width_in / (le_x_in * inputs.depth_in);
                if (fbe > 0) {
                    amp_y -= (fbx_act / fbe) * (fbx_act / fbe);
                }
            }
            if (amp_y <= 0) amp_y = 0.001;
            interaction += fby_act / (adj.fb_prime * amp_y);
        }

        if (interaction > worst_interaction) {
            worst_interaction = interaction;
            worst_idx = i;
            worst_p = p;
            worst_mx = mx;
            worst_my = my;
            worst_fc_actual = fc_act;
            worst_fbx_actual = fbx_act;
            worst_fby_actual = fby_act;
            worst_dcr_comp = dcr_comp;
            worst_adj = adj;
            worst_duration = duration;
        }
    }

    // Copy combo name
    var combo_name: [32]u8 = .{0} ** 32;
    const gov_name = loads_mod.asd_combinations[worst_idx].name;
    const name_len: u8 = @intCast(@min(gov_name.len, 32));
    @memcpy(combo_name[0..name_len], gov_name[0..name_len]);

    // Status
    const comp_status: CheckStatus = if (worst_dcr_comp <= 1.0) .pass else .fail;
    const inter_status: CheckStatus = if (worst_interaction <= 1.0) .pass else .fail;
    const overall: CheckStatus = if (comp_status == .pass and inter_status == .pass) .pass else .fail;

    return .{
        .area_in2 = area,
        .ix_in4 = ix,
        .iy_in4 = iy,
        .sx_in3 = sx,
        .sy_in3 = sy,
        .rx_in = rx,
        .ry_in = ry,
        .self_weight_lb = self_weight_lb,
        .governing_combo_name = combo_name,
        .governing_combo_len = name_len,
        .governing_axial_lb = worst_p,
        .governing_moment_x_ft_lb = worst_mx,
        .governing_moment_y_ft_lb = worst_my,
        .governing_load_duration = worst_duration,
        .adjusted = worst_adj,
        .le_d_x = le_d_x,
        .le_d_y = le_d_y,
        .fc_actual = worst_fc_actual,
        .fbx_actual = worst_fbx_actual,
        .fby_actual = worst_fby_actual,
        .dcr_compression = worst_dcr_comp,
        .dcr_interaction = worst_interaction,
        .compression_status = comp_status,
        .interaction_status = inter_status,
        .overall_status = overall,
    };
}

// -- Tests ----------------------------------------------------------------

test "pure axial 6x6 DF-L No.2 at 10ft" {
    const inputs = Inputs{
        .height_ft = 10,
        .width_in = 5.5,
        .depth_in = 5.5,
        .material = .{ .sawn_lumber = .{ .species = .douglas_fir_larch, .grade = .no2 } },
        .axial_dead_lb = 5000,
        .axial_live_lb = 10000,
        .include_self_weight = false,
    };
    const out = try compute(inputs);

    // Section: 5.5 x 5.5 = 30.25 in2
    try std.testing.expectApproxEqAbs(out.area_in2, 30.25, 0.01);

    // Cp should be between 0 and 1 for 10' column
    try std.testing.expect(out.adjusted.cp_x > 0.1);
    try std.testing.expect(out.adjusted.cp_x < 1.0);

    // Both axes equal for square
    try std.testing.expectApproxEqAbs(out.adjusted.cp_x, out.adjusted.cp_y, 0.001);

    // Actual stress = P/A
    try std.testing.expect(out.fc_actual > 0);

    // DCR should be reasonable
    try std.testing.expect(out.dcr_compression > 0);
    try std.testing.expect(out.dcr_interaction > 0);

    // le/d = 120/5.5 = 21.8
    try std.testing.expectApproxEqAbs(out.le_d_x, 120.0 / 5.5, 0.01);
}

test "combined axial + moment" {
    const inputs = Inputs{
        .height_ft = 10,
        .width_in = 3.5,
        .depth_in = 5.5,
        .material = .{ .sawn_lumber = .{ .species = .douglas_fir_larch, .grade = .no2 } },
        .axial_dead_lb = 3000,
        .axial_live_lb = 5000,
        .moment_x_dead_ft_lb = 500,
        .moment_x_live_ft_lb = 1000,
        .include_self_weight = false,
    };
    const out = try compute(inputs);

    // Interaction should be greater than pure compression DCR
    try std.testing.expect(out.dcr_interaction > out.dcr_compression);
    try std.testing.expect(out.fbx_actual > 0);
}

test "slenderness rejection" {
    const inputs = Inputs{
        .height_ft = 30,
        .width_in = 3.5,
        .depth_in = 3.5,
        // le/d = 360/3.5 = 102.9 > 50
        .material = .{ .sawn_lumber = .{ .species = .douglas_fir_larch, .grade = .no2 } },
        .axial_dead_lb = 1000,
        .include_self_weight = false,
    };
    const result = compute(inputs);
    try std.testing.expectError(error.SlendernessExceeded, result);
}

test "self weight calculation" {
    const inputs = Inputs{
        .height_ft = 10,
        .width_in = 5.5,
        .depth_in = 5.5,
        .material = .{ .sawn_lumber = .{ .species = .douglas_fir_larch, .grade = .no2 } },
        .axial_dead_lb = 5000,
        .axial_live_lb = 5000,
        .include_self_weight = true,
    };
    const out = try compute(inputs);
    // SG=0.50, A=30.25, weight = 0.50 * 62.4 * 30.25 / 144 * 10 = 65.4 lb
    try std.testing.expect(out.self_weight_lb > 60.0);
    try std.testing.expect(out.self_weight_lb < 70.0);
}

test "glulam column" {
    const inputs = Inputs{
        .height_ft = 12,
        .width_in = 5.125,
        .depth_in = 5.125,
        .material = .{ .glulam = .{ .stress_class = .@"24F-1.8E" } },
        .axial_dead_lb = 10000,
        .axial_live_lb = 20000,
        .include_self_weight = false,
    };
    const out = try compute(inputs);
    // Glulam uses c=0.9
    try std.testing.expect(out.adjusted.cp_x > 0.0);
    try std.testing.expect(out.dcr_compression > 0);
}
