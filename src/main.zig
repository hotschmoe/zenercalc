const std = @import("std");
const zenercalc = @import("zenercalc");

const wood_beam = zenercalc.wood_beam;
const wood_column = zenercalc.wood_column;
const wood = zenercalc.wood;
const loads = zenercalc.loads;
const nds2018 = zenercalc.nds2018;

pub fn main() !void {
    var gpa_impl: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_impl.deinit();
    const gpa = gpa_impl.allocator();

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    const input_bytes = if (args.len > 1)
        try std.fs.cwd().readFileAlloc(gpa, args[1], 1024 * 1024)
    else
        try std.fs.File.stdin().readToEndAlloc(gpa, 1024 * 1024);
    defer gpa.free(input_bytes);

    const module_name = detectModule(input_bytes) catch |err| {
        try writeError(err);
        return;
    };

    if (std.mem.eql(u8, module_name, "wood_column")) {
        const inputs = parseColumnInputs(input_bytes) catch |err| {
            try writeError(err);
            return;
        };
        const outputs = wood_column.compute(inputs) catch |err| {
            try writeError(err);
            return;
        };
        try writeColumnOutputs(inputs, outputs);
    } else {
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
}

const ParseError = error{
    InvalidJson,
    UnsupportedModule,
    UnknownSpecies,
    UnknownGrade,
    UnknownStressClass,
    UnknownMaterial,
};

fn detectModule(bytes: []const u8) ParseError![]const u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, bytes, .{}) catch
        return error.InvalidJson;
    defer parsed.deinit();
    const root = parsed.value.object;
    if (root.get("module")) |m| {
        if (m == .string) {
            if (std.mem.eql(u8, m.string, "wood_beam")) return "wood_beam";
            if (std.mem.eql(u8, m.string, "wood_column")) return "wood_column";
            return error.UnsupportedModule;
        }
    }
    return "wood_beam"; // default
}

fn parseInputs(bytes: []const u8) ParseError!wood_beam.Inputs {
    const parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, bytes, .{}) catch
        return error.InvalidJson;
    defer parsed.deinit();

    const root = parsed.value.object;

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

    const mat_val = root.get("material") orelse return error.UnknownMaterial;
    if (mat_val != .object) return error.UnknownMaterial;
    const mat = mat_val.object;

    const type_val = mat.get("type") orelse return error.UnknownMaterial;
    const mt = if (type_val == .string) type_val.string else return error.UnknownMaterial;

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

fn parseColumnInputs(bytes: []const u8) ParseError!wood_column.Inputs {
    const parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, bytes, .{}) catch
        return error.InvalidJson;
    defer parsed.deinit();

    const root = parsed.value.object;

    var inputs = wood_column.Inputs{
        .height_ft = getFloat(root, "height_ft") orelse 0,
        .width_in = getFloat(root, "width_in") orelse 0,
        .depth_in = getFloat(root, "depth_in") orelse 0,
        .material = undefined,
        .axial_dead_lb = getFloat(root, "axial_dead_lb") orelse 0,
        .axial_live_lb = getFloat(root, "axial_live_lb") orelse 0,
        .axial_snow_lb = getFloat(root, "axial_snow_lb") orelse 0,
        .axial_wind_lb = getFloat(root, "axial_wind_lb") orelse 0,
        .moment_x_dead_ft_lb = getFloat(root, "moment_x_dead_ft_lb") orelse 0,
        .moment_x_live_ft_lb = getFloat(root, "moment_x_live_ft_lb") orelse 0,
        .moment_y_dead_ft_lb = getFloat(root, "moment_y_dead_ft_lb") orelse 0,
        .moment_y_live_ft_lb = getFloat(root, "moment_y_live_ft_lb") orelse 0,
    };

    const mat_val = root.get("material") orelse return error.UnknownMaterial;
    if (mat_val != .object) return error.UnknownMaterial;
    const mat = mat_val.object;

    const type_val = mat.get("type") orelse return error.UnknownMaterial;
    const mt = if (type_val == .string) type_val.string else return error.UnknownMaterial;

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

    if (root.get("include_self_weight")) |v| {
        if (v == .bool) inputs.include_self_weight = v.bool;
    }
    if (root.get("ke_x")) |v| {
        inputs.ke_x = jsonFloat(v) orelse 1.0;
    }
    if (root.get("ke_y")) |v| {
        inputs.ke_y = jsonFloat(v) orelse 1.0;
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

    return inputs;
}

