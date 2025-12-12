// pathfinding.zig
// A* pathfinding algorithm for grid-based maps
//
// Provides efficient pathfinding with support for:
// - Diagonal movement (optional)
// - Variable movement costs
// - Dynamic obstacle handling
// - Path smoothing
//
// Performance target: <50ms for 100x100 grid corner-to-corner paths

const std = @import("std");

/// 2D grid coordinate
pub const Coord = struct {
    x: i32,
    y: i32,

    pub fn init(x: i32, y: i32) Coord {
        return .{ .x = x, .y = y };
    }

    pub fn eql(self: Coord, other: Coord) bool {
        return self.x == other.x and self.y == other.y;
    }

    /// Manhattan distance to another coordinate
    pub fn manhattanDistance(self: Coord, other: Coord) i32 {
        return @intCast(@abs(self.x - other.x) + @abs(self.y - other.y));
    }

    /// Chebyshev distance (diagonal distance)
    pub fn chebyshevDistance(self: Coord, other: Coord) i32 {
        return @max(@abs(self.x - other.x), @abs(self.y - other.y));
    }

    /// Euclidean distance squared (for comparisons without sqrt)
    pub fn euclideanDistanceSquared(self: Coord, other: Coord) i32 {
        const dx = self.x - other.x;
        const dy = self.y - other.y;
        return dx * dx + dy * dy;
    }
};

/// Path result from A* search
pub const Path = struct {
    /// The path points from start to goal (inclusive)
    points: std.ArrayList(Coord),

    /// Total cost of the path
    total_cost: f32,

    /// Whether the path reaches the goal
    complete: bool,

    pub fn init(allocator: std.mem.Allocator) Path {
        return .{
            .points = std.ArrayList(Coord).init(allocator),
            .total_cost = 0,
            .complete = false,
        };
    }

    pub fn deinit(self: *Path) void {
        self.points.deinit();
    }

    /// Get the number of steps in the path
    pub fn len(self: *const Path) usize {
        return self.points.items.len;
    }

    /// Check if path is empty
    pub fn isEmpty(self: *const Path) bool {
        return self.points.items.len == 0;
    }

    /// Get the next point after the start
    pub fn getNextStep(self: *const Path) ?Coord {
        if (self.points.items.len > 1) {
            return self.points.items[1];
        }
        return null;
    }

    /// Reverse the path (used internally during reconstruction)
    pub fn reverse(self: *Path) void {
        std.mem.reverse(Coord, self.points.items);
    }
};

/// Configuration for pathfinding behavior
pub const PathfindingConfig = struct {
    /// Allow diagonal movement
    allow_diagonal: bool = true,

    /// Cost multiplier for diagonal moves (typically sqrt(2) ≈ 1.414)
    diagonal_cost: f32 = 1.414,

    /// Cost for cardinal (N/S/E/W) moves
    cardinal_cost: f32 = 1.0,

    /// Maximum number of nodes to explore before giving up
    /// Set to 0 for unlimited
    max_iterations: u32 = 0,

    /// Heuristic weight (1.0 = standard A*, higher = faster but less optimal)
    heuristic_weight: f32 = 1.0,
};

/// Callback for custom walkability checking
pub const WalkableCallback = *const fn (x: i32, y: i32, user_data: ?*anyopaque) bool;

/// Callback for custom movement cost
pub const CostCallback = *const fn (from_x: i32, from_y: i32, to_x: i32, to_y: i32, user_data: ?*anyopaque) f32;

/// Node in the A* open/closed sets
const Node = struct {
    coord: Coord,
    g_cost: f32, // Cost from start to this node
    f_cost: f32, // g_cost + heuristic (total estimated cost)
    parent: ?Coord, // For path reconstruction

    fn compare(_: void, a: Node, b: Node) std.math.Order {
        // Min-heap: lower f_cost = higher priority
        return std.math.order(a.f_cost, b.f_cost);
    }
};

