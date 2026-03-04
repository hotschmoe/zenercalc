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
    var max_total: f64 = -std.math.inf(f64);
    var max_name: []const u8 = "";
    var max_idx: usize = 0;

    for (asd_combinations, 0..) |c, i| {
        const total = c.apply(case);
        if (total > max_total) {
            max_total = total;
            max_name = c.name;
            max_idx = i;
        }
    }

    return .{ .combo_name = max_name, .total = max_total, .index = max_idx };
}

pub fn minimumAsd(case: LoadCase) GoverningResult {
    var min_total: f64 = std.math.inf(f64);
    var min_name: []const u8 = "";
    var min_idx: usize = 0;

    for (asd_combinations, 0..) |c, i| {
        const total = c.apply(case);
        if (total < min_total) {
            min_total = total;
            min_name = c.name;
            min_idx = i;
        }
    }

    return .{ .combo_name = min_name, .total = min_total, .index = min_idx };
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

test "load duration from governing combo" {
    var case = LoadCase{};
    case.set(.dead, 100);
    case.set(.live, 200);
    const gov = governingAsd(case);
    const dur = governingLoadDuration(gov.index, case);
    try std.testing.expectEqual(LoadDuration.normal, dur);
}
