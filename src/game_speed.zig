//! Game Speed System - Timing Control for Game Simulation
//!
//! Provides game speed multipliers with pause functionality, preset speed levels,
//! and both scaled (game) and unscaled (real) time tracking.
//!
//! Features:
//! - Multiple speed settings (0.5x, 1x, 2x, 4x)
//! - Pause functionality
//! - Per-system speed scaling (systems choose whether to use game or real time)
//! - Preset and custom speed values
//! - Total time tracking for both game and real time
//!
//! Usage:
//! ```zig
//! var speed = GameSpeed.init(.{});
//!
//! // In main loop:
//! speed.update(raw_delta_time);
//!
//! // Get scaled time for game systems
//! tween_manager.update(speed.getGameDelta());
//! animation.update(speed.getGameDelta());
//!
//! // Get unscaled time for UI (always runs)
//! ui_tween_manager.update(speed.getRealDelta());
//!
//! // Control speed
//! speed.togglePause();
//! speed.setPreset(.fast);
//! speed.setCustomSpeed(3.0);
//! ```

const std = @import("std");

/// Speed preset levels
pub const SpeedPreset = enum {
    pause, // 0.0x
    slow, // 0.5x
    normal, // 1.0x
    fast, // 2.0x
    very_fast, // 4.0x

    /// Get the speed multiplier for this preset
    pub fn getMultiplier(self: SpeedPreset) f32 {
        return switch (self) {
            .pause => 0.0,
            .slow => 0.5,
            .normal => 1.0,
            .fast => 2.0,
            .very_fast => 4.0,
        };
    }

    /// Get human-readable name for this preset
    pub fn getName(self: SpeedPreset) []const u8 {
        return switch (self) {
            .pause => "Paused",
            .slow => "Slow (0.5x)",
            .normal => "Normal (1x)",
            .fast => "Fast (2x)",
            .very_fast => "Very Fast (4x)",
        };
    }

    /// Get short label for UI display
    pub fn getShortName(self: SpeedPreset) []const u8 {
        return switch (self) {
            .pause => "||",
            .slow => "0.5x",
            .normal => "1x",
            .fast => "2x",
            .very_fast => "4x",
        };
    }

    /// Get next preset in cycle (skips pause)
    pub fn next(self: SpeedPreset) SpeedPreset {
        return switch (self) {
            .pause => .slow,
            .slow => .normal,
            .normal => .fast,
            .fast => .very_fast,
            .very_fast => .slow,
        };
    }

    /// Get previous preset in cycle (skips pause)
    pub fn prev(self: SpeedPreset) SpeedPreset {
        return switch (self) {
            .pause => .very_fast,
            .slow => .very_fast,
            .normal => .slow,
            .fast => .normal,
            .very_fast => .fast,
        };
    }

    /// All non-pause presets for iteration
    pub const playable = [_]SpeedPreset{ .slow, .normal, .fast, .very_fast };
};

/// Configuration for GameSpeed
pub const Config = struct {
    /// Initial speed multiplier
    initial_speed: f32 = 1.0,
    /// Minimum allowed speed (0.0 allows pause)
    min_speed: f32 = 0.0,
    /// Maximum allowed speed
    max_speed: f32 = 10.0,
    /// Start paused
    start_paused: bool = false,
};