/// A* pathfinder for grid-based maps
pub const AStarPathfinder = struct {
    const Self = @This();

    /// Grid dimensions
    width: u32,
    height: u32,

    /// Walkability grid (true = walkable)
    /// If null, uses walkable_callback
    walkable: ?[]bool,

    /// Movement cost grid (optional, for variable terrain costs)
    /// Values are cost multipliers (1.0 = normal, 2.0 = double cost, etc.)
    /// If null, uses default costs
    cost_grid: ?[]f32,

    /// Custom walkability callback (optional)
    walkable_callback: ?WalkableCallback,
    walkable_user_data: ?*anyopaque,

    /// Custom cost callback (optional)
    cost_callback: ?CostCallback,
    cost_user_data: ?*anyopaque,

    /// Configuration
    config: PathfindingConfig,

    /// Memory allocator
    allocator: std.mem.Allocator,

    /// Initialize pathfinder with a fixed-size grid
    /// The walkable array should have width * height elements
    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) Self {
        return .{
            .width = width,
            .height = height,
            .walkable = null,
            .cost_grid = null,
            .walkable_callback = null,
            .walkable_user_data = null,
            .cost_callback = null,
            .cost_user_data = null,
            .config = .{},
            .allocator = allocator,
        };
    }

    /// Initialize with a walkability array
    pub fn initWithGrid(allocator: std.mem.Allocator, width: u32, height: u32, walkable: []bool) Self {
        var self = init(allocator, width, height);
        self.walkable = walkable;
        return self;
    }

    /// Initialize with a custom walkability callback
    pub fn initWithCallback(
        allocator: std.mem.Allocator,
        width: u32,
        height: u32,
        callback: WalkableCallback,
        user_data: ?*anyopaque,
    ) Self {
        var self = init(allocator, width, height);
        self.walkable_callback = callback;
        self.walkable_user_data = user_data;
        return self;
    }

    /// Set pathfinding configuration
    pub fn setConfig(self: *Self, config: PathfindingConfig) void {
        self.config = config;
    }

    /// Set walkability for a single cell
    pub fn setWalkable(self: *Self, x: i32, y: i32, walkable: bool) void {
        if (self.walkable) |grid| {
            if (self.isInBounds(x, y)) {
                const idx = self.coordToIndex(x, y);
                grid[idx] = walkable;
            }
        }
    }

    /// Set movement cost for a single cell
    pub fn setCost(self: *Self, x: i32, y: i32, cost: f32) void {
        if (self.cost_grid) |grid| {
            if (self.isInBounds(x, y)) {
                const idx = self.coordToIndex(x, y);
                grid[idx] = cost;
            }
        }
    }

    /// Set the cost grid (optional, for variable terrain costs)
    pub fn setCostGrid(self: *Self, cost_grid: []f32) void {
        self.cost_grid = cost_grid;
    }

    /// Set custom cost callback
    pub fn setCostCallback(self: *Self, callback: CostCallback, user_data: ?*anyopaque) void {
        self.cost_callback = callback;
        self.cost_user_data = user_data;
    }

    /// Check if a coordinate is within grid bounds
    pub fn isInBounds(self: *const Self, x: i32, y: i32) bool {
        return x >= 0 and y >= 0 and
            x < @as(i32, @intCast(self.width)) and
            y < @as(i32, @intCast(self.height));
    }

    /// Check if a coordinate is walkable
    pub fn isWalkable(self: *const Self, x: i32, y: i32) bool {
        if (!self.isInBounds(x, y)) return false;

        // Use callback if provided
        if (self.walkable_callback) |callback| {
            return callback(x, y, self.walkable_user_data);
        }

        // Use grid if provided
        if (self.walkable) |grid| {
            const idx = self.coordToIndex(x, y);
            return grid[idx];
        }

        // Default: all cells walkable
        return true;
    }

    /// Get movement cost to enter a cell
    pub fn getMovementCost(self: *const Self, from_x: i32, from_y: i32, to_x: i32, to_y: i32) f32 {
        // Use custom callback if provided
        if (self.cost_callback) |callback| {
            return callback(from_x, from_y, to_x, to_y, self.cost_user_data);
        }

        // Base cost depends on direction
        const dx = @abs(to_x - from_x);
        const dy = @abs(to_y - from_y);
        var base_cost: f32 = undefined;
        if (dx == 1 and dy == 1) {
            base_cost = self.config.diagonal_cost;
        } else {
            base_cost = self.config.cardinal_cost;
        }

        // Apply terrain cost if grid provided
        if (self.cost_grid) |grid| {
            if (self.isInBounds(to_x, to_y)) {
                const idx = self.coordToIndex(to_x, to_y);
                base_cost *= grid[idx];
            }
        }

        return base_cost;
    }

    /// Find a path from start to goal
    pub fn findPath(self: *Self, start: Coord, goal: Coord) !Path {
        var path = Path.init(self.allocator);
        errdefer path.deinit();

        // Quick checks
        if (!self.isInBounds(start.x, start.y) or !self.isInBounds(goal.x, goal.y)) {
            return path; // Empty path, incomplete
        }

        if (!self.isWalkable(start.x, start.y) or !self.isWalkable(goal.x, goal.y)) {
            return path; // Empty path, incomplete
        }

        if (start.eql(goal)) {
            try path.points.append(start);
            path.complete = true;
            return path;
        }

        // A* data structures
        var open_set = std.PriorityQueue(Node, void, Node.compare).init(self.allocator, {});
        defer open_set.deinit();

        var g_costs = std.AutoHashMap(Coord, f32).init(self.allocator);
        defer g_costs.deinit();

        var parents = std.AutoHashMap(Coord, Coord).init(self.allocator);
        defer parents.deinit();

        var closed_set = std.AutoHashMap(Coord, void).init(self.allocator);
        defer closed_set.deinit();

        // Initialize with start node
        const start_h = self.heuristic(start, goal);
        try open_set.add(.{
            .coord = start,
            .g_cost = 0,
            .f_cost = start_h,
            .parent = null,
        });
        try g_costs.put(start, 0);

        var iterations: u32 = 0;

        // Main A* loop
        while (open_set.count() > 0) {
            // Check iteration limit
            if (self.config.max_iterations > 0 and iterations >= self.config.max_iterations) {
                break;
            }
            iterations += 1;

            // Get node with lowest f_cost
            const current = open_set.remove();

            // Check if we reached the goal
            if (current.coord.eql(goal)) {
                // Reconstruct path
                try self.reconstructPath(&path, &parents, start, goal);
                path.total_cost = current.g_cost;
                path.complete = true;
                return path;
            }

            // Skip if already processed
            if (closed_set.contains(current.coord)) {
                continue;
            }
            try closed_set.put(current.coord, {});

            // Explore neighbors
            const neighbors = self.getNeighbors(current.coord);
            for (neighbors) |neighbor| {
                if (neighbor == null) continue;
                const n = neighbor.?;

                // Skip if already in closed set
                if (closed_set.contains(n)) continue;

                // Skip if not walkable
                if (!self.isWalkable(n.x, n.y)) continue;

                // Check diagonal corner-cutting
                if (self.config.allow_diagonal) {
                    const dx = n.x - current.coord.x;
                    const dy = n.y - current.coord.y;
                    if (@abs(dx) == 1 and @abs(dy) == 1) {
                        // Diagonal move - check adjacent cells to prevent corner cutting
                        const adj1_walkable = self.isWalkable(current.coord.x + dx, current.coord.y);
                        const adj2_walkable = self.isWalkable(current.coord.x, current.coord.y + dy);
                        if (!adj1_walkable or !adj2_walkable) {
                            continue; // Can't cut through corners
                        }
                    }
                }

                // Calculate costs
                const move_cost = self.getMovementCost(current.coord.x, current.coord.y, n.x, n.y);
                const tentative_g = current.g_cost + move_cost;

                // Check if this is a better path
                const existing_g = g_costs.get(n);
                if (existing_g == null or tentative_g < existing_g.?) {
                    try g_costs.put(n, tentative_g);
                    try parents.put(n, current.coord);

                    const h = self.heuristic(n, goal);
                    try open_set.add(.{
                        .coord = n,
                        .g_cost = tentative_g,
                        .f_cost = tentative_g + h,
                        .parent = current.coord,
                    });
                }
            }
        }

        // No path found - return best partial path if available
        return path;
    }

    /// Apply path smoothing to remove unnecessary waypoints
    /// Uses line-of-sight checks to create more direct paths
    pub fn smoothPath(self: *Self, path: *Path) !void {
        if (path.points.items.len <= 2) return;

        var smoothed = std.ArrayList(Coord).init(self.allocator);
        errdefer smoothed.deinit();

        try smoothed.append(path.points.items[0]);

        var current_idx: usize = 0;
        while (current_idx < path.points.items.len - 1) {
            var furthest_visible = current_idx + 1;

            // Find the furthest point we can see from current
            var check_idx = current_idx + 2;
            while (check_idx < path.points.items.len) : (check_idx += 1) {
                if (self.hasLineOfSight(path.points.items[current_idx], path.points.items[check_idx])) {
                    furthest_visible = check_idx;
                }
            }

            try smoothed.append(path.points.items[furthest_visible]);
            current_idx = furthest_visible;
        }

        // Replace path points with smoothed version
        path.points.deinit();
        path.points = smoothed;
    }

    /// Check if there's a clear line of sight between two points
    /// Uses Bresenham's line algorithm
    pub fn hasLineOfSight(self: *const Self, from: Coord, to: Coord) bool {
        var x0 = from.x;
        var y0 = from.y;
        const x1 = to.x;
        const y1 = to.y;

        const dx: i32 = @intCast(@abs(x1 - x0));
        const dy: i32 = @intCast(@abs(y1 - y0));
        const sx: i32 = if (x0 < x1) 1 else -1;
        const sy: i32 = if (y0 < y1) 1 else -1;
        var err = dx - dy;

        while (true) {
            if (!self.isWalkable(x0, y0)) return false;

            if (x0 == x1 and y0 == y1) break;

            const e2 = err * 2;
            if (e2 > -dy) {
                err -= dy;
                x0 += sx;
            }
            if (e2 < dx) {
                err += dx;
                y0 += sy;
            }
        }

        return true;
    }

    /// Update obstacle at position (for dynamic obstacle handling)
    /// Marks a cell as blocked or unblocked
    pub fn setObstacle(self: *Self, x: i32, y: i32, blocked: bool) void {
        self.setWalkable(x, y, !blocked);
    }

    /// Batch update multiple obstacles
    pub fn setObstacles(self: *Self, coords: []const Coord, blocked: bool) void {
        for (coords) |coord| {
            self.setObstacle(coord.x, coord.y, blocked);
        }
    }

    // Internal: Calculate heuristic (estimated cost from coord to goal)
    fn heuristic(self: *const Self, from: Coord, to: Coord) f32 {
        if (self.config.allow_diagonal) {
            // Octile distance for 8-directional movement
            const dx = @abs(from.x - to.x);
            const dy = @abs(from.y - to.y);
            const d1 = @as(f32, @floatFromInt(@min(dx, dy)));
            const d2 = @as(f32, @floatFromInt(@max(dx, dy)));
            const h = self.config.diagonal_cost * d1 + self.config.cardinal_cost * (d2 - d1);
            return h * self.config.heuristic_weight;
        } else {
            // Manhattan distance for 4-directional movement
            const h = @as(f32, @floatFromInt(from.manhattanDistance(to)));
            return h * self.config.cardinal_cost * self.config.heuristic_weight;
        }
    }

    // Internal: Get valid neighbors of a coordinate
    fn getNeighbors(self: *const Self, coord: Coord) [8]?Coord {
        var neighbors: [8]?Coord = .{ null, null, null, null, null, null, null, null };
        var idx: usize = 0;

        // Cardinal directions (N, S, E, W)
        const cardinal_offsets = [_][2]i32{
            .{ 0, -1 }, // North
            .{ 0, 1 }, // South
            .{ 1, 0 }, // East
            .{ -1, 0 }, // West
        };

        for (cardinal_offsets) |offset| {
            const nx = coord.x + offset[0];
            const ny = coord.y + offset[1];
            if (self.isInBounds(nx, ny)) {
                neighbors[idx] = Coord.init(nx, ny);
                idx += 1;
            }
        }

        // Diagonal directions (if enabled)
        if (self.config.allow_diagonal) {
            const diagonal_offsets = [_][2]i32{
                .{ 1, -1 }, // NE
                .{ -1, -1 }, // NW
                .{ 1, 1 }, // SE
                .{ -1, 1 }, // SW
            };

            for (diagonal_offsets) |offset| {
                const nx = coord.x + offset[0];
                const ny = coord.y + offset[1];
                if (self.isInBounds(nx, ny)) {
                    neighbors[idx] = Coord.init(nx, ny);
                    idx += 1;
                }
            }
        }

        return neighbors;
    }

    // Internal: Reconstruct path from parents map
    fn reconstructPath(
        self: *Self,
        path: *Path,
        parents: *std.AutoHashMap(Coord, Coord),
        start: Coord,
        goal: Coord,
    ) !void {
        _ = self;
        var current = goal;
        try path.points.append(current);

        while (!current.eql(start)) {
            if (parents.get(current)) |parent| {
                try path.points.append(parent);
                current = parent;
            } else {
                break;
            }
        }

        path.reverse();
    }

    // Internal: Convert 2D coordinate to 1D index
    fn coordToIndex(self: *const Self, x: i32, y: i32) usize {
        return @intCast(@as(i32, @intCast(self.width)) * y + x);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Coord operations" {
    const a = Coord.init(3, 4);
    const b = Coord.init(6, 8);

    // Equality
    try std.testing.expect(a.eql(Coord.init(3, 4)));
    try std.testing.expect(!a.eql(b));

    // Manhattan distance
    try std.testing.expectEqual(@as(i32, 7), a.manhattanDistance(b));

    // Chebyshev distance
    try std.testing.expectEqual(@as(i32, 4), a.chebyshevDistance(b));

    // Euclidean distance squared
    try std.testing.expectEqual(@as(i32, 25), a.euclideanDistanceSquared(b));
}

