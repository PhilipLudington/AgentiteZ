//! Observable property with change notification support.
//!
//! Observable wraps a value and notifies subscribers when it changes.
//! This enables reactive UI patterns where widgets automatically update
//! when underlying data changes.
//!
//! ## Example
//! ```zig
//! var volume = Observable(f32).init(allocator, 0.8);
//! defer volume.deinit();
//!
//! // Subscribe to changes
//! const handle = try volume.subscribe(struct {
//!     fn onChange(old: f32, new: f32, _: ?*anyopaque) void {
//!         std.debug.print("Volume changed: {d} -> {d}\n", .{ old, new });
//!     }
//! }.onChange, null);
//!
//! volume.set(0.5); // Triggers callback
//! _ = volume.unsubscribe(handle);
//! ```

const std = @import("std");

/// Subscription handle for managing subscriptions
pub const Handle = u32;

/// Generic observable property that notifies subscribers when its value changes.
/// Uses comptime type parameter for zero-cost abstraction.
pub fn Observable(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Subscription callback receives old and new values
        pub const ChangeCallback = *const fn (
            old_value: T,
            new_value: T,
            user_data: ?*anyopaque,
        ) void;

        /// Internal subscription record
        const Subscription = struct {
            id: Handle,
            callback: ChangeCallback,
            user_data: ?*anyopaque,
        };

        value: T,
        subscriptions: std.ArrayList(Subscription),
        next_handle: Handle,
        allocator: std.mem.Allocator,

        // Batching support - coalesce multiple changes into single notification
        batch_depth: u32,
        pending_old_value: ?T,

        /// Initialize an observable with an initial value
        pub fn init(allocator: std.mem.Allocator, initial: T) Self {
            return .{
                .value = initial,
                .subscriptions = .{},
                .next_handle = 1,
                .allocator = allocator,
                .batch_depth = 0,
                .pending_old_value = null,
            };
        }

        /// Clean up resources
        pub fn deinit(self: *Self) void {
            self.subscriptions.deinit(self.allocator);
        }

        /// Get the current value (read-only access)
        pub fn get(self: *const Self) T {
            return self.value;
        }

        /// Set the value and notify subscribers if it changed
        pub fn set(self: *Self, new_value: T) void {
            if (self.eql(self.value, new_value)) return;

            const old_value = self.value;
            self.value = new_value;

            if (self.batch_depth > 0) {
                // Capture first old value for batched notification
                if (self.pending_old_value == null) {
                    self.pending_old_value = old_value;
                }
            } else {
                self.notifySubscribers(old_value, new_value);
            }
        }

        /// Subscribe to value changes
        /// Returns a handle that can be used to unsubscribe later
        pub fn subscribe(
            self: *Self,
            callback: ChangeCallback,
            user_data: ?*anyopaque,
        ) !Handle {
            const handle = self.next_handle;
            self.next_handle += 1;

            try self.subscriptions.append(self.allocator, .{
                .id = handle,
                .callback = callback,
                .user_data = user_data,
            });

            return handle;
        }

        /// Unsubscribe by handle
        /// Returns true if the subscription was found and removed
        pub fn unsubscribe(self: *Self, handle: Handle) bool {
            for (self.subscriptions.items, 0..) |sub, i| {
                if (sub.id == handle) {
                    _ = self.subscriptions.swapRemove(i);
                    return true;
                }
            }
            return false;
        }

        /// Get the number of active subscriptions
        pub fn getSubscriptionCount(self: *const Self) usize {
            return self.subscriptions.items.len;
        }

        /// Begin a batch update - defers notifications until endBatch is called.
        /// Batching allows multiple changes to be coalesced into a single notification.
        /// Batches can be nested; notifications only fire when the outermost batch ends.
        pub fn beginBatch(self: *Self) void {
            self.batch_depth += 1;
        }

        /// End a batch update - fires notification if value changed during batch.
        /// The notification uses the first old value and the final new value.
        pub fn endBatch(self: *Self) void {
            std.debug.assert(self.batch_depth > 0);
            self.batch_depth -= 1;

            if (self.batch_depth == 0) {
                if (self.pending_old_value) |old| {
                    self.pending_old_value = null;
                    self.notifySubscribers(old, self.value);
                }
            }
        }

        /// Check if currently in a batch update
        pub fn isInBatch(self: *const Self) bool {
            return self.batch_depth > 0;
        }

        /// Notify all subscribers of a value change
        fn notifySubscribers(self: *Self, old_value: T, new_value: T) void {
            for (self.subscriptions.items) |sub| {
                sub.callback(old_value, new_value, sub.user_data);
            }
        }

        /// Type-specific equality check
        fn eql(self: *const Self, a: T, b: T) bool {
            _ = self;
            const info = @typeInfo(T);
            return switch (info) {
                .float => @abs(a - b) < 0.0001,
                .int, .comptime_int, .bool, .@"enum" => a == b,
                .pointer => |ptr| if (ptr.size == .Slice)
                    std.mem.eql(ptr.child, a, b)
                else
                    a == b,
                .@"struct" => if (@hasDecl(T, "eql"))
                    a.eql(b)
                else
                    std.meta.eql(a, b),
                .optional => blk: {
                    if (a == null and b == null) break :blk true;
                    if (a == null or b == null) break :blk false;
                    // Recursively compare unwrapped values
                    const inner_info = @typeInfo(@typeInfo(T).optional.child);
                    _ = inner_info;
                    break :blk std.meta.eql(a, b);
                },
                else => std.meta.eql(a, b),
            };
        }
    };
}

