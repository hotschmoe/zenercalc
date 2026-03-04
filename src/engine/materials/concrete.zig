const std = @import("std");

// ACI 318-19 Concrete and Reinforcement Properties

pub const ConcreteStrength = enum {
    fc_3000,
    fc_4000,
    fc_5000,
    fc_6000,

    // f'c in psi
    pub fn fc(self: ConcreteStrength) f64 {
        return switch (self) {
            .fc_3000 => 3000,
            .fc_4000 => 4000,
            .fc_5000 => 5000,
            .fc_6000 => 6000,
        };
    }

    pub fn code(self: ConcreteStrength) []const u8 {
        return switch (self) {
            .fc_3000 => "3000",
            .fc_4000 => "4000",
            .fc_5000 => "5000",
            .fc_6000 => "6000",
        };
    }
};

// ACI 318-19 Section 19.2.4 -- lightweight concrete modification factor
pub const ConcreteType = enum {
    normal_weight,
    sand_lightweight,
    all_lightweight,

    pub fn lambda(self: ConcreteType) f64 {
        return switch (self) {
            .normal_weight => 1.0,
            .sand_lightweight => 0.85,
            .all_lightweight => 0.75,
        };
    }

    pub fn code(self: ConcreteType) []const u8 {
        return switch (self) {
            .normal_weight => "NW",
            .sand_lightweight => "SLW",
            .all_lightweight => "ALW",
        };
    }

    // Unit weight in pcf (typical values)
    pub fn unitWeight(self: ConcreteType) f64 {
        return switch (self) {
            .normal_weight => 150.0,
            .sand_lightweight => 120.0,
            .all_lightweight => 110.0,
        };
    }
};

pub const RebarGrade = enum {
    grade_40,
    grade_60,
    grade_80,

    // fy in psi
    pub fn fy(self: RebarGrade) f64 {
        return switch (self) {
            .grade_40 => 40_000,
            .grade_60 => 60_000,
            .grade_80 => 80_000,
        };
    }

    pub fn code(self: RebarGrade) []const u8 {
        return switch (self) {
            .grade_40 => "40",
            .grade_60 => "60",
            .grade_80 => "80",
        };
    }
};

// ASTM A615 standard rebar sizes
pub const BarSize = enum {
    no3,
    no4,
    no5,
    no6,
    no7,
    no8,
    no9,
    no10,
    no11,

    pub fn diameter(self: BarSize) f64 {
        return bar_table[@intFromEnum(self)].diameter;
    }

    pub fn area(self: BarSize) f64 {
        return bar_table[@intFromEnum(self)].area;
    }

    pub fn weight(self: BarSize) f64 {
        return bar_table[@intFromEnum(self)].weight;
    }

    pub fn code(self: BarSize) []const u8 {
        return bar_table[@intFromEnum(self)].name;
    }
};

const BarEntry = struct {
    name: []const u8,
    diameter: f64, // inches
    area: f64, // in2
    weight: f64, // lb/ft
};

// ASTM A615 -- 9 standard sizes
pub const bar_table = [_]BarEntry{
    .{ .name = "#3", .diameter = 0.375, .area = 0.11, .weight = 0.376 },
    .{ .name = "#4", .diameter = 0.500, .area = 0.20, .weight = 0.668 },
    .{ .name = "#5", .diameter = 0.625, .area = 0.31, .weight = 1.043 },
    .{ .name = "#6", .diameter = 0.750, .area = 0.44, .weight = 1.502 },
    .{ .name = "#7", .diameter = 0.875, .area = 0.60, .weight = 2.044 },
    .{ .name = "#8", .diameter = 1.000, .area = 0.79, .weight = 2.670 },
    .{ .name = "#9", .diameter = 1.128, .area = 1.00, .weight = 3.400 },
    .{ .name = "#10", .diameter = 1.270, .area = 1.27, .weight = 4.303 },
    .{ .name = "#11", .diameter = 1.410, .area = 1.56, .weight = 5.313 },
};

pub const ConcreteMaterial = struct {
    strength: ConcreteStrength,
    concrete_type: ConcreteType,
    rebar_grade: RebarGrade,
};

// -- Tests ----------------------------------------------------------------

test "bar table has 9 entries" {
    try std.testing.expectEqual(@as(usize, 9), bar_table.len);
}

test "#5 bar properties" {
    try std.testing.expectApproxEqAbs(BarSize.no5.diameter(), 0.625, 0.001);
    try std.testing.expectApproxEqAbs(BarSize.no5.area(), 0.31, 0.001);
}

test "#8 bar properties" {
    try std.testing.expectApproxEqAbs(BarSize.no8.diameter(), 1.000, 0.001);
    try std.testing.expectApproxEqAbs(BarSize.no8.area(), 0.79, 0.001);
}

test "concrete strength values" {
    try std.testing.expectApproxEqAbs(ConcreteStrength.fc_4000.fc(), 4000.0, 0.01);
    try std.testing.expectApproxEqAbs(ConcreteStrength.fc_6000.fc(), 6000.0, 0.01);
}

test "lambda values" {
    try std.testing.expectApproxEqAbs(ConcreteType.normal_weight.lambda(), 1.0, 0.001);
    try std.testing.expectApproxEqAbs(ConcreteType.sand_lightweight.lambda(), 0.85, 0.001);
    try std.testing.expectApproxEqAbs(ConcreteType.all_lightweight.lambda(), 0.75, 0.001);
}

test "rebar grade values" {
    try std.testing.expectApproxEqAbs(RebarGrade.grade_60.fy(), 60_000.0, 0.01);
    try std.testing.expectApproxEqAbs(RebarGrade.grade_80.fy(), 80_000.0, 0.01);
}
