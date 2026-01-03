// reflection.zig
// ECS Reflection System for AgentiteZ
// Runtime component introspection with comptime metadata generation
//
// Features:
// - Field metadata (name, type, offset, size)
// - FieldKind classification for serialization/UI
// - ComponentTypeMetadata for full type introspection
// - Comptime metadata generation via generateMetadata()

const std = @import("std");
const Entity = @import("entity.zig").Entity;

// ============================================================================
// Field Value Types (Extended)
// ============================================================================

/// Extended field value for reflection system
/// Supports more types than prefab.FieldValue for complete component representation
pub const FieldValue = union(enum) {
    // Basic types (compatible with prefab.FieldValue)
    int: i64,
    uint: u64,
    float: f64,
    boolean: bool,
    string: []const u8,

    // Extended types for full component support
    vec2: Vec2,
    color: Color,
    entity: Entity,
    optional_entity: ?Entity,

    // Enum stored as string tag
    enum_value: EnumValue,

    pub const Vec2 = struct { x: f32, y: f32 };
    pub const Color = struct { r: u8, g: u8, b: u8, a: u8 };
    pub const EnumValue = struct {
        type_name: []const u8,
        value_name: []const u8,
    };

    pub fn format(self: FieldValue, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .int => |v| try writer.print("{d}", .{v}),
            .uint => |v| try writer.print("{d}", .{v}),
            .float => |v| try writer.print("{d:.6}", .{v}),
            .boolean => |v| try writer.print("{}", .{v}),
            .string => |v| try writer.print("\"{s}\"", .{v}),
            .vec2 => |v| try writer.print("{{ x = {d:.6}, y = {d:.6} }}", .{ v.x, v.y }),
            .color => |v| try writer.print("{{ r = {d}, g = {d}, b = {d}, a = {d} }}", .{ v.r, v.g, v.b, v.a }),
            .entity => |v| try writer.print("{{ id = {d}, gen = {d} }}", .{ v.id, v.generation }),
            .optional_entity => |v| {
                if (v) |e| {
                    try writer.print("{{ id = {d}, gen = {d} }}", .{ e.id, e.generation });
                } else {
                    try writer.writeAll("null");
                }
            },
            .enum_value => |v| try writer.print("\"{s}\"", .{v.value_name}),
        }
    }

    /// Check if this value equals another
    pub fn eql(self: FieldValue, other: FieldValue) bool {
        const self_tag = std.meta.activeTag(self);
        const other_tag = std.meta.activeTag(other);
        if (self_tag != other_tag) return false;

        return switch (self) {
            .int => |v| v == other.int,
            .uint => |v| v == other.uint,
            .float => |v| v == other.float,
            .boolean => |v| v == other.boolean,
            .string => |v| std.mem.eql(u8, v, other.string),
            .vec2 => |v| v.x == other.vec2.x and v.y == other.vec2.y,
            .color => |v| v.r == other.color.r and v.g == other.color.g and v.b == other.color.b and v.a == other.color.a,
            .entity => |v| v.eql(other.entity),
            .optional_entity => |v| {
                if (v) |e| {
                    if (other.optional_entity) |oe| {
                        return e.eql(oe);
                    }
                    return false;
                }
                return other.optional_entity == null;
            },
            .enum_value => |v| std.mem.eql(u8, v.type_name, other.enum_value.type_name) and
                std.mem.eql(u8, v.value_name, other.enum_value.value_name),
        };
    }
};

// ============================================================================
// Field Kind Classification
// ============================================================================

