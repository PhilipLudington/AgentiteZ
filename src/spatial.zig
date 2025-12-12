// spatial.zig
// High-performance spatial indexing for game entities
//
// Provides O(1) entity insertion/removal and efficient spatial queries
// using grid-based spatial hashing. Ideal for:
// - Collision detection
// - Proximity queries (entities near a point)
// - Range queries (entities within radius or rectangle)
// - Nearest neighbor search
//
// The grid cell size should be chosen based on typical query radius.
// For best performance, cell_size should be approximately equal to
// the most common query radius.

const std = @import("std");

/// 2D vector for positions
pub const Vec2 = struct {
    x: f32,
    y: f32,

    pub fn init(x: f32, y: f32) Vec2 {
        return .{ .x = x, .y = y };
    }

    pub fn zero() Vec2 {
        return .{ .x = 0, .y = 0 };
    }

    pub fn add(self: Vec2, other: Vec2) Vec2 {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }

    pub fn sub(self: Vec2, other: Vec2) Vec2 {
        return .{ .x = self.x - other.x, .y = self.y - other.y };
    }

    pub fn scale(self: Vec2, s: f32) Vec2 {
        return .{ .x = self.x * s, .y = self.y * s };
    }

    pub fn lengthSquared(self: Vec2) f32 {
        return self.x * self.x + self.y * self.y;
    }

    pub fn length(self: Vec2) f32 {
        return @sqrt(self.lengthSquared());
    }

    pub fn distance(self: Vec2, other: Vec2) f32 {
        return self.sub(other).length();
    }

    pub fn distanceSquared(self: Vec2, other: Vec2) f32 {
        return self.sub(other).lengthSquared();
    }
};

/// Axis-aligned bounding box for rectangle queries
pub const AABB = struct {
    min_x: f32,
    min_y: f32,
    max_x: f32,
    max_y: f32,

    /// Create AABB from center and half-extents
    pub fn fromCenterSize(ctr: Vec2, half_width: f32, half_height: f32) AABB {
        return .{
            .min_x = ctr.x - half_width,
            .min_y = ctr.y - half_height,
            .max_x = ctr.x + half_width,
            .max_y = ctr.y + half_height,
        };
    }

    /// Create AABB from corner and size
    pub fn fromRect(x: f32, y: f32, w: f32, h: f32) AABB {
        return .{
            .min_x = x,
            .min_y = y,
            .max_x = x + w,
            .max_y = y + h,
        };
    }

    /// Check if point is inside AABB
    pub fn containsPoint(self: AABB, point: Vec2) bool {
        return point.x >= self.min_x and point.x <= self.max_x and
            point.y >= self.min_y and point.y <= self.max_y;
    }

    /// Check if two AABBs overlap
    pub fn overlaps(self: AABB, other: AABB) bool {
        return self.min_x <= other.max_x and self.max_x >= other.min_x and
            self.min_y <= other.max_y and self.max_y >= other.min_y;
    }

    /// Get center of AABB
    pub fn center(self: AABB) Vec2 {
        return .{
            .x = (self.min_x + self.max_x) * 0.5,
            .y = (self.min_y + self.max_y) * 0.5,
        };
    }

    /// Get width of AABB
    pub fn width(self: AABB) f32 {
        return self.max_x - self.min_x;
    }

    /// Get height of AABB
    pub fn height(self: AABB) f32 {
        return self.max_y - self.min_y;
    }
};

/// Cell key for spatial hashing
pub const CellKey = struct {
    x: i32,
    y: i32,
};

/// Entry stored in spatial index
fn SpatialEntry(comptime T: type) type {
    return struct {
        id: T,
        position: Vec2,
    };
}

/// Configuration options for SpatialIndex
pub const SpatialIndexConfig = struct {
    /// Size of each grid cell. For best performance, should be approximately
    /// equal to the typical query radius.
    cell_size: f32 = 64.0,

    /// Initial capacity for the cell hash map
    initial_cell_capacity: u32 = 256,

    /// Initial capacity for entity lists within each cell
    initial_list_capacity: u32 = 16,
};

