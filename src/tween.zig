//! Tween System - UI Animation with Easing Functions
//!
//! A flexible tweening system for animating UI properties with smooth
//! interpolation and various easing functions.
//!
//! Features:
//! - 30+ easing functions (linear, ease-in/out, bounce, elastic, etc.)
//! - Property animation for floats, Vec2, and colors
//! - Sequence and parallel composition
//! - Callbacks on completion
//! - Yoyo (ping-pong) mode
//! - Repeat support
//!
//! Usage:
//! ```zig
//! var manager = TweenManager.init(allocator);
//! defer manager.deinit();
//!
//! // Simple float tween
//! const id = try manager.tweenFloat(&my_alpha, 0.0, 1.0, 0.5, .ease_out_quad, .{
//!     .on_complete = myCallback,
//! });
//!
//! // Update each frame
//! manager.update(delta_time);
//! ```

const std = @import("std");
const types = @import("ui/types.zig");

pub const Vec2 = types.Vec2;
pub const Color = types.Color;

// ============================================================================
// Easing Functions
// ============================================================================

/// Easing function type
pub const EasingFn = *const fn (t: f32) f32;

/// Standard easing functions
pub const Easing = enum {
    // Linear
    linear,

    // Quadratic
    ease_in_quad,
    ease_out_quad,
    ease_in_out_quad,

    // Cubic
    ease_in_cubic,
    ease_out_cubic,
    ease_in_out_cubic,

    // Quartic
    ease_in_quart,
    ease_out_quart,
    ease_in_out_quart,

    // Quintic
    ease_in_quint,
    ease_out_quint,
    ease_in_out_quint,

    // Sinusoidal
    ease_in_sine,
    ease_out_sine,
    ease_in_out_sine,

    // Exponential
    ease_in_expo,
    ease_out_expo,
    ease_in_out_expo,

    // Circular
    ease_in_circ,
    ease_out_circ,
    ease_in_out_circ,

    // Back (overshoot)
    ease_in_back,
    ease_out_back,
    ease_in_out_back,

    // Elastic
    ease_in_elastic,
    ease_out_elastic,
    ease_in_out_elastic,

    // Bounce
    ease_in_bounce,
    ease_out_bounce,
    ease_in_out_bounce,

    /// Get the easing function for this type
    pub fn getFunction(self: Easing) EasingFn {
        return switch (self) {
            .linear => linear,
            .ease_in_quad => easeInQuad,
            .ease_out_quad => easeOutQuad,
            .ease_in_out_quad => easeInOutQuad,
            .ease_in_cubic => easeInCubic,
            .ease_out_cubic => easeOutCubic,
            .ease_in_out_cubic => easeInOutCubic,
            .ease_in_quart => easeInQuart,
            .ease_out_quart => easeOutQuart,
            .ease_in_out_quart => easeInOutQuart,
            .ease_in_quint => easeInQuint,
            .ease_out_quint => easeOutQuint,
            .ease_in_out_quint => easeInOutQuint,
            .ease_in_sine => easeInSine,
            .ease_out_sine => easeOutSine,
            .ease_in_out_sine => easeInOutSine,
            .ease_in_expo => easeInExpo,
            .ease_out_expo => easeOutExpo,
            .ease_in_out_expo => easeInOutExpo,
            .ease_in_circ => easeInCirc,
            .ease_out_circ => easeOutCirc,
            .ease_in_out_circ => easeInOutCirc,
            .ease_in_back => easeInBack,
            .ease_out_back => easeOutBack,
            .ease_in_out_back => easeInOutBack,
            .ease_in_elastic => easeInElastic,
            .ease_out_elastic => easeOutElastic,
            .ease_in_out_elastic => easeInOutElastic,
            .ease_in_bounce => easeInBounce,
            .ease_out_bounce => easeOutBounce,
            .ease_in_out_bounce => easeInOutBounce,
        };
    }

    /// Apply the easing function to a value t in [0, 1]
    pub fn apply(self: Easing, t: f32) f32 {
        return self.getFunction()(t);
    }
};

// ============================================================================
// Easing Function Implementations
// ============================================================================

const PI = std.math.pi;

/// Linear interpolation (no easing)
pub fn linear(t: f32) f32 {
    return t;
}

// Quadratic
pub fn easeInQuad(t: f32) f32 {
    return t * t;
}

pub fn easeOutQuad(t: f32) f32 {
    return 1.0 - (1.0 - t) * (1.0 - t);
}

pub fn easeInOutQuad(t: f32) f32 {
    if (t < 0.5) {
        return 2.0 * t * t;
    } else {
        return 1.0 - std.math.pow(f32, -2.0 * t + 2.0, 2) / 2.0;
    }
}

// Cubic
pub fn easeInCubic(t: f32) f32 {
    return t * t * t;
}

pub fn easeOutCubic(t: f32) f32 {
    return 1.0 - std.math.pow(f32, 1.0 - t, 3);
}

