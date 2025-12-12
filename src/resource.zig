//! Resource System - Generic Resource Storage and Management
//!
//! A flexible resource management system for games with economies.
//! Supports storage with capacity limits, production/consumption tracking,
//! and resource transfers.
//!
//! Features:
//! - Generic resource types (works with any enum)
//! - Per-resource capacity limits
//! - Production and consumption rate tracking
//! - Net rate calculation (production - consumption)
//! - Resource transfers between storages
//! - Overflow and deficit handling policies
//! - Rate history for UI display
//!
//! Usage:
//! ```zig
//! const ResourceType = enum { credits, energy, minerals, food };
//!
//! var storage = ResourceStorage(ResourceType).init(allocator);
//! defer storage.deinit();
//!
//! try storage.defineResource(.credits, .{ .max_capacity = 10000 });
//! try storage.add(.credits, 500);
//! const balance = storage.get(.credits);
//! const net_rate = storage.getNetRate(.credits);
//! ```

const std = @import("std");

const log = std.log.scoped(.resource);

/// Overflow policy when adding resources beyond capacity
pub const OverflowPolicy = enum {
    /// Clamp to max capacity (lose excess)
    clamp,
    /// Reject the entire addition if it would overflow
    reject,
    /// Allow overflow (no capacity limit enforced)
    allow,
};

/// Deficit policy when removing more resources than available
pub const DeficitPolicy = enum {
    /// Clamp to zero (partial removal)
    clamp,
    /// Reject if insufficient resources
    reject,
    /// Allow negative values (debt)
    allow_negative,
};

/// Resource definition with properties
pub const ResourceDefinition = struct {
    /// Maximum storage capacity (0 = unlimited)
    max_capacity: f64 = 0,
    /// Starting amount
    initial_amount: f64 = 0,
    /// Display name (optional, for UI)
    name: ?[]const u8 = null,
    /// Overflow handling
    overflow_policy: OverflowPolicy = .clamp,
    /// Deficit handling
    deficit_policy: DeficitPolicy = .reject,
};

/// Result of a resource operation
pub const ResourceResult = enum {
    success,
    insufficient,
    overflow,
    not_defined,
};