/// Grid-based spatial index for fast proximity queries
///
/// Generic over entity ID type T, which must be hashable and equatable.
/// Common choices: u32, u64, Entity (from ECS), or custom ID types.
///
/// Performance characteristics:
/// - Insert: O(1) amortized
/// - Remove: O(k) where k is entities in the cell
/// - Update position: O(k) for old cell + O(1) for new cell
/// - Query radius: O(cells_checked * entities_per_cell)
/// - Query rectangle: O(cells_checked * entities_per_cell)
/// - Nearest neighbor: O(cells_checked * entities_per_cell)
pub fn SpatialIndex(comptime T: type) type {
    return struct {
        const Self = @This();
        const Entry = SpatialEntry(T);
        const CellList = std.ArrayList(Entry);
        const CellMap = std.AutoHashMap(CellKey, CellList);
        const EntityPositionMap = std.AutoHashMap(T, Vec2);

        /// Map from cell key to list of entries in that cell
        cells: CellMap,

        /// Map from entity ID to its current position (for fast removal/update)
        entity_positions: EntityPositionMap,

        /// Size of each grid cell
        cell_size: f32,

        /// Initial capacity for new cell lists
        initial_list_capacity: u32,

        /// Memory allocator
        allocator: std.mem.Allocator,

        /// Initialize a new spatial index
        pub fn init(allocator: std.mem.Allocator, config: SpatialIndexConfig) Self {
            return .{
                .cells = CellMap.init(allocator),
                .entity_positions = EntityPositionMap.init(allocator),
                .cell_size = config.cell_size,
                .initial_list_capacity = config.initial_list_capacity,
                .allocator = allocator,
            };
        }

        /// Free all resources
        pub fn deinit(self: *Self) void {
            // Free all cell lists
            var cell_iter = self.cells.valueIterator();
            while (cell_iter.next()) |list| {
                list.deinit();
            }
            self.cells.deinit();
            self.entity_positions.deinit();
        }

        /// Clear all entities from the index
        pub fn clear(self: *Self) void {
            var cell_iter = self.cells.valueIterator();
            while (cell_iter.next()) |list| {
                list.deinit();
            }
            self.cells.clearRetainingCapacity();
            self.entity_positions.clearRetainingCapacity();
        }

        /// Get the number of entities in the index
        pub fn count(self: *const Self) usize {
            return self.entity_positions.count();
        }

        /// Check if an entity is in the index
        pub fn contains(self: *const Self, id: T) bool {
            return self.entity_positions.contains(id);
        }

        /// Get the position of an entity (if it exists)
        pub fn getPosition(self: *const Self, id: T) ?Vec2 {
            return self.entity_positions.get(id);
        }

        /// Insert an entity at a position
        /// Returns error if entity already exists (use update instead)
        pub fn insert(self: *Self, id: T, position: Vec2) !void {
            // Check if entity already exists
            if (self.entity_positions.contains(id)) {
                return error.EntityAlreadyExists;
            }

            // Track entity position
            try self.entity_positions.put(id, position);

            // Add to appropriate cell
            const key = self.getCellKey(position);
            const result = try self.cells.getOrPut(key);
            if (!result.found_existing) {
                result.value_ptr.* = CellList.init(self.allocator);
                try result.value_ptr.ensureTotalCapacity(self.initial_list_capacity);
            }

            try result.value_ptr.append(.{ .id = id, .position = position });
        }

        /// Remove an entity from the index
        /// Returns the entity's position if found, null otherwise
        pub fn remove(self: *Self, id: T) ?Vec2 {
            // Get and remove the entity's tracked position
            const kv = self.entity_positions.fetchRemove(id);
            if (kv == null) return null;

            const position = kv.?.value;
            const key = self.getCellKey(position);

            // Remove from cell list
            if (self.cells.getPtr(key)) |list| {
                for (list.items, 0..) |entry, i| {
                    if (entry.id == id) {
                        _ = list.swapRemove(i);
                        break;
                    }
                }

                // Clean up empty cells (optional, helps memory)
                if (list.items.len == 0) {
                    list.deinit();
                    _ = self.cells.remove(key);
                }
            }

            return position;
        }

        /// Update an entity's position
        /// More efficient than remove + insert for entities that move frequently
        pub fn update(self: *Self, id: T, new_position: Vec2) !void {
            const old_position = self.entity_positions.get(id) orelse {
                return error.EntityNotFound;
            };

            const old_key = self.getCellKey(old_position);
            const new_key = self.getCellKey(new_position);

            // Update tracked position
            try self.entity_positions.put(id, new_position);

            // If staying in same cell, just update position in place
            if (old_key.x == new_key.x and old_key.y == new_key.y) {
                if (self.cells.getPtr(old_key)) |list| {
                    for (list.items) |*entry| {
                        if (entry.id == id) {
                            entry.position = new_position;
                            break;
                        }
                    }
                }
                return;
            }

            // Remove from old cell
            if (self.cells.getPtr(old_key)) |list| {
                for (list.items, 0..) |entry, i| {
                    if (entry.id == id) {
                        _ = list.swapRemove(i);
                        break;
                    }
                }

                // Clean up empty cells
                if (list.items.len == 0) {
                    list.deinit();
                    _ = self.cells.remove(old_key);
                }
            }

            // Add to new cell
            const result = try self.cells.getOrPut(new_key);
            if (!result.found_existing) {
                result.value_ptr.* = CellList.init(self.allocator);
                try result.value_ptr.ensureTotalCapacity(self.initial_list_capacity);
            }
            try result.value_ptr.append(.{ .id = id, .position = new_position });
        }

        /// Query all entities within a radius of a point
        /// Returns a list of (id, position) pairs
        pub fn queryRadius(
            self: *Self,
            center: Vec2,
            radius: f32,
            allocator: std.mem.Allocator,
        ) !std.ArrayList(Entry) {
            var results = std.ArrayList(Entry).init(allocator);
            errdefer results.deinit();

            const radius_squared = radius * radius;

            // Calculate cell range to check
            const min_x = self.getCellCoord(center.x - radius);
            const max_x = self.getCellCoord(center.x + radius);
            const min_y = self.getCellCoord(center.y - radius);
            const max_y = self.getCellCoord(center.y + radius);

            // Check all cells in range
            var y: i32 = min_y;
            while (y <= max_y) : (y += 1) {
                var x: i32 = min_x;
                while (x <= max_x) : (x += 1) {
                    const key = CellKey{ .x = x, .y = y };
                    if (self.cells.get(key)) |cell_list| {
                        for (cell_list.items) |entry| {
                            // Exact distance check (cell check is conservative)
                            const dist_sq = center.distanceSquared(entry.position);
                            if (dist_sq <= radius_squared) {
                                try results.append(entry);
                            }
                        }
                    }
                }
            }

            return results;
        }

        /// Query all entities within an axis-aligned bounding box
        pub fn queryRect(
            self: *Self,
            rect: AABB,
            allocator: std.mem.Allocator,
        ) !std.ArrayList(Entry) {
            var results = std.ArrayList(Entry).init(allocator);
            errdefer results.deinit();

            // Calculate cell range to check
            const min_x = self.getCellCoord(rect.min_x);
            const max_x = self.getCellCoord(rect.max_x);
            const min_y = self.getCellCoord(rect.min_y);
            const max_y = self.getCellCoord(rect.max_y);

            // Check all cells in range
            var y: i32 = min_y;
            while (y <= max_y) : (y += 1) {
                var x: i32 = min_x;
                while (x <= max_x) : (x += 1) {
                    const key = CellKey{ .x = x, .y = y };
                    if (self.cells.get(key)) |cell_list| {
                        for (cell_list.items) |entry| {
                            // Exact containment check
                            if (rect.containsPoint(entry.position)) {
                                try results.append(entry);
                            }
                        }
                    }
                }
            }

            return results;
        }

        /// Find the nearest neighbor to a point within a maximum radius
        /// Returns null if no entity is found within the radius
        pub fn findNearest(
            self: *Self,
            center: Vec2,
            max_radius: f32,
        ) ?NearestResult(T) {
            var best: ?NearestResult(T) = null;
            var best_dist_sq: f32 = max_radius * max_radius;

            // Start with the cell containing the center point
            // Then expand outward in a spiral pattern
            const center_cell_x = self.getCellCoord(center.x);
            const center_cell_y = self.getCellCoord(center.y);

            // Maximum cells to check based on radius
            const cells_to_check = @as(i32, @intFromFloat(@ceil(max_radius / self.cell_size))) + 1;

            // Check cells in expanding rings
            var ring: i32 = 0;
            while (ring <= cells_to_check) : (ring += 1) {
                // Early exit: if we found something and the ring is far enough
                // that no closer entity could exist, we're done
                if (best != null and ring > 0) {
                    const ring_min_dist = @as(f32, @floatFromInt(ring - 1)) * self.cell_size;
                    if (ring_min_dist * ring_min_dist > best_dist_sq) {
                        break;
                    }
                }

                // Check all cells in this ring
                var dy: i32 = -ring;
                while (dy <= ring) : (dy += 1) {
                    var dx: i32 = -ring;
                    while (dx <= ring) : (dx += 1) {
                        // Only check cells on the ring perimeter
                        if (@abs(dx) != ring and @abs(dy) != ring) {
                            continue;
                        }

                        const key = CellKey{
                            .x = center_cell_x + dx,
                            .y = center_cell_y + dy,
                        };

                        if (self.cells.get(key)) |cell_list| {
                            for (cell_list.items) |entry| {
                                const dist_sq = center.distanceSquared(entry.position);
                                if (dist_sq < best_dist_sq) {
                                    best_dist_sq = dist_sq;
                                    best = .{
                                        .id = entry.id,
                                        .position = entry.position,
                                        .distance = @sqrt(dist_sq),
                                    };
                                }
                            }
                        }
                    }
                }
            }

            return best;
        }

        /// Find the K nearest neighbors to a point
        /// Returns at most k results, sorted by distance (closest first)
        pub fn findKNearest(
            self: *Self,
            center: Vec2,
            k: usize,
            max_radius: f32,
            allocator: std.mem.Allocator,
        ) !std.ArrayList(NearestResult(T)) {
            var results = std.ArrayList(NearestResult(T)).init(allocator);
            errdefer results.deinit();

            if (k == 0) return results;

            // First, collect all entities within radius
            const radius_squared = max_radius * max_radius;
            const min_x = self.getCellCoord(center.x - max_radius);
            const max_x = self.getCellCoord(center.x + max_radius);
            const min_y = self.getCellCoord(center.y - max_radius);
            const max_y = self.getCellCoord(center.y + max_radius);

            // Temporary list for candidates
            var candidates = std.ArrayList(NearestResult(T)).init(allocator);
            defer candidates.deinit();

            var y: i32 = min_y;
            while (y <= max_y) : (y += 1) {
                var x: i32 = min_x;
                while (x <= max_x) : (x += 1) {
                    const key = CellKey{ .x = x, .y = y };
                    if (self.cells.get(key)) |cell_list| {
                        for (cell_list.items) |entry| {
                            const dist_sq = center.distanceSquared(entry.position);
                            if (dist_sq <= radius_squared) {
                                try candidates.append(.{
                                    .id = entry.id,
                                    .position = entry.position,
                                    .distance = @sqrt(dist_sq),
                                });
                            }
                        }
                    }
                }
            }

            // Sort by distance
            std.mem.sort(NearestResult(T), candidates.items, {}, struct {
                fn lessThan(_: void, a: NearestResult(T), b: NearestResult(T)) bool {
                    return a.distance < b.distance;
                }
            }.lessThan);

            // Take top k
            const count_to_take = @min(k, candidates.items.len);
            for (candidates.items[0..count_to_take]) |item| {
                try results.append(item);
            }

            return results;
        }

        /// Get all entities in a specific cell (useful for debugging)
        pub fn getCell(self: *const Self, cell_x: i32, cell_y: i32) ?[]const Entry {
            const key = CellKey{ .x = cell_x, .y = cell_y };
            if (self.cells.get(key)) |list| {
                return list.items;
            }
            return null;
        }

        /// Get the cell coordinates for a world position
        pub fn getCellCoords(self: *const Self, position: Vec2) struct { x: i32, y: i32 } {
            return .{
                .x = self.getCellCoord(position.x),
                .y = self.getCellCoord(position.y),
            };
        }

        /// Get statistics about the spatial index (for debugging/profiling)
        pub fn getStats(self: *const Self) SpatialIndexStats {
            var total_entries: usize = 0;
            var max_cell_size: usize = 0;
            var min_cell_size: usize = std.math.maxInt(usize);
            var non_empty_cells: usize = 0;

            var cell_iter = self.cells.valueIterator();
            while (cell_iter.next()) |list| {
                const len = list.items.len;
                if (len > 0) {
                    non_empty_cells += 1;
                    total_entries += len;
                    max_cell_size = @max(max_cell_size, len);
                    min_cell_size = @min(min_cell_size, len);
                }
            }

            if (non_empty_cells == 0) {
                min_cell_size = 0;
            }

            return .{
                .total_entities = self.entity_positions.count(),
                .non_empty_cells = non_empty_cells,
                .total_cell_capacity = self.cells.capacity(),
                .max_entities_per_cell = max_cell_size,
                .min_entities_per_cell = min_cell_size,
                .avg_entities_per_cell = if (non_empty_cells > 0)
                    @as(f32, @floatFromInt(total_entries)) / @as(f32, @floatFromInt(non_empty_cells))
                else
                    0.0,
                .cell_size = self.cell_size,
            };
        }

        // Internal: Get cell coordinate for a single axis
        fn getCellCoord(self: *const Self, coord: f32) i32 {
            return @intFromFloat(@floor(coord / self.cell_size));
        }

        // Internal: Get cell key for a position
        fn getCellKey(self: *const Self, position: Vec2) CellKey {
            return .{
                .x = self.getCellCoord(position.x),
                .y = self.getCellCoord(position.y),
            };
        }
    };
}

