//! ViewModel base type for managing observable lifecycles.
//!
//! The ViewModel provides lifecycle management for observable properties,
//! ensuring proper cleanup of subscriptions when the ViewModel is destroyed.
//!
//! ## Example
//! ```zig
//! const SettingsVM = struct {
//!     base: ViewModel,
//!     volume: ObservableFloat,
//!     muted: ObservableBool,
//!
//!     pub fn init(allocator: std.mem.Allocator) SettingsVM {
//!         return .{
//!             .base = ViewModel.init(allocator),
//!             .volume = ObservableFloat.init(allocator, 0.8),
//!             .muted = ObservableBool.init(allocator, false),
//!         };
//!     }
//!
//!     pub fn deinit(self: *SettingsVM) void {
//!         self.volume.deinit();
//!         self.muted.deinit();
//!         self.base.deinit();
//!     }
//! };
//! ```

const std = @import("std");
const observable = @import("observable.zig");
const Observable = observable.Observable;
const Handle = observable.Handle;

/// Handle for managing a binding's lifetime.
/// Bindings can be explicitly unbound or will be automatically cleaned up
/// when the ViewModel is deinitialized.
pub const BindingHandle = struct {
    /// Function to call for unbinding (type-erased)
    unbind_fn: *const fn (self: *BindingHandle) void,
    /// Data needed for unbinding (type-erased pointer)
    data: *anyopaque,
    /// Subscription handle
    handle: Handle,

    /// Explicitly unbind this binding
    pub fn unbind(self: *BindingHandle) void {
        self.unbind_fn(self);
    }
};

/// Base ViewModel providing lifecycle and subscription management.
///
/// Games create concrete ViewModels by embedding this struct and adding
/// Observable fields. The base provides:
/// - Binding registration for automatic cleanup
/// - Allocator access for dynamic operations
pub const ViewModel = struct {
    allocator: std.mem.Allocator,
    bindings: std.ArrayList(BindingHandle),

    /// Initialize the ViewModel base
    pub fn init(allocator: std.mem.Allocator) ViewModel {
        return .{
            .allocator = allocator,
            .bindings = .{},
        };
    }

    /// Clean up resources and unbind all registered bindings
    pub fn deinit(self: *ViewModel) void {
        // Unbind all registered bindings
        for (self.bindings.items) |*binding| {
            binding.unbind();
        }
        self.bindings.deinit(self.allocator);
    }

    /// Register a binding for automatic cleanup.
    /// The binding will be unbound when deinit is called.
    pub fn registerBinding(self: *ViewModel, handle: BindingHandle) !void {
        try self.bindings.append(self.allocator, handle);
    }

    /// Get the number of registered bindings
    pub fn getBindingCount(self: *const ViewModel) usize {
        return self.bindings.items.len;
    }

    /// Create a binding handle that will unsubscribe from an observable.
    /// This is a helper for creating type-erased binding handles.
    pub fn createUnsubscribeHandle(
        comptime T: type,
        obs: *Observable(T),
        subscription_handle: Handle,
    ) BindingHandle {
        const Unbinder = struct {
            fn unbind(binding: *BindingHandle) void {
                const o: *Observable(T) = @ptrCast(@alignCast(binding.data));
                _ = o.unsubscribe(binding.handle);
            }
        };

        return .{
            .unbind_fn = Unbinder.unbind,
            .data = @ptrCast(obs),
            .handle = subscription_handle,
        };
    }
};

/// Scoped subscription that automatically unsubscribes when it goes out of scope.
/// Useful for temporary subscriptions without ViewModel management.
pub fn ScopedSubscription(comptime T: type) type {
    return struct {
        const Self = @This();

        observable: *Observable(T),
        handle: Handle,

        /// Create a scoped subscription
        pub fn init(
            obs: *Observable(T),
            callback: Observable(T).ChangeCallback,
            user_data: ?*anyopaque,
        ) !Self {
            return .{
                .observable = obs,
                .handle = try obs.subscribe(callback, user_data),
            };
        }

        /// Unsubscribe when going out of scope
        pub fn deinit(self: *Self) void {
            _ = self.observable.unsubscribe(self.handle);
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "ViewModel: init and deinit" {
    const allocator = std.testing.allocator;

    var vm = ViewModel.init(allocator);
    defer vm.deinit();

    try std.testing.expectEqual(@as(usize, 0), vm.getBindingCount());
}

test "ViewModel: register binding" {
    const allocator = std.testing.allocator;

    var obs = Observable(i32).init(allocator, 0);
    defer obs.deinit();

    const sub_handle = try obs.subscribe(struct {
        fn callback(_: i32, _: i32, _: ?*anyopaque) void {}
    }.callback, null);

    var vm = ViewModel.init(allocator);

    const binding = ViewModel.createUnsubscribeHandle(i32, &obs, sub_handle);
    try vm.registerBinding(binding);

    try std.testing.expectEqual(@as(usize, 1), vm.getBindingCount());
    try std.testing.expectEqual(@as(usize, 1), obs.getSubscriptionCount());

    vm.deinit();

    // After vm deinit, observable should have no subscriptions
    try std.testing.expectEqual(@as(usize, 0), obs.getSubscriptionCount());
}

test "ViewModel: multiple bindings" {
    const allocator = std.testing.allocator;

    var obs1 = Observable(i32).init(allocator, 0);
    defer obs1.deinit();

    var obs2 = Observable(f32).init(allocator, 0.0);
    defer obs2.deinit();

    const h1 = try obs1.subscribe(struct {
        fn cb(_: i32, _: i32, _: ?*anyopaque) void {}
    }.cb, null);

    const h2 = try obs2.subscribe(struct {
        fn cb(_: f32, _: f32, _: ?*anyopaque) void {}
    }.cb, null);

    var vm = ViewModel.init(allocator);

    try vm.registerBinding(ViewModel.createUnsubscribeHandle(i32, &obs1, h1));
    try vm.registerBinding(ViewModel.createUnsubscribeHandle(f32, &obs2, h2));

    try std.testing.expectEqual(@as(usize, 2), vm.getBindingCount());

    vm.deinit();

    try std.testing.expectEqual(@as(usize, 0), obs1.getSubscriptionCount());
    try std.testing.expectEqual(@as(usize, 0), obs2.getSubscriptionCount());
}

test "ScopedSubscription: auto unsubscribe" {
    const allocator = std.testing.allocator;

    var obs = Observable(i32).init(allocator, 0);
    defer obs.deinit();

    {
        var scoped = try ScopedSubscription(i32).init(&obs, struct {
            fn cb(_: i32, _: i32, _: ?*anyopaque) void {}
        }.cb, null);
        defer scoped.deinit();

        try std.testing.expectEqual(@as(usize, 1), obs.getSubscriptionCount());
    }

    // After scope exits, subscription should be gone
    try std.testing.expectEqual(@as(usize, 0), obs.getSubscriptionCount());
}

test "BindingHandle: unbind manually" {
    const allocator = std.testing.allocator;

    var obs = Observable(i32).init(allocator, 0);
    defer obs.deinit();

    const sub_handle = try obs.subscribe(struct {
        fn callback(_: i32, _: i32, _: ?*anyopaque) void {}
    }.callback, null);

    var binding = ViewModel.createUnsubscribeHandle(i32, &obs, sub_handle);

    try std.testing.expectEqual(@as(usize, 1), obs.getSubscriptionCount());

    binding.unbind();

    try std.testing.expectEqual(@as(usize, 0), obs.getSubscriptionCount());
}
