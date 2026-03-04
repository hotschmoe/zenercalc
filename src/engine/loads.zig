const std = @import("std");

// ASCE 7-22 Section 2.4.1 ASD Load Combinations

pub const LoadType = enum {
    dead,
    live,
    live_roof,
    snow,
    rain,
    wind,
    seismic,

    pub const count = @typeInfo(LoadType).@"enum".fields.len;
};

pub const LoadCase = struct {
    values: [LoadType.count]f64 = .{0} ** LoadType.count,

    pub fn set(self: *LoadCase, load_type: LoadType, value: f64) void {
        self.values[@intFromEnum(load_type)] = value;
    }

    pub fn get(self: LoadCase, load_type: LoadType) f64 {
        return self.values[@intFromEnum(load_type)];
    }
};

pub const LoadCombo = struct {
    name: []const u8,
    equation: []const u8,
    factors: [LoadType.count]f64,

    pub fn apply(self: LoadCombo, case: LoadCase) f64 {
        var total: f64 = 0;
        for (0..LoadType.count) |i| {
            total += self.factors[i] * case.values[i];
        }
        return total;
    }
};

fn combo(name: []const u8, equation: []const u8, factors: [LoadType.count]f64) LoadCombo {
    return .{ .name = name, .equation = equation, .factors = factors };
}

// Factor array helper: indices match LoadType enum order
// [dead, live, live_roof, snow, rain, wind, seismic]
const F = [LoadType.count]f64;

pub const asd_combinations = [_]LoadCombo{
    // ASCE 7-22 Section 2.4.1
    combo("ASD-1", "D", F{ 1.0, 0, 0, 0, 0, 0, 0 }),
    combo("ASD-2", "D + L", F{ 1.0, 1.0, 0, 0, 0, 0, 0 }),
    combo("ASD-3a", "D + Lr", F{ 1.0, 0, 1.0, 0, 0, 0, 0 }),
    combo("ASD-3b", "D + S", F{ 1.0, 0, 0, 1.0, 0, 0, 0 }),
    combo("ASD-3c", "D + R", F{ 1.0, 0, 0, 0, 1.0, 0, 0 }),
    combo("ASD-4a", "D + 0.75L + 0.75Lr", F{ 1.0, 0.75, 0.75, 0, 0, 0, 0 }),
    combo("ASD-4b", "D + 0.75L + 0.75S", F{ 1.0, 0.75, 0, 0.75, 0, 0, 0 }),
    combo("ASD-4c", "D + 0.75L + 0.75R", F{ 1.0, 0.75, 0, 0, 0.75, 0, 0 }),
    combo("ASD-5a", "D + 0.6W", F{ 1.0, 0, 0, 0, 0, 0.6, 0 }),
    combo("ASD-5a'", "D - 0.6W", F{ 1.0, 0, 0, 0, 0, -0.6, 0 }),
    combo("ASD-5b", "D + 0.7E", F{ 1.0, 0, 0, 0, 0, 0, 0.7 }),
    combo("ASD-6a", "D + 0.75L + 0.45W + 0.75Lr", F{ 1.0, 0.75, 0.75, 0, 0, 0.45, 0 }),
    combo("ASD-6a'", "D + 0.75L - 0.45W + 0.75Lr", F{ 1.0, 0.75, 0.75, 0, 0, -0.45, 0 }),
    combo("ASD-6b", "D + 0.75L + 0.45W + 0.75S", F{ 1.0, 0.75, 0, 0.75, 0, 0.45, 0 }),
    combo("ASD-6b'", "D + 0.75L - 0.45W + 0.75S", F{ 1.0, 0.75, 0, 0.75, 0, -0.45, 0 }),
    combo("ASD-6c", "D + 0.75L + 0.45W + 0.75R", F{ 1.0, 0.75, 0, 0, 0.75, 0.45, 0 }),
    combo("ASD-6c'", "D + 0.75L - 0.45W + 0.75R", F{ 1.0, 0.75, 0, 0, 0.75, -0.45, 0 }),
    combo("ASD-7", "D + 0.75L + 0.525E + 0.75S", F{ 1.0, 0.75, 0, 0.75, 0, 0, 0.525 }),
    combo("ASD-8", "0.6D + 0.6W", F{ 0.6, 0, 0, 0, 0, 0.6, 0 }),
    combo("ASD-8'", "0.6D - 0.6W", F{ 0.6, 0, 0, 0, 0, -0.6, 0 }),
    combo("ASD-9", "0.6D + 0.7E", F{ 0.6, 0, 0, 0, 0, 0, 0.7 }),
};