pub fn easeInOutCubic(t: f32) f32 {
    if (t < 0.5) {
        return 4.0 * t * t * t;
    } else {
        return 1.0 - std.math.pow(f32, -2.0 * t + 2.0, 3) / 2.0;
    }
}

// Quartic
pub fn easeInQuart(t: f32) f32 {
    return t * t * t * t;
}

pub fn easeOutQuart(t: f32) f32 {
    return 1.0 - std.math.pow(f32, 1.0 - t, 4);
}

pub fn easeInOutQuart(t: f32) f32 {
    if (t < 0.5) {
        return 8.0 * t * t * t * t;
    } else {
        return 1.0 - std.math.pow(f32, -2.0 * t + 2.0, 4) / 2.0;
    }
}

// Quintic
pub fn easeInQuint(t: f32) f32 {
    return t * t * t * t * t;
}

pub fn easeOutQuint(t: f32) f32 {
    return 1.0 - std.math.pow(f32, 1.0 - t, 5);
}

pub fn easeInOutQuint(t: f32) f32 {
    if (t < 0.5) {
        return 16.0 * t * t * t * t * t;
    } else {
        return 1.0 - std.math.pow(f32, -2.0 * t + 2.0, 5) / 2.0;
    }
}

// Sinusoidal
pub fn easeInSine(t: f32) f32 {
    return 1.0 - @cos((t * PI) / 2.0);
}

pub fn easeOutSine(t: f32) f32 {
    return @sin((t * PI) / 2.0);
}

pub fn easeInOutSine(t: f32) f32 {
    return -(@cos(PI * t) - 1.0) / 2.0;
}

// Exponential
pub fn easeInExpo(t: f32) f32 {
    if (t == 0) return 0;
    return std.math.pow(f32, 2.0, 10.0 * t - 10.0);
}

pub fn easeOutExpo(t: f32) f32 {
    if (t == 1) return 1;
    return 1.0 - std.math.pow(f32, 2.0, -10.0 * t);
}

pub fn easeInOutExpo(t: f32) f32 {
    if (t == 0) return 0;
    if (t == 1) return 1;
    if (t < 0.5) {
        return std.math.pow(f32, 2.0, 20.0 * t - 10.0) / 2.0;
    } else {
        return (2.0 - std.math.pow(f32, 2.0, -20.0 * t + 10.0)) / 2.0;
    }
}

// Circular
pub fn easeInCirc(t: f32) f32 {
    return 1.0 - @sqrt(1.0 - t * t);
}

pub fn easeOutCirc(t: f32) f32 {
    return @sqrt(1.0 - (t - 1.0) * (t - 1.0));
}

pub fn easeInOutCirc(t: f32) f32 {
    if (t < 0.5) {
        return (1.0 - @sqrt(1.0 - 4.0 * t * t)) / 2.0;
    } else {
        return (@sqrt(1.0 - std.math.pow(f32, -2.0 * t + 2.0, 2)) + 1.0) / 2.0;
    }
}

// Back (overshoot)
const c1: f32 = 1.70158;
const c2: f32 = c1 * 1.525;
const c3: f32 = c1 + 1.0;

pub fn easeInBack(t: f32) f32 {
    return c3 * t * t * t - c1 * t * t;
}

pub fn easeOutBack(t: f32) f32 {
    const t1 = t - 1.0;
    return 1.0 + c3 * t1 * t1 * t1 + c1 * t1 * t1;
}

pub fn easeInOutBack(t: f32) f32 {
    if (t < 0.5) {
        return (std.math.pow(f32, 2.0 * t, 2) * ((c2 + 1.0) * 2.0 * t - c2)) / 2.0;
    } else {
        return (std.math.pow(f32, 2.0 * t - 2.0, 2) * ((c2 + 1.0) * (2.0 * t - 2.0) + c2) + 2.0) / 2.0;
    }
}

// Elastic
const c4: f32 = (2.0 * PI) / 3.0;
const c5: f32 = (2.0 * PI) / 4.5;

pub fn easeInElastic(t: f32) f32 {
    if (t == 0) return 0;
    if (t == 1) return 1;
    return -std.math.pow(f32, 2.0, 10.0 * t - 10.0) * @sin((t * 10.0 - 10.75) * c4);
}

pub fn easeOutElastic(t: f32) f32 {
    if (t == 0) return 0;
    if (t == 1) return 1;
    return std.math.pow(f32, 2.0, -10.0 * t) * @sin((t * 10.0 - 0.75) * c4) + 1.0;
}

pub fn easeInOutElastic(t: f32) f32 {
    if (t == 0) return 0;
    if (t == 1) return 1;
    if (t < 0.5) {
        return -(std.math.pow(f32, 2.0, 20.0 * t - 10.0) * @sin((20.0 * t - 11.125) * c5)) / 2.0;
    } else {
        return (std.math.pow(f32, 2.0, -20.0 * t + 10.0) * @sin((20.0 * t - 11.125) * c5)) / 2.0 + 1.0;
    }
}

