const std = @import("std");
const zenercalc = @import("zenercalc");

const wood_beam = zenercalc.wood_beam;
const wood_column = zenercalc.wood_column;
const spread_footing = zenercalc.spread_footing;
const wood = zenercalc.wood;
const concrete = zenercalc.concrete;
const loads = zenercalc.loads;
const nds2018 = zenercalc.nds2018;
const aci318 = zenercalc.aci318;

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
    } else if (std.mem.eql(u8, module_name, "spread_footing")) {
        const inputs = parseFootingInputs(input_bytes) catch |err| {
            try writeError(err);
            return;
        };
        const outputs = spread_footing.compute(inputs) catch |err| {
            try writeError(err);
            return;
        };
        try writeFootingOutputs(outputs);
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
    UnknownConcreteStrength,
    UnknownConcreteType,
    UnknownRebarGrade,
    UnknownBarSize,
    UnknownFootingShape,
    UnknownColumnShape,
    UnknownColumnPosition,
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
            if (std.mem.eql(u8, m.string, "spread_footing")) return "spread_footing";
            return error.UnsupportedModule;
        }
    }
    return "wood_beam"; // default
}

fn parseMaterial(root: std.json.ObjectMap) ParseError!wood.WoodMaterial {
    const mat_val = root.get("material") orelse return error.UnknownMaterial;
    if (mat_val != .object) return error.UnknownMaterial;
    const mat = mat_val.object;

    const type_val = mat.get("type") orelse return error.UnknownMaterial;
    const mt = if (type_val == .string) type_val.string else return error.UnknownMaterial;

    if (std.mem.eql(u8, mt, "sawn_lumber")) {
        const species = parseSpecies(mat) orelse return error.UnknownSpecies;
        const grade = parseGrade(mat) orelse return error.UnknownGrade;
        return .{ .sawn_lumber = .{ .species = species, .grade = grade } };
    } else if (std.mem.eql(u8, mt, "glulam")) {
        const sc = parseStressClass(mat) orelse return error.UnknownStressClass;
        return .{ .glulam = .{ .stress_class = sc } };
    } else {
        return error.UnknownMaterial;
    }
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
        .material = try parseMaterial(root),
        .dead_load_plf = getFloat(root, "dead_load_plf") orelse 0,
        .live_load_plf = getFloat(root, "live_load_plf") orelse 0,
        .snow_load_plf = getFloat(root, "snow_load_plf") orelse 0,
        .wind_load_plf = getFloat(root, "wind_load_plf") orelse 0,
    };

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
        .material = try parseMaterial(root),
        .axial_dead_lb = getFloat(root, "axial_dead_lb") orelse 0,
        .axial_live_lb = getFloat(root, "axial_live_lb") orelse 0,
        .axial_snow_lb = getFloat(root, "axial_snow_lb") orelse 0,
        .axial_wind_lb = getFloat(root, "axial_wind_lb") orelse 0,
        .moment_x_dead_ft_lb = getFloat(root, "moment_x_dead_ft_lb") orelse 0,
        .moment_x_live_ft_lb = getFloat(root, "moment_x_live_ft_lb") orelse 0,
        .moment_y_dead_ft_lb = getFloat(root, "moment_y_dead_ft_lb") orelse 0,
        .moment_y_live_ft_lb = getFloat(root, "moment_y_live_ft_lb") orelse 0,
    };

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

// -- Spread Footing Parsing -----------------------------------------------

fn parseConcreteStrength(s: []const u8) ?concrete.ConcreteStrength {
    if (std.mem.eql(u8, s, "3000")) return .fc_3000;
    if (std.mem.eql(u8, s, "4000")) return .fc_4000;
    if (std.mem.eql(u8, s, "5000")) return .fc_5000;
    if (std.mem.eql(u8, s, "6000")) return .fc_6000;
    return null;
}

fn parseConcreteType(s: []const u8) ?concrete.ConcreteType {
    if (std.mem.eql(u8, s, "normal_weight") or std.mem.eql(u8, s, "NW")) return .normal_weight;
    if (std.mem.eql(u8, s, "sand_lightweight") or std.mem.eql(u8, s, "SLW")) return .sand_lightweight;
    if (std.mem.eql(u8, s, "all_lightweight") or std.mem.eql(u8, s, "ALW")) return .all_lightweight;
    return null;
}