/// Game speed controller providing scaled delta time
pub const GameSpeed = struct {
    const Self = @This();

    config: Config,

    // Time state
    real_delta: f32 = 0,
    game_delta: f32 = 0,
    total_real_time: f64 = 0,
    total_game_time: f64 = 0,

    // Speed state
    current_speed: f32,
    paused: bool,
    current_preset: ?SpeedPreset,

    // Speed before pause (for restore)
    speed_before_pause: f32 = 1.0,

    /// Initialize with configuration
    pub fn init(config: Config) Self {
        const initial = std.math.clamp(config.initial_speed, config.min_speed, config.max_speed);
        return Self{
            .config = config,
            .current_speed = initial,
            .paused = config.start_paused,
            .current_preset = presetFromSpeed(initial),
            .speed_before_pause = initial,
        };
    }

    /// Update time tracking with raw (unscaled) delta time
    /// Call this once per frame with the frame's delta time
    pub fn update(self: *Self, raw_delta: f32) void {
        self.real_delta = raw_delta;
        self.total_real_time += raw_delta;

        if (self.paused) {
            self.game_delta = 0;
        } else {
            self.game_delta = raw_delta * self.current_speed;
            self.total_game_time += self.game_delta;
        }
    }

    /// Get the scaled delta time for game systems
    /// Returns 0 when paused
    pub fn getGameDelta(self: *const Self) f32 {
        return self.game_delta;
    }

    /// Get the unscaled delta time for systems that should always run
    /// Use this for UI animations, etc.
    pub fn getRealDelta(self: *const Self) f32 {
        return self.real_delta;
    }

    /// Get total accumulated game time (scaled)
    pub fn getGameTime(self: *const Self) f64 {
        return self.total_game_time;
    }

    /// Get total accumulated real time (unscaled)
    pub fn getRealTime(self: *const Self) f64 {
        return self.total_real_time;
    }

    /// Get current speed multiplier
    pub fn getSpeedMultiplier(self: *const Self) f32 {
        return if (self.paused) 0.0 else self.current_speed;
    }

    /// Check if game is paused
    pub fn isPaused(self: *const Self) bool {
        return self.paused;
    }

    /// Pause the game
    pub fn pause(self: *Self) void {
        if (!self.paused) {
            self.speed_before_pause = self.current_speed;
            self.paused = true;
        }
    }

    /// Unpause the game (restores previous speed)
    pub fn unpause(self: *Self) void {
        if (self.paused) {
            self.paused = false;
            self.current_speed = self.speed_before_pause;
            self.current_preset = presetFromSpeed(self.current_speed);
        }
    }

    /// Toggle pause state
    pub fn togglePause(self: *Self) void {
        if (self.paused) {
            self.unpause();
        } else {
            self.pause();
        }
    }

    /// Set speed using a preset
    pub fn setPreset(self: *Self, preset: SpeedPreset) void {
        if (preset == .pause) {
            self.pause();
        } else {
            self.paused = false;
            self.current_speed = preset.getMultiplier();
            self.current_preset = preset;
            self.speed_before_pause = self.current_speed;
        }
    }

    /// Set a custom speed value (clamped to min/max)
    pub fn setCustomSpeed(self: *Self, speed: f32) void {
        const clamped = std.math.clamp(speed, self.config.min_speed, self.config.max_speed);
        if (clamped == 0) {
            self.pause();
        } else {
            self.paused = false;
            self.current_speed = clamped;
            self.current_preset = presetFromSpeed(clamped);
            self.speed_before_pause = self.current_speed;
        }
    }

    /// Cycle to next speed preset (skips pause)
    pub fn cycleSpeed(self: *Self) void {
        if (self.current_preset) |preset| {
            self.setPreset(preset.next());
        } else {
            // Custom speed, go to normal
            self.setPreset(.normal);
        }
    }

    /// Cycle to previous speed preset (skips pause)
    pub fn cyclePrevSpeed(self: *Self) void {
        if (self.current_preset) |preset| {
            self.setPreset(preset.prev());
        } else {
            // Custom speed, go to normal
            self.setPreset(.normal);
        }
    }

    /// Get current preset (null if using custom speed)
    pub fn getCurrentPreset(self: *const Self) ?SpeedPreset {
        return if (self.paused) .pause else self.current_preset;
    }

    /// Get formatted speed string for display
    pub fn getSpeedString(self: *const Self, buf: []u8) []const u8 {
        if (self.paused) {
            return "Paused";
        }
        if (self.current_preset) |preset| {
            return preset.getShortName();
        }
        // Custom speed - format as "X.Xx"
        return std.fmt.bufPrint(buf, "{d:.1}x", .{self.current_speed}) catch "?x";
    }

    /// Reset time counters (useful for level transitions)
    pub fn resetTime(self: *Self) void {
        self.total_real_time = 0;
        self.total_game_time = 0;
        self.real_delta = 0;
        self.game_delta = 0;
    }

    /// Helper to match speed value to preset
    fn presetFromSpeed(speed: f32) ?SpeedPreset {
        const epsilon = 0.001;
        for (SpeedPreset.playable) |preset| {
            if (@abs(speed - preset.getMultiplier()) < epsilon) {
                return preset;
            }
        }
        return null;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "init with default config" {
    const speed = GameSpeed.init(.{});
    try std.testing.expectEqual(@as(f32, 1.0), speed.current_speed);
    try std.testing.expectEqual(false, speed.paused);
    try std.testing.expectEqual(SpeedPreset.normal, speed.current_preset.?);
}

test "init with custom config" {
    const speed = GameSpeed.init(.{
        .initial_speed = 2.0,
        .start_paused = true,
    });
    try std.testing.expectEqual(@as(f32, 2.0), speed.current_speed);
    try std.testing.expectEqual(true, speed.paused);
    try std.testing.expectEqual(SpeedPreset.fast, speed.current_preset.?);
}

test "init clamps initial speed to bounds" {
    const speed = GameSpeed.init(.{
        .initial_speed = 100.0,
        .max_speed = 5.0,
    });
    try std.testing.expectEqual(@as(f32, 5.0), speed.current_speed);
}

test "update advances real time" {
    var speed = GameSpeed.init(.{});
    speed.update(0.016);
    try std.testing.expectApproxEqAbs(@as(f32, 0.016), speed.real_delta, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.016), speed.total_real_time, 0.0001);
}

test "update advances game time with multiplier" {
    var speed = GameSpeed.init(.{ .initial_speed = 2.0 });
    speed.update(0.016);
    try std.testing.expectApproxEqAbs(@as(f32, 0.032), speed.game_delta, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.032), speed.total_game_time, 0.0001);
}

