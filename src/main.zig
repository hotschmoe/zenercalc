const std = @import("std");
const zenercalc = @import("zenercalc");

const wood_beam = zenercalc.wood_beam;
const wood = zenercalc.wood;
const loads = zenercalc.loads;
const nds2018 = zenercalc.nds2018;

pub fn main() !void {
    var gpa_impl: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_impl.deinit();
    const gpa = gpa_impl.allocator();

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    var input_bytes: []const u8 = undefined;
    var allocated = false;

    if (args.len > 1) {
        input_bytes = try std.fs.cwd().readFileAlloc(gpa, args[1], 1024 * 1024);
        allocated = true;
    } else {
        input_bytes = try std.fs.File.stdin().readToEndAlloc(gpa, 1024 * 1024);
        allocated = true;
    }
    defer if (allocated) gpa.free(input_bytes);

    const inputs = parseInputs(input_bytes) catch |err| {
        try writeError(err);
        return;
    };

    const outputs = wood_beam.compute(inputs) catch |err| {
        try writeError(err);
        return;
    };

    try writeOutputs(inputs, outputs);
}

const ParseError = error{
    InvalidJson,
    UnsupportedModule,
    UnknownSpecies,
    UnknownGrade,
    UnknownStressClass,
    UnknownMaterial,
};

fn parseInputs(bytes: []const u8) ParseError!wood_beam.Inputs {
    const parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, bytes, .{}) catch
        return error.InvalidJson;
    defer parsed.deinit();

    const root = parsed.value.object;

    if (root.get("module")) |m| {
        if (m == .string) {
            if (!std.mem.eql(u8, m.string, "wood_beam")) return error.UnsupportedModule;
        }
    }

    var inputs = wood_beam.Inputs{
        .span_ft = getFloat(root, "span_ft") orelse 0,
        .width_in = getFloat(root, "width_in") orelse 0,
        .depth_in = getFloat(root, "depth_in") orelse 0,
        .material = undefined,
        .dead_load_plf = getFloat(root, "dead_load_plf") orelse 0,
        .live_load_plf = getFloat(root, "live_load_plf") orelse 0,
        .snow_load_plf = getFloat(root, "snow_load_plf") orelse 0,
        .wind_load_plf = getFloat(root, "wind_load_plf") orelse 0,
    };

    if (root.get("material")) |mat_val| {
        if (mat_val == .object) {
            const mat = mat_val.object;
            const mat_type = if (mat.get("type")) |t| (if (t == .string) t.string else null) else null;
            if (mat_type) |mt| {
                if (std.mem.eql(u8, mt, "sawn_lumber")) {
                    const species = parseSpecies(mat) orelse return error.UnknownSpecies;
                    const grade = parseGrade(mat) orelse return error.UnknownGrade;
                    inputs.material = .{ .sawn_lumber = .{ .species = species, .grade = grade } };
                } else if (std.mem.eql(u8, mt, "glulam")) {
                    const sc = parseStressClass(mat) orelse return error.UnknownStressClass;
                    inputs.material = .{ .glulam = .{ .stress_class = sc } };
                } else {
                    return error.UnknownMaterial;
                }
            } else {
                return error.UnknownMaterial;
            }
        } else {
            return error.UnknownMaterial;
        }
    } else {
        return error.UnknownMaterial;
    }

    if (root.get("include_self_weight")) |v| {
        if (v == .bool) inputs.include_self_weight = v.bool;
    }
    if (root.get("compression_edge_braced")) |v| {
        if (v == .bool) inputs.compression_edge_braced = v.bool;
    }
    if (root.get("flat_use")) |v| {
        if (v == .bool) inputs.flat_use = v.bool;
    }
    if (root.get("unbraced_length_ft")) |v| {
        inputs.unbraced_length_ft = jsonFloat(v) orelse 0;
    }
    if (root.get("deflection_limit_ll")) |v| {
        inputs.deflection_limit_ll = jsonFloat(v) orelse 360;
    }
    if (root.get("deflection_limit_tl")) |v| {
        inputs.deflection_limit_tl = jsonFloat(v) orelse 240;
    }

    if (getString(root, "load_duration")) |s| {
        inputs.load_duration = stringToLoadDuration(s);
    }
    if (getString(root, "moisture")) |s| {
        inputs.moisture = stringToMoisture(s);
    }
    if (getString(root, "temperature")) |s| {
        inputs.temperature = stringToTemperature(s);
    }
    if (getString(root, "incising")) |s| {
        inputs.incising = stringToIncising(s);
    }
    if (getString(root, "repetitive")) |s| {
        inputs.repetitive = stringToRepetitive(s);
    }

    return inputs;
}

