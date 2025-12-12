// animation.zig
// Frame-based Animation System for AgentiteZ
//
// Features:
// - Animation clips (start frame, end frame, fps, loop)
// - Playback controls (play, pause, stop, resume)
// - Animation events (callbacks at specific frames)
// - Animation state machine with transitions
// - Blend transitions between animations

const std = @import("std");

/// Animation playback state
pub const PlaybackState = enum {
    stopped,
    playing,
    paused,
};

/// Animation clip definition
pub const AnimationClip = struct {
    /// Name/ID of this clip
    name: []const u8,

    /// First frame index in the sprite sheet
    start_frame: u32,

    /// Last frame index (inclusive)
    end_frame: u32,

    /// Frames per second
    fps: f32,

    /// Whether the animation loops
    loop: bool,

    /// Events triggered at specific frames (frame index -> event name)
    events: ?[]const FrameEvent = null,

    /// Get the number of frames in this clip
    pub fn frameCount(self: AnimationClip) u32 {
        return self.end_frame - self.start_frame + 1;
    }

    /// Get the duration of one loop in seconds
    pub fn duration(self: AnimationClip) f32 {
        return @as(f32, @floatFromInt(self.frameCount())) / self.fps;
    }
};

/// Event triggered at a specific frame
pub const FrameEvent = struct {
    frame: u32, // Frame index relative to clip start
    name: []const u8, // Event name/identifier
};

/// Event callback function type
pub const EventCallback = *const fn (event_name: []const u8, user_data: ?*anyopaque) void;

