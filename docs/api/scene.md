# Scene System

Level/scene loading and management with TOML definitions, entity spawning from prefabs, and scene lifecycle management.

## Overview

The Scene System provides structured level/scene management for games:

- **Scene Definitions** - TOML-based scene files with entity instances, asset references, and metadata
- **Scene Manager** - Central controller for loading, unloading, and transitioning between scenes
- **State Machine** - Lifecycle states (inactive, loading, active, unloading) with callbacks
- **Asset Tracking** - Reference tracking for textures, sounds, and other assets per scene
- **Entity Lifetime** - Entities owned by scenes are automatically destroyed on unload

## Quick Start

```zig
const scene = @import("agentitez").scene;
const prefab = @import("agentitez").prefab;
const ecs = @import("agentitez").ecs;

// Create managers
var entity_manager = ecs.EntityManager.init(allocator);
var prefab_registry = prefab.PrefabRegistry.init(allocator);
var scene_manager = scene.SceneManager.init(allocator);
defer scene_manager.deinit();

// Connect systems
scene_manager.setEntityManager(&entity_manager);
scene_manager.setPrefabRegistry(&prefab_registry);

// Register a scene
var level1 = try scene.SceneDefinition.init(allocator, "level1");
try level1.setName("Level 1");
try scene_manager.registerScene(level1);

// Load and activate
try scene_manager.loadScene("level1");
try scene_manager.setActiveScene("level1");

// Transition to another scene (unloads current, loads new)
try scene_manager.transitionTo("level2");

// Unload when done
try scene_manager.unloadScene("level2");
```

## Scene Definition Format (TOML)

Scenes are defined in TOML format:

```toml
[[scene]]
id = "level1"
name = "Forest Level"

[scene.assets]
texture = "textures/forest_bg.png"
music = "music/forest_theme.ogg"
prefab = "prefabs/enemies.toml"

[[scene.entity]]
prefab = "player"
name = "hero"

[scene.entity.Position]
x = 100.0
y = 200.0

[[scene.entity]]
prefab = "enemy_goblin"
name = "goblin1"

[scene.entity.Position]
x = 500.0
y = 200.0

[scene.entity.Health]
current = 30
max = 30

[[scene]]
id = "level2"
name = "Desert Level"

[scene.assets]
texture = "textures/desert_bg.png"
```

## Core Types

### SceneState

Scene lifecycle states:

```zig
pub const SceneState = enum {
    inactive,   // Scene not loaded
    loading,    // Scene being loaded (assets, entities)
    active,     // Scene fully loaded and active
    unloading,  // Scene being unloaded (entities destroyed)
};
```

### AssetType

Types of assets that can be referenced:

```zig
pub const AssetType = enum {
    texture,
    sound,
    music,
    font,
    prefab,
    tilemap,
    script,
    other,
};
```

### AssetReference

Reference to a required asset:

```zig
pub const AssetReference = struct {
    asset_type: AssetType,
    path: []const u8,
    required: bool,      // Whether scene fails to load without this
    loaded: bool,        // Whether asset has been loaded
};
```

### EntityInstance

Definition of an entity to spawn in a scene:

```zig
pub const EntityInstance = struct {
    name: ?[]const u8,           // Optional name for lookup
    prefab_id: []const u8,       // Prefab to spawn from
    overrides: StringHashMap(ComponentData),  // Component overrides
};

// Create entity instance
var entity = try EntityInstance.init(allocator, "player_prefab");
try entity.setName("hero");

// Add component overrides
const pos = try entity.getOrCreateOverride("Position");
try pos.setFloat("x", 100.0);
try pos.setFloat("y", 200.0);
```

### SceneDefinition

Scene template loaded from file:

```zig
pub const SceneDefinition = struct {
    id: []const u8,
    name: ?[]const u8,
    assets: ArrayList(AssetReference),
    entities: ArrayList(EntityInstance),
    metadata: StringHashMap([]const u8),
};

// Create scene definition
var scene_def = try SceneDefinition.init(allocator, "level1");
try scene_def.setName("Level 1");

// Add assets
try scene_def.addAsset(.texture, "textures/bg.png", true);
try scene_def.addAsset(.music, "music/theme.ogg", false);

// Add metadata
try scene_def.setMetadata("author", "GameDev");
try scene_def.setMetadata("version", "1.0");
```

### Scene

Runtime scene instance:

```zig
pub const Scene = struct {
    definition: *const SceneDefinition,
    state: SceneState,
    owned_entities: ArrayList(Entity),     // Auto-destroyed on unload
    named_entities: StringHashMap(Entity), // Name -> Entity lookup
    load_progress: f32,                    // 0.0 to 1.0
    error_message: ?[]const u8,            // Set if loading fails
};

// Query scene
const scene = manager.getScene("level1").?;
if (scene.state == .active) {
    // Get entity by name
    if (scene.getEntityByName("hero")) |hero| {
        // Use hero entity
    }

    // Check entity count
    const count = scene.entityCount();
}
```

### SceneManager

Central scene controller:

```zig
pub const SceneManager = struct {
    definitions: StringHashMap(SceneDefinition),
    scenes: StringHashMap(Scene),
    active_scene_id: ?[]const u8,
    prefab_registry: ?*PrefabRegistry,
    entity_manager: ?*EntityManager,
};
```

## SceneManager API

