const std = @import("std");
const math = std.math;

// -- Section Properties ---------------------------------------------------

pub const RectSection = struct {
    b: f64, // width (in)
    d: f64, // depth (in)

    pub fn area(self: RectSection) f64 {
        return self.b * self.d;
    }

    pub fn sectionModulus(self: RectSection) f64 {
        return self.b * self.d * self.d / 6.0;
    }

    pub fn momentOfInertia(self: RectSection) f64 {
        return self.b * self.d * self.d * self.d / 12.0;
    }
};

// -- Load Types -----------------------------------------------------------

pub const diagram_points: usize = 51;

pub const Load = union(enum) {
    uniform_full: struct { w_plf: f64 },
    point: struct { p_lb: f64, a_ft: f64 },
    uniform_partial: struct { w_plf: f64, a_ft: f64, b_ft: f64 },

    // Simple beam reactions, shear, moment, deflection for each load type.
    // All assume simply-supported beam of span L_ft.

    pub fn reactionLeft(self: Load, span_ft: f64) f64 {
        return switch (self) {
            .uniform_full => |u| u.w_plf * span_ft / 2.0,
            .point => |p| p.p_lb * (span_ft - p.a_ft) / span_ft,
            .uniform_partial => |u| blk: {
                // Partial UDL from a to b: R_L = w*(b-a)*(L - (a+b)/2) / L
                const w = u.w_plf;
                const a = u.a_ft;
                const b = u.b_ft;
                const l = span_ft;
                break :blk w * (b - a) * (l - (a + b) / 2.0) / l;
            },
        };
    }

    pub fn reactionRight(self: Load, span_ft: f64) f64 {
        return switch (self) {
            .uniform_full => |u| u.w_plf * span_ft / 2.0,
            .point => |p| p.p_lb * p.a_ft / span_ft,
            .uniform_partial => |u| blk: {
                const w = u.w_plf;
                const a = u.a_ft;
                const b = u.b_ft;
                const l = span_ft;
                break :blk w * (b - a) * (a + b) / (2.0 * l);
            },
        };
    }

    pub fn shearAt(self: Load, x_ft: f64, span_ft: f64) f64 {
        const rl = self.reactionLeft(span_ft);
        return switch (self) {
            .uniform_full => |u| rl - u.w_plf * x_ft,
            .point => |p| if (x_ft < p.a_ft) rl else rl - p.p_lb,
            .uniform_partial => |u| blk: {
                if (x_ft <= u.a_ft) {
                    break :blk rl;
                } else if (x_ft <= u.b_ft) {
                    break :blk rl - u.w_plf * (x_ft - u.a_ft);
                } else {
                    break :blk rl - u.w_plf * (u.b_ft - u.a_ft);
                }
            },
        };
    }

    pub fn momentAt(self: Load, x_ft: f64, span_ft: f64) f64 {
        const rl = self.reactionLeft(span_ft);
        return switch (self) {
            .uniform_full => |u| rl * x_ft - u.w_plf * x_ft * x_ft / 2.0,
            .point => |p| blk: {
                if (x_ft <= p.a_ft) {
                    break :blk rl * x_ft;
                } else {
                    break :blk rl * x_ft - p.p_lb * (x_ft - p.a_ft);
                }
            },
            .uniform_partial => |u| blk: {
                if (x_ft <= u.a_ft) {
                    break :blk rl * x_ft;
                } else if (x_ft <= u.b_ft) {
                    const dx = x_ft - u.a_ft;
                    break :blk rl * x_ft - u.w_plf * dx * dx / 2.0;
                } else {
                    const loaded_len = u.b_ft - u.a_ft;
                    const centroid = u.a_ft + loaded_len / 2.0;
                    break :blk rl * x_ft - u.w_plf * loaded_len * (x_ft - centroid);
                }
            },
        };
    }

    // Deflection at point x for simply-supported beam.
    // Units: x_ft, span_ft in feet; E in psi; I in in^4.
    // Returns deflection in inches (positive = downward).
    pub fn deflectionAt(self: Load, x_ft: f64, span_ft: f64, e_psi: f64, i_in4: f64) f64 {
        const l = span_ft * 12.0; // convert to inches
        const x = x_ft * 12.0;
        const ei = e_psi * i_in4;

        if (ei == 0.0) return 0.0;

        return switch (self) {
            .uniform_full => |u| blk: {
                // delta = w*x*(L^3 - 2*L*x^2 + x^3) / (24*E*I)
                // w in plf -> w/12 in lb/in
                const w = u.w_plf / 12.0;
                break :blk w * x * (l * l * l - 2.0 * l * x * x + x * x * x) / (24.0 * ei);
            },
            .point => |p| blk: {
                const a = p.a_ft * 12.0;
                const b = l - a;
                if (x <= a) {
                    // delta = P*b*x*(L^2 - b^2 - x^2) / (6*L*E*I)
                    break :blk p.p_lb * b * x * (l * l - b * b - x * x) / (6.0 * l * ei);
                } else {
                    // delta = P*a*(L-x)*(2*L*x - a^2 - x^2) / (6*L*E*I)
                    const lmx = l - x;
                    break :blk p.p_lb * a * lmx * (2.0 * l * x - a * a - x * x) / (6.0 * l * ei);
                }
            },
            .uniform_partial => |u| blk: {
                // Approximate partial uniform as 20 sub-point-loads
                const n: usize = 20;
                const loaded_len = u.b_ft - u.a_ft;
                const sub_p = u.w_plf * loaded_len / @as(f64, @floatFromInt(n));
                var delta: f64 = 0.0;
                for (0..n) |i| {
                    const frac = (@as(f64, @floatFromInt(i)) + 0.5) / @as(f64, @floatFromInt(n));
                    const sub_a_ft = u.a_ft + loaded_len * frac;
                    const sub_load = Load{ .point = .{ .p_lb = sub_p, .a_ft = sub_a_ft } };
                    delta += sub_load.deflectionAt(x_ft, span_ft, e_psi, i_in4);
                }
                break :blk delta;
            },
        };
    }
};