fn parseRebarGrade(s: []const u8) ?concrete.RebarGrade {
    if (std.mem.eql(u8, s, "40")) return .grade_40;
    if (std.mem.eql(u8, s, "60")) return .grade_60;
    if (std.mem.eql(u8, s, "80")) return .grade_80;
    return null;
}

fn parseBarSize(s: []const u8) ?concrete.BarSize {
    if (std.mem.eql(u8, s, "#3") or std.mem.eql(u8, s, "3")) return .no3;
    if (std.mem.eql(u8, s, "#4") or std.mem.eql(u8, s, "4")) return .no4;
    if (std.mem.eql(u8, s, "#5") or std.mem.eql(u8, s, "5")) return .no5;
    if (std.mem.eql(u8, s, "#6") or std.mem.eql(u8, s, "6")) return .no6;
    if (std.mem.eql(u8, s, "#7") or std.mem.eql(u8, s, "7")) return .no7;
    if (std.mem.eql(u8, s, "#8") or std.mem.eql(u8, s, "8")) return .no8;
    if (std.mem.eql(u8, s, "#9") or std.mem.eql(u8, s, "9")) return .no9;
    if (std.mem.eql(u8, s, "#10") or std.mem.eql(u8, s, "10")) return .no10;
    if (std.mem.eql(u8, s, "#11") or std.mem.eql(u8, s, "11")) return .no11;
    return null;
}

fn parseFootingShape(s: []const u8) ?spread_footing.FootingShape {
    if (std.mem.eql(u8, s, "square")) return .square;
    if (std.mem.eql(u8, s, "rectangular")) return .rectangular;
    if (std.mem.eql(u8, s, "circular")) return .circular;
    return null;
}

fn parseColumnShape(s: []const u8) ?spread_footing.ColumnShape {
    if (std.mem.eql(u8, s, "square")) return .square;
    if (std.mem.eql(u8, s, "rectangular")) return .rectangular;
    if (std.mem.eql(u8, s, "circular")) return .circular;
    return null;
}

fn parseColumnPosition(s: []const u8) ?aci318.ColumnPosition {
    if (std.mem.eql(u8, s, "interior")) return .interior;
    if (std.mem.eql(u8, s, "edge")) return .edge;
    if (std.mem.eql(u8, s, "corner")) return .corner;
    return null;
}

