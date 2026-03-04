const std = @import("std");
const math = std.math;
const loads = @import("../loads.zig");

// NDS 2018 Adjustment Factors for Sawn Lumber (Chapter 4)
//
// Fb' = Fb * CD * CM * Ct * CL * CF * Cfu * Ci * Cr   (NDS 2018 S4.3.1)
// Fv' = Fv * CD * CM * Ct * Ci
// E'  = E  * CM * Ct * Ci
// E'min = Emin * CM * Ct * Ci

// -- Moisture Condition ---------------------------------------------------

pub const MoistureCondition = enum {
    dry, // MC <= 19%
    wet, // MC > 19%
};

// NDS 2018 Table 4.3.3
pub fn cmFb(moisture: MoistureCondition) f64 {
    return switch (moisture) {
        .dry => 1.0,
        .wet => 0.85,
    };
}

pub fn cmFv(moisture: MoistureCondition) f64 {
    return switch (moisture) {
        .dry => 1.0,
        .wet => 0.97,
    };
}

pub fn cmFcPerp(moisture: MoistureCondition) f64 {
    return switch (moisture) {
        .dry => 1.0,
        .wet => 0.67,
    };
}

pub fn cmFc(moisture: MoistureCondition) f64 {
    return switch (moisture) {
        .dry => 1.0,
        .wet => 0.80,
    };
}

pub fn cmE(moisture: MoistureCondition) f64 {
    return switch (moisture) {
        .dry => 1.0,
        .wet => 0.90,
    };
}

// -- Temperature ----------------------------------------------------------

pub const TemperatureCondition = enum {
    normal, // T <= 100F
    elevated, // 100F < T <= 125F
    high, // 125F < T <= 150F
};

// NDS 2018 Table 2.3.3
pub fn ct(temp: TemperatureCondition, moisture: MoistureCondition) f64 {
    return switch (temp) {
        .normal => 1.0,
        .elevated => switch (moisture) {
            .dry => 0.8,
            .wet => 0.7,
        },
        .high => switch (moisture) {
            .dry => 0.7,
            .wet => 0.5,
        },
    };
}

// -- Incising -------------------------------------------------------------

pub const IncisingCondition = enum {
    none,
    incised,
};

// NDS 2018 Table 4.3.8
pub fn ciStrength(incising: IncisingCondition) f64 {
    return switch (incising) {
        .none => 1.0,
        .incised => 0.80,
    };
}

pub fn ciE(incising: IncisingCondition) f64 {
    return switch (incising) {
        .none => 1.0,
        .incised => 0.95,
    };
}

// -- Repetitive Member ----------------------------------------------------

pub const RepetitiveCondition = enum {
    single,
    repetitive, // 3+ members at <= 24" OC with load distribution
};

// NDS 2018 Section 4.3.9
pub fn cr(rep: RepetitiveCondition) f64 {
    return switch (rep) {
        .single => 1.0,
        .repetitive => 1.15,
    };
}

// -- Size Factor (CF) -----------------------------------------------------

// NDS 2018 Table 4A footnote -- for 2"-4" thick dimension lumber
pub fn cfFb(depth_in: f64) f64 {
    if (depth_in <= 3.5) return 1.5; // 2x4
    if (depth_in <= 5.5) return 1.3; // 2x6
    if (depth_in <= 7.25) return 1.2; // 2x8
    if (depth_in <= 9.25) return 1.1; // 2x10
    if (depth_in <= 11.25) return 1.0; // 2x12
    // d > 12": CF = (12/d)^(1/9)
    return math.pow(f64, 12.0 / depth_in, 1.0 / 9.0);
}

pub fn cfFt(depth_in: f64) f64 {
    if (depth_in <= 5.5) return 1.3;
    if (depth_in <= 7.25) return 1.2;
    if (depth_in <= 9.25) return 1.1;
    if (depth_in <= 11.25) return 1.0;
    return math.pow(f64, 12.0 / depth_in, 1.0 / 9.0);
}

pub fn cfFc(depth_in: f64) f64 {
    if (depth_in <= 5.5) return 1.15;
    if (depth_in <= 7.25) return 1.1;
    if (depth_in <= 9.25) return 1.05;
    if (depth_in <= 11.25) return 1.0;
    return math.pow(f64, 12.0 / depth_in, 1.0 / 9.0);
}

// -- Flat Use Factor (Cfu) ------------------------------------------------

// NDS 2018 Table 4.3.7 -- for 2"-4" thick lumber loaded on wide face
pub fn cfu(width_in: f64, flat_use: bool) f64 {
    if (!flat_use) return 1.0;
    if (width_in <= 1.5) return 1.0; // 2x nominal
    if (width_in <= 2.5) return 1.04; // 3x nominal
    if (width_in <= 3.5) return 1.10; // 4x nominal
    return 1.15;
}

