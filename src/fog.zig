//! Fog of War System - Visibility Management
//!
//! A tile-based fog of war system for strategy games supporting multiple players,
//! vision sources with range, and line-of-sight blocking.
//!
//! Features:
//! - Three visibility states (unexplored, explored, visible)
//! - Per-player fog state
//! - Vision sources with configurable range
//! - Line-of-sight blocking for terrain
//! - Efficient update with dirty tracking
//! - Support for shared vision between allies
//!
//! Usage:
//! ```zig
//! var fow = FogOfWar.init(allocator, .{ .width = 100, .height = 100 });
//! defer fow.deinit();
//!
//! const source = try fow.addVisionSource(.{ .x = 50, .y = 50, .range = 10, .player_id = 0 });
//! fow.update();
//!
//! const vis = fow.getVisibility(60, 55, 0);
//! if (vis == .visible) { ... }
//! ```

const std = @import("std");

const log = std.log.scoped(.fog);

/// Maximum number of players supported
pub const MAX_PLAYERS = 16;

/// Visibility state for a tile
pub const Visibility = enum(u8) {
    /// Never seen
    unexplored = 0,
    /// Previously seen but not currently visible
    explored = 1,
    /// Currently visible
    visible = 2,
};

/// Configuration for fog of war
pub const FogConfig = struct {
    /// Map width in tiles
    width: u32,
    /// Map height in tiles
    height: u32,
    /// Number of players
    player_count: u8 = 2,
    /// Whether explored areas remember terrain
    remember_explored: bool = true,
    /// Default vision range for new sources
    default_vision_range: u8 = 5,
};

/// A source of vision (unit, building, etc.)
pub const VisionSource = struct {
    /// Unique identifier
    id: u32,
    /// X position in tiles
    x: i32,
    /// Y position in tiles
    y: i32,
    /// Vision range in tiles
    range: u8,
    /// Owning player ID
    player_id: u8,
    /// Whether this source is active
    active: bool = true,
    /// Whether this source can see through blockers
    ignores_blockers: bool = false,
};

/// Vision source handle for external reference
pub const VisionSourceHandle = struct {
    id: u32,
};