pub const GoverningResult = struct {
    combo_name: []const u8,
    total: f64,
    index: usize,
};

pub fn governingAsd(case: LoadCase) GoverningResult {
    return governing(&asd_combinations, case);
}

pub fn minimumAsd(case: LoadCase) GoverningResult {
    return minimum(&asd_combinations, case);
}

// ASCE 7-22 Section 2.3.1 LRFD Load Combinations

pub const lrfd_combinations = [_]LoadCombo{
    combo("LRFD-1", "1.4D", F{ 1.4, 0, 0, 0, 0, 0, 0 }),
    combo("LRFD-2", "1.2D + 1.6L + 0.5Lr", F{ 1.2, 1.6, 0.5, 0, 0, 0, 0 }),
    combo("LRFD-2a", "1.2D + 1.6L + 0.5S", F{ 1.2, 1.6, 0, 0.5, 0, 0, 0 }),
    combo("LRFD-2b", "1.2D + 1.6L + 0.5R", F{ 1.2, 1.6, 0, 0, 0.5, 0, 0 }),
    combo("LRFD-3", "1.2D + 1.6Lr + L", F{ 1.2, 1.0, 1.6, 0, 0, 0, 0 }),
    combo("LRFD-3a", "1.2D + 1.6S + L", F{ 1.2, 1.0, 0, 1.6, 0, 0, 0 }),
    combo("LRFD-3b", "1.2D + 1.6R + L", F{ 1.2, 1.0, 0, 0, 1.6, 0, 0 }),
    combo("LRFD-3c", "1.2D + 1.6Lr + 0.5W", F{ 1.2, 0, 1.6, 0, 0, 0.5, 0 }),
    combo("LRFD-3d", "1.2D + 1.6S + 0.5W", F{ 1.2, 0, 0, 1.6, 0, 0.5, 0 }),
    combo("LRFD-3e", "1.2D + 1.6R + 0.5W", F{ 1.2, 0, 0, 0, 1.6, 0.5, 0 }),
    combo("LRFD-4", "1.2D + 1.0W + L + 0.5Lr", F{ 1.2, 1.0, 0.5, 0, 0, 1.0, 0 }),
    combo("LRFD-4a", "1.2D + 1.0W + L + 0.5S", F{ 1.2, 1.0, 0, 0.5, 0, 1.0, 0 }),
    combo("LRFD-4b", "1.2D + 1.0W + L + 0.5R", F{ 1.2, 1.0, 0, 0, 0.5, 1.0, 0 }),
    combo("LRFD-5", "1.2D + 1.0E + L + 0.2S", F{ 1.2, 1.0, 0, 0.2, 0, 0, 1.0 }),
    combo("LRFD-6", "0.9D + 1.0W", F{ 0.9, 0, 0, 0, 0, 1.0, 0 }),
    combo("LRFD-6'", "0.9D - 1.0W", F{ 0.9, 0, 0, 0, 0, -1.0, 0 }),
    combo("LRFD-7", "0.9D + 1.0E", F{ 0.9, 0, 0, 0, 0, 0, 1.0 }),
};

pub fn governingLrfd(case: LoadCase) GoverningResult {
    return governing(&lrfd_combinations, case);
}

pub fn minimumLrfd(case: LoadCase) GoverningResult {
    return minimum(&lrfd_combinations, case);
}

fn governing(combos: []const LoadCombo, case: LoadCase) GoverningResult {
    var best_total: f64 = -std.math.inf(f64);
    var best_name: []const u8 = "";
    var best_idx: usize = 0;

    for (combos, 0..) |c, i| {
        const total = c.apply(case);
        if (total > best_total) {
            best_total = total;
            best_name = c.name;
            best_idx = i;
        }
    }

    return .{ .combo_name = best_name, .total = best_total, .index = best_idx };
}

