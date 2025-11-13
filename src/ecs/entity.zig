const std = @import("std");

/// Entity is a unique identifier with generation tracking for recycling
pub const Entity = struct {
    id: u32,
    generation: u32,

    pub fn init(id: u32, generation: u32) Entity {
        return .{ .id = id, .generation = generation };
    }

    pub fn eql(self: Entity, other: Entity) bool {
        return self.id == other.id and self.generation == other.generation;
    }
};

/// EntityManager handles entity creation, destruction, and recycling
pub const EntityManager = struct {
    allocator: std.mem.Allocator,
    /// List of entity generations (index = entity ID)
    generations: std.ArrayList(u32),
    /// Free list of recycled entity IDs
    free_list: std.ArrayList(u32),
    /// Number of alive entities
    alive_count: u32,

    pub fn init(allocator: std.mem.Allocator) EntityManager {
        return .{
            .allocator = allocator,
            .generations = .{},
            .free_list = .{},
            .alive_count = 0,
        };
    }

    pub fn deinit(self: *EntityManager) void {
        self.generations.deinit(self.allocator);
        self.free_list.deinit(self.allocator);
    }

    /// Create a new entity, recycling IDs when possible
    pub fn create(self: *EntityManager) !Entity {
        var id: u32 = undefined;
        var generation: u32 = undefined;

        if (self.free_list.items.len > 0) {
            // Reuse a recycled ID
            id = self.free_list.pop() orelse unreachable; // Safe because we checked len > 0
            generation = self.generations.items[id];
        } else {
            // Allocate a new ID
            id = @intCast(self.generations.items.len);
            generation = 0;
            try self.generations.append(self.allocator, generation);
        }

        self.alive_count += 1;
        return Entity.init(id, generation);
    }

    /// Destroy an entity, recycling its ID for future use
    pub fn destroy(self: *EntityManager, entity: Entity) !void {
        if (!self.isAlive(entity)) {
            return error.EntityNotAlive;
        }

        // Increment generation to invalidate old references
        self.generations.items[entity.id] += 1;

        // Add to free list for recycling
        try self.free_list.append(self.allocator, entity.id);

        self.alive_count -= 1;
    }

    /// Check if an entity is still alive
    pub fn isAlive(self: *EntityManager, entity: Entity) bool {
        if (entity.id >= self.generations.items.len) {
            return false;
        }
        return self.generations.items[entity.id] == entity.generation;
    }

    /// Get total number of alive entities
    pub fn count(self: *EntityManager) u32 {
        return self.alive_count;
    }
};

test "EntityManager - basic creation" {
    var manager = EntityManager.init(std.testing.allocator);
    defer manager.deinit();

    const e1 = try manager.create();
    const e2 = try manager.create();
    const e3 = try manager.create();

    try std.testing.expectEqual(@as(u32, 0), e1.id);
    try std.testing.expectEqual(@as(u32, 1), e2.id);
    try std.testing.expectEqual(@as(u32, 2), e3.id);
    try std.testing.expectEqual(@as(u32, 3), manager.count());
}

test "EntityManager - entity recycling" {
    var manager = EntityManager.init(std.testing.allocator);
    defer manager.deinit();

    const e1 = try manager.create();
    const e2 = try manager.create();

    // Destroy e1
    try manager.destroy(e1);
    try std.testing.expectEqual(@as(u32, 1), manager.count());

    // Create new entity - should reuse e1's ID with incremented generation
    const e3 = try manager.create();
    try std.testing.expectEqual(e1.id, e3.id); // Same ID
    try std.testing.expectEqual(e1.generation + 1, e3.generation); // New generation

    // Old e1 should not be alive
    try std.testing.expect(!manager.isAlive(e1));
    try std.testing.expect(manager.isAlive(e2));
    try std.testing.expect(manager.isAlive(e3));
}

test "EntityManager - double destroy error" {
    var manager = EntityManager.init(std.testing.allocator);
    defer manager.deinit();

    const e1 = try manager.create();
    try manager.destroy(e1);

    // Second destroy should fail
    try std.testing.expectError(error.EntityNotAlive, manager.destroy(e1));
}
