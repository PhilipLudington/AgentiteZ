//! Computed properties that derive from other observables.
//!
//! A Computed value automatically re-evaluates when any of its dependencies change.
//! This enables reactive patterns where derived values stay in sync with source data.
//!
//! ## Example
//! ```zig
//! var health = Observable(f32).init(allocator, 100);
//! var max_health = Observable(f32).init(allocator, 100);
//!
//! // Computed health percentage
//! var health_percent = try Computed(f32).init(allocator, struct {
//!     fn compute(ctx: *anyopaque) f32 {
//!         const self: *GameState = @ptrCast(@alignCast(ctx));
//!         return self.health.get() / self.max_health.get();
//!     }
//! }.compute, &game_state);
//!
//! try health_percent.dependOn(f32, &health);
//! try health_percent.dependOn(f32, &max_health);
//!
//! health.set(50); // health_percent automatically recomputes to 0.5
//! ```

const std = @import("std");
const observable = @import("observable.zig");
const Observable = observable.Observable;
const Handle = observable.Handle;

/// Computed property that derives its value from other observables.
/// Re-evaluates when any dependency changes and notifies its own subscribers.
pub fn Computed(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Function that computes the derived value
        pub const ComputeFn = *const fn (context: *anyopaque) T;

        /// Change callback (same signature as Observable)
        pub const ChangeCallback = Observable(T).ChangeCallback;

        /// Internal record of a dependency subscription
        const DependencyHandle = struct {
            /// Function to call for unsubscribing (type-erased)
            unsubscribe_fn: *const fn (handle: Handle, data: *anyopaque) void,
            /// The subscription handle
            handle: Handle,
            /// Pointer to the dependency observable (type-erased)
            data: *anyopaque,
        };

        /// The underlying observable that stores the computed value
        inner: Observable(T),
        /// Function to compute the value
        compute_fn: ComputeFn,
        /// Context passed to compute function
        context: *anyopaque,
        /// Handles for dependency subscriptions (for cleanup)
        dependency_handles: std.ArrayList(DependencyHandle),
        /// Allocator for managing dependency list
        allocator: std.mem.Allocator,
        /// Flag to prevent recursive recomputation
        is_computing: bool,

        /// Initialize a computed property
        pub fn init(
            allocator: std.mem.Allocator,
            compute_fn: ComputeFn,
            context: *anyopaque,
        ) Self {
            const initial = compute_fn(context);
            return .{
                .inner = Observable(T).init(allocator, initial),
                .compute_fn = compute_fn,
                .context = context,
                .dependency_handles = .{},
                .allocator = allocator,
                .is_computing = false,
            };
        }

        /// Clean up resources and unsubscribe from all dependencies
        pub fn deinit(self: *Self) void {
            // Unsubscribe from all dependencies
            for (self.dependency_handles.items) |dep| {
                dep.unsubscribe_fn(dep.handle, dep.data);
            }
            self.dependency_handles.deinit(self.allocator);
            self.inner.deinit();
        }

        /// Get the current computed value
        pub fn get(self: *const Self) T {
            return self.inner.get();
        }

        /// Register a dependency on another observable.
        /// When the dependency changes, this computed property will recompute.
        pub fn dependOn(self: *Self, comptime U: type, dep: *Observable(U)) !void {
            // Subscribe to the dependency
            const handle = try dep.subscribe(
                struct {
                    fn onChange(_: U, _: U, user_data: ?*anyopaque) void {
                        const computed: *Self = @ptrCast(@alignCast(user_data.?));
                        computed.recompute();
                    }
                }.onChange,
                self,
            );

            // Store the handle for cleanup
            try self.dependency_handles.append(self.allocator, .{
                .unsubscribe_fn = struct {
                    fn unsub(h: Handle, data: *anyopaque) void {
                        const d: *Observable(U) = @ptrCast(@alignCast(data));
                        _ = d.unsubscribe(h);
                    }
                }.unsub,
                .handle = handle,
                .data = @ptrCast(dep),
            });
        }

        /// Subscribe to computed value changes
        pub fn subscribe(
            self: *Self,
            callback: ChangeCallback,
            user_data: ?*anyopaque,
        ) !Handle {
            return self.inner.subscribe(callback, user_data);
        }

        /// Unsubscribe from computed value changes
        pub fn unsubscribe(self: *Self, handle: Handle) bool {
            return self.inner.unsubscribe(handle);
        }

        /// Get the number of subscribers
        pub fn getSubscriptionCount(self: *const Self) usize {
            return self.inner.getSubscriptionCount();
        }

        /// Get the number of dependencies
        pub fn getDependencyCount(self: *const Self) usize {
            return self.dependency_handles.items.len;
        }

        /// Force recomputation of the value
        pub fn recompute(self: *Self) void {
            // Prevent recursive recomputation
            if (self.is_computing) return;

            self.is_computing = true;
            defer self.is_computing = false;

            const new_value = self.compute_fn(self.context);
            self.inner.set(new_value);
        }
    };
}

