// ECS (Entity-Component-System) module exports
pub const Entity = @import("ecs/entity.zig").Entity;
pub const EntityManager = @import("ecs/entity.zig").EntityManager;
pub const ComponentArray = @import("ecs/component.zig").ComponentArray;
pub const ComponentIterator = @import("ecs/component.zig").ComponentIterator;
pub const System = @import("ecs/system.zig").System;
pub const SystemRegistry = @import("ecs/system.zig").SystemRegistry;
pub const World = @import("ecs/world.zig").World;

// Reflection system exports
pub const reflection = @import("ecs/reflection.zig");
pub const ComponentAccessor = @import("ecs/component_accessor.zig").ComponentAccessor;
pub const serialization = @import("ecs/serialization.zig");

// Include tests
test {
    _ = @import("ecs/error_tests.zig");
    _ = @import("ecs/reflection.zig");
    _ = @import("ecs/component_accessor.zig");
    _ = @import("ecs/serialization.zig");
}