/// Result from nearest neighbor search
pub fn NearestResult(comptime T: type) type {
    return struct {
        id: T,
        position: Vec2,
        distance: f32,
    };
}

/// Statistics about spatial index for debugging/profiling
pub const SpatialIndexStats = struct {
    total_entities: usize,
    non_empty_cells: usize,
    total_cell_capacity: usize,
    max_entities_per_cell: usize,
    min_entities_per_cell: usize,
    avg_entities_per_cell: f32,
    cell_size: f32,
};

// ============================================================================
// Tests
// ============================================================================

test "Vec2 operations" {
    const a = Vec2.init(3.0, 4.0);
    const b = Vec2.init(1.0, 2.0);

    // Addition
    const sum = a.add(b);
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), sum.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 6.0), sum.y, 0.001);

    // Subtraction
    const diff = a.sub(b);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), diff.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), diff.y, 0.001);

    // Length
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), a.length(), 0.001);

    // Distance
    try std.testing.expectApproxEqAbs(@as(f32, 2.828), a.distance(b), 0.01);
}

test "AABB operations" {
    const box = AABB.fromRect(10.0, 20.0, 100.0, 50.0);

    // Contains point
    try std.testing.expect(box.containsPoint(Vec2.init(50.0, 40.0)));
    try std.testing.expect(!box.containsPoint(Vec2.init(5.0, 40.0)));
    try std.testing.expect(!box.containsPoint(Vec2.init(50.0, 100.0)));

    // Center
    const c = box.center();
    try std.testing.expectApproxEqAbs(@as(f32, 60.0), c.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 45.0), c.y, 0.001);

    // Dimensions
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), box.width(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), box.height(), 0.001);

    // Overlaps
    const box2 = AABB.fromRect(100.0, 50.0, 50.0, 50.0);
    try std.testing.expect(box.overlaps(box2)); // Shares edge

    const box3 = AABB.fromRect(200.0, 200.0, 50.0, 50.0);
    try std.testing.expect(!box.overlaps(box3)); // No overlap
}

