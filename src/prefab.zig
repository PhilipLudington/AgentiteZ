// prefab.zig
// Prefab System for AgentiteZ
// Entity templates with component data for spawning
//
// Features:
// - Prefab definition with component data
// - Prefab registry for caching loaded prefabs
// - Spawning with component overrides
// - Hierarchical prefabs (parent-child inheritance)
// - TOML-based prefab definitions

const std = @import("std");
const ecs = @import("ecs.zig");
const Entity = ecs.Entity;
const toml = @import("data/toml.zig");
const reflection = @import("ecs/reflection.zig");

// ============================================================================
// Component Value Types
// ============================================================================

/// Represents a single field value that can be stored in a prefab
pub const FieldValue = union(enum) {
    int: i64,
    uint: u64,
    float: f64,
    boolean: bool,
    string: []const u8,

    pub fn format(self: FieldValue, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .int => |v| try writer.print("{d}", .{v}),
            .uint => |v| try writer.print("{d}", .{v}),
            .float => |v| try writer.print("{d:.2}", .{v}),
            .boolean => |v| try writer.print("{}", .{v}),
            .string => |v| try writer.print("\"{s}\"", .{v}),
        }
    }
};

/// Represents component data as a map of field names to values
pub const ComponentData = struct {
    fields: std.StringHashMap(FieldValue),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ComponentData {
        return .{
            .fields = std.StringHashMap(FieldValue).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ComponentData) void {
        // Free string keys and values
        var iter = self.fields.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            if (entry.value_ptr.* == .string) {
                self.allocator.free(entry.value_ptr.string);
            }
        }
        self.fields.deinit();
    }

    pub fn clone(self: *const ComponentData, allocator: std.mem.Allocator) !ComponentData {
        var new_data = ComponentData.init(allocator);
        errdefer new_data.deinit();

        var iter = self.fields.iterator();
        while (iter.next()) |entry| {
            const key = try allocator.dupe(u8, entry.key_ptr.*);
            errdefer allocator.free(key);

            var value = entry.value_ptr.*;
            if (value == .string) {
                value = .{ .string = try allocator.dupe(u8, value.string) };
            }
            try new_data.fields.put(key, value);
        }

        return new_data;
    }

    pub fn setInt(self: *ComponentData, key: []const u8, value: i64) !void {
        const key_copy = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_copy);
        try self.fields.put(key_copy, .{ .int = value });
    }

    pub fn setUint(self: *ComponentData, key: []const u8, value: u64) !void {
        const key_copy = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_copy);
        try self.fields.put(key_copy, .{ .uint = value });
    }

    pub fn setFloat(self: *ComponentData, key: []const u8, value: f64) !void {
        const key_copy = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_copy);
        try self.fields.put(key_copy, .{ .float = value });
    }

    pub fn setBool(self: *ComponentData, key: []const u8, value: bool) !void {
        const key_copy = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_copy);
        try self.fields.put(key_copy, .{ .boolean = value });
    }

    pub fn setString(self: *ComponentData, key: []const u8, value: []const u8) !void {
        const key_copy = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_copy);
        const value_copy = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(value_copy);
        try self.fields.put(key_copy, .{ .string = value_copy });
    }

    pub fn getInt(self: *const ComponentData, key: []const u8) ?i64 {
        if (self.fields.get(key)) |value| {
            return switch (value) {
                .int => |v| v,
                .uint => |v| if (v <= std.math.maxInt(i64)) @as(i64, @intCast(v)) else null,
                else => null,
            };
        }
        return null;
    }

    pub fn getUint(self: *const ComponentData, key: []const u8) ?u64 {
        if (self.fields.get(key)) |value| {
            return switch (value) {
                .uint => |v| v,
                .int => |v| if (v >= 0) @as(u64, @intCast(v)) else null,
                else => null,
            };
        }
        return null;
    }

    pub fn getFloat(self: *const ComponentData, key: []const u8) ?f64 {
        if (self.fields.get(key)) |value| {
            return switch (value) {
                .float => |v| v,
                .int => |v| @as(f64, @floatFromInt(v)),
                .uint => |v| @as(f64, @floatFromInt(v)),
                else => null,
            };
        }
        return null;
    }

    pub fn getBool(self: *const ComponentData, key: []const u8) ?bool {
        if (self.fields.get(key)) |value| {
            return switch (value) {
                .boolean => |v| v,
                else => null,
            };
        }
        return null;
    }

    pub fn getString(self: *const ComponentData, key: []const u8) ?[]const u8 {
        if (self.fields.get(key)) |value| {
            return switch (value) {
                .string => |v| v,
                else => null,
            };
        }
        return null;
    }
};

