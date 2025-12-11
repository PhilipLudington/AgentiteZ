# ECS Module API Reference

Entity-Component-System architecture for game logic organization.

## Overview

The ECS module provides a professional entity-component-system implementation with:
- **Sparse-set storage** for cache-friendly iteration
- **Generation counters** to prevent use-after-free bugs
- **Type-safe component arrays**
- **Polymorphic systems** via VTable pattern

## Module Structure

```zig
const ecs = @import("AgentiteZ").ecs;

// Core types
ecs.Entity         // Entity handle with ID + generation
ecs.ComponentArray // Generic component storage
ecs.System         // System interface
ecs.World          // Central ECS coordinator
```

## Types

### `Entity`

Unique identifier for an entity with generation counter.

```zig
pub const Entity = struct {
    id: u32,         // Unique entity ID
    generation: u32, // Generation counter (prevents use-after-free)
};
```

**Methods:**
- `isValid(self: Entity) bool` - Check if entity is valid (non-zero ID)

**Example:**
```zig
const player = try world.createEntity();
std.debug.print("Entity ID: {d}, Gen: {d}\n", .{player.id, player.generation});
```

---

### `ComponentArray(T)`

Sparse-set storage for components of type `T`.

```zig
pub fn ComponentArray(comptime T: type) type {
    return struct {
        // ... internal sparse-set implementation
    };
}
```

**Methods:**

#### `init(allocator: std.mem.Allocator) ComponentArray(T)`
Create a new component array.

**Parameters:**
- `allocator` - Memory allocator for internal storage

**Returns:** Initialized component array

**Example:**
```zig
var positions = ecs.ComponentArray(Position).init(allocator);
defer positions.deinit();
```

---

#### `deinit(self: *ComponentArray(T)) void`
Free all resources.

**Example:**
```zig
defer positions.deinit();
```

---

#### `add(self: *ComponentArray(T), entity: Entity, component: T) !void`
Add a component to an entity.

**Parameters:**
- `entity` - Entity to add component to
- `component` - Component data to add

**Errors:**
- `OutOfMemory` - Failed to allocate storage

**Example:**
```zig
try positions.add(player, .{ .x = 100, .y = 200 });
```

---

#### `remove(self: *ComponentArray(T), entity: Entity) void`
Remove a component from an entity.

**Parameters:**
- `entity` - Entity to remove component from

**Example:**
```zig
positions.remove(player);
```

---

#### `get(self: *ComponentArray(T), entity: Entity) ?*T`
Get mutable component for an entity.

**Parameters:**
- `entity` - Entity to get component for

**Returns:** Pointer to component, or `null` if not found

**Example:**
```zig
if (positions.get(player)) |pos| {
    pos.x += velocity.x;
    pos.y += velocity.y;
}
```

---

#### `has(self: *const ComponentArray(T), entity: Entity) bool`
Check if entity has this component.

**Parameters:**
- `entity` - Entity to check

**Returns:** `true` if component exists

**Example:**
```zig
if (positions.has(player)) {
    std.debug.print("Player has position\n", .{});
}
```

---

#### `iterator(self: *ComponentArray(T)) Iterator`
Iterate over all components (cache-optimal).

**Returns:** Iterator over entities and components

**Example:**
```zig
var iter = positions.iterator();
while (iter.next()) |entry| {
    std.debug.print("Entity {d}: ({d}, {d})\n",
        .{entry.entity.id, entry.component.x, entry.component.y});
}
```

---

### `System`

VTable-based polymorphic system interface.

```zig
pub const System = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        update: *const fn (ptr: *anyopaque, delta_time: f32) anyerror!void,
        deinit: *const fn (ptr: *anyopaque) void,
    };
};
```

**Methods:**

#### `init(pointer: anytype) System`
Create a system from any type with `update()` and `deinit()` methods.

**Parameters:**
- `pointer` - Pointer to system implementation

**Returns:** System with VTable

**Example:**
```zig
const MovementSystem = struct {
    positions: *ecs.ComponentArray(Position),
    velocities: *ecs.ComponentArray(Velocity),

    pub fn update(self: *MovementSystem, delta_time: f32) !void {
        var pos_iter = self.positions.iterator();
        while (pos_iter.next()) |entry| {
            if (self.velocities.get(entry.entity)) |vel| {
                entry.component.x += vel.x * delta_time;
                entry.component.y += vel.y * delta_time;
            }
        }
    }

    pub fn deinit(self: *MovementSystem) void {
        _ = self;
    }
};

var movement_system = MovementSystem{
    .positions = &positions,
    .velocities = &velocities,
};

const system = ecs.System.init(&movement_system);
```

---

### `World`

Central ECS coordinator managing entities and systems.

```zig
pub const World = struct {
    allocator: std.mem.Allocator,
    entity_manager: EntityManager,
    systems: SystemRegistry,
};
```

**Methods:**

#### `init(allocator: std.mem.Allocator) World`
Create a new ECS world.

**Parameters:**
- `allocator` - Memory allocator

**Returns:** Initialized world

**Example:**
```zig
var world = ecs.World.init(allocator);
defer world.deinit();
```

---

#### `deinit(self: *World) void`
Free all resources and registered systems.

**Example:**
```zig
defer world.deinit();
```

---

#### `createEntity(self: *World) !Entity`
Create a new entity.

**Returns:** Entity handle with unique ID

**Errors:**
- `OutOfMemory` - Failed to allocate entity

**Example:**
```zig
const player = try world.createEntity();
const enemy = try world.createEntity();
```