/// Classification of field types for serialization and UI purposes
pub const FieldKind = enum {
    int_signed,
    int_unsigned,
    float,
    boolean,
    string,
    vec2,
    entity,
    optional_entity,
    color,
    @"enum",
    @"struct",
    array,
    optional,
    unknown,

    /// Determine FieldKind from a Zig type at comptime
    pub fn fromType(comptime T: type) FieldKind {
        const info = @typeInfo(T);
        return switch (info) {
            .int => |i| if (i.signedness == .signed) .int_signed else .int_unsigned,
            .float => .float,
            .bool => .boolean,
            .pointer => |p| blk: {
                if (p.size == .Slice and p.child == u8) {
                    break :blk .string;
                }
                break :blk .unknown;
            },
            .@"struct" => blk: {
                // Check for known special struct types
                if (T == Entity) {
                    break :blk .entity;
                }
                // Check for Vec2-like structs (x, y floats)
                if (@hasField(T, "x") and @hasField(T, "y")) {
                    const x_info = @typeInfo(@TypeOf(@as(T, undefined).x));
                    const y_info = @typeInfo(@TypeOf(@as(T, undefined).y));
                    if (x_info == .float and y_info == .float) {
                        break :blk .vec2;
                    }
                }
                // Check for Color-like structs (r, g, b, a)
                if (@hasField(T, "r") and @hasField(T, "g") and @hasField(T, "b") and @hasField(T, "a")) {
                    break :blk .color;
                }
                break :blk .@"struct";
            },
            .optional => |o| blk: {
                if (o.child == Entity) {
                    break :blk .optional_entity;
                }
                break :blk .optional;
            },
            .@"enum" => .@"enum",
            .array => .array,
            else => .unknown,
        };
    }

    /// Check if this kind is a primitive type
    pub fn isPrimitive(self: FieldKind) bool {
        return switch (self) {
            .int_signed, .int_unsigned, .float, .boolean, .string => true,
            else => false,
        };
    }

    /// Check if this kind is serializable to TOML
    pub fn isSerializable(self: FieldKind) bool {
        return switch (self) {
            .int_signed, .int_unsigned, .float, .boolean, .string, .vec2, .entity, .optional_entity, .color, .@"enum" => true,
            .@"struct", .array, .optional, .unknown => false,
        };
    }
};

// ============================================================================
// Field Metadata
// ============================================================================

/// Metadata for a single struct field
pub const FieldInfo = struct {
    /// Field name as appears in source code
    name: []const u8,

    /// Type name (e.g., "f32", "i32", "Entity")
    type_name: []const u8,

    /// Byte offset within the struct
    offset: usize,

    /// Size of the field in bytes
    size: usize,

    /// Field type category for serialization/UI
    kind: FieldKind,

    /// Default value if available (null if no default or unsupported type)
    default_value: ?FieldValue,

    /// Whether field is optional (?T)
    is_optional: bool,
};

// ============================================================================
// Component Type Metadata
// ============================================================================

/// Complete metadata for a component type
pub const ComponentTypeMetadata = struct {
    /// Type name from @typeName(T)
    name: []const u8,

    /// All field metadata
    fields: []const FieldInfo,

    /// Total size of the component struct
    size: usize,

    /// Alignment requirement
    alignment: usize,

    /// Number of fields
    field_count: usize,

    /// Get field info by name (runtime lookup)
    pub fn getField(self: *const ComponentTypeMetadata, name: []const u8) ?*const FieldInfo {
        for (self.fields) |*field| {
            if (std.mem.eql(u8, field.name, name)) {
                return field;
            }
        }
        return null;
    }

    /// Get field index by name
    pub fn getFieldIndex(self: *const ComponentTypeMetadata, name: []const u8) ?usize {
        for (self.fields, 0..) |field, i| {
            if (std.mem.eql(u8, field.name, name)) {
                return i;
            }
        }
        return null;
    }

    /// Iterate over all fields
    pub fn fieldIterator(self: *const ComponentTypeMetadata) FieldIterator {
        return .{ .fields = self.fields, .index = 0 };
    }

    /// Get list of field names
    pub fn getFieldNames(self: *const ComponentTypeMetadata) []const []const u8 {
        var names: [32][]const u8 = undefined;
        for (self.fields, 0..) |field, i| {
            if (i >= 32) break;
            names[i] = field.name;
        }
        return names[0..@min(self.field_count, 32)];
    }
};

/// Iterator for traversing component fields
pub const FieldIterator = struct {
    fields: []const FieldInfo,
    index: usize,

    pub fn next(self: *FieldIterator) ?*const FieldInfo {
        if (self.index >= self.fields.len) return null;
        const field = &self.fields[self.index];
        self.index += 1;
        return field;
    }

    pub fn reset(self: *FieldIterator) void {
        self.index = 0;
    }
};

// ============================================================================
// Comptime Metadata Generation
// ============================================================================