fn parseFootingInputs(bytes: []const u8) ParseError!spread_footing.Inputs {
    const parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, bytes, .{}) catch
        return error.InvalidJson;
    defer parsed.deinit();

    const root = parsed.value.object;

    var inp = spread_footing.Inputs{
        .length_ft = getFloat(root, "length_ft") orelse 0,
        .width_ft = getFloat(root, "width_ft") orelse 0,
        .thickness_in = getFloat(root, "thickness_in") orelse 18.0,
        .cover_in = getFloat(root, "cover_in") orelse 3.0,
        .c1_in = getFloat(root, "c1_in") orelse 18.0,
        .c2_in = getFloat(root, "c2_in") orelse 18.0,
        .axial_dead_lb = getFloat(root, "axial_dead_lb") orelse 0,
        .axial_live_lb = getFloat(root, "axial_live_lb") orelse 0,
        .axial_snow_lb = getFloat(root, "axial_snow_lb") orelse 0,
        .axial_wind_lb = getFloat(root, "axial_wind_lb") orelse 0,
        .axial_seismic_lb = getFloat(root, "axial_seismic_lb") orelse 0,
        .moment_x_dead_ft_lb = getFloat(root, "moment_x_dead_ft_lb") orelse 0,
        .moment_x_live_ft_lb = getFloat(root, "moment_x_live_ft_lb") orelse 0,
        .moment_x_wind_ft_lb = getFloat(root, "moment_x_wind_ft_lb") orelse 0,
        .moment_x_seismic_ft_lb = getFloat(root, "moment_x_seismic_ft_lb") orelse 0,
        .moment_y_dead_ft_lb = getFloat(root, "moment_y_dead_ft_lb") orelse 0,
        .moment_y_live_ft_lb = getFloat(root, "moment_y_live_ft_lb") orelse 0,
        .moment_y_wind_ft_lb = getFloat(root, "moment_y_wind_ft_lb") orelse 0,
        .moment_y_seismic_ft_lb = getFloat(root, "moment_y_seismic_ft_lb") orelse 0,
        .shear_x_dead_lb = getFloat(root, "shear_x_dead_lb") orelse 0,
        .shear_x_live_lb = getFloat(root, "shear_x_live_lb") orelse 0,
        .shear_x_wind_lb = getFloat(root, "shear_x_wind_lb") orelse 0,
        .shear_x_seismic_lb = getFloat(root, "shear_x_seismic_lb") orelse 0,
        .shear_y_dead_lb = getFloat(root, "shear_y_dead_lb") orelse 0,
        .shear_y_live_lb = getFloat(root, "shear_y_live_lb") orelse 0,
        .shear_y_wind_lb = getFloat(root, "shear_y_wind_lb") orelse 0,
        .shear_y_seismic_lb = getFloat(root, "shear_y_seismic_lb") orelse 0,
        .allowable_bearing_psf = getFloat(root, "allowable_bearing_psf") orelse 3000,
        .friction_coeff = getFloat(root, "friction_coeff") orelse 0.40,
        .soil_unit_weight_pcf = getFloat(root, "soil_unit_weight_pcf") orelse 110,
        .depth_to_bottom_ft = getFloat(root, "depth_to_bottom_ft") orelse 4.0,
    };

    if (getFloat(root, "overturning_fs")) |v| inp.overturning_fs = v;
    if (getFloat(root, "sliding_fs")) |v| inp.sliding_fs = v;
    if (root.get("include_self_weight")) |v| {
        if (v == .bool) inp.include_self_weight = v.bool;
    }
    if (getString(root, "footing_shape")) |s| {
        inp.footing_shape = parseFootingShape(s) orelse return error.UnknownFootingShape;
    }
    if (getString(root, "column_shape")) |s| {
        inp.column_shape = parseColumnShape(s) orelse return error.UnknownColumnShape;
    }
    if (getString(root, "column_position")) |s| {
        inp.column_position = parseColumnPosition(s) orelse return error.UnknownColumnPosition;
    }
    if (getString(root, "concrete_strength")) |s| {
        inp.concrete_strength = parseConcreteStrength(s) orelse return error.UnknownConcreteStrength;
    }
    if (getString(root, "concrete_type")) |s| {
        inp.concrete_type = parseConcreteType(s) orelse return error.UnknownConcreteType;
    }
    if (getString(root, "rebar_grade")) |s| {
        inp.rebar_grade = parseRebarGrade(s) orelse return error.UnknownRebarGrade;
    }
    if (getString(root, "bar_size")) |s| {
        inp.bar_size = parseBarSize(s) orelse return error.UnknownBarSize;
    }

    return inp;
}

fn statusStr(s: spread_footing.CheckStatus) []const u8 {
    return if (s == .pass) "pass" else "fail";
}