test "Path basic operations" {
    const allocator = std.testing.allocator;
    var path = Path.init(allocator);
    defer path.deinit();

    try std.testing.expect(path.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), path.len());

    try path.points.append(Coord.init(0, 0));
    try path.points.append(Coord.init(1, 0));
    try path.points.append(Coord.init(2, 0));

    try std.testing.expect(!path.isEmpty());
    try std.testing.expectEqual(@as(usize, 3), path.len());

    const next = path.getNextStep();
    try std.testing.expect(next != null);
    try std.testing.expectEqual(@as(i32, 1), next.?.x);
}

test "AStarPathfinder basic path" {
    const allocator = std.testing.allocator;

    // Create 10x10 grid, all walkable
    var walkable: [100]bool = undefined;
    @memset(&walkable, true);

    var pathfinder = AStarPathfinder.initWithGrid(allocator, 10, 10, &walkable);

    // Find path from corner to corner
    var path = try pathfinder.findPath(Coord.init(0, 0), Coord.init(9, 9));
    defer path.deinit();

    try std.testing.expect(path.complete);
    try std.testing.expect(!path.isEmpty());

    // Start should be first point
    try std.testing.expect(path.points.items[0].eql(Coord.init(0, 0)));

    // Goal should be last point
    try std.testing.expect(path.points.items[path.points.items.len - 1].eql(Coord.init(9, 9)));
}