// Pre-instantiated common observable types
pub const ObservableFloat = Observable(f32);
pub const ObservableBool = Observable(bool);
pub const ObservableInt = Observable(i32);
pub const ObservableUsize = Observable(usize);

// ============================================================================
// Tests
// ============================================================================

test "Observable: init and get" {
    const allocator = std.testing.allocator;

    var obs = Observable(f32).init(allocator, 42.0);
    defer obs.deinit();

    try std.testing.expectEqual(@as(f32, 42.0), obs.get());
}

test "Observable: set updates value" {
    const allocator = std.testing.allocator;

    var obs = Observable(i32).init(allocator, 10);
    defer obs.deinit();

    obs.set(20);
    try std.testing.expectEqual(@as(i32, 20), obs.get());
}

test "Observable: set with same value does not notify" {
    const allocator = std.testing.allocator;

    const Counter = struct {
        var count: u32 = 0;

        fn callback(_: i32, _: i32, _: ?*anyopaque) void {
            count += 1;
        }
    };
    Counter.count = 0;

    var obs = Observable(i32).init(allocator, 10);
    defer obs.deinit();

    _ = try obs.subscribe(Counter.callback, null);

    obs.set(10); // Same value - should not notify
    try std.testing.expectEqual(@as(u32, 0), Counter.count);

    obs.set(20); // Different value - should notify
    try std.testing.expectEqual(@as(u32, 1), Counter.count);
}

test "Observable: subscribe and receive notifications" {
    const allocator = std.testing.allocator;

    const Tracker = struct {
        var old_val: f32 = 0;
        var new_val: f32 = 0;
        var call_count: u32 = 0;

        fn callback(old: f32, new: f32, _: ?*anyopaque) void {
            old_val = old;
            new_val = new;
            call_count += 1;
        }
    };
    Tracker.old_val = 0;
    Tracker.new_val = 0;
    Tracker.call_count = 0;

    var obs = Observable(f32).init(allocator, 1.0);
    defer obs.deinit();

    _ = try obs.subscribe(Tracker.callback, null);

    obs.set(2.0);
    try std.testing.expectEqual(@as(f32, 1.0), Tracker.old_val);
    try std.testing.expectEqual(@as(f32, 2.0), Tracker.new_val);
    try std.testing.expectEqual(@as(u32, 1), Tracker.call_count);

    obs.set(3.0);
    try std.testing.expectEqual(@as(f32, 2.0), Tracker.old_val);
    try std.testing.expectEqual(@as(f32, 3.0), Tracker.new_val);
    try std.testing.expectEqual(@as(u32, 2), Tracker.call_count);
}

test "Observable: unsubscribe stops notifications" {
    const allocator = std.testing.allocator;

    const Counter = struct {
        var count: u32 = 0;

        fn callback(_: i32, _: i32, _: ?*anyopaque) void {
            count += 1;
        }
    };
    Counter.count = 0;

    var obs = Observable(i32).init(allocator, 0);
    defer obs.deinit();

    const handle = try obs.subscribe(Counter.callback, null);

    obs.set(1);
    try std.testing.expectEqual(@as(u32, 1), Counter.count);

    const removed = obs.unsubscribe(handle);
    try std.testing.expect(removed);

    obs.set(2);
    try std.testing.expectEqual(@as(u32, 1), Counter.count); // No additional call
}

test "Observable: unsubscribe invalid handle returns false" {
    const allocator = std.testing.allocator;

    var obs = Observable(i32).init(allocator, 0);
    defer obs.deinit();

    const removed = obs.unsubscribe(999);
    try std.testing.expect(!removed);
}

