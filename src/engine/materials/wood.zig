const std = @import("std");

// NDS 2018 Table 4A -- Sawn Lumber Reference Design Values

pub const Species = enum {
    douglas_fir_larch,
    southern_pine,
    hem_fir,
    spruce_pine_fir,
    douglas_fir_south,

    pub fn code(self: Species) []const u8 {
        return switch (self) {
            .douglas_fir_larch => "DF-L",
            .southern_pine => "SP",
            .hem_fir => "HF",
            .spruce_pine_fir => "SPF",
            .douglas_fir_south => "DF-S",
        };
    }
};

pub const Grade = enum {
    select_structural,
    no1,
    no2,
    no3,

    pub fn code(self: Grade) []const u8 {
        return switch (self) {
            .select_structural => "SS",
            .no1 => "No1",
            .no2 => "No2",
            .no3 => "No3",
        };
    }
};

pub const LumberProps = struct {
    fb: f64, // bending (psi)
    ft: f64, // tension parallel (psi)
    fv: f64, // shear (psi)
    fc_perp: f64, // compression perpendicular (psi)
    fc: f64, // compression parallel (psi)
    e: f64, // modulus of elasticity (psi)
    e_min: f64, // minimum E for stability (psi)
    sg: f64, // specific gravity
};

const LumberEntry = struct {
    species: Species,
    grade: Grade,
    props: LumberProps,
};

// NDS 2018 Table 4A -- 5 species x 4 grades = 20 entries
// All values transcribed from stratify's verified TOML / NDS 2018 Supplement
pub const lumber_table = [_]LumberEntry{
    // Douglas Fir-Larch
    .{ .species = .douglas_fir_larch, .grade = .select_structural, .props = .{ .fb = 1500, .ft = 1000, .fv = 180, .fc_perp = 625, .fc = 1700, .e = 1_900_000, .e_min = 690_000, .sg = 0.50 } },
    .{ .species = .douglas_fir_larch, .grade = .no1, .props = .{ .fb = 1200, .ft = 800, .fv = 180, .fc_perp = 625, .fc = 1550, .e = 1_700_000, .e_min = 620_000, .sg = 0.50 } },
    .{ .species = .douglas_fir_larch, .grade = .no2, .props = .{ .fb = 900, .ft = 575, .fv = 180, .fc_perp = 625, .fc = 1350, .e = 1_600_000, .e_min = 580_000, .sg = 0.50 } },
    .{ .species = .douglas_fir_larch, .grade = .no3, .props = .{ .fb = 525, .ft = 325, .fv = 180, .fc_perp = 625, .fc = 775, .e = 1_400_000, .e_min = 510_000, .sg = 0.50 } },
    // Southern Pine
    .{ .species = .southern_pine, .grade = .select_structural, .props = .{ .fb = 1500, .ft = 1000, .fv = 175, .fc_perp = 565, .fc = 1800, .e = 1_800_000, .e_min = 660_000, .sg = 0.55 } },
    .{ .species = .southern_pine, .grade = .no1, .props = .{ .fb = 1250, .ft = 825, .fv = 175, .fc_perp = 565, .fc = 1650, .e = 1_700_000, .e_min = 620_000, .sg = 0.55 } },
    .{ .species = .southern_pine, .grade = .no2, .props = .{ .fb = 850, .ft = 550, .fv = 175, .fc_perp = 565, .fc = 1450, .e = 1_400_000, .e_min = 510_000, .sg = 0.55 } },
    .{ .species = .southern_pine, .grade = .no3, .props = .{ .fb = 500, .ft = 300, .fv = 175, .fc_perp = 565, .fc = 825, .e = 1_200_000, .e_min = 440_000, .sg = 0.55 } },
    // Hem-Fir
    .{ .species = .hem_fir, .grade = .select_structural, .props = .{ .fb = 1400, .ft = 925, .fv = 150, .fc_perp = 405, .fc = 1500, .e = 1_600_000, .e_min = 580_000, .sg = 0.43 } },
    .{ .species = .hem_fir, .grade = .no1, .props = .{ .fb = 1100, .ft = 725, .fv = 150, .fc_perp = 405, .fc = 1350, .e = 1_500_000, .e_min = 550_000, .sg = 0.43 } },
    .{ .species = .hem_fir, .grade = .no2, .props = .{ .fb = 850, .ft = 525, .fv = 150, .fc_perp = 405, .fc = 1300, .e = 1_300_000, .e_min = 470_000, .sg = 0.43 } },
    .{ .species = .hem_fir, .grade = .no3, .props = .{ .fb = 500, .ft = 300, .fv = 150, .fc_perp = 405, .fc = 750, .e = 1_200_000, .e_min = 440_000, .sg = 0.43 } },
    // Spruce-Pine-Fir
    .{ .species = .spruce_pine_fir, .grade = .select_structural, .props = .{ .fb = 1250, .ft = 825, .fv = 135, .fc_perp = 425, .fc = 1400, .e = 1_500_000, .e_min = 550_000, .sg = 0.42 } },
    .{ .species = .spruce_pine_fir, .grade = .no1, .props = .{ .fb = 1000, .ft = 650, .fv = 135, .fc_perp = 425, .fc = 1250, .e = 1_400_000, .e_min = 510_000, .sg = 0.42 } },
    .{ .species = .spruce_pine_fir, .grade = .no2, .props = .{ .fb = 875, .ft = 450, .fv = 135, .fc_perp = 425, .fc = 1150, .e = 1_400_000, .e_min = 510_000, .sg = 0.42 } },
    .{ .species = .spruce_pine_fir, .grade = .no3, .props = .{ .fb = 500, .ft = 250, .fv = 135, .fc_perp = 425, .fc = 650, .e = 1_200_000, .e_min = 440_000, .sg = 0.42 } },
    // Douglas Fir-South
    .{ .species = .douglas_fir_south, .grade = .select_structural, .props = .{ .fb = 1350, .ft = 900, .fv = 180, .fc_perp = 520, .fc = 1600, .e = 1_400_000, .e_min = 510_000, .sg = 0.46 } },
    .{ .species = .douglas_fir_south, .grade = .no1, .props = .{ .fb = 1050, .ft = 700, .fv = 180, .fc_perp = 520, .fc = 1450, .e = 1_200_000, .e_min = 440_000, .sg = 0.46 } },
    .{ .species = .douglas_fir_south, .grade = .no2, .props = .{ .fb = 875, .ft = 525, .fv = 180, .fc_perp = 520, .fc = 1350, .e = 1_100_000, .e_min = 400_000, .sg = 0.46 } },
    .{ .species = .douglas_fir_south, .grade = .no3, .props = .{ .fb = 500, .ft = 300, .fv = 180, .fc_perp = 520, .fc = 775, .e = 1_000_000, .e_min = 370_000, .sg = 0.46 } },
};