test "SpatialIndex insert and contains" {
    const allocator = std.testing.allocator;
    var index = SpatialIndex(u32).init(allocator, .{ .cell_size = 64.0 });
    defer index.deinit();

    try index.insert(1, Vec2.init(100.0, 100.0));
    try index.insert(2, Vec2.init(200.0, 150.0));
    try index.insert(3, Vec2.init(-50.0, -50.0));

    try std.testing.expect(index.contains(1));
    try std.testing.expect(index.contains(2));
    try std.testing.expect(index.contains(3));
    try std.testing.expect(!index.contains(4));
    try std.testing.expectEqual(@as(usize, 3), index.count());

    // Duplicate insert should fail
    try std.testing.expectError(error.EntityAlreadyExists, index.insert(1, Vec2.init(0.0, 0.0)));
}

test "SpatialIndex remove" {
    const allocator = std.testing.allocator;
    var index = SpatialIndex(u32).init(allocator, .{ .cell_size = 64.0 });
    defer index.deinit();

    try index.insert(1, Vec2.init(100.0, 100.0));
    try index.insert(2, Vec2.init(200.0, 150.0));

    // Remove existing
    const pos = index.remove(1);
    try std.testing.expect(pos != null);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), pos.?.x, 0.001);
    try std.testing.expect(!index.contains(1));
    try std.testing.expectEqual(@as(usize, 1), index.count());

    // Remove non-existing
    try std.testing.expect(index.remove(999) == null);
}

