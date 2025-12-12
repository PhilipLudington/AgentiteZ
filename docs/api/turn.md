# Turn Manager

Turn-based game flow control with configurable phases (`src/turn.zig`).

## Features

- **Generic phase types** - Works with any enum for phases
- **Configurable phase ordering** - Add, remove, insert phases dynamically
- **Phase callbacks** - Register handlers for each phase with context
- **Turn lifecycle callbacks** - on_turn_start, on_turn_end, on_phase_start, on_phase_end
- **Progress tracking** - Get current phase and progress for UI
- **Error handling** - Phase failures with optional continue-on-failure
- **Phase timing** - Optional profiling of phase duration
- **Turn modes** - Sequential, simultaneous, real-time-with-pause

## Usage

### Basic Turn Processing

```zig
const turn = @import("AgentiteZ").turn;

const Phase = enum { upkeep, main, combat, end };

var manager = turn.TurnManager(Phase).init(allocator);
defer manager.deinit();

try manager.setPhaseOrder(&.{ .upkeep, .main, .combat, .end });

const result = manager.processTurn();
if (result.success) {
    std.debug.print("Turn {} completed ({} phases)\n",
        .{result.turn_number, result.phases_completed});
}
```

### Phase Callbacks

```zig
const GameState = struct {
    resources: i32 = 0,

    fn upkeepPhase(_: Phase, ctx: ?*anyopaque) turn.PhaseResult {
        const state: *GameState = @ptrCast(@alignCast(ctx.?));
        state.resources += 100;
        return .{ .success = true };
    }

    fn combatPhase(_: Phase, _: ?*anyopaque) turn.PhaseResult {
        return .{ .success = true };
    }
};

var game = GameState{};
try manager.registerPhase(.upkeep, GameState.upkeepPhase, &game);
try manager.registerPhase(.combat, GameState.combatPhase, &game);

_ = manager.processTurn();
```

### Turn Lifecycle Callbacks

```zig
const Callbacks = struct {
    fn onTurnStart(turn_num: u32, ctx: ?*anyopaque) void {
        const game: *Game = @ptrCast(@alignCast(ctx.?));
        game.log("Turn {} started", .{turn_num});
    }

    fn onTurnEnd(turn_num: u32, ctx: ?*anyopaque) void {
        const game: *Game = @ptrCast(@alignCast(ctx.?));
        game.autosave();
    }

    fn onPhaseStart(phase: Phase, ctx: ?*anyopaque) void {
        const game: *Game = @ptrCast(@alignCast(ctx.?));
        game.ui.showPhase(@tagName(phase));
    }

    fn onPhaseEnd(phase: Phase, result: turn.PhaseResult, _: ?*anyopaque) void {
        if (!result.success) {
            std.log.warn("Phase {s} failed", .{@tagName(phase)});
        }
    }
};

manager.setCallbacks(
    Callbacks.onTurnStart,
    Callbacks.onTurnEnd,
    Callbacks.onPhaseStart,
    Callbacks.onPhaseEnd,
    &game,
);
```

### Error Handling

```zig
// Stop on first failure (default)
var manager = turn.TurnManager(Phase).init(allocator);

// Or continue processing after failures
var manager = turn.TurnManager(Phase).initWithConfig(allocator, .{
    .continue_on_failure = true,
});

// Phase can signal to skip remaining phases
fn victoryCheckPhase(_: Phase, ctx: ?*anyopaque) turn.PhaseResult {
    const game: *Game = @ptrCast(@alignCast(ctx.?));
    if (game.checkVictory()) {
        return .{ .success = true, .skip_remaining = true };
    }
    return .{ .success = true };
}
```

### Progress and State

```zig
const current_turn = manager.getTurnNumber();
const progress = manager.getProgress();  // 0.0 to 1.0
const current_phase = manager.getCurrentPhase();

if (manager.hasPhaseCompleted(.combat)) {
    // Combat already resolved this turn
}

_ = manager.nextTurn();  // Increment without processing
manager.reset();
manager.setTurnNumber(saved_turn);
```

### Profiling

```zig
var manager = turn.TurnManager(Phase).initWithConfig(allocator, .{
    .profiling_enabled = true,
});

const result = manager.processTurn();
std.debug.print("Turn took {d}ms\n", .{result.total_duration_ns / 1_000_000});
```

## Data Structures

- `TurnManager(PhaseType)` - Generic manager parameterized by phase enum
- `PhaseResult` - Result of a single phase (success, error_message, duration_ns, skip_remaining)
- `TurnResult(PhaseType)` - Result of a complete turn
- `TurnManagerConfig` - Configuration (profiling, continue_on_failure, turn_mode)
- `TurnMode` - sequential, simultaneous, real_time_with_pause

## Key Methods

- `setPhaseOrder(phases)` - Set phase execution order
- `addPhase(phase)` / `insertPhase(index, phase)` / `removePhase(phase)` - Modify order
- `registerPhase(phase, callback, context)` - Register phase handler
- `processTurn()` - Process all phases and return result
- `processPhase(phase)` - Process single phase
- `nextTurn()` - Advance turn number without processing
- `getTurnNumber()` / `getCurrentPhase()` / `getProgress()` - Query state
- `hasPhaseCompleted(phase)` - Check if phase ran this turn
- `setCallbacks(...)` - Set lifecycle callbacks
- `reset()` - Reset to turn 0

## Tests

22 comprehensive tests covering phase ordering, callbacks, error handling, skip_remaining, progress tracking, profiling, and edge cases.
