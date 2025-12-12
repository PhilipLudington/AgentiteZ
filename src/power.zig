//! Power Network System - Grid-based Power Distribution
//!
//! A power distribution system for factory/strategy games where buildings
//! connect to power networks through poles/substations. Uses Union-Find
//! for efficient network connectivity.
//!
//! Features:
//! - Power poles with configurable coverage radius
//! - Automatic network merging when poles connect
//! - Network splitting when poles are removed
//! - Production/consumption tracking per network
//! - Powered/brownout/blackout status
//! - Cell and entity coverage queries
//! - Multiple independent networks
//!
//! Usage:
//! ```zig
//! var power = PowerNetwork.init(allocator, .{ .pole_radius = 5 });
//! defer power.deinit();
//!
//! const pole1 = try power.addPole(10, 10, 1);
//! const pole2 = try power.addPole(15, 10, 2); // Within range - same network
//!
//! try power.addProducer(pole1, 100);
//! try power.addConsumer(pole1, 60);
//!
//! power.recalculate();
//! if (power.isPowered(pole1)) { ... }
//! ```

const std = @import("std");

/// Grid coordinate
pub const Coord = struct {
    x: i32,
    y: i32,

    pub fn init(x: i32, y: i32) Coord {
        return .{ .x = x, .y = y };
    }

    /// Squared distance to another coordinate
    pub fn distanceSquared(self: Coord, other: Coord) i64 {
        const dx: i64 = @as(i64, self.x) - @as(i64, other.x);
        const dy: i64 = @as(i64, self.y) - @as(i64, other.y);
        return dx * dx + dy * dy;
    }

    /// Check if within radius of another coordinate
    pub fn withinRadius(self: Coord, other: Coord, radius: i32) bool {
        const r_sq: i64 = @as(i64, radius) * @as(i64, radius);
        return self.distanceSquared(other) <= r_sq;
    }
};

/// Power network statistics
pub const NetworkStats = struct {
    production: i64 = 0,
    consumption: i64 = 0,
    powered: bool = false,
    brownout: bool = false,

    /// Get surplus power (production - consumption)
    pub fn getSurplus(self: NetworkStats) i64 {
        return self.production - self.consumption;
    }

    /// Get power ratio (production / consumption), 0 if no consumption
    pub fn getRatio(self: NetworkStats) f32 {
        if (self.consumption == 0) return if (self.production > 0) 1.0 else 0.0;
        return @as(f32, @floatFromInt(self.production)) / @as(f32, @floatFromInt(self.consumption));
    }
};

/// Power status for a building/entity
pub const PowerStatus = enum {
    /// Not connected to any power network
    disconnected,
    /// Connected but network has no production
    unpowered,
    /// Connected but production < consumption (brownout)
    brownout,
    /// Connected and production >= consumption
    powered,
};

/// Configuration for the power network
pub const PowerConfig = struct {
    /// Radius that each pole covers for buildings
    pole_radius: i32 = 5,
    /// Maximum distance between poles to connect (default: 2x pole_radius)
    connection_range: ?i32 = null,
    /// Brownout threshold (ratio below this = brownout)
    brownout_threshold: f32 = 1.0,
    /// Maximum number of poles
    max_poles: usize = 4096,

    /// Get effective connection range
    pub fn getConnectionRange(self: PowerConfig) i32 {
        return self.connection_range orelse (self.pole_radius * 2);
    }
};

/// Power pole data
pub const PowerPole = struct {
    /// Position on the grid
    position: Coord,
    /// Building/entity ID that owns this pole
    owner_id: u32,
    /// Network this pole belongs to (index in union-find)
    network_id: u32,
    /// Whether this pole is active
    active: bool = true,
};

