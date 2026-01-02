# Prefab System

Entity templates with component data for spawning (`src/prefab.zig`).

## Features

- **Prefab definitions** - Templates storing component data by type name
- **TOML loading** - Load prefabs from TOML configuration files
- **Prefab registry** - Cache and manage multiple prefab definitions
- **Component registration** - Type-safe component factory pattern
- **Spawning** - Create entities from prefabs with automatic component addition
- **Overrides** - Modify component values when spawning
- **Hierarchical prefabs** - Parent-child inheritance for prefab composition

## Usage

### Basic Setup

```zig
const prefab = @import("AgentiteZ").prefab;
const ecs = @import("AgentiteZ").ecs;

// Initialize registry
var registry = prefab.PrefabRegistry.init(allocator);
defer registry.deinit();

// Initialize ECS
var entity_manager = ecs.EntityManager.init(allocator);
defer entity_manager.deinit();
```

### Defining Components

```zig
const Position = struct {
    x: f32 = 0,
    y: f32 = 0,
};

const Health = struct {
    current: i32 = 100,
    max: i32 = 100,
};

// Component arrays for ECS
var positions = ecs.ComponentArray(Position).init(allocator);
defer positions.deinit();

var healths = ecs.ComponentArray(Health).init(allocator);
defer healths.deinit();

// Register component types with the registry
try registry.registerComponentType(Position, &positions);
try registry.registerComponentType(Health, &healths);
```

### Creating Prefabs Programmatically

```zig
// Create a prefab definition
var player_prefab = try prefab.PrefabDefinition.init(allocator, "player");
defer player_prefab.deinit();

// Add Position component data
const pos_data = try player_prefab.getOrCreateComponent(@typeName(Position));
try pos_data.setFloat("x", 100.0);
try pos_data.setFloat("y", 200.0);

// Add Health component data
const health_data = try player_prefab.getOrCreateComponent(@typeName(Health));
try health_data.setInt("current", 100);
try health_data.setInt("max", 100);

// Register the prefab
try registry.registerPrefab(player_prefab);
```

### Loading Prefabs from TOML

```zig
// Load from file
const count = try registry.loadFromFile("assets/prefabs.toml");

// Or load from string content
const toml_content =
    \\[[prefab]]
    \\id = "enemy"
    \\
    \\[prefab.Position]
    \\x = 50.0
    \\y = 50.0
    \\
    \\[prefab.Health]
    \\current = 50
    \\max = 50
;
_ = try registry.loadFromToml(toml_content);
```

### Spawning Entities

```zig
// Basic spawn
const entity = try registry.spawn(&entity_manager, "player");

// Access spawned components
const pos = try positions.get(entity);
const health = try healths.get(entity);
```

### Spawning with Overrides

```zig
// Create override data
var overrides = std.StringHashMap(prefab.ComponentData).init(allocator);
defer {
    var iter = overrides.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.deinit();
    }
    overrides.deinit();
}

var pos_override = prefab.ComponentData.init(allocator);
try pos_override.setFloat("x", 500.0); // Override x position
try overrides.put(@typeName(Position), pos_override);

// Spawn with overrides
const entity = try registry.spawnWithOverrides(&entity_manager, "player", &overrides);
```

### Hierarchical Prefabs

```zig
// Base prefab
var base = try prefab.PrefabDefinition.init(allocator, "base_entity");
const base_health = try base.getOrCreateComponent(@typeName(Health));
try base_health.setInt("max", 100);
try base_health.setInt("current", 100);
try registry.registerPrefab(base);
base.deinit();

// Child prefab inheriting from base
var goblin = try prefab.PrefabDefinition.init(allocator, "goblin");
try goblin.setParent("base_entity");

// Override only what's different
const goblin_health = try goblin.getOrCreateComponent(@typeName(Health));
try goblin_health.setInt("max", 50);
try goblin_health.setInt("current", 50);
try registry.registerPrefab(goblin);
goblin.deinit();

// Spawning goblin will have Health from base, with overridden values
const entity = try registry.spawn(&entity_manager, "goblin");
```

## TOML Format

```toml
# Basic prefab
[[prefab]]
id = "player"

[prefab.Position]
x = 100.0
y = 200.0

[prefab.Health]
current = 100
max = 100

# Prefab with inheritance
[[prefab]]
id = "enemy_goblin"
parent = "player"

[prefab.Health]
current = 50
max = 50
```

## Data Structures

- `FieldValue` - Tagged union for field values (int, uint, float, bool, string)
- `ComponentData` - Map of field names to FieldValues
- `PrefabDefinition` - Template with ID, optional parent, and component data map
- `PrefabRegistry` - Registry managing prefabs and component type registration

## Component Data API

```zig
var data = prefab.ComponentData.init(allocator);
defer data.deinit();

// Set values
try data.setInt("health", 100);
try data.setFloat("speed", 5.5);
try data.setBool("active", true);
try data.setString("name", "Player");

// Get values (returns null if not found or wrong type)
const health = data.getInt("health");     // ?i64
const speed = data.getFloat("speed");     // ?f64
const active = data.getBool("active");    // ?bool
const name = data.getString("name");      // ?[]const u8
```

## Inheritance Rules

When spawning a prefab with a parent:
1. Parent's components are collected first (recursively)
2. Child's components override/merge with parent's
3. Override fields replace parent fields, new fields are added
4. Components not in child are inherited unchanged

## Technical Details

- Component type names use `@typeName(T)` for type-safe registration
- Uses comptime reflection to map ComponentData fields to struct fields
- Supports default values in component structs
- Type conversion handled automatically (int to float, etc.)

## Tests

10 tests covering ComponentData operations, PrefabDefinition, registry, TOML loading, spawning, inheritance, and component creation.