fn getFloat(obj: std.json.ObjectMap, key: []const u8) ?f64 {
    if (obj.get(key)) |v| return jsonFloat(v);
    return null;
}

fn jsonFloat(v: std.json.Value) ?f64 {
    return switch (v) {
        .float => |f| f,
        .integer => |i| @floatFromInt(i),
        else => null,
    };
}

fn getString(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    if (obj.get(key)) |v| {
        if (v == .string) return v.string;
    }
    return null;
}

fn parseSpecies(obj: std.json.ObjectMap) ?wood.Species {
    const s = getString(obj, "species") orelse return null;
    if (std.mem.eql(u8, s, "DF-L")) return .douglas_fir_larch;
    if (std.mem.eql(u8, s, "SP")) return .southern_pine;
    if (std.mem.eql(u8, s, "HF")) return .hem_fir;
    if (std.mem.eql(u8, s, "SPF")) return .spruce_pine_fir;
    if (std.mem.eql(u8, s, "DF-S")) return .douglas_fir_south;
    return null;
}

fn parseGrade(obj: std.json.ObjectMap) ?wood.Grade {
    const s = getString(obj, "grade") orelse return null;
    if (std.mem.eql(u8, s, "SS")) return .select_structural;
    if (std.mem.eql(u8, s, "No.1") or std.mem.eql(u8, s, "No1")) return .no1;
    if (std.mem.eql(u8, s, "No.2") or std.mem.eql(u8, s, "No2")) return .no2;
    if (std.mem.eql(u8, s, "No.3") or std.mem.eql(u8, s, "No3")) return .no3;
    return null;
}

fn parseStressClass(obj: std.json.ObjectMap) ?wood.GlulamStressClass {
    const s = getString(obj, "stress_class") orelse return null;
    inline for (@typeInfo(wood.GlulamStressClass).@"enum".fields) |field| {
        if (std.mem.eql(u8, s, field.name)) return @enumFromInt(field.value);
    }
    return null;
}

fn stringToLoadDuration(s: []const u8) loads.LoadDuration {
    if (std.mem.eql(u8, s, "permanent")) return .permanent;
    if (std.mem.eql(u8, s, "snow")) return .snow;
    if (std.mem.eql(u8, s, "construction")) return .construction;
    if (std.mem.eql(u8, s, "wind_seismic")) return .wind_seismic;
    if (std.mem.eql(u8, s, "impact")) return .impact;
    return .normal;
}

fn stringToMoisture(s: []const u8) nds2018.MoistureCondition {
    if (std.mem.eql(u8, s, "wet")) return .wet;
    return .dry;
}

fn stringToTemperature(s: []const u8) nds2018.TemperatureCondition {
    if (std.mem.eql(u8, s, "elevated")) return .elevated;
    if (std.mem.eql(u8, s, "high")) return .high;
    return .normal;
}

fn stringToIncising(s: []const u8) nds2018.IncisingCondition {
    if (std.mem.eql(u8, s, "incised")) return .incised;
    return .none;
}

fn stringToRepetitive(s: []const u8) nds2018.RepetitiveCondition {
    if (std.mem.eql(u8, s, "repetitive")) return .repetitive;
    return .single;
}

fn writeError(err: anytype) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const w = &stdout_writer.interface;
    try w.print("{{\"error\": \"{s}\"}}\n", .{@errorName(err)});
    try w.flush();
}

