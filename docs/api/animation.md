# Animation System

Frame-based sprite animation system (`src/animation.zig`).

## Features

- **Animation clips** - Define animations by frame range, fps, and loop settings
- **Playback controls** - Play, pause, unpause, stop, reverse playback
- **Playback speed** - Variable speed multiplier (slow motion, fast forward)
- **Frame events** - Callbacks triggered at specific frames (footsteps, impacts)
- **Progress tracking** - Get current frame, progress (0-1), finished state
- **State machine** - Automatic transitions between animations with conditions
- **Blend transitions** - Cross-fade between animations

## Usage

### Basic Animation

```zig
const animation = @import("AgentiteZ").animation;

// Create animation state
var anim = animation.Animation.init(allocator);
defer anim.deinit();

// Define clips (frame indices in sprite sheet)
try anim.addClip("idle", .{ .start = 0, .end = 3, .fps = 8, .loop = true });
try anim.addClip("walk", .{ .start = 4, .end = 11, .fps = 12, .loop = true });
try anim.addClip("attack", .{ .start = 12, .end = 17, .fps = 15, .loop = false });

// Play animation
anim.play("idle");

// Update each frame
anim.update(delta_time);

// Get current frame for rendering
const frame = anim.getCurrentFrame();

// Playback controls
anim.pause();
anim.unpause();
anim.stop();
anim.playReversed("walk");

// Speed control
anim.setSpeed(2.0);  // 2x speed
anim.setSpeed(0.5);  // Half speed

// Check state
if (anim.isFinished()) {
    // Non-looping animation completed
}
const progress = anim.getProgress();  // 0.0 to 1.0
```

### Frame Events

```zig
const events = [_]animation.FrameEvent{
    .{ .frame = 0, .name = "start" },
    .{ .frame = 4, .name = "footstep_left" },
    .{ .frame = 8, .name = "footstep_right" },
};

try anim.addClip("walk", .{
    .start = 0,
    .end = 11,
    .fps = 12,
    .loop = true,
    .events = &events,
});

// Set callback for events
anim.setEventCallback(onAnimationEvent, user_data);

fn onAnimationEvent(event_name: []const u8, user_data: ?*anyopaque) void {
    if (std.mem.eql(u8, event_name, "footstep_left")) {
        // Play footstep sound
    }
}
```

### State Machine

```zig
var sm = animation.AnimationStateMachine.init(allocator);
defer sm.deinit();

// Add clips
try sm.addClip("idle", .{ .start = 0, .end = 3, .fps = 8, .loop = true });
try sm.addClip("walk", .{ .start = 4, .end = 11, .fps = 12, .loop = true });
try sm.addClip("attack", .{ .start = 12, .end = 17, .fps = 15, .loop = false });

// Add automatic transitions
try sm.addTransition("attack", "idle", .{
    .on_finish = true,  // Transition when attack finishes
    .blend_duration = 0.1,  // 100ms cross-fade
});

// Conditional transitions (with callback)
try sm.addTransition("idle", "walk", .{
    .condition = isMoving,
    .user_data = &player,
});

// Set initial state
sm.setState("idle");

// Update each frame
sm.update(delta_time);

// Manual transition
sm.transitionTo("attack", 0.05);  // 50ms blend

// Get current frame for rendering
const frame = sm.getCurrentFrame();

// During blend transitions
if (sm.getBlendProgress()) |progress| {
    const from_frame = sm.getBlendFromFrame().?;
    // Blend between from_frame and getCurrentFrame() by progress
}
```

## Data Structures

- `Animation` - Animation state with clips, playback, and events
- `AnimationClip` - Clip definition (name, start/end frame, fps, loop, events)
- `AnimationStateMachine` - State machine for automatic transitions
- `FrameEvent` - Event triggered at specific frame
- `PlaybackState` - stopped, playing, paused

## Tests

20 comprehensive tests covering clips, playback, looping, events, and state machine.