test "AStarPathfinder with obstacles" {
    const allocator = std.testing.allocator;

    // Create 10x10 grid
    var walkable: [100]bool = undefined;
    @memset(&walkable, true);

    // Create a wall from (5,0) to (5,8)
    var y: usize = 0;
    while (y < 9) : (y += 1) {
        walkable[5 + y * 10] = false;
    }

    var pathfinder = AStarPathfinder.initWithGrid(allocator, 10, 10, &walkable);

    // Path from left of wall to right of wall
    var path = try pathfinder.findPath(Coord.init(0, 5), Coord.init(9, 5));
    defer path.deinit();

    try std.testing.expect(path.complete);

    // Path must go around the wall (through y=9)
    var went_around = false;
    for (path.points.items) |point| {
        if (point.y == 9) {
            went_around = true;
            break;
        }
    }
    try std.testing.expect(went_around);
}

test "AStarPathfinder no path possible" {
    const allocator = std.testing.allocator;

    // Create 10x10 grid
    var walkable: [100]bool = undefined;
    @memset(&walkable, true);

    // Create a complete wall blocking the grid
    var y: usize = 0;
    while (y < 10) : (y += 1) {
        walkable[5 + y * 10] = false;
    }

    var pathfinder = AStarPathfinder.initWithGrid(allocator, 10, 10, &walkable);

    var path = try pathfinder.findPath(Coord.init(0, 5), Coord.init(9, 5));
    defer path.deinit();

    try std.testing.expect(!path.complete);
}