/// Power network manager
pub fn PowerNetwork(comptime EntityId: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        config: PowerConfig,

        // Pole storage
        poles: std.ArrayList(PowerPole),
        /// Map from owner_id to pole index
        owner_to_pole: std.AutoHashMap(EntityId, usize),

        // Union-Find for network connectivity
        parent: std.ArrayList(u32),
        rank: std.ArrayList(u8),

        // Per-network stats (indexed by root of union-find)
        network_stats: std.AutoHashMap(u32, NetworkStats),

        // Producers and consumers per pole
        producers: std.AutoHashMap(usize, i64),
        consumers: std.AutoHashMap(usize, i64),

        /// Dirty flag - needs recalculation
        dirty: bool = true,

        /// Initialize the power network
        pub fn init(allocator: std.mem.Allocator, config: PowerConfig) Self {
            return Self{
                .allocator = allocator,
                .config = config,
                .poles = std.ArrayList(PowerPole).init(allocator),
                .owner_to_pole = std.AutoHashMap(EntityId, usize).init(allocator),
                .parent = std.ArrayList(u32).init(allocator),
                .rank = std.ArrayList(u8).init(allocator),
                .network_stats = std.AutoHashMap(u32, NetworkStats).init(allocator),
                .producers = std.AutoHashMap(usize, i64).init(allocator),
                .consumers = std.AutoHashMap(usize, i64).init(allocator),
            };
        }

        /// Clean up resources
        pub fn deinit(self: *Self) void {
            self.poles.deinit();
            self.owner_to_pole.deinit();
            self.parent.deinit();
            self.rank.deinit();
            self.network_stats.deinit();
            self.producers.deinit();
            self.consumers.deinit();
        }

        // ====== Union-Find Operations ======

        fn ufFind(self: *Self, i: u32) u32 {
            const idx = @as(usize, i);
            if (idx >= self.parent.items.len) return i;

            if (self.parent.items[idx] != i) {
                // Path compression
                self.parent.items[idx] = self.ufFind(self.parent.items[idx]);
            }
            return self.parent.items[idx];
        }

        fn ufUnion(self: *Self, a: u32, b: u32) void {
            const root_a = self.ufFind(a);
            const root_b = self.ufFind(b);

            if (root_a == root_b) return;

            const idx_a = @as(usize, root_a);
            const idx_b = @as(usize, root_b);

            // Union by rank
            if (self.rank.items[idx_a] < self.rank.items[idx_b]) {
                self.parent.items[idx_a] = root_b;
            } else if (self.rank.items[idx_a] > self.rank.items[idx_b]) {
                self.parent.items[idx_b] = root_a;
            } else {
                self.parent.items[idx_b] = root_a;
                self.rank.items[idx_a] += 1;
            }
        }

        // ====== Pole Management ======

        /// Add a power pole at the given position
        pub fn addPole(self: *Self, x: i32, y: i32, owner_id: EntityId) !usize {
            if (self.poles.items.len >= self.config.max_poles) {
                return error.TooManyPoles;
            }

            // Check if owner already has a pole
            if (self.owner_to_pole.contains(owner_id)) {
                return error.DuplicateOwner;
            }

            const pole_index = self.poles.items.len;
            const pole_idx_u32 = @as(u32, @intCast(pole_index));

            // Add pole
            try self.poles.append(.{
                .position = Coord.init(x, y),
                .owner_id = @intCast(owner_id),
                .network_id = pole_idx_u32,
            });

            // Initialize union-find
            try self.parent.append(pole_idx_u32);
            try self.rank.append(0);

            // Map owner to pole
            try self.owner_to_pole.put(owner_id, pole_index);

            // Connect to nearby poles
            const connection_range = self.config.getConnectionRange();
            const position = Coord.init(x, y);

            for (self.poles.items[0..pole_index], 0..) |*other_pole, i| {
                if (!other_pole.active) continue;

                if (position.withinRadius(other_pole.position, connection_range)) {
                    self.ufUnion(pole_idx_u32, @as(u32, @intCast(i)));
                }
            }

            // Update network IDs
            for (self.poles.items, 0..) |*pole, i| {
                if (pole.active) {
                    pole.network_id = self.ufFind(@as(u32, @intCast(i)));
                }
            }

            self.dirty = true;
            return pole_index;
        }

        /// Remove a power pole by owner ID
        pub fn removePole(self: *Self, owner_id: EntityId) bool {
            const pole_index = self.owner_to_pole.get(owner_id) orelse return false;

            // Deactivate pole
            self.poles.items[pole_index].active = false;

            // Remove from mappings
            _ = self.owner_to_pole.remove(owner_id);
            _ = self.producers.remove(pole_index);
            _ = self.consumers.remove(pole_index);

            // Rebuild networks (removing can split networks)
            self.rebuildNetworks();

            self.dirty = true;
            return true;
        }

        /// Remove a power pole by index
        pub fn removePoleByIndex(self: *Self, pole_index: usize) bool {
            if (pole_index >= self.poles.items.len) return false;

            const pole = &self.poles.items[pole_index];
            if (!pole.active) return false;

            pole.active = false;

            // Find and remove owner mapping
            var to_remove: ?EntityId = null;
            var iter = self.owner_to_pole.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.* == pole_index) {
                    to_remove = entry.key_ptr.*;
                    break;
                }
            }
            if (to_remove) |owner| {
                _ = self.owner_to_pole.remove(owner);
            }

            _ = self.producers.remove(pole_index);
            _ = self.consumers.remove(pole_index);

            self.rebuildNetworks();
            self.dirty = true;
            return true;
        }

        /// Rebuild all network connections from scratch
        fn rebuildNetworks(self: *Self) void {
            const connection_range = self.config.getConnectionRange();

            // Reset union-find
            for (0..self.poles.items.len) |i| {
                const idx_u32 = @as(u32, @intCast(i));
                self.parent.items[i] = idx_u32;
                self.rank.items[i] = 0;
            }

            // Reconnect all active poles
            for (self.poles.items, 0..) |*pole_i, i| {
                if (!pole_i.active) continue;

                for (self.poles.items[i + 1 ..], i + 1..) |*pole_j, j| {
                    if (!pole_j.active) continue;

                    if (pole_i.position.withinRadius(pole_j.position, connection_range)) {
                        self.ufUnion(@as(u32, @intCast(i)), @as(u32, @intCast(j)));
                    }
                }
            }

            // Update network IDs
            for (self.poles.items, 0..) |*pole, i| {
                if (pole.active) {
                    pole.network_id = self.ufFind(@as(u32, @intCast(i)));
                }
            }
        }

        // ====== Power Production/Consumption ======

        /// Set production for a pole (generator attached)
        pub fn setProduction(self: *Self, pole_index: usize, amount: i64) !void {
            if (pole_index >= self.poles.items.len) return error.InvalidPole;
            if (!self.poles.items[pole_index].active) return error.InactivePole;

            try self.producers.put(pole_index, amount);
            self.dirty = true;
        }

        /// Set production by owner ID
        pub fn setProductionByOwner(self: *Self, owner_id: EntityId, amount: i64) !void {
            const pole_index = self.owner_to_pole.get(owner_id) orelse return error.OwnerNotFound;
            try self.setProduction(pole_index, amount);
        }

        /// Set consumption for a pole (machines attached)
        pub fn setConsumption(self: *Self, pole_index: usize, amount: i64) !void {
            if (pole_index >= self.poles.items.len) return error.InvalidPole;
            if (!self.poles.items[pole_index].active) return error.InactivePole;

            try self.consumers.put(pole_index, amount);
            self.dirty = true;
        }

        /// Set consumption by owner ID
        pub fn setConsumptionByOwner(self: *Self, owner_id: EntityId, amount: i64) !void {
            const pole_index = self.owner_to_pole.get(owner_id) orelse return error.OwnerNotFound;
            try self.setConsumption(pole_index, amount);
        }

        /// Add production to a pole
        pub fn addProduction(self: *Self, pole_index: usize, amount: i64) !void {
            if (pole_index >= self.poles.items.len) return error.InvalidPole;
            if (!self.poles.items[pole_index].active) return error.InactivePole;

            const current = self.producers.get(pole_index) orelse 0;
            try self.producers.put(pole_index, current + amount);
            self.dirty = true;
        }

        /// Add consumption to a pole
        pub fn addConsumption(self: *Self, pole_index: usize, amount: i64) !void {
            if (pole_index >= self.poles.items.len) return error.InvalidPole;
            if (!self.poles.items[pole_index].active) return error.InactivePole;

            const current = self.consumers.get(pole_index) orelse 0;
            try self.consumers.put(pole_index, current + amount);
            self.dirty = true;
        }

        /// Clear all production/consumption (call before rebuilding)
        pub fn clearPowerData(self: *Self) void {
            self.producers.clearRetainingCapacity();
            self.consumers.clearRetainingCapacity();
            self.dirty = true;
        }

        // ====== Recalculation ======

        /// Recalculate all network statistics
        pub fn recalculate(self: *Self) void {
            self.network_stats.clearRetainingCapacity();

            // Aggregate production/consumption per network
            for (self.poles.items, 0..) |pole, i| {
                if (!pole.active) continue;

                const network_id = pole.network_id;
                const production = self.producers.get(i) orelse 0;
                const consumption = self.consumers.get(i) orelse 0;

                const result = self.network_stats.getOrPut(network_id) catch continue;
                if (!result.found_existing) {
                    result.value_ptr.* = .{};
                }
                result.value_ptr.production += production;
                result.value_ptr.consumption += consumption;
            }

            // Calculate powered status
            var iter = self.network_stats.iterator();
            while (iter.next()) |entry| {
                const stats = entry.value_ptr;
                if (stats.production == 0) {
                    stats.powered = false;
                    stats.brownout = false;
                } else if (stats.production >= stats.consumption) {
                    stats.powered = true;
                    stats.brownout = false;
                } else {
                    // Partial power - brownout
                    const ratio = stats.getRatio();
                    stats.powered = false;
                    stats.brownout = ratio >= self.config.brownout_threshold * 0.5;
                }
            }

            self.dirty = false;
        }

        // ====== Queries ======

        /// Get the network ID for a pole
        pub fn getNetworkId(self: *const Self, pole_index: usize) ?u32 {
            if (pole_index >= self.poles.items.len) return null;
            const pole = self.poles.items[pole_index];
            if (!pole.active) return null;
            return pole.network_id;
        }

        /// Get the network ID for an owner
        pub fn getNetworkIdByOwner(self: *const Self, owner_id: EntityId) ?u32 {
            const pole_index = self.owner_to_pole.get(owner_id) orelse return null;
            return self.getNetworkId(pole_index);
        }

        /// Get network statistics
        pub fn getNetworkStats(self: *const Self, network_id: u32) ?NetworkStats {
            return self.network_stats.get(network_id);
        }

        /// Check if a network is powered
        pub fn isNetworkPowered(self: *const Self, network_id: u32) bool {
            if (self.network_stats.get(network_id)) |stats| {
                return stats.powered;
            }
            return false;
        }

        /// Check if a pole is powered
        pub fn isPowered(self: *const Self, pole_index: usize) bool {
            const network_id = self.getNetworkId(pole_index) orelse return false;
            return self.isNetworkPowered(network_id);
        }

        /// Check if an owner's pole is powered
        pub fn isPoweredByOwner(self: *const Self, owner_id: EntityId) bool {
            const network_id = self.getNetworkIdByOwner(owner_id) orelse return false;
            return self.isNetworkPowered(network_id);
        }

        /// Get power status for a pole
        pub fn getPowerStatus(self: *const Self, pole_index: usize) PowerStatus {
            const network_id = self.getNetworkId(pole_index) orelse return .disconnected;

            if (self.network_stats.get(network_id)) |stats| {
                if (stats.powered) return .powered;
                if (stats.brownout) return .brownout;
                if (stats.production > 0) return .brownout;
                return .unpowered;
            }
            return .disconnected;
        }

        /// Check if a cell (grid position) is covered by any pole
        pub fn isCellCovered(self: *const Self, x: i32, y: i32) bool {
            return self.getCellNetwork(x, y) != null;
        }

        /// Get the network ID covering a cell
        pub fn getCellNetwork(self: *const Self, x: i32, y: i32) ?u32 {
            const pos = Coord.init(x, y);

            for (self.poles.items) |pole| {
                if (!pole.active) continue;

                if (pos.withinRadius(pole.position, self.config.pole_radius)) {
                    return pole.network_id;
                }
            }

            return null;
        }

        /// Check if a cell is powered
        pub fn isCellPowered(self: *const Self, x: i32, y: i32) bool {
            const network_id = self.getCellNetwork(x, y) orelse return false;
            return self.isNetworkPowered(network_id);
        }

        /// Get all cells covered by power (for rendering)
        pub fn getCoveredCells(self: *const Self, allocator: std.mem.Allocator) ![]Coord {
            var cells = std.ArrayList(Coord).init(allocator);
            errdefer cells.deinit();

            var seen = std.AutoHashMap(i64, void).init(allocator);
            defer seen.deinit();

            const radius = self.config.pole_radius;

            for (self.poles.items) |pole| {
                if (!pole.active) continue;

                var dy: i32 = -radius;
                while (dy <= radius) : (dy += 1) {
                    var dx: i32 = -radius;
                    while (dx <= radius) : (dx += 1) {
                        if (dx * dx + dy * dy <= radius * radius) {
                            const cx = pole.position.x + dx;
                            const cy = pole.position.y + dy;
                            const key = @as(i64, cx) << 32 | @as(i64, @bitCast(@as(i32, cy)));

                            if (!seen.contains(key)) {
                                try seen.put(key, {});
                                try cells.append(Coord.init(cx, cy));
                            }
                        }
                    }
                }
            }

            return cells.toOwnedSlice();
        }

        /// Check if two poles are in the same network
        pub fn areConnected(self: *const Self, pole_a: usize, pole_b: usize) bool {
            const net_a = self.getNetworkId(pole_a) orelse return false;
            const net_b = self.getNetworkId(pole_b) orelse return false;
            return net_a == net_b;
        }

        /// Count active poles
        pub fn getPoleCount(self: *const Self) usize {
            var count: usize = 0;
            for (self.poles.items) |pole| {
                if (pole.active) count += 1;
            }
            return count;
        }

        /// Count distinct networks
        pub fn getNetworkCount(self: *const Self) usize {
            return self.network_stats.count();
        }

        /// Get a pole by index
        pub fn getPole(self: *const Self, index: usize) ?PowerPole {
            if (index >= self.poles.items.len) return null;
            const pole = self.poles.items[index];
            if (!pole.active) return null;
            return pole;
        }

        /// Get pole index by owner
        pub fn getPoleIndex(self: *const Self, owner_id: EntityId) ?usize {
            return self.owner_to_pole.get(owner_id);
        }

        /// Find the nearest powered pole to a position
        pub fn findNearestPoweredPole(self: *const Self, x: i32, y: i32) ?usize {
            const pos = Coord.init(x, y);
            var best_index: ?usize = null;
            var best_dist: i64 = std.math.maxInt(i64);

            for (self.poles.items, 0..) |pole, i| {
                if (!pole.active) continue;
                if (!self.isPowered(i)) continue;

                const dist = pos.distanceSquared(pole.position);
                if (dist < best_dist) {
                    best_dist = dist;
                    best_index = i;
                }
            }

            return best_index;
        }

        /// Get total power production across all networks
        pub fn getTotalProduction(self: *const Self) i64 {
            var total: i64 = 0;
            var iter = self.network_stats.iterator();
            while (iter.next()) |entry| {
                total += entry.value_ptr.production;
            }
            return total;
        }

        /// Get total power consumption across all networks
        pub fn getTotalConsumption(self: *const Self) i64 {
            var total: i64 = 0;
            var iter = self.network_stats.iterator();
            while (iter.next()) |entry| {
                total += entry.value_ptr.consumption;
            }
            return total;
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "PowerNetwork - init and deinit" {
    var power = PowerNetwork(u32).init(std.testing.allocator, .{});
    defer power.deinit();

    try std.testing.expectEqual(@as(usize, 0), power.getPoleCount());
}

test "PowerNetwork - add single pole" {
    var power = PowerNetwork(u32).init(std.testing.allocator, .{ .pole_radius = 5 });
    defer power.deinit();

    const idx = try power.addPole(10, 10, 1);
    try std.testing.expectEqual(@as(usize, 0), idx);
    try std.testing.expectEqual(@as(usize, 1), power.getPoleCount());

    const pole = power.getPole(idx).?;
    try std.testing.expectEqual(@as(i32, 10), pole.position.x);
    try std.testing.expectEqual(@as(i32, 10), pole.position.y);
}

test "PowerNetwork - poles connect within range" {
    var power = PowerNetwork(u32).init(std.testing.allocator, .{
        .pole_radius = 5,
        .connection_range = 10,
    });
    defer power.deinit();

    const pole1 = try power.addPole(0, 0, 1);
    _ = try power.addPole(8, 0, 2); // Within range

    try std.testing.expect(power.areConnected(pole1, 1));
    try std.testing.expectEqual(power.getNetworkId(pole1), power.getNetworkId(1));
}

test "PowerNetwork - poles don't connect outside range" {
    var power = PowerNetwork(u32).init(std.testing.allocator, .{
        .pole_radius = 5,
        .connection_range = 10,
    });
    defer power.deinit();

    const pole1 = try power.addPole(0, 0, 1);
    const pole2 = try power.addPole(20, 0, 2); // Outside range

    try std.testing.expect(!power.areConnected(pole1, pole2));
}

test "PowerNetwork - network chaining" {
    var power = PowerNetwork(u32).init(std.testing.allocator, .{
        .pole_radius = 5,
        .connection_range = 10,
    });
    defer power.deinit();

    const pole1 = try power.addPole(0, 0, 1);
    const pole2 = try power.addPole(8, 0, 2);
    const pole3 = try power.addPole(16, 0, 3);

    // All three should be connected through chaining
    try std.testing.expect(power.areConnected(pole1, pole2));
    try std.testing.expect(power.areConnected(pole2, pole3));
    try std.testing.expect(power.areConnected(pole1, pole3));
}

test "PowerNetwork - production and consumption" {
    var power = PowerNetwork(u32).init(std.testing.allocator, .{ .pole_radius = 5 });
    defer power.deinit();

    const pole = try power.addPole(10, 10, 1);
    try power.setProduction(pole, 100);
    try power.setConsumption(pole, 60);

    power.recalculate();

    const network_id = power.getNetworkId(pole).?;
    const stats = power.getNetworkStats(network_id).?;

    try std.testing.expectEqual(@as(i64, 100), stats.production);
    try std.testing.expectEqual(@as(i64, 60), stats.consumption);
    try std.testing.expect(stats.powered);
}

test "PowerNetwork - unpowered network" {
    var power = PowerNetwork(u32).init(std.testing.allocator, .{ .pole_radius = 5 });
    defer power.deinit();

    const pole = try power.addPole(10, 10, 1);
    try power.setConsumption(pole, 60);
    // No production

    power.recalculate();

    try std.testing.expect(!power.isPowered(pole));
    try std.testing.expectEqual(PowerStatus.unpowered, power.getPowerStatus(pole));
}

test "PowerNetwork - brownout" {
    var power = PowerNetwork(u32).init(std.testing.allocator, .{ .pole_radius = 5 });
    defer power.deinit();

    const pole = try power.addPole(10, 10, 1);
    try power.setProduction(pole, 50);
    try power.setConsumption(pole, 100); // More consumption than production

    power.recalculate();

    try std.testing.expect(!power.isPowered(pole));
    try std.testing.expectEqual(PowerStatus.brownout, power.getPowerStatus(pole));
}

test "PowerNetwork - cell coverage" {
    var power = PowerNetwork(u32).init(std.testing.allocator, .{ .pole_radius = 5 });
    defer power.deinit();

    _ = try power.addPole(10, 10, 1);

    // Within radius
    try std.testing.expect(power.isCellCovered(10, 10)); // Center
    try std.testing.expect(power.isCellCovered(13, 10)); // 3 away
    try std.testing.expect(power.isCellCovered(10, 14)); // 4 away

    // Outside radius
    try std.testing.expect(!power.isCellCovered(20, 10)); // 10 away
    try std.testing.expect(!power.isCellCovered(10, 20)); // 10 away
}

test "PowerNetwork - remove pole" {
    var power = PowerNetwork(u32).init(std.testing.allocator, .{
        .pole_radius = 5,
        .connection_range = 10,
    });
    defer power.deinit();

    const pole1 = try power.addPole(0, 0, 1);
    _ = try power.addPole(8, 0, 2);
    const pole3 = try power.addPole(16, 0, 3);

    // All connected initially
    try std.testing.expect(power.areConnected(pole1, pole3));

    // Remove middle pole
    try std.testing.expect(power.removePole(2));
    try std.testing.expectEqual(@as(usize, 2), power.getPoleCount());

    // Now pole1 and pole3 should be disconnected
    try std.testing.expect(!power.areConnected(pole1, pole3));
}

test "PowerNetwork - network aggregation" {
    var power = PowerNetwork(u32).init(std.testing.allocator, .{
        .pole_radius = 5,
        .connection_range = 10,
    });
    defer power.deinit();

    const pole1 = try power.addPole(0, 0, 1);
    const pole2 = try power.addPole(8, 0, 2);

    try power.setProduction(pole1, 100);
    try power.setConsumption(pole2, 60);

    power.recalculate();

    // Both should be powered (same network)
    try std.testing.expect(power.isPowered(pole1));
    try std.testing.expect(power.isPowered(pole2));

    const network_id = power.getNetworkId(pole1).?;
    const stats = power.getNetworkStats(network_id).?;
    try std.testing.expectEqual(@as(i64, 100), stats.production);
    try std.testing.expectEqual(@as(i64, 60), stats.consumption);
}

test "PowerNetwork - duplicate owner" {
    var power = PowerNetwork(u32).init(std.testing.allocator, .{ .pole_radius = 5 });
    defer power.deinit();

    _ = try power.addPole(10, 10, 1);

    // Same owner should fail
    try std.testing.expectError(error.DuplicateOwner, power.addPole(20, 20, 1));
}

test "PowerNetwork - by owner operations" {
    var power = PowerNetwork(u32).init(std.testing.allocator, .{ .pole_radius = 5 });
    defer power.deinit();

    _ = try power.addPole(10, 10, 42);

    try power.setProductionByOwner(42, 100);
    try power.setConsumptionByOwner(42, 30);

    power.recalculate();

    try std.testing.expect(power.isPoweredByOwner(42));
}

test "PowerNetwork - total production/consumption" {
    var power = PowerNetwork(u32).init(std.testing.allocator, .{
        .pole_radius = 5,
        .connection_range = 5, // Separate networks
    });
    defer power.deinit();

    const pole1 = try power.addPole(0, 0, 1);
    const pole2 = try power.addPole(100, 0, 2); // Separate network

    try power.setProduction(pole1, 100);
    try power.setProduction(pole2, 200);
    try power.setConsumption(pole1, 50);
    try power.setConsumption(pole2, 150);

    power.recalculate();

    try std.testing.expectEqual(@as(i64, 300), power.getTotalProduction());
    try std.testing.expectEqual(@as(i64, 200), power.getTotalConsumption());
}

test "PowerNetwork - clear power data" {
    var power = PowerNetwork(u32).init(std.testing.allocator, .{ .pole_radius = 5 });
    defer power.deinit();

    const pole = try power.addPole(10, 10, 1);
    try power.setProduction(pole, 100);
    try power.setConsumption(pole, 60);

    power.clearPowerData();
    power.recalculate();

    const network_id = power.getNetworkId(pole).?;
    const stats = power.getNetworkStats(network_id).?;

    try std.testing.expectEqual(@as(i64, 0), stats.production);
    try std.testing.expectEqual(@as(i64, 0), stats.consumption);
}

test "PowerNetwork - network count" {
    var power = PowerNetwork(u32).init(std.testing.allocator, .{
        .pole_radius = 5,
        .connection_range = 5,
    });
    defer power.deinit();

    _ = try power.addPole(0, 0, 1);
    _ = try power.addPole(100, 0, 2);
    _ = try power.addPole(200, 0, 3);

    power.recalculate();

    try std.testing.expectEqual(@as(usize, 3), power.getNetworkCount());
}

test "PowerNetwork - find nearest powered pole" {
    var power = PowerNetwork(u32).init(std.testing.allocator, .{ .pole_radius = 5 });
    defer power.deinit();

    _ = try power.addPole(0, 0, 1);
    const pole2 = try power.addPole(100, 0, 2);

    try power.setProduction(pole2, 100); // Only pole2 powered

    power.recalculate();

    const nearest = power.findNearestPoweredPole(50, 0);
    try std.testing.expectEqual(@as(?usize, pole2), nearest);
}

test "PowerNetwork - NetworkStats helpers" {
    const stats = NetworkStats{
        .production = 100,
        .consumption = 80,
        .powered = true,
    };

    try std.testing.expectEqual(@as(i64, 20), stats.getSurplus());
    try std.testing.expectApproxEqAbs(@as(f32, 1.25), stats.getRatio(), 0.01);
}

test "PowerNetwork - Coord helpers" {
    const a = Coord.init(0, 0);
    const b = Coord.init(3, 4);

    try std.testing.expectEqual(@as(i64, 25), a.distanceSquared(b));
    try std.testing.expect(a.withinRadius(b, 5));
    try std.testing.expect(!a.withinRadius(b, 4));
}

test "PowerNetwork - getCoveredCells" {
    var power = PowerNetwork(u32).init(std.testing.allocator, .{ .pole_radius = 2 });
    defer power.deinit();

    _ = try power.addPole(5, 5, 1);

    const cells = try power.getCoveredCells(std.testing.allocator);
    defer std.testing.allocator.free(cells);

    // Should have cells in a circle of radius 2
    try std.testing.expect(cells.len > 0);
    try std.testing.expect(cells.len <= 13); // Pi * 2^2 = ~12.5
}

test "PowerNetwork - add production incremental" {
    var power = PowerNetwork(u32).init(std.testing.allocator, .{ .pole_radius = 5 });
    defer power.deinit();

    const pole = try power.addPole(10, 10, 1);
    try power.addProduction(pole, 50);
    try power.addProduction(pole, 30);
    try power.addConsumption(pole, 20);
    try power.addConsumption(pole, 10);

    power.recalculate();

    const network_id = power.getNetworkId(pole).?;
    const stats = power.getNetworkStats(network_id).?;

    try std.testing.expectEqual(@as(i64, 80), stats.production);
    try std.testing.expectEqual(@as(i64, 30), stats.consumption);
}