// -- Beam Stability Factor (CL) ------------------------------------------

// NDS 2018 Section 3.3.3
pub fn cl(le_in: f64, b_in: f64, d_in: f64, fb_star: f64, e_min_prime: f64) f64 {
    if (le_in <= 0) return 1.0;

    // Slenderness ratio RB = sqrt(le * d / b^2)  -- NDS 3.3.3.5
    const rb = @sqrt(le_in * d_in / (b_in * b_in));

    // RB shall not exceed 50 (NDS 3.3.3.3)
    if (rb > 50.0) return 0.0;

    if (fb_star <= 0) return 0.0;

    // FbE = 1.20 * E'min / RB^2  -- NDS Eq. 3.3-6
    const f_be = 1.20 * e_min_prime / (rb * rb);

    // CL = (1 + FbE/Fb*) / 1.9 - sqrt[((1 + FbE/Fb*) / 1.9)^2 - (FbE/Fb*) / 0.95]
    const ratio = f_be / fb_star;
    const term1 = (1.0 + ratio) / 1.9;
    const c_l = term1 - @sqrt(term1 * term1 - ratio / 0.95);

    return @min(c_l, 1.0);
}

// Effective length le per NDS Table 3.3.3 for uniform load on simple span.
// lu = unbraced length in feet.
// For uniformly loaded simple span: le = 1.63*lu + 3*d  (when lu/d >= 7)
// For lu/d < 7: le = 2.06*lu
pub fn effectiveLength(lu_ft: f64, d_in: f64) f64 {
    const lu_in = lu_ft * 12.0;
    const ratio = lu_in / d_in;
    if (ratio < 7.0) {
        return 2.06 * lu_in;
    } else {
        return 1.63 * lu_in + 3.0 * d_in;
    }
}

// -- Column Stability Factor (Cp) ----------------------------------------

// NDS 2018 Section 3.7.1, Equation 3.7-1
// c = 0.8 for sawn lumber, 0.9 for glulam (NDS Table 3.7)
pub fn cp(fc_star: f64, e_min_prime: f64, le_in: f64, d_in: f64, c: f64) f64 {
    if (le_in <= 0) return 1.0;
    if (d_in <= 0) return 0.0;

    const le_d = le_in / d_in;

    // NDS 3.7.1.4: le/d shall not exceed 50
    if (le_d > 50.0) return 0.0;

    if (fc_star <= 0) return 0.0;

    // FcE = 0.822 * E'min / (le/d)^2  -- NDS Eq. 3.7-1
    const f_ce = 0.822 * e_min_prime / (le_d * le_d);

    // Cp = (1 + FcE/Fc*) / (2c) - sqrt[((1 + FcE/Fc*) / (2c))^2 - (FcE/Fc*) / c]
    const ratio = f_ce / fc_star;
    const term1 = (1.0 + ratio) / (2.0 * c);
    const cp_val = term1 - @sqrt(term1 * term1 - ratio / c);

    return @min(cp_val, 1.0);
}

// Critical buckling stress for column stability
// FcE = 0.822 * E'min / (le/d)^2  -- NDS Eq. 3.7-1
pub fn fce(e_min_prime: f64, le_in: f64, d_in: f64) f64 {
    if (le_in <= 0 or d_in <= 0) return 0.0;
    const le_d = le_in / d_in;
    return 0.822 * e_min_prime / (le_d * le_d);
}

// -- Column Adjusted Values -----------------------------------------------

pub const ColumnAdjustedValues = struct {
    fc_star: f64, // Fc with all factors except Cp
    fc_prime_x: f64, // Fc' for x-axis buckling (Fc* * Cp_x)
    fc_prime_y: f64, // Fc' for y-axis buckling (Fc* * Cp_y)
    fc_prime: f64, // Fc' governing (min of x and y)
    fc_perp_prime: f64, // Fc_perp' for bearing
    fb_prime: f64, // Fb' for bending
    fv_prime: f64, // Fv' for shear
    e_prime: f64,
    e_min_prime: f64,
    cp_x: f64, // Column stability factor, x-axis
    cp_y: f64, // Column stability factor, y-axis
    fce_x: f64, // Critical buckling stress, x-axis
    fce_y: f64, // Critical buckling stress, y-axis
    c_d: f64,
    c_m_fc: f64,
    c_m_fb: f64,
    c_m_fv: f64,
    c_m_e: f64,
    c_t: f64,
    c_f_fc: f64,
    c_f_fb: f64,
    c_i_strength: f64,
    c_i_e: f64,
};