// ============================================================================
// Prefab Definition
// ============================================================================

/// A prefab definition containing component data templates
pub const PrefabDefinition = struct {
    id: []const u8,
    parent_id: ?[]const u8,
    /// Map of component type name to component data
    components: std.StringHashMap(ComponentData),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, id: []const u8) !PrefabDefinition {
        return .{
            .id = try allocator.dupe(u8, id),
            .parent_id = null,
            .components = std.StringHashMap(ComponentData).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PrefabDefinition) void {
        self.allocator.free(self.id);
        if (self.parent_id) |parent| {
            self.allocator.free(parent);
        }

        // Free component data
        var iter = self.components.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit();
        }
        self.components.deinit();
    }

    /// Set the parent prefab ID for inheritance
    pub fn setParent(self: *PrefabDefinition, parent_id: []const u8) !void {
        if (self.parent_id) |old_parent| {
            self.allocator.free(old_parent);
        }
        self.parent_id = try self.allocator.dupe(u8, parent_id);
    }

    /// Add or get component data for a component type
    pub fn getOrCreateComponent(self: *PrefabDefinition, component_type: []const u8) !*ComponentData {
        if (self.components.getPtr(component_type)) |existing| {
            return existing;
        }

        const type_copy = try self.allocator.dupe(u8, component_type);
        errdefer self.allocator.free(type_copy);

        const component_data = ComponentData.init(self.allocator);
        try self.components.put(type_copy, component_data);

        return self.components.getPtr(component_type).?;
    }

    /// Check if prefab has a specific component type
    pub fn hasComponent(self: *const PrefabDefinition, component_type: []const u8) bool {
        return self.components.contains(component_type);
    }

    /// Get component data for a component type
    pub fn getComponent(self: *const PrefabDefinition, component_type: []const u8) ?*const ComponentData {
        return self.components.getPtr(component_type);
    }
};

// ============================================================================
// Component Factory
// ============================================================================

/// Function type for creating a component from ComponentData
pub const ComponentFactory = *const fn (data: *const ComponentData) ?*anyopaque;

/// Function type for applying a component to an entity
pub const ComponentApplier = *const fn (component_array: *anyopaque, entity: Entity, data: *const ComponentData) anyerror!void;

/// Function type for cleaning up a component array
pub const ComponentArrayDeinit = *const fn (component_array: *anyopaque) void;

/// Function type for getting a field value from a component
pub const FieldGetter = *const fn (component_ptr: *const anyopaque, field_name: []const u8) ?reflection.FieldValue;

/// Function type for setting a field value on a component
pub const FieldSetter = *const fn (component_ptr: *anyopaque, field_name: []const u8, value: reflection.FieldValue) bool;

/// Registration info for a component type
pub const ComponentTypeInfo = struct {
    name: []const u8,
    applier: ComponentApplier,
    component_array: *anyopaque,
    deinit_fn: ?ComponentArrayDeinit = null,
    // Reflection fields (optional for backward compatibility)
    metadata: ?*const reflection.ComponentTypeMetadata = null,
    getter: ?FieldGetter = null,
    setter: ?FieldSetter = null,
};

// ============================================================================
// Prefab Registry
// ============================================================================