// Bounce
pub fn easeOutBounce(t: f32) f32 {
    const n1: f32 = 7.5625;
    const d1: f32 = 2.75;

    if (t < 1.0 / d1) {
        return n1 * t * t;
    } else if (t < 2.0 / d1) {
        const t1 = t - 1.5 / d1;
        return n1 * t1 * t1 + 0.75;
    } else if (t < 2.5 / d1) {
        const t1 = t - 2.25 / d1;
        return n1 * t1 * t1 + 0.9375;
    } else {
        const t1 = t - 2.625 / d1;
        return n1 * t1 * t1 + 0.984375;
    }
}

pub fn easeInBounce(t: f32) f32 {
    return 1.0 - easeOutBounce(1.0 - t);
}

pub fn easeInOutBounce(t: f32) f32 {
    if (t < 0.5) {
        return (1.0 - easeOutBounce(1.0 - 2.0 * t)) / 2.0;
    } else {
        return (1.0 + easeOutBounce(2.0 * t - 1.0)) / 2.0;
    }
}

// ============================================================================
// Interpolation Helpers
// ============================================================================

/// Interpolate between two f32 values
pub fn lerpFloat(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

/// Interpolate between two Vec2 values
pub fn lerpVec2(a: Vec2, b: Vec2, t: f32) Vec2 {
    return Vec2.init(
        lerpFloat(a.x, b.x, t),
        lerpFloat(a.y, b.y, t),
    );
}

/// Interpolate between two Color values
pub fn lerpColor(a: Color, b: Color, t: f32) Color {
    return Color.init(
        @intFromFloat(lerpFloat(@floatFromInt(a.r), @floatFromInt(b.r), t)),
        @intFromFloat(lerpFloat(@floatFromInt(a.g), @floatFromInt(b.g), t)),
        @intFromFloat(lerpFloat(@floatFromInt(a.b), @floatFromInt(b.b), t)),
        @intFromFloat(lerpFloat(@floatFromInt(a.a), @floatFromInt(b.a), t)),
    );
}

// ============================================================================
// Tween Types
// ============================================================================

/// Callback function type for tween events
pub const TweenCallback = *const fn (user_data: ?*anyopaque) void;

/// Tween state
pub const TweenState = enum {
    pending, // Not yet started (for sequences)
    running,
    paused,
    completed,
    cancelled,
};

/// Tween options
pub const TweenOptions = struct {
    /// Delay before starting (seconds)
    delay: f32 = 0,
    /// Number of times to repeat (-1 = infinite)
    repeat: i32 = 0,
    /// Yoyo mode (reverse direction each repeat)
    yoyo: bool = false,
    /// Callback when tween completes (each repeat)
    on_complete: ?TweenCallback = null,
    /// Callback when tween starts
    on_start: ?TweenCallback = null,
    /// Callback on each update
    on_update: ?TweenCallback = null,
    /// User data passed to callbacks
    user_data: ?*anyopaque = null,
};

/// Property type being tweened
pub const PropertyType = enum {
    float,
    vec2,
    color,
};

/// Tween ID for tracking
pub const TweenId = u64;

/// Individual tween
pub const Tween = struct {
    id: TweenId,
    state: TweenState,
    elapsed: f32,
    duration: f32,
    delay: f32,
    delay_elapsed: f32,
    easing: Easing,

    // Property data
    property_type: PropertyType,
    target_ptr: *anyopaque,
    start_value: TweenValue,
    end_value: TweenValue,

    // Options
    repeat_count: i32,
    repeats_remaining: i32,
    yoyo: bool,
    forward: bool, // Current direction for yoyo

    // Callbacks
    on_complete: ?TweenCallback,
    on_start: ?TweenCallback,
    on_update: ?TweenCallback,
    user_data: ?*anyopaque,

    /// Create a float tween
    pub fn initFloat(id: TweenId, target: *f32, start: f32, end: f32, duration: f32, easing: Easing, options: TweenOptions) Tween {
        return .{
            .id = id,
            .state = .pending,
            .elapsed = 0,
            .duration = duration,
            .delay = options.delay,
            .delay_elapsed = 0,
            .easing = easing,
            .property_type = .float,
            .target_ptr = @ptrCast(target),
            .start_value = .{ .float = start },
            .end_value = .{ .float = end },
            .repeat_count = options.repeat,
            .repeats_remaining = options.repeat,
            .yoyo = options.yoyo,
            .forward = true,
            .on_complete = options.on_complete,
            .on_start = options.on_start,
            .on_update = options.on_update,
            .user_data = options.user_data,
        };
    }

    /// Create a Vec2 tween
    pub fn initVec2(id: TweenId, target: *Vec2, start: Vec2, end: Vec2, duration: f32, easing: Easing, options: TweenOptions) Tween {
        return .{
            .id = id,
            .state = .pending,
            .elapsed = 0,
            .duration = duration,
            .delay = options.delay,
            .delay_elapsed = 0,
            .easing = easing,
            .property_type = .vec2,
            .target_ptr = @ptrCast(target),
            .start_value = .{ .vec2 = start },
            .end_value = .{ .vec2 = end },
            .repeat_count = options.repeat,
            .repeats_remaining = options.repeat,
            .yoyo = options.yoyo,
            .forward = true,
            .on_complete = options.on_complete,
            .on_start = options.on_start,
            .on_update = options.on_update,
            .user_data = options.user_data,
        };
    }

    /// Create a Color tween
    pub fn initColor(id: TweenId, target: *Color, start: Color, end: Color, duration: f32, easing: Easing, options: TweenOptions) Tween {
        return .{
            .id = id,
            .state = .pending,
            .elapsed = 0,
            .duration = duration,
            .delay = options.delay,
            .delay_elapsed = 0,
            .easing = easing,
            .property_type = .color,
            .target_ptr = @ptrCast(target),
            .start_value = .{ .color = start },
            .end_value = .{ .color = end },
            .repeat_count = options.repeat,
            .repeats_remaining = options.repeat,
            .yoyo = options.yoyo,
            .forward = true,
            .on_complete = options.on_complete,
            .on_start = options.on_start,
            .on_update = options.on_update,
            .user_data = options.user_data,
        };
    }

    /// Update the tween
    pub fn update(self: *Tween, delta_time: f32) void {
        if (self.state == .completed or self.state == .cancelled or self.state == .paused) {
            return;
        }

        // Handle delay
        if (self.delay_elapsed < self.delay) {
            self.delay_elapsed += delta_time;
            if (self.delay_elapsed >= self.delay) {
                // Start the tween
                self.state = .running;
                if (self.on_start) |callback| {
                    callback(self.user_data);
                }
            }
            return;
        }

        // First frame after delay
        if (self.state == .pending) {
            self.state = .running;
            if (self.on_start) |callback| {
                callback(self.user_data);
            }
        }

        // Update elapsed time
        self.elapsed += delta_time;

        // Calculate progress
        var progress = std.math.clamp(self.elapsed / self.duration, 0.0, 1.0);

        // Apply yoyo direction
        if (self.yoyo and !self.forward) {
            progress = 1.0 - progress;
        }

        // Apply easing
        const eased = self.easing.apply(progress);

        // Update the target property
        self.applyValue(eased);

        // Call update callback
        if (self.on_update) |callback| {
            callback(self.user_data);
        }

        // Check for completion
        if (self.elapsed >= self.duration) {
            self.handleCompletion();
        }
    }

    /// Apply the interpolated value to the target
    fn applyValue(self: *Tween, t: f32) void {
        switch (self.property_type) {
            .float => {
                const target: *f32 = @ptrCast(@alignCast(self.target_ptr));
                target.* = lerpFloat(self.start_value.float, self.end_value.float, t);
            },
            .vec2 => {
                const target: *Vec2 = @ptrCast(@alignCast(self.target_ptr));
                target.* = lerpVec2(self.start_value.vec2, self.end_value.vec2, t);
            },
            .color => {
                const target: *Color = @ptrCast(@alignCast(self.target_ptr));
                target.* = lerpColor(self.start_value.color, self.end_value.color, t);
            },
        }
    }

    /// Handle tween completion (repeats, yoyo, callbacks)
    fn handleCompletion(self: *Tween) void {
        // Call completion callback
        if (self.on_complete) |callback| {
            callback(self.user_data);
        }

        // Handle repeats
        if (self.repeats_remaining == -1 or self.repeats_remaining > 0) {
            // Repeat
            if (self.repeats_remaining > 0) {
                self.repeats_remaining -= 1;
            }

            // Reset for next iteration
            self.elapsed = 0;

            // Toggle direction for yoyo
            if (self.yoyo) {
                self.forward = !self.forward;
            }
        } else {
            // Done
            self.state = .completed;

            // Ensure we're at the final value
            if (self.yoyo and !self.forward) {
                self.applyValue(0.0);
            } else {
                self.applyValue(1.0);
            }
        }
    }

    /// Pause the tween
    pub fn pause(self: *Tween) void {
        if (self.state == .running or self.state == .pending) {
            self.state = .paused;
        }
    }

    /// Resume a paused tween
    pub fn unpause(self: *Tween) void {
        if (self.state == .paused) {
            self.state = if (self.delay_elapsed < self.delay) .pending else .running;
        }
    }

    /// Cancel the tween
    pub fn cancel(self: *Tween) void {
        self.state = .cancelled;
    }

    /// Get progress (0.0 to 1.0)
    pub fn getProgress(self: *const Tween) f32 {
        return std.math.clamp(self.elapsed / self.duration, 0.0, 1.0);
    }

    /// Check if tween is active (not completed or cancelled)
    pub fn isActive(self: *const Tween) bool {
        return self.state != .completed and self.state != .cancelled;
    }
};

/// Tween value union
pub const TweenValue = union {
    float: f32,
    vec2: Vec2,
    color: Color,
};

// ============================================================================
// Tween Sequence
// ============================================================================

/// A sequence of tweens that play one after another
pub const TweenSequence = struct {
    allocator: std.mem.Allocator,
    tweens: std.ArrayList(Tween),
    current_index: usize,
    state: TweenState,
    on_complete: ?TweenCallback,
    user_data: ?*anyopaque,

    /// Create a new sequence
    pub fn init(allocator: std.mem.Allocator) TweenSequence {
        return .{
            .allocator = allocator,
            .tweens = std.ArrayList(Tween).init(allocator),
            .current_index = 0,
            .state = .pending,
            .on_complete = null,
            .user_data = null,
        };
    }

    /// Clean up
    pub fn deinit(self: *TweenSequence) void {
        self.tweens.deinit();
    }

    /// Add a tween to the sequence
    pub fn append(self: *TweenSequence, tween: Tween) !void {
        try self.tweens.append(tween);
    }

    /// Set completion callback
    pub fn setOnComplete(self: *TweenSequence, callback: TweenCallback, user_data: ?*anyopaque) void {
        self.on_complete = callback;
        self.user_data = user_data;
    }

    /// Update the sequence
    pub fn update(self: *TweenSequence, delta_time: f32) void {
        if (self.state == .completed or self.state == .cancelled or self.state == .paused) {
            return;
        }

        if (self.current_index >= self.tweens.items.len) {
            self.state = .completed;
            if (self.on_complete) |callback| {
                callback(self.user_data);
            }
            return;
        }

        self.state = .running;
        var current = &self.tweens.items[self.current_index];
        current.update(delta_time);

        if (current.state == .completed) {
            self.current_index += 1;
        }
    }

    /// Pause the sequence
    pub fn pause(self: *TweenSequence) void {
        if (self.state == .running) {
            self.state = .paused;
            if (self.current_index < self.tweens.items.len) {
                self.tweens.items[self.current_index].pause();
            }
        }
    }

    /// Resume the sequence
    pub fn unpause(self: *TweenSequence) void {
        if (self.state == .paused) {
            self.state = .running;
            if (self.current_index < self.tweens.items.len) {
                self.tweens.items[self.current_index].unpause();
            }
        }
    }

    /// Cancel the sequence
    pub fn cancel(self: *TweenSequence) void {
        self.state = .cancelled;
        for (self.tweens.items) |*tween| {
            tween.cancel();
        }
    }

    /// Check if sequence is active
    pub fn isActive(self: *const TweenSequence) bool {
        return self.state != .completed and self.state != .cancelled;
    }
};

// ============================================================================
// Tween Group (Parallel)
// ============================================================================

/// A group of tweens that play simultaneously
pub const TweenGroup = struct {
    allocator: std.mem.Allocator,
    tweens: std.ArrayList(Tween),
    state: TweenState,
    on_complete: ?TweenCallback,
    user_data: ?*anyopaque,

    /// Create a new group
    pub fn init(allocator: std.mem.Allocator) TweenGroup {
        return .{
            .allocator = allocator,
            .tweens = std.ArrayList(Tween).init(allocator),
            .state = .pending,
            .on_complete = null,
            .user_data = null,
        };
    }

    /// Clean up
    pub fn deinit(self: *TweenGroup) void {
        self.tweens.deinit();
    }

    /// Add a tween to the group
    pub fn append(self: *TweenGroup, tween: Tween) !void {
        try self.tweens.append(tween);
    }

    /// Set completion callback
    pub fn setOnComplete(self: *TweenGroup, callback: TweenCallback, user_data: ?*anyopaque) void {
        self.on_complete = callback;
        self.user_data = user_data;
    }

    /// Update all tweens in the group
    pub fn update(self: *TweenGroup, delta_time: f32) void {
        if (self.state == .completed or self.state == .cancelled or self.state == .paused) {
            return;
        }

        self.state = .running;
        var all_complete = true;

        for (self.tweens.items) |*tween| {
            tween.update(delta_time);
            if (tween.isActive()) {
                all_complete = false;
            }
        }

        if (all_complete) {
            self.state = .completed;
            if (self.on_complete) |callback| {
                callback(self.user_data);
            }
        }
    }

    /// Pause all tweens
    pub fn pause(self: *TweenGroup) void {
        if (self.state == .running) {
            self.state = .paused;
            for (self.tweens.items) |*tween| {
                tween.pause();
            }
        }
    }

    /// Resume all tweens
    pub fn unpause(self: *TweenGroup) void {
        if (self.state == .paused) {
            self.state = .running;
            for (self.tweens.items) |*tween| {
                tween.unpause();
            }
        }
    }

    /// Cancel all tweens
    pub fn cancel(self: *TweenGroup) void {
        self.state = .cancelled;
        for (self.tweens.items) |*tween| {
            tween.cancel();
        }
    }

    /// Check if group is active
    pub fn isActive(self: *const TweenGroup) bool {
        return self.state != .completed and self.state != .cancelled;
    }
};

// ============================================================================
// Tween Manager
// ============================================================================

/// Manages multiple tweens
pub const TweenManager = struct {
    allocator: std.mem.Allocator,
    tweens: std.ArrayList(Tween),
    sequences: std.ArrayList(TweenSequence),
    groups: std.ArrayList(TweenGroup),
    next_id: TweenId,

    /// Create a new tween manager
    pub fn init(allocator: std.mem.Allocator) TweenManager {
        return .{
            .allocator = allocator,
            .tweens = std.ArrayList(Tween).init(allocator),
            .sequences = std.ArrayList(TweenSequence).init(allocator),
            .groups = std.ArrayList(TweenGroup).init(allocator),
            .next_id = 1,
        };
    }

    /// Clean up
    pub fn deinit(self: *TweenManager) void {
        for (self.sequences.items) |*seq| {
            seq.deinit();
        }
        for (self.groups.items) |*grp| {
            grp.deinit();
        }
        self.tweens.deinit();
        self.sequences.deinit();
        self.groups.deinit();
    }

    /// Create a float tween
    pub fn tweenFloat(
        self: *TweenManager,
        target: *f32,
        start: f32,
        end: f32,
        duration: f32,
        easing: Easing,
        options: TweenOptions,
    ) !TweenId {
        const id = self.next_id;
        self.next_id += 1;

        const tween = Tween.initFloat(id, target, start, end, duration, easing, options);
        try self.tweens.append(tween);
        return id;
    }

    /// Create a Vec2 tween
    pub fn tweenVec2(
        self: *TweenManager,
        target: *Vec2,
        start: Vec2,
        end: Vec2,
        duration: f32,
        easing: Easing,
        options: TweenOptions,
    ) !TweenId {
        const id = self.next_id;
        self.next_id += 1;

        const tween = Tween.initVec2(id, target, start, end, duration, easing, options);
        try self.tweens.append(tween);
        return id;
    }

    /// Create a Color tween
    pub fn tweenColor(
        self: *TweenManager,
        target: *Color,
        start: Color,
        end: Color,
        duration: f32,
        easing: Easing,
        options: TweenOptions,
    ) !TweenId {
        const id = self.next_id;
        self.next_id += 1;

        const tween = Tween.initColor(id, target, start, end, duration, easing, options);
        try self.tweens.append(tween);
        return id;
    }

    /// Create a sequence and return it for adding tweens
    pub fn createSequence(self: *TweenManager) !*TweenSequence {
        const seq = TweenSequence.init(self.allocator);
        try self.sequences.append(seq);
        return &self.sequences.items[self.sequences.items.len - 1];
    }

    /// Create a group and return it for adding tweens
    pub fn createGroup(self: *TweenManager) !*TweenGroup {
        const grp = TweenGroup.init(self.allocator);
        try self.groups.append(grp);
        return &self.groups.items[self.groups.items.len - 1];
    }

    /// Update all tweens
    pub fn update(self: *TweenManager, delta_time: f32) void {
        // Update individual tweens
        var i: usize = 0;
        while (i < self.tweens.items.len) {
            self.tweens.items[i].update(delta_time);
            if (!self.tweens.items[i].isActive()) {
                _ = self.tweens.swapRemove(i);
            } else {
                i += 1;
            }
        }

        // Update sequences
        var j: usize = 0;
        while (j < self.sequences.items.len) {
            self.sequences.items[j].update(delta_time);
            if (!self.sequences.items[j].isActive()) {
                self.sequences.items[j].deinit();
                _ = self.sequences.swapRemove(j);
            } else {
                j += 1;
            }
        }

        // Update groups
        var k: usize = 0;
        while (k < self.groups.items.len) {
            self.groups.items[k].update(delta_time);
            if (!self.groups.items[k].isActive()) {
                self.groups.items[k].deinit();
                _ = self.groups.swapRemove(k);
            } else {
                k += 1;
            }
        }
    }

    /// Get a tween by ID
    pub fn getTween(self: *TweenManager, id: TweenId) ?*Tween {
        for (self.tweens.items) |*tween| {
            if (tween.id == id) {
                return tween;
            }
        }
        return null;
    }

    /// Cancel a tween by ID
    pub fn cancel(self: *TweenManager, id: TweenId) bool {
        if (self.getTween(id)) |tween| {
            tween.cancel();
            return true;
        }
        return false;
    }

    /// Cancel all tweens
    pub fn cancelAll(self: *TweenManager) void {
        for (self.tweens.items) |*tween| {
            tween.cancel();
        }
        for (self.sequences.items) |*seq| {
            seq.cancel();
        }
        for (self.groups.items) |*grp| {
            grp.cancel();
        }
    }

    /// Get count of active tweens
    pub fn activeCount(self: *const TweenManager) usize {
        var count: usize = 0;
        for (self.tweens.items) |tween| {
            if (tween.isActive()) count += 1;
        }
        for (self.sequences.items) |seq| {
            if (seq.isActive()) count += 1;
        }
        for (self.groups.items) |grp| {
            if (grp.isActive()) count += 1;
        }
        return count;
    }

    /// Check if any tweens are active
    pub fn hasActiveTweens(self: *const TweenManager) bool {
        return self.activeCount() > 0;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Easing - linear" {
    try std.testing.expectEqual(@as(f32, 0.0), linear(0.0));
    try std.testing.expectEqual(@as(f32, 0.5), linear(0.5));
    try std.testing.expectEqual(@as(f32, 1.0), linear(1.0));
}

test "Easing - ease_out_quad" {
    try std.testing.expectEqual(@as(f32, 0.0), easeOutQuad(0.0));
    try std.testing.expectEqual(@as(f32, 1.0), easeOutQuad(1.0));
    // Ease out should be faster at start
    try std.testing.expect(easeOutQuad(0.5) > 0.5);
}

test "Easing - ease_in_quad" {
    try std.testing.expectEqual(@as(f32, 0.0), easeInQuad(0.0));
    try std.testing.expectEqual(@as(f32, 1.0), easeInQuad(1.0));
    // Ease in should be slower at start
    try std.testing.expect(easeInQuad(0.5) < 0.5);
}

test "Easing - ease_in_out_quad" {
    try std.testing.expectEqual(@as(f32, 0.0), easeInOutQuad(0.0));
    try std.testing.expectEqual(@as(f32, 1.0), easeInOutQuad(1.0));
    try std.testing.expectEqual(@as(f32, 0.5), easeInOutQuad(0.5));
}

test "Easing - bounce" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), easeOutBounce(0.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), easeOutBounce(1.0), 0.001);
}

