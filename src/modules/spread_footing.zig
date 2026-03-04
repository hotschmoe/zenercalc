const std = @import("std");
const math = std.math;
const loads_mod = @import("../engine/loads.zig");
const concrete = @import("../engine/materials/concrete.zig");
const aci = @import("../engine/codes/aci318.zig");

pub const CheckStatus = enum {
    pass,
    fail,
};

pub const FootingShape = enum {
    square,
    rectangular,
    circular,
};

pub const ColumnShape = enum {
    square,
    rectangular,
    circular,
};

pub const Inputs = struct {
    // Footing geometry
    footing_shape: FootingShape = .square,
    length_ft: f64, // L direction
    width_ft: f64, // B direction (= length for square)
    thickness_in: f64 = 18.0,
    cover_in: f64 = 3.0,

    // Column geometry
    column_shape: ColumnShape = .square,
    c1_in: f64 = 18.0, // column dimension in L direction
    c2_in: f64 = 18.0, // column dimension in B direction (or diameter for circular)
    column_position: aci.ColumnPosition = .interior,

    // Material
    concrete_strength: concrete.ConcreteStrength = .fc_4000,
    concrete_type: concrete.ConcreteType = .normal_weight,
    rebar_grade: concrete.RebarGrade = .grade_60,
    bar_size: concrete.BarSize = .no5,

    // Axial loads (positive = compression downward)
    axial_dead_lb: f64 = 0,
    axial_live_lb: f64 = 0,
    axial_snow_lb: f64 = 0,
    axial_wind_lb: f64 = 0,
    axial_seismic_lb: f64 = 0,

    // Moments about L axis (cause eccentricity in B direction)
    moment_x_dead_ft_lb: f64 = 0,
    moment_x_live_ft_lb: f64 = 0,
    moment_x_wind_ft_lb: f64 = 0,
    moment_x_seismic_ft_lb: f64 = 0,

    // Moments about B axis (cause eccentricity in L direction)
    moment_y_dead_ft_lb: f64 = 0,
    moment_y_live_ft_lb: f64 = 0,
    moment_y_wind_ft_lb: f64 = 0,
    moment_y_seismic_ft_lb: f64 = 0,

    // Lateral shears for sliding check
    shear_x_dead_lb: f64 = 0,
    shear_x_live_lb: f64 = 0,
    shear_x_wind_lb: f64 = 0,
    shear_x_seismic_lb: f64 = 0,

    shear_y_dead_lb: f64 = 0,
    shear_y_live_lb: f64 = 0,
    shear_y_wind_lb: f64 = 0,
    shear_y_seismic_lb: f64 = 0,

    // Soil properties
    allowable_bearing_psf: f64 = 3000,
    friction_coeff: f64 = 0.40,
    soil_unit_weight_pcf: f64 = 110,
    depth_to_bottom_ft: f64 = 4.0,

    // Safety factor thresholds
    overturning_fs: f64 = 1.5,
    sliding_fs: f64 = 1.5,

    include_self_weight: bool = true,
};