/// Registry for caching and managing prefab definitions
pub const PrefabRegistry = struct {
    prefabs: std.StringHashMap(PrefabDefinition),
    component_types: std.StringHashMap(ComponentTypeInfo),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PrefabRegistry {
        return .{
            .prefabs = std.StringHashMap(PrefabDefinition).init(allocator),
            .component_types = std.StringHashMap(ComponentTypeInfo).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PrefabRegistry) void {
        // Free prefabs
        var prefab_iter = self.prefabs.iterator();
        while (prefab_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit();
        }
        self.prefabs.deinit();

        // Free component type names
        var type_iter = self.component_types.iterator();
        while (type_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.component_types.deinit();
    }

    /// Register a component type with its factory and array
    pub fn registerComponentType(
        self: *PrefabRegistry,
        comptime T: type,
        component_array: *ecs.ComponentArray(T),
    ) !void {
        const type_name = @typeName(T);

        // Create applier function for this type
        const Applier = struct {
            fn apply(array_ptr: *anyopaque, entity: Entity, data: *const ComponentData) !void {
                const array: *ecs.ComponentArray(T) = @ptrCast(@alignCast(array_ptr));
                const component = createComponent(T, data);
                try array.add(entity, component);
            }
        };

        const name_copy = try self.allocator.dupe(u8, type_name);
        errdefer self.allocator.free(name_copy);

        try self.component_types.put(name_copy, .{
            .name = name_copy,
            .applier = Applier.apply,
            .component_array = component_array,
        });
    }

    /// Register a component type with full reflection support
    /// This provides runtime field access via getter/setter functions
    pub fn registerComponentTypeWithReflection(
        self: *PrefabRegistry,
        comptime T: type,
        component_array: *ecs.ComponentArray(T),
    ) !void {
        const type_name = @typeName(T);

        // Generate metadata at comptime
        const metadata = comptime reflection.generateMetadata(T);

        // Create type-specific functions
        const Accessors = struct {
            fn apply(array_ptr: *anyopaque, entity: Entity, data: *const ComponentData) !void {
                const array: *ecs.ComponentArray(T) = @ptrCast(@alignCast(array_ptr));
                const component = createComponent(T, data);
                try array.add(entity, component);
            }

            fn getField(ptr: *const anyopaque, field_name: []const u8) ?reflection.FieldValue {
                const component: *const T = @ptrCast(@alignCast(ptr));
                inline for (@typeInfo(T).@"struct".fields) |field| {
                    if (std.mem.eql(u8, field.name, field_name)) {
                        return getFieldValue(T, component, field.name);
                    }
                }
                return null;
            }

            fn setField(ptr: *anyopaque, field_name: []const u8, value: reflection.FieldValue) bool {
                const component: *T = @ptrCast(@alignCast(ptr));
                inline for (@typeInfo(T).@"struct".fields) |field| {
                    if (std.mem.eql(u8, field.name, field_name)) {
                        return setFieldValue(T, component, field.name, value);
                    }
                }
                return false;
            }

            fn getFieldValue(comptime C: type, component: *const C, comptime field_name: []const u8) ?reflection.FieldValue {
                const FieldType = @TypeOf(@field(component.*, field_name));
                const val = @field(component.*, field_name);
                const kind = reflection.FieldKind.fromType(FieldType);

                return switch (kind) {
                    .int_signed => .{ .int = @intCast(val) },
                    .int_unsigned => .{ .uint = @intCast(val) },
                    .float => .{ .float = @floatCast(val) },
                    .boolean => .{ .boolean = val },
                    .entity => .{ .entity = val },
                    .optional_entity => .{ .optional_entity = val },
                    .vec2 => .{ .vec2 = .{ .x = val.x, .y = val.y } },
                    .@"enum" => .{ .enum_value = .{ .type_name = @typeName(FieldType), .value_name = @tagName(val) } },
                    else => null,
                };
            }

            fn setFieldValue(comptime C: type, component: *C, comptime field_name: []const u8, value: reflection.FieldValue) bool {
                const FieldType = @TypeOf(@field(component.*, field_name));
                const kind = reflection.FieldKind.fromType(FieldType);

                switch (kind) {
                    .int_signed => {
                        if (value == .int) {
                            @field(component.*, field_name) = @intCast(value.int);
                            return true;
                        } else if (value == .uint) {
                            @field(component.*, field_name) = @intCast(value.uint);
                            return true;
                        } else if (value == .float) {
                            @field(component.*, field_name) = @intFromFloat(value.float);
                            return true;
                        }
                    },
                    .int_unsigned => {
                        if (value == .uint) {
                            @field(component.*, field_name) = @intCast(value.uint);
                            return true;
                        } else if (value == .int and value.int >= 0) {
                            @field(component.*, field_name) = @intCast(value.int);
                            return true;
                        } else if (value == .float and value.float >= 0) {
                            @field(component.*, field_name) = @intFromFloat(value.float);
                            return true;
                        }
                    },
                    .float => {
                        if (value == .float) {
                            @field(component.*, field_name) = @floatCast(value.float);
                            return true;
                        } else if (value == .int) {
                            @field(component.*, field_name) = @floatFromInt(value.int);
                            return true;
                        } else if (value == .uint) {
                            @field(component.*, field_name) = @floatFromInt(value.uint);
                            return true;
                        }
                    },
                    .boolean => {
                        if (value == .boolean) {
                            @field(component.*, field_name) = value.boolean;
                            return true;
                        }
                    },
                    .entity => {
                        if (value == .entity) {
                            @field(component.*, field_name) = value.entity;
                            return true;
                        }
                    },
                    .optional_entity => {
                        if (value == .optional_entity) {
                            @field(component.*, field_name) = value.optional_entity;
                            return true;
                        } else if (value == .entity) {
                            @field(component.*, field_name) = value.entity;
                            return true;
                        }
                    },
                    else => {},
                }
                return false;
            }
        };

        const name_copy = try self.allocator.dupe(u8, type_name);
        errdefer self.allocator.free(name_copy);

        try self.component_types.put(name_copy, .{
            .name = name_copy,
            .applier = Accessors.apply,
            .component_array = component_array,
            .metadata = &metadata,
            .getter = Accessors.getField,
            .setter = Accessors.setField,
        });
    }

    /// Register a prefab definition
    pub fn registerPrefab(self: *PrefabRegistry, prefab: PrefabDefinition) !void {
        const id_copy = try self.allocator.dupe(u8, prefab.id);
        errdefer self.allocator.free(id_copy);

        // Clone the prefab
        var new_prefab = try PrefabDefinition.init(self.allocator, prefab.id);
        errdefer new_prefab.deinit();

        if (prefab.parent_id) |parent| {
            try new_prefab.setParent(parent);
        }

        var comp_iter = prefab.components.iterator();
        while (comp_iter.next()) |entry| {
            const type_copy = try self.allocator.dupe(u8, entry.key_ptr.*);
            errdefer self.allocator.free(type_copy);

            const data_clone = try entry.value_ptr.clone(self.allocator);
            try new_prefab.components.put(type_copy, data_clone);
        }

        // Free old entry if exists
        if (self.prefabs.fetchRemove(id_copy)) |old| {
            self.allocator.free(old.key);
            var old_prefab = old.value;
            old_prefab.deinit();
        }

        try self.prefabs.put(id_copy, new_prefab);
    }

    /// Get a prefab by ID
    pub fn getPrefab(self: *const PrefabRegistry, id: []const u8) ?*const PrefabDefinition {
        return self.prefabs.getPtr(id);
    }

    /// Check if a prefab exists
    pub fn hasPrefab(self: *const PrefabRegistry, id: []const u8) bool {
        return self.prefabs.contains(id);
    }

    /// Get the number of registered prefabs
    pub fn prefabCount(self: *const PrefabRegistry) usize {
        return self.prefabs.count();
    }

    /// Spawn an entity from a prefab
    pub fn spawn(self: *PrefabRegistry, entity_manager: *ecs.EntityManager, prefab_id: []const u8) !Entity {
        return self.spawnWithOverrides(entity_manager, prefab_id, null);
    }

    /// Spawn an entity from a prefab with component overrides
    pub fn spawnWithOverrides(
        self: *PrefabRegistry,
        entity_manager: *ecs.EntityManager,
        prefab_id: []const u8,
        overrides: ?*const std.StringHashMap(ComponentData),
    ) !Entity {
        const prefab = self.getPrefab(prefab_id) orelse return error.PrefabNotFound;

        // Create the entity
        const entity = try entity_manager.create();
        errdefer entity_manager.destroy(entity) catch {};

        // Collect all components (with inheritance)
        var merged_components = std.StringHashMap(ComponentData).init(self.allocator);
        defer {
            var iter = merged_components.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit();
            }
            merged_components.deinit();
        }

        // Apply parent prefab components first (recursive)
        try self.collectInheritedComponents(prefab, &merged_components);

        // Apply overrides if provided
        if (overrides) |ovr| {
            var ovr_iter = ovr.iterator();
            while (ovr_iter.next()) |entry| {
                if (merged_components.getPtr(entry.key_ptr.*)) |existing| {
                    // Merge override fields into existing component
                    var field_iter = entry.value_ptr.fields.iterator();
                    while (field_iter.next()) |field| {
                        const key = try self.allocator.dupe(u8, field.key_ptr.*);
                        var value = field.value_ptr.*;
                        if (value == .string) {
                            value = .{ .string = try self.allocator.dupe(u8, value.string) };
                        }
                        // Remove old key if exists
                        if (existing.fields.fetchRemove(key)) |old| {
                            self.allocator.free(old.key);
                            if (old.value == .string) {
                                self.allocator.free(old.value.string);
                            }
                        }
                        try existing.fields.put(key, value);
                    }
                } else {
                    // Add new component from override
                    const type_copy = try self.allocator.dupe(u8, entry.key_ptr.*);
                    const data_clone = try entry.value_ptr.clone(self.allocator);
                    try merged_components.put(type_copy, data_clone);
                }
            }
        }

        // Apply all components to entity
        var comp_iter = merged_components.iterator();
        while (comp_iter.next()) |entry| {
            if (self.component_types.get(entry.key_ptr.*)) |type_info| {
                try type_info.applier(type_info.component_array, entity, entry.value_ptr);
            }
            // Skip unknown component types silently
        }

        return entity;
    }

    /// Recursively collect components from parent prefabs
    fn collectInheritedComponents(
        self: *PrefabRegistry,
        prefab: *const PrefabDefinition,
        result: *std.StringHashMap(ComponentData),
    ) !void {
        // First, collect parent components
        if (prefab.parent_id) |parent_id| {
            if (self.getPrefab(parent_id)) |parent| {
                try self.collectInheritedComponents(parent, result);
            }
        }

        // Then apply this prefab's components (overwriting parent values)
        var comp_iter = prefab.components.iterator();
        while (comp_iter.next()) |entry| {
            if (result.getPtr(entry.key_ptr.*)) |existing| {
                // Merge fields into existing component
                var field_iter = entry.value_ptr.fields.iterator();
                while (field_iter.next()) |field| {
                    const key = try self.allocator.dupe(u8, field.key_ptr.*);
                    var value = field.value_ptr.*;
                    if (value == .string) {
                        value = .{ .string = try self.allocator.dupe(u8, value.string) };
                    }
                    // Remove old key if exists
                    if (existing.fields.fetchRemove(key)) |old| {
                        self.allocator.free(old.key);
                        if (old.value == .string) {
                            self.allocator.free(old.value.string);
                        }
                    }
                    try existing.fields.put(key, value);
                }
            } else {
                // Add new component
                const type_copy = try self.allocator.dupe(u8, entry.key_ptr.*);
                const data_clone = try entry.value_ptr.clone(self.allocator);
                try result.put(type_copy, data_clone);
            }
        }
    }

    /// Load prefabs from TOML content
    pub fn loadFromToml(self: *PrefabRegistry, content: []const u8) !usize {
        var loaded_count: usize = 0;
        var lines = std.mem.splitScalar(u8, content, '\n');

        var current_prefab: ?PrefabDefinition = null;
        var current_component: ?[]const u8 = null;

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");

            // Skip comments and empty lines
            if (trimmed.len == 0 or trimmed[0] == '#') continue;

            // Check for [[prefab]] section
            if (std.mem.eql(u8, trimmed, "[[prefab]]")) {
                // Save previous prefab if complete
                if (current_prefab) |*prefab| {
                    try self.registerPrefab(prefab.*);
                    prefab.deinit();
                    loaded_count += 1;
                }
                current_prefab = null;
                current_component = null;
                continue;
            }

            // Check for [prefab.component_name] section
            if (std.mem.startsWith(u8, trimmed, "[prefab.") and trimmed[trimmed.len - 1] == ']') {
                const component_name = trimmed[8 .. trimmed.len - 1];
                if (current_prefab) |*prefab| {
                    _ = try prefab.getOrCreateComponent(component_name);
                    current_component = component_name;
                }
                continue;
            }

            // Parse key-value pairs
            if (toml.parseKeyValue(trimmed)) |kv| {
                if (current_prefab == null) {
                    // We're still setting up the prefab header
                    if (std.mem.eql(u8, kv.key, "id")) {
                        const id = toml.trimQuotes(kv.value);
                        current_prefab = try PrefabDefinition.init(self.allocator, id);
                    }
                } else if (current_prefab) |*prefab| {
                    if (std.mem.eql(u8, kv.key, "id") and current_component == null) {
                        // ID already set
                    } else if (std.mem.eql(u8, kv.key, "parent") and current_component == null) {
                        const parent = toml.trimQuotes(kv.value);
                        if (parent.len > 0) {
                            try prefab.setParent(parent);
                        }
                    } else if (current_component) |comp_name| {
                        // Add field to current component
                        if (prefab.components.getPtr(comp_name)) |comp_data| {
                            try parseAndSetField(comp_data, kv.key, kv.value);
                        }
                    }
                }
            }
        }

        // Save last prefab
        if (current_prefab) |*prefab| {
            try self.registerPrefab(prefab.*);
            prefab.deinit();
            loaded_count += 1;
        }

        return loaded_count;
    }

    /// Load prefabs from a file
    pub fn loadFromFile(self: *PrefabRegistry, path: []const u8) !usize {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
        defer self.allocator.free(content);

        return self.loadFromToml(content);
    }
};