test "SpatialIndex update position" {
    const allocator = std.testing.allocator;
    var index = SpatialIndex(u32).init(allocator, .{ .cell_size = 64.0 });
    defer index.deinit();

    try index.insert(1, Vec2.init(100.0, 100.0));

    // Update within same cell
    try index.update(1, Vec2.init(110.0, 110.0));
    const pos1 = index.getPosition(1).?;
    try std.testing.expectApproxEqAbs(@as(f32, 110.0), pos1.x, 0.001);

    // Update to different cell
    try index.update(1, Vec2.init(500.0, 500.0));
    const pos2 = index.getPosition(1).?;
    try std.testing.expectApproxEqAbs(@as(f32, 500.0), pos2.x, 0.001);

    // Update non-existing should fail
    try std.testing.expectError(error.EntityNotFound, index.update(999, Vec2.init(0.0, 0.0)));
}

test "SpatialIndex queryRadius" {
    const allocator = std.testing.allocator;
    var index = SpatialIndex(u32).init(allocator, .{ .cell_size = 64.0 });
    defer index.deinit();

    // Place entities in a pattern
    try index.insert(1, Vec2.init(0.0, 0.0));
    try index.insert(2, Vec2.init(50.0, 0.0));
    try index.insert(3, Vec2.init(100.0, 0.0));
    try index.insert(4, Vec2.init(200.0, 0.0));

    // Query around origin with radius 75
    var results = try index.queryRadius(Vec2.init(0.0, 0.0), 75.0, allocator);
    defer results.deinit();

    // Should find entities 1 and 2
    try std.testing.expectEqual(@as(usize, 2), results.items.len);

    var found1 = false;
    var found2 = false;
    for (results.items) |entry| {
        if (entry.id == 1) found1 = true;
        if (entry.id == 2) found2 = true;
    }
    try std.testing.expect(found1);
    try std.testing.expect(found2);
}