---

#### `destroyEntity(self: *World, entity: Entity) void`
Destroy an entity (mark for recycling).

**Parameters:**
- `entity` - Entity to destroy

**Note:** Entity ID will be recycled with incremented generation counter.

**Example:**
```zig
world.destroyEntity(enemy);
```

---

#### `registerSystem(self: *World, system: System) !void`
Register a system for updates.

**Parameters:**
- `system` - System to register

**Errors:**
- `OutOfMemory` - Failed to allocate system slot

**Example:**
```zig
try world.registerSystem(ecs.System.init(&movement_system));
try world.registerSystem(ecs.System.init(&render_system));
```

---

#### `update(self: *World, delta_time: f32) !void`
Update all registered systems in order.

**Parameters:**
- `delta_time` - Time elapsed since last frame (seconds)

**Errors:**
- Propagates errors from system updates

**Example:**
```zig
// In main loop
const delta_time: f32 = 0.016; // 60 FPS
try world.update(delta_time);
```

---

## Usage Patterns

### Basic ECS Setup

```zig
const std = @import("std");
const ecs = @import("AgentiteZ").ecs;

// Define components
const Position = struct {
    x: f32,
    y: f32,
};

const Velocity = struct {
    x: f32,
    y: f32,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create world
    var world = ecs.World.init(allocator);
    defer world.deinit();

    // Create component storage
    var positions = ecs.ComponentArray(Position).init(allocator);
    defer positions.deinit();

    var velocities = ecs.ComponentArray(Velocity).init(allocator);
    defer velocities.deinit();

    // Create entities with components
    const player = try world.createEntity();
    try positions.add(player, .{ .x = 100, .y = 200 });
    try velocities.add(player, .{ .x = 50, .y = 0 });

    // Register systems
    var movement_system = MovementSystem{
        .positions = &positions,
        .velocities = &velocities,
    };
    try world.registerSystem(ecs.System.init(&movement_system));

    // Game loop
    const delta_time: f32 = 0.016; // 60 FPS
    try world.update(delta_time);

    // Query components
    if (positions.get(player)) |pos| {
        std.debug.print("Player position: ({d:.1}, {d:.1})\n", .{pos.x, pos.y});
    }
}
```

### Implementing a System

```zig
const RenderSystem = struct {
    positions: *ecs.ComponentArray(Position),
    sprites: *ecs.ComponentArray(Sprite),
    renderer: *Renderer,

    pub fn update(self: *RenderSystem, delta_time: f32) !void {
        _ = delta_time;

        // Iterate all entities with both position and sprite
        var iter = self.positions.iterator();
        while (iter.next()) |entry| {
            if (self.sprites.get(entry.entity)) |sprite| {
                // Render sprite at position
                try self.renderer.drawSprite(
                    sprite.texture,
                    entry.component.x,
                    entry.component.y,
                );
            }
        }
    }

    pub fn deinit(self: *RenderSystem) void {
        _ = self;
    }
};
```

### Component Queries

```zig
// Find all entities with specific components
fn findMovableEntities(
    positions: *ecs.ComponentArray(Position),
    velocities: *ecs.ComponentArray(Velocity),
) !std.ArrayList(ecs.Entity) {
    var result = std.ArrayList(ecs.Entity).init(allocator);

    var iter = positions.iterator();
    while (iter.next()) |entry| {
        if (velocities.has(entry.entity)) {
            try result.append(entry.entity);
        }
    }

    return result;
}
```

## Performance Notes

### Sparse-Set Advantages
- **O(1) component lookup** via sparse array
- **O(n) cache-optimal iteration** over packed dense array
- No memory fragmentation from entity destruction

### Best Practices
1. **Iterate over smallest component array** first for better cache utilization
2. **Group related components** in the same system update
3. **Avoid cross-system dependencies** - systems should be independent
4. **Use generation counters** - always check entity validity if storing references

### Memory Usage
- **Entity**: 8 bytes (id + generation)
- **Sparse index**: 4 bytes per entity ID slot
- **Component**: `sizeof(T)` per component + sparse overhead

## Common Patterns

### Deferred Entity Destruction

```zig
var entities_to_destroy = std.ArrayList(ecs.Entity).init(allocator);
defer entities_to_destroy.deinit();

// Mark entities for destruction
var iter = health.iterator();
while (iter.next()) |entry| {
    if (entry.component.value <= 0) {
        try entities_to_destroy.append(entry.entity);
    }
}

// Destroy after iteration
for (entities_to_destroy.items) |entity| {
    world.destroyEntity(entity);
    positions.remove(entity);
    health.remove(entity);
}
```

### Prefabs/Archetypes

```zig
fn spawnEnemy(
    world: *ecs.World,
    positions: *ecs.ComponentArray(Position),
    health: *ecs.ComponentArray(Health),
    sprites: *ecs.ComponentArray(Sprite),
    x: f32,
    y: f32,
) !ecs.Entity {
    const entity = try world.createEntity();

    try positions.add(entity, .{ .x = x, .y = y });
    try health.add(entity, .{ .value = 100, .max = 100 });
    try sprites.add(entity, .{ .texture = enemy_texture });

    return entity;
}
```

## See Also

- [UI Module](ui.md) - User interface widgets
- [Main Documentation](index.md) - API overview

---

**Module Path:** `src/ecs/`
**Tests:** `src/ecs/*_test.zig`
**Examples:** See `src/main.zig` for bouncing entities demo
