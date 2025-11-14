const std = @import("std");

/// Unique identifier for a registered system
pub const SystemId = u32;

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

/// System registration options
pub const SystemOptions = struct {
    /// List of system IDs this system depends on
    /// This system will execute after all dependencies
    depends_on: []const SystemId = &.{},
};

/// Internal node for dependency graph
const SystemNode = struct {
    id: SystemId,
    system: System,
    dependencies: std.ArrayList(SystemId),

    fn deinit(self: *SystemNode, allocator: std.mem.Allocator) void {
        self.dependencies.deinit(allocator);
    }
};

/// SystemRegistry manages multiple systems and their execution order
/// Supports dependency-based ordering via topological sort
pub const SystemRegistry = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayList(SystemNode),
    sorted_order: std.ArrayList(SystemId),
    next_id: SystemId,
    needs_resort: bool,

    pub fn init(allocator: std.mem.Allocator) SystemRegistry {
        return .{
            .allocator = allocator,
            .nodes = .{},
            .sorted_order = .{},
            .next_id = 0,
            .needs_resort = false,
        };
    }

    pub fn deinit(self: *SystemRegistry) void {
        for (self.nodes.items) |*node| {
            node.system.deinit();
            node.deinit(self.allocator);
        }
        self.nodes.deinit(self.allocator);
        self.sorted_order.deinit(self.allocator);
    }

    /// Register a system with optional dependencies
    /// Returns a unique SystemId that can be used as a dependency for other systems
    pub fn registerWithOptions(self: *SystemRegistry, system: System, options: SystemOptions) !SystemId {
        const id = self.next_id;
        self.next_id += 1;

        // Validate dependencies exist
        for (options.depends_on) |dep_id| {
            if (!self.systemExists(dep_id)) {
                return error.InvalidDependency;
            }
        }

        // Create node with dependencies
        var dependencies: std.ArrayList(SystemId) = .{};
        try dependencies.appendSlice(self.allocator, options.depends_on);

        try self.nodes.append(self.allocator, .{
            .id = id,
            .system = system,
            .dependencies = dependencies,
        });

        self.needs_resort = true;
        return id;
    }

    /// Register a system without dependencies (convenience method)
    /// Systems execute in registration order if no dependencies specified
    pub fn register(self: *SystemRegistry, system: System) !SystemId {
        return self.registerWithOptions(system, .{});
    }

    /// Check if a system ID exists
    fn systemExists(self: *SystemRegistry, id: SystemId) bool {
        for (self.nodes.items) |node| {
            if (node.id == id) return true;
        }
        return false;
    }

    /// Perform topological sort using Kahn's algorithm
    fn topologicalSort(self: *SystemRegistry) !void {
        self.sorted_order.clearRetainingCapacity();

        const n = self.nodes.items.len;
        if (n == 0) return;

        // Calculate in-degree for each node
        // In-degree = number of dependencies this system has
        var in_degree = try self.allocator.alloc(u32, n);
        defer self.allocator.free(in_degree);

        for (self.nodes.items, 0..) |node, idx| {
            in_degree[idx] = @intCast(node.dependencies.items.len);
        }

        // Queue for nodes with no dependencies
        var queue: std.ArrayList(usize) = .{};
        defer queue.deinit(self.allocator);

        for (in_degree, 0..) |degree, idx| {
            if (degree == 0) {
                try queue.append(self.allocator, idx);
            }
        }

        var processed: usize = 0;
        while (queue.items.len > 0) {
            const idx = queue.orderedRemove(0);
            const node = &self.nodes.items[idx];
            try self.sorted_order.append(self.allocator, node.id);
            processed += 1;

            // Reduce in-degree for all nodes that depend on this one
            for (self.nodes.items, 0..) |dependent, dep_idx| {
                // Check if dependent system lists this node as a dependency
                for (dependent.dependencies.items) |dep_id| {
                    if (dep_id == node.id) {
                        in_degree[dep_idx] -= 1;
                        if (in_degree[dep_idx] == 0) {
                            try queue.append(self.allocator, dep_idx);
                        }
                        break;
                    }
                }
            }
        }

        // Check for cycles
        if (processed != n) {
            return error.CyclicDependency;
        }
    }

    /// Update all systems in dependency order
    pub fn updateAll(self: *SystemRegistry, delta_time: f32) !void {
        if (self.needs_resort) {
            try self.topologicalSort();
            self.needs_resort = false;
        }

        for (self.sorted_order.items) |id| {
            // Find and update the system with this ID
            for (self.nodes.items) |node| {
                if (node.id == id) {
                    try node.system.update(delta_time);
                    break;
                }
            }
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

    _ = try registry.register(System.init(&sys1));
    _ = try registry.register(System.init(&sys2));

    try registry.updateAll(0.016);
    try std.testing.expectEqual(@as(u32, 2), counter);

    try registry.updateAll(0.016);
    try std.testing.expectEqual(@as(u32, 4), counter);
}

test "SystemRegistry - dependency ordering" {
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

    var order: std.ArrayList(u8) = .{};
    defer order.deinit(std.testing.allocator);

    var sys_a = OrderTracker{ .order = &order, .allocator = std.testing.allocator, .marker = 'A' };
    var sys_b = OrderTracker{ .order = &order, .allocator = std.testing.allocator, .marker = 'B' };
    var sys_c = OrderTracker{ .order = &order, .allocator = std.testing.allocator, .marker = 'C' };

    var registry = SystemRegistry.init(std.testing.allocator);
    defer registry.deinit();

    // Register systems: C depends on B, B depends on A
    // Expected order: A -> B -> C
    const id_a = try registry.register(System.init(&sys_a));
    const id_b = try registry.registerWithOptions(System.init(&sys_b), .{ .depends_on = &.{id_a} });
    _ = try registry.registerWithOptions(System.init(&sys_c), .{ .depends_on = &.{id_b} });

    try registry.updateAll(0.016);

    // Verify execution order
    try std.testing.expectEqual(@as(usize, 3), order.items.len);
    try std.testing.expectEqual(@as(u8, 'A'), order.items[0]);
    try std.testing.expectEqual(@as(u8, 'B'), order.items[1]);
    try std.testing.expectEqual(@as(u8, 'C'), order.items[2]);
}

test "SystemRegistry - complex dependency graph" {
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

    var order: std.ArrayList(u8) = .{};
    defer order.deinit(std.testing.allocator);

    var sys_a = OrderTracker{ .order = &order, .allocator = std.testing.allocator, .marker = 'A' };
    var sys_b = OrderTracker{ .order = &order, .allocator = std.testing.allocator, .marker = 'B' };
    var sys_c = OrderTracker{ .order = &order, .allocator = std.testing.allocator, .marker = 'C' };
    var sys_d = OrderTracker{ .order = &order, .allocator = std.testing.allocator, .marker = 'D' };

    var registry = SystemRegistry.init(std.testing.allocator);
    defer registry.deinit();

    // Diamond dependency:
    //     A
    //    / \
    //   B   C
    //    \ /
    //     D
    // D depends on both B and C, which both depend on A
    const id_a = try registry.register(System.init(&sys_a));
    const id_b = try registry.registerWithOptions(System.init(&sys_b), .{ .depends_on = &.{id_a} });
    const id_c = try registry.registerWithOptions(System.init(&sys_c), .{ .depends_on = &.{id_a} });
    _ = try registry.registerWithOptions(System.init(&sys_d), .{ .depends_on = &.{ id_b, id_c } });

    try registry.updateAll(0.016);

    // Verify execution order
    try std.testing.expectEqual(@as(usize, 4), order.items.len);
    try std.testing.expectEqual(@as(u8, 'A'), order.items[0]); // A must be first
    // B and C can be in any order (both depend only on A)
    try std.testing.expect((order.items[1] == 'B' and order.items[2] == 'C') or
        (order.items[1] == 'C' and order.items[2] == 'B'));
    try std.testing.expectEqual(@as(u8, 'D'), order.items[3]); // D must be last
}

test "SystemRegistry - cyclic dependency detection" {
    const DummySystem = struct {
        pub fn update(self: *@This(), delta_time: f32) !void {
            _ = self;
            _ = delta_time;
        }

        pub fn deinit(self: *@This()) void {
            _ = self;
        }
    };

    var sys_a = DummySystem{};
    var sys_b = DummySystem{};
    var sys_c = DummySystem{};

    var registry = SystemRegistry.init(std.testing.allocator);
    defer registry.deinit();

    // Create a cycle: A -> B -> C -> A
    const id_a = try registry.register(System.init(&sys_a));
    const id_b = try registry.registerWithOptions(System.init(&sys_b), .{ .depends_on = &.{id_a} });
    const id_c = try registry.registerWithOptions(System.init(&sys_c), .{ .depends_on = &.{id_b} });

    // Try to make A depend on C (creating a cycle)
    // This should fail during topological sort, not during registration
    // We need to manually create the cycle for this test
    registry.nodes.items[0].dependencies = .{};
    try registry.nodes.items[0].dependencies.append(std.testing.allocator, id_c);
    registry.needs_resort = true;

    // Should detect cycle during updateAll
    try std.testing.expectError(error.CyclicDependency, registry.updateAll(0.016));
}

test "SystemRegistry - invalid dependency" {
    const DummySystem = struct {
        pub fn update(self: *@This(), delta_time: f32) !void {
            _ = self;
            _ = delta_time;
        }

        pub fn deinit(self: *@This()) void {
            _ = self;
        }
    };

    var sys_a = DummySystem{};

    var registry = SystemRegistry.init(std.testing.allocator);
    defer registry.deinit();

    // Try to register system with non-existent dependency
    const invalid_id: SystemId = 999;
    try std.testing.expectError(error.InvalidDependency, registry.registerWithOptions(System.init(&sys_a), .{ .depends_on = &.{invalid_id} }));
}

test "SystemRegistry - multiple updates maintain order" {
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

    var order: std.ArrayList(u8) = .{};
    defer order.deinit(std.testing.allocator);

    var sys_a = OrderTracker{ .order = &order, .allocator = std.testing.allocator, .marker = 'A' };
    var sys_b = OrderTracker{ .order = &order, .allocator = std.testing.allocator, .marker = 'B' };

    var registry = SystemRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const id_a = try registry.register(System.init(&sys_a));
    _ = try registry.registerWithOptions(System.init(&sys_b), .{ .depends_on = &.{id_a} });

    // Multiple updates should maintain order
    try registry.updateAll(0.016);
    try registry.updateAll(0.016);
    try registry.updateAll(0.016);

    try std.testing.expectEqual(@as(usize, 6), order.items.len);
    // Check pattern: A, B, A, B, A, B
    for (0..3) |i| {
        try std.testing.expectEqual(@as(u8, 'A'), order.items[i * 2]);
        try std.testing.expectEqual(@as(u8, 'B'), order.items[i * 2 + 1]);
    }
}
