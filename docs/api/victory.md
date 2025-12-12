# Victory Conditions System

Win/lose state management with multiple victory types and progress tracking.

## Overview

The Victory Conditions system provides:
- Multiple victory condition types
- Custom condition callbacks
- Per-player progress tracking
- Player elimination handling
- Turn limits and scoring
- Victory/elimination notifications
- Built-in common conditions

## Quick Start

```zig
const victory = @import("AgentiteZ").victory;

var vm = victory.VictoryManager.init(allocator, .{ .player_count = 4 });
defer vm.deinit();

// Add domination victory (last player standing)
try vm.addCondition(victory.dominationCondition());

// Add custom victory condition
try vm.addCondition(.{
    .id = "wonder",
    .name = "Wonder Victory",
    .check_fn = checkWonderComplete,
    .progress_fn = getWonderProgress,
    .min_turn = 50,
});

// Game loop
vm.setTurn(current_turn);

if (vm.checkVictory(&game_state)) |result| {
    std.debug.print("Player {d} wins via {s}!\n", .{ result.winner, result.condition_id });
}
```

## API Reference

### VictoryManager

Main manager for victory conditions.

#### Initialization

```zig
pub fn init(allocator: std.mem.Allocator, config: VictoryConfig) VictoryManager
pub fn deinit(self: *VictoryManager) void
```

#### Condition Management

```zig
pub fn addCondition(self: *VictoryManager, condition: VictoryCondition) !void
pub fn removeCondition(self: *VictoryManager, id: []const u8) bool
pub fn setConditionEnabled(self: *VictoryManager, id: []const u8, enabled: bool) bool
pub fn isConditionEnabled(self: *const VictoryManager, id: []const u8) bool
pub fn getConditionCount(self: *const VictoryManager) usize
pub fn getConditionInfo(self: *const VictoryManager, id: []const u8) ?ConditionInfo
pub fn getEnabledConditions(self: *const VictoryManager, allocator: std.mem.Allocator) ![][]const u8
```

#### Player State

```zig
pub fn eliminatePlayer(self: *VictoryManager, player_id: u8) void
pub fn surrender(self: *VictoryManager, player_id: u8) void
pub fn getPlayerState(self: *const VictoryManager, player_id: u8) PlayerState
pub fn isPlayerActive(self: *const VictoryManager, player_id: u8) bool
pub fn getActivePlayerCount(self: *const VictoryManager) u8
```

#### Victory Checking

```zig
pub fn checkVictory(self: *VictoryManager, user_data: ?*anyopaque) ?VictoryResult
pub fn isGameOver(self: *const VictoryManager) bool
pub fn getVictoryResult(self: *const VictoryManager) ?VictoryResult
```

#### Progress

```zig
pub fn getProgress(self: *VictoryManager, condition_id: []const u8, player_id: u8, user_data: ?*anyopaque) f32
pub fn setTurn(self: *VictoryManager, turn: u32) void
```

#### Callbacks

```zig
pub fn setOnVictory(self: *VictoryManager, callback: ?*const fn (VictoryResult, ?*anyopaque) void, ctx: ?*anyopaque) void
pub fn setOnElimination(self: *VictoryManager, callback: ?*const fn (u8, ?*anyopaque) void, ctx: ?*anyopaque) void
```

#### Control

```zig
pub fn reset(self: *VictoryManager) void
pub fn forceVictory(self: *VictoryManager, player_id: u8, condition_id: []const u8) VictoryResult
```

### VictoryConfig

```zig
pub const VictoryConfig = struct {
    player_count: u8 = 2,       // Number of players
    turn_limit: u32 = 0,        // 0 = no limit
    auto_check: bool = true,    // Check conditions automatically
    allow_draw: bool = false,   // Allow multiple winners
};
```

### VictoryCondition

```zig
pub const VictoryCondition = struct {
    id: []const u8,
    name: ?[]const u8 = null,
    description: ?[]const u8 = null,
    victory_type: VictoryType = .custom,
    check_fn: VictoryCheckFn,
    progress_fn: ?ProgressCheckFn = null,
    message_format: ?[]const u8 = null,
    enabled: bool = true,
    priority: i32 = 0,           // Lower = checked first
    min_turn: u32 = 0,           // Earliest turn this can trigger
    allow_shared: bool = false,  // Multiple winners allowed
};
```

