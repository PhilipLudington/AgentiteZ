# Spatial Index

High-performance grid-based spatial indexing for fast proximity queries (`src/spatial.zig`).

## Features

- **Grid-based spatial hashing** - O(1) insertion and removal
- **Generic entity ID type** - Works with u32, u64, or custom ID types
- **Position tracking** - Automatic tracking for efficient updates
- **Range queries** - Query by radius or axis-aligned bounding box
- **Nearest neighbor** - Find closest entity or K-nearest neighbors
- **Statistics** - Built-in profiling for cell distribution

## Usage

### Basic Operations

```zig
const spatial = @import("AgentiteZ").spatial;

// Create spatial index with 64-pixel cells
var index = spatial.SpatialIndex(u32).init(allocator, .{ .cell_size = 64.0 });
defer index.deinit();

// Insert entities at positions
try index.insert(player_id, spatial.Vec2.init(100.0, 200.0));
try index.insert(enemy_id, spatial.Vec2.init(150.0, 180.0));

// Update position (more efficient than remove+insert for moving entities)
try index.update(player_id, spatial.Vec2.init(105.0, 205.0));

// Remove entity
const old_pos = index.remove(enemy_id);

// Check if entity exists
if (index.contains(player_id)) {
    const pos = index.getPosition(player_id).?;
}
```

### Radius Query

```zig
var nearby = try index.queryRadius(
    spatial.Vec2.init(100.0, 100.0),
    100.0,  // radius
    allocator,
);
defer nearby.deinit();

for (nearby.items) |entry| {
    handleNearbyEntity(entry.id, entry.position);
}
```

### Rectangle Query

```zig
const search_area = spatial.AABB.fromRect(0.0, 0.0, 200.0, 200.0);
var entities = try index.queryRect(search_area, allocator);
defer entities.deinit();

for (entities.items) |entry| {
    processEntity(entry.id);
}
```

### Nearest Neighbor

```zig
// Find single nearest entity within max radius
if (index.findNearest(spatial.Vec2.init(100.0, 100.0), 500.0)) |nearest| {
    attackTarget(nearest.id);
}

// Find K nearest entities
var k_nearest = try index.findKNearest(
    spatial.Vec2.init(100.0, 100.0),
    5,      // k - number of results
    500.0,  // max radius
    allocator,
);
defer k_nearest.deinit();

// Results are sorted by distance (closest first)
for (k_nearest.items) |result| {
    std.debug.print("Entity {d} at distance {d:.1}\n", .{result.id, result.distance});
}
```

### Statistics

```zig
const stats = index.getStats();
std.debug.print("Entities: {d}, Cells: {d}, Max/cell: {d}\n", .{
    stats.total_entities,
    stats.non_empty_cells,
    stats.max_entities_per_cell,
});
```

## Data Structures

- `SpatialIndex(T)` - Generic spatial index parameterized by entity ID type
- `Vec2` - 2D vector with add, sub, scale, length, distance operations
- `AABB` - Axis-aligned bounding box with containment and overlap tests
- `NearestResult(T)` - Result from nearest neighbor queries (id, position, distance)
- `SpatialIndexStats` - Statistics about index distribution

## Performance

- Insert: O(1) amortized
- Remove: O(k) where k is entities in the cell
- Update position: O(k) for old cell + O(1) for new cell
- Query radius: O(cells_checked × entities_per_cell)
- Nearest neighbor: O(cells_checked × entities_per_cell)

**Cell Size Selection:** Set `cell_size` approximately equal to your typical query radius for optimal performance.

## Tests

18 comprehensive tests covering Vec2, AABB, insert/remove/update, queries, nearest neighbor, edge cases, and custom ID types.