test "Easing - elastic" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), easeOutElastic(0.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), easeOutElastic(1.0), 0.001);
}

test "Easing - enum apply" {
    try std.testing.expectEqual(@as(f32, 0.5), Easing.linear.apply(0.5));
    try std.testing.expect(Easing.ease_out_quad.apply(0.5) > 0.5);
}

test "lerpFloat" {
    try std.testing.expectEqual(@as(f32, 0.0), lerpFloat(0.0, 100.0, 0.0));
    try std.testing.expectEqual(@as(f32, 50.0), lerpFloat(0.0, 100.0, 0.5));
    try std.testing.expectEqual(@as(f32, 100.0), lerpFloat(0.0, 100.0, 1.0));
}

test "lerpVec2" {
    const a = Vec2.init(0.0, 0.0);
    const b = Vec2.init(100.0, 200.0);
    const result = lerpVec2(a, b, 0.5);
    try std.testing.expectEqual(@as(f32, 50.0), result.x);
    try std.testing.expectEqual(@as(f32, 100.0), result.y);
}

test "lerpColor" {
    const a = Color.init(0, 0, 0, 255);
    const b = Color.init(100, 200, 50, 255);
    const result = lerpColor(a, b, 0.5);
    try std.testing.expectEqual(@as(u8, 50), result.r);
    try std.testing.expectEqual(@as(u8, 100), result.g);
    try std.testing.expectEqual(@as(u8, 25), result.b);
}

