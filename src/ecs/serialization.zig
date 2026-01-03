// serialization.zig
// TOML serialization helpers for ECS components
//
// Provides utilities for serializing components to TOML format
// and converting between ComponentData and reflection.FieldValue.

const std = @import("std");
const reflection = @import("reflection.zig");
const prefab = @import("../prefab.zig");
const ComponentAccessor = @import("component_accessor.zig").ComponentAccessor;

// ============================================================================
// TOML Serialization
// ============================================================================

/// Serialize a component to TOML format using reflection
pub fn serializeComponent(
    accessor: *const ComponentAccessor,
    type_name: []const u8,
    component_ptr: *const anyopaque,
    writer: anytype,
) !void {
    const metadata = accessor.getMetadata(type_name) orelse return error.UnknownComponentType;
    const info = accessor.registry.component_types.get(type_name) orelse return error.UnknownComponentType;
    const getter = info.getter orelse return error.NoGetter;

    var iter = metadata.fieldIterator();
    while (iter.next()) |field| {
        // Only serialize serializable types
        if (!field.kind.isSerializable()) continue;

        if (getter(component_ptr, field.name)) |value| {
            try writeFieldToToml(writer, field.name, value);
        }
    }
}

/// Serialize a component to TOML with a section header
pub fn serializeComponentWithHeader(
    accessor: *const ComponentAccessor,
    type_name: []const u8,
    component_ptr: *const anyopaque,
    writer: anytype,
) !void {
    try writer.print("[{s}]\n", .{type_name});
    try serializeComponent(accessor, type_name, component_ptr, writer);
}

/// Write a single field value to TOML format
pub fn writeFieldToToml(writer: anytype, name: []const u8, value: reflection.FieldValue) !void {
    try writer.print("{s} = ", .{name});
    switch (value) {
        .int => |v| try writer.print("{d}\n", .{v}),
        .uint => |v| try writer.print("{d}\n", .{v}),
        .float => |v| try writer.print("{d:.6}\n", .{v}),
        .boolean => |v| try writer.print("{}\n", .{v}),
        .string => |v| {
            try writer.writeByte('"');
            try writeEscapedString(writer, v);
            try writer.writeAll("\"\n");
        },
        .vec2 => |v| try writer.print("{{ x = {d:.6}, y = {d:.6} }}\n", .{ v.x, v.y }),
        .entity => |v| try writer.print("{{ id = {d}, generation = {d} }}\n", .{ v.id, v.generation }),
        .optional_entity => |v| {
            if (v) |e| {
                try writer.print("{{ id = {d}, generation = {d} }}\n", .{ e.id, e.generation });
            } else {
                try writer.writeAll("null\n");
            }
        },
        .color => |v| try writer.print("{{ r = {d}, g = {d}, b = {d}, a = {d} }}\n", .{ v.r, v.g, v.b, v.a }),
        .enum_value => |v| try writer.print("\"{s}\"\n", .{v.value_name}),
    }
}

/// Write a string with TOML escape sequences
fn writeEscapedString(writer: anytype, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(c),
        }
    }
}

// ============================================================================
// ComponentData Conversion
// ============================================================================

/// Convert a prefab.FieldValue to reflection.FieldValue
pub fn prefabToReflectionValue(value: prefab.FieldValue) reflection.FieldValue {
    return switch (value) {
        .int => |v| .{ .int = v },
        .uint => |v| .{ .uint = v },
        .float => |v| .{ .float = v },
        .boolean => |v| .{ .boolean = v },
        .string => |v| .{ .string = v },
    };
}

/// Convert a reflection.FieldValue to prefab.FieldValue (if possible)
pub fn reflectionToPrefabValue(value: reflection.FieldValue) ?prefab.FieldValue {
    return switch (value) {
        .int => |v| .{ .int = v },
        .uint => |v| .{ .uint = v },
        .float => |v| .{ .float = v },
        .boolean => |v| .{ .boolean = v },
        .string => |v| .{ .string = v },
        // Extended types don't have direct prefab equivalents
        .vec2, .color, .entity, .optional_entity, .enum_value => null,
    };
}

/// Convert ComponentData fields to a map of reflection.FieldValue
pub fn componentDataToFieldValues(
    data: *const prefab.ComponentData,
    allocator: std.mem.Allocator,
) !std.StringHashMap(reflection.FieldValue) {
    var result = std.StringHashMap(reflection.FieldValue).init(allocator);
    errdefer result.deinit();

    var iter = data.fields.iterator();
    while (iter.next()) |entry| {
        const key_copy = try allocator.dupe(u8, entry.key_ptr.*);
        errdefer allocator.free(key_copy);

        const converted = prefabToReflectionValue(entry.value_ptr.*);
        try result.put(key_copy, converted);
    }

    return result;
}

/// Free a field values map created by componentDataToFieldValues
pub fn freeFieldValuesMap(map: *std.StringHashMap(reflection.FieldValue), allocator: std.mem.Allocator) void {
    var iter = map.iterator();
    while (iter.next()) |entry| {
        allocator.free(entry.key_ptr.*);
    }
    map.deinit();
}

// ============================================================================
// Deserialization Helpers
// ============================================================================