test "AStarPathfinder same start and goal" {
    const allocator = std.testing.allocator;

    var walkable: [100]bool = undefined;
    @memset(&walkable, true);

    var pathfinder = AStarPathfinder.initWithGrid(allocator, 10, 10, &walkable);

    var path = try pathfinder.findPath(Coord.init(5, 5), Coord.init(5, 5));
    defer path.deinit();

    try std.testing.expect(path.complete);
    try std.testing.expectEqual(@as(usize, 1), path.len());
}

test "AStarPathfinder cardinal only movement" {
    const allocator = std.testing.allocator;

    var walkable: [100]bool = undefined;
    @memset(&walkable, true);

    var pathfinder = AStarPathfinder.initWithGrid(allocator, 10, 10, &walkable);
    pathfinder.setConfig(.{ .allow_diagonal = false });

    var path = try pathfinder.findPath(Coord.init(0, 0), Coord.init(3, 3));
    defer path.deinit();

    try std.testing.expect(path.complete);

    // Verify no diagonal moves (dx and dy can't both be non-zero between adjacent points)
    var i: usize = 0;
    while (i < path.points.items.len - 1) : (i += 1) {
        const dx = @abs(path.points.items[i + 1].x - path.points.items[i].x);
        const dy = @abs(path.points.items[i + 1].y - path.points.items[i].y);
        try std.testing.expect(!(dx == 1 and dy == 1));
    }
}

