# Game Speed System

Game speed and timing control system (`src/game_speed.zig`).

## Features

- **Multiple speed settings** - Pause, slow (0.5x), normal (1x), fast (2x), very fast (4x)
- **Pause functionality** - Pause game time while real time continues
- **Per-system speed scaling** - Systems choose whether to use game time or real time
- **Preset and custom speeds** - Built-in presets plus custom multiplier values
- **Time tracking** - Both game time (scaled) and real time (unscaled)
- **UI widget** - Speed control widget with pause button and preset selection

## Usage

### Basic Setup

```zig
const engine = @import("AgentiteZ");
const GameSpeed = engine.game_speed.GameSpeed;

// Create with default settings (1x speed, not paused)
var speed = GameSpeed.init(.{});

// Or with custom settings
var speed = GameSpeed.init(.{
    .initial_speed = 2.0,   // Start at 2x speed
    .min_speed = 0.0,       // Allow pause (0x)
    .max_speed = 10.0,      // Cap at 10x
    .start_paused = false,
});
```

### Main Loop Integration

```zig
// Calculate raw delta time as usual
const raw_delta = @as(f32, @floatFromInt(current_time - last_time)) / 1000.0;

// Update game speed (calculates scaled delta)
speed.update(raw_delta);

// Game systems use scaled time (respects pause and speed)
tween_manager.update(speed.getGameDelta());
animation.update(speed.getGameDelta());
rate_tracker.update(speed.getGameDelta(), ...);

// UI systems use real time (always runs, even when paused)
ui_tween_manager.update(speed.getRealDelta());
```

### Pause Control

```zig
// Toggle pause
speed.togglePause();

// Explicit pause/unpause (unpause restores previous speed)
speed.pause();
speed.unpause();

// Check pause state
if (speed.isPaused()) {
    // Show pause overlay
}
```

### Speed Presets

```zig
const SpeedPreset = engine.game_speed.SpeedPreset;

// Set preset speed
speed.setPreset(.slow);      // 0.5x
speed.setPreset(.normal);    // 1x
speed.setPreset(.fast);      // 2x
speed.setPreset(.very_fast); // 4x
speed.setPreset(.pause);     // 0x (pauses)

// Cycle through presets (skips pause)
speed.cycleSpeed();     // normal -> fast -> very_fast -> slow -> ...
speed.cyclePrevSpeed(); // normal -> slow -> very_fast -> fast -> ...

// Get current preset (null if using custom speed)
if (speed.getCurrentPreset()) |preset| {
    const name = preset.getName(); // "Fast (2x)"
}
```

### Custom Speed

```zig
// Set arbitrary speed (clamped to min/max)
speed.setCustomSpeed(1.5);  // 1.5x speed
speed.setCustomSpeed(3.0);  // 3x speed
speed.setCustomSpeed(0.0);  // Pauses (same as setPreset(.pause))

// Get current multiplier (0 when paused)
const mult = speed.getSpeedMultiplier();
```

### Time Queries

```zig
// Delta time (per frame)
const game_dt = speed.getGameDelta();  // Scaled by speed, 0 when paused
const real_dt = speed.getRealDelta();  // Always raw delta

// Total accumulated time
const game_time = speed.getGameTime(); // Total game time (f64)
const real_time = speed.getRealTime(); // Total real time (f64)

// Get speed string for display
var buf: [16]u8 = undefined;
const str = speed.getSpeedString(&buf); // "2x", "Paused", "1.5x", etc.

// Reset time counters (useful for level transitions)
speed.resetTime();
```

## UI Widget

### Speed Control Widget

Full speed control with pause button and preset selection.

```zig
const ui = engine.ui;

// In UI render code
ui.speedControl(ctx, &game_speed, rect, .{
    .show_shortcuts = true,   // Show keyboard hint below
    .show_multiplier = true,  // Show "Speed: 2x" text
});

// Auto-layout version
ui.speedControlAuto(ctx, &game_speed, .{});

// Check result for changes
const result = ui.speedControl(ctx, &game_speed, rect, .{});
if (result.pause_toggled) {
    // Pause state changed
}
if (result.speed_changed) {
    // Speed preset changed
}
```

### Compact Speed Control

Minimal widget with just pause button and speed indicator.

```zig
// Compact version (pause button + speed display)
ui.speedControlCompact(ctx, &game_speed, rect);

// Auto-layout compact
ui.speedControlCompactAuto(ctx, &game_speed);
```

## API Reference

### SpeedPreset

```zig
pub const SpeedPreset = enum {
    pause,      // 0.0x
    slow,       // 0.5x
    normal,     // 1.0x
    fast,       // 2.0x
    very_fast,  // 4.0x

    pub fn getMultiplier(self) f32;
    pub fn getName(self) []const u8;       // "Fast (2x)"
    pub fn getShortName(self) []const u8;  // "2x"
    pub fn next(self) SpeedPreset;         // Cycle forward
    pub fn prev(self) SpeedPreset;         // Cycle backward

    pub const playable = [_]SpeedPreset{ .slow, .normal, .fast, .very_fast };
};
```

### GameSpeed.Config

```zig
pub const Config = struct {
    initial_speed: f32 = 1.0,   // Starting speed multiplier
    min_speed: f32 = 0.0,       // Minimum speed (0 = allow pause)
    max_speed: f32 = 10.0,      // Maximum speed cap
    start_paused: bool = false, // Start in paused state
};
```

### GameSpeed Methods

| Method | Description |
|--------|-------------|
| `init(config)` | Create new GameSpeed with config |
| `update(raw_delta)` | Update time tracking (call each frame) |
| `getGameDelta()` | Get scaled delta time (0 when paused) |
| `getRealDelta()` | Get unscaled delta time |
| `getGameTime()` | Get total game time (f64) |
| `getRealTime()` | Get total real time (f64) |
| `getSpeedMultiplier()` | Get current speed (0 when paused) |
| `isPaused()` | Check if paused |
| `pause()` | Pause (saves current speed) |
| `unpause()` | Unpause (restores previous speed) |
| `togglePause()` | Toggle pause state |
| `setPreset(preset)` | Set speed from preset |
| `setCustomSpeed(speed)` | Set custom speed value |
| `cycleSpeed()` | Cycle to next preset |
| `cyclePrevSpeed()` | Cycle to previous preset |
| `getCurrentPreset()` | Get current preset (null if custom) |
| `getSpeedString(buf)` | Get display string ("2x", "Paused") |
| `resetTime()` | Reset time counters to zero |

### SpeedControlOptions

```zig
pub const SpeedControlOptions = struct {
    show_shortcuts: bool = false,  // Show keyboard hints
    show_multiplier: bool = true,  // Show "Speed: 2x" display
};
```

### SpeedControlResult

```zig
pub const SpeedControlResult = struct {
    speed_changed: bool = false,  // Speed preset was changed
    pause_toggled: bool = false,  // Pause state was toggled
};
```
