# Pathfinding System

A* pathfinding algorithm for grid-based maps (`src/pathfinding.zig`).

## Features

- **A* algorithm** - Optimal pathfinding with configurable heuristics
- **Diagonal movement** - Optional 8-directional movement with corner-cutting prevention
- **Variable movement costs** - Per-tile terrain costs (swamps, roads, etc.)
- **Path smoothing** - Line-of-sight based waypoint reduction
- **Dynamic obstacles** - Runtime obstacle updates without recreation
- **Custom callbacks** - Flexible walkability and cost functions

## Usage

### Basic Pathfinding

```zig
const pathfinding = @import("AgentiteZ").pathfinding;

// Create pathfinder for a 100x100 grid
var walkable: [10000]bool = undefined;
@memset(&walkable, true);
walkable[5 + 5 * 100] = false; // Block (5, 5)

var pathfinder = pathfinding.AStarPathfinder.initWithGrid(allocator, 100, 100, &walkable);

// Find path
var path = try pathfinder.findPath(
    pathfinding.Coord.init(0, 0),
    pathfinding.Coord.init(99, 99),
);
defer path.deinit();

if (path.complete) {
    std.debug.print("Path found with {d} steps, cost: {d:.1}\n",
        .{path.len(), path.total_cost});

    if (path.getNextStep()) |next| {
        moveEntityTo(next.x, next.y);
    }
}
```

### Configuration

```zig
pathfinder.setConfig(.{
    .allow_diagonal = true,
    .diagonal_cost = 1.414,
    .cardinal_cost = 1.0,
    .max_iterations = 10000,
    .heuristic_weight = 1.0,
});
```

### Variable Terrain Costs

```zig
var cost_grid: [10000]f32 = undefined;
@memset(&cost_grid, 1.0);

// Swamp area (5x movement cost)
for (20..30) |y| {
    for (20..30) |x| {
        cost_grid[x + y * 100] = 5.0;
    }
}

// Road (half movement cost)
for (0..100) |x| {
    cost_grid[x + 50 * 100] = 0.5;
}

pathfinder.setCostGrid(&cost_grid);
```

### Path Smoothing

```zig
var path = try pathfinder.findPath(start, goal);
if (path.complete) {
    const original_len = path.len();
    try pathfinder.smoothPath(&path);
    std.debug.print("Smoothed from {d} to {d} waypoints\n",
        .{original_len, path.len()});
}
```

### Dynamic Obstacles

```zig
pathfinder.setObstacle(enemy_x, enemy_y, true);
path = try pathfinder.findPath(current_pos, goal);
pathfinder.setObstacle(enemy_x, enemy_y, false);

// Batch updates
pathfinder.setObstacles(&new_obstacles, true);
```

### Custom Callbacks

```zig
fn isWalkable(x: i32, y: i32, user_data: ?*anyopaque) bool {
    const game: *GameState = @ptrCast(@alignCast(user_data.?));
    if (game.getTileAt(x, y)) |tile| {
        return !tile.is_solid and !tile.has_enemy;
    }
    return false;
}

fn getMovementCost(from_x: i32, from_y: i32, to_x: i32, to_y: i32, user_data: ?*anyopaque) f32 {
    _ = from_x; _ = from_y;
    const game: *GameState = @ptrCast(@alignCast(user_data.?));
    if (game.getTileAt(to_x, to_y)) |tile| {
        return tile.movement_cost;
    }
    return 1.0;
}

var pathfinder = pathfinding.AStarPathfinder.initWithCallback(
    allocator, 100, 100, isWalkable, &game_state
);
pathfinder.setCostCallback(getMovementCost, &game_state);
```

### Line of Sight

```zig
if (pathfinder.hasLineOfSight(
    pathfinding.Coord.init(10, 10),
    pathfinding.Coord.init(50, 50),
)) {
    fireAt(target);
} else {
    var path = try pathfinder.findPath(shooter_pos, target_pos);
}
```

## Data Structures

- `AStarPathfinder` - Main pathfinder with grid, callbacks, and configuration
- `Coord` - 2D integer coordinate with distance functions
- `Path` - Path result with points, cost, and completion status
- `PathfindingConfig` - Algorithm settings

### Coord Methods

- `init(x, y)` - Create coordinate
- `eql(other)` - Equality check
- `manhattanDistance(other)` - Manhattan distance
- `chebyshevDistance(other)` - Chebyshev distance
- `euclideanDistanceSquared(other)` - Squared Euclidean distance

### Path Methods

- `len()` - Number of waypoints
- `isEmpty()` - Check if path is empty
- `getNextStep()` - Get next waypoint after start
- `complete` - Whether path reaches goal
- `total_cost` - Total movement cost

## Tests

20 comprehensive tests covering basic paths, obstacles, diagonal movement, variable costs, path smoothing, line of sight, dynamic obstacles, callbacks, and edge cases.