test "Tween - float basic" {
    var value: f32 = 0.0;
    var tween = Tween.initFloat(1, &value, 0.0, 100.0, 1.0, .linear, .{});

    try std.testing.expectEqual(@as(f32, 0.0), value);

    // Update for 0.5 seconds
    tween.update(0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), value, 0.01);

    // Complete the tween
    tween.update(0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), value, 0.01);
    try std.testing.expectEqual(TweenState.completed, tween.state);
}

test "Tween - delay" {
    var value: f32 = 0.0;
    var tween = Tween.initFloat(1, &value, 0.0, 100.0, 1.0, .linear, .{ .delay = 0.5 });

    // Update during delay
    tween.update(0.3);
    try std.testing.expectEqual(@as(f32, 0.0), value);
    try std.testing.expectEqual(TweenState.pending, tween.state);

    // Finish delay, start tween
    tween.update(0.2);
    try std.testing.expect(tween.state == .pending or tween.state == .running);

    // Update tween
    tween.update(0.5);
    try std.testing.expect(value > 0.0);
}

test "Tween - yoyo" {
    var value: f32 = 0.0;
    var tween = Tween.initFloat(1, &value, 0.0, 100.0, 0.5, .linear, .{
        .yoyo = true,
        .repeat = 1,
    });

    // First pass: 0 -> 100
    tween.update(0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), value, 0.01);

    // Yoyo: 100 -> 0
    tween.update(0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), value, 0.01);
    try std.testing.expectEqual(TweenState.completed, tween.state);
}