pub fn lookupLumber(species: Species, grade: Grade) ?LumberProps {
    for (lumber_table) |entry| {
        if (entry.species == species and entry.grade == grade) return entry.props;
    }
    return null;
}

// NDS Supplement Table 5A/5B -- Glulam

pub const GlulamStressClass = enum {
    @"16F-1.3E",
    @"20F-1.5E",
    @"24F-1.7E",
    @"24F-1.8E",
    @"26F-1.9E",
    @"24F-V4",
    @"24F-V8",

    pub fn code(self: GlulamStressClass) []const u8 {
        return @tagName(self);
    }
};

pub const GlulamProps = struct {
    fb_pos: f64,
    fb_neg: f64,
    ft: f64,
    fv: f64,
    fc_perp: f64,
    fc: f64,
    e: f64,
    e_min: f64,
    sg: f64,
    balanced: bool,
};

const GlulamEntry = struct {
    stress_class: GlulamStressClass,
    props: GlulamProps,
};

pub const glulam_table = [_]GlulamEntry{
    .{ .stress_class = .@"16F-1.3E", .props = .{ .fb_pos = 1600, .fb_neg = 1600, .ft = 800, .fv = 265, .fc_perp = 560, .fc = 1400, .e = 1_300_000, .e_min = 685_000, .sg = 0.50, .balanced = true } },
    .{ .stress_class = .@"20F-1.5E", .props = .{ .fb_pos = 2000, .fb_neg = 2000, .ft = 1000, .fv = 265, .fc_perp = 560, .fc = 1550, .e = 1_500_000, .e_min = 790_000, .sg = 0.50, .balanced = true } },
    .{ .stress_class = .@"24F-1.7E", .props = .{ .fb_pos = 2400, .fb_neg = 2400, .ft = 1150, .fv = 265, .fc_perp = 650, .fc = 1650, .e = 1_700_000, .e_min = 895_000, .sg = 0.50, .balanced = true } },
    .{ .stress_class = .@"24F-1.8E", .props = .{ .fb_pos = 2400, .fb_neg = 2400, .ft = 1150, .fv = 265, .fc_perp = 650, .fc = 1650, .e = 1_800_000, .e_min = 950_000, .sg = 0.50, .balanced = true } },
    .{ .stress_class = .@"26F-1.9E", .props = .{ .fb_pos = 2600, .fb_neg = 2600, .ft = 1250, .fv = 265, .fc_perp = 650, .fc = 1750, .e = 1_900_000, .e_min = 1_000_000, .sg = 0.50, .balanced = true } },
    .{ .stress_class = .@"24F-V4", .props = .{ .fb_pos = 2400, .fb_neg = 1450, .ft = 1100, .fv = 265, .fc_perp = 650, .fc = 1600, .e = 1_800_000, .e_min = 950_000, .sg = 0.50, .balanced = false } },
    .{ .stress_class = .@"24F-V8", .props = .{ .fb_pos = 2400, .fb_neg = 2400, .ft = 1100, .fv = 265, .fc_perp = 650, .fc = 1600, .e = 1_800_000, .e_min = 950_000, .sg = 0.50, .balanced = true } },
};