test "pause stops game time" {
    var speed = GameSpeed.init(.{});
    speed.pause();
    speed.update(0.016);
    try std.testing.expectEqual(@as(f32, 0.0), speed.game_delta);
    try std.testing.expectEqual(@as(f64, 0.0), speed.total_game_time);
}

test "pause does not stop real time" {
    var speed = GameSpeed.init(.{});
    speed.pause();
    speed.update(0.016);
    try std.testing.expectApproxEqAbs(@as(f32, 0.016), speed.real_delta, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.016), speed.total_real_time, 0.0001);
}

test "unpause restores previous speed" {
    var speed = GameSpeed.init(.{ .initial_speed = 2.0 });
    speed.pause();
    speed.unpause();
    try std.testing.expectEqual(false, speed.paused);
    try std.testing.expectEqual(@as(f32, 2.0), speed.current_speed);
}

test "toggle pause behavior" {
    var speed = GameSpeed.init(.{});
    try std.testing.expectEqual(false, speed.paused);
    speed.togglePause();
    try std.testing.expectEqual(true, speed.paused);
    speed.togglePause();
    try std.testing.expectEqual(false, speed.paused);
}

test "preset pause sets paused state" {
    var speed = GameSpeed.init(.{});
    speed.setPreset(.pause);
    try std.testing.expectEqual(true, speed.paused);
    try std.testing.expectEqual(SpeedPreset.pause, speed.getCurrentPreset().?);
}

test "preset normal sets speed to 1" {
    var speed = GameSpeed.init(.{ .initial_speed = 2.0 });
    speed.setPreset(.normal);
    try std.testing.expectEqual(@as(f32, 1.0), speed.current_speed);
    try std.testing.expectEqual(SpeedPreset.normal, speed.current_preset.?);
}

test "preset fast sets speed to 2" {
    var speed = GameSpeed.init(.{});
    speed.setPreset(.fast);
    try std.testing.expectEqual(@as(f32, 2.0), speed.current_speed);
    try std.testing.expectEqual(SpeedPreset.fast, speed.current_preset.?);
}

test "preset very_fast sets speed to 4" {
    var speed = GameSpeed.init(.{});
    speed.setPreset(.very_fast);
    try std.testing.expectEqual(@as(f32, 4.0), speed.current_speed);
}