// ============================================================================
// Helper Functions
// ============================================================================

/// Parse a TOML value and set it in ComponentData
fn parseAndSetField(data: *ComponentData, key: []const u8, value: []const u8) !void {
    // Try to determine the type from the value
    if (std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "false")) {
        try data.setBool(key, toml.parseBool(value));
    } else if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
        try data.setString(key, toml.trimQuotes(value));
    } else if (std.mem.indexOf(u8, value, ".")) |_| {
        // Has decimal point, treat as float
        const f = toml.parseF32(value) catch return;
        try data.setFloat(key, @floatCast(f));
    } else {
        // Try as integer
        if (std.fmt.parseInt(i64, value, 10)) |i| {
            try data.setInt(key, i);
        } else |_| {
            // If all else fails, treat as string
            try data.setString(key, value);
        }
    }
}

/// Create a component instance from ComponentData
/// Uses comptime reflection to set fields
fn createComponent(comptime T: type, data: *const ComponentData) T {
    var component: T = undefined;

    // Initialize with default values if available
    inline for (@typeInfo(T).@"struct".fields) |field| {
        if (field.default_value) |default_ptr| {
            const default: *const field.type = @ptrCast(@alignCast(default_ptr));
            @field(component, field.name) = default.*;
        } else {
            // Set zero/null defaults for non-default fields
            @field(component, field.name) = switch (@typeInfo(field.type)) {
                .int, .comptime_int => 0,
                .float, .comptime_float => 0.0,
                .bool => false,
                .pointer => |ptr| if (ptr.size == .Slice) &[_]ptr.child{} else undefined,
                .optional => null,
                else => undefined,
            };
        }
    }

    // Apply values from ComponentData
    inline for (@typeInfo(T).@"struct".fields) |field| {
        if (data.fields.get(field.name)) |value| {
            switch (@typeInfo(field.type)) {
                .int => |int_info| {
                    if (int_info.signedness == .signed) {
                        if (value == .int) {
                            @field(component, field.name) = @intCast(value.int);
                        } else if (value == .uint) {
                            @field(component, field.name) = @intCast(value.uint);
                        }
                    } else {
                        if (value == .uint) {
                            @field(component, field.name) = @intCast(value.uint);
                        } else if (value == .int and value.int >= 0) {
                            @field(component, field.name) = @intCast(value.int);
                        }
                    }
                },
                .float => {
                    if (value == .float) {
                        @field(component, field.name) = @floatCast(value.float);
                    } else if (value == .int) {
                        @field(component, field.name) = @floatFromInt(value.int);
                    } else if (value == .uint) {
                        @field(component, field.name) = @floatFromInt(value.uint);
                    }
                },
                .bool => {
                    if (value == .boolean) {
                        @field(component, field.name) = value.boolean;
                    }
                },
                else => {},
            }
        }
    }

    return component;
}