// Pre-instantiated common computed types
pub const ComputedFloat = Computed(f32);
pub const ComputedBool = Computed(bool);
pub const ComputedInt = Computed(i32);

// ============================================================================
// Tests
// ============================================================================

test "Computed: init computes initial value" {
    const allocator = std.testing.allocator;

    const ctx = struct {
        var value: i32 = 42;

        fn compute(_: *anyopaque) i32 {
            return value;
        }
    };

    var computed = Computed(i32).init(allocator, ctx.compute, undefined);
    defer computed.deinit();

    try std.testing.expectEqual(@as(i32, 42), computed.get());
}

test "Computed: recompute updates value" {
    const allocator = std.testing.allocator;

    const ctx = struct {
        var value: i32 = 10;

        fn compute(_: *anyopaque) i32 {
            return value * 2;
        }
    };

    var computed = Computed(i32).init(allocator, ctx.compute, undefined);
    defer computed.deinit();

    try std.testing.expectEqual(@as(i32, 20), computed.get());

    ctx.value = 15;
    computed.recompute();

    try std.testing.expectEqual(@as(i32, 30), computed.get());
}

test "Computed: dependOn triggers recompute" {
    const allocator = std.testing.allocator;

    var source = Observable(i32).init(allocator, 5);
    defer source.deinit();

    // Create computed that depends on source
    const ComputeContext = struct {
        source_ptr: *Observable(i32),

        fn compute(ctx_ptr: *anyopaque) i32 {
            const self: *@This() = @ptrCast(@alignCast(ctx_ptr));
            return self.source_ptr.get() * 10;
        }
    };

    var ctx = ComputeContext{ .source_ptr = &source };
    var computed = Computed(i32).init(allocator, ComputeContext.compute, &ctx);
    defer computed.deinit();

    try computed.dependOn(i32, &source);

    try std.testing.expectEqual(@as(i32, 50), computed.get());

    // Changing source should trigger recompute
    source.set(7);

    try std.testing.expectEqual(@as(i32, 70), computed.get());
}

test "Computed: multiple dependencies" {
    const allocator = std.testing.allocator;

    var a = Observable(f32).init(allocator, 10.0);
    defer a.deinit();

    var b = Observable(f32).init(allocator, 20.0);
    defer b.deinit();

    const ComputeContext = struct {
        a_ptr: *Observable(f32),
        b_ptr: *Observable(f32),

        fn compute(ctx_ptr: *anyopaque) f32 {
            const self: *@This() = @ptrCast(@alignCast(ctx_ptr));
            return self.a_ptr.get() + self.b_ptr.get();
        }
    };

    var ctx = ComputeContext{ .a_ptr = &a, .b_ptr = &b };
    var computed = Computed(f32).init(allocator, ComputeContext.compute, &ctx);
    defer computed.deinit();

    try computed.dependOn(f32, &a);
    try computed.dependOn(f32, &b);

    try std.testing.expectEqual(@as(usize, 2), computed.getDependencyCount());
    try std.testing.expectApproxEqAbs(@as(f32, 30.0), computed.get(), 0.001);

    a.set(15.0);
    try std.testing.expectApproxEqAbs(@as(f32, 35.0), computed.get(), 0.001);

    b.set(25.0);
    try std.testing.expectApproxEqAbs(@as(f32, 40.0), computed.get(), 0.001);
}