/// Generate ComponentTypeMetadata at comptime for a type
/// Returns a pointer to static metadata that can be stored at runtime
pub fn generateMetadata(comptime T: type) ComponentTypeMetadata {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") {
        @compileError("generateMetadata requires a struct type, got " ++ @typeName(T));
    }

    // Use a type-specific struct to hold static const data
    // This ensures the field_infos array has a stable address at runtime
    const MetaHolder = struct {
        const struct_info = @typeInfo(T).@"struct";
        const fields = struct_info.fields;

        const field_infos: [fields.len]FieldInfo = blk: {
            var infos: [fields.len]FieldInfo = undefined;
            for (fields, 0..) |field, i| {
                const default_val: ?FieldValue = if (field.default_value_ptr) |dv| dv_blk: {
                    const default: *const field.type = @ptrCast(@alignCast(dv));
                    break :dv_blk convertToFieldValue(field.type, default.*);
                } else null;

                const is_opt = @typeInfo(field.type) == .optional;

                infos[i] = .{
                    .name = field.name,
                    .type_name = @typeName(field.type),
                    .offset = @offsetOf(T, field.name),
                    .size = @sizeOf(field.type),
                    .kind = FieldKind.fromType(field.type),
                    .default_value = default_val,
                    .is_optional = is_opt,
                };
            }
            break :blk infos;
        };

        const metadata = ComponentTypeMetadata{
            .name = @typeName(T),
            .fields = &field_infos,
            .size = @sizeOf(T),
            .alignment = @alignOf(T),
            .field_count = fields.len,
        };
    };

    return MetaHolder.metadata;
}

/// Convert a value to FieldValue at comptime
fn convertToFieldValue(comptime T: type, value: T) ?FieldValue {
    const info = @typeInfo(T);
    return switch (info) {
        .int => |i| if (i.signedness == .signed)
            .{ .int = @intCast(value) }
        else
            .{ .uint = @intCast(value) },
        .float => .{ .float = @floatCast(value) },
        .bool => .{ .boolean = value },
        .@"struct" => blk: {
            if (T == Entity) {
                break :blk .{ .entity = value };
            }
            // Check for Vec2-like
            if (@hasField(T, "x") and @hasField(T, "y")) {
                break :blk .{ .vec2 = .{ .x = @floatCast(value.x), .y = @floatCast(value.y) } };
            }
            break :blk null;
        },
        .optional => |o| blk: {
            if (o.child == Entity) {
                break :blk .{ .optional_entity = value };
            }
            break :blk null;
        },
        .@"enum" => .{
            .enum_value = .{
                .type_name = @typeName(T),
                .value_name = @tagName(value),
            },
        },
        else => null,
    };
}

// ============================================================================
// Runtime Value Conversion Helpers
// ============================================================================