// ============================================================================
// Tests
// ============================================================================

test "ComponentData - basic operations" {
    var data = ComponentData.init(std.testing.allocator);
    defer data.deinit();

    try data.setInt("health", 100);
    try data.setFloat("speed", 5.5);
    try data.setBool("active", true);
    try data.setString("name", "Player");

    try std.testing.expectEqual(@as(i64, 100), data.getInt("health").?);
    try std.testing.expectEqual(@as(f64, 5.5), data.getFloat("speed").?);
    try std.testing.expectEqual(true, data.getBool("active").?);
    try std.testing.expectEqualStrings("Player", data.getString("name").?);
}

test "ComponentData - clone" {
    var original = ComponentData.init(std.testing.allocator);
    defer original.deinit();

    try original.setInt("x", 10);
    try original.setString("name", "Test");

    var cloned = try original.clone(std.testing.allocator);
    defer cloned.deinit();

    try std.testing.expectEqual(@as(i64, 10), cloned.getInt("x").?);
    try std.testing.expectEqualStrings("Test", cloned.getString("name").?);
}

test "PrefabDefinition - basic operations" {
    var prefab = try PrefabDefinition.init(std.testing.allocator, "player");
    defer prefab.deinit();

    try std.testing.expectEqualStrings("player", prefab.id);
    try std.testing.expect(prefab.parent_id == null);

    // Add a component
    const pos_data = try prefab.getOrCreateComponent("Position");
    try pos_data.setFloat("x", 100.0);
    try pos_data.setFloat("y", 200.0);

    try std.testing.expect(prefab.hasComponent("Position"));
    try std.testing.expect(!prefab.hasComponent("Velocity"));

    // Set parent
    try prefab.setParent("base_entity");
    try std.testing.expectEqualStrings("base_entity", prefab.parent_id.?);
}