test "Tween - repeat" {
    var value: f32 = 0.0;
    var completed_count: u32 = 0;

    const callback = struct {
        fn cb(user_data: ?*anyopaque) void {
            const count: *u32 = @ptrCast(@alignCast(user_data.?));
            count.* += 1;
        }
    }.cb;

    var tween = Tween.initFloat(1, &value, 0.0, 100.0, 0.5, .linear, .{
        .repeat = 2,
        .on_complete = callback,
        .user_data = &completed_count,
    });

    // First pass
    tween.update(0.5);
    try std.testing.expectEqual(@as(u32, 1), completed_count);

    // Second pass
    tween.update(0.5);
    try std.testing.expectEqual(@as(u32, 2), completed_count);

    // Third pass (final)
    tween.update(0.5);
    try std.testing.expectEqual(@as(u32, 3), completed_count);
    try std.testing.expectEqual(TweenState.completed, tween.state);
}

test "Tween - pause and resume" {
    var value: f32 = 0.0;
    var tween = Tween.initFloat(1, &value, 0.0, 100.0, 1.0, .linear, .{});

    tween.update(0.3);
    const paused_value = value;

    tween.pause();
    tween.update(0.3);
    try std.testing.expectEqual(paused_value, value);

    tween.unpause();
    tween.update(0.3);
    try std.testing.expect(value > paused_value);
}

