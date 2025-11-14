const std = @import("std");
const entity_mod = @import("entity.zig");
const component_mod = @import("component.zig");
const system_mod = @import("system.zig");

pub const Entity = entity_mod.Entity;
pub const EntityManager = entity_mod.EntityManager;
pub const ComponentArray = component_mod.ComponentArray;
pub const System = system_mod.System;
pub const SystemRegistry = system_mod.SystemRegistry;
pub const SystemId = system_mod.SystemId;
pub const SystemOptions = system_mod.SystemOptions;

/// World is the central ECS coordinator
/// Manages entities, components, and systems
pub const World = struct {
    allocator: std.mem.Allocator,
    entity_manager: EntityManager,
    system_registry: SystemRegistry,
    /// Component storage is managed externally via getComponentArray()
    /// This keeps World generic and extensible

    pub fn init(allocator: std.mem.Allocator) World {
        return .{
            .allocator = allocator,
            .entity_manager = EntityManager.init(allocator),
            .system_registry = SystemRegistry.init(allocator),
        };
    }

    pub fn deinit(self: *World) void {
        self.entity_manager.deinit();
        self.system_registry.deinit();
    }

    /// Create a new entity
    pub fn createEntity(self: *World) !Entity {
        return try self.entity_manager.create();
    }

    /// Destroy an entity
    pub fn destroyEntity(self: *World, entity: Entity) !void {
        try self.entity_manager.destroy(entity);
        // Note: Components are managed separately and should be cleaned up
        // by the game/application layer before destroying the entity
    }

    /// Check if an entity is alive
    pub fn isEntityAlive(self: *World, entity: Entity) bool {
        return self.entity_manager.isAlive(entity);
    }

    /// Get entity count
    pub fn entityCount(self: *World) u32 {
        return self.entity_manager.count();
    }

    /// Register a system without dependencies
    /// Returns a SystemId that can be used as a dependency for other systems
    pub fn registerSystem(self: *World, system: System) !SystemId {
        return try self.system_registry.register(system);
    }

    /// Register a system with dependencies
    /// Returns a SystemId that can be used as a dependency for other systems
    pub fn registerSystemWithOptions(self: *World, system: System, options: SystemOptions) !SystemId {
        return try self.system_registry.registerWithOptions(system, options);
    }

    /// Update all systems
    pub fn update(self: *World, delta_time: f32) !void {
        try self.system_registry.updateAll(delta_time);
    }
};

test "World - basic entity management" {
    var world = World.init(std.testing.allocator);
    defer world.deinit();

    const e1 = try world.createEntity();
    const e2 = try world.createEntity();
    const e3 = try world.createEntity();

    try std.testing.expectEqual(@as(u32, 3), world.entityCount());
    try std.testing.expect(world.isEntityAlive(e1));
    try std.testing.expect(world.isEntityAlive(e2));
    try std.testing.expect(world.isEntityAlive(e3));

    try world.destroyEntity(e2);
    try std.testing.expectEqual(@as(u32, 2), world.entityCount());
    try std.testing.expect(!world.isEntityAlive(e2));
}

test "World - system integration" {
    const TestSystem = struct {
        update_count: *u32,

        pub fn update(self: *@This(), delta_time: f32) !void {
            _ = delta_time;
            self.update_count.* += 1;
        }

        pub fn deinit(self: *@This()) void {
            _ = self;
        }
    };

    var world = World.init(std.testing.allocator);
    defer world.deinit();

    var update_count: u32 = 0;
    var test_sys = TestSystem{ .update_count = &update_count };

    _ = try world.registerSystem(System.init(&test_sys));

    try world.update(0.016);
    try std.testing.expectEqual(@as(u32, 1), update_count);

    try world.update(0.016);
    try std.testing.expectEqual(@as(u32, 2), update_count);
}

test "World - system dependency ordering" {
    const OrderTracker = struct {
        order: *std.ArrayList(u8),
        allocator: std.mem.Allocator,
        marker: u8,

        pub fn update(self: *@This(), delta_time: f32) !void {
            _ = delta_time;
            try self.order.append(self.allocator, self.marker);
        }

        pub fn deinit(self: *@This()) void {
            _ = self;
        }
    };

    var world = World.init(std.testing.allocator);
    defer world.deinit();

    var order: std.ArrayList(u8) = .{};
    defer order.deinit(std.testing.allocator);

    var sys_a = OrderTracker{ .order = &order, .allocator = std.testing.allocator, .marker = 'A' };
    var sys_b = OrderTracker{ .order = &order, .allocator = std.testing.allocator, .marker = 'B' };
    var sys_c = OrderTracker{ .order = &order, .allocator = std.testing.allocator, .marker = 'C' };

    // Register systems: C depends on B, B depends on A
    // Expected order: A -> B -> C
    const id_a = try world.registerSystem(System.init(&sys_a));
    const id_b = try world.registerSystemWithOptions(System.init(&sys_b), .{ .depends_on = &.{id_a} });
    _ = try world.registerSystemWithOptions(System.init(&sys_c), .{ .depends_on = &.{id_b} });

    try world.update(0.016);

    // Verify execution order
    try std.testing.expectEqual(@as(usize, 3), order.items.len);
    try std.testing.expectEqual(@as(u8, 'A'), order.items[0]);
    try std.testing.expectEqual(@as(u8, 'B'), order.items[1]);
    try std.testing.expectEqual(@as(u8, 'C'), order.items[2]);
}