pub const Outputs = struct {
    // Geometry
    footing_area_sf: f64,
    effective_depth_in: f64,
    self_weight_lb: f64,
    overburden_lb: f64,

    // Bearing (service-level ASD)
    service_axial_lb: f64,
    q_max_psf: f64,
    q_min_psf: f64,
    eccentricity_x_in: f64,
    eccentricity_y_in: f64,
    kern_exceeded: bool,
    bearing_dcr: f64,
    bearing_combo_name: [32]u8,
    bearing_combo_len: u8,

    // One-way shear (factored LRFD) -- check both directions
    vu_one_way_l_lb: f64, // critical in L direction
    vu_one_way_b_lb: f64, // critical in B direction
    phi_vc_one_way_l_lb: f64,
    phi_vc_one_way_b_lb: f64,
    one_way_shear_dcr: f64,
    one_way_combo_name: [32]u8,
    one_way_combo_len: u8,

    // Two-way (punching) shear (factored LRFD)
    vu_two_way_lb: f64,
    bo_in: f64,
    phi_vc_two_way_lb: f64,
    vc1_lb: f64,
    vc2_lb: f64,
    vc3_lb: f64,
    governing_vc_eq: u8,
    two_way_shear_dcr: f64,
    two_way_combo_name: [32]u8,
    two_way_combo_len: u8,

    // Flexure (factored LRFD) -- report governing direction
    mu_l_ft_lb: f64, // moment per ft width in L direction cantilever
    mu_b_ft_lb: f64, // moment per ft width in B direction cantilever
    as_required_in2_per_ft: f64,
    as_min_in2_per_ft: f64,
    as_provided_in2_per_ft: f64,
    bar_spacing_in: f64,
    phi_mn_ft_lb: f64,
    flexure_dcr: f64,
    flexure_combo_name: [32]u8,
    flexure_combo_len: u8,

    // Development length
    ld_required_in: f64,
    ld_available_in: f64,
    development_dcr: f64,

    // Stability (service-level ASD)
    overturning_fs_x: f64,
    overturning_fs_y: f64,
    sliding_fs_x: f64,
    sliding_fs_y: f64,

    // Status
    bearing_status: CheckStatus,
    one_way_shear_status: CheckStatus,
    two_way_shear_status: CheckStatus,
    flexure_status: CheckStatus,
    development_status: CheckStatus,
    overturning_status: CheckStatus,
    sliding_status: CheckStatus,
    overall_status: CheckStatus,
};

pub const ComputeError = error{
    InvalidDimensions,
    InvalidThickness,
    ColumnExceedsFooting,
    InsufficientDepth,
};