test "TweenManager - basic usage" {
    var manager = TweenManager.init(std.testing.allocator);
    defer manager.deinit();

    var value: f32 = 0.0;
    const id = try manager.tweenFloat(&value, 0.0, 100.0, 1.0, .linear, .{});

    try std.testing.expect(id > 0);
    try std.testing.expectEqual(@as(usize, 1), manager.activeCount());

    manager.update(0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), value, 0.01);

    manager.update(0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), value, 0.01);

    // Completed tweens are removed
    try std.testing.expectEqual(@as(usize, 0), manager.activeCount());
}

test "TweenManager - Vec2" {
    var manager = TweenManager.init(std.testing.allocator);
    defer manager.deinit();

    var pos = Vec2.init(0.0, 0.0);
    _ = try manager.tweenVec2(&pos, Vec2.init(0.0, 0.0), Vec2.init(100.0, 200.0), 1.0, .linear, .{});

    manager.update(0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), pos.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), pos.y, 0.01);
}

test "TweenManager - cancel" {
    var manager = TweenManager.init(std.testing.allocator);
    defer manager.deinit();

    var value: f32 = 0.0;
    const id = try manager.tweenFloat(&value, 0.0, 100.0, 1.0, .linear, .{});

    manager.update(0.3);
    const cancelled_value = value;

    try std.testing.expect(manager.cancel(id));
    manager.update(0.3);

    // Value should not have changed after cancel
    try std.testing.expectEqual(cancelled_value, value);
}