fn writeOutputs(inputs: wood_beam.Inputs, out: wood_beam.Outputs) !void {
    var stdout_buffer: [16384]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const w = &stdout_writer.interface;

    const status_str = if (out.overall_status == .pass) "pass" else "fail";
    const combo_name = out.governing_combo_name[0..out.governing_combo_len];

    // Split into multiple print calls to stay within Zig's 32-arg format limit
    try w.print(
        \\{{
        \\  "module": "wood_beam",
        \\  "status": "{s}",
        \\  "section": {{
        \\    "width_in": {d:.3},
        \\    "depth_in": {d:.3},
        \\    "area_in2": {d:.3},
        \\    "section_modulus_in3": {d:.4},
        \\    "moment_of_inertia_in4": {d:.4}
        \\  }},
        \\  "loads": {{
        \\    "self_weight_plf": {d:.2},
        \\    "governing_combo": "{s}",
        \\    "governing_total_plf": {d:.2},
        \\    "load_duration": "{s}"
        \\  }},
        \\  "adjusted_values": {{
        \\    "Fb_prime_psi": {d:.1},
        \\    "Fv_prime_psi": {d:.1},
        \\    "E_prime_psi": {d:.0},
        \\    "E_min_prime_psi": {d:.0}
        \\  }},
        \\
    , .{
        status_str,
        inputs.width_in,
        inputs.depth_in,
        out.area_in2,
        out.section_modulus_in3,
        out.moment_of_inertia_in4,
        out.self_weight_plf,
        combo_name,
        out.governing_total_plf,
        @tagName(out.governing_load_duration),
        out.adjusted.fb_prime,
        out.adjusted.fv_prime,
        out.adjusted.e_prime,
        out.adjusted.e_min_prime,
    });

    try w.print(
        \\  "factors": {{
        \\    "C_D": {d:.3},
        \\    "C_M_fb": {d:.3},
        \\    "C_M_fv": {d:.3},
        \\    "C_M_e": {d:.3},
        \\    "C_t": {d:.3},
        \\    "C_F": {d:.3},
        \\    "C_fu": {d:.3},
        \\    "C_i": {d:.3},
        \\    "C_i_e": {d:.3},
        \\    "C_r": {d:.3},
        \\    "C_L": {d:.4}
        \\  }},
        \\  "results": {{
        \\    "max_moment_ft_lb": {d:.1},
        \\    "max_shear_lb": {d:.1},
        \\    "reaction_left_lb": {d:.1},
        \\    "reaction_right_lb": {d:.1},
        \\    "fb_actual_psi": {d:.1},
        \\    "fv_actual_psi": {d:.1},
        \\    "deflection_total_in": {d:.4},
        \\    "deflection_ll_in": {d:.4}
        \\  }},
        \\
    , .{
        out.adjusted.c_d,
        out.adjusted.c_m_fb,
        out.adjusted.c_m_fv,
        out.adjusted.c_m_e,
        out.adjusted.c_t,
        out.adjusted.c_f,
        out.adjusted.c_fu,
        out.adjusted.c_i_strength,
        out.adjusted.c_i_e,
        out.adjusted.c_r,
        out.adjusted.c_l,
        out.max_moment_ft_lb,
        out.max_shear_lb,
        out.reaction_left_lb,
        out.reaction_right_lb,
        out.fb_actual,
        out.fv_actual,
        out.max_deflection_total_in,
        out.max_deflection_ll_in,
    });

    try w.print(
        \\  "checks": {{
        \\    "bending": {{ "dcr": {d:.3}, "status": "{s}" }},
        \\    "shear": {{ "dcr": {d:.3}, "status": "{s}" }},
        \\    "deflection_ll": {{ "limit": "L/{d:.0}", "dcr": {d:.3}, "status": "{s}" }},
        \\    "deflection_tl": {{ "limit": "L/{d:.0}", "dcr": {d:.3}, "status": "{s}" }}
        \\  }}
        \\}}
        \\
    , .{
        out.dcr_bending,
        if (out.bending_status == .pass) "pass" else "fail",
        out.dcr_shear,
        if (out.shear_status == .pass) "pass" else "fail",
        inputs.deflection_limit_ll,
        out.dcr_deflection_ll,
        if (out.deflection_ll_status == .pass) "pass" else "fail",
        inputs.deflection_limit_tl,
        out.dcr_deflection_tl,
        if (out.deflection_tl_status == .pass) "pass" else "fail",
    });

    try w.flush();
}