test "SpatialIndex queryRect" {
    const allocator = std.testing.allocator;
    var index = SpatialIndex(u32).init(allocator, .{ .cell_size = 64.0 });
    defer index.deinit();

    try index.insert(1, Vec2.init(10.0, 10.0));
    try index.insert(2, Vec2.init(50.0, 50.0));
    try index.insert(3, Vec2.init(100.0, 100.0));
    try index.insert(4, Vec2.init(200.0, 200.0));

    var results = try index.queryRect(AABB.fromRect(0.0, 0.0, 80.0, 80.0), allocator);
    defer results.deinit();

    try std.testing.expectEqual(@as(usize, 2), results.items.len);
}

test "SpatialIndex findNearest" {
    const allocator = std.testing.allocator;
    var index = SpatialIndex(u32).init(allocator, .{ .cell_size = 64.0 });
    defer index.deinit();

    try index.insert(1, Vec2.init(100.0, 100.0));
    try index.insert(2, Vec2.init(50.0, 50.0));
    try index.insert(3, Vec2.init(200.0, 200.0));

    // Find nearest to origin
    const nearest = index.findNearest(Vec2.init(0.0, 0.0), 500.0);
    try std.testing.expect(nearest != null);
    try std.testing.expectEqual(@as(u32, 2), nearest.?.id);

    // Find nearest with limited radius (should not find any)
    const none = index.findNearest(Vec2.init(0.0, 0.0), 10.0);
    try std.testing.expect(none == null);
}