test "AStarPathfinder out of bounds" {
    const allocator = std.testing.allocator;

    var walkable: [100]bool = undefined;
    @memset(&walkable, true);

    var pathfinder = AStarPathfinder.initWithGrid(allocator, 10, 10, &walkable);

    // Start out of bounds
    var path1 = try pathfinder.findPath(Coord.init(-1, 0), Coord.init(5, 5));
    defer path1.deinit();
    try std.testing.expect(!path1.complete);

    // Goal out of bounds
    var path2 = try pathfinder.findPath(Coord.init(0, 0), Coord.init(100, 100));
    defer path2.deinit();
    try std.testing.expect(!path2.complete);
}

test "AStarPathfinder unwalkable start or goal" {
    const allocator = std.testing.allocator;

    var walkable: [100]bool = undefined;
    @memset(&walkable, true);
    walkable[0] = false; // Start unwalkable
    walkable[99] = false; // Goal unwalkable

    var pathfinder = AStarPathfinder.initWithGrid(allocator, 10, 10, &walkable);

    var path1 = try pathfinder.findPath(Coord.init(0, 0), Coord.init(5, 5));
    defer path1.deinit();
    try std.testing.expect(!path1.complete);

    var path2 = try pathfinder.findPath(Coord.init(5, 5), Coord.init(9, 9));
    defer path2.deinit();
    try std.testing.expect(!path2.complete);
}