/// Fog of War manager
pub const FogOfWar = struct {
    allocator: std.mem.Allocator,
    config: FogConfig,

    /// Per-player visibility grids (player_id -> grid)
    visibility: [][]Visibility,

    /// Blocking terrain grid (true = blocks vision)
    blockers: []bool,

    /// Active vision sources
    sources: std.AutoHashMap(u32, VisionSource),

    /// Next source ID
    next_source_id: u32,

    /// Players sharing vision (player_id -> set of allies)
    shared_vision: [MAX_PLAYERS]std.AutoHashMap(u8, void),

    /// Dirty flag for optimization
    needs_update: bool,

    /// Initialize fog of war
    pub fn init(allocator: std.mem.Allocator, config: FogConfig) !FogOfWar {
        const grid_size = @as(usize, config.width) * @as(usize, config.height);

        // Allocate visibility grids for each player
        const visibility = try allocator.alloc([]Visibility, config.player_count);
        errdefer allocator.free(visibility);

        for (0..config.player_count) |i| {
            visibility[i] = try allocator.alloc(Visibility, grid_size);
            @memset(visibility[i], .unexplored);
        }

        // Allocate blocker grid
        const blockers = try allocator.alloc(bool, grid_size);
        @memset(blockers, false);

        // Initialize shared vision maps
        var shared: [MAX_PLAYERS]std.AutoHashMap(u8, void) = undefined;
        for (0..MAX_PLAYERS) |i| {
            shared[i] = std.AutoHashMap(u8, void).init(allocator);
        }

        return FogOfWar{
            .allocator = allocator,
            .config = config,
            .visibility = visibility,
            .blockers = blockers,
            .sources = std.AutoHashMap(u32, VisionSource).init(allocator),
            .next_source_id = 1,
            .shared_vision = shared,
            .needs_update = true,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *FogOfWar) void {
        for (0..self.config.player_count) |i| {
            self.allocator.free(self.visibility[i]);
        }
        self.allocator.free(self.visibility);
        self.allocator.free(self.blockers);
        self.sources.deinit();

        for (0..MAX_PLAYERS) |i| {
            self.shared_vision[i].deinit();
        }
    }

    /// Add a vision source
    pub fn addVisionSource(self: *FogOfWar, source: struct {
        x: i32,
        y: i32,
        range: ?u8 = null,
        player_id: u8,
        active: bool = true,
        ignores_blockers: bool = false,
    }) !VisionSourceHandle {
        const id = self.next_source_id;
        self.next_source_id += 1;

        try self.sources.put(id, .{
            .id = id,
            .x = source.x,
            .y = source.y,
            .range = source.range orelse self.config.default_vision_range,
            .player_id = source.player_id,
            .active = source.active,
            .ignores_blockers = source.ignores_blockers,
        });

        self.needs_update = true;
        return .{ .id = id };
    }

    /// Remove a vision source
    pub fn removeVisionSource(self: *FogOfWar, handle: VisionSourceHandle) bool {
        if (self.sources.remove(handle.id)) {
            self.needs_update = true;
            return true;
        }
        return false;
    }

    /// Move a vision source
    pub fn moveVisionSource(self: *FogOfWar, handle: VisionSourceHandle, x: i32, y: i32) bool {
        if (self.sources.getPtr(handle.id)) |source| {
            if (source.x != x or source.y != y) {
                source.x = x;
                source.y = y;
                self.needs_update = true;
            }
            return true;
        }
        return false;
    }

    /// Set vision source range
    pub fn setVisionRange(self: *FogOfWar, handle: VisionSourceHandle, range: u8) bool {
        if (self.sources.getPtr(handle.id)) |source| {
            if (source.range != range) {
                source.range = range;
                self.needs_update = true;
            }
            return true;
        }
        return false;
    }

    /// Set vision source active state
    pub fn setVisionActive(self: *FogOfWar, handle: VisionSourceHandle, active: bool) bool {
        if (self.sources.getPtr(handle.id)) |source| {
            if (source.active != active) {
                source.active = active;
                self.needs_update = true;
            }
            return true;
        }
        return false;
    }

    /// Set a tile as blocking vision
    pub fn setBlocker(self: *FogOfWar, x: i32, y: i32, blocks: bool) void {
        if (self.getIndex(x, y)) |idx| {
            if (self.blockers[idx] != blocks) {
                self.blockers[idx] = blocks;
                self.needs_update = true;
            }
        }
    }

    /// Check if a tile blocks vision
    pub fn isBlocker(self: *const FogOfWar, x: i32, y: i32) bool {
        if (self.getIndex(x, y)) |idx| {
            return self.blockers[idx];
        }
        return true; // Out of bounds blocks
    }

    /// Clear all blockers
    pub fn clearBlockers(self: *FogOfWar) void {
        @memset(self.blockers, false);
        self.needs_update = true;
    }

    /// Set shared vision between players
    pub fn setSharedVision(self: *FogOfWar, player_a: u8, player_b: u8, shared: bool) !void {
        if (player_a >= MAX_PLAYERS or player_b >= MAX_PLAYERS) return;

        if (shared) {
            try self.shared_vision[player_a].put(player_b, {});
            try self.shared_vision[player_b].put(player_a, {});
        } else {
            _ = self.shared_vision[player_a].remove(player_b);
            _ = self.shared_vision[player_b].remove(player_a);
        }
        self.needs_update = true;
    }

    /// Check if players share vision
    pub fn hasSharedVision(self: *const FogOfWar, player_a: u8, player_b: u8) bool {
        if (player_a >= MAX_PLAYERS or player_b >= MAX_PLAYERS) return false;
        return self.shared_vision[player_a].contains(player_b);
    }

    /// Update fog of war (call after moving units or changing sources)
    pub fn update(self: *FogOfWar) void {
        if (!self.needs_update) return;

        // Step 1: Demote all "visible" to "explored" (if remembering)
        for (0..self.config.player_count) |player| {
            const grid = self.visibility[player];
            for (grid) |*cell| {
                if (cell.* == .visible) {
                    cell.* = if (self.config.remember_explored) .explored else .unexplored;
                }
            }
        }

        // Step 2: Apply vision from all active sources
        var iter = self.sources.iterator();
        while (iter.next()) |entry| {
            const source = entry.value_ptr;
            if (!source.active) continue;

            self.applyVision(source.*);
        }

        self.needs_update = false;
    }

    /// Force full update
    pub fn forceUpdate(self: *FogOfWar) void {
        self.needs_update = true;
        self.update();
    }

    /// Apply vision from a single source
    fn applyVision(self: *FogOfWar, source: VisionSource) void {
        const range: i32 = @intCast(source.range);
        const range_sq = range * range;

        // Calculate bounds
        const min_x = @max(0, source.x - range);
        const max_x = @min(@as(i32, @intCast(self.config.width)) - 1, source.x + range);
        const min_y = @max(0, source.y - range);
        const max_y = @min(@as(i32, @intCast(self.config.height)) - 1, source.y + range);

        var y = min_y;
        while (y <= max_y) : (y += 1) {
            var x = min_x;
            while (x <= max_x) : (x += 1) {
                const dx = x - source.x;
                const dy = y - source.y;
                const dist_sq = dx * dx + dy * dy;

                if (dist_sq <= range_sq) {
                    // Check line of sight if not ignoring blockers
                    if (!source.ignores_blockers and !self.hasLineOfSight(source.x, source.y, x, y)) {
                        continue;
                    }

                    self.setVisible(x, y, source.player_id);
                }
            }
        }
    }

    /// Set a tile visible for a player (and allies)
    fn setVisible(self: *FogOfWar, x: i32, y: i32, player_id: u8) void {
        const idx = self.getIndex(x, y) orelse return;

        // Set for this player
        if (player_id < self.config.player_count) {
            self.visibility[player_id][idx] = .visible;
        }

        // Set for allies with shared vision
        var ally_iter = self.shared_vision[player_id].keyIterator();
        while (ally_iter.next()) |ally| {
            if (ally.* < self.config.player_count) {
                self.visibility[ally.*][idx] = .visible;
            }
        }
    }

    /// Check line of sight between two points (Bresenham)
    fn hasLineOfSight(self: *const FogOfWar, x0: i32, y0: i32, x1: i32, y1: i32) bool {
        var x = x0;
        var y = y0;
        const dx = @as(i32, @intCast(@abs(x1 - x0)));
        const dy = @as(i32, @intCast(@abs(y1 - y0)));
        const sx: i32 = if (x0 < x1) 1 else -1;
        const sy: i32 = if (y0 < y1) 1 else -1;
        var err = dx - dy;

        while (true) {
            // Don't check the destination tile itself
            if (x == x1 and y == y1) {
                return true;
            }

            // Check if this tile blocks
            if (self.isBlocker(x, y)) {
                // Allow seeing the blocking tile, but not beyond
                if (x != x0 or y != y0) {
                    return false;
                }
            }

            const e2 = 2 * err;
            if (e2 > -dy) {
                err -= dy;
                x += sx;
            }
            if (e2 < dx) {
                err += dx;
                y += sy;
            }
        }
    }

    /// Get visibility for a player at a tile
    pub fn getVisibility(self: *const FogOfWar, x: i32, y: i32, player_id: u8) Visibility {
        if (player_id >= self.config.player_count) return .unexplored;
        const idx = self.getIndex(x, y) orelse return .unexplored;
        return self.visibility[player_id][idx];
    }

    /// Check if a tile is visible to a player
    pub fn isVisible(self: *const FogOfWar, x: i32, y: i32, player_id: u8) bool {
        return self.getVisibility(x, y, player_id) == .visible;
    }

    /// Check if a tile has been explored by a player
    pub fn isExplored(self: *const FogOfWar, x: i32, y: i32, player_id: u8) bool {
        const vis = self.getVisibility(x, y, player_id);
        return vis == .visible or vis == .explored;
    }

    /// Reveal entire map for a player (cheat/debug)
    pub fn revealAll(self: *FogOfWar, player_id: u8) void {
        if (player_id >= self.config.player_count) return;
        @memset(self.visibility[player_id], .visible);
    }

    /// Hide entire map for a player (reset)
    pub fn hideAll(self: *FogOfWar, player_id: u8) void {
        if (player_id >= self.config.player_count) return;
        @memset(self.visibility[player_id], .unexplored);
    }

    /// Reveal a specific area
    pub fn revealArea(self: *FogOfWar, center_x: i32, center_y: i32, radius: u8, player_id: u8) void {
        if (player_id >= self.config.player_count) return;

        const r: i32 = @intCast(radius);
        const r_sq = r * r;

        var y = center_y - r;
        while (y <= center_y + r) : (y += 1) {
            var x = center_x - r;
            while (x <= center_x + r) : (x += 1) {
                const dx = x - center_x;
                const dy = y - center_y;
                if (dx * dx + dy * dy <= r_sq) {
                    if (self.getIndex(x, y)) |idx| {
                        self.visibility[player_id][idx] = .visible;
                    }
                }
            }
        }
    }

    /// Get visible tile range for rendering (camera culling)
    pub fn getVisibleTiles(self: *const FogOfWar, player_id: u8, min_x: i32, min_y: i32, max_x: i32, max_y: i32, allocator: std.mem.Allocator) ![]struct { x: i32, y: i32 } {
        var list = std.ArrayList(struct { x: i32, y: i32 }).init(allocator);

        const clamp_min_x = @max(0, min_x);
        const clamp_max_x = @min(@as(i32, @intCast(self.config.width)) - 1, max_x);
        const clamp_min_y = @max(0, min_y);
        const clamp_max_y = @min(@as(i32, @intCast(self.config.height)) - 1, max_y);

        var y = clamp_min_y;
        while (y <= clamp_max_y) : (y += 1) {
            var x = clamp_min_x;
            while (x <= clamp_max_x) : (x += 1) {
                if (self.isVisible(x, y, player_id)) {
                    try list.append(.{ .x = x, .y = y });
                }
            }
        }

        return list.toOwnedSlice();
    }

    /// Get explored percentage for a player
    pub fn getExploredPercentage(self: *const FogOfWar, player_id: u8) f32 {
        if (player_id >= self.config.player_count) return 0;

        var explored: usize = 0;
        const grid = self.visibility[player_id];
        for (grid) |cell| {
            if (cell != .unexplored) {
                explored += 1;
            }
        }

        const total = self.config.width * self.config.height;
        return @as(f32, @floatFromInt(explored)) / @as(f32, @floatFromInt(total));
    }

    /// Get visible percentage for a player
    pub fn getVisiblePercentage(self: *const FogOfWar, player_id: u8) f32 {
        if (player_id >= self.config.player_count) return 0;

        var visible: usize = 0;
        const grid = self.visibility[player_id];
        for (grid) |cell| {
            if (cell == .visible) {
                visible += 1;
            }
        }

        const total = self.config.width * self.config.height;
        return @as(f32, @floatFromInt(visible)) / @as(f32, @floatFromInt(total));
    }

    /// Get index into flat grid
    fn getIndex(self: *const FogOfWar, x: i32, y: i32) ?usize {
        if (x < 0 or y < 0) return null;
        const ux: usize = @intCast(x);
        const uy: usize = @intCast(y);
        if (ux >= self.config.width or uy >= self.config.height) return null;
        return uy * self.config.width + ux;
    }

    /// Get source count
    pub fn getSourceCount(self: *const FogOfWar) usize {
        return self.sources.count();
    }

    /// Get active source count
    pub fn getActiveSourceCount(self: *const FogOfWar) usize {
        var count: usize = 0;
        var iter = self.sources.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.active) {
                count += 1;
            }
        }
        return count;
    }

    /// Get all sources for a player
    pub fn getPlayerSources(self: *const FogOfWar, player_id: u8, allocator: std.mem.Allocator) ![]VisionSourceHandle {
        var list = std.ArrayList(VisionSourceHandle).init(allocator);
        var iter = self.sources.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.player_id == player_id) {
                try list.append(.{ .id = entry.key_ptr.* });
            }
        }
        return list.toOwnedSlice();
    }

    /// Check if any player can see a tile
    pub fn isVisibleToAny(self: *const FogOfWar, x: i32, y: i32) bool {
        const idx = self.getIndex(x, y) orelse return false;
        for (0..self.config.player_count) |player| {
            if (self.visibility[player][idx] == .visible) {
                return true;
            }
        }
        return false;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "FogOfWar - init and basic visibility" {
    var fow = try FogOfWar.init(std.testing.allocator, .{
        .width = 10,
        .height = 10,
        .player_count = 2,
    });
    defer fow.deinit();

    // All tiles start unexplored
    try std.testing.expectEqual(Visibility.unexplored, fow.getVisibility(5, 5, 0));
    try std.testing.expect(!fow.isVisible(5, 5, 0));
    try std.testing.expect(!fow.isExplored(5, 5, 0));
}

test "FogOfWar - add vision source" {
    var fow = try FogOfWar.init(std.testing.allocator, .{
        .width = 20,
        .height = 20,
        .player_count = 2,
    });
    defer fow.deinit();

    _ = try fow.addVisionSource(.{ .x = 10, .y = 10, .range = 5, .player_id = 0 });
    fow.update();

    // Center should be visible
    try std.testing.expect(fow.isVisible(10, 10, 0));
    // Near the source should be visible
    try std.testing.expect(fow.isVisible(12, 10, 0));
    // Far away should not be visible
    try std.testing.expect(!fow.isVisible(0, 0, 0));
    // Other player should not see it
    try std.testing.expect(!fow.isVisible(10, 10, 1));
}

test "FogOfWar - move vision source" {
    var fow = try FogOfWar.init(std.testing.allocator, .{
        .width = 20,
        .height = 20,
        .player_count = 1,
        .remember_explored = true,
    });
    defer fow.deinit();

    const handle = try fow.addVisionSource(.{ .x = 5, .y = 5, .range = 3, .player_id = 0 });
    fow.update();

    try std.testing.expect(fow.isVisible(5, 5, 0));

    // Move the source
    _ = fow.moveVisionSource(handle, 15, 15);
    fow.update();

    // Old position should now be explored (not visible)
    try std.testing.expectEqual(Visibility.explored, fow.getVisibility(5, 5, 0));
    // New position should be visible
    try std.testing.expect(fow.isVisible(15, 15, 0));
}

test "FogOfWar - blockers" {
    var fow = try FogOfWar.init(std.testing.allocator, .{
        .width = 20,
        .height = 20,
        .player_count = 1,
    });
    defer fow.deinit();

    // Add a wall between source and target
    fow.setBlocker(7, 5, true);
    fow.setBlocker(7, 6, true);
    fow.setBlocker(7, 4, true);

    _ = try fow.addVisionSource(.{ .x = 5, .y = 5, .range = 10, .player_id = 0 });
    fow.update();

    // Before the wall should be visible
    try std.testing.expect(fow.isVisible(6, 5, 0));
    // The wall itself might be visible (edge case)
    // But beyond the wall should not be visible
    try std.testing.expect(!fow.isVisible(10, 5, 0));
}

test "FogOfWar - ignores blockers" {
    var fow = try FogOfWar.init(std.testing.allocator, .{
        .width = 20,
        .height = 20,
        .player_count = 1,
    });
    defer fow.deinit();

    fow.setBlocker(7, 5, true);

    _ = try fow.addVisionSource(.{
        .x = 5,
        .y = 5,
        .range = 10,
        .player_id = 0,
        .ignores_blockers = true,
    });
    fow.update();

    // Should see through the wall
    try std.testing.expect(fow.isVisible(10, 5, 0));
}

test "FogOfWar - shared vision" {
    var fow = try FogOfWar.init(std.testing.allocator, .{
        .width = 20,
        .height = 20,
        .player_count = 3,
    });
    defer fow.deinit();

    // Player 0 and 1 share vision
    try fow.setSharedVision(0, 1, true);

    _ = try fow.addVisionSource(.{ .x = 10, .y = 10, .range = 5, .player_id = 0 });
    fow.update();

    // Player 0 can see
    try std.testing.expect(fow.isVisible(10, 10, 0));
    // Player 1 can also see (shared)
    try std.testing.expect(fow.isVisible(10, 10, 1));
    // Player 2 cannot see
    try std.testing.expect(!fow.isVisible(10, 10, 2));
}

test "FogOfWar - remove shared vision" {
    var fow = try FogOfWar.init(std.testing.allocator, .{
        .width = 20,
        .height = 20,
        .player_count = 2,
    });
    defer fow.deinit();

    try fow.setSharedVision(0, 1, true);
    try std.testing.expect(fow.hasSharedVision(0, 1));

    try fow.setSharedVision(0, 1, false);
    try std.testing.expect(!fow.hasSharedVision(0, 1));
}

test "FogOfWar - remove vision source" {
    var fow = try FogOfWar.init(std.testing.allocator, .{
        .width = 20,
        .height = 20,
        .player_count = 1,
        .remember_explored = true,
    });
    defer fow.deinit();

    const handle = try fow.addVisionSource(.{ .x = 10, .y = 10, .range = 5, .player_id = 0 });
    fow.update();

    try std.testing.expect(fow.isVisible(10, 10, 0));

    _ = fow.removeVisionSource(handle);
    fow.forceUpdate();

    // Should be explored but not visible
    try std.testing.expectEqual(Visibility.explored, fow.getVisibility(10, 10, 0));
}

test "FogOfWar - deactivate vision source" {
    var fow = try FogOfWar.init(std.testing.allocator, .{
        .width = 20,
        .height = 20,
        .player_count = 1,
        .remember_explored = true,
    });
    defer fow.deinit();

    const handle = try fow.addVisionSource(.{ .x = 10, .y = 10, .range = 5, .player_id = 0 });
    fow.update();

    try std.testing.expect(fow.isVisible(10, 10, 0));

    _ = fow.setVisionActive(handle, false);
    fow.forceUpdate();

    // Should be explored but not visible
    try std.testing.expectEqual(Visibility.explored, fow.getVisibility(10, 10, 0));
}

test "FogOfWar - reveal all" {
    var fow = try FogOfWar.init(std.testing.allocator, .{
        .width = 10,
        .height = 10,
        .player_count = 2,
    });
    defer fow.deinit();

    fow.revealAll(0);

    // All tiles visible for player 0
    try std.testing.expect(fow.isVisible(0, 0, 0));
    try std.testing.expect(fow.isVisible(9, 9, 0));

    // Player 1 still unexplored
    try std.testing.expect(!fow.isVisible(0, 0, 1));
}

test "FogOfWar - reveal area" {
    var fow = try FogOfWar.init(std.testing.allocator, .{
        .width = 20,
        .height = 20,
        .player_count = 1,
    });
    defer fow.deinit();

    fow.revealArea(10, 10, 3, 0);

    // Center visible
    try std.testing.expect(fow.isVisible(10, 10, 0));
    // Near center visible
    try std.testing.expect(fow.isVisible(12, 10, 0));
    // Far away not visible
    try std.testing.expect(!fow.isVisible(0, 0, 0));
}

test "FogOfWar - explored percentage" {
    var fow = try FogOfWar.init(std.testing.allocator, .{
        .width = 10,
        .height = 10,
        .player_count = 1,
    });
    defer fow.deinit();

    try std.testing.expectApproxEqAbs(@as(f32, 0.0), fow.getExploredPercentage(0), 0.01);

    fow.revealAll(0);

    try std.testing.expectApproxEqAbs(@as(f32, 1.0), fow.getExploredPercentage(0), 0.01);
}

test "FogOfWar - source count" {
    var fow = try FogOfWar.init(std.testing.allocator, .{
        .width = 20,
        .height = 20,
        .player_count = 2,
    });
    defer fow.deinit();

    try std.testing.expectEqual(@as(usize, 0), fow.getSourceCount());

    _ = try fow.addVisionSource(.{ .x = 5, .y = 5, .range = 5, .player_id = 0 });
    _ = try fow.addVisionSource(.{ .x = 10, .y = 10, .range = 5, .player_id = 1 });

    try std.testing.expectEqual(@as(usize, 2), fow.getSourceCount());
    try std.testing.expectEqual(@as(usize, 2), fow.getActiveSourceCount());
}

test "FogOfWar - out of bounds" {
    var fow = try FogOfWar.init(std.testing.allocator, .{
        .width = 10,
        .height = 10,
        .player_count = 1,
    });
    defer fow.deinit();

    // Out of bounds should return unexplored
    try std.testing.expectEqual(Visibility.unexplored, fow.getVisibility(-1, 5, 0));
    try std.testing.expectEqual(Visibility.unexplored, fow.getVisibility(5, -1, 0));
    try std.testing.expectEqual(Visibility.unexplored, fow.getVisibility(100, 5, 0));
    try std.testing.expectEqual(Visibility.unexplored, fow.getVisibility(5, 100, 0));
}

test "FogOfWar - invalid player" {
    var fow = try FogOfWar.init(std.testing.allocator, .{
        .width = 10,
        .height = 10,
        .player_count = 2,
    });
    defer fow.deinit();

    // Invalid player should return unexplored
    try std.testing.expectEqual(Visibility.unexplored, fow.getVisibility(5, 5, 99));
}

test "FogOfWar - vision range change" {
    var fow = try FogOfWar.init(std.testing.allocator, .{
        .width = 20,
        .height = 20,
        .player_count = 1,
    });
    defer fow.deinit();

    const handle = try fow.addVisionSource(.{ .x = 10, .y = 10, .range = 3, .player_id = 0 });
    fow.update();

    // With range 3, tile at distance 5 not visible
    try std.testing.expect(!fow.isVisible(15, 10, 0));

    _ = fow.setVisionRange(handle, 6);
    fow.update();

    // Now with range 6, it should be visible
    try std.testing.expect(fow.isVisible(15, 10, 0));
}

test "FogOfWar - circular vision" {
    var fow = try FogOfWar.init(std.testing.allocator, .{
        .width = 20,
        .height = 20,
        .player_count = 1,
    });
    defer fow.deinit();

    _ = try fow.addVisionSource(.{ .x = 10, .y = 10, .range = 3, .player_id = 0 });
    fow.update();

    // Tiles at exact range should be visible
    try std.testing.expect(fow.isVisible(13, 10, 0)); // East
    try std.testing.expect(fow.isVisible(7, 10, 0)); // West
    try std.testing.expect(fow.isVisible(10, 13, 0)); // South
    try std.testing.expect(fow.isVisible(10, 7, 0)); // North

    // Diagonal at range 3 (~4.24) should NOT be visible
    try std.testing.expect(!fow.isVisible(13, 13, 0));
}

test "FogOfWar - no remember explored" {
    var fow = try FogOfWar.init(std.testing.allocator, .{
        .width = 20,
        .height = 20,
        .player_count = 1,
        .remember_explored = false,
    });
    defer fow.deinit();

    const handle = try fow.addVisionSource(.{ .x = 5, .y = 5, .range = 3, .player_id = 0 });
    fow.update();

    try std.testing.expect(fow.isVisible(5, 5, 0));

    // Move source away
    _ = fow.moveVisionSource(handle, 15, 15);
    fow.update();

    // Old position should be unexplored (not remembered)
    try std.testing.expectEqual(Visibility.unexplored, fow.getVisibility(5, 5, 0));
}

test "FogOfWar - isVisibleToAny" {
    var fow = try FogOfWar.init(std.testing.allocator, .{
        .width = 20,
        .height = 20,
        .player_count = 2,
    });
    defer fow.deinit();

    _ = try fow.addVisionSource(.{ .x = 10, .y = 10, .range = 5, .player_id = 0 });
    fow.update();

    // Visible to player 0, so visible to any
    try std.testing.expect(fow.isVisibleToAny(10, 10));

    // Not visible to anyone
    try std.testing.expect(!fow.isVisibleToAny(0, 0));
}

test "FogOfWar - getPlayerSources" {
    var fow = try FogOfWar.init(std.testing.allocator, .{
        .width = 20,
        .height = 20,
        .player_count = 2,
    });
    defer fow.deinit();

    _ = try fow.addVisionSource(.{ .x = 5, .y = 5, .range = 5, .player_id = 0 });
    _ = try fow.addVisionSource(.{ .x = 10, .y = 10, .range = 5, .player_id = 0 });
    _ = try fow.addVisionSource(.{ .x = 15, .y = 15, .range = 5, .player_id = 1 });

    const p0_sources = try fow.getPlayerSources(0, std.testing.allocator);
    defer std.testing.allocator.free(p0_sources);

    const p1_sources = try fow.getPlayerSources(1, std.testing.allocator);
    defer std.testing.allocator.free(p1_sources);

    try std.testing.expectEqual(@as(usize, 2), p0_sources.len);
    try std.testing.expectEqual(@as(usize, 1), p1_sources.len);
}
