const std = @import("std");
const Entity = @import("entity.zig").Entity;

/// ComponentArray stores components in a packed array for cache-friendly iteration
/// Uses sparse set pattern: entity ID -> dense index mapping
pub fn ComponentArray(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        /// Dense array of components (packed, no gaps)
        components: std.ArrayList(T),
        /// Dense array of entity IDs (parallel to components)
        entities: std.ArrayList(Entity),
        /// Sparse array: entity ID -> dense index (u32.max = not present)
        entity_to_index: std.ArrayList(u32),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .components = .{},
                .entities = .{},
                .entity_to_index = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.components.deinit(self.allocator);
            self.entities.deinit(self.allocator);
            self.entity_to_index.deinit(self.allocator);
        }

        /// Add a component to an entity
        pub fn add(self: *Self, entity: Entity, component: T) !void {
            // Ensure sparse array is large enough
            while (self.entity_to_index.items.len <= entity.id) {
                try self.entity_to_index.append(self.allocator, std.math.maxInt(u32));
            }

            // Check if entity already has this component
            if (self.entity_to_index.items[entity.id] != std.math.maxInt(u32)) {
                return error.ComponentAlreadyExists;
            }

            // Add to dense arrays
            const index: u32 = @intCast(self.components.items.len);
            try self.components.append(self.allocator, component);
            try self.entities.append(self.allocator, entity);

            // Update sparse mapping
            self.entity_to_index.items[entity.id] = index;
        }

        /// Remove a component from an entity
        pub fn remove(self: *Self, entity: Entity) !void {
            if (entity.id >= self.entity_to_index.items.len) {
                return error.ComponentNotFound;
            }

            const index = self.entity_to_index.items[entity.id];
            if (index == std.math.maxInt(u32)) {
                return error.ComponentNotFound;
            }

            // Swap with last element (swap-and-pop)
            const last_index = self.components.items.len - 1;
            if (index != last_index) {
                self.components.items[index] = self.components.items[last_index];
                self.entities.items[index] = self.entities.items[last_index];

                // Update the moved entity's index
                const moved_entity = self.entities.items[index];
                self.entity_to_index.items[moved_entity.id] = index;
            }

            // Remove last element
            _ = self.components.pop();
            _ = self.entities.pop();

            // Mark as removed in sparse array
            self.entity_to_index.items[entity.id] = std.math.maxInt(u32);
        }

        /// Get a component for an entity (returns pointer for modification)
        pub fn get(self: *Self, entity: Entity) !*T {
            if (entity.id >= self.entity_to_index.items.len) {
                return error.ComponentNotFound;
            }

            const index = self.entity_to_index.items[entity.id];
            if (index == std.math.maxInt(u32)) {
                return error.ComponentNotFound;
            }

            return &self.components.items[index];
        }

        /// Check if an entity has this component
        pub fn has(self: *Self, entity: Entity) bool {
            if (entity.id >= self.entity_to_index.items.len) {
                return false;
            }
            return self.entity_to_index.items[entity.id] != std.math.maxInt(u32);
        }

        /// Get the number of components
        pub fn count(self: *Self) usize {
            return self.components.items.len;
        }

        /// Iterator for all components
        pub fn iterator(self: *Self) ComponentIterator(T) {
            return ComponentIterator(T){
                .components = self.components.items,
                .entities = self.entities.items,
                .index = 0,
            };
        }
    };
}

/// Iterator over components and their entities
pub fn ComponentIterator(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const Entry = struct {
            entity: Entity,
            component: *T,
        };

        components: []T,
        entities: []Entity,
        index: usize,

        pub fn next(self: *Self) ?Entry {
            if (self.index >= self.components.len) {
                return null;
            }

            const result = Entry{
                .entity = self.entities[self.index],
                .component = &self.components[self.index],
            };
            self.index += 1;
            return result;
        }
    };
}

test "ComponentArray - basic add and get" {
    const Position = struct { x: f32, y: f32 };

    var array = ComponentArray(Position).init(std.testing.allocator);
    defer array.deinit();

    const e1 = Entity.init(0, 0);
    const e2 = Entity.init(1, 0);

    try array.add(e1, .{ .x = 10, .y = 20 });
    try array.add(e2, .{ .x = 30, .y = 40 });

    const pos1 = try array.get(e1);
    try std.testing.expectEqual(@as(f32, 10), pos1.x);
    try std.testing.expectEqual(@as(f32, 20), pos1.y);

    const pos2 = try array.get(e2);
    try std.testing.expectEqual(@as(f32, 30), pos2.x);
    try std.testing.expectEqual(@as(f32, 40), pos2.y);
}

test "ComponentArray - remove and swap" {
    const Health = struct { value: i32 };

    var array = ComponentArray(Health).init(std.testing.allocator);
    defer array.deinit();

    const e1 = Entity.init(0, 0);
    const e2 = Entity.init(1, 0);
    const e3 = Entity.init(2, 0);

    try array.add(e1, .{ .value = 100 });
    try array.add(e2, .{ .value = 200 });
    try array.add(e3, .{ .value = 300 });

    try std.testing.expectEqual(@as(usize, 3), array.count());

    // Remove middle element
    try array.remove(e2);
    try std.testing.expectEqual(@as(usize, 2), array.count());

    // e2 should no longer have component
    try std.testing.expectError(error.ComponentNotFound, array.get(e2));

    // e1 and e3 should still be accessible
    const h1 = try array.get(e1);
    try std.testing.expectEqual(@as(i32, 100), h1.value);

    const h3 = try array.get(e3);
    try std.testing.expectEqual(@as(i32, 300), h3.value);
}

test "ComponentArray - iterator" {
    const Speed = struct { value: f32 };

    var array = ComponentArray(Speed).init(std.testing.allocator);
    defer array.deinit();

    try array.add(Entity.init(0, 0), .{ .value = 1.5 });
    try array.add(Entity.init(1, 0), .{ .value = 2.5 });
    try array.add(Entity.init(2, 0), .{ .value = 3.5 });

    var iter = array.iterator();
    var count: usize = 0;
    while (iter.next()) |_| {
        count += 1;
    }

    try std.testing.expectEqual(@as(usize, 3), count);
}