pub const ColumnAdjustmentInputs = struct {
    load_duration: loads.LoadDuration = .normal,
    moisture: MoistureCondition = .dry,
    temperature: TemperatureCondition = .normal,
    incising: IncisingCondition = .none,
    le_x_in: f64 = 0, // effective length for x-axis buckling
    le_y_in: f64 = 0, // effective length for y-axis buckling
    buckling_c: f64 = 0.8, // 0.8 sawn, 0.9 glulam
};

pub fn columnAdjustedValues(
    fc_ref: f64,
    fc_perp_ref: f64,
    fb_ref: f64,
    fv_ref: f64,
    e_ref: f64,
    e_min_ref: f64,
    width_in: f64,
    depth_in: f64,
    inputs: ColumnAdjustmentInputs,
) ColumnAdjustedValues {
    const c_d = inputs.load_duration.factor();
    const c_m_fc_val = cmFc(inputs.moisture);
    const c_m_fb_val = cmFb(inputs.moisture);
    const c_m_fv_val = cmFv(inputs.moisture);
    const c_m_e_val = cmE(inputs.moisture);
    const c_m_fc_perp_val = cmFcPerp(inputs.moisture);
    const c_t_val = ct(inputs.temperature, inputs.moisture);
    const c_f_fc_val = cfFc(depth_in);
    const c_f_fb_val = cfFb(depth_in);
    const c_i_str = ciStrength(inputs.incising);
    const c_i_e_val = ciE(inputs.incising);

    // E' and E'min
    const e_prime = e_ref * c_m_e_val * c_t_val * c_i_e_val;
    const e_min_prime = e_min_ref * c_m_e_val * c_t_val * c_i_e_val;

    // Fc* = Fc * CD * CM * Ct * CF * Ci  (all factors except Cp)
    const fc_star = fc_ref * c_d * c_m_fc_val * c_t_val * c_f_fc_val * c_i_str;

    // Column stability factors for each axis
    // x-axis buckling: column buckles about x-axis, dimension is depth (d)
    const fce_x_val = fce(e_min_prime, inputs.le_x_in, depth_in);
    const cp_x_val = cp(fc_star, e_min_prime, inputs.le_x_in, depth_in, inputs.buckling_c);
    // y-axis buckling: column buckles about y-axis, dimension is width (b)
    const fce_y_val = fce(e_min_prime, inputs.le_y_in, width_in);
    const cp_y_val = cp(fc_star, e_min_prime, inputs.le_y_in, width_in, inputs.buckling_c);

    const fc_prime_x = fc_star * cp_x_val;
    const fc_prime_y = fc_star * cp_y_val;
    const fc_prime = @min(fc_prime_x, fc_prime_y);

    // Fc_perp' = Fc_perp * CM * Ct * Ci
    const fc_perp_prime = fc_perp_ref * c_m_fc_perp_val * c_t_val * c_i_str;

    // Fb' = Fb * CD * CM * Ct * CF * Ci  (CL=1.0 for columns, no Cr, no Cfu)
    const fb_prime = fb_ref * c_d * c_m_fb_val * c_t_val * c_f_fb_val * c_i_str;

    // Fv' = Fv * CD * CM * Ct * Ci
    const fv_prime = fv_ref * c_d * c_m_fv_val * c_t_val * c_i_str;

    return .{
        .fc_star = fc_star,
        .fc_prime_x = fc_prime_x,
        .fc_prime_y = fc_prime_y,
        .fc_prime = fc_prime,
        .fc_perp_prime = fc_perp_prime,
        .fb_prime = fb_prime,
        .fv_prime = fv_prime,
        .e_prime = e_prime,
        .e_min_prime = e_min_prime,
        .cp_x = cp_x_val,
        .cp_y = cp_y_val,
        .fce_x = fce_x_val,
        .fce_y = fce_y_val,
        .c_d = c_d,
        .c_m_fc = c_m_fc_val,
        .c_m_fb = c_m_fb_val,
        .c_m_fv = c_m_fv_val,
        .c_m_e = c_m_e_val,
        .c_t = c_t_val,
        .c_f_fc = c_f_fc_val,
        .c_f_fb = c_f_fb_val,
        .c_i_strength = c_i_str,
        .c_i_e = c_i_e_val,
    };
}

// -- Adjustment Input Bundle ----------------------------------------------

pub const AdjustmentInputs = struct {
    load_duration: loads.LoadDuration = .normal,
    moisture: MoistureCondition = .dry,
    temperature: TemperatureCondition = .normal,
    incising: IncisingCondition = .none,
    repetitive: RepetitiveCondition = .single,
    flat_use: bool = false,
    compression_edge_braced: bool = true,
    unbraced_length_ft: f64 = 0,
};