test "Computed: subscribers notified on recompute" {
    const allocator = std.testing.allocator;

    var source = Observable(i32).init(allocator, 1);
    defer source.deinit();

    const ComputeContext = struct {
        source_ptr: *Observable(i32),

        fn compute(ctx_ptr: *anyopaque) i32 {
            const self: *@This() = @ptrCast(@alignCast(ctx_ptr));
            return self.source_ptr.get() * 2;
        }
    };

    var ctx = ComputeContext{ .source_ptr = &source };
    var computed = Computed(i32).init(allocator, ComputeContext.compute, &ctx);
    defer computed.deinit();

    try computed.dependOn(i32, &source);

    const Tracker = struct {
        var old_val: i32 = 0;
        var new_val: i32 = 0;
        var call_count: u32 = 0;

        fn callback(old: i32, new: i32, _: ?*anyopaque) void {
            old_val = old;
            new_val = new;
            call_count += 1;
        }
    };
    Tracker.old_val = 0;
    Tracker.new_val = 0;
    Tracker.call_count = 0;

    _ = try computed.subscribe(Tracker.callback, null);

    source.set(5);

    try std.testing.expectEqual(@as(u32, 1), Tracker.call_count);
    try std.testing.expectEqual(@as(i32, 2), Tracker.old_val);
    try std.testing.expectEqual(@as(i32, 10), Tracker.new_val);
}

test "Computed: unsubscribe works" {
    const allocator = std.testing.allocator;

    const ctx = struct {
        fn compute(_: *anyopaque) i32 {
            return 42;
        }
    };

    var computed = Computed(i32).init(allocator, ctx.compute, undefined);
    defer computed.deinit();

    const Counter = struct {
        var count: u32 = 0;
        fn callback(_: i32, _: i32, _: ?*anyopaque) void {
            count += 1;
        }
    };
    Counter.count = 0;

    const handle = try computed.subscribe(Counter.callback, null);
    computed.recompute();
    // Value didn't change, so no notification
    try std.testing.expectEqual(@as(u32, 0), Counter.count);

    const removed = computed.unsubscribe(handle);
    try std.testing.expect(removed);
    try std.testing.expectEqual(@as(usize, 0), computed.getSubscriptionCount());
}

test "Computed: prevents recursive recomputation" {
    const allocator = std.testing.allocator;

    const ctx = struct {
        var compute_count: u32 = 0;

        fn compute(_: *anyopaque) i32 {
            compute_count += 1;
            return 42;
        }
    };
    ctx.compute_count = 0;

    var computed = Computed(i32).init(allocator, ctx.compute, undefined);
    defer computed.deinit();

    // Initial computation
    try std.testing.expectEqual(@as(u32, 1), ctx.compute_count);

    // Simulate recursive recomputation attempt
    computed.is_computing = true;
    computed.recompute();
    computed.is_computing = false;

    // Should not have recomputed due to guard
    try std.testing.expectEqual(@as(u32, 1), ctx.compute_count);

    // Normal recompute should work
    computed.recompute();
    try std.testing.expectEqual(@as(u32, 2), ctx.compute_count);
}

test "Computed: deinit unsubscribes from dependencies" {
    const allocator = std.testing.allocator;

    var source = Observable(i32).init(allocator, 1);
    defer source.deinit();

    try std.testing.expectEqual(@as(usize, 0), source.getSubscriptionCount());

    {
        const ComputeContext = struct {
            source_ptr: *Observable(i32),

            fn compute(ctx_ptr: *anyopaque) i32 {
                const self: *@This() = @ptrCast(@alignCast(ctx_ptr));
                return self.source_ptr.get();
            }
        };

        var ctx = ComputeContext{ .source_ptr = &source };
        var computed = Computed(i32).init(allocator, ComputeContext.compute, &ctx);

        try computed.dependOn(i32, &source);
        try std.testing.expectEqual(@as(usize, 1), source.getSubscriptionCount());

        computed.deinit();
    }

    // After computed deinit, source should have no subscriptions
    try std.testing.expectEqual(@as(usize, 0), source.getSubscriptionCount());
}