// -- Beam Analysis --------------------------------------------------------

pub const DiagramPoint = struct {
    x_ft: f64,
    moment_ft_lb: f64,
    shear_lb: f64,
    deflection_in: f64,
};

pub const BeamAnalysisResult = struct {
    max_moment_ft_lb: f64,
    max_moment_pos_ft: f64,
    max_shear_lb: f64,
    max_shear_pos_ft: f64,
    max_deflection_in: f64,
    max_deflection_pos_ft: f64,
    reaction_left_lb: f64,
    reaction_right_lb: f64,
    diagram: [diagram_points]DiagramPoint,
};

pub fn analyzeSimpleBeam(
    span_ft: f64,
    loads: []const Load,
    e_psi: f64,
    i_in4: f64,
) BeamAnalysisResult {
    var result = BeamAnalysisResult{
        .max_moment_ft_lb = 0,
        .max_moment_pos_ft = 0,
        .max_shear_lb = 0,
        .max_shear_pos_ft = 0,
        .max_deflection_in = 0,
        .max_deflection_pos_ft = 0,
        .reaction_left_lb = 0,
        .reaction_right_lb = 0,
        .diagram = undefined,
    };

    // Sum reactions
    for (loads) |load| {
        result.reaction_left_lb += load.reactionLeft(span_ft);
        result.reaction_right_lb += load.reactionRight(span_ft);
    }

    // Sweep diagram points
    const n = diagram_points;
    for (0..n) |i| {
        const x_ft = span_ft * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(n - 1));

        var moment: f64 = 0;
        var shear: f64 = 0;
        var deflection: f64 = 0;

        for (loads) |load| {
            moment += load.momentAt(x_ft, span_ft);
            shear += load.shearAt(x_ft, span_ft);
            deflection += load.deflectionAt(x_ft, span_ft, e_psi, i_in4);
        }

        result.diagram[i] = .{
            .x_ft = x_ft,
            .moment_ft_lb = moment,
            .shear_lb = shear,
            .deflection_in = deflection,
        };

        if (@abs(moment) > @abs(result.max_moment_ft_lb)) {
            result.max_moment_ft_lb = moment;
            result.max_moment_pos_ft = x_ft;
        }
        if (@abs(shear) > @abs(result.max_shear_lb)) {
            result.max_shear_lb = shear;
            result.max_shear_pos_ft = x_ft;
        }
        if (@abs(deflection) > @abs(result.max_deflection_in)) {
            result.max_deflection_in = deflection;
            result.max_deflection_pos_ft = x_ft;
        }
    }

    return result;
}

// -- Tests ----------------------------------------------------------------

test "RectSection 2x10 nominal" {
    const sec = RectSection{ .b = 1.5, .d = 9.25 };
    try std.testing.expectApproxEqAbs(sec.area(), 13.875, 0.001);
    try std.testing.expectApproxEqAbs(sec.sectionModulus(), 21.3906, 0.01);
    try std.testing.expectApproxEqAbs(sec.momentOfInertia(), 98.932, 0.01);
}

test "UDL midspan moment = wL^2/8" {
    const span: f64 = 12.0;
    const w: f64 = 100.0;
    const loads = [_]Load{.{ .uniform_full = .{ .w_plf = w } }};
    const result = analyzeSimpleBeam(span, &loads, 1_600_000, 98.932);
    const expected_m = w * span * span / 8.0;
    try std.testing.expectApproxEqAbs(result.max_moment_ft_lb, expected_m, 1.0);
}

test "point load midspan moment = PL/4" {
    const span: f64 = 10.0;
    const p: f64 = 1000.0;
    const loads = [_]Load{.{ .point = .{ .p_lb = p, .a_ft = 5.0 } }};
    const result = analyzeSimpleBeam(span, &loads, 1_600_000, 98.932);
    const expected_m = p * span / 4.0;
    try std.testing.expectApproxEqAbs(result.max_moment_ft_lb, expected_m, 1.0);
}

test "UDL max deflection = 5wL^4/(384EI)" {
    const span: f64 = 12.0;
    const w: f64 = 100.0;
    const e: f64 = 1_600_000.0;
    const i: f64 = 98.932;
    const loads = [_]Load{.{ .uniform_full = .{ .w_plf = w } }};
    const result = analyzeSimpleBeam(span, &loads, e, i);
    // 5*w*L^4 / (384*E*I), w in lb/in, L in inches
    const w_in = w / 12.0;
    const l_in = span * 12.0;
    const expected = 5.0 * w_in * l_in * l_in * l_in * l_in / (384.0 * e * i);
    try std.testing.expectApproxEqRel(result.max_deflection_in, expected, 0.02);
}