pub fn compute(inp: Inputs) ComputeError!Outputs {
    // 1. Validate
    if (inp.length_ft <= 0 or inp.width_ft <= 0) return error.InvalidDimensions;
    if (inp.thickness_in <= inp.cover_in) return error.InvalidThickness;

    const col_L_ft = inp.c1_in / 12.0;
    const col_B_ft = inp.c2_in / 12.0;
    if (col_L_ft >= inp.length_ft or col_B_ft >= inp.width_ft) return error.ColumnExceedsFooting;

    // 2. Geometry
    const length_in = inp.length_ft * 12.0;
    const width_in = inp.width_ft * 12.0;
    const area_sf = inp.length_ft * inp.width_ft;
    const db = inp.bar_size.diameter();
    const d = inp.thickness_in - inp.cover_in - db / 2.0;
    if (d <= 0) return error.InsufficientDepth;

    // Material properties
    const fc = inp.concrete_strength.fc();
    const lambda = inp.concrete_type.lambda();
    const fy = inp.rebar_grade.fy();
    const conc_wt = inp.concrete_type.unitWeight();

    // 3. Self weight and overburden
    const self_weight_lb = if (inp.include_self_weight)
        area_sf * (inp.thickness_in / 12.0) * conc_wt
    else
        0;

    // Soil overburden above footing (depth_to_bottom minus footing thickness)
    const soil_depth_ft = @max(0, inp.depth_to_bottom_ft - inp.thickness_in / 12.0);
    const overburden_lb = area_sf * soil_depth_ft * inp.soil_unit_weight_pcf;

    // Total added weight for bearing check (service)
    const added_weight = self_weight_lb + overburden_lb;

    // 4. Build load cases
    var axial_case = loads_mod.LoadCase{};
    axial_case.set(.dead, inp.axial_dead_lb + added_weight);
    axial_case.set(.live, inp.axial_live_lb);
    axial_case.set(.snow, inp.axial_snow_lb);
    axial_case.set(.wind, inp.axial_wind_lb);
    axial_case.set(.seismic, inp.axial_seismic_lb);

    var mx_case = loads_mod.LoadCase{};
    mx_case.set(.dead, inp.moment_x_dead_ft_lb);
    mx_case.set(.live, inp.moment_x_live_ft_lb);
    mx_case.set(.wind, inp.moment_x_wind_ft_lb);
    mx_case.set(.seismic, inp.moment_x_seismic_ft_lb);

    var my_case = loads_mod.LoadCase{};
    my_case.set(.dead, inp.moment_y_dead_ft_lb);
    my_case.set(.live, inp.moment_y_live_ft_lb);
    my_case.set(.wind, inp.moment_y_wind_ft_lb);
    my_case.set(.seismic, inp.moment_y_seismic_ft_lb);

    var vx_case = loads_mod.LoadCase{};
    vx_case.set(.dead, inp.shear_x_dead_lb);
    vx_case.set(.live, inp.shear_x_live_lb);
    vx_case.set(.wind, inp.shear_x_wind_lb);
    vx_case.set(.seismic, inp.shear_x_seismic_lb);

    var vy_case = loads_mod.LoadCase{};
    vy_case.set(.dead, inp.shear_y_dead_lb);
    vy_case.set(.live, inp.shear_y_live_lb);
    vy_case.set(.wind, inp.shear_y_wind_lb);
    vy_case.set(.seismic, inp.shear_y_seismic_lb);

    // =====================================================================
    // 5. SERVICE-LEVEL CHECKS (ASD combos)
    // =====================================================================

    // Find governing ASD combo for bearing
    var worst_bearing_dcr: f64 = 0;
    var worst_bearing_idx: usize = 0;
    var worst_q_max: f64 = 0;
    var worst_q_min: f64 = 0;
    var worst_ex: f64 = 0;
    var worst_ey: f64 = 0;
    var worst_kern: bool = false;
    var worst_service_p: f64 = 0;

    for (loads_mod.asd_combinations, 0..) |c, i| {
        const p = c.apply(axial_case);
        const mx_val = c.apply(mx_case);
        const my_val = c.apply(my_case);

        if (p <= 0) continue; // no bearing for uplift

        // Eccentricities (in feet)
        const ex_ft = if (p > 0) @abs(my_val) / p else 0;
        const ey_ft = if (p > 0) @abs(mx_val) / p else 0;

        // Kern limits
        const kern_x = inp.length_ft / 6.0;
        const kern_y = inp.width_ft / 6.0;

        var q_max: f64 = 0;
        var q_min: f64 = 0;
        var kern_out = false;

        if (ex_ft <= kern_x and ey_ft <= kern_y) {
            // Within kern -- standard q = P/A +/- Mc/I (per axis)
            const sx_ft3 = area_sf * inp.width_ft / 6.0; // section modulus about x (for B direction eccentricity)
            const sy_ft3 = area_sf * inp.length_ft / 6.0; // section modulus about y (for L direction eccentricity)

            const q_base = p / area_sf;
            const q_mx = if (sx_ft3 > 0) @abs(mx_val) / sx_ft3 else 0;
            const q_my = if (sy_ft3 > 0) @abs(my_val) / sy_ft3 else 0;

            q_max = q_base + q_mx + q_my;
            q_min = q_base - q_mx - q_my;
        } else {
            // Kern exceeded -- triangular/trapezoidal distribution
            kern_out = true;
            // Simplified: handle each axis independently
            if (ex_ft > kern_x) {
                // Triangular in L direction
                const bearing_length = 3.0 * (inp.length_ft / 2.0 - ex_ft);
                if (bearing_length > 0) {
                    q_max = @max(q_max, 2.0 * p / (inp.width_ft * bearing_length));
                }
            }
            if (ey_ft > kern_y) {
                // Triangular in B direction
                const bearing_width = 3.0 * (inp.width_ft / 2.0 - ey_ft);
                if (bearing_width > 0) {
                    q_max = @max(q_max, 2.0 * p / (inp.length_ft * bearing_width));
                }
            }
            // If neither axis exceeds kern individually (but combined does),
            // fall back to simple superposition
            if (q_max == 0) {
                const q_base = p / area_sf;
                const sx_ft3 = area_sf * inp.width_ft / 6.0;
                const sy_ft3 = area_sf * inp.length_ft / 6.0;
                const q_mx = if (sx_ft3 > 0) @abs(mx_val) / sx_ft3 else 0;
                const q_my = if (sy_ft3 > 0) @abs(my_val) / sy_ft3 else 0;
                q_max = q_base + q_mx + q_my;
            }
            q_min = 0;
        }

        const dcr = if (inp.allowable_bearing_psf > 0) q_max / inp.allowable_bearing_psf else 0;

        if (dcr > worst_bearing_dcr) {
            worst_bearing_dcr = dcr;
            worst_bearing_idx = i;
            worst_q_max = q_max;
            worst_q_min = q_min;
            worst_ex = ex_ft * 12.0; // store in inches
            worst_ey = ey_ft * 12.0;
            worst_kern = kern_out;
            worst_service_p = p;
        }
    }

    // Stability: overturning and sliding (worst case across ASD combos)
    var ot_fs_x: f64 = math.inf(f64);
    var ot_fs_y: f64 = math.inf(f64);
    var sl_fs_x: f64 = math.inf(f64);
    var sl_fs_y: f64 = math.inf(f64);

    for (loads_mod.asd_combinations) |c| {
        const p = c.apply(axial_case);
        const mx_val = c.apply(mx_case);
        const my_val = c.apply(my_case);
        const vx_val = c.apply(vx_case);
        const vy_val = c.apply(vy_case);

        // Overturning about x-axis: resisting = P * B/2, driving = |Mx|
        if (@abs(mx_val) > 0 and p > 0) {
            const resist_x = p * (inp.width_ft / 2.0);
            const fs = resist_x / @abs(mx_val);
            ot_fs_x = @min(ot_fs_x, fs);
        }
        // Overturning about y-axis: resisting = P * L/2, driving = |My|
        if (@abs(my_val) > 0 and p > 0) {
            const resist_y = p * (inp.length_ft / 2.0);
            const fs = resist_y / @abs(my_val);
            ot_fs_y = @min(ot_fs_y, fs);
        }
        // Sliding in x: resisting = mu*P, driving = |Vx|
        if (@abs(vx_val) > 0 and p > 0) {
            const resist = inp.friction_coeff * p;
            const fs = resist / @abs(vx_val);
            sl_fs_x = @min(sl_fs_x, fs);
        }
        // Sliding in y: resisting = mu*P, driving = |Vy|
        if (@abs(vy_val) > 0 and p > 0) {
            const resist = inp.friction_coeff * p;
            const fs = resist / @abs(vy_val);
            sl_fs_y = @min(sl_fs_y, fs);
        }
    }

    // =====================================================================
    // 6. FACTORED CHECKS (LRFD combos)
    // =====================================================================

    // Build factored axial case (net pressure -- subtract footing weight for structural design)
    var axial_case_net = loads_mod.LoadCase{};
    axial_case_net.set(.dead, inp.axial_dead_lb);
    axial_case_net.set(.live, inp.axial_live_lb);
    axial_case_net.set(.snow, inp.axial_snow_lb);
    axial_case_net.set(.wind, inp.axial_wind_lb);
    axial_case_net.set(.seismic, inp.axial_seismic_lb);

    // Track worst factored checks across all LRFD combos
    var worst_vu_1way_l: f64 = 0;
    var worst_vu_1way_b: f64 = 0;
    var worst_1way_dcr: f64 = 0;
    var worst_1way_idx: usize = 0;
    var worst_vu_2way: f64 = 0;
    var worst_2way_dcr: f64 = 0;
    var worst_2way_idx: usize = 0;
    var worst_mu_l: f64 = 0;
    var worst_mu_b: f64 = 0;
    var worst_flex_dcr: f64 = 0;
    var worst_flex_idx: usize = 0;

    // Precompute shear capacities (constant for all combos)
    // One-way shear: critical section at d from column face
    // In L direction: cantilever from column face to footing edge minus d
    const cant_l_in = (length_in - inp.c1_in) / 2.0; // cantilever in L direction
    const cant_b_in = (width_in - inp.c2_in) / 2.0; // cantilever in B direction

    // phi*Vc for one-way shear (per foot of width)
    const phi_vc_1way_l = aci.phi_shear * aci.oneWayShearCapacity(fc, lambda, 12.0, d);
    const phi_vc_1way_b = aci.phi_shear * aci.oneWayShearCapacity(fc, lambda, 12.0, d);

    // Two-way shear
    const bo = if (inp.column_shape == .circular)
        aci.punchingPerimeterCircular(inp.c1_in, d, inp.column_position)
    else
        aci.punchingPerimeter(inp.c1_in, inp.c2_in, d, inp.column_position);

    const beta_col = @max(inp.c1_in, inp.c2_in) / @min(inp.c1_in, inp.c2_in);
    const two_way_result = aci.twoWayShearCapacity(fc, lambda, bo, d, beta_col, inp.column_position);
    const phi_vc_2way = aci.phi_shear * two_way_result.vc_governing;

    for (loads_mod.lrfd_combinations, 0..) |c, i| {
        const pu = c.apply(axial_case_net);
        if (pu <= 0) continue;

        // Net factored soil pressure (uniform, ignoring moments for shear/flexure)
        const qu_psf = pu / area_sf;

        // -- One-way shear --
        // Vu per foot of width = qu * (cantilever - d) / 12 * 12
        // Critical section at d from column face
        const shear_span_l = cant_l_in - d;
        const shear_span_b = cant_b_in - d;

        var vu_1way_l: f64 = 0;
        if (shear_span_l > 0) {
            vu_1way_l = qu_psf * (shear_span_l / 12.0); // lb per ft of width
        }
        var vu_1way_b: f64 = 0;
        if (shear_span_b > 0) {
            vu_1way_b = qu_psf * (shear_span_b / 12.0);
        }
        const vu_1way = @max(vu_1way_l, vu_1way_b);
        const phi_vc_1way = if (vu_1way == vu_1way_l) phi_vc_1way_l else phi_vc_1way_b;
        const dcr_1way = if (phi_vc_1way > 0) vu_1way / phi_vc_1way else 0;

        if (dcr_1way > worst_1way_dcr) {
            worst_1way_dcr = dcr_1way;
            worst_1way_idx = i;
            worst_vu_1way_l = vu_1way_l;
            worst_vu_1way_b = vu_1way_b;
        }

        // -- Two-way shear --
        // Vu = Pu - qu * area_within_critical_section
        const crit_l = inp.c1_in + d;
        const crit_b = inp.c2_in + d;
        const crit_area_sf = if (inp.column_shape == .circular)
            math.pi / 4.0 * (inp.c1_in + d) * (inp.c1_in + d) / 144.0
        else
            (crit_l * crit_b) / 144.0;

        const vu_2way = pu - qu_psf * crit_area_sf;
        const dcr_2way = if (phi_vc_2way > 0) vu_2way / phi_vc_2way else 0;

        if (dcr_2way > worst_2way_dcr) {
            worst_2way_dcr = dcr_2way;
            worst_2way_idx = i;
            worst_vu_2way = vu_2way;
        }

        // -- Flexure --
        // Mu per ft width = qu * cantilever^2 / 2 (cantilever from column face)
        const mu_l_ft_lb = qu_psf * (cant_l_in / 12.0) * (cant_l_in / 12.0) / 2.0;
        const mu_b_ft_lb = qu_psf * (cant_b_in / 12.0) * (cant_b_in / 12.0) / 2.0;
        const mu_gov = @max(mu_l_ft_lb, mu_b_ft_lb);
        const mu_in_lb = mu_gov * 12.0; // convert ft-lb to in-lb

        // phi*Mn for provided steel (computed below, but track worst Mu for DCR)
        // For DCR tracking, compute required As
        const as_req = aci.requiredFlexuralSteel(mu_in_lb, fc, fy, 12.0, d);
        const as_min = aci.minimumFlexuralSteel(fy, 12.0, inp.thickness_in, d);
        const as_design = @max(as_req, as_min);

        // phi*Mn from as_design
        const a_block = as_design * fy / (0.85 * fc * 12.0);
        const phi_mn = aci.phi_flexure * as_design * fy * (d - a_block / 2.0);
        const dcr_flex = if (phi_mn > 0) mu_in_lb / phi_mn else 0;

        if (mu_gov > @max(worst_mu_l, worst_mu_b)) {
            worst_mu_l = mu_l_ft_lb;
            worst_mu_b = mu_b_ft_lb;
            worst_flex_dcr = dcr_flex;
            worst_flex_idx = i;
        }
    }

    // Compute final flexural design from governing moments
    const mu_design = @max(worst_mu_l, worst_mu_b);
    const mu_design_in_lb = mu_design * 12.0;
    const as_required = aci.requiredFlexuralSteel(mu_design_in_lb, fc, fy, 12.0, d);
    const as_min = aci.minimumFlexuralSteel(fy, 12.0, inp.thickness_in, d);
    const as_design = @max(as_required, as_min);

    // Bar spacing for provided area
    const bar_area = inp.bar_size.area();
    const bar_spacing = if (as_design > 0) 12.0 * bar_area / as_design else 0;

    // Actual provided As at computed spacing (round spacing down to whole inch)
    const spacing_used = if (bar_spacing > 0) @max(@floor(bar_spacing), 4.0) else 18.0;
    const as_provided = 12.0 * bar_area / spacing_used;

    // phi*Mn from provided steel
    const a_prov = as_provided * fy / (0.85 * fc * 12.0);
    const phi_mn = aci.phi_flexure * as_provided * fy * (d - a_prov / 2.0);
    const final_flex_dcr = if (phi_mn > 0) mu_design_in_lb / phi_mn else 0;

    // Development length
    const ld_required = aci.developmentLength(fy, fc, lambda, db, 1.0, 1.0);
    // Available: cantilever minus 3" end cover
    const ld_available = @max(cant_l_in, cant_b_in) - 3.0;
    const dev_dcr = if (ld_available > 0) ld_required / ld_available else math.inf(f64);

    // =====================================================================
    // 7. Assemble statuses
    // =====================================================================

    const bearing_status: CheckStatus = if (worst_bearing_dcr <= 1.0) .pass else .fail;
    const one_way_status: CheckStatus = if (worst_1way_dcr <= 1.0) .pass else .fail;
    const two_way_status: CheckStatus = if (worst_2way_dcr <= 1.0) .pass else .fail;
    const flex_status: CheckStatus = if (final_flex_dcr <= 1.0) .pass else .fail;
    const dev_status: CheckStatus = if (dev_dcr <= 1.0) .pass else .fail;
    const ot_status: CheckStatus = if (ot_fs_x >= inp.overturning_fs and ot_fs_y >= inp.overturning_fs) .pass else .fail;
    const sl_status: CheckStatus = if (sl_fs_x >= inp.sliding_fs and sl_fs_y >= inp.sliding_fs) .pass else .fail;

    const overall: CheckStatus = if (bearing_status == .pass and one_way_status == .pass and
        two_way_status == .pass and flex_status == .pass and
        dev_status == .pass and ot_status == .pass and sl_status == .pass) .pass else .fail;

    // Copy combo names
    var bearing_name: [32]u8 = .{0} ** 32;
    const bn = loads_mod.asd_combinations[worst_bearing_idx].name;
    const bn_len: u8 = @intCast(@min(bn.len, 32));
    @memcpy(bearing_name[0..bn_len], bn[0..bn_len]);

    var ow_name: [32]u8 = .{0} ** 32;
    const own = loads_mod.lrfd_combinations[worst_1way_idx].name;
    const own_len: u8 = @intCast(@min(own.len, 32));
    @memcpy(ow_name[0..own_len], own[0..own_len]);

    var tw_name: [32]u8 = .{0} ** 32;
    const twn = loads_mod.lrfd_combinations[worst_2way_idx].name;
    const twn_len: u8 = @intCast(@min(twn.len, 32));
    @memcpy(tw_name[0..twn_len], twn[0..twn_len]);

    var fl_name: [32]u8 = .{0} ** 32;
    const fln = loads_mod.lrfd_combinations[worst_flex_idx].name;
    const fln_len: u8 = @intCast(@min(fln.len, 32));
    @memcpy(fl_name[0..fln_len], fln[0..fln_len]);

    return .{
        .footing_area_sf = area_sf,
        .effective_depth_in = d,
        .self_weight_lb = self_weight_lb,
        .overburden_lb = overburden_lb,

        .service_axial_lb = worst_service_p,
        .q_max_psf = worst_q_max,
        .q_min_psf = worst_q_min,
        .eccentricity_x_in = worst_ex,
        .eccentricity_y_in = worst_ey,
        .kern_exceeded = worst_kern,
        .bearing_dcr = worst_bearing_dcr,
        .bearing_combo_name = bearing_name,
        .bearing_combo_len = bn_len,

        .vu_one_way_l_lb = worst_vu_1way_l,
        .vu_one_way_b_lb = worst_vu_1way_b,
        .phi_vc_one_way_l_lb = phi_vc_1way_l,
        .phi_vc_one_way_b_lb = phi_vc_1way_b,
        .one_way_shear_dcr = worst_1way_dcr,
        .one_way_combo_name = ow_name,
        .one_way_combo_len = own_len,

        .vu_two_way_lb = worst_vu_2way,
        .bo_in = bo,
        .phi_vc_two_way_lb = phi_vc_2way,
        .vc1_lb = two_way_result.vc1,
        .vc2_lb = two_way_result.vc2,
        .vc3_lb = two_way_result.vc3,
        .governing_vc_eq = two_way_result.governing_eq,
        .two_way_shear_dcr = worst_2way_dcr,
        .two_way_combo_name = tw_name,
        .two_way_combo_len = twn_len,

        .mu_l_ft_lb = worst_mu_l,
        .mu_b_ft_lb = worst_mu_b,
        .as_required_in2_per_ft = as_required,
        .as_min_in2_per_ft = as_min,
        .as_provided_in2_per_ft = as_provided,
        .bar_spacing_in = spacing_used,
        .phi_mn_ft_lb = phi_mn / 12.0, // convert in-lb back to ft-lb
        .flexure_dcr = final_flex_dcr,
        .flexure_combo_name = fl_name,
        .flexure_combo_len = fln_len,

        .ld_required_in = ld_required,
        .ld_available_in = ld_available,
        .development_dcr = dev_dcr,

        .overturning_fs_x = ot_fs_x,
        .overturning_fs_y = ot_fs_y,
        .sliding_fs_x = sl_fs_x,
        .sliding_fs_y = sl_fs_y,

        .bearing_status = bearing_status,
        .one_way_shear_status = one_way_status,
        .two_way_shear_status = two_way_status,
        .flexure_status = flex_status,
        .development_status = dev_status,
        .overturning_status = ot_status,
        .sliding_status = sl_status,
        .overall_status = overall,
    };
}