fn writeColumnOutputs(inputs: wood_column.Inputs, out: wood_column.Outputs) !void {
    var stdout_buffer: [16384]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const w = &stdout_writer.interface;

    const status_str = if (out.overall_status == .pass) "pass" else "fail";
    const combo_name = out.governing_combo_name[0..out.governing_combo_len];

    try w.print(
        \\{{
        \\  "module": "wood_column",
        \\  "status": "{s}",
        \\  "section": {{
        \\    "width_in": {d:.3},
        \\    "depth_in": {d:.3},
        \\    "area_in2": {d:.3},
        \\    "Ix_in4": {d:.4},
        \\    "Iy_in4": {d:.4},
        \\    "Sx_in3": {d:.4},
        \\    "Sy_in3": {d:.4},
        \\    "rx_in": {d:.4},
        \\    "ry_in": {d:.4}
        \\  }},
        \\  "loads": {{
        \\    "self_weight_lb": {d:.2},
        \\    "governing_combo": "{s}",
        \\    "governing_axial_lb": {d:.2},
        \\    "governing_moment_x_ft_lb": {d:.2},
        \\    "governing_moment_y_ft_lb": {d:.2},
        \\    "load_duration": "{s}"
        \\  }},
        \\
    , .{
        status_str,
        inputs.width_in,
        inputs.depth_in,
        out.area_in2,
        out.ix_in4,
        out.iy_in4,
        out.sx_in3,
        out.sy_in3,
        out.rx_in,
        out.ry_in,
        out.self_weight_lb,
        combo_name,
        out.governing_axial_lb,
        out.governing_moment_x_ft_lb,
        out.governing_moment_y_ft_lb,
        @tagName(out.governing_load_duration),
    });

    try w.print(
        \\  "adjusted_values": {{
        \\    "Fc_star_psi": {d:.1},
        \\    "Fc_prime_psi": {d:.1},
        \\    "Fc_prime_x_psi": {d:.1},
        \\    "Fc_prime_y_psi": {d:.1},
        \\    "Fc_perp_prime_psi": {d:.1},
        \\    "Fb_prime_psi": {d:.1},
        \\    "Fv_prime_psi": {d:.1},
        \\    "E_prime_psi": {d:.0},
        \\    "E_min_prime_psi": {d:.0}
        \\  }},
        \\  "stability": {{
        \\    "le_d_x": {d:.2},
        \\    "le_d_y": {d:.2},
        \\    "Cp_x": {d:.4},
        \\    "Cp_y": {d:.4},
        \\    "FcE_x_psi": {d:.1},
        \\    "FcE_y_psi": {d:.1}
        \\  }},
        \\
    , .{
        out.adjusted.fc_star,
        out.adjusted.fc_prime,
        out.adjusted.fc_prime_x,
        out.adjusted.fc_prime_y,
        out.adjusted.fc_perp_prime,
        out.adjusted.fb_prime,
        out.adjusted.fv_prime,
        out.adjusted.e_prime,
        out.adjusted.e_min_prime,
        out.le_d_x,
        out.le_d_y,
        out.adjusted.cp_x,
        out.adjusted.cp_y,
        out.adjusted.fce_x,
        out.adjusted.fce_y,
    });

    try w.print(
        \\  "factors": {{
        \\    "C_D": {d:.3},
        \\    "C_M_fc": {d:.3},
        \\    "C_M_fb": {d:.3},
        \\    "C_M_fv": {d:.3},
        \\    "C_M_e": {d:.3},
        \\    "C_t": {d:.3},
        \\    "C_F_fc": {d:.3},
        \\    "C_F_fb": {d:.3},
        \\    "C_i": {d:.3},
        \\    "C_i_e": {d:.3}
        \\  }},
        \\  "stresses": {{
        \\    "fc_actual_psi": {d:.1},
        \\    "fbx_actual_psi": {d:.1},
        \\    "fby_actual_psi": {d:.1}
        \\  }},
        \\
    , .{
        out.adjusted.c_d,
        out.adjusted.c_m_fc,
        out.adjusted.c_m_fb,
        out.adjusted.c_m_fv,
        out.adjusted.c_m_e,
        out.adjusted.c_t,
        out.adjusted.c_f_fc,
        out.adjusted.c_f_fb,
        out.adjusted.c_i_strength,
        out.adjusted.c_i_e,
        out.fc_actual,
        out.fbx_actual,
        out.fby_actual,
    });

    try w.print(
        \\  "checks": {{
        \\    "compression": {{ "dcr": {d:.3}, "status": "{s}" }},
        \\    "interaction": {{ "dcr": {d:.3}, "status": "{s}" }}
        \\  }}
        \\}}
        \\
    , .{
        out.dcr_compression,
        if (out.compression_status == .pass) "pass" else "fail",
        out.dcr_interaction,
        if (out.interaction_status == .pass) "pass" else "fail",
    });

    try w.flush();
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