fn writeFootingOutputs(out: spread_footing.Outputs) !void {
    var stdout_buffer: [32768]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const w = &stdout_writer.interface;

    try w.print(
        \\{{
        \\  "module": "spread_footing",
        \\  "status": "{s}",
        \\  "geometry": {{
        \\    "footing_area_sf": {d:.2},
        \\    "effective_depth_in": {d:.4},
        \\    "self_weight_lb": {d:.1},
        \\    "overburden_lb": {d:.1}
        \\  }},
        \\  "bearing": {{
        \\    "service_axial_lb": {d:.1},
        \\    "q_max_psf": {d:.1},
        \\    "q_min_psf": {d:.1},
        \\    "eccentricity_x_in": {d:.3},
        \\    "eccentricity_y_in": {d:.3},
        \\    "kern_exceeded": {s},
        \\    "dcr": {d:.3},
        \\    "governing_combo": "{s}",
        \\    "status": "{s}"
        \\  }},
        \\
    , .{
        statusStr(out.overall_status),
        out.footing_area_sf,
        out.effective_depth_in,
        out.self_weight_lb,
        out.overburden_lb,
        out.service_axial_lb,
        out.q_max_psf,
        out.q_min_psf,
        out.eccentricity_x_in,
        out.eccentricity_y_in,
        if (out.kern_exceeded) "true" else "false",
        out.bearing_dcr,
        out.bearing_combo_name[0..out.bearing_combo_len],
        statusStr(out.bearing_status),
    });

    try w.print(
        \\  "one_way_shear": {{
        \\    "Vu_L_lb": {d:.1},
        \\    "Vu_B_lb": {d:.1},
        \\    "phi_Vc_lb": {d:.1},
        \\    "dcr": {d:.3},
        \\    "governing_combo": "{s}",
        \\    "status": "{s}"
        \\  }},
        \\  "two_way_shear": {{
        \\    "Vu_lb": {d:.1},
        \\    "bo_in": {d:.2},
        \\    "phi_Vc_lb": {d:.1},
        \\    "Vc1_lb": {d:.1},
        \\    "Vc2_lb": {d:.1},
        \\    "Vc3_lb": {d:.1},
        \\    "governing_eq": {d},
        \\    "dcr": {d:.3},
        \\    "governing_combo": "{s}",
        \\    "status": "{s}"
        \\  }},
        \\
    , .{
        out.vu_one_way_l_lb,
        out.vu_one_way_b_lb,
        out.phi_vc_one_way_lb,
        out.one_way_shear_dcr,
        out.one_way_combo_name[0..out.one_way_combo_len],
        statusStr(out.one_way_shear_status),
        out.vu_two_way_lb,
        out.bo_in,
        out.phi_vc_two_way_lb,
        out.vc1_lb,
        out.vc2_lb,
        out.vc3_lb,
        out.governing_vc_eq,
        out.two_way_shear_dcr,
        out.two_way_combo_name[0..out.two_way_combo_len],
        statusStr(out.two_way_shear_status),
    });

    try w.print(
        \\  "flexure": {{
        \\    "Mu_L_ft_lb": {d:.1},
        \\    "Mu_B_ft_lb": {d:.1},
        \\    "As_required_in2_per_ft": {d:.4},
        \\    "As_min_in2_per_ft": {d:.4},
        \\    "As_provided_in2_per_ft": {d:.4},
        \\    "bar_spacing_in": {d:.1},
        \\    "phi_Mn_ft_lb": {d:.1},
        \\    "dcr": {d:.3},
        \\    "governing_combo": "{s}",
        \\    "status": "{s}"
        \\  }},
        \\  "development": {{
        \\    "ld_required_in": {d:.2},
        \\    "ld_available_in": {d:.2},
        \\    "dcr": {d:.3},
        \\    "status": "{s}"
        \\  }},
        \\
    , .{
        out.mu_l_ft_lb,
        out.mu_b_ft_lb,
        out.as_required_in2_per_ft,
        out.as_min_in2_per_ft,
        out.as_provided_in2_per_ft,
        out.bar_spacing_in,
        out.phi_mn_ft_lb,
        out.flexure_dcr,
        out.flexure_combo_name[0..out.flexure_combo_len],
        statusStr(out.flexure_status),
        out.ld_required_in,
        out.ld_available_in,
        out.development_dcr,
        statusStr(out.development_status),
    });

    // Cap infinite FS values for valid JSON (inf = no driving force)
    const cap = 9999.0;
    try w.print(
        \\  "stability": {{
        \\    "overturning_fs_x": {d:.2},
        \\    "overturning_fs_y": {d:.2},
        \\    "sliding_fs_x": {d:.2},
        \\    "sliding_fs_y": {d:.2},
        \\    "overturning_status": "{s}",
        \\    "sliding_status": "{s}"
        \\  }}
        \\}}
        \\
    , .{
        @min(out.overturning_fs_x, cap),
        @min(out.overturning_fs_y, cap),
        @min(out.sliding_fs_x, cap),
        @min(out.sliding_fs_y, cap),
        statusStr(out.overturning_status),
        statusStr(out.sliding_status),
    });

    try w.flush();
}