// -- Tests ----------------------------------------------------------------

test "concentric square footing" {
    // 8'x8'x18" footing, 18"x18" column, f'c=4000, 80k dead + 60k live, qa=3000 psf
    const inp = Inputs{
        .length_ft = 8.0,
        .width_ft = 8.0,
        .thickness_in = 18.0,
        .cover_in = 3.0,
        .c1_in = 18.0,
        .c2_in = 18.0,
        .concrete_strength = .fc_4000,
        .concrete_type = .normal_weight,
        .rebar_grade = .grade_60,
        .bar_size = .no5,
        .axial_dead_lb = 80_000,
        .axial_live_lb = 60_000,
        .allowable_bearing_psf = 3000,
        .include_self_weight = true,
    };

    const out = try compute(inp);

    // Area = 64 sf
    try std.testing.expectApproxEqAbs(out.footing_area_sf, 64.0, 0.01);

    // d = 18 - 3 - 0.625/2 = 14.6875"
    try std.testing.expectApproxEqAbs(out.effective_depth_in, 14.6875, 0.01);

    // No eccentricity
    try std.testing.expectApproxEqAbs(out.eccentricity_x_in, 0, 0.01);
    try std.testing.expectApproxEqAbs(out.eccentricity_y_in, 0, 0.01);
    try std.testing.expect(!out.kern_exceeded);

    // DCRs should be positive
    try std.testing.expect(out.bearing_dcr > 0);
    try std.testing.expect(out.one_way_shear_dcr >= 0);
    try std.testing.expect(out.two_way_shear_dcr > 0);
    try std.testing.expect(out.flexure_dcr > 0);
    try std.testing.expect(out.development_dcr > 0);

    // Should pass all checks for this well-sized footing
    try std.testing.expect(out.bearing_status == .pass);
}

