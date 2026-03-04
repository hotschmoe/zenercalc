const std = @import("std");
const math = std.math;

// ACI 318-19 Provisions for Spread Footings

// -- Strength Reduction Factors (Table 21.2.1) ----------------------------

pub const phi_shear: f64 = 0.75;
pub const phi_flexure: f64 = 0.90;

// -- Column Position (for punching shear alpha_s) -------------------------

pub const ColumnPosition = enum {
    interior,
    edge,
    corner,

    // ACI 318-19 Table 22.6.5.2
    pub fn alphaS(self: ColumnPosition) f64 {
        return switch (self) {
            .interior => 40.0,
            .edge => 30.0,
            .corner => 20.0,
        };
    }
};

// -- One-Way Shear (ACI 318-19 Table 22.5.5.1) ---------------------------

// Vc = 2 * lambda * sqrt(f'c) * bw * d  (simplified method, no Vu/Mu term)
// All inputs in psi and inches; returns Vc in lbs
pub fn oneWayShearCapacity(fc: f64, lambda: f64, bw: f64, d: f64) f64 {
    return 2.0 * lambda * @sqrt(fc) * bw * d;
}

// -- Two-Way (Punching) Shear (ACI 318-19 Table 22.6.5.2) ----------------

pub const TwoWayShearResult = struct {
    vc1: f64, // Eq. (a): 4*lambda*sqrt(f'c)
    vc2: f64, // Eq. (b): (2 + 4/beta)*lambda*sqrt(f'c)
    vc3: f64, // Eq. (c): (2 + alpha_s*d/bo)*lambda*sqrt(f'c)
    vc_governing: f64, // minimum of the three
    governing_eq: u8, // 1, 2, or 3
};

// Returns Vc in lbs. beta = long/short column dimension ratio.
// bo = punching perimeter (in), d = effective depth (in)
pub fn twoWayShearCapacity(fc: f64, lambda: f64, bo: f64, d: f64, beta: f64, position: ColumnPosition) TwoWayShearResult {
    const sqrt_fc = @sqrt(fc);
    const alpha_s = position.alphaS();

    // (a) Vc = 4*lambda*sqrt(f'c)*bo*d
    const vc1_stress = 4.0 * lambda * sqrt_fc;
    const vc1 = vc1_stress * bo * d;

    // (b) Vc = (2 + 4/beta)*lambda*sqrt(f'c)*bo*d
    const vc2_stress = (2.0 + 4.0 / beta) * lambda * sqrt_fc;
    const vc2 = vc2_stress * bo * d;

    // (c) Vc = (2 + alpha_s*d/bo)*lambda*sqrt(f'c)*bo*d
    const vc3_stress = (2.0 + alpha_s * d / bo) * lambda * sqrt_fc;
    const vc3 = vc3_stress * bo * d;

    const min12 = @min(vc1, vc2);
    const vc_gov = @min(min12, vc3);

    var gov_eq: u8 = 1;
    if (vc_gov == vc2) gov_eq = 2;
    if (vc_gov == vc3) gov_eq = 3;

    return .{
        .vc1 = vc1,
        .vc2 = vc2,
        .vc3 = vc3,
        .vc_governing = vc_gov,
        .governing_eq = gov_eq,
    };
}

// -- Punching Perimeter (ACI 318-19 Section 22.6.4.1) --------------------

// Rectangular column: bo = 2*(c1 + d) + 2*(c2 + d) for interior
pub fn punchingPerimeter(c1: f64, c2: f64, d: f64, position: ColumnPosition) f64 {
    return switch (position) {
        .interior => 2.0 * (c1 + d) + 2.0 * (c2 + d),
        .edge => 2.0 * (c1 + d / 2.0) + (c2 + d),
        .corner => (c1 + d / 2.0) + (c2 + d / 2.0),
    };
}

// Circular column: bo = pi * (D + d) for interior
pub fn punchingPerimeterCircular(col_diameter: f64, d: f64, position: ColumnPosition) f64 {
    return switch (position) {
        .interior => math.pi * (col_diameter + d),
        .edge => math.pi * (col_diameter + d) / 2.0 + (col_diameter + d),
        .corner => math.pi * (col_diameter + d) / 4.0 + (col_diameter + d) / 2.0,
    };
}

// -- Flexural Reinforcement (ACI 318-19 Section 22.2) ---------------------

// Solve for required As from Mu using rectangular stress block:
//   Mu = phi * As * fy * (d - a/2)   where a = As*fy / (0.85*f'c*b)
// Rearranging to quadratic in As:
//   As^2 * (fy^2 / (1.7*f'c*b)) - As * (fy*d) + Mu/phi = 0
// Returns As in in2. Mu in lb-in, fc/fy in psi, b/d in inches.
pub fn requiredFlexuralSteel(mu: f64, fc: f64, fy: f64, b: f64, d: f64) f64 {
    if (mu <= 0) return 0;

    const phi = phi_flexure;
    const a_coeff = fy * fy / (1.7 * fc * b);
    const b_coeff = fy * d;
    const c_coeff = mu / phi;

    const discriminant = b_coeff * b_coeff - 4.0 * a_coeff * c_coeff;
    if (discriminant < 0) return -1.0; // section insufficient

    // Take smaller root (less steel)
    return (b_coeff - @sqrt(discriminant)) / (2.0 * a_coeff);
}

