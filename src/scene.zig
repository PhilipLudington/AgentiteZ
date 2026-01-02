// scene.zig
// Scene System for AgentiteZ
// Level/scene loading and management
//
// Features:
// - Scene file format with entity definitions (TOML-based)
// - Scene manager for loading/unloading scenes
// - Scene state machine (inactive, loading, active, unloading)
// - Asset reference tracking per scene
// - Entity lifetime tied to scene

const std = @import("std");
const ecs = @import("ecs.zig");
const Entity = ecs.Entity;
const prefab = @import("prefab.zig");
const toml = @import("data/toml.zig");

// ============================================================================
// Scene State
// ============================================================================

/// Scene lifecycle states
pub const SceneState = enum {
    /// Scene is not loaded
    inactive,
    /// Scene is being loaded (assets, entities being created)
    loading,
    /// Scene is fully loaded and active
    active,
    /// Scene is being unloaded (entities being destroyed)
    unloading,
};

// ============================================================================
// Asset Reference
// ============================================================================

/// Types of assets that can be referenced by a scene
pub const AssetType = enum {
    texture,
    sound,
    music,
    font,
    prefab,
    tilemap,
    script,
    other,

    pub fn fromString(s: []const u8) AssetType {
        const map = std.StaticStringMap(AssetType).initComptime(.{
            .{ "texture", .texture },
            .{ "sound", .sound },
            .{ "music", .music },
            .{ "font", .font },
            .{ "prefab", .prefab },
            .{ "tilemap", .tilemap },
            .{ "script", .script },
        });
        return map.get(s) orelse .other;
    }
};

/// Reference to an asset required by a scene
pub const AssetReference = struct {
    asset_type: AssetType,
    path: []const u8,
    /// Whether this asset is required (vs optional)
    required: bool,
    /// Whether this asset has been loaded
    loaded: bool,

    pub fn init(asset_type: AssetType, path: []const u8, required: bool) AssetReference {
        return .{
            .asset_type = asset_type,
            .path = path,
            .required = required,
            .loaded = false,
        };
    }
};

// ============================================================================
// Entity Instance Definition
// ============================================================================

/// Definition of an entity instance in a scene
pub const EntityInstance = struct {
    /// Optional name for this entity instance
    name: ?[]const u8,
    /// Prefab ID to spawn from
    prefab_id: []const u8,
    /// Component overrides (key = component type name)
    overrides: std.StringHashMap(prefab.ComponentData),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, prefab_id: []const u8) !EntityInstance {
        return .{
            .name = null,
            .prefab_id = try allocator.dupe(u8, prefab_id),
            .overrides = std.StringHashMap(prefab.ComponentData).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *EntityInstance) void {
        self.allocator.free(self.prefab_id);
        if (self.name) |name| {
            self.allocator.free(name);
        }
        var iter = self.overrides.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit();
        }
        self.overrides.deinit();
    }

    pub fn setName(self: *EntityInstance, name: []const u8) !void {
        if (self.name) |old_name| {
            self.allocator.free(old_name);
        }
        self.name = try self.allocator.dupe(u8, name);
    }

    /// Get or create component override data
    pub fn getOrCreateOverride(self: *EntityInstance, component_type: []const u8) !*prefab.ComponentData {
        if (self.overrides.getPtr(component_type)) |existing| {
            return existing;
        }

        const type_copy = try self.allocator.dupe(u8, component_type);
        errdefer self.allocator.free(type_copy);

        const data = prefab.ComponentData.init(self.allocator);
        try self.overrides.put(type_copy, data);

        return self.overrides.getPtr(component_type).?;
    }
};

// ============================================================================
// Scene Definition
// ============================================================================