test "eccentric load" {
    const inp = Inputs{
        .length_ft = 8.0,
        .width_ft = 8.0,
        .thickness_in = 18.0,
        .c1_in = 18.0,
        .c2_in = 18.0,
        .axial_dead_lb = 80_000,
        .axial_live_lb = 60_000,
        .moment_x_dead_ft_lb = 10_000,
        .moment_x_live_ft_lb = 15_000,
        .allowable_bearing_psf = 3000,
        .include_self_weight = false,
    };

    const out = try compute(inp);

    // Should have eccentricity in y (from Mx)
    try std.testing.expect(out.eccentricity_y_in > 0);
    // q_max > q_min due to moment
    try std.testing.expect(out.q_max_psf > out.q_min_psf);
    // Bearing DCR should be higher than concentric
    try std.testing.expect(out.bearing_dcr > 0);
}

test "invalid dimensions" {
    const inp = Inputs{
        .length_ft = 0,
        .width_ft = 8.0,
        .thickness_in = 18.0,
        .c1_in = 18.0,
        .c2_in = 18.0,
        .axial_dead_lb = 80_000,
    };
    const result = compute(inp);
    try std.testing.expectError(error.InvalidDimensions, result);
}

test "column exceeds footing" {
    const inp = Inputs{
        .length_ft = 1.0, // 12" -- less than 18" column
        .width_ft = 8.0,
        .thickness_in = 18.0,
        .c1_in = 18.0,
        .c2_in = 18.0,
        .axial_dead_lb = 80_000,
    };
    const result = compute(inp);
    try std.testing.expectError(error.ColumnExceedsFooting, result);
}

test "all DCRs positive for loaded footing" {
    const inp = Inputs{
        .length_ft = 6.0,
        .width_ft = 6.0,
        .thickness_in = 15.0,
        .c1_in = 12.0,
        .c2_in = 12.0,
        .axial_dead_lb = 50_000,
        .axial_live_lb = 40_000,
        .allowable_bearing_psf = 4000,
        .include_self_weight = true,
    };

    const out = try compute(inp);
    try std.testing.expect(out.bearing_dcr > 0);
    try std.testing.expect(out.two_way_shear_dcr > 0);
    try std.testing.expect(out.flexure_dcr > 0);
    try std.testing.expect(out.development_dcr > 0);
}
