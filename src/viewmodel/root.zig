//! ViewModel Pattern - MVVM data binding for AgentiteZ UI.
//!
//! This module provides reactive data binding between application state and UI widgets:
//! - **Observable** - Wrapper for values that notify subscribers when changed
//! - **Computed** - Derived values that auto-update when dependencies change
//! - **ViewModel** - Base type for managing observable lifecycles
//! - **Binding** - Helper functions for two-way widget binding
//!
//! ## Quick Start
//!
//! ```zig
//! const vm = @import("viewmodel");
//!
//! // Define a ViewModel with observable properties
//! const SettingsVM = struct {
//!     base: vm.ViewModel,
//!     volume: vm.ObservableFloat,
//!     muted: vm.ObservableBool,
//!
//!     pub fn init(allocator: std.mem.Allocator) SettingsVM {
//!         return .{
//!             .base = vm.ViewModel.init(allocator),
//!             .volume = vm.ObservableFloat.init(allocator, 0.8),
//!             .muted = vm.ObservableBool.init(allocator, false),
//!         };
//!     }
//!
//!     pub fn deinit(self: *SettingsVM) void {
//!         self.volume.deinit();
//!         self.muted.deinit();
//!         self.base.deinit();
//!     }
//! };
//!
//! // In render loop - two-way binding
//! fn renderSettings(ctx: *ui.Context, settings: *SettingsVM) void {
//!     vm.Binding.sliderFloatAuto(ctx, "Volume", 300, &settings.volume, 0, 1);
//!     vm.Binding.checkboxBoolAuto(ctx, "Mute", &settings.muted);
//! }
//!
//! // Subscribe to changes for side effects
//! _ = try settings.volume.subscribe(struct {
//!     fn onVolumeChanged(old: f32, new: f32, _: ?*anyopaque) void {
//!         audio.setMasterVolume(new);
//!         _ = old;
//!     }
//! }.onVolumeChanged, null);
//! ```
//!
//! ## Key Concepts
//!
//! ### Observable Properties
//! Observable wraps a value and notifies subscribers when it changes:
//! ```zig
//! var health = ObservableFloat.init(allocator, 100.0);
//! health.set(50.0); // Notifies all subscribers
//! ```
//!
//! ### Computed Properties
//! Computed values derive from other observables and auto-update:
//! ```zig
//! var health_percent = Computed(f32).init(allocator, computePercent, &state);
//! try health_percent.dependOn(f32, &health);
//! try health_percent.dependOn(f32, &max_health);
//! // Now health_percent.get() auto-updates when health or max_health changes
//! ```
//!
//! ### Batching Updates
//! Multiple changes can be batched into a single notification:
//! ```zig
//! obs.beginBatch();
//! obs.set(1);
//! obs.set(2);
//! obs.set(3);
//! obs.endBatch(); // Single notification: old=original, new=3
//! ```

const std = @import("std");

// Core types
pub const observable = @import("observable.zig");
pub const computed = @import("computed.zig");
pub const viewmodel = @import("viewmodel.zig");
pub const binding = @import("binding.zig");

// Re-export main types at root level for convenience
pub const Observable = observable.Observable;
pub const Handle = observable.Handle;

pub const Computed = computed.Computed;

pub const ViewModel = viewmodel.ViewModel;
pub const BindingHandle = viewmodel.BindingHandle;
pub const ScopedSubscription = viewmodel.ScopedSubscription;

pub const Binding = binding.Binding;

// Pre-instantiated common observable types
pub const ObservableFloat = observable.ObservableFloat;
pub const ObservableBool = observable.ObservableBool;
pub const ObservableInt = observable.ObservableInt;
pub const ObservableUsize = observable.ObservableUsize;
pub const ObservableString = Observable([]const u8);

// Pre-instantiated common computed types
pub const ComputedFloat = computed.ComputedFloat;
pub const ComputedBool = computed.ComputedBool;
pub const ComputedInt = computed.ComputedInt;

// ============================================================================
// Tests
// ============================================================================

test "viewmodel module compiles" {
    // Import all submodules to verify they compile
    _ = observable;
    _ = computed;
    _ = viewmodel;
    _ = binding;
}

test "viewmodel: integration test" {
    const allocator = std.testing.allocator;

    // Create observables
    var health = ObservableFloat.init(allocator, 100.0);
    defer health.deinit();

    var max_health = ObservableFloat.init(allocator, 100.0);
    defer max_health.deinit();

    // Track changes
    const Tracker = struct {
        var last_health: f32 = 0;

        fn onHealthChange(_: f32, new: f32, _: ?*anyopaque) void {
            last_health = new;
        }
    };

    _ = try health.subscribe(Tracker.onHealthChange, null);

    // Modify and verify
    health.set(75.0);
    try std.testing.expectApproxEqAbs(@as(f32, 75.0), Tracker.last_health, 0.001);

    health.set(50.0);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), Tracker.last_health, 0.001);
}

test "viewmodel: computed with dependencies" {
    const allocator = std.testing.allocator;

    var numerator = ObservableFloat.init(allocator, 50.0);
    defer numerator.deinit();

    var denominator = ObservableFloat.init(allocator, 100.0);
    defer denominator.deinit();

    const ComputeContext = struct {
        num: *ObservableFloat,
        den: *ObservableFloat,

        fn compute(ctx_ptr: *anyopaque) f32 {
            const self: *@This() = @ptrCast(@alignCast(ctx_ptr));
            const d = self.den.get();
            if (d <= 0) return 0;
            return self.num.get() / d;
        }
    };

    var ctx = ComputeContext{ .num = &numerator, .den = &denominator };
    var ratio = Computed(f32).init(allocator, ComputeContext.compute, &ctx);
    defer ratio.deinit();

    try ratio.dependOn(f32, &numerator);
    try ratio.dependOn(f32, &denominator);

    // Initial value
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), ratio.get(), 0.001);

    // Change numerator
    numerator.set(75.0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), ratio.get(), 0.001);

    // Change denominator
    denominator.set(50.0);
    try std.testing.expectApproxEqAbs(@as(f32, 1.5), ratio.get(), 0.001);
}

test "viewmodel: ViewModel lifecycle management" {
    const allocator = std.testing.allocator;

    var obs = ObservableInt.init(allocator, 0);
    defer obs.deinit();

    // Create ViewModel and register a subscription
    var base = ViewModel.init(allocator);

    const handle = try obs.subscribe(struct {
        fn cb(_: i32, _: i32, _: ?*anyopaque) void {}
    }.cb, null);

    try base.registerBinding(ViewModel.createUnsubscribeHandle(i32, &obs, handle));

    try std.testing.expectEqual(@as(usize, 1), obs.getSubscriptionCount());

    // Deinit ViewModel - should clean up subscription
    base.deinit();

    try std.testing.expectEqual(@as(usize, 0), obs.getSubscriptionCount());
}