/// Scene definition loaded from file
pub const SceneDefinition = struct {
    id: []const u8,
    name: ?[]const u8,
    /// Asset references required by this scene
    assets: std.ArrayList(AssetReference),
    /// Entity instances to spawn
    entities: std.ArrayList(EntityInstance),
    /// Scene metadata (arbitrary key-value pairs)
    metadata: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, id: []const u8) !SceneDefinition {
        return .{
            .id = try allocator.dupe(u8, id),
            .name = null,
            .assets = std.ArrayList(AssetReference).init(allocator),
            .entities = std.ArrayList(EntityInstance).init(allocator),
            .metadata = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SceneDefinition) void {
        self.allocator.free(self.id);
        if (self.name) |name| {
            self.allocator.free(name);
        }

        // Free assets
        for (self.assets.items) |*asset| {
            self.allocator.free(asset.path);
        }
        self.assets.deinit();

        // Free entity instances
        for (self.entities.items) |*entity| {
            entity.deinit();
        }
        self.entities.deinit();

        // Free metadata
        var meta_iter = self.metadata.iterator();
        while (meta_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.metadata.deinit();
    }

    pub fn setName(self: *SceneDefinition, name: []const u8) !void {
        if (self.name) |old_name| {
            self.allocator.free(old_name);
        }
        self.name = try self.allocator.dupe(u8, name);
    }

    /// Add an asset reference to this scene
    pub fn addAsset(self: *SceneDefinition, asset_type: AssetType, path: []const u8, required: bool) !void {
        const path_copy = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(path_copy);
        try self.assets.append(.{
            .asset_type = asset_type,
            .path = path_copy,
            .required = required,
            .loaded = false,
        });
    }

    /// Add an entity instance to spawn
    pub fn addEntity(self: *SceneDefinition, entity: EntityInstance) !void {
        try self.entities.append(entity);
    }

    /// Set metadata value
    pub fn setMetadata(self: *SceneDefinition, key: []const u8, value: []const u8) !void {
        const key_copy = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_copy);
        const value_copy = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(value_copy);

        if (self.metadata.fetchRemove(key_copy)) |old| {
            self.allocator.free(old.key);
            self.allocator.free(old.value);
        }

        try self.metadata.put(key_copy, value_copy);
    }

    /// Get metadata value
    pub fn getMetadata(self: *const SceneDefinition, key: []const u8) ?[]const u8 {
        return self.metadata.get(key);
    }
};

// ============================================================================
// Scene Instance
// ============================================================================

/// Runtime scene instance
pub const Scene = struct {
    definition: *const SceneDefinition,
    state: SceneState,
    /// Entities owned by this scene (destroyed when scene unloads)
    owned_entities: std.ArrayList(Entity),
    /// Named entities for easy lookup
    named_entities: std.StringHashMap(Entity),
    /// Loading progress (0.0 to 1.0)
    load_progress: f32,
    /// Error message if loading failed
    error_message: ?[]const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, definition: *const SceneDefinition) Scene {
        return .{
            .definition = definition,
            .state = .inactive,
            .owned_entities = std.ArrayList(Entity).init(allocator),
            .named_entities = std.StringHashMap(Entity).init(allocator),
            .load_progress = 0.0,
            .error_message = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Scene) void {
        self.owned_entities.deinit();
        var iter = self.named_entities.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.named_entities.deinit();
        if (self.error_message) |msg| {
            self.allocator.free(msg);
        }
    }

    /// Get an entity by name
    pub fn getEntityByName(self: *const Scene, name: []const u8) ?Entity {
        return self.named_entities.get(name);
    }

    /// Check if scene is in a loaded state (loading, active, or unloading)
    pub fn isLoaded(self: *const Scene) bool {
        return self.state != .inactive;
    }

    /// Get the number of entities owned by this scene
    pub fn entityCount(self: *const Scene) usize {
        return self.owned_entities.items.len;
    }
};

// ============================================================================
// Scene Manager
// ============================================================================

/// Callback for scene state changes
pub const SceneCallback = *const fn (scene_id: []const u8, old_state: SceneState, new_state: SceneState, user_data: ?*anyopaque) void;