pub const AdjustedValues = struct {
    fb_prime: f64,
    fv_prime: f64,
    e_prime: f64,
    e_min_prime: f64,

    // Individual factor values for audit trail
    c_d: f64,
    c_m_fb: f64,
    c_m_fv: f64,
    c_m_e: f64,
    c_t: f64,
    c_f: f64,
    c_fu: f64,
    c_i_strength: f64,
    c_i_e: f64,
    c_r: f64,
    c_l: f64,
};

pub fn adjustedValues(
    fb_ref: f64,
    fv_ref: f64,
    e_ref: f64,
    e_min_ref: f64,
    width_in: f64,
    depth_in: f64,
    inputs: AdjustmentInputs,
) AdjustedValues {
    const c_d = inputs.load_duration.factor();
    const c_m_fb_val = cmFb(inputs.moisture);
    const c_m_fv_val = cmFv(inputs.moisture);
    const c_m_e_val = cmE(inputs.moisture);
    const c_t_val = ct(inputs.temperature, inputs.moisture);
    const c_f_val = cfFb(depth_in);
    const c_fu_val = cfu(width_in, inputs.flat_use);
    const c_i_str = ciStrength(inputs.incising);
    const c_i_e_val = ciE(inputs.incising);
    const c_r_val = cr(inputs.repetitive);

    // E' and E'min (no CD, CF, CL, Cfu, Cr)
    const e_prime = e_ref * c_m_e_val * c_t_val * c_i_e_val;
    const e_min_prime = e_min_ref * c_m_e_val * c_t_val * c_i_e_val;

    // CL calculation
    var c_l_val: f64 = 1.0;
    if (!inputs.compression_edge_braced and inputs.unbraced_length_ft > 0) {
        const le = effectiveLength(inputs.unbraced_length_ft, depth_in);
        // Fb* = Fb * CD * CM * Ct * CF * Cfu * Ci * Cr (all except CL)
        const fb_star = fb_ref * c_d * c_m_fb_val * c_t_val * c_f_val * c_fu_val * c_i_str * c_r_val;
        c_l_val = cl(le, width_in, depth_in, fb_star, e_min_prime);
    }

    // Fb' = Fb * CD * CM * Ct * CL * CF * Cfu * Ci * Cr  (NDS 2018 S4.3.1)
    const fb_prime = fb_ref * c_d * c_m_fb_val * c_t_val * c_l_val * c_f_val * c_fu_val * c_i_str * c_r_val;

    // Fv' = Fv * CD * CM * Ct * Ci
    const fv_prime = fv_ref * c_d * c_m_fv_val * c_t_val * c_i_str;

    return .{
        .fb_prime = fb_prime,
        .fv_prime = fv_prime,
        .e_prime = e_prime,
        .e_min_prime = e_min_prime,
        .c_d = c_d,
        .c_m_fb = c_m_fb_val,
        .c_m_fv = c_m_fv_val,
        .c_m_e = c_m_e_val,
        .c_t = c_t_val,
        .c_f = c_f_val,
        .c_fu = c_fu_val,
        .c_i_strength = c_i_str,
        .c_i_e = c_i_e_val,
        .c_r = c_r_val,
        .c_l = c_l_val,
    };
}

// -- Tests ----------------------------------------------------------------

test "CD values" {
    try std.testing.expectApproxEqAbs(loads.LoadDuration.permanent.factor(), 0.9, 0.001);
    try std.testing.expectApproxEqAbs(loads.LoadDuration.normal.factor(), 1.0, 0.001);
    try std.testing.expectApproxEqAbs(loads.LoadDuration.snow.factor(), 1.15, 0.001);
    try std.testing.expectApproxEqAbs(loads.LoadDuration.construction.factor(), 1.25, 0.001);
    try std.testing.expectApproxEqAbs(loads.LoadDuration.wind_seismic.factor(), 1.6, 0.001);
    try std.testing.expectApproxEqAbs(loads.LoadDuration.impact.factor(), 2.0, 0.001);
}

test "CM values" {
    try std.testing.expectApproxEqAbs(cmFb(.dry), 1.0, 0.001);
    try std.testing.expectApproxEqAbs(cmFb(.wet), 0.85, 0.001);
    try std.testing.expectApproxEqAbs(cmFv(.wet), 0.97, 0.001);
    try std.testing.expectApproxEqAbs(cmFcPerp(.wet), 0.67, 0.001);
    try std.testing.expectApproxEqAbs(cmFc(.wet), 0.80, 0.001);
    try std.testing.expectApproxEqAbs(cmE(.wet), 0.90, 0.001);
}