### Initialization

```zig
var manager = SceneManager.init(allocator);
defer manager.deinit();

// Connect to other systems
manager.setEntityManager(&entity_manager);
manager.setPrefabRegistry(&prefab_registry);
```

### Loading from Files

```zig
// Load from TOML content
const count = try manager.loadFromToml(toml_content);

// Load from file
const count = try manager.loadFromFile("scenes/levels.toml");
```

### Scene Registration

```zig
// Register programmatically created scene
var scene_def = try SceneDefinition.init(allocator, "custom");
try manager.registerScene(scene_def);

// Check if scene exists
if (manager.hasScene("level1")) {
    const def = manager.getDefinition("level1").?;
}
```

### Scene Loading/Unloading

```zig
// Load a scene (spawns entities)
try manager.loadScene("level1");

// Set as active scene
try manager.setActiveScene("level1");

// Get active scene
if (manager.getActiveScene()) |active| {
    // Work with active scene
}

// Unload scene (destroys owned entities)
try manager.unloadScene("level1");

// Transition (unload current, load new)
try manager.transitionTo("level2");
```

### State Callbacks

```zig
// Register callback for state changes
fn onStateChange(
    scene_id: []const u8,
    old_state: SceneState,
    new_state: SceneState,
    user_data: ?*anyopaque,
) void {
    if (new_state == .active) {
        std.debug.print("Scene {s} is now active\n", .{scene_id});
    }
}

try manager.registerCallback(onStateChange, null);
```

### Queries

```zig
// Count definitions and loaded scenes
const def_count = manager.definitionCount();
const loaded_count = manager.loadedSceneCount();

// Get mutable scene for modification
if (manager.getSceneMut("level1")) |scene| {
    // Modify scene
}
```

## Entity Spawning

When a scene loads, it spawns entities from prefabs:

```zig
// Scene definition with entity
var scene_def = try SceneDefinition.init(allocator, "test");

var entity_inst = try EntityInstance.init(allocator, "enemy");
try entity_inst.setName("boss");

// Override component values
const health = try entity_inst.getOrCreateOverride("Health");
try health.setInt("current", 500);
try health.setInt("max", 500);

try scene_def.entities.append(entity_inst);
try manager.registerScene(scene_def);

// When loaded, entity is spawned with overrides applied
try manager.loadScene("test");
const scene = manager.getScene("test").?;
const boss = scene.getEntityByName("boss").?;
```

## Scene Lifecycle

```
inactive -> loading -> active -> unloading -> inactive
    ^                                           |
    |___________________________________________|
```

1. **Inactive**: Scene is not loaded
2. **Loading**:
   - Assets being loaded
   - Entities being spawned from prefabs
   - `load_progress` updates (0.0 to 1.0)
3. **Active**:
   - Scene fully loaded
   - Entities are alive
   - Can be set as active scene
4. **Unloading**:
   - All owned entities destroyed
   - Scene removed from loaded scenes

## Error Handling

```zig
// Scene not found
manager.loadScene("nonexistent") catch |err| switch (err) {
    error.SceneNotFound => {
        // Handle missing scene
    },
    else => return err,
};

// Scene already loaded
manager.loadScene("level1") catch |err| switch (err) {
    error.SceneAlreadyLoaded => {
        // Already loaded, use existing
    },
    else => return err,
};

// Check for load errors
const scene = manager.getScene("level1").?;
if (scene.error_message) |msg| {
    std.debug.print("Load error: {s}\n", .{msg});
}
```

## Integration with Prefab System

The Scene System integrates with the Prefab System:

```zig
// Register prefabs first
var prefab_registry = prefab.PrefabRegistry.init(allocator);
try prefab_registry.loadFromFile("prefabs/entities.toml");

// Connect to scene manager
scene_manager.setPrefabRegistry(&prefab_registry);

// Scene entities reference prefab IDs
// [[scene.entity]]
// prefab = "player"  <- References prefab with id "player"
```

## Best Practices

1. **Asset Organization**: Group related assets per scene
2. **Named Entities**: Use names for entities you need to reference
3. **Prefab Reuse**: Define entities as prefabs, spawn in scenes with overrides
4. **State Callbacks**: Use callbacks for loading screens, transitions
5. **Error Handling**: Always check `error_message` after loading
6. **Clean Transitions**: Use `transitionTo` instead of manual load/unload

## Example: Complete Game Flow

```zig
// Initialize systems
var entity_manager = ecs.EntityManager.init(allocator);
var prefab_registry = prefab.PrefabRegistry.init(allocator);
var scene_manager = scene.SceneManager.init(allocator);

scene_manager.setEntityManager(&entity_manager);
scene_manager.setPrefabRegistry(&prefab_registry);

// Load game data
_ = try prefab_registry.loadFromFile("data/prefabs.toml");
_ = try scene_manager.loadFromFile("data/scenes.toml");

// Start with menu scene
try scene_manager.transitionTo("main_menu");

// Game loop
while (running) {
    if (start_game_pressed) {
        try scene_manager.transitionTo("level1");
    }

    if (player_died) {
        try scene_manager.transitionTo("game_over");
    }

    if (level_complete) {
        try scene_manager.transitionTo("level2");
    }
}

// Cleanup
scene_manager.deinit();
prefab_registry.deinit();
entity_manager.deinit();
```