// -- Minimum Flexural Steel (ACI 318-19 Section 7.6.1.1 for footings) ----

// As_min = 0.0018 * b * h  (for fy = 60 ksi, Grade 60)
// General: As_min = max(0.0018*Ag, 200*bw*d/fy) per ACI 7.6.1.1 / 9.6.1.2
pub fn minimumFlexuralSteel(fy: f64, b: f64, h: f64, d: f64) f64 {
    const as_temp = 0.0018 * b * h;
    const as_flex = 200.0 * b * d / fy;
    return @max(as_temp, as_flex);
}

// -- Development Length (ACI 318-19 Section 25.4.2.3 simplified) ----------

// ld = (fy * psi_t * psi_e / (25 * lambda * sqrt(f'c))) * db
// Simplified per Table 25.4.2.3 for #6 and smaller bars with clear spacing >= db
// Returns ld in inches.
pub fn developmentLength(fy: f64, fc: f64, lambda: f64, db: f64, psi_t: f64, psi_e: f64) f64 {
    const denom = 25.0 * lambda * @sqrt(fc);
    if (denom <= 0) return 0;
    const ld = (fy * psi_t * psi_e / denom) * db;
    return @max(ld, 12.0); // ACI 25.4.2.1: minimum 12 inches
}

// -- Tests ----------------------------------------------------------------

test "one-way shear capacity" {
    // 12" wide strip, d=15.5", f'c=4000, NW concrete
    // Vc = 2 * 1.0 * sqrt(4000) * 12 * 15.5 = 2*63.246*12*15.5 = 23,527 lb
    const vc = oneWayShearCapacity(4000, 1.0, 12.0, 15.5);
    try std.testing.expectApproxEqAbs(vc, 23527.0, 5.0);
}

test "two-way shear interior square column" {
    // 18x18 column, d=15.5, f'c=4000, NW, interior
    // bo = 2*(18+15.5) + 2*(18+15.5) = 134"
    const bo = punchingPerimeter(18, 18, 15.5, .interior);
    try std.testing.expectApproxEqAbs(bo, 134.0, 0.01);

    const result = twoWayShearCapacity(4000, 1.0, bo, 15.5, 1.0, .interior);
    // Eq (a): 4*1.0*63.246*134*15.5 = 525,455 lb (approx)
    try std.testing.expect(result.vc1 > 500_000);
    // beta=1.0 -> Eq (b): (2+4/1)*63.246*134*15.5 = 6*63.246*... > Eq(a), so (a) governs
    try std.testing.expect(result.vc_governing <= result.vc1);
    try std.testing.expect(result.vc_governing <= result.vc2);
    try std.testing.expect(result.vc_governing <= result.vc3);
}

test "required flexural steel" {
    // Mu = 50,000 ft-lb = 600,000 in-lb, f'c=4000, fy=60000, b=12, d=15.5
    const as = requiredFlexuralSteel(600_000, 4000, 60_000, 12.0, 15.5);
    try std.testing.expect(as > 0);
    try std.testing.expect(as < 3.0); // sanity: should be reasonable
}

test "minimum flexural steel" {
    // b=12, h=18, d=15.5, fy=60000
    const as_min = minimumFlexuralSteel(60_000, 12.0, 18.0, 15.5);
    // 0.0018*12*18 = 0.3888
    // 200*12*15.5/60000 = 0.62
    try std.testing.expectApproxEqAbs(as_min, 0.62, 0.01);
}

test "development length" {
    // #5 bar, fy=60000, f'c=4000, NW, bottom bar (psi_t=1.0), uncoated (psi_e=1.0)
    const db = 0.625;
    const ld = developmentLength(60_000, 4000, 1.0, db, 1.0, 1.0);
    // ld = (60000 * 1.0 * 1.0 / (25 * 1.0 * 63.246)) * 0.625 = 23.7"
    try std.testing.expect(ld > 20.0);
    try std.testing.expect(ld < 30.0);
}

test "development length minimum 12 inches" {
    // Small bar, low fy -> computed ld < 12, should return 12
    const ld = developmentLength(40_000, 6000, 1.0, 0.375, 1.0, 1.0);
    try std.testing.expect(ld >= 12.0);
}

test "punching perimeter edge" {
    const bo = punchingPerimeter(18, 18, 15.5, .edge);
    // edge: 2*(18+7.75) + (18+15.5) = 51.5 + 33.5 = 85.0
    try std.testing.expectApproxEqAbs(bo, 85.0, 0.01);
}