test "Observable: multiple subscribers" {
    const allocator = std.testing.allocator;

    const Counter1 = struct {
        var count: u32 = 0;
        fn callback(_: i32, _: i32, _: ?*anyopaque) void {
            count += 1;
        }
    };
    const Counter2 = struct {
        var count: u32 = 0;
        fn callback(_: i32, _: i32, _: ?*anyopaque) void {
            count += 1;
        }
    };
    Counter1.count = 0;
    Counter2.count = 0;

    var obs = Observable(i32).init(allocator, 0);
    defer obs.deinit();

    _ = try obs.subscribe(Counter1.callback, null);
    _ = try obs.subscribe(Counter2.callback, null);

    try std.testing.expectEqual(@as(usize, 2), obs.getSubscriptionCount());

    obs.set(1);
    try std.testing.expectEqual(@as(u32, 1), Counter1.count);
    try std.testing.expectEqual(@as(u32, 1), Counter2.count);
}

test "Observable: batch coalesces notifications" {
    const allocator = std.testing.allocator;

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

    var obs = Observable(i32).init(allocator, 0);
    defer obs.deinit();

    _ = try obs.subscribe(Tracker.callback, null);

    obs.beginBatch();
    try std.testing.expect(obs.isInBatch());

    obs.set(1);
    obs.set(2);
    obs.set(3);

    // No notifications yet
    try std.testing.expectEqual(@as(u32, 0), Tracker.call_count);

    obs.endBatch();
    try std.testing.expect(!obs.isInBatch());

    // Single notification with first old value and final new value
    try std.testing.expectEqual(@as(u32, 1), Tracker.call_count);
    try std.testing.expectEqual(@as(i32, 0), Tracker.old_val);
    try std.testing.expectEqual(@as(i32, 3), Tracker.new_val);
}

test "Observable: nested batches" {
    const allocator = std.testing.allocator;

    const Counter = struct {
        var count: u32 = 0;
        fn callback(_: i32, _: i32, _: ?*anyopaque) void {
            count += 1;
        }
    };
    Counter.count = 0;

    var obs = Observable(i32).init(allocator, 0);
    defer obs.deinit();

    _ = try obs.subscribe(Counter.callback, null);

    obs.beginBatch();
    obs.beginBatch();
    obs.set(1);
    obs.endBatch();

    // Still in outer batch - no notification
    try std.testing.expectEqual(@as(u32, 0), Counter.count);

    obs.endBatch();

    // Now notification fires
    try std.testing.expectEqual(@as(u32, 1), Counter.count);
}

test "Observable: batch with no changes does not notify" {
    const allocator = std.testing.allocator;

    const Counter = struct {
        var count: u32 = 0;
        fn callback(_: i32, _: i32, _: ?*anyopaque) void {
            count += 1;
        }
    };
    Counter.count = 0;

    var obs = Observable(i32).init(allocator, 5);
    defer obs.deinit();

    _ = try obs.subscribe(Counter.callback, null);

    obs.beginBatch();
    // No changes
    obs.endBatch();

    try std.testing.expectEqual(@as(u32, 0), Counter.count);
}

test "Observable: float equality uses epsilon" {
    const allocator = std.testing.allocator;

    const Counter = struct {
        var count: u32 = 0;
        fn callback(_: f32, _: f32, _: ?*anyopaque) void {
            count += 1;
        }
    };
    Counter.count = 0;

    var obs = Observable(f32).init(allocator, 1.0);
    defer obs.deinit();

    _ = try obs.subscribe(Counter.callback, null);

    // Very small difference - should be considered equal
    obs.set(1.00001);
    try std.testing.expectEqual(@as(u32, 0), Counter.count);

    // Large difference - should trigger notification
    obs.set(2.0);
    try std.testing.expectEqual(@as(u32, 1), Counter.count);
}

test "Observable: bool type" {
    const allocator = std.testing.allocator;

    var obs = ObservableBool.init(allocator, false);
    defer obs.deinit();

    try std.testing.expect(!obs.get());

    obs.set(true);
    try std.testing.expect(obs.get());

    obs.set(false);
    try std.testing.expect(!obs.get());
}

test "Observable: user_data passed to callback" {
    const allocator = std.testing.allocator;

    const Context = struct {
        multiplier: i32,
        result: i32 = 0,
    };

    var ctx = Context{ .multiplier = 10 };

    var obs = Observable(i32).init(allocator, 0);
    defer obs.deinit();

    _ = try obs.subscribe(struct {
        fn callback(_: i32, new: i32, user_data: ?*anyopaque) void {
            const c: *Context = @ptrCast(@alignCast(user_data.?));
            c.result = new * c.multiplier;
        }
    }.callback, &ctx);

    obs.set(5);
    try std.testing.expectEqual(@as(i32, 50), ctx.result);
}