test "TweenSequence - basic" {
    var manager = TweenManager.init(std.testing.allocator);
    defer manager.deinit();

    var value1: f32 = 0.0;
    var value2: f32 = 0.0;

    var seq = try manager.createSequence();
    try seq.append(Tween.initFloat(1, &value1, 0.0, 100.0, 0.5, .linear, .{}));
    try seq.append(Tween.initFloat(2, &value2, 0.0, 50.0, 0.5, .linear, .{}));

    // First tween
    manager.update(0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), value1, 0.01);
    try std.testing.expectEqual(@as(f32, 0.0), value2); // Not started yet

    // Second tween
    manager.update(0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), value2, 0.01);
}

test "TweenGroup - parallel" {
    var manager = TweenManager.init(std.testing.allocator);
    defer manager.deinit();

    var value1: f32 = 0.0;
    var value2: f32 = 0.0;

    var grp = try manager.createGroup();
    try grp.append(Tween.initFloat(1, &value1, 0.0, 100.0, 1.0, .linear, .{}));
    try grp.append(Tween.initFloat(2, &value2, 0.0, 50.0, 0.5, .linear, .{}));

    // Both tweens update simultaneously
    manager.update(0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), value1, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), value2, 0.01);

    // value2 is done, value1 continues
    manager.update(0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), value1, 0.01);
}

test "Easing - all functions return valid ranges" {
    // Test that all easing functions return values at endpoints
    const easings = [_]Easing{
        .linear,
        .ease_in_quad,
        .ease_out_quad,
        .ease_in_out_quad,
        .ease_in_cubic,
        .ease_out_cubic,
        .ease_in_out_cubic,
        .ease_in_sine,
        .ease_out_sine,
        .ease_in_out_sine,
        .ease_in_expo,
        .ease_out_expo,
        .ease_in_out_expo,
        .ease_in_circ,
        .ease_out_circ,
        .ease_in_out_circ,
        .ease_in_bounce,
        .ease_out_bounce,
        .ease_in_out_bounce,
    };

    for (easings) |e| {
        const start = e.apply(0.0);
        const end = e.apply(1.0);
        try std.testing.expectApproxEqAbs(@as(f32, 0.0), start, 0.01);
        try std.testing.expectApproxEqAbs(@as(f32, 1.0), end, 0.01);
    }
}