/// Animation state for a single animated entity
pub const Animation = struct {
    allocator: std.mem.Allocator,

    /// Registered animation clips (owned)
    clips: std.StringHashMap(AnimationClip),

    /// Current clip being played (reference to clips map)
    current_clip: ?*const AnimationClip,

    /// Current playback state
    state: PlaybackState,

    /// Current time within the animation (seconds)
    current_time: f32,

    /// Current frame index (absolute, includes start_frame offset)
    current_frame: u32,

    /// Playback speed multiplier (1.0 = normal)
    speed: f32,

    /// Event callback (optional)
    event_callback: ?EventCallback,
    event_user_data: ?*anyopaque,

    /// Last frame that had events processed (to avoid double-triggering)
    last_event_frame: u32,

    /// Whether playback direction is reversed
    reversed: bool,

    /// Create a new animation state
    pub fn init(allocator: std.mem.Allocator) Animation {
        return .{
            .allocator = allocator,
            .clips = std.StringHashMap(AnimationClip).init(allocator),
            .current_clip = null,
            .state = .stopped,
            .current_time = 0,
            .current_frame = 0,
            .speed = 1.0,
            .event_callback = null,
            .event_user_data = null,
            .last_event_frame = std.math.maxInt(u32),
            .reversed = false,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *Animation) void {
        self.clips.deinit();
    }

    /// Add an animation clip
    pub fn addClip(self: *Animation, name: []const u8, config: struct {
        start: u32,
        end: u32,
        fps: f32 = 12.0,
        loop: bool = true,
        events: ?[]const FrameEvent = null,
    }) !void {
        const clip = AnimationClip{
            .name = name,
            .start_frame = config.start,
            .end_frame = config.end,
            .fps = config.fps,
            .loop = config.loop,
            .events = config.events,
        };
        try self.clips.put(name, clip);
    }

    /// Remove an animation clip
    pub fn removeClip(self: *Animation, name: []const u8) bool {
        // If this is the current clip, stop playback
        if (self.current_clip) |current| {
            if (std.mem.eql(u8, current.name, name)) {
                self.stop();
            }
        }
        return self.clips.remove(name);
    }

    /// Get a clip by name
    pub fn getClip(self: *const Animation, name: []const u8) ?*const AnimationClip {
        if (self.clips.getPtr(name)) |ptr| {
            return ptr;
        }
        return null;
    }

    /// Play an animation clip by name
    pub fn play(self: *Animation, name: []const u8) void {
        if (self.clips.getPtr(name)) |clip| {
            self.current_clip = clip;
            self.state = .playing;
            self.current_time = 0;
            self.current_frame = clip.start_frame;
            self.last_event_frame = std.math.maxInt(u32);
            self.reversed = false;
        }
    }

    /// Play animation in reverse
    pub fn playReversed(self: *Animation, name: []const u8) void {
        if (self.clips.getPtr(name)) |clip| {
            self.current_clip = clip;
            self.state = .playing;
            self.current_time = clip.duration();
            self.current_frame = clip.end_frame;
            self.last_event_frame = std.math.maxInt(u32);
            self.reversed = true;
        }
    }

    /// Pause the current animation
    pub fn pause(self: *Animation) void {
        if (self.state == .playing) {
            self.state = .paused;
        }
    }

    /// Resume a paused animation
    pub fn unpause(self: *Animation) void {
        if (self.state == .paused) {
            self.state = .playing;
        }
    }

    /// Stop the current animation and reset to first frame
    pub fn stop(self: *Animation) void {
        self.state = .stopped;
        self.current_time = 0;
        if (self.current_clip) |clip| {
            self.current_frame = clip.start_frame;
        }
    }

    /// Check if animation is currently playing
    pub fn isPlaying(self: *const Animation) bool {
        return self.state == .playing;
    }

    /// Check if animation is paused
    pub fn isPaused(self: *const Animation) bool {
        return self.state == .paused;
    }

    /// Check if animation is stopped
    pub fn isStopped(self: *const Animation) bool {
        return self.state == .stopped;
    }

    /// Check if a non-looping animation has finished
    pub fn isFinished(self: *const Animation) bool {
        if (self.current_clip) |clip| {
            if (!clip.loop) {
                if (self.reversed) {
                    return self.current_frame == clip.start_frame and self.state != .playing;
                } else {
                    return self.current_frame == clip.end_frame and self.state != .playing;
                }
            }
        }
        return false;
    }

    /// Get the current frame index
    pub fn getCurrentFrame(self: *const Animation) u32 {
        return self.current_frame;
    }

    /// Get the current clip name (or null if none)
    pub fn getCurrentClipName(self: *const Animation) ?[]const u8 {
        if (self.current_clip) |clip| {
            return clip.name;
        }
        return null;
    }

    /// Get normalized progress (0.0 to 1.0) within current clip
    pub fn getProgress(self: *const Animation) f32 {
        if (self.current_clip) |clip| {
            return self.current_time / clip.duration();
        }
        return 0;
    }

    /// Set playback speed (1.0 = normal, 2.0 = double speed, 0.5 = half speed)
    pub fn setSpeed(self: *Animation, speed_multiplier: f32) void {
        self.speed = @max(0.0, speed_multiplier);
    }

    /// Set event callback
    pub fn setEventCallback(self: *Animation, callback: EventCallback, user_data: ?*anyopaque) void {
        self.event_callback = callback;
        self.event_user_data = user_data;
    }

    /// Clear event callback
    pub fn clearEventCallback(self: *Animation) void {
        self.event_callback = null;
        self.event_user_data = null;
    }

    /// Update the animation (call once per frame)
    pub fn update(self: *Animation, delta_time: f32) void {
        if (self.state != .playing) return;

        const clip = self.current_clip orelse return;

        // Advance time
        const time_delta = delta_time * self.speed;
        if (self.reversed) {
            self.current_time -= time_delta;
        } else {
            self.current_time += time_delta;
        }

        const clip_duration = clip.duration();
        const frame_count = clip.frameCount();

        // Handle looping and bounds
        if (self.reversed) {
            if (self.current_time < 0) {
                if (clip.loop) {
                    // Wrap around
                    self.current_time = @mod(self.current_time, clip_duration) + clip_duration;
                } else {
                    // Stop at beginning
                    self.current_time = 0;
                    self.current_frame = clip.start_frame;
                    self.state = .stopped;
                    return;
                }
            }
        } else {
            if (self.current_time >= clip_duration) {
                if (clip.loop) {
                    // Wrap around
                    self.current_time = @mod(self.current_time, clip_duration);
                } else {
                    // Stop at end
                    self.current_time = clip_duration;
                    self.current_frame = clip.end_frame;
                    self.state = .stopped;
                    return;
                }
            }
        }

        // Calculate current frame
        const frame_time = 1.0 / clip.fps;
        const frame_offset: u32 = @intFromFloat(@floor(self.current_time / frame_time));
        self.current_frame = clip.start_frame + @min(frame_offset, frame_count - 1);

        // Process events for the current frame
        self.processEvents();
    }

    /// Process frame events
    fn processEvents(self: *Animation) void {
        if (self.event_callback == null) return;

        const clip = self.current_clip orelse return;
        const events = clip.events orelse return;

        // Calculate frame index relative to clip start
        const relative_frame = self.current_frame - clip.start_frame;

        // Only process if frame changed
        if (relative_frame == self.last_event_frame) return;
        self.last_event_frame = relative_frame;

        // Check for events on this frame
        for (events) |event| {
            if (event.frame == relative_frame) {
                if (self.event_callback) |callback| {
                    callback(event.name, self.event_user_data);
                }
            }
        }
    }

    /// Jump to a specific frame within the current clip
    pub fn setFrame(self: *Animation, frame: u32) void {
        if (self.current_clip) |clip| {
            self.current_frame = std.math.clamp(frame, clip.start_frame, clip.end_frame);
            const relative_frame = self.current_frame - clip.start_frame;
            self.current_time = @as(f32, @floatFromInt(relative_frame)) / clip.fps;
        }
    }

    /// Set progress within current clip (0.0 to 1.0)
    pub fn setProgress(self: *Animation, progress: f32) void {
        if (self.current_clip) |clip| {
            const clamped_progress = std.math.clamp(progress, 0.0, 1.0);
            self.current_time = clamped_progress * clip.duration();
            const frame_offset: u32 = @intFromFloat(@floor(clamped_progress * @as(f32, @floatFromInt(clip.frameCount()))));
            self.current_frame = clip.start_frame + @min(frame_offset, clip.frameCount() - 1);
        }
    }
};

/// Animation state machine for managing transitions between animations
pub const AnimationStateMachine = struct {
    allocator: std.mem.Allocator,

    /// The underlying animation
    animation: Animation,

    /// State transitions (from_state -> list of transitions)
    transitions: std.StringHashMap(std.ArrayList(Transition)),

    /// Current state name
    current_state: ?[]const u8,

    /// Transition in progress
    active_transition: ?ActiveTransition,

    /// Create a new animation state machine
    pub fn init(allocator: std.mem.Allocator) AnimationStateMachine {
        return .{
            .allocator = allocator,
            .animation = Animation.init(allocator),
            .transitions = std.StringHashMap(std.ArrayList(Transition)).init(allocator),
            .current_state = null,
            .active_transition = null,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *AnimationStateMachine) void {
        var iter = self.transitions.valueIterator();
        while (iter.next()) |list| {
            list.deinit();
        }
        self.transitions.deinit();
        self.animation.deinit();
    }

    /// Add an animation clip (delegates to Animation)
    pub fn addClip(self: *AnimationStateMachine, name: []const u8, config: struct {
        start: u32,
        end: u32,
        fps: f32 = 12.0,
        loop: bool = true,
        events: ?[]const FrameEvent = null,
    }) !void {
        try self.animation.addClip(name, config);
    }

    /// Add a transition between states
    pub fn addTransition(self: *AnimationStateMachine, from: []const u8, to: []const u8, config: struct {
        /// Condition function (returns true to trigger transition)
        condition: ?*const fn (user_data: ?*anyopaque) bool = null,
        /// User data passed to condition function
        user_data: ?*anyopaque = null,
        /// Duration of cross-fade blend (0 = instant)
        blend_duration: f32 = 0,
        /// Auto-trigger when source animation finishes
        on_finish: bool = false,
    }) !void {
        const transition = Transition{
            .to_state = to,
            .condition = config.condition,
            .user_data = config.user_data,
            .blend_duration = config.blend_duration,
            .on_finish = config.on_finish,
        };

        const result = try self.transitions.getOrPut(from);
        if (!result.found_existing) {
            result.value_ptr.* = std.ArrayList(Transition).init(self.allocator);
        }
        try result.value_ptr.append(transition);
    }

    /// Set the current state (plays the animation)
    pub fn setState(self: *AnimationStateMachine, state: []const u8) void {
        self.current_state = state;
        self.animation.play(state);
        self.active_transition = null;
    }

    /// Trigger a transition to a new state
    pub fn transitionTo(self: *AnimationStateMachine, state: []const u8, blend_duration: f32) void {
        if (blend_duration > 0 and self.current_state != null) {
            self.active_transition = .{
                .from_state = self.current_state.?,
                .to_state = state,
                .duration = blend_duration,
                .elapsed = 0,
                .from_frame = self.animation.getCurrentFrame(),
            };
        }
        self.current_state = state;
        self.animation.play(state);
    }

    /// Update the state machine (call once per frame)
    pub fn update(self: *AnimationStateMachine, delta_time: f32) void {
        // Update active transition
        if (self.active_transition) |*transition| {
            transition.elapsed += delta_time;
            if (transition.elapsed >= transition.duration) {
                self.active_transition = null;
            }
        }

        // Check transitions
        if (self.current_state) |state| {
            if (self.transitions.get(state)) |trans_list| {
                for (trans_list.items) |transition| {
                    var should_transition = false;

                    // Check condition
                    if (transition.condition) |cond| {
                        if (cond(transition.user_data)) {
                            should_transition = true;
                        }
                    }

                    // Check on_finish
                    if (transition.on_finish and self.animation.isFinished()) {
                        should_transition = true;
                    }

                    if (should_transition) {
                        self.transitionTo(transition.to_state, transition.blend_duration);
                        break;
                    }
                }
            }
        }

        // Update animation
        self.animation.update(delta_time);
    }

    /// Get the current frame (for rendering)
    pub fn getCurrentFrame(self: *const AnimationStateMachine) u32 {
        return self.animation.getCurrentFrame();
    }

    /// Get blend progress if transitioning (0.0 to 1.0, null if not blending)
    pub fn getBlendProgress(self: *const AnimationStateMachine) ?f32 {
        if (self.active_transition) |transition| {
            return transition.elapsed / transition.duration;
        }
        return null;
    }

    /// Get the from-frame during a blend transition
    pub fn getBlendFromFrame(self: *const AnimationStateMachine) ?u32 {
        if (self.active_transition) |transition| {
            return transition.from_frame;
        }
        return null;
    }

    /// Get the underlying animation for direct access
    pub fn getAnimation(self: *AnimationStateMachine) *Animation {
        return &self.animation;
    }
};

/// Transition definition
const Transition = struct {
    to_state: []const u8,
    condition: ?*const fn (user_data: ?*anyopaque) bool,
    user_data: ?*anyopaque,
    blend_duration: f32,
    on_finish: bool,
};

/// Active transition state
const ActiveTransition = struct {
    from_state: []const u8,
    to_state: []const u8,
    duration: f32,
    elapsed: f32,
    from_frame: u32,
};

// ============================================================================
// Tests
// ============================================================================

test "animation - AnimationClip basics" {
    const clip = AnimationClip{
        .name = "walk",
        .start_frame = 0,
        .end_frame = 7,
        .fps = 8.0,
        .loop = true,
    };

    try std.testing.expectEqual(@as(u32, 8), clip.frameCount());
    try std.testing.expectApproxEqRel(@as(f32, 1.0), clip.duration(), 0.0001);
}

test "animation - Animation init and deinit" {
    var anim = Animation.init(std.testing.allocator);
    defer anim.deinit();

    try std.testing.expect(anim.current_clip == null);
    try std.testing.expectEqual(PlaybackState.stopped, anim.state);
    try std.testing.expectEqual(@as(f32, 1.0), anim.speed);
}

test "animation - add and get clips" {
    var anim = Animation.init(std.testing.allocator);
    defer anim.deinit();

    try anim.addClip("idle", .{ .start = 0, .end = 3, .fps = 8.0, .loop = true });
    try anim.addClip("walk", .{ .start = 4, .end = 11, .fps = 12.0, .loop = true });
    try anim.addClip("attack", .{ .start = 12, .end = 17, .fps = 15.0, .loop = false });

    const idle = anim.getClip("idle");
    try std.testing.expect(idle != null);
    try std.testing.expectEqual(@as(u32, 0), idle.?.start_frame);
    try std.testing.expectEqual(@as(u32, 3), idle.?.end_frame);

    const walk = anim.getClip("walk");
    try std.testing.expect(walk != null);
    try std.testing.expectEqual(@as(u32, 4), walk.?.start_frame);

    const none = anim.getClip("nonexistent");
    try std.testing.expect(none == null);
}

test "animation - play and stop" {
    var anim = Animation.init(std.testing.allocator);
    defer anim.deinit();

    try anim.addClip("idle", .{ .start = 0, .end = 3, .fps = 8.0, .loop = true });

    try std.testing.expect(anim.isStopped());

    anim.play("idle");
    try std.testing.expect(anim.isPlaying());
    try std.testing.expect(!anim.isStopped());
    try std.testing.expectEqual(@as(u32, 0), anim.getCurrentFrame());
    try std.testing.expectEqualStrings("idle", anim.getCurrentClipName().?);

    anim.stop();
    try std.testing.expect(anim.isStopped());
}

test "animation - pause and resume" {
    var anim = Animation.init(std.testing.allocator);
    defer anim.deinit();

    try anim.addClip("walk", .{ .start = 0, .end = 7, .fps = 8.0, .loop = true });

    anim.play("walk");
    anim.update(0.1); // Advance a bit

    anim.pause();
    try std.testing.expect(anim.isPaused());

    const frame_before = anim.getCurrentFrame();
    anim.update(0.1); // Should not advance while paused
    try std.testing.expectEqual(frame_before, anim.getCurrentFrame());

    anim.unpause();
    try std.testing.expect(anim.isPlaying());
}

test "animation - update advances frames" {
    var anim = Animation.init(std.testing.allocator);
    defer anim.deinit();

    // 8 fps = 0.125s per frame
    try anim.addClip("walk", .{ .start = 0, .end = 7, .fps = 8.0, .loop = true });

    anim.play("walk");
    try std.testing.expectEqual(@as(u32, 0), anim.getCurrentFrame());

    anim.update(0.125); // Advance one frame
    try std.testing.expectEqual(@as(u32, 1), anim.getCurrentFrame());

    anim.update(0.125); // Advance another frame
    try std.testing.expectEqual(@as(u32, 2), anim.getCurrentFrame());
}

test "animation - looping" {
    var anim = Animation.init(std.testing.allocator);
    defer anim.deinit();

    // 4 frames at 4 fps = 1 second per loop
    try anim.addClip("loop", .{ .start = 0, .end = 3, .fps = 4.0, .loop = true });

    anim.play("loop");

    // Run for more than one loop
    anim.update(1.25); // Should be at frame 1 of second loop

    try std.testing.expect(anim.isPlaying());
    try std.testing.expectEqual(@as(u32, 1), anim.getCurrentFrame());
}

test "animation - non-looping stops at end" {
    var anim = Animation.init(std.testing.allocator);
    defer anim.deinit();

    // 4 frames at 4 fps = 1 second
    try anim.addClip("attack", .{ .start = 10, .end = 13, .fps = 4.0, .loop = false });

    anim.play("attack");
    try std.testing.expect(!anim.isFinished());

    // Run past the end
    anim.update(2.0);

    try std.testing.expect(anim.isStopped());
    try std.testing.expect(anim.isFinished());
    try std.testing.expectEqual(@as(u32, 13), anim.getCurrentFrame()); // Should be at end frame
}

test "animation - playback speed" {
    var anim = Animation.init(std.testing.allocator);
    defer anim.deinit();

    try anim.addClip("walk", .{ .start = 0, .end = 7, .fps = 8.0, .loop = true });

    anim.play("walk");
    anim.setSpeed(2.0); // Double speed

    // At 2x speed, 0.0625s should advance one frame (normally 0.125s)
    anim.update(0.0625);
    try std.testing.expectEqual(@as(u32, 1), anim.getCurrentFrame());
}

test "animation - reversed playback" {
    var anim = Animation.init(std.testing.allocator);
    defer anim.deinit();

    try anim.addClip("walk", .{ .start = 0, .end = 3, .fps = 4.0, .loop = false });

    anim.playReversed("walk");
    try std.testing.expectEqual(@as(u32, 3), anim.getCurrentFrame()); // Start at end

    anim.update(0.25); // Move back one frame
    try std.testing.expectEqual(@as(u32, 2), anim.getCurrentFrame());

    // Continue to beginning and stop
    anim.update(1.0);
    try std.testing.expect(anim.isStopped());
    try std.testing.expectEqual(@as(u32, 0), anim.getCurrentFrame());
}

test "animation - setFrame and setProgress" {
    var anim = Animation.init(std.testing.allocator);
    defer anim.deinit();

    try anim.addClip("walk", .{ .start = 10, .end = 17, .fps = 8.0, .loop = true });

    anim.play("walk");

    anim.setFrame(14);
    try std.testing.expectEqual(@as(u32, 14), anim.getCurrentFrame());

    // Clamp to valid range
    anim.setFrame(100);
    try std.testing.expectEqual(@as(u32, 17), anim.getCurrentFrame());

    anim.setProgress(0.5); // Middle of clip
    try std.testing.expectEqual(@as(u32, 14), anim.getCurrentFrame()); // 10 + 4 = 14
}

test "animation - getProgress" {
    var anim = Animation.init(std.testing.allocator);
    defer anim.deinit();

    // 4 frames at 4 fps = 1 second
    try anim.addClip("walk", .{ .start = 0, .end = 3, .fps = 4.0, .loop = true });

    anim.play("walk");
    try std.testing.expectApproxEqRel(@as(f32, 0.0), anim.getProgress(), 0.01);

    anim.update(0.5);
    try std.testing.expectApproxEqRel(@as(f32, 0.5), anim.getProgress(), 0.01);
}

test "animation - removeClip" {
    var anim = Animation.init(std.testing.allocator);
    defer anim.deinit();

    try anim.addClip("idle", .{ .start = 0, .end = 3, .fps = 8.0, .loop = true });

    anim.play("idle");
    try std.testing.expect(anim.isPlaying());

    const removed = anim.removeClip("idle");
    try std.testing.expect(removed);
    try std.testing.expect(anim.isStopped()); // Should stop when current clip is removed

    const removed_again = anim.removeClip("idle");
    try std.testing.expect(!removed_again);
}

test "animation - event callbacks" {
    var anim = Animation.init(std.testing.allocator);
    defer anim.deinit();

    const events = [_]FrameEvent{
        .{ .frame = 0, .name = "start" },
        .{ .frame = 2, .name = "footstep" },
    };

    try anim.addClip("walk", .{
        .start = 0,
        .end = 3,
        .fps = 4.0,
        .loop = true,
        .events = &events,
    });

    var event_count: u32 = 0;
    const callback = struct {
        fn cb(_: []const u8, user_data: ?*anyopaque) void {
            const count: *u32 = @ptrCast(@alignCast(user_data.?));
            count.* += 1;
        }
    }.cb;

    anim.setEventCallback(callback, &event_count);
    anim.play("walk");

    // Frame 0 - "start" event
    anim.update(0.001);
    try std.testing.expectEqual(@as(u32, 1), event_count);

    // Frame 2 - "footstep" event (at 0.5s = 2 frames)
    anim.update(0.5);
    try std.testing.expectEqual(@as(u32, 2), event_count);
}

test "animation - state machine basic" {
    var sm = AnimationStateMachine.init(std.testing.allocator);
    defer sm.deinit();

    try sm.addClip("idle", .{ .start = 0, .end = 3, .fps = 8.0, .loop = true });
    try sm.addClip("walk", .{ .start = 4, .end = 11, .fps = 12.0, .loop = true });

    sm.setState("idle");
    try std.testing.expectEqual(@as(u32, 0), sm.getCurrentFrame());

    sm.update(0.1);
    try std.testing.expect(sm.animation.isPlaying());
}

test "animation - state machine transitions" {
    var sm = AnimationStateMachine.init(std.testing.allocator);
    defer sm.deinit();

    try sm.addClip("idle", .{ .start = 0, .end = 3, .fps = 8.0, .loop = true });
    try sm.addClip("walk", .{ .start = 4, .end = 11, .fps = 12.0, .loop = true });

    // Add manual transition
    sm.setState("idle");
    sm.transitionTo("walk", 0);

    try std.testing.expectEqualStrings("walk", sm.current_state.?);
}

test "animation - state machine on_finish transition" {
    var sm = AnimationStateMachine.init(std.testing.allocator);
    defer sm.deinit();

    try sm.addClip("attack", .{ .start = 0, .end = 3, .fps = 4.0, .loop = false });
    try sm.addClip("idle", .{ .start = 4, .end = 7, .fps = 8.0, .loop = true });

    try sm.addTransition("attack", "idle", .{ .on_finish = true });

    sm.setState("attack");

    // Run until attack finishes
    sm.update(2.0);

    // Should have transitioned to idle
    try std.testing.expectEqualStrings("idle", sm.current_state.?);
}

test "animation - state machine blend progress" {
    var sm = AnimationStateMachine.init(std.testing.allocator);
    defer sm.deinit();

    try sm.addClip("idle", .{ .start = 0, .end = 3, .fps = 8.0, .loop = true });
    try sm.addClip("walk", .{ .start = 4, .end = 11, .fps = 12.0, .loop = true });

    sm.setState("idle");
    sm.update(0.1);

    // Start transition with blend
    sm.transitionTo("walk", 0.5);

    // Check blend progress
    const progress = sm.getBlendProgress();
    try std.testing.expect(progress != null);
    try std.testing.expectApproxEqRel(@as(f32, 0.0), progress.?, 0.01);

    // After some time
    sm.update(0.25);
    const progress2 = sm.getBlendProgress();
    try std.testing.expect(progress2 != null);
    try std.testing.expectApproxEqRel(@as(f32, 0.5), progress2.?, 0.01);

    // After blend completes
    sm.update(0.5);
    const progress3 = sm.getBlendProgress();
    try std.testing.expect(progress3 == null);
}