test "SpatialIndex findKNearest" {
    const allocator = std.testing.allocator;
    var index = SpatialIndex(u32).init(allocator, .{ .cell_size = 64.0 });
    defer index.deinit();

    try index.insert(1, Vec2.init(100.0, 100.0));
    try index.insert(2, Vec2.init(50.0, 50.0));
    try index.insert(3, Vec2.init(200.0, 200.0));
    try index.insert(4, Vec2.init(75.0, 75.0));

    var results = try index.findKNearest(Vec2.init(0.0, 0.0), 2, 500.0, allocator);
    defer results.deinit();

    // Should get 2 nearest
    try std.testing.expectEqual(@as(usize, 2), results.items.len);

    // First should be closest (entity 2 at 50,50)
    try std.testing.expectEqual(@as(u32, 2), results.items[0].id);

    // Second should be entity 4 at 75,75
    try std.testing.expectEqual(@as(u32, 4), results.items[1].id);
}

test "SpatialIndex clear" {
    const allocator = std.testing.allocator;
    var index = SpatialIndex(u32).init(allocator, .{ .cell_size = 64.0 });
    defer index.deinit();

    try index.insert(1, Vec2.init(100.0, 100.0));
    try index.insert(2, Vec2.init(200.0, 200.0));

    index.clear();

    try std.testing.expectEqual(@as(usize, 0), index.count());
    try std.testing.expect(!index.contains(1));
    try std.testing.expect(!index.contains(2));
}

test "SpatialIndex getStats" {
    const allocator = std.testing.allocator;
    var index = SpatialIndex(u32).init(allocator, .{ .cell_size = 64.0 });
    defer index.deinit();

    // Empty index stats
    var stats = index.getStats();
    try std.testing.expectEqual(@as(usize, 0), stats.total_entities);
    try std.testing.expectEqual(@as(usize, 0), stats.non_empty_cells);

    // Add some entities
    try index.insert(1, Vec2.init(0.0, 0.0));
    try index.insert(2, Vec2.init(10.0, 10.0)); // Same cell as 1
    try index.insert(3, Vec2.init(200.0, 200.0)); // Different cell

    stats = index.getStats();
    try std.testing.expectEqual(@as(usize, 3), stats.total_entities);
    try std.testing.expectEqual(@as(usize, 2), stats.non_empty_cells);
    try std.testing.expectEqual(@as(usize, 2), stats.max_entities_per_cell);
    try std.testing.expectEqual(@as(usize, 1), stats.min_entities_per_cell);
}

test "SpatialIndex negative coordinates" {
    const allocator = std.testing.allocator;
    var index = SpatialIndex(u32).init(allocator, .{ .cell_size = 64.0 });
    defer index.deinit();

    try index.insert(1, Vec2.init(-100.0, -100.0));
    try index.insert(2, Vec2.init(-50.0, 50.0));
    try index.insert(3, Vec2.init(50.0, -50.0));

    var results = try index.queryRadius(Vec2.init(0.0, 0.0), 150.0, allocator);
    defer results.deinit();

    try std.testing.expectEqual(@as(usize, 3), results.items.len);
}