test "AStarPathfinder variable movement costs" {
    const allocator = std.testing.allocator;

    var walkable: [100]bool = undefined;
    @memset(&walkable, true);

    var cost_grid: [100]f32 = undefined;
    @memset(&cost_grid, 1.0);

    // Create a "swamp" in the middle - expensive to traverse
    var y: usize = 3;
    while (y < 7) : (y += 1) {
        var x: usize = 3;
        while (x < 7) : (x += 1) {
            cost_grid[x + y * 10] = 10.0; // 10x more expensive
        }
    }

    var pathfinder = AStarPathfinder.initWithGrid(allocator, 10, 10, &walkable);
    pathfinder.setCostGrid(&cost_grid);

    // Path should avoid the expensive middle area
    var path = try pathfinder.findPath(Coord.init(0, 5), Coord.init(9, 5));
    defer path.deinit();

    try std.testing.expect(path.complete);

    // Check that path avoids expensive area (should go around)
    var enters_swamp = false;
    for (path.points.items) |point| {
        if (point.x >= 3 and point.x <= 6 and point.y >= 3 and point.y <= 6) {
            enters_swamp = true;
            break;
        }
    }
    // With 10x cost, it's cheaper to go around
    try std.testing.expect(!enters_swamp);
}

test "AStarPathfinder path smoothing" {
    const allocator = std.testing.allocator;

    var walkable: [100]bool = undefined;
    @memset(&walkable, true);

    var pathfinder = AStarPathfinder.initWithGrid(allocator, 10, 10, &walkable);
    pathfinder.setConfig(.{ .allow_diagonal = false }); // Force zigzag path

    var path = try pathfinder.findPath(Coord.init(0, 0), Coord.init(9, 9));
    defer path.deinit();

    try std.testing.expect(path.complete);

    const original_len = path.len();

    // Smooth the path
    try pathfinder.smoothPath(&path);

    // Smoothed path should be shorter (fewer waypoints)
    try std.testing.expect(path.len() < original_len);

    // Should still start and end at correct points
    try std.testing.expect(path.points.items[0].eql(Coord.init(0, 0)));
    try std.testing.expect(path.points.items[path.points.items.len - 1].eql(Coord.init(9, 9)));
}

test "AStarPathfinder line of sight" {
    const allocator = std.testing.allocator;

    var walkable: [100]bool = undefined;
    @memset(&walkable, true);

    var pathfinder = AStarPathfinder.initWithGrid(allocator, 10, 10, &walkable);

    // Clear line of sight
    try std.testing.expect(pathfinder.hasLineOfSight(Coord.init(0, 0), Coord.init(9, 9)));

    // Add obstacle blocking line of sight
    walkable[5 + 5 * 10] = false; // Block (5,5)
    try std.testing.expect(!pathfinder.hasLineOfSight(Coord.init(0, 0), Coord.init(9, 9)));
}

test "AStarPathfinder dynamic obstacles" {
    const allocator = std.testing.allocator;

    var walkable: [100]bool = undefined;
    @memset(&walkable, true);

    var pathfinder = AStarPathfinder.initWithGrid(allocator, 10, 10, &walkable);

    // Initial path should be direct
    var path1 = try pathfinder.findPath(Coord.init(0, 5), Coord.init(9, 5));
    defer path1.deinit();
    try std.testing.expect(path1.complete);

    // Add obstacle
    pathfinder.setObstacle(5, 5, true);

    // New path should avoid obstacle
    var path2 = try pathfinder.findPath(Coord.init(0, 5), Coord.init(9, 5));
    defer path2.deinit();
    try std.testing.expect(path2.complete);

    // Path should not go through (5,5)
    var goes_through_obstacle = false;
    for (path2.points.items) |point| {
        if (point.x == 5 and point.y == 5) {
            goes_through_obstacle = true;
            break;
        }
    }
    try std.testing.expect(!goes_through_obstacle);
}

test "AStarPathfinder corner cutting prevention" {
    const allocator = std.testing.allocator;

    var walkable: [100]bool = undefined;
    @memset(&walkable, true);

    // Create L-shaped obstacle
    walkable[5 + 4 * 10] = false; // (5,4)
    walkable[4 + 5 * 10] = false; // (4,5)

    var pathfinder = AStarPathfinder.initWithGrid(allocator, 10, 10, &walkable);

    var path = try pathfinder.findPath(Coord.init(4, 4), Coord.init(5, 5));
    defer path.deinit();

    try std.testing.expect(path.complete);

    // Path should not cut diagonally from (4,4) to (5,5)
    // It must go through either (4,5) or (5,4) - but both are blocked
    // So it must go around
    try std.testing.expect(path.len() > 2);
}