test "PrefabRegistry - register and get prefab" {
    var registry = PrefabRegistry.init(std.testing.allocator);
    defer registry.deinit();

    var prefab = try PrefabDefinition.init(std.testing.allocator, "enemy");
    defer prefab.deinit();

    const health_data = try prefab.getOrCreateComponent("Health");
    try health_data.setInt("current", 50);
    try health_data.setInt("max", 50);

    try registry.registerPrefab(prefab);

    try std.testing.expect(registry.hasPrefab("enemy"));
    try std.testing.expectEqual(@as(usize, 1), registry.prefabCount());

    const retrieved = registry.getPrefab("enemy").?;
    try std.testing.expectEqualStrings("enemy", retrieved.id);
}

test "PrefabRegistry - spawn entity" {
    var registry = PrefabRegistry.init(std.testing.allocator);
    defer registry.deinit();

    var entity_manager = ecs.EntityManager.init(std.testing.allocator);
    defer entity_manager.deinit();

    // Create a simple prefab
    var prefab = try PrefabDefinition.init(std.testing.allocator, "test_entity");
    defer prefab.deinit();

    const pos_data = try prefab.getOrCreateComponent("Position");
    try pos_data.setFloat("x", 10.0);
    try pos_data.setFloat("y", 20.0);

    try registry.registerPrefab(prefab);

    // Spawn entity (without component registration, components won't be added)
    const entity = try registry.spawn(&entity_manager, "test_entity");
    try std.testing.expect(entity_manager.isAlive(entity));
}