/// Manager for loading, unloading, and transitioning between scenes
pub const SceneManager = struct {
    /// Registered scene definitions
    definitions: std.StringHashMap(SceneDefinition),
    /// Active scene instances
    scenes: std.StringHashMap(Scene),
    /// Currently active scene ID (only one scene can be "primary" active)
    active_scene_id: ?[]const u8,
    /// Prefab registry for spawning entities
    prefab_registry: ?*prefab.PrefabRegistry,
    /// Entity manager for creating/destroying entities
    entity_manager: ?*ecs.EntityManager,
    /// State change callbacks
    callbacks: std.ArrayList(struct { callback: SceneCallback, user_data: ?*anyopaque }),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SceneManager {
        return .{
            .definitions = std.StringHashMap(SceneDefinition).init(allocator),
            .scenes = std.StringHashMap(Scene).init(allocator),
            .active_scene_id = null,
            .prefab_registry = null,
            .entity_manager = null,
            .callbacks = std.ArrayList(struct { callback: SceneCallback, user_data: ?*anyopaque }).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SceneManager) void {
        // Clean up scenes
        var scene_iter = self.scenes.iterator();
        while (scene_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit();
        }
        self.scenes.deinit();

        // Clean up definitions
        var def_iter = self.definitions.iterator();
        while (def_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit();
        }
        self.definitions.deinit();

        self.callbacks.deinit();

        if (self.active_scene_id) |id| {
            self.allocator.free(id);
        }
    }

    /// Set the prefab registry for entity spawning
    pub fn setPrefabRegistry(self: *SceneManager, registry: *prefab.PrefabRegistry) void {
        self.prefab_registry = registry;
    }

    /// Set the entity manager for entity creation/destruction
    pub fn setEntityManager(self: *SceneManager, manager: *ecs.EntityManager) void {
        self.entity_manager = manager;
    }

    /// Register a state change callback
    pub fn registerCallback(self: *SceneManager, callback: SceneCallback, user_data: ?*anyopaque) !void {
        try self.callbacks.append(.{ .callback = callback, .user_data = user_data });
    }

    /// Fire state change callbacks
    fn fireCallbacks(self: *SceneManager, scene_id: []const u8, old_state: SceneState, new_state: SceneState) void {
        for (self.callbacks.items) |cb| {
            cb.callback(scene_id, old_state, new_state, cb.user_data);
        }
    }

    /// Register a scene definition
    pub fn registerScene(self: *SceneManager, definition: SceneDefinition) !void {
        const id_copy = try self.allocator.dupe(u8, definition.id);
        errdefer self.allocator.free(id_copy);

        // Clone the definition
        var new_def = try SceneDefinition.init(self.allocator, definition.id);
        errdefer new_def.deinit();

        if (definition.name) |name| {
            try new_def.setName(name);
        }

        // Clone assets
        for (definition.assets.items) |asset| {
            try new_def.addAsset(asset.asset_type, asset.path, asset.required);
        }

        // Clone entities
        for (definition.entities.items) |entity| {
            var new_entity = try EntityInstance.init(self.allocator, entity.prefab_id);
            if (entity.name) |name| {
                try new_entity.setName(name);
            }
            // Clone overrides
            var ovr_iter = entity.overrides.iterator();
            while (ovr_iter.next()) |entry| {
                const ovr_data = try new_entity.getOrCreateOverride(entry.key_ptr.*);
                var field_iter = entry.value_ptr.fields.iterator();
                while (field_iter.next()) |field| {
                    const key = try self.allocator.dupe(u8, field.key_ptr.*);
                    var value = field.value_ptr.*;
                    if (value == .string) {
                        value = .{ .string = try self.allocator.dupe(u8, value.string) };
                    }
                    try ovr_data.fields.put(key, value);
                }
            }
            try new_def.entities.append(new_entity);
        }

        // Clone metadata
        var meta_iter = definition.metadata.iterator();
        while (meta_iter.next()) |entry| {
            try new_def.setMetadata(entry.key_ptr.*, entry.value_ptr.*);
        }

        // Remove old definition if exists
        if (self.definitions.fetchRemove(id_copy)) |old| {
            self.allocator.free(old.key);
            var old_def = old.value;
            old_def.deinit();
        }

        try self.definitions.put(id_copy, new_def);
    }

    /// Check if a scene definition exists
    pub fn hasScene(self: *const SceneManager, id: []const u8) bool {
        return self.definitions.contains(id);
    }

    /// Get a scene definition
    pub fn getDefinition(self: *const SceneManager, id: []const u8) ?*const SceneDefinition {
        return self.definitions.getPtr(id);
    }

    /// Get an active scene instance
    pub fn getScene(self: *const SceneManager, id: []const u8) ?*const Scene {
        return self.scenes.getPtr(id);
    }

    /// Get a mutable active scene instance
    pub fn getSceneMut(self: *SceneManager, id: []const u8) ?*Scene {
        return self.scenes.getPtr(id);
    }

    /// Get the currently active scene
    pub fn getActiveScene(self: *const SceneManager) ?*const Scene {
        if (self.active_scene_id) |id| {
            return self.getScene(id);
        }
        return null;
    }

    /// Load a scene (creates entities from prefabs)
    pub fn loadScene(self: *SceneManager, scene_id: []const u8) !void {
        const definition = self.definitions.getPtr(scene_id) orelse return error.SceneNotFound;

        // Check if already loaded
        if (self.scenes.contains(scene_id)) {
            return error.SceneAlreadyLoaded;
        }

        const id_copy = try self.allocator.dupe(u8, scene_id);
        errdefer self.allocator.free(id_copy);

        // Create scene instance
        var scene = Scene.init(self.allocator, definition);
        errdefer scene.deinit();

        // Transition to loading state
        scene.state = .loading;
        self.fireCallbacks(scene_id, .inactive, .loading);

        // Spawn entities from prefabs
        if (self.prefab_registry) |registry| {
            if (self.entity_manager) |entity_manager| {
                const total_entities = definition.entities.items.len;
                for (definition.entities.items, 0..) |entity_def, i| {
                    // Spawn entity with overrides
                    const overrides: ?*const std.StringHashMap(prefab.ComponentData) = if (entity_def.overrides.count() > 0)
                        &entity_def.overrides
                    else
                        null;

                    const entity = registry.spawnWithOverrides(entity_manager, entity_def.prefab_id, overrides) catch |err| {
                        scene.error_message = try std.fmt.allocPrint(self.allocator, "Failed to spawn entity from prefab '{s}': {}", .{ entity_def.prefab_id, err });
                        scene.state = .inactive;
                        self.fireCallbacks(scene_id, .loading, .inactive);
                        return err;
                    };

                    try scene.owned_entities.append(entity);

                    // Register named entity
                    if (entity_def.name) |name| {
                        const name_copy = try self.allocator.dupe(u8, name);
                        try scene.named_entities.put(name_copy, entity);
                    }

                    // Update progress
                    if (total_entities > 0) {
                        scene.load_progress = @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(total_entities));
                    }
                }
            }
        }

        // Transition to active state
        scene.state = .active;
        scene.load_progress = 1.0;
        self.fireCallbacks(scene_id, .loading, .active);

        try self.scenes.put(id_copy, scene);
    }

    /// Unload a scene (destroys all owned entities)
    pub fn unloadScene(self: *SceneManager, scene_id: []const u8) !void {
        const scene = self.scenes.getPtr(scene_id) orelse return error.SceneNotLoaded;

        if (scene.state == .unloading) {
            return error.SceneAlreadyUnloading;
        }

        const old_state = scene.state;

        // Transition to unloading state
        scene.state = .unloading;
        self.fireCallbacks(scene_id, old_state, .unloading);

        // Destroy all owned entities
        if (self.entity_manager) |entity_manager| {
            for (scene.owned_entities.items) |entity| {
                entity_manager.destroy(entity) catch {};
            }
        }

        // Clear active scene if this was it
        if (self.active_scene_id) |active_id| {
            if (std.mem.eql(u8, active_id, scene_id)) {
                self.allocator.free(active_id);
                self.active_scene_id = null;
            }
        }

        // Fire callback for transition to inactive
        self.fireCallbacks(scene_id, .unloading, .inactive);

        // Remove scene instance
        if (self.scenes.fetchRemove(scene_id)) |removed| {
            self.allocator.free(removed.key);
            var scene_to_deinit = removed.value;
            scene_to_deinit.deinit();
        }
    }

    /// Set a scene as the active (primary) scene
    pub fn setActiveScene(self: *SceneManager, scene_id: []const u8) !void {
        if (!self.scenes.contains(scene_id)) {
            return error.SceneNotLoaded;
        }

        // Free old active scene ID
        if (self.active_scene_id) |old_id| {
            self.allocator.free(old_id);
        }

        self.active_scene_id = try self.allocator.dupe(u8, scene_id);
    }

    /// Transition from current scene to a new scene (unload old, load new)
    pub fn transitionTo(self: *SceneManager, scene_id: []const u8) !void {
        // Unload current active scene if any
        if (self.active_scene_id) |current_id| {
            // Make a copy since unloadScene may free active_scene_id
            const current_copy = try self.allocator.dupe(u8, current_id);
            defer self.allocator.free(current_copy);
            try self.unloadScene(current_copy);
        }

        // Load and activate new scene
        try self.loadScene(scene_id);
        try self.setActiveScene(scene_id);
    }

    /// Load scene definitions from TOML content
    pub fn loadFromToml(self: *SceneManager, content: []const u8) !usize {
        var loaded_count: usize = 0;
        var lines = std.mem.splitScalar(u8, content, '\n');

        var current_scene: ?SceneDefinition = null;
        var current_entity: ?EntityInstance = null;
        var current_override: ?[]const u8 = null;
        var in_assets_section = false;

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");

            // Skip comments and empty lines
            if (trimmed.len == 0 or trimmed[0] == '#') continue;

            // Check for [[scene]] section
            if (std.mem.eql(u8, trimmed, "[[scene]]")) {
                // Save previous entity if any
                if (current_entity) |*entity| {
                    if (current_scene) |*scene| {
                        try scene.entities.append(entity.*);
                    } else {
                        entity.deinit();
                    }
                }
                current_entity = null;
                current_override = null;

                // Save previous scene if complete
                if (current_scene) |*scene| {
                    try self.registerScene(scene.*);
                    scene.deinit();
                    loaded_count += 1;
                }
                current_scene = null;
                in_assets_section = false;
                continue;
            }

            // Check for [[scene.entity]] section
            if (std.mem.eql(u8, trimmed, "[[scene.entity]]")) {
                // Save previous entity if any
                if (current_entity) |*entity| {
                    if (current_scene) |*scene| {
                        try scene.entities.append(entity.*);
                    } else {
                        entity.deinit();
                    }
                }
                current_entity = null;
                current_override = null;
                in_assets_section = false;
                continue;
            }

            // Check for [scene.assets] section
            if (std.mem.eql(u8, trimmed, "[scene.assets]")) {
                in_assets_section = true;
                current_override = null;
                continue;
            }

            // Check for [scene.entity.ComponentName] section
            if (std.mem.startsWith(u8, trimmed, "[scene.entity.") and trimmed[trimmed.len - 1] == ']') {
                const component_name = trimmed[14 .. trimmed.len - 1];
                current_override = component_name;
                in_assets_section = false;
                continue;
            }

            // Check for [scene.metadata] section
            if (std.mem.eql(u8, trimmed, "[scene.metadata]")) {
                in_assets_section = false;
                current_override = null;
                continue;
            }

            // Parse key-value pairs
            if (toml.parseKeyValue(trimmed)) |kv| {
                if (current_scene == null) {
                    // Scene header
                    if (std.mem.eql(u8, kv.key, "id")) {
                        const id = toml.trimQuotes(kv.value);
                        current_scene = try SceneDefinition.init(self.allocator, id);
                    }
                } else if (current_scene) |*scene| {
                    if (current_entity != null and current_override != null) {
                        // Entity component override
                        if (current_override) |comp_name| {
                            if (current_entity) |*entity| {
                                const ovr_data = try entity.getOrCreateOverride(comp_name);
                                try parseAndSetField(ovr_data, kv.key, kv.value, self.allocator);
                            }
                        }
                    } else if (current_entity != null) {
                        // Entity definition
                        if (current_entity) |*entity| {
                            if (std.mem.eql(u8, kv.key, "name")) {
                                try entity.setName(toml.trimQuotes(kv.value));
                            }
                            // prefab is already set when [[scene.entity]] is encountered
                        }
                    } else if (in_assets_section) {
                        // Asset definition: type = "path"
                        const asset_type = AssetType.fromString(kv.key);
                        const path = toml.trimQuotes(kv.value);
                        try scene.addAsset(asset_type, path, true);
                    } else {
                        // Scene-level properties
                        if (std.mem.eql(u8, kv.key, "name")) {
                            try scene.setName(toml.trimQuotes(kv.value));
                        } else if (std.mem.eql(u8, kv.key, "prefab")) {
                            // Starting a new entity with prefab
                            const prefab_id = toml.trimQuotes(kv.value);
                            current_entity = try EntityInstance.init(self.allocator, prefab_id);
                        }
                    }
                }
            }
        }

        // Save last entity
        if (current_entity) |*entity| {
            if (current_scene) |*scene| {
                try scene.entities.append(entity.*);
            } else {
                entity.deinit();
            }
        }

        // Save last scene
        if (current_scene) |*scene| {
            try self.registerScene(scene.*);
            scene.deinit();
            loaded_count += 1;
        }

        return loaded_count;
    }

    /// Load scene definitions from a file
    pub fn loadFromFile(self: *SceneManager, path: []const u8) !usize {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
        defer self.allocator.free(content);

        return self.loadFromToml(content);
    }

    /// Get the number of registered scene definitions
    pub fn definitionCount(self: *const SceneManager) usize {
        return self.definitions.count();
    }

    /// Get the number of loaded scenes
    pub fn loadedSceneCount(self: *const SceneManager) usize {
        return self.scenes.count();
    }
};