### VictoryType

```zig
pub const VictoryType = enum {
    domination,     // Eliminate all opponents
    conquest,       // Control majority of map
    economic,       // Accumulate resources
    technological,  // Research ultimate tech
    wonder,         // Complete wonder/project
    score,          // Highest score at time limit
    survival,       // Survive until turn limit
    objectives,     // Complete specific objectives
    custom,         // User-defined
};
```

### VictoryResult

```zig
pub const VictoryResult = struct {
    winner: u8,
    condition_id: []const u8,
    victory_type: VictoryType,
    message: ?[]const u8,
};
```

### PlayerState

```zig
pub const PlayerState = enum {
    active,
    eliminated,
    victorious,
    surrendered,
};
```

### GameContext

Context passed to check functions:

```zig
pub const GameContext = struct {
    turn: u32,
    active_players: u8,
    eliminated: [MAX_PLAYERS]bool,
    scores: [MAX_PLAYERS]i64,
    user_data: ?*anyopaque,
};
```

## Examples

### Custom Victory Condition

```zig
fn checkWonderComplete(player_id: u8, ctx: *const GameContext) bool {
    const game: *Game = @ptrCast(@alignCast(ctx.user_data));
    return game.players[player_id].wonder_progress >= 100;
}

fn getWonderProgress(player_id: u8, ctx: *const GameContext) f32 {
    const game: *Game = @ptrCast(@alignCast(ctx.user_data));
    return @as(f32, @floatFromInt(game.players[player_id].wonder_progress)) / 100.0;
}

try vm.addCondition(.{
    .id = "wonder",
    .name = "Wonder Victory",
    .description = "Complete your civilization's wonder",
    .victory_type = .wonder,
    .check_fn = checkWonderComplete,
    .progress_fn = getWonderProgress,
    .min_turn = 50,
});
```

### Priority-Based Checking

```zig
// Higher priority conditions checked first
try vm.addCondition(.{
    .id = "instant_win",
    .check_fn = checkInstantWin,
    .priority = 1,  // Checked first
});

try vm.addCondition(.{
    .id = "domination",
    .check_fn = checkDomination,
    .priority = 100,  // Checked last
});
```

### Time-Limited Game

```zig
var vm = VictoryManager.init(allocator, .{
    .player_count = 4,
    .turn_limit = 200,  // Game ends at turn 200
});

// At turn limit, player with highest score wins
```

### Victory Callback

```zig
vm.setOnVictory(struct {
    fn callback(result: VictoryResult, ctx: ?*anyopaque) void {
        const game: *Game = @ptrCast(@alignCast(ctx));
        game.showVictoryScreen(result.winner, result.message);
    }
}.callback, game);
```

### Elimination Tracking

```zig
vm.setOnElimination(struct {
    fn callback(player_id: u8, ctx: ?*anyopaque) void {
        const game: *Game = @ptrCast(@alignCast(ctx));
        game.removePlayer(player_id);
        game.showMessage("Player {d} has been eliminated!", .{player_id});
    }
}.callback, game);

// When a player loses all units/bases
vm.eliminatePlayer(losing_player);
```

### Progress Display

```zig
for (0..player_count) |player| {
    const progress = vm.getProgress("wonder", @intCast(player), &game);
    ui.drawProgressBar(player, "Wonder", progress);
}
```

## Built-in Conditions

### dominationCondition()

Last player standing wins. Automatically detects when only one player remains.

```zig
try vm.addCondition(victory.dominationCondition());
```

### scoreCondition(required_score)

Win by reaching a score threshold. Provides progress tracking.

```zig
try vm.addCondition(victory.scoreCondition(10000));
```

## Test Coverage

20 tests covering:
- Basic initialization
- Adding/removing conditions
- Last player standing
- Custom conditions
- Min turn requirements
- Enable/disable conditions
- Turn limits
- Player states
- Victory callbacks
- Elimination callbacks
- Reset functionality
- Condition priority
- Progress functions
- Force victory