test "PrefabRegistry - hierarchical prefabs" {
    var registry = PrefabRegistry.init(std.testing.allocator);
    defer registry.deinit();

    // Create base prefab
    var base = try PrefabDefinition.init(std.testing.allocator, "base");
    defer base.deinit();

    const base_health = try base.getOrCreateComponent("Health");
    try base_health.setInt("max", 100);
    try base_health.setInt("current", 100);

    const base_pos = try base.getOrCreateComponent("Position");
    try base_pos.setFloat("x", 0.0);
    try base_pos.setFloat("y", 0.0);

    try registry.registerPrefab(base);

    // Create child prefab that inherits from base
    var child = try PrefabDefinition.init(std.testing.allocator, "goblin");
    defer child.deinit();

    try child.setParent("base");

    // Override health values
    const child_health = try child.getOrCreateComponent("Health");
    try child_health.setInt("max", 50);
    try child_health.setInt("current", 50);

    try registry.registerPrefab(child);

    // Verify parent is set
    const goblin = registry.getPrefab("goblin").?;
    try std.testing.expectEqualStrings("base", goblin.parent_id.?);
}

test "PrefabRegistry - load from TOML" {
    var registry = PrefabRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const toml_content =
        \\[[prefab]]
        \\id = "player"
        \\
        \\[prefab.Position]
        \\x = 100.0
        \\y = 200.0
        \\
        \\[prefab.Health]
        \\current = 100
        \\max = 100
        \\
        \\[[prefab]]
        \\id = "enemy"
        \\parent = "player"
        \\
        \\[prefab.Health]
        \\current = 50
        \\max = 50
    ;

    const count = try registry.loadFromToml(toml_content);
    try std.testing.expectEqual(@as(usize, 2), count);

    // Check player prefab
    const player = registry.getPrefab("player").?;
    try std.testing.expectEqualStrings("player", player.id);
    try std.testing.expect(player.parent_id == null);
    try std.testing.expect(player.hasComponent("Position"));
    try std.testing.expect(player.hasComponent("Health"));

    // Check enemy prefab
    const enemy = registry.getPrefab("enemy").?;
    try std.testing.expectEqualStrings("enemy", enemy.id);
    try std.testing.expectEqualStrings("player", enemy.parent_id.?);
}

