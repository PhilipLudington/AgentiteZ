// component_accessor.zig
// Runtime field access API for ECS Reflection
//
// Provides type-erased access to component fields via registered
// getter/setter functions. Works with PrefabRegistry to enable
// runtime introspection of entity components.

const std = @import("std");
const reflection = @import("reflection.zig");
const prefab = @import("../prefab.zig");

/// Validation result for component data
pub const ValidationResult = struct {
    valid: bool,
    missing_fields: []const []const u8,
    unknown_fields: []const []const u8,
    type_errors: []const []const u8,

    pub fn deinit(self: *ValidationResult, allocator: std.mem.Allocator) void {
        allocator.free(self.missing_fields);
        allocator.free(self.unknown_fields);
        allocator.free(self.type_errors);
    }
};

/// Provides runtime access to component fields via the PrefabRegistry
pub const ComponentAccessor = struct {
    registry: *const prefab.PrefabRegistry,

    pub fn init(registry: *const prefab.PrefabRegistry) ComponentAccessor {
        return .{ .registry = registry };
    }

    /// Get component metadata by type name
    pub fn getMetadata(self: *const ComponentAccessor, type_name: []const u8) ?*const reflection.ComponentTypeMetadata {
        if (self.registry.component_types.get(type_name)) |info| {
            return info.metadata;
        }
        return null;
    }

    /// Get component type info by type name
    pub fn getTypeInfo(self: *const ComponentAccessor, type_name: []const u8) ?prefab.ComponentTypeInfo {
        return self.registry.component_types.get(type_name);
    }

    /// Get all registered component type names
    pub fn getRegisteredTypes(self: *const ComponentAccessor, allocator: std.mem.Allocator) ![][]const u8 {
        var types = std.ArrayList([]const u8).init(allocator);
        errdefer {
            for (types.items) |t| allocator.free(t);
            types.deinit();
        }

        var iter = self.registry.component_types.iterator();
        while (iter.next()) |entry| {
            const name_copy = try allocator.dupe(u8, entry.key_ptr.*);
            try types.append(name_copy);
        }
        return types.toOwnedSlice();
    }

    /// Get the number of registered component types
    pub fn getRegisteredTypeCount(self: *const ComponentAccessor) usize {
        return self.registry.component_types.count();
    }

    /// Check if a component type is registered
    pub fn isTypeRegistered(self: *const ComponentAccessor, type_name: []const u8) bool {
        return self.registry.component_types.contains(type_name);
    }

    /// Check if a component type has reflection support
    pub fn hasReflection(self: *const ComponentAccessor, type_name: []const u8) bool {
        if (self.registry.component_types.get(type_name)) |info| {
            return info.metadata != null and info.getter != null and info.setter != null;
        }
        return false;
    }

    /// Get a field value from a component
    pub fn getFieldValue(
        self: *const ComponentAccessor,
        type_name: []const u8,
        component_ptr: *const anyopaque,
        field_name: []const u8,
    ) ?reflection.FieldValue {
        if (self.registry.component_types.get(type_name)) |info| {
            if (info.getter) |getter| {
                return getter(component_ptr, field_name);
            }
        }
        return null;
    }

    /// Set a field value on a component
    pub fn setFieldValue(
        self: *const ComponentAccessor,
        type_name: []const u8,
        component_ptr: *anyopaque,
        field_name: []const u8,
        value: reflection.FieldValue,
    ) bool {
        if (self.registry.component_types.get(type_name)) |info| {
            if (info.setter) |setter| {
                return setter(component_ptr, field_name, value);
            }
        }
        return false;
    }

    /// Check if a component type supports a field
    pub fn hasField(
        self: *const ComponentAccessor,
        type_name: []const u8,
        field_name: []const u8,
    ) bool {
        if (self.getMetadata(type_name)) |metadata| {
            return metadata.getField(field_name) != null;
        }
        return false;
    }

    /// Get the kind of a specific field
    pub fn getFieldKind(
        self: *const ComponentAccessor,
        type_name: []const u8,
        field_name: []const u8,
    ) ?reflection.FieldKind {
        if (self.getMetadata(type_name)) |metadata| {
            if (metadata.getField(field_name)) |field| {
                return field.kind;
            }
        }
        return null;
    }

    /// Get all field names for a component type
    pub fn getFieldNames(
        self: *const ComponentAccessor,
        type_name: []const u8,
        allocator: std.mem.Allocator,
    ) !?[][]const u8 {
        if (self.getMetadata(type_name)) |metadata| {
            var names = std.ArrayList([]const u8).init(allocator);
            errdefer {
                for (names.items) |n| allocator.free(n);
                names.deinit();
            }

            var iter = metadata.fieldIterator();
            while (iter.next()) |field| {
                const name_copy = try allocator.dupe(u8, field.name);
                try names.append(name_copy);
            }
            return names.toOwnedSlice();
        }
        return null;
    }

    /// Get all field values from a component as a hash map
    pub fn getAllFieldValues(
        self: *const ComponentAccessor,
        type_name: []const u8,
        component_ptr: *const anyopaque,
        allocator: std.mem.Allocator,
    ) !?std.StringHashMap(reflection.FieldValue) {
        const metadata = self.getMetadata(type_name) orelse return null;
        const info = self.registry.component_types.get(type_name) orelse return null;
        const getter = info.getter orelse return null;

        var result = std.StringHashMap(reflection.FieldValue).init(allocator);
        errdefer result.deinit();

        var iter = metadata.fieldIterator();
        while (iter.next()) |field| {
            if (getter(component_ptr, field.name)) |value| {
                const key_copy = try allocator.dupe(u8, field.name);
                try result.put(key_copy, value);
            }
        }

        return result;
    }

    /// Validate ComponentData against a component type schema
    pub fn validateComponentData(
        self: *const ComponentAccessor,
        type_name: []const u8,
        data: *const prefab.ComponentData,
        allocator: std.mem.Allocator,
    ) !ValidationResult {
        const metadata = self.getMetadata(type_name) orelse {
            var unknown = std.ArrayList([]const u8).init(allocator);
            try unknown.append(try allocator.dupe(u8, type_name));
            return .{
                .valid = false,
                .missing_fields = &.{},
                .unknown_fields = &.{},
                .type_errors = try unknown.toOwnedSlice(),
            };
        };

        var unknown_fields = std.ArrayList([]const u8).init(allocator);
        errdefer {
            for (unknown_fields.items) |f| allocator.free(f);
            unknown_fields.deinit();
        }

        var type_errors = std.ArrayList([]const u8).init(allocator);
        errdefer {
            for (type_errors.items) |e| allocator.free(e);
            type_errors.deinit();
        }

        // Check for unknown fields in data
        var data_iter = data.fields.iterator();
        while (data_iter.next()) |entry| {
            if (metadata.getField(entry.key_ptr.*) == null) {
                const field_copy = try allocator.dupe(u8, entry.key_ptr.*);
                try unknown_fields.append(field_copy);
            }
        }

        // Check field types (basic validation)
        var field_iter = metadata.fieldIterator();
        while (field_iter.next()) |field| {
            if (data.fields.get(field.name)) |value| {
                const compatible = isValueCompatible(field.kind, value);
                if (!compatible) {
                    const err_msg = try std.fmt.allocPrint(allocator, "Field '{s}' type mismatch", .{field.name});
                    try type_errors.append(err_msg);
                }
            }
        }

        const unknown_slice = try unknown_fields.toOwnedSlice();
        const type_err_slice = try type_errors.toOwnedSlice();

        return .{
            .valid = unknown_slice.len == 0 and type_err_slice.len == 0,
            .missing_fields = &.{}, // Not checking required fields for now
            .unknown_fields = unknown_slice,
            .type_errors = type_err_slice,
        };
    }
};