pub fn lookupGlulam(stress_class: GlulamStressClass) GlulamProps {
    for (glulam_table) |entry| {
        if (entry.stress_class == stress_class) return entry.props;
    }
    unreachable;
}

// Unified material type for the wood_beam module

pub const WoodMaterial = union(enum) {
    sawn_lumber: struct { species: Species, grade: Grade },
    glulam: struct { stress_class: GlulamStressClass },

    pub fn referenceFb(self: WoodMaterial) f64 {
        return switch (self) {
            .sawn_lumber => |s| (lookupLumber(s.species, s.grade) orelse unreachable).fb,
            .glulam => |g| lookupGlulam(g.stress_class).fb_pos,
        };
    }

    pub fn referenceFv(self: WoodMaterial) f64 {
        return switch (self) {
            .sawn_lumber => |s| (lookupLumber(s.species, s.grade) orelse unreachable).fv,
            .glulam => |g| lookupGlulam(g.stress_class).fv,
        };
    }

    pub fn referenceE(self: WoodMaterial) f64 {
        return switch (self) {
            .sawn_lumber => |s| (lookupLumber(s.species, s.grade) orelse unreachable).e,
            .glulam => |g| lookupGlulam(g.stress_class).e,
        };
    }

    pub fn referenceEmin(self: WoodMaterial) f64 {
        return switch (self) {
            .sawn_lumber => |s| (lookupLumber(s.species, s.grade) orelse unreachable).e_min,
            .glulam => |g| lookupGlulam(g.stress_class).e_min,
        };
    }

    pub fn specificGravity(self: WoodMaterial) f64 {
        return switch (self) {
            .sawn_lumber => |s| (lookupLumber(s.species, s.grade) orelse unreachable).sg,
            .glulam => |g| lookupGlulam(g.stress_class).sg,
        };
    }

    pub fn referenceFc(self: WoodMaterial) f64 {
        return switch (self) {
            .sawn_lumber => |s| (lookupLumber(s.species, s.grade) orelse unreachable).fc,
            .glulam => |g| lookupGlulam(g.stress_class).fc,
        };
    }

    pub fn referenceFcPerp(self: WoodMaterial) f64 {
        return switch (self) {
            .sawn_lumber => |s| (lookupLumber(s.species, s.grade) orelse unreachable).fc_perp,
            .glulam => |g| lookupGlulam(g.stress_class).fc_perp,
        };
    }

    pub fn referenceFt(self: WoodMaterial) f64 {
        return switch (self) {
            .sawn_lumber => |s| (lookupLumber(s.species, s.grade) orelse unreachable).ft,
            .glulam => |g| lookupGlulam(g.stress_class).ft,
        };
    }

    // NDS 2018 Table 3.7: c = 0.8 for sawn lumber, 0.9 for glulam
    pub fn bucklingC(self: WoodMaterial) f64 {
        return switch (self) {
            .sawn_lumber => 0.8,
            .glulam => 0.9,
        };
    }
};

// -- Tests ----------------------------------------------------------------

test "DF-L No.2 lookup" {
    const props = lookupLumber(.douglas_fir_larch, .no2).?;
    try std.testing.expectApproxEqAbs(props.fb, 900.0, 0.01);
    try std.testing.expectApproxEqAbs(props.e, 1_600_000.0, 0.01);
    try std.testing.expectApproxEqAbs(props.e_min, 580_000.0, 0.01);
    try std.testing.expectApproxEqAbs(props.fv, 180.0, 0.01);
}

test "24F-1.8E glulam lookup" {
    const props = lookupGlulam(.@"24F-1.8E");
    try std.testing.expectApproxEqAbs(props.fb_pos, 2400.0, 0.01);
    try std.testing.expectApproxEqAbs(props.e, 1_800_000.0, 0.01);
}

test "24F-V4 unbalanced" {
    const props = lookupGlulam(.@"24F-V4");
    try std.testing.expectApproxEqAbs(props.fb_pos, 2400.0, 0.01);
    try std.testing.expectApproxEqAbs(props.fb_neg, 1450.0, 0.01);
    try std.testing.expect(!props.balanced);
}

test "WoodMaterial unified access" {
    const mat = WoodMaterial{ .sawn_lumber = .{ .species = .douglas_fir_larch, .grade = .no2 } };
    try std.testing.expectApproxEqAbs(mat.referenceFb(), 900.0, 0.01);
    try std.testing.expectApproxEqAbs(mat.referenceE(), 1_600_000.0, 0.01);
}

test "lumber table has 20 entries" {
    try std.testing.expectEqual(@as(usize, 20), lumber_table.len);
}

test "glulam table has 7 entries" {
    try std.testing.expectEqual(@as(usize, 7), glulam_table.len);
}