/// Convert a runtime FieldValue to a specific type (for setField operations)
pub fn fieldValueToType(comptime T: type, value: FieldValue) ?T {
    const kind = FieldKind.fromType(T);
    return switch (kind) {
        .int_signed => switch (value) {
            .int => |v| @intCast(v),
            .uint => |v| @intCast(v),
            .float => |v| @intFromFloat(v),
            else => null,
        },
        .int_unsigned => switch (value) {
            .int => |v| if (v >= 0) @intCast(v) else null,
            .uint => |v| @intCast(v),
            .float => |v| if (v >= 0) @intFromFloat(v) else null,
            else => null,
        },
        .float => switch (value) {
            .float => |v| @floatCast(v),
            .int => |v| @floatFromInt(v),
            .uint => |v| @floatFromInt(v),
            else => null,
        },
        .boolean => switch (value) {
            .boolean => |v| v,
            else => null,
        },
        .entity => switch (value) {
            .entity => |v| v,
            else => null,
        },
        .optional_entity => switch (value) {
            .optional_entity => |v| v,
            .entity => |v| v,
            else => null,
        },
        else => null,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "FieldKind.fromType - primitives" {
    try std.testing.expectEqual(FieldKind.int_signed, FieldKind.fromType(i32));
    try std.testing.expectEqual(FieldKind.int_signed, FieldKind.fromType(i64));
    try std.testing.expectEqual(FieldKind.int_unsigned, FieldKind.fromType(u32));
    try std.testing.expectEqual(FieldKind.int_unsigned, FieldKind.fromType(u8));
    try std.testing.expectEqual(FieldKind.float, FieldKind.fromType(f32));
    try std.testing.expectEqual(FieldKind.float, FieldKind.fromType(f64));
    try std.testing.expectEqual(FieldKind.boolean, FieldKind.fromType(bool));
    try std.testing.expectEqual(FieldKind.string, FieldKind.fromType([]const u8));
}

test "FieldKind.fromType - special types" {
    try std.testing.expectEqual(FieldKind.entity, FieldKind.fromType(Entity));
    try std.testing.expectEqual(FieldKind.optional_entity, FieldKind.fromType(?Entity));

    const Vec2 = struct { x: f32, y: f32 };
    try std.testing.expectEqual(FieldKind.vec2, FieldKind.fromType(Vec2));

    const Color = struct { r: u8, g: u8, b: u8, a: u8 };
    try std.testing.expectEqual(FieldKind.color, FieldKind.fromType(Color));

    const TestEnum = enum { a, b, c };
    try std.testing.expectEqual(FieldKind.@"enum", FieldKind.fromType(TestEnum));
}

test "FieldKind.isPrimitive" {
    try std.testing.expect(FieldKind.int_signed.isPrimitive());
    try std.testing.expect(FieldKind.float.isPrimitive());
    try std.testing.expect(FieldKind.boolean.isPrimitive());
    try std.testing.expect(!FieldKind.entity.isPrimitive());
    try std.testing.expect(!FieldKind.@"struct".isPrimitive());
}

test "generateMetadata - basic struct" {
    const Position = struct {
        x: f32 = 0,
        y: f32 = 0,
    };

    const metadata = comptime generateMetadata(Position);

    try std.testing.expectEqual(@as(usize, 2), metadata.field_count);
    try std.testing.expectEqual(@as(usize, 8), metadata.size);

    const x_field = metadata.getField("x").?;
    try std.testing.expectEqualStrings("x", x_field.name);
    try std.testing.expectEqual(FieldKind.float, x_field.kind);
    try std.testing.expectEqual(@as(usize, 0), x_field.offset);
    try std.testing.expectEqual(@as(usize, 4), x_field.size);
    try std.testing.expect(!x_field.is_optional);

    const y_field = metadata.getField("y").?;
    try std.testing.expectEqualStrings("y", y_field.name);
    try std.testing.expectEqual(@as(usize, 4), y_field.offset);
}

test "generateMetadata - default values" {
    const Health = struct {
        current: i32 = 100,
        max: i32 = 100,
        regenerating: bool = false,
    };

    const metadata = comptime generateMetadata(Health);

    try std.testing.expectEqual(@as(usize, 3), metadata.field_count);

    const current_field = metadata.getField("current").?;
    try std.testing.expect(current_field.default_value != null);
    try std.testing.expectEqual(@as(i64, 100), current_field.default_value.?.int);

    const regen_field = metadata.getField("regenerating").?;
    try std.testing.expect(regen_field.default_value != null);
    try std.testing.expectEqual(false, regen_field.default_value.?.boolean);
}

test "generateMetadata - mixed types" {
    const ComplexComponent = struct {
        id: u32 = 0,
        health: i32 = 100,
        speed: f32 = 1.0,
        active: bool = true,
    };

    const metadata = comptime generateMetadata(ComplexComponent);

    try std.testing.expectEqual(@as(usize, 4), metadata.field_count);

    try std.testing.expectEqual(FieldKind.int_unsigned, metadata.getField("id").?.kind);
    try std.testing.expectEqual(FieldKind.int_signed, metadata.getField("health").?.kind);
    try std.testing.expectEqual(FieldKind.float, metadata.getField("speed").?.kind);
    try std.testing.expectEqual(FieldKind.boolean, metadata.getField("active").?.kind);
}

test "generateMetadata - optional fields" {
    const OptionalComponent = struct {
        target: ?Entity = null,
        name: []const u8 = "",
    };

    const metadata = comptime generateMetadata(OptionalComponent);

    const target_field = metadata.getField("target").?;
    try std.testing.expect(target_field.is_optional);
    try std.testing.expectEqual(FieldKind.optional_entity, target_field.kind);

    const name_field = metadata.getField("name").?;
    try std.testing.expect(!name_field.is_optional);
    try std.testing.expectEqual(FieldKind.string, name_field.kind);
}

test "ComponentTypeMetadata.fieldIterator" {
    const Position = struct { x: f32, y: f32 };
    const metadata = comptime generateMetadata(Position);

    var iter = metadata.fieldIterator();
    var count: usize = 0;
    while (iter.next()) |_| {
        count += 1;
    }

    try std.testing.expectEqual(@as(usize, 2), count);

    // Test reset
    iter.reset();
    try std.testing.expect(iter.next() != null);
}

test "ComponentTypeMetadata.getFieldIndex" {
    const TestComp = struct { a: i32, b: f32, c: bool };
    const metadata = comptime generateMetadata(TestComp);

    try std.testing.expectEqual(@as(?usize, 0), metadata.getFieldIndex("a"));
    try std.testing.expectEqual(@as(?usize, 1), metadata.getFieldIndex("b"));
    try std.testing.expectEqual(@as(?usize, 2), metadata.getFieldIndex("c"));
    try std.testing.expectEqual(@as(?usize, null), metadata.getFieldIndex("nonexistent"));
}

test "FieldValue.format" {
    var buf: [128]u8 = undefined;

    const int_val = FieldValue{ .int = 42 };
    const int_str = try std.fmt.bufPrint(&buf, "{}", .{int_val});
    try std.testing.expectEqualStrings("42", int_str);

    const float_val = FieldValue{ .float = 3.14 };
    const float_str = try std.fmt.bufPrint(&buf, "{}", .{float_val});
    try std.testing.expect(std.mem.startsWith(u8, float_str, "3.14"));

    const bool_val = FieldValue{ .boolean = true };
    const bool_str = try std.fmt.bufPrint(&buf, "{}", .{bool_val});
    try std.testing.expectEqualStrings("true", bool_str);
}

test "FieldValue.eql" {
    const a = FieldValue{ .int = 42 };
    const b = FieldValue{ .int = 42 };
    const c = FieldValue{ .int = 43 };
    const d = FieldValue{ .float = 42.0 };

    try std.testing.expect(a.eql(b));
    try std.testing.expect(!a.eql(c));
    try std.testing.expect(!a.eql(d));

    const str1 = FieldValue{ .string = "hello" };
    const str2 = FieldValue{ .string = "hello" };
    const str3 = FieldValue{ .string = "world" };

    try std.testing.expect(str1.eql(str2));
    try std.testing.expect(!str1.eql(str3));
}

test "fieldValueToType - conversions" {
    // Int conversions
    const int_val = FieldValue{ .int = 42 };
    try std.testing.expectEqual(@as(?i32, 42), fieldValueToType(i32, int_val));
    try std.testing.expectEqual(@as(?u32, 42), fieldValueToType(u32, int_val));
    try std.testing.expectEqual(@as(?f32, 42.0), fieldValueToType(f32, int_val));

    // Float conversions
    const float_val = FieldValue{ .float = 3.5 };
    try std.testing.expectEqual(@as(?f32, 3.5), fieldValueToType(f32, float_val));
    try std.testing.expectEqual(@as(?i32, 3), fieldValueToType(i32, float_val));

    // Bool
    const bool_val = FieldValue{ .boolean = true };
    try std.testing.expectEqual(@as(?bool, true), fieldValueToType(bool, bool_val));

    // Entity
    const entity_val = FieldValue{ .entity = Entity.init(5, 2) };
    const result = fieldValueToType(Entity, entity_val);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u32, 5), result.?.id);
    try std.testing.expectEqual(@as(u32, 2), result.?.generation);
}

test "generateMetadata - vec2 default value" {
    const Vec2 = struct { x: f32, y: f32 };
    const Transform = struct {
        position: Vec2 = .{ .x = 10.0, .y = 20.0 },
        scale: f32 = 1.0,
    };

    const metadata = comptime generateMetadata(Transform);

    const pos_field = metadata.getField("position").?;
    try std.testing.expectEqual(FieldKind.vec2, pos_field.kind);
    try std.testing.expect(pos_field.default_value != null);

    const default_vec = pos_field.default_value.?.vec2;
    try std.testing.expectEqual(@as(f32, 10.0), default_vec.x);
    try std.testing.expectEqual(@as(f32, 20.0), default_vec.y);
}

test "generateMetadata - enum default value" {
    const State = enum { idle, moving, attacking };
    const Unit = struct {
        state: State = .idle,
        health: i32 = 100,
    };

    const metadata = comptime generateMetadata(Unit);

    const state_field = metadata.getField("state").?;
    try std.testing.expectEqual(FieldKind.@"enum", state_field.kind);
    try std.testing.expect(state_field.default_value != null);
    try std.testing.expectEqualStrings("idle", state_field.default_value.?.enum_value.value_name);
}