test "SpatialIndex cell boundary" {
    const allocator = std.testing.allocator;
    var index = SpatialIndex(u32).init(allocator, .{ .cell_size = 100.0 });
    defer index.deinit();

    // Place entities right on cell boundaries
    try index.insert(1, Vec2.init(0.0, 0.0));
    try index.insert(2, Vec2.init(100.0, 0.0)); // Next cell
    try index.insert(3, Vec2.init(99.9, 0.0)); // Same cell as 1

    const coords1 = index.getCellCoords(Vec2.init(0.0, 0.0));
    const coords2 = index.getCellCoords(Vec2.init(100.0, 0.0));
    const coords3 = index.getCellCoords(Vec2.init(99.9, 0.0));

    try std.testing.expectEqual(@as(i32, 0), coords1.x);
    try std.testing.expectEqual(@as(i32, 1), coords2.x);
    try std.testing.expectEqual(@as(i32, 0), coords3.x);
}

test "SpatialIndex many entities same cell" {
    const allocator = std.testing.allocator;
    var index = SpatialIndex(u32).init(allocator, .{ .cell_size = 1000.0 });
    defer index.deinit();

    // Insert many entities in same cell
    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        const x = @as(f32, @floatFromInt(i)) * 5.0;
        const y = @as(f32, @floatFromInt(i)) * 5.0;
        try index.insert(i, Vec2.init(x, y));
    }

    try std.testing.expectEqual(@as(usize, 100), index.count());

    var results = try index.queryRadius(Vec2.init(250.0, 250.0), 1000.0, allocator);
    defer results.deinit();

    try std.testing.expectEqual(@as(usize, 100), results.items.len);
}

test "SpatialIndex sparse distribution" {
    const allocator = std.testing.allocator;
    var index = SpatialIndex(u32).init(allocator, .{ .cell_size = 64.0 });
    defer index.deinit();

    // Place entities far apart
    try index.insert(1, Vec2.init(0.0, 0.0));
    try index.insert(2, Vec2.init(10000.0, 0.0));
    try index.insert(3, Vec2.init(0.0, 10000.0));
    try index.insert(4, Vec2.init(-10000.0, -10000.0));

    // Query around origin should only find entity 1
    var results = try index.queryRadius(Vec2.init(0.0, 0.0), 100.0, allocator);
    defer results.deinit();

    try std.testing.expectEqual(@as(usize, 1), results.items.len);
    try std.testing.expectEqual(@as(u32, 1), results.items[0].id);
}

test "SpatialIndex empty query" {
    const allocator = std.testing.allocator;
    var index = SpatialIndex(u32).init(allocator, .{ .cell_size = 64.0 });
    defer index.deinit();

    try index.insert(1, Vec2.init(1000.0, 1000.0));

    // Query far from any entity
    var results = try index.queryRadius(Vec2.init(0.0, 0.0), 100.0, allocator);
    defer results.deinit();

    try std.testing.expectEqual(@as(usize, 0), results.items.len);
}

test "SpatialIndex with different ID types" {
    const allocator = std.testing.allocator;

    // Test with u64
    var index_u64 = SpatialIndex(u64).init(allocator, .{ .cell_size = 64.0 });
    defer index_u64.deinit();
    try index_u64.insert(12345678901234, Vec2.init(100.0, 100.0));
    try std.testing.expect(index_u64.contains(12345678901234));

    // Test with custom struct ID
    const EntityId = struct {
        generation: u16,
        index: u16,
    };
    var index_custom = SpatialIndex(EntityId).init(allocator, .{ .cell_size = 64.0 });
    defer index_custom.deinit();
    const id = EntityId{ .generation = 1, .index = 42 };
    try index_custom.insert(id, Vec2.init(100.0, 100.0));
    try std.testing.expect(index_custom.contains(id));
}