test "PrefabRegistry - spawn with registered components" {
    const Position = struct {
        x: f32 = 0,
        y: f32 = 0,
    };

    const Health = struct {
        current: i32 = 100,
        max: i32 = 100,
    };

    var registry = PrefabRegistry.init(std.testing.allocator);
    defer registry.deinit();

    var entity_manager = ecs.EntityManager.init(std.testing.allocator);
    defer entity_manager.deinit();

    var positions = ecs.ComponentArray(Position).init(std.testing.allocator);
    defer positions.deinit();

    var healths = ecs.ComponentArray(Health).init(std.testing.allocator);
    defer healths.deinit();

    // Register component types
    try registry.registerComponentType(Position, &positions);
    try registry.registerComponentType(Health, &healths);

    // Create prefab
    var prefab = try PrefabDefinition.init(std.testing.allocator, "hero");
    defer prefab.deinit();

    const pos_data = try prefab.getOrCreateComponent(@typeName(Position));
    try pos_data.setFloat("x", 50.0);
    try pos_data.setFloat("y", 75.0);

    const health_data = try prefab.getOrCreateComponent(@typeName(Health));
    try health_data.setInt("current", 80);
    try health_data.setInt("max", 100);

    try registry.registerPrefab(prefab);

    // Spawn entity
    const entity = try registry.spawn(&entity_manager, "hero");
    try std.testing.expect(entity_manager.isAlive(entity));

    // Verify components were added
    const pos = try positions.get(entity);
    try std.testing.expectEqual(@as(f32, 50.0), pos.x);
    try std.testing.expectEqual(@as(f32, 75.0), pos.y);

    const health = try healths.get(entity);
    try std.testing.expectEqual(@as(i32, 80), health.current);
    try std.testing.expectEqual(@as(i32, 100), health.max);
}

test "createComponent - basic struct" {
    const TestComponent = struct {
        x: f32 = 0,
        y: f32 = 0,
        health: i32 = 100,
        active: bool = false,
    };

    var data = ComponentData.init(std.testing.allocator);
    defer data.deinit();

    try data.setFloat("x", 10.5);
    try data.setFloat("y", 20.5);
    try data.setInt("health", 50);
    try data.setBool("active", true);

    const component = createComponent(TestComponent, &data);
    try std.testing.expectEqual(@as(f32, 10.5), component.x);
    try std.testing.expectEqual(@as(f32, 20.5), component.y);
    try std.testing.expectEqual(@as(i32, 50), component.health);
    try std.testing.expectEqual(true, component.active);
}
