const std = @import("std");

/// System interface - all systems must implement this
/// Systems are pure functions that operate on components
pub const System = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        update: *const fn (ptr: *anyopaque, delta_time: f32) anyerror!void,
        deinit: *const fn (ptr: *anyopaque) void,
    };

    pub fn update(self: System, delta_time: f32) !void {
        try self.vtable.update(self.ptr, delta_time);
    }

    pub fn deinit(self: System) void {
        self.vtable.deinit(self.ptr);
    }

    /// Helper to create a System from any type that implements the interface
    pub fn init(pointer: anytype) System {
        const T = @TypeOf(pointer.*);
        const ptr = @as(*anyopaque, @ptrCast(pointer));

        const gen = struct {
            fn updateImpl(p: *anyopaque, dt: f32) anyerror!void {
                const self: *T = @ptrCast(@alignCast(p));
                return self.update(dt);
            }

            fn deinitImpl(p: *anyopaque) void {
                const self: *T = @ptrCast(@alignCast(p));
                self.deinit();
            }

            const vtable = VTable{
                .update = updateImpl,
                .deinit = deinitImpl,
            };
        };

        return .{
            .ptr = ptr,
            .vtable = &gen.vtable,
        };
    }
};

/// SystemRegistry manages multiple systems and their execution order
pub const SystemRegistry = struct {
    allocator: std.mem.Allocator,
    systems: std.ArrayList(System),

    pub fn init(allocator: std.mem.Allocator) SystemRegistry {
        return .{
            .allocator = allocator,
            .systems = .{},
        };
    }

    pub fn deinit(self: *SystemRegistry) void {
        for (self.systems.items) |system| {
            system.deinit();
        }
        self.systems.deinit(self.allocator);
    }

    /// Register a system (systems execute in registration order)
    pub fn register(self: *SystemRegistry, system: System) !void {
        try self.systems.append(self.allocator, system);
    }

    /// Update all systems
    pub fn updateAll(self: *SystemRegistry, delta_time: f32) !void {
        for (self.systems.items) |system| {
            try system.update(delta_time);
        }
    }
};

test "System - interface and registry" {
    // Example system implementation
    const TestSystem = struct {
        counter: u32,

        pub fn update(self: *@This(), delta_time: f32) !void {
            _ = delta_time;
            self.counter += 1;
        }

        pub fn deinit(self: *@This()) void {
            _ = self;
        }
    };

    var test_sys = TestSystem{ .counter = 0 };
    const system = System.init(&test_sys);

    try system.update(0.016);
    try std.testing.expectEqual(@as(u32, 1), test_sys.counter);

    try system.update(0.016);
    try std.testing.expectEqual(@as(u32, 2), test_sys.counter);
}

test "SystemRegistry - multiple systems" {
    const CounterSystem = struct {
        value: *u32,

        pub fn update(self: *@This(), delta_time: f32) !void {
            _ = delta_time;
            self.value.* += 1;
        }

        pub fn deinit(self: *@This()) void {
            _ = self;
        }
    };

    var counter: u32 = 0;
    var sys1 = CounterSystem{ .value = &counter };
    var sys2 = CounterSystem{ .value = &counter };

    var registry = SystemRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.register(System.init(&sys1));
    try registry.register(System.init(&sys2));

    try registry.updateAll(0.016);
    try std.testing.expectEqual(@as(u32, 2), counter);

    try registry.updateAll(0.016);
    try std.testing.expectEqual(@as(u32, 4), counter);
}