fn minimum(combos: []const LoadCombo, case: LoadCase) GoverningResult {
    var best_total: f64 = std.math.inf(f64);
    var best_name: []const u8 = "";
    var best_idx: usize = 0;

    for (combos, 0..) |c, i| {
        const total = c.apply(case);
        if (total < best_total) {
            best_total = total;
            best_name = c.name;
            best_idx = i;
        }
    }

    return .{ .combo_name = best_name, .total = best_total, .index = best_idx };
}

// Determine load duration from governing combo's load types.
// Returns the shortest-duration load type present with nonzero factor.
pub fn governingLoadDuration(combo_idx: usize, case: LoadCase) LoadDuration {
    const c = asd_combinations[combo_idx];
    // Check from shortest duration to longest
    if (c.factors[@intFromEnum(LoadType.wind)] != 0 and case.get(.wind) != 0) return .wind_seismic;
    if (c.factors[@intFromEnum(LoadType.seismic)] != 0 and case.get(.seismic) != 0) return .wind_seismic;
    if (c.factors[@intFromEnum(LoadType.snow)] != 0 and case.get(.snow) != 0) return .snow;
    if (c.factors[@intFromEnum(LoadType.live)] != 0 and case.get(.live) != 0) return .normal;
    if (c.factors[@intFromEnum(LoadType.live_roof)] != 0 and case.get(.live_roof) != 0) return .normal;
    if (c.factors[@intFromEnum(LoadType.rain)] != 0 and case.get(.rain) != 0) return .normal;
    return .permanent;
}

pub const LoadDuration = enum {
    permanent,
    normal,
    snow,
    construction,
    wind_seismic,
    impact,

    // NDS 2018 Table 2.3.2
    pub fn factor(self: LoadDuration) f64 {
        return switch (self) {
            .permanent => 0.9,
            .normal => 1.0,
            .snow => 1.15,
            .construction => 1.25,
            .wind_seismic => 1.6,
            .impact => 2.0,
        };
    }
};

// -- Tests ----------------------------------------------------------------

test "ASD combo count" {
    try std.testing.expectEqual(@as(usize, 21), asd_combinations.len);
}

test "ASD-2 D+L" {
    var case = LoadCase{};
    case.set(.dead, 150);
    case.set(.live, 400);
    const gov = governingAsd(case);
    try std.testing.expectApproxEqAbs(gov.total, 550.0, 0.001);
    try std.testing.expectEqualStrings("ASD-2", gov.combo_name);
}

test "ASD-8' uplift" {
    var case = LoadCase{};
    case.set(.dead, 150);
    case.set(.wind, 200);
    const min = minimumAsd(case);
    // 0.6*150 - 0.6*200 = 90 - 120 = -30
    try std.testing.expectApproxEqAbs(min.total, -30.0, 0.001);
    try std.testing.expectEqualStrings("ASD-8'", min.combo_name);
}

test "LRFD combo count" {
    try std.testing.expectEqual(@as(usize, 17), lrfd_combinations.len);
}

test "LRFD-2 1.2D + 1.6L" {
    var case = LoadCase{};
    case.set(.dead, 100);
    case.set(.live, 200);
    // LRFD-2: 1.2*100 + 1.6*200 = 120 + 320 = 440
    const gov = governingLrfd(case);
    try std.testing.expectApproxEqAbs(gov.total, 440.0, 0.001);
    try std.testing.expectEqualStrings("LRFD-2", gov.combo_name);
}

test "LRFD-6' uplift" {
    var case = LoadCase{};
    case.set(.dead, 100);
    case.set(.wind, 200);
    const min = minimumLrfd(case);
    // LRFD-6': 0.9*100 - 1.0*200 = 90 - 200 = -110
    try std.testing.expectApproxEqAbs(min.total, -110.0, 0.001);
    try std.testing.expectEqualStrings("LRFD-6'", min.combo_name);
}

test "load duration from governing combo" {
    var case = LoadCase{};
    case.set(.dead, 100);
    case.set(.live, 200);
    const gov = governingAsd(case);
    const dur = governingLoadDuration(gov.index, case);
    try std.testing.expectEqual(LoadDuration.normal, dur);
}