// ============================================================================
// Helper Functions
// ============================================================================

/// Parse a TOML value and set it in ComponentData
fn parseAndSetField(data: *prefab.ComponentData, key: []const u8, value: []const u8, allocator: std.mem.Allocator) !void {
    _ = allocator;
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

// ============================================================================
// Tests
// ============================================================================

test "SceneDefinition - basic operations" {
    var scene = try SceneDefinition.init(std.testing.allocator, "test_scene");
    defer scene.deinit();

    try std.testing.expectEqualStrings("test_scene", scene.id);
    try std.testing.expect(scene.name == null);

    try scene.setName("Test Scene");
    try std.testing.expectEqualStrings("Test Scene", scene.name.?);

    // Add asset
    try scene.addAsset(.texture, "textures/player.png", true);
    try std.testing.expectEqual(@as(usize, 1), scene.assets.items.len);

    // Add metadata
    try scene.setMetadata("author", "test");
    try std.testing.expectEqualStrings("test", scene.getMetadata("author").?);
}

test "EntityInstance - basic operations" {
    var entity = try EntityInstance.init(std.testing.allocator, "player_prefab");
    defer entity.deinit();

    try std.testing.expectEqualStrings("player_prefab", entity.prefab_id);
    try std.testing.expect(entity.name == null);

    try entity.setName("player1");
    try std.testing.expectEqualStrings("player1", entity.name.?);

    // Add override
    const pos_override = try entity.getOrCreateOverride("Position");
    try pos_override.setFloat("x", 100.0);
    try pos_override.setFloat("y", 200.0);

    try std.testing.expectEqual(@as(f64, 100.0), pos_override.getFloat("x").?);
}

test "SceneManager - register and get scene" {
    var manager = SceneManager.init(std.testing.allocator);
    defer manager.deinit();

    var scene = try SceneDefinition.init(std.testing.allocator, "level1");
    defer scene.deinit();

    try scene.setName("Level 1");
    try scene.addAsset(.texture, "bg.png", true);

    try manager.registerScene(scene);

    try std.testing.expect(manager.hasScene("level1"));
    try std.testing.expectEqual(@as(usize, 1), manager.definitionCount());

    const retrieved = manager.getDefinition("level1").?;
    try std.testing.expectEqualStrings("level1", retrieved.id);
    try std.testing.expectEqualStrings("Level 1", retrieved.name.?);
}

test "SceneManager - load and unload scene" {
    var manager = SceneManager.init(std.testing.allocator);
    defer manager.deinit();

    var entity_manager = ecs.EntityManager.init(std.testing.allocator);
    defer entity_manager.deinit();

    var prefab_registry = prefab.PrefabRegistry.init(std.testing.allocator);
    defer prefab_registry.deinit();

    manager.setEntityManager(&entity_manager);
    manager.setPrefabRegistry(&prefab_registry);

    // Register a simple prefab
    var player_prefab = try prefab.PrefabDefinition.init(std.testing.allocator, "player");
    defer player_prefab.deinit();
    try prefab_registry.registerPrefab(player_prefab);

    // Register scene with entity
    var scene = try SceneDefinition.init(std.testing.allocator, "test");
    defer scene.deinit();

    var entity_inst = try EntityInstance.init(std.testing.allocator, "player");
    try entity_inst.setName("hero");
    try scene.entities.append(entity_inst);

    try manager.registerScene(scene);

    // Load scene
    try manager.loadScene("test");
    try std.testing.expectEqual(@as(usize, 1), manager.loadedSceneCount());

    const loaded = manager.getScene("test").?;
    try std.testing.expectEqual(SceneState.active, loaded.state);
    try std.testing.expectEqual(@as(usize, 1), loaded.entityCount());
    try std.testing.expect(loaded.getEntityByName("hero") != null);

    // Unload scene
    try manager.unloadScene("test");
    try std.testing.expectEqual(@as(usize, 0), manager.loadedSceneCount());
}

test "SceneManager - transition between scenes" {
    var manager = SceneManager.init(std.testing.allocator);
    defer manager.deinit();

    var entity_manager = ecs.EntityManager.init(std.testing.allocator);
    defer entity_manager.deinit();

    var prefab_registry = prefab.PrefabRegistry.init(std.testing.allocator);
    defer prefab_registry.deinit();

    manager.setEntityManager(&entity_manager);
    manager.setPrefabRegistry(&prefab_registry);

    // Register empty scenes
    var scene1 = try SceneDefinition.init(std.testing.allocator, "scene1");
    defer scene1.deinit();
    try manager.registerScene(scene1);

    var scene2 = try SceneDefinition.init(std.testing.allocator, "scene2");
    defer scene2.deinit();
    try manager.registerScene(scene2);

    // Transition to scene1
    try manager.transitionTo("scene1");
    try std.testing.expect(manager.getActiveScene() != null);
    try std.testing.expectEqualStrings("scene1", manager.active_scene_id.?);

    // Transition to scene2
    try manager.transitionTo("scene2");
    try std.testing.expectEqualStrings("scene2", manager.active_scene_id.?);
    try std.testing.expectEqual(@as(usize, 1), manager.loadedSceneCount());
}

test "SceneManager - load from TOML" {
    var manager = SceneManager.init(std.testing.allocator);
    defer manager.deinit();

    const toml_content =
        \\[[scene]]
        \\id = "level1"
        \\name = "Level 1"
        \\
        \\[scene.assets]
        \\texture = "bg.png"
        \\music = "level1.ogg"
        \\
        \\[[scene]]
        \\id = "level2"
        \\name = "Level 2"
    ;

    const count = try manager.loadFromToml(toml_content);
    try std.testing.expectEqual(@as(usize, 2), count);

    const level1 = manager.getDefinition("level1").?;
    try std.testing.expectEqualStrings("Level 1", level1.name.?);
    try std.testing.expectEqual(@as(usize, 2), level1.assets.items.len);

    const level2 = manager.getDefinition("level2").?;
    try std.testing.expectEqualStrings("Level 2", level2.name.?);
}

test "SceneManager - state callbacks" {
    var manager = SceneManager.init(std.testing.allocator);
    defer manager.deinit();

    var entity_manager = ecs.EntityManager.init(std.testing.allocator);
    defer entity_manager.deinit();

    var prefab_registry = prefab.PrefabRegistry.init(std.testing.allocator);
    defer prefab_registry.deinit();

    manager.setEntityManager(&entity_manager);
    manager.setPrefabRegistry(&prefab_registry);

    // Track state changes
    var callback_count: usize = 0;
    const Counter = struct {
        fn callback(_: []const u8, _: SceneState, _: SceneState, user_data: ?*anyopaque) void {
            const counter: *usize = @ptrCast(@alignCast(user_data.?));
            counter.* += 1;
        }
    };

    try manager.registerCallback(Counter.callback, &callback_count);

    var scene = try SceneDefinition.init(std.testing.allocator, "test");
    defer scene.deinit();
    try manager.registerScene(scene);

    // Load scene - should trigger inactive->loading and loading->active
    try manager.loadScene("test");
    try std.testing.expectEqual(@as(usize, 2), callback_count);

    // Unload scene - should trigger active->unloading and unloading->inactive
    try manager.unloadScene("test");
    try std.testing.expectEqual(@as(usize, 4), callback_count);
}

test "AssetType - fromString" {
    try std.testing.expectEqual(AssetType.texture, AssetType.fromString("texture"));
    try std.testing.expectEqual(AssetType.sound, AssetType.fromString("sound"));
    try std.testing.expectEqual(AssetType.music, AssetType.fromString("music"));
    try std.testing.expectEqual(AssetType.other, AssetType.fromString("unknown"));
}