/// Generic resource storage parameterized by resource type
pub fn ResourceStorage(comptime ResourceType: type) type {
    const resource_info = @typeInfo(ResourceType);
    if (resource_info != .@"enum") {
        @compileError("ResourceStorage requires an enum type, got " ++ @typeName(ResourceType));
    }

    return struct {
        const Self = @This();

        /// Per-resource data
        const ResourceData = struct {
            amount: f64 = 0,
            max_capacity: f64 = 0,
            production_rate: f64 = 0,
            consumption_rate: f64 = 0,
            overflow_policy: OverflowPolicy = .clamp,
            deficit_policy: DeficitPolicy = .reject,
            name: ?[]const u8 = null,
            defined: bool = false,
        };

        allocator: std.mem.Allocator,
        resources: std.AutoHashMap(ResourceType, ResourceData),

        /// Initialize the resource storage
        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .resources = std.AutoHashMap(ResourceType, ResourceData).init(allocator),
            };
        }

        /// Clean up resources
        pub fn deinit(self: *Self) void {
            self.resources.deinit();
        }

        /// Define a resource with its properties
        pub fn defineResource(self: *Self, resource: ResourceType, definition: ResourceDefinition) !void {
            try self.resources.put(resource, .{
                .amount = definition.initial_amount,
                .max_capacity = definition.max_capacity,
                .overflow_policy = definition.overflow_policy,
                .deficit_policy = definition.deficit_policy,
                .name = definition.name,
                .defined = true,
            });
        }

        /// Define multiple resources at once
        pub fn defineResources(self: *Self, definitions: []const struct { ResourceType, ResourceDefinition }) !void {
            for (definitions) |def| {
                try self.defineResource(def[0], def[1]);
            }
        }

        /// Check if a resource is defined
        pub fn isDefined(self: *const Self, resource: ResourceType) bool {
            if (self.resources.get(resource)) |data| {
                return data.defined;
            }
            return false;
        }

        /// Get current amount of a resource
        pub fn get(self: *const Self, resource: ResourceType) f64 {
            if (self.resources.get(resource)) |data| {
                return data.amount;
            }
            return 0;
        }

        /// Get maximum capacity for a resource (0 = unlimited)
        pub fn getCapacity(self: *const Self, resource: ResourceType) f64 {
            if (self.resources.get(resource)) |data| {
                return data.max_capacity;
            }
            return 0;
        }

        /// Get fill percentage (0.0 to 1.0, or 0 if no capacity)
        pub fn getFillRatio(self: *const Self, resource: ResourceType) f64 {
            if (self.resources.get(resource)) |data| {
                if (data.max_capacity > 0) {
                    return @min(1.0, data.amount / data.max_capacity);
                }
            }
            return 0;
        }

        /// Add resources with policy enforcement
        pub fn add(self: *Self, resource: ResourceType, amount: f64) ResourceResult {
            if (amount < 0) return self.remove(resource, -amount);

            const ptr = self.resources.getPtr(resource) orelse return .not_defined;

            const new_amount = ptr.amount + amount;

            if (ptr.max_capacity > 0 and new_amount > ptr.max_capacity) {
                switch (ptr.overflow_policy) {
                    .clamp => ptr.amount = ptr.max_capacity,
                    .reject => return .overflow,
                    .allow => ptr.amount = new_amount,
                }
            } else {
                ptr.amount = new_amount;
            }

            return .success;
        }

        /// Remove resources with policy enforcement
        pub fn remove(self: *Self, resource: ResourceType, amount: f64) ResourceResult {
            if (amount < 0) return self.add(resource, -amount);

            const ptr = self.resources.getPtr(resource) orelse return .not_defined;

            const new_amount = ptr.amount - amount;

            if (new_amount < 0) {
                switch (ptr.deficit_policy) {
                    .clamp => ptr.amount = 0,
                    .reject => return .insufficient,
                    .allow_negative => ptr.amount = new_amount,
                }
            } else {
                ptr.amount = new_amount;
            }

            return .success;
        }

        /// Set resource amount directly (respects capacity)
        pub fn set(self: *Self, resource: ResourceType, amount: f64) ResourceResult {
            const ptr = self.resources.getPtr(resource) orelse return .not_defined;

            if (ptr.max_capacity > 0 and amount > ptr.max_capacity) {
                switch (ptr.overflow_policy) {
                    .clamp => ptr.amount = ptr.max_capacity,
                    .reject => return .overflow,
                    .allow => ptr.amount = amount,
                }
            } else if (amount < 0) {
                switch (ptr.deficit_policy) {
                    .clamp => ptr.amount = 0,
                    .reject => return .insufficient,
                    .allow_negative => ptr.amount = amount,
                }
            } else {
                ptr.amount = amount;
            }

            return .success;
        }

        /// Check if storage has at least the specified amount
        pub fn has(self: *const Self, resource: ResourceType, amount: f64) bool {
            return self.get(resource) >= amount;
        }

        /// Check if storage can accept more of a resource
        pub fn hasSpace(self: *const Self, resource: ResourceType, amount: f64) bool {
            if (self.resources.get(resource)) |data| {
                if (data.max_capacity == 0) return true; // Unlimited
                return (data.amount + amount) <= data.max_capacity;
            }
            return false;
        }

        /// Get available space for a resource
        pub fn getAvailableSpace(self: *const Self, resource: ResourceType) f64 {
            if (self.resources.get(resource)) |data| {
                if (data.max_capacity == 0) return std.math.inf(f64);
                return @max(0, data.max_capacity - data.amount);
            }
            return 0;
        }

        // ====== Rate Tracking ======

        /// Set production rate for a resource
        pub fn setProductionRate(self: *Self, resource: ResourceType, rate: f64) ResourceResult {
            const ptr = self.resources.getPtr(resource) orelse return .not_defined;
            ptr.production_rate = rate;
            return .success;
        }

        /// Add to production rate
        pub fn addProductionRate(self: *Self, resource: ResourceType, rate: f64) ResourceResult {
            const ptr = self.resources.getPtr(resource) orelse return .not_defined;
            ptr.production_rate += rate;
            return .success;
        }

        /// Set consumption rate for a resource
        pub fn setConsumptionRate(self: *Self, resource: ResourceType, rate: f64) ResourceResult {
            const ptr = self.resources.getPtr(resource) orelse return .not_defined;
            ptr.consumption_rate = rate;
            return .success;
        }

        /// Add to consumption rate
        pub fn addConsumptionRate(self: *Self, resource: ResourceType, rate: f64) ResourceResult {
            const ptr = self.resources.getPtr(resource) orelse return .not_defined;
            ptr.consumption_rate += rate;
            return .success;
        }

        /// Get production rate
        pub fn getProductionRate(self: *const Self, resource: ResourceType) f64 {
            if (self.resources.get(resource)) |data| {
                return data.production_rate;
            }
            return 0;
        }

        /// Get consumption rate
        pub fn getConsumptionRate(self: *const Self, resource: ResourceType) f64 {
            if (self.resources.get(resource)) |data| {
                return data.consumption_rate;
            }
            return 0;
        }

        /// Get net rate (production - consumption)
        pub fn getNetRate(self: *const Self, resource: ResourceType) f64 {
            if (self.resources.get(resource)) |data| {
                return data.production_rate - data.consumption_rate;
            }
            return 0;
        }

        /// Reset all rates to zero
        pub fn resetRates(self: *Self) void {
            var iter = self.resources.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.production_rate = 0;
                entry.value_ptr.consumption_rate = 0;
            }
        }

        /// Apply rates for a time delta (call once per tick/turn)
        pub fn applyRates(self: *Self, delta: f64) void {
            var iter = self.resources.iterator();
            while (iter.next()) |entry| {
                const net = entry.value_ptr.production_rate - entry.value_ptr.consumption_rate;
                const change = net * delta;

                if (change > 0) {
                    _ = self.add(entry.key_ptr.*, change);
                } else if (change < 0) {
                    _ = self.remove(entry.key_ptr.*, -change);
                }
            }
        }

        // ====== Transfers ======

        /// Transfer resources to another storage
        pub fn transferTo(self: *Self, target: *Self, resource: ResourceType, amount: f64) ResourceResult {
            // Check if we have enough
            if (!self.has(resource, amount)) {
                return .insufficient;
            }

            // Check if target can accept
            if (!target.hasSpace(resource, amount)) {
                return .overflow;
            }

            // Perform transfer
            _ = self.remove(resource, amount);
            _ = target.add(resource, amount);

            return .success;
        }

        /// Transfer as much as possible (up to amount)
        pub fn transferToMax(self: *Self, target: *Self, resource: ResourceType, max_amount: f64) f64 {
            const available = self.get(resource);
            const space = target.getAvailableSpace(resource);
            const transfer_amount = @min(max_amount, @min(available, space));

            if (transfer_amount > 0) {
                _ = self.remove(resource, transfer_amount);
                _ = target.add(resource, transfer_amount);
            }

            return transfer_amount;
        }

        // ====== Cost Operations ======

        /// Check if storage can afford a set of costs
        pub fn canAfford(self: *const Self, costs: []const struct { ResourceType, f64 }) bool {
            for (costs) |cost| {
                if (!self.has(cost[0], cost[1])) {
                    return false;
                }
            }
            return true;
        }

        /// Deduct multiple resources at once (atomic - all or nothing)
        pub fn deductCosts(self: *Self, costs: []const struct { ResourceType, f64 }) ResourceResult {
            // First check all
            if (!self.canAfford(costs)) {
                return .insufficient;
            }

            // Then deduct all
            for (costs) |cost| {
                _ = self.remove(cost[0], cost[1]);
            }

            return .success;
        }

        /// Add multiple resources at once
        pub fn addBulk(self: *Self, amounts: []const struct { ResourceType, f64 }) void {
            for (amounts) |item| {
                _ = self.add(item[0], item[1]);
            }
        }

        // ====== Utility ======

        /// Clear all resources (set amounts to 0)
        pub fn clear(self: *Self) void {
            var iter = self.resources.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.amount = 0;
            }
        }

        /// Get count of defined resources
        pub fn getDefinedCount(self: *const Self) usize {
            var count: usize = 0;
            var iter = self.resources.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.defined) {
                    count += 1;
                }
            }
            return count;
        }

        /// Get all defined resource types
        pub fn getDefinedResources(self: *const Self, allocator: std.mem.Allocator) ![]ResourceType {
            var list = std.ArrayList(ResourceType).init(allocator);
            var iter = self.resources.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.defined) {
                    try list.append(entry.key_ptr.*);
                }
            }
            return list.toOwnedSlice();
        }

        /// Get a summary of all resources
        pub fn getSummary(self: *const Self, resource: ResourceType) ?struct {
            amount: f64,
            capacity: f64,
            production: f64,
            consumption: f64,
            net_rate: f64,
            fill_ratio: f64,
        } {
            if (self.resources.get(resource)) |data| {
                return .{
                    .amount = data.amount,
                    .capacity = data.max_capacity,
                    .production = data.production_rate,
                    .consumption = data.consumption_rate,
                    .net_rate = data.production_rate - data.consumption_rate,
                    .fill_ratio = if (data.max_capacity > 0) @min(1.0, data.amount / data.max_capacity) else 0,
                };
            }
            return null;
        }

        /// Set capacity for a resource
        pub fn setCapacity(self: *Self, resource: ResourceType, capacity: f64) ResourceResult {
            const ptr = self.resources.getPtr(resource) orelse return .not_defined;
            ptr.max_capacity = capacity;
            // Clamp current amount if needed
            if (capacity > 0 and ptr.amount > capacity) {
                ptr.amount = capacity;
            }
            return .success;
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

const TestResource = enum { credits, energy, minerals, food, research };

test "ResourceStorage - define and get" {
    var storage = ResourceStorage(TestResource).init(std.testing.allocator);
    defer storage.deinit();

    try storage.defineResource(.credits, .{ .initial_amount = 100, .max_capacity = 1000 });

    try std.testing.expect(storage.isDefined(.credits));
    try std.testing.expect(!storage.isDefined(.energy));
    try std.testing.expectEqual(@as(f64, 100), storage.get(.credits));
    try std.testing.expectEqual(@as(f64, 1000), storage.getCapacity(.credits));
}

test "ResourceStorage - add and remove" {
    var storage = ResourceStorage(TestResource).init(std.testing.allocator);
    defer storage.deinit();

    try storage.defineResource(.credits, .{ .initial_amount = 100 });

    try std.testing.expectEqual(ResourceResult.success, storage.add(.credits, 50));
    try std.testing.expectEqual(@as(f64, 150), storage.get(.credits));

    try std.testing.expectEqual(ResourceResult.success, storage.remove(.credits, 30));
    try std.testing.expectEqual(@as(f64, 120), storage.get(.credits));
}

test "ResourceStorage - capacity overflow clamp" {
    var storage = ResourceStorage(TestResource).init(std.testing.allocator);
    defer storage.deinit();

    try storage.defineResource(.credits, .{
        .initial_amount = 0,
        .max_capacity = 100,
        .overflow_policy = .clamp,
    });

    _ = storage.add(.credits, 150);
    try std.testing.expectEqual(@as(f64, 100), storage.get(.credits)); // Clamped
}

test "ResourceStorage - capacity overflow reject" {
    var storage = ResourceStorage(TestResource).init(std.testing.allocator);
    defer storage.deinit();

    try storage.defineResource(.credits, .{
        .initial_amount = 50,
        .max_capacity = 100,
        .overflow_policy = .reject,
    });

    try std.testing.expectEqual(ResourceResult.overflow, storage.add(.credits, 60));
    try std.testing.expectEqual(@as(f64, 50), storage.get(.credits)); // Unchanged
}

test "ResourceStorage - deficit reject" {
    var storage = ResourceStorage(TestResource).init(std.testing.allocator);
    defer storage.deinit();

    try storage.defineResource(.credits, .{
        .initial_amount = 50,
        .deficit_policy = .reject,
    });

    try std.testing.expectEqual(ResourceResult.insufficient, storage.remove(.credits, 60));
    try std.testing.expectEqual(@as(f64, 50), storage.get(.credits)); // Unchanged
}

test "ResourceStorage - deficit clamp" {
    var storage = ResourceStorage(TestResource).init(std.testing.allocator);
    defer storage.deinit();

    try storage.defineResource(.credits, .{
        .initial_amount = 50,
        .deficit_policy = .clamp,
    });

    try std.testing.expectEqual(ResourceResult.success, storage.remove(.credits, 60));
    try std.testing.expectEqual(@as(f64, 0), storage.get(.credits)); // Clamped to 0
}

test "ResourceStorage - deficit allow negative" {
    var storage = ResourceStorage(TestResource).init(std.testing.allocator);
    defer storage.deinit();

    try storage.defineResource(.credits, .{
        .initial_amount = 50,
        .deficit_policy = .allow_negative,
    });

    try std.testing.expectEqual(ResourceResult.success, storage.remove(.credits, 60));
    try std.testing.expectEqual(@as(f64, -10), storage.get(.credits)); // Negative allowed
}

test "ResourceStorage - rates" {
    var storage = ResourceStorage(TestResource).init(std.testing.allocator);
    defer storage.deinit();

    try storage.defineResource(.energy, .{ .initial_amount = 100 });

    _ = storage.setProductionRate(.energy, 10);
    _ = storage.setConsumptionRate(.energy, 3);

    try std.testing.expectEqual(@as(f64, 10), storage.getProductionRate(.energy));
    try std.testing.expectEqual(@as(f64, 3), storage.getConsumptionRate(.energy));
    try std.testing.expectEqual(@as(f64, 7), storage.getNetRate(.energy));
}

test "ResourceStorage - apply rates" {
    var storage = ResourceStorage(TestResource).init(std.testing.allocator);
    defer storage.deinit();

    try storage.defineResource(.energy, .{ .initial_amount = 100 });

    _ = storage.setProductionRate(.energy, 10);
    _ = storage.setConsumptionRate(.energy, 3);

    storage.applyRates(1.0); // 1 tick
    try std.testing.expectEqual(@as(f64, 107), storage.get(.energy)); // +7 net

    storage.applyRates(2.0); // 2 ticks
    try std.testing.expectEqual(@as(f64, 121), storage.get(.energy)); // +14 more
}

test "ResourceStorage - has and hasSpace" {
    var storage = ResourceStorage(TestResource).init(std.testing.allocator);
    defer storage.deinit();

    try storage.defineResource(.credits, .{
        .initial_amount = 50,
        .max_capacity = 100,
    });

    try std.testing.expect(storage.has(.credits, 50));
    try std.testing.expect(storage.has(.credits, 30));
    try std.testing.expect(!storage.has(.credits, 60));

    try std.testing.expect(storage.hasSpace(.credits, 50));
    try std.testing.expect(!storage.hasSpace(.credits, 60));
}

test "ResourceStorage - fill ratio" {
    var storage = ResourceStorage(TestResource).init(std.testing.allocator);
    defer storage.deinit();

    try storage.defineResource(.energy, .{
        .initial_amount = 25,
        .max_capacity = 100,
    });

    try std.testing.expectEqual(@as(f64, 0.25), storage.getFillRatio(.energy));

    _ = storage.set(.energy, 100);
    try std.testing.expectEqual(@as(f64, 1.0), storage.getFillRatio(.energy));
}

test "ResourceStorage - transfer" {
    var source = ResourceStorage(TestResource).init(std.testing.allocator);
    defer source.deinit();

    var target = ResourceStorage(TestResource).init(std.testing.allocator);
    defer target.deinit();

    try source.defineResource(.credits, .{ .initial_amount = 100 });
    try target.defineResource(.credits, .{ .initial_amount = 0, .max_capacity = 200 });

    try std.testing.expectEqual(ResourceResult.success, source.transferTo(&target, .credits, 50));
    try std.testing.expectEqual(@as(f64, 50), source.get(.credits));
    try std.testing.expectEqual(@as(f64, 50), target.get(.credits));
}

test "ResourceStorage - transfer insufficient" {
    var source = ResourceStorage(TestResource).init(std.testing.allocator);
    defer source.deinit();

    var target = ResourceStorage(TestResource).init(std.testing.allocator);
    defer target.deinit();

    try source.defineResource(.credits, .{ .initial_amount = 30 });
    try target.defineResource(.credits, .{ .initial_amount = 0 });

    try std.testing.expectEqual(ResourceResult.insufficient, source.transferTo(&target, .credits, 50));
    try std.testing.expectEqual(@as(f64, 30), source.get(.credits)); // Unchanged
}

test "ResourceStorage - transfer overflow" {
    var source = ResourceStorage(TestResource).init(std.testing.allocator);
    defer source.deinit();

    var target = ResourceStorage(TestResource).init(std.testing.allocator);
    defer target.deinit();

    try source.defineResource(.credits, .{ .initial_amount = 100 });
    try target.defineResource(.credits, .{ .initial_amount = 90, .max_capacity = 100 });

    try std.testing.expectEqual(ResourceResult.overflow, source.transferTo(&target, .credits, 20));
    try std.testing.expectEqual(@as(f64, 100), source.get(.credits)); // Unchanged
}

test "ResourceStorage - transferToMax" {
    var source = ResourceStorage(TestResource).init(std.testing.allocator);
    defer source.deinit();

    var target = ResourceStorage(TestResource).init(std.testing.allocator);
    defer target.deinit();

    try source.defineResource(.credits, .{ .initial_amount = 100 });
    try target.defineResource(.credits, .{ .initial_amount = 90, .max_capacity = 100 });

    const transferred = source.transferToMax(&target, .credits, 50);
    try std.testing.expectEqual(@as(f64, 10), transferred); // Only 10 space available
    try std.testing.expectEqual(@as(f64, 90), source.get(.credits));
    try std.testing.expectEqual(@as(f64, 100), target.get(.credits));
}

test "ResourceStorage - canAfford and deductCosts" {
    var storage = ResourceStorage(TestResource).init(std.testing.allocator);
    defer storage.deinit();

    try storage.defineResource(.credits, .{ .initial_amount = 100 });
    try storage.defineResource(.energy, .{ .initial_amount = 50 });
    try storage.defineResource(.minerals, .{ .initial_amount = 30 });

    const costs = [_]struct { TestResource, f64 }{
        .{ .credits, 50 },
        .{ .energy, 20 },
        .{ .minerals, 10 },
    };

    try std.testing.expect(storage.canAfford(&costs));

    try std.testing.expectEqual(ResourceResult.success, storage.deductCosts(&costs));
    try std.testing.expectEqual(@as(f64, 50), storage.get(.credits));
    try std.testing.expectEqual(@as(f64, 30), storage.get(.energy));
    try std.testing.expectEqual(@as(f64, 20), storage.get(.minerals));
}

test "ResourceStorage - deductCosts insufficient" {
    var storage = ResourceStorage(TestResource).init(std.testing.allocator);
    defer storage.deinit();

    try storage.defineResource(.credits, .{ .initial_amount = 100 });
    try storage.defineResource(.energy, .{ .initial_amount = 10 }); // Not enough

    const costs = [_]struct { TestResource, f64 }{
        .{ .credits, 50 },
        .{ .energy, 20 },
    };

    try std.testing.expect(!storage.canAfford(&costs));
    try std.testing.expectEqual(ResourceResult.insufficient, storage.deductCosts(&costs));

    // Should be unchanged (atomic)
    try std.testing.expectEqual(@as(f64, 100), storage.get(.credits));
    try std.testing.expectEqual(@as(f64, 10), storage.get(.energy));
}

test "ResourceStorage - undefined resource" {
    var storage = ResourceStorage(TestResource).init(std.testing.allocator);
    defer storage.deinit();

    // Operations on undefined resource
    try std.testing.expectEqual(ResourceResult.not_defined, storage.add(.credits, 100));
    try std.testing.expectEqual(ResourceResult.not_defined, storage.remove(.credits, 50));
    try std.testing.expectEqual(@as(f64, 0), storage.get(.credits));
}

test "ResourceStorage - clear" {
    var storage = ResourceStorage(TestResource).init(std.testing.allocator);
    defer storage.deinit();

    try storage.defineResource(.credits, .{ .initial_amount = 100 });
    try storage.defineResource(.energy, .{ .initial_amount = 50 });

    storage.clear();

    try std.testing.expectEqual(@as(f64, 0), storage.get(.credits));
    try std.testing.expectEqual(@as(f64, 0), storage.get(.energy));
}

test "ResourceStorage - getSummary" {
    var storage = ResourceStorage(TestResource).init(std.testing.allocator);
    defer storage.deinit();

    try storage.defineResource(.energy, .{
        .initial_amount = 75,
        .max_capacity = 100,
    });
    _ = storage.setProductionRate(.energy, 10);
    _ = storage.setConsumptionRate(.energy, 3);

    const summary = storage.getSummary(.energy).?;
    try std.testing.expectEqual(@as(f64, 75), summary.amount);
    try std.testing.expectEqual(@as(f64, 100), summary.capacity);
    try std.testing.expectEqual(@as(f64, 10), summary.production);
    try std.testing.expectEqual(@as(f64, 3), summary.consumption);
    try std.testing.expectEqual(@as(f64, 7), summary.net_rate);
    try std.testing.expectEqual(@as(f64, 0.75), summary.fill_ratio);
}

test "ResourceStorage - setCapacity clamps amount" {
    var storage = ResourceStorage(TestResource).init(std.testing.allocator);
    defer storage.deinit();

    try storage.defineResource(.energy, .{
        .initial_amount = 100,
        .max_capacity = 200,
    });

    _ = storage.setCapacity(.energy, 50); // Reduce capacity below current amount
    try std.testing.expectEqual(@as(f64, 50), storage.get(.energy)); // Clamped
    try std.testing.expectEqual(@as(f64, 50), storage.getCapacity(.energy));
}

test "ResourceStorage - getDefinedResources" {
    var storage = ResourceStorage(TestResource).init(std.testing.allocator);
    defer storage.deinit();

    try storage.defineResource(.credits, .{});
    try storage.defineResource(.energy, .{});
    try storage.defineResource(.minerals, .{});

    const resources = try storage.getDefinedResources(std.testing.allocator);
    defer std.testing.allocator.free(resources);

    try std.testing.expectEqual(@as(usize, 3), resources.len);
}

test "ResourceStorage - addBulk" {
    var storage = ResourceStorage(TestResource).init(std.testing.allocator);
    defer storage.deinit();

    try storage.defineResource(.credits, .{ .initial_amount = 0 });
    try storage.defineResource(.energy, .{ .initial_amount = 0 });
    try storage.defineResource(.minerals, .{ .initial_amount = 0 });

    storage.addBulk(&[_]struct { TestResource, f64 }{
        .{ .credits, 100 },
        .{ .energy, 50 },
        .{ .minerals, 25 },
    });

    try std.testing.expectEqual(@as(f64, 100), storage.get(.credits));
    try std.testing.expectEqual(@as(f64, 50), storage.get(.energy));
    try std.testing.expectEqual(@as(f64, 25), storage.get(.minerals));
}

test "ResourceStorage - getAvailableSpace" {
    var storage = ResourceStorage(TestResource).init(std.testing.allocator);
    defer storage.deinit();

    try storage.defineResource(.energy, .{
        .initial_amount = 30,
        .max_capacity = 100,
    });

    try std.testing.expectEqual(@as(f64, 70), storage.getAvailableSpace(.energy));

    // Unlimited capacity
    try storage.defineResource(.credits, .{ .initial_amount = 1000 });
    try std.testing.expect(storage.getAvailableSpace(.credits) == std.math.inf(f64));
}

test "ResourceStorage - resetRates" {
    var storage = ResourceStorage(TestResource).init(std.testing.allocator);
    defer storage.deinit();

    try storage.defineResource(.energy, .{ .initial_amount = 100 });
    try storage.defineResource(.credits, .{ .initial_amount = 100 });

    _ = storage.setProductionRate(.energy, 10);
    _ = storage.setConsumptionRate(.energy, 5);
    _ = storage.setProductionRate(.credits, 20);

    storage.resetRates();

    try std.testing.expectEqual(@as(f64, 0), storage.getProductionRate(.energy));
    try std.testing.expectEqual(@as(f64, 0), storage.getConsumptionRate(.energy));
    try std.testing.expectEqual(@as(f64, 0), storage.getProductionRate(.credits));
}

test "ResourceStorage - negative rates" {
    var storage = ResourceStorage(TestResource).init(std.testing.allocator);
    defer storage.deinit();

    try storage.defineResource(.energy, .{
        .initial_amount = 100,
        .deficit_policy = .clamp,
    });

    _ = storage.setProductionRate(.energy, 5);
    _ = storage.setConsumptionRate(.energy, 15);

    try std.testing.expectEqual(@as(f64, -10), storage.getNetRate(.energy));

    storage.applyRates(5.0); // Lose 50
    try std.testing.expectEqual(@as(f64, 50), storage.get(.energy));

    storage.applyRates(10.0); // Would lose 100, but clamps to 0
    try std.testing.expectEqual(@as(f64, 0), storage.get(.energy));
}