test "custom speed applies correctly" {
    var speed = GameSpeed.init(.{});
    speed.setCustomSpeed(3.0);
    try std.testing.expectEqual(@as(f32, 3.0), speed.current_speed);
    try std.testing.expectEqual(@as(?SpeedPreset, null), speed.current_preset);
}

test "custom speed clamps to min/max" {
    var speed = GameSpeed.init(.{ .min_speed = 0.1, .max_speed = 5.0 });
    speed.setCustomSpeed(100.0);
    try std.testing.expectEqual(@as(f32, 5.0), speed.current_speed);
    speed.setCustomSpeed(-5.0);
    try std.testing.expectEqual(@as(f32, 0.1), speed.current_speed);
}

test "custom speed zero pauses" {
    var speed = GameSpeed.init(.{});
    speed.setCustomSpeed(0.0);
    try std.testing.expectEqual(true, speed.paused);
}

test "cycle speed progresses through presets" {
    var speed = GameSpeed.init(.{});
    try std.testing.expectEqual(SpeedPreset.normal, speed.current_preset.?);
    speed.cycleSpeed();
    try std.testing.expectEqual(SpeedPreset.fast, speed.current_preset.?);
    speed.cycleSpeed();
    try std.testing.expectEqual(SpeedPreset.very_fast, speed.current_preset.?);
    speed.cycleSpeed();
    try std.testing.expectEqual(SpeedPreset.slow, speed.current_preset.?);
}

test "cycle prev speed goes backwards" {
    var speed = GameSpeed.init(.{});
    speed.cyclePrevSpeed();
    try std.testing.expectEqual(SpeedPreset.slow, speed.current_preset.?);
    speed.cyclePrevSpeed();
    try std.testing.expectEqual(SpeedPreset.very_fast, speed.current_preset.?);
}

test "getSpeedMultiplier returns 0 when paused" {
    var speed = GameSpeed.init(.{ .initial_speed = 2.0 });
    try std.testing.expectEqual(@as(f32, 2.0), speed.getSpeedMultiplier());
    speed.pause();
    try std.testing.expectEqual(@as(f32, 0.0), speed.getSpeedMultiplier());
}

test "resetTime clears counters" {
    var speed = GameSpeed.init(.{});
    speed.update(1.0);
    speed.update(1.0);
    try std.testing.expect(speed.total_real_time > 0);
    speed.resetTime();
    try std.testing.expectEqual(@as(f64, 0.0), speed.total_real_time);
    try std.testing.expectEqual(@as(f64, 0.0), speed.total_game_time);
}

test "SpeedPreset getMultiplier values" {
    try std.testing.expectEqual(@as(f32, 0.0), SpeedPreset.pause.getMultiplier());
    try std.testing.expectEqual(@as(f32, 0.5), SpeedPreset.slow.getMultiplier());
    try std.testing.expectEqual(@as(f32, 1.0), SpeedPreset.normal.getMultiplier());
    try std.testing.expectEqual(@as(f32, 2.0), SpeedPreset.fast.getMultiplier());
    try std.testing.expectEqual(@as(f32, 4.0), SpeedPreset.very_fast.getMultiplier());
}

test "SpeedPreset next cycles correctly" {
    try std.testing.expectEqual(SpeedPreset.slow, SpeedPreset.pause.next());
    try std.testing.expectEqual(SpeedPreset.normal, SpeedPreset.slow.next());
    try std.testing.expectEqual(SpeedPreset.fast, SpeedPreset.normal.next());
    try std.testing.expectEqual(SpeedPreset.very_fast, SpeedPreset.fast.next());
    try std.testing.expectEqual(SpeedPreset.slow, SpeedPreset.very_fast.next());
}

test "SpeedPreset prev cycles correctly" {
    try std.testing.expectEqual(SpeedPreset.very_fast, SpeedPreset.pause.prev());
    try std.testing.expectEqual(SpeedPreset.very_fast, SpeedPreset.slow.prev());
    try std.testing.expectEqual(SpeedPreset.slow, SpeedPreset.normal.prev());
    try std.testing.expectEqual(SpeedPreset.normal, SpeedPreset.fast.prev());
    try std.testing.expectEqual(SpeedPreset.fast, SpeedPreset.very_fast.prev());
}