test "AStarPathfinder max iterations limit" {
    const allocator = std.testing.allocator;

    var walkable: [10000]bool = undefined;
    @memset(&walkable, true);

    var pathfinder = AStarPathfinder.initWithGrid(allocator, 100, 100, &walkable);
    pathfinder.setConfig(.{ .max_iterations = 10 });

    // With only 10 iterations, finding a path across a 100x100 grid won't succeed
    var path = try pathfinder.findPath(Coord.init(0, 0), Coord.init(99, 99));
    defer path.deinit();

    try std.testing.expect(!path.complete);
}

test "AStarPathfinder with callback" {
    const allocator = std.testing.allocator;

    const Context = struct {
        blocked_x: i32,

        fn isWalkable(x: i32, y: i32, user_data: ?*anyopaque) bool {
            _ = y;
            const ctx: *@This() = @ptrCast(@alignCast(user_data.?));
            return x != ctx.blocked_x;
        }
    };

    var ctx = Context{ .blocked_x = 5 };

    var pathfinder = AStarPathfinder.initWithCallback(allocator, 10, 10, Context.isWalkable, &ctx);

    var path = try pathfinder.findPath(Coord.init(0, 5), Coord.init(9, 5));
    defer path.deinit();

    try std.testing.expect(path.complete);

    // Path should not go through x=5
    for (path.points.items) |point| {
        try std.testing.expect(point.x != 5);
    }
}

test "AStarPathfinder heuristic weight" {
    const allocator = std.testing.allocator;

    var walkable: [100]bool = undefined;
    @memset(&walkable, true);

    // Higher weight should find paths faster but potentially less optimal
    var pathfinder = AStarPathfinder.initWithGrid(allocator, 10, 10, &walkable);
    pathfinder.setConfig(.{ .heuristic_weight = 2.0 });

    var path = try pathfinder.findPath(Coord.init(0, 0), Coord.init(9, 9));
    defer path.deinit();

    try std.testing.expect(path.complete);
}

test "AStarPathfinder setWalkable" {
    const allocator = std.testing.allocator;

    var walkable: [100]bool = undefined;
    @memset(&walkable, true);

    var pathfinder = AStarPathfinder.initWithGrid(allocator, 10, 10, &walkable);

    // Block a cell
    pathfinder.setWalkable(5, 5, false);
    try std.testing.expect(!pathfinder.isWalkable(5, 5));

    // Unblock it
    pathfinder.setWalkable(5, 5, true);
    try std.testing.expect(pathfinder.isWalkable(5, 5));
}

test "AStarPathfinder adjacent path" {
    const allocator = std.testing.allocator;

    var walkable: [100]bool = undefined;
    @memset(&walkable, true);

    var pathfinder = AStarPathfinder.initWithGrid(allocator, 10, 10, &walkable);

    // Path to adjacent cell
    var path = try pathfinder.findPath(Coord.init(5, 5), Coord.init(6, 5));
    defer path.deinit();

    try std.testing.expect(path.complete);
    try std.testing.expectEqual(@as(usize, 2), path.len());
}

test "AStarPathfinder batch obstacles" {
    const allocator = std.testing.allocator;

    var walkable: [100]bool = undefined;
    @memset(&walkable, true);

    var pathfinder = AStarPathfinder.initWithGrid(allocator, 10, 10, &walkable);

    const obstacles = [_]Coord{
        Coord.init(5, 0),
        Coord.init(5, 1),
        Coord.init(5, 2),
        Coord.init(5, 3),
    };

    pathfinder.setObstacles(&obstacles, true);

    try std.testing.expect(!pathfinder.isWalkable(5, 0));
    try std.testing.expect(!pathfinder.isWalkable(5, 1));
    try std.testing.expect(!pathfinder.isWalkable(5, 2));
    try std.testing.expect(!pathfinder.isWalkable(5, 3));
}