/// Check if a FieldValue is compatible with a FieldKind
fn isValueCompatible(kind: reflection.FieldKind, value: prefab.FieldValue) bool {
    return switch (kind) {
        .int_signed => value == .int or value == .uint,
        .int_unsigned => value == .uint or (value == .int and value.int >= 0),
        .float => value == .float or value == .int or value == .uint,
        .boolean => value == .boolean,
        .string => value == .string,
        else => true, // Allow other types without strict validation
    };
}

// ============================================================================
// Tests
// ============================================================================

test "ComponentAccessor - basic usage" {
    const allocator = std.testing.allocator;

    // Create a test registry
    var registry = prefab.PrefabRegistry.init(allocator);
    defer registry.deinit();

    // Create accessor
    const accessor = ComponentAccessor.init(&registry);

    // Initially no types registered
    try std.testing.expectEqual(@as(usize, 0), accessor.getRegisteredTypeCount());
}

test "ComponentAccessor - type registration check" {
    const allocator = std.testing.allocator;

    var registry = prefab.PrefabRegistry.init(allocator);
    defer registry.deinit();

    const accessor = ComponentAccessor.init(&registry);

    // Non-existent type
    try std.testing.expect(!accessor.isTypeRegistered("NonExistent"));
    try std.testing.expect(accessor.getMetadata("NonExistent") == null);
}

test "ComponentAccessor - getRegisteredTypes" {
    const allocator = std.testing.allocator;

    var registry = prefab.PrefabRegistry.init(allocator);
    defer registry.deinit();

    const accessor = ComponentAccessor.init(&registry);

    // Get types (empty)
    const types = try accessor.getRegisteredTypes(allocator);
    defer {
        for (types) |t| allocator.free(t);
        allocator.free(types);
    }

    try std.testing.expectEqual(@as(usize, 0), types.len);
}

test "isValueCompatible" {
    // Int signed accepts int and uint
    try std.testing.expect(isValueCompatible(.int_signed, .{ .int = 42 }));
    try std.testing.expect(isValueCompatible(.int_signed, .{ .uint = 42 }));
    try std.testing.expect(!isValueCompatible(.int_signed, .{ .float = 42.0 }));

    // Int unsigned accepts uint and non-negative int
    try std.testing.expect(isValueCompatible(.int_unsigned, .{ .uint = 42 }));
    try std.testing.expect(isValueCompatible(.int_unsigned, .{ .int = 42 }));
    try std.testing.expect(!isValueCompatible(.int_unsigned, .{ .int = -1 }));

    // Float accepts float, int, and uint
    try std.testing.expect(isValueCompatible(.float, .{ .float = 3.14 }));
    try std.testing.expect(isValueCompatible(.float, .{ .int = 42 }));
    try std.testing.expect(isValueCompatible(.float, .{ .uint = 42 }));

    // Boolean only accepts boolean
    try std.testing.expect(isValueCompatible(.boolean, .{ .boolean = true }));
    try std.testing.expect(!isValueCompatible(.boolean, .{ .int = 1 }));

    // String only accepts string
    try std.testing.expect(isValueCompatible(.string, .{ .string = "hello" }));
    try std.testing.expect(!isValueCompatible(.string, .{ .int = 42 }));
}