test "CF for 2x10 and formula for large depths" {
    try std.testing.expectApproxEqAbs(cfFb(9.25), 1.1, 0.001);
    try std.testing.expectApproxEqAbs(cfFb(11.25), 1.0, 0.001);
    const expected = math.pow(f64, 12.0 / 15.0, 1.0 / 9.0);
    try std.testing.expectApproxEqAbs(cfFb(15.0), expected, 0.001);
}

test "CL for known slenderness" {
    // 12' unbraced, 1.5" x 9.25" beam, DF-L No.2
    const le = effectiveLength(12.0, 9.25);
    const fb_star = 900.0 * 1.0 * 1.1; // Fb * CD * CF
    const e_min_prime: f64 = 580_000.0;
    const c_l = cl(le, 1.5, 9.25, fb_star, e_min_prime);
    try std.testing.expect(c_l > 0.0);
    try std.testing.expect(c_l < 1.0);
}

test "CL = 1.0 when braced" {
    const adj = adjustedValues(900, 180, 1_600_000, 580_000, 1.5, 9.25, .{});
    try std.testing.expectApproxEqAbs(adj.c_l, 1.0, 0.001);
}

test "adjusted Fb with snow + repetitive" {
    const adj = adjustedValues(900, 180, 1_600_000, 580_000, 1.5, 9.25, .{
        .load_duration = .snow,
        .repetitive = .repetitive,
    });
    // Fb' = 900 * 1.15 * 1.0 * 1.0 * 1.0 * 1.1 * 1.0 * 1.0 * 1.15 = 1309.5
    // (CD=1.15, CM=1.0, Ct=1.0, CL=1.0, CF=1.1, Cfu=1.0, Ci=1.0, Cr=1.15)
    try std.testing.expectApproxEqRel(adj.fb_prime, 1309.275, 0.01);
}

test "Cp short column approaches 1.0" {
    // Very short column: Cp should be close to 1.0
    const fc_star: f64 = 1350.0 * 1.15; // Fc * CF for 6x6
    const e_min_prime: f64 = 580_000.0;
    const le_in: f64 = 12.0; // 1 foot
    const d_in: f64 = 5.5;
    const cp_val = cp(fc_star, e_min_prime, le_in, d_in, 0.8);
    try std.testing.expect(cp_val > 0.99);
}

test "Cp 6x6 DF-L No.2 at 10ft" {
    // 6x6 DF-L No.2: Fc=1350, Emin=580000, d=5.5
    const fc_star: f64 = 1350.0 * 1.0 * 1.15; // Fc * CD(normal) * CF(6x6)
    const e_min_prime: f64 = 580_000.0;
    const le_in: f64 = 10.0 * 12.0; // 10 ft
    const d_in: f64 = 5.5;
    const cp_val = cp(fc_star, e_min_prime, le_in, d_in, 0.8);
    // le/d = 120/5.5 = 21.8, moderate slenderness
    try std.testing.expect(cp_val > 0.2);
    try std.testing.expect(cp_val < 0.8);
}

test "Cp returns 0 for le/d > 50" {
    const cp_val = cp(1000.0, 580_000.0, 300.0, 5.5, 0.8);
    // le/d = 300/5.5 = 54.5 > 50
    try std.testing.expectApproxEqAbs(cp_val, 0.0, 0.001);
}

test "columnAdjustedValues basic" {
    // 6x6 DF-L No.2, 10' height
    const adj = columnAdjustedValues(
        1350, // fc
        625, // fc_perp
        900, // fb
        180, // fv
        1_600_000, // e
        580_000, // e_min
        5.5, // width
        5.5, // depth
        .{
            .le_x_in = 120.0,
            .le_y_in = 120.0,
            .buckling_c = 0.8,
        },
    );
    // Both axes equal for square section
    try std.testing.expectApproxEqAbs(adj.cp_x, adj.cp_y, 0.001);
    try std.testing.expect(adj.fc_prime > 0);
    try std.testing.expect(adj.fc_prime < adj.fc_star);
    try std.testing.expect(adj.fb_prime > 0);
    try std.testing.expect(adj.fv_prime > 0);
}

test "adjusted Fv with snow" {
    const adj = adjustedValues(900, 180, 1_600_000, 580_000, 1.5, 9.25, .{
        .load_duration = .snow,
    });
    // Fv' = 180 * 1.15 * 1.0 * 1.0 * 1.0 = 207
    try std.testing.expectApproxEqAbs(adj.fv_prime, 207.0, 0.1);
}