/// Parse a TOML value string into a prefab.FieldValue
pub fn parseTomlValue(value_str: []const u8) ?prefab.FieldValue {
    const trimmed = std.mem.trim(u8, value_str, " \t");

    // Boolean
    if (std.mem.eql(u8, trimmed, "true")) {
        return .{ .boolean = true };
    }
    if (std.mem.eql(u8, trimmed, "false")) {
        return .{ .boolean = false };
    }

    // String (quoted)
    if (trimmed.len >= 2 and trimmed[0] == '"' and trimmed[trimmed.len - 1] == '"') {
        return .{ .string = trimmed[1 .. trimmed.len - 1] };
    }

    // Try integer
    if (std.fmt.parseInt(i64, trimmed, 10)) |int_val| {
        if (int_val >= 0) {
            return .{ .uint = @intCast(int_val) };
        }
        return .{ .int = int_val };
    } else |_| {}

    // Try float
    if (std.fmt.parseFloat(f64, trimmed)) |float_val| {
        return .{ .float = float_val };
    } else |_| {}

    return null;
}

// ============================================================================
// Tests
// ============================================================================

test "writeFieldToToml - primitives" {
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    try writeFieldToToml(writer, "count", .{ .int = 42 });
    try std.testing.expectEqualStrings("count = 42\n", stream.getWritten());

    stream.reset();
    try writeFieldToToml(writer, "speed", .{ .float = 3.14 });
    try std.testing.expect(std.mem.startsWith(u8, stream.getWritten(), "speed = 3.14"));

    stream.reset();
    try writeFieldToToml(writer, "active", .{ .boolean = true });
    try std.testing.expectEqualStrings("active = true\n", stream.getWritten());
}

test "writeFieldToToml - string escaping" {
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    try writeFieldToToml(writer, "message", .{ .string = "hello\nworld" });
    try std.testing.expectEqualStrings("message = \"hello\\nworld\"\n", stream.getWritten());

    stream.reset();
    try writeFieldToToml(writer, "path", .{ .string = "C:\\Users" });
    try std.testing.expectEqualStrings("path = \"C:\\\\Users\"\n", stream.getWritten());
}

test "writeFieldToToml - extended types" {
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    const writer = stream.writer();

    try writeFieldToToml(writer, "position", .{ .vec2 = .{ .x = 10.0, .y = 20.0 } });
    try std.testing.expect(std.mem.startsWith(u8, stream.getWritten(), "position = { x = 10"));

    stream.reset();
    try writeFieldToToml(writer, "tint", .{ .color = .{ .r = 255, .g = 128, .b = 64, .a = 255 } });
    try std.testing.expectEqualStrings("tint = { r = 255, g = 128, b = 64, a = 255 }\n", stream.getWritten());
}

test "prefabToReflectionValue - conversions" {
    const int_val = prefab.FieldValue{ .int = 42 };
    const reflected_int = prefabToReflectionValue(int_val);
    try std.testing.expectEqual(@as(i64, 42), reflected_int.int);

    const float_val = prefab.FieldValue{ .float = 3.14 };
    const reflected_float = prefabToReflectionValue(float_val);
    try std.testing.expectEqual(@as(f64, 3.14), reflected_float.float);

    const bool_val = prefab.FieldValue{ .boolean = true };
    const reflected_bool = prefabToReflectionValue(bool_val);
    try std.testing.expectEqual(true, reflected_bool.boolean);
}

test "reflectionToPrefabValue - conversions" {
    const int_val = reflection.FieldValue{ .int = 42 };
    const prefab_int = reflectionToPrefabValue(int_val).?;
    try std.testing.expectEqual(@as(i64, 42), prefab_int.int);

    // Extended types return null
    const vec_val = reflection.FieldValue{ .vec2 = .{ .x = 1.0, .y = 2.0 } };
    try std.testing.expect(reflectionToPrefabValue(vec_val) == null);
}

test "parseTomlValue" {
    // Boolean
    try std.testing.expectEqual(prefab.FieldValue{ .boolean = true }, parseTomlValue("true").?);
    try std.testing.expectEqual(prefab.FieldValue{ .boolean = false }, parseTomlValue("false").?);

    // Integer
    const int_result = parseTomlValue("42").?;
    try std.testing.expectEqual(@as(u64, 42), int_result.uint);

    const neg_result = parseTomlValue("-10").?;
    try std.testing.expectEqual(@as(i64, -10), neg_result.int);

    // Float
    const float_result = parseTomlValue("3.14").?;
    try std.testing.expectEqual(@as(f64, 3.14), float_result.float);

    // String
    const str_result = parseTomlValue("\"hello\"").?;
    try std.testing.expectEqualStrings("hello", str_result.string);
}

test "componentDataToFieldValues" {
    const allocator = std.testing.allocator;

    var data = prefab.ComponentData.init(allocator);
    defer data.deinit();

    try data.setInt("health", 100);
    try data.setFloat("speed", 5.5);
    try data.setBool("active", true);

    var field_values = try componentDataToFieldValues(&data, allocator);
    defer freeFieldValuesMap(&field_values, allocator);

    try std.testing.expectEqual(@as(usize, 3), field_values.count());
    try std.testing.expectEqual(@as(i64, 100), field_values.get("health").?.int);
    try std.testing.expectEqual(@as(f64, 5.5), field_values.get("speed").?.float);
    try std.testing.expectEqual(true, field_values.get("active").?.boolean);
}
