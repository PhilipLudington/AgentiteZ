//! Victory Conditions System - Win/Lose State Management
//!
//! A flexible victory condition system for strategy games supporting multiple
//! victory types, progress tracking, and custom win conditions.
//!
//! Features:
//! - Multiple victory condition types
//! - Per-player progress tracking
//! - Custom condition callbacks
//! - Victory/defeat notifications
//! - Condition enable/disable
//! - Progress thresholds and percentages
//!
//! Usage:
//! ```zig
//! var vm = VictoryManager.init(allocator, .{ .player_count = 4 });
//! defer vm.deinit();
//!
//! try vm.addCondition(.{
//!     .id = "domination",
//!     .name = "Domination Victory",
//!     .check_fn = checkDomination,
//! });
//!
//! if (vm.checkVictory(&game_state)) |result| {
//!     // Game over: result.winner won via result.condition
//! }
//! ```

const std = @import("std");

const log = std.log.scoped(.victory);

/// Maximum number of players
pub const MAX_PLAYERS = 16;

/// Built-in victory condition types
pub const VictoryType = enum {
    /// Eliminate all opponents
    domination,
    /// Control majority of map
    conquest,
    /// Accumulate required resources
    economic,
    /// Research ultimate technology
    technological,
    /// Complete wonder/project
    wonder,
    /// Achieve highest score by time limit
    score,
    /// Survive until turn limit
    survival,
    /// Complete specific objectives
    objectives,
    /// Custom user-defined condition
    custom,
};

/// Result of a victory check
pub const VictoryResult = struct {
    /// Winning player ID
    winner: u8,
    /// Which condition was met
    condition_id: []const u8,
    /// Victory type
    victory_type: VictoryType,
    /// Human-readable victory message
    message: ?[]const u8,
};

/// Game context passed to victory check functions
pub const GameContext = struct {
    /// Current turn number
    turn: u32,
    /// Number of players still in game
    active_players: u8,
    /// Eliminated player flags
    eliminated: [MAX_PLAYERS]bool,
    /// Player scores
    scores: [MAX_PLAYERS]i64,
    /// Custom data pointer
    user_data: ?*anyopaque,
};

/// Victory check function type
/// Returns winning player ID if condition met, null otherwise
pub const VictoryCheckFn = *const fn (player_id: u8, ctx: *const GameContext) bool;

/// Progress check function type
/// Returns progress as 0.0-1.0
pub const ProgressCheckFn = *const fn (player_id: u8, ctx: *const GameContext) f32;

/// Victory condition definition
pub const VictoryCondition = struct {
    /// Unique identifier
    id: []const u8,
    /// Display name
    name: ?[]const u8 = null,
    /// Description
    description: ?[]const u8 = null,
    /// Victory type
    victory_type: VictoryType = .custom,
    /// Function to check if condition is met
    check_fn: VictoryCheckFn,
    /// Optional function to get progress (0.0 to 1.0)
    progress_fn: ?ProgressCheckFn = null,
    /// Victory message format (use {player} for winner name)
    message_format: ?[]const u8 = null,
    /// Whether this condition is enabled
    enabled: bool = true,
    /// Priority (lower = checked first)
    priority: i32 = 0,
    /// Minimum turn before this can trigger
    min_turn: u32 = 0,
    /// Whether multiple players can win (shared victory)
    allow_shared: bool = false,
};

/// Internal condition with owned strings
const OwnedCondition = struct {
    id: []u8,
    name: ?[]u8,
    description: ?[]u8,
    victory_type: VictoryType,
    check_fn: VictoryCheckFn,
    progress_fn: ?ProgressCheckFn,
    message_format: ?[]u8,
    enabled: bool,
    priority: i32,
    min_turn: u32,
    allow_shared: bool,

    fn deinit(self: *OwnedCondition, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        if (self.name) |n| allocator.free(n);
        if (self.description) |d| allocator.free(d);
        if (self.message_format) |m| allocator.free(m);
    }
};

/// Configuration for victory manager
pub const VictoryConfig = struct {
    /// Number of players
    player_count: u8 = 2,
    /// Turn limit (0 = no limit)
    turn_limit: u32 = 0,
    /// Whether to check conditions every update
    auto_check: bool = true,
    /// Allow multiple winners
    allow_draw: bool = false,
};

/// Player state for victory tracking
pub const PlayerState = enum {
    active,
    eliminated,
    victorious,
    surrendered,
};

/// Victory Manager
pub const VictoryManager = struct {
    allocator: std.mem.Allocator,
    config: VictoryConfig,

    /// Registered conditions
    conditions: std.ArrayList(OwnedCondition),

    /// Per-player state
    player_states: [MAX_PLAYERS]PlayerState,

    /// Per-player cached progress per condition
    progress_cache: std.StringHashMap([MAX_PLAYERS]f32),

    /// Last victory result (if game ended)
    victory_result: ?OwnedVictoryResult,

    /// Current turn (updated by user)
    current_turn: u32,

    /// Callback when victory occurs
    on_victory: ?*const fn (result: VictoryResult, ctx: ?*anyopaque) void,
    on_victory_ctx: ?*anyopaque,

    /// Callback when player is eliminated
    on_elimination: ?*const fn (player_id: u8, ctx: ?*anyopaque) void,
    on_elimination_ctx: ?*anyopaque,

    const OwnedVictoryResult = struct {
        winner: u8,
        condition_id: []u8,
        victory_type: VictoryType,
        message: ?[]u8,

        fn deinit(self: *OwnedVictoryResult, allocator: std.mem.Allocator) void {
            allocator.free(self.condition_id);
            if (self.message) |m| allocator.free(m);
        }

        fn toResult(self: *const OwnedVictoryResult) VictoryResult {
            return .{
                .winner = self.winner,
                .condition_id = self.condition_id,
                .victory_type = self.victory_type,
                .message = self.message,
            };
        }
    };

    /// Initialize victory manager
    pub fn init(allocator: std.mem.Allocator, config: VictoryConfig) VictoryManager {
        var player_states: [MAX_PLAYERS]PlayerState = undefined;
        for (&player_states) |*s| {
            s.* = .active;
        }

        return VictoryManager{
            .allocator = allocator,
            .config = config,
            .conditions = std.ArrayList(OwnedCondition).init(allocator),
            .player_states = player_states,
            .progress_cache = std.StringHashMap([MAX_PLAYERS]f32).init(allocator),
            .victory_result = null,
            .current_turn = 0,
            .on_victory = null,
            .on_victory_ctx = null,
            .on_elimination = null,
            .on_elimination_ctx = null,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *VictoryManager) void {
        for (self.conditions.items) |*cond| {
            cond.deinit(self.allocator);
        }
        self.conditions.deinit();
        self.progress_cache.deinit();

        if (self.victory_result) |*result| {
            result.deinit(self.allocator);
        }
    }

    /// Add a victory condition
    pub fn addCondition(self: *VictoryManager, condition: VictoryCondition) !void {
        const id_copy = try self.allocator.dupe(u8, condition.id);
        errdefer self.allocator.free(id_copy);

        var owned = OwnedCondition{
            .id = id_copy,
            .name = null,
            .description = null,
            .victory_type = condition.victory_type,
            .check_fn = condition.check_fn,
            .progress_fn = condition.progress_fn,
            .message_format = null,
            .enabled = condition.enabled,
            .priority = condition.priority,
            .min_turn = condition.min_turn,
            .allow_shared = condition.allow_shared,
        };

        if (condition.name) |n| {
            owned.name = try self.allocator.dupe(u8, n);
        }
        if (condition.description) |d| {
            owned.description = try self.allocator.dupe(u8, d);
        }
        if (condition.message_format) |m| {
            owned.message_format = try self.allocator.dupe(u8, m);
        }

        try self.conditions.append(owned);

        // Sort by priority
        std.mem.sort(OwnedCondition, self.conditions.items, {}, struct {
            fn lessThan(_: void, a: OwnedCondition, b: OwnedCondition) bool {
                return a.priority < b.priority;
            }
        }.lessThan);
    }

    /// Remove a victory condition
    pub fn removeCondition(self: *VictoryManager, id: []const u8) bool {
        for (self.conditions.items, 0..) |*cond, i| {
            if (std.mem.eql(u8, cond.id, id)) {
                cond.deinit(self.allocator);
                _ = self.conditions.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    /// Enable/disable a condition
    pub fn setConditionEnabled(self: *VictoryManager, id: []const u8, enabled: bool) bool {
        for (self.conditions.items) |*cond| {
            if (std.mem.eql(u8, cond.id, id)) {
                cond.enabled = enabled;
                return true;
            }
        }
        return false;
    }

    /// Check if a condition is enabled
    pub fn isConditionEnabled(self: *const VictoryManager, id: []const u8) bool {
        for (self.conditions.items) |cond| {
            if (std.mem.eql(u8, cond.id, id)) {
                return cond.enabled;
            }
        }
        return false;
    }

    /// Set current turn
    pub fn setTurn(self: *VictoryManager, turn: u32) void {
        self.current_turn = turn;
    }

    /// Eliminate a player
    pub fn eliminatePlayer(self: *VictoryManager, player_id: u8) void {
        if (player_id >= MAX_PLAYERS) return;
        self.player_states[player_id] = .eliminated;

        if (self.on_elimination) |callback| {
            callback(player_id, self.on_elimination_ctx);
        }
    }

    /// Player surrenders
    pub fn surrender(self: *VictoryManager, player_id: u8) void {
        if (player_id >= MAX_PLAYERS) return;
        self.player_states[player_id] = .surrendered;

        if (self.on_elimination) |callback| {
            callback(player_id, self.on_elimination_ctx);
        }
    }

    /// Get player state
    pub fn getPlayerState(self: *const VictoryManager, player_id: u8) PlayerState {
        if (player_id >= MAX_PLAYERS) return .eliminated;
        return self.player_states[player_id];
    }

    /// Check if player is still in game
    pub fn isPlayerActive(self: *const VictoryManager, player_id: u8) bool {
        return self.getPlayerState(player_id) == .active;
    }

    /// Get count of active players
    pub fn getActivePlayerCount(self: *const VictoryManager) u8 {
        var count: u8 = 0;
        for (0..self.config.player_count) |i| {
            if (self.player_states[i] == .active) {
                count += 1;
            }
        }
        return count;
    }

    /// Build game context for condition checks
    fn buildContext(self: *const VictoryManager, user_data: ?*anyopaque) GameContext {
        var eliminated: [MAX_PLAYERS]bool = undefined;
        var scores: [MAX_PLAYERS]i64 = undefined;

        for (0..MAX_PLAYERS) |i| {
            eliminated[i] = self.player_states[i] != .active;
            scores[i] = 0;
        }

        return GameContext{
            .turn = self.current_turn,
            .active_players = self.getActivePlayerCount(),
            .eliminated = eliminated,
            .scores = scores,
            .user_data = user_data,
        };
    }

    /// Check all victory conditions
    pub fn checkVictory(self: *VictoryManager, user_data: ?*anyopaque) ?VictoryResult {
        // Already have a winner
        if (self.victory_result) |result| {
            return result.toResult();
        }

        const ctx = self.buildContext(user_data);

        // Check last player standing first
        if (ctx.active_players == 1) {
            // Find the winner
            for (0..self.config.player_count) |i| {
                if (self.player_states[i] == .active) {
                    return self.declareVictory(@intCast(i), "last_standing", .domination, "Last player standing");
                }
            }
        }

        // Check turn limit
        if (self.config.turn_limit > 0 and self.current_turn >= self.config.turn_limit) {
            // Find player with highest score or first active
            var best_player: u8 = 0;
            for (0..self.config.player_count) |i| {
                if (self.player_states[i] == .active) {
                    best_player = @intCast(i);
                    break;
                }
            }
            return self.declareVictory(best_player, "time_limit", .score, "Time limit reached");
        }

        // Check each condition
        for (self.conditions.items) |cond| {
            if (!cond.enabled) continue;
            if (self.current_turn < cond.min_turn) continue;

            // Check each active player
            for (0..self.config.player_count) |player| {
                if (self.player_states[player] != .active) continue;

                if (cond.check_fn(@intCast(player), &ctx)) {
                    const message = cond.message_format orelse cond.name;
                    return self.declareVictory(@intCast(player), cond.id, cond.victory_type, message);
                }
            }
        }

        return null;
    }

    /// Declare a victory
    fn declareVictory(self: *VictoryManager, winner: u8, condition_id: []const u8, victory_type: VictoryType, message: ?[]const u8) VictoryResult {
        // Store result
        const id_copy = self.allocator.dupe(u8, condition_id) catch condition_id;
        var msg_copy: ?[]u8 = null;
        if (message) |m| {
            msg_copy = self.allocator.dupe(u8, m) catch null;
        }

        self.victory_result = .{
            .winner = winner,
            .condition_id = @constCast(id_copy),
            .victory_type = victory_type,
            .message = msg_copy,
        };

        self.player_states[winner] = .victorious;

        // Callback
        if (self.on_victory) |callback| {
            callback(self.victory_result.?.toResult(), self.on_victory_ctx);
        }

        return self.victory_result.?.toResult();
    }

    /// Get progress for a condition (0.0 to 1.0)
    pub fn getProgress(self: *VictoryManager, condition_id: []const u8, player_id: u8, user_data: ?*anyopaque) f32 {
        for (self.conditions.items) |cond| {
            if (std.mem.eql(u8, cond.id, condition_id)) {
                if (cond.progress_fn) |progress_fn| {
                    const ctx = self.buildContext(user_data);
                    return progress_fn(player_id, &ctx);
                }
                return 0;
            }
        }
        return 0;
    }

    /// Get all enabled conditions
    pub fn getEnabledConditions(self: *const VictoryManager, allocator: std.mem.Allocator) ![][]const u8 {
        var list = std.ArrayList([]const u8).init(allocator);
        for (self.conditions.items) |cond| {
            if (cond.enabled) {
                try list.append(cond.id);
            }
        }
        return list.toOwnedSlice();
    }

    /// Get condition info
    pub fn getConditionInfo(self: *const VictoryManager, id: []const u8) ?struct {
        id: []const u8,
        name: ?[]const u8,
        description: ?[]const u8,
        victory_type: VictoryType,
        enabled: bool,
        min_turn: u32,
    } {
        for (self.conditions.items) |cond| {
            if (std.mem.eql(u8, cond.id, id)) {
                return .{
                    .id = cond.id,
                    .name = cond.name,
                    .description = cond.description,
                    .victory_type = cond.victory_type,
                    .enabled = cond.enabled,
                    .min_turn = cond.min_turn,
                };
            }
        }
        return null;
    }

    /// Check if game has ended
    pub fn isGameOver(self: *const VictoryManager) bool {
        return self.victory_result != null;
    }

    /// Get victory result if game ended
    pub fn getVictoryResult(self: *const VictoryManager) ?VictoryResult {
        if (self.victory_result) |result| {
            return result.toResult();
        }
        return null;
    }

    /// Reset the game
    pub fn reset(self: *VictoryManager) void {
        for (&self.player_states) |*s| {
            s.* = .active;
        }
        self.current_turn = 0;

        if (self.victory_result) |*result| {
            result.deinit(self.allocator);
            self.victory_result = null;
        }
    }

    /// Set victory callback
    pub fn setOnVictory(self: *VictoryManager, callback: ?*const fn (VictoryResult, ?*anyopaque) void, ctx: ?*anyopaque) void {
        self.on_victory = callback;
        self.on_victory_ctx = ctx;
    }

    /// Set elimination callback
    pub fn setOnElimination(self: *VictoryManager, callback: ?*const fn (u8, ?*anyopaque) void, ctx: ?*anyopaque) void {
        self.on_elimination = callback;
        self.on_elimination_ctx = ctx;
    }

    /// Get condition count
    pub fn getConditionCount(self: *const VictoryManager) usize {
        return self.conditions.items.len;
    }

    /// Force victory for a player (debug/testing)
    pub fn forceVictory(self: *VictoryManager, player_id: u8, condition_id: []const u8) VictoryResult {
        return self.declareVictory(player_id, condition_id, .custom, "Forced victory");
    }
};

// ============================================================================
// Built-in condition helpers
// ============================================================================

/// Create a simple elimination victory condition
pub fn dominationCondition() VictoryCondition {
    return .{
        .id = "domination",
        .name = "Domination",
        .description = "Eliminate all opponents",
        .victory_type = .domination,
        .check_fn = struct {
            fn check(player_id: u8, ctx: *const GameContext) bool {
                // Win if only one player remains and it's us
                if (ctx.active_players != 1) return false;
                return !ctx.eliminated[player_id];
            }
        }.check,
        .priority = 100, // Low priority, check other conditions first
    };
}

/// Create a score-based victory condition
/// Note: The required_score parameter is for documentation purposes.
/// For actual score checking, use a custom condition with user_data.
pub fn scoreCondition(required_score: i64) VictoryCondition {
    _ = required_score; // Score threshold would be passed via user_data in actual use
    return .{
        .id = "score",
        .name = "Score Victory",
        .description = "Reach the required score",
        .victory_type = .score,
        .check_fn = struct {
            fn check(player_id: u8, ctx: *const GameContext) bool {
                // Note: This is a simplified check - actual score threshold
                // would need to be passed via user_data or closure
                _ = ctx;
                _ = player_id;
                return false;
            }
        }.check,
        .progress_fn = struct {
            fn progress(player_id: u8, ctx: *const GameContext) f32 {
                const score = ctx.scores[player_id];
                if (score <= 0) return 0;
                // Return normalized progress (would need threshold from closure)
                return @min(1.0, @as(f32, @floatFromInt(score)) / 10000.0);
            }
        }.progress,
        .priority = 50,
        .min_turn = 0,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "VictoryManager - init and basic" {
    var vm = VictoryManager.init(std.testing.allocator, .{ .player_count = 4 });
    defer vm.deinit();

    try std.testing.expectEqual(@as(u8, 4), vm.getActivePlayerCount());
    try std.testing.expect(!vm.isGameOver());
}

test "VictoryManager - add condition" {
    var vm = VictoryManager.init(std.testing.allocator, .{ .player_count = 2 });
    defer vm.deinit();

    const always_false = struct {
        fn check(_: u8, _: *const GameContext) bool {
            return false;
        }
    }.check;

    try vm.addCondition(.{
        .id = "test",
        .name = "Test Condition",
        .check_fn = always_false,
    });

    try std.testing.expectEqual(@as(usize, 1), vm.getConditionCount());

    const info = vm.getConditionInfo("test").?;
    try std.testing.expectEqualStrings("test", info.id);
    try std.testing.expectEqualStrings("Test Condition", info.name.?);
}

test "VictoryManager - last player standing" {
    var vm = VictoryManager.init(std.testing.allocator, .{ .player_count = 3 });
    defer vm.deinit();

    // Eliminate player 1 and 2
    vm.eliminatePlayer(1);
    vm.eliminatePlayer(2);

    // Player 0 should win
    const result = vm.checkVictory(null).?;
    try std.testing.expectEqual(@as(u8, 0), result.winner);
    try std.testing.expectEqual(VictoryType.domination, result.victory_type);
    try std.testing.expect(vm.isGameOver());
}

test "VictoryManager - custom condition" {
    var vm = VictoryManager.init(std.testing.allocator, .{ .player_count = 2 });
    defer vm.deinit();

    var player1_wins = false;

    const custom_check = struct {
        fn check(player_id: u8, ctx: *const GameContext) bool {
            const flag: *bool = @ptrCast(@alignCast(ctx.user_data));
            return player_id == 1 and flag.*;
        }
    }.check;

    try vm.addCondition(.{
        .id = "custom",
        .check_fn = custom_check,
    });

    // Not triggered yet
    try std.testing.expect(vm.checkVictory(&player1_wins) == null);

    // Trigger the condition
    player1_wins = true;
    const result = vm.checkVictory(&player1_wins).?;
    try std.testing.expectEqual(@as(u8, 1), result.winner);
}

test "VictoryManager - min turn" {
    var vm = VictoryManager.init(std.testing.allocator, .{ .player_count = 2 });
    defer vm.deinit();

    const always_true = struct {
        fn check(_: u8, _: *const GameContext) bool {
            return true;
        }
    }.check;

    try vm.addCondition(.{
        .id = "delayed",
        .check_fn = always_true,
        .min_turn = 10,
    });

    // Turn 0 - shouldn't trigger
    vm.setTurn(0);
    try std.testing.expect(vm.checkVictory(null) == null);

    // Turn 5 - still shouldn't trigger
    vm.setTurn(5);
    try std.testing.expect(vm.checkVictory(null) == null);

    // Turn 10 - should trigger
    vm.setTurn(10);
    try std.testing.expect(vm.checkVictory(null) != null);
}

test "VictoryManager - enable/disable condition" {
    var vm = VictoryManager.init(std.testing.allocator, .{ .player_count = 2 });
    defer vm.deinit();

    const always_true = struct {
        fn check(_: u8, _: *const GameContext) bool {
            return true;
        }
    }.check;

    try vm.addCondition(.{
        .id = "toggle",
        .check_fn = always_true,
        .enabled = true,
    });

    // Enabled - should trigger
    try std.testing.expect(vm.checkVictory(null) != null);

    // Reset and disable
    vm.reset();
    _ = vm.setConditionEnabled("toggle", false);
    try std.testing.expect(!vm.isConditionEnabled("toggle"));
    try std.testing.expect(vm.checkVictory(null) == null);

    // Re-enable
    _ = vm.setConditionEnabled("toggle", true);
    try std.testing.expect(vm.checkVictory(null) != null);
}

test "VictoryManager - turn limit" {
    var vm = VictoryManager.init(std.testing.allocator, .{
        .player_count = 2,
        .turn_limit = 50,
    });
    defer vm.deinit();

    vm.setTurn(49);
    try std.testing.expect(vm.checkVictory(null) == null);

    vm.setTurn(50);
    const result = vm.checkVictory(null).?;
    try std.testing.expectEqual(VictoryType.score, result.victory_type);
}

test "VictoryManager - player states" {
    var vm = VictoryManager.init(std.testing.allocator, .{ .player_count = 4 });
    defer vm.deinit();

    try std.testing.expect(vm.isPlayerActive(0));
    try std.testing.expect(vm.isPlayerActive(1));

    vm.eliminatePlayer(1);
    try std.testing.expect(!vm.isPlayerActive(1));
    try std.testing.expectEqual(PlayerState.eliminated, vm.getPlayerState(1));

    vm.surrender(2);
    try std.testing.expectEqual(PlayerState.surrendered, vm.getPlayerState(2));

    try std.testing.expectEqual(@as(u8, 2), vm.getActivePlayerCount());
}

test "VictoryManager - victory callback" {
    var vm = VictoryManager.init(std.testing.allocator, .{ .player_count = 2 });
    defer vm.deinit();

    var callback_called = false;

    const callback = struct {
        fn cb(_: VictoryResult, ctx: ?*anyopaque) void {
            const flag: *bool = @ptrCast(@alignCast(ctx));
            flag.* = true;
        }
    }.cb;

    vm.setOnVictory(callback, &callback_called);

    // Trigger last player standing
    vm.eliminatePlayer(1);
    _ = vm.checkVictory(null);

    try std.testing.expect(callback_called);
}

test "VictoryManager - elimination callback" {
    var vm = VictoryManager.init(std.testing.allocator, .{ .player_count = 4 });
    defer vm.deinit();

    var eliminated_player: u8 = 255;

    const callback = struct {
        fn cb(player_id: u8, ctx: ?*anyopaque) void {
            const ptr: *u8 = @ptrCast(@alignCast(ctx));
            ptr.* = player_id;
        }
    }.cb;

    vm.setOnElimination(callback, &eliminated_player);

    vm.eliminatePlayer(2);
    try std.testing.expectEqual(@as(u8, 2), eliminated_player);
}

test "VictoryManager - reset" {
    var vm = VictoryManager.init(std.testing.allocator, .{ .player_count = 2 });
    defer vm.deinit();

    vm.eliminatePlayer(1);
    _ = vm.checkVictory(null);

    try std.testing.expect(vm.isGameOver());

    vm.reset();

    try std.testing.expect(!vm.isGameOver());
    try std.testing.expect(vm.isPlayerActive(1));
    try std.testing.expectEqual(@as(u32, 0), vm.current_turn);
}

test "VictoryManager - condition priority" {
    var vm = VictoryManager.init(std.testing.allocator, .{ .player_count = 2 });
    defer vm.deinit();

    // Add conditions out of order
    try vm.addCondition(.{
        .id = "low_priority",
        .check_fn = struct {
            fn check(_: u8, _: *const GameContext) bool {
                return true;
            }
        }.check,
        .priority = 100,
    });

    try vm.addCondition(.{
        .id = "high_priority",
        .check_fn = struct {
            fn check(_: u8, _: *const GameContext) bool {
                return true;
            }
        }.check,
        .priority = 10,
    });

    // High priority should win
    const result = vm.checkVictory(null).?;
    try std.testing.expectEqualStrings("high_priority", result.condition_id);
}

test "VictoryManager - progress function" {
    var vm = VictoryManager.init(std.testing.allocator, .{ .player_count = 2 });
    defer vm.deinit();

    try vm.addCondition(.{
        .id = "progress_test",
        .check_fn = struct {
            fn check(_: u8, _: *const GameContext) bool {
                return false;
            }
        }.check,
        .progress_fn = struct {
            fn progress(player_id: u8, _: *const GameContext) f32 {
                return @as(f32, @floatFromInt(player_id)) * 0.5;
            }
        }.progress,
    });

    try std.testing.expectApproxEqAbs(@as(f32, 0.0), vm.getProgress("progress_test", 0, null), 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), vm.getProgress("progress_test", 1, null), 0.01);
}

test "VictoryManager - remove condition" {
    var vm = VictoryManager.init(std.testing.allocator, .{ .player_count = 2 });
    defer vm.deinit();

    try vm.addCondition(.{
        .id = "removable",
        .check_fn = struct {
            fn check(_: u8, _: *const GameContext) bool {
                return false;
            }
        }.check,
    });

    try std.testing.expectEqual(@as(usize, 1), vm.getConditionCount());

    try std.testing.expect(vm.removeCondition("removable"));
    try std.testing.expectEqual(@as(usize, 0), vm.getConditionCount());

    try std.testing.expect(!vm.removeCondition("nonexistent"));
}

test "VictoryManager - force victory" {
    var vm = VictoryManager.init(std.testing.allocator, .{ .player_count = 2 });
    defer vm.deinit();

    const result = vm.forceVictory(1, "debug");
    try std.testing.expectEqual(@as(u8, 1), result.winner);
    try std.testing.expect(vm.isGameOver());
}

test "VictoryManager - getEnabledConditions" {
    var vm = VictoryManager.init(std.testing.allocator, .{ .player_count = 2 });
    defer vm.deinit();

    const check_fn = struct {
        fn check(_: u8, _: *const GameContext) bool {
            return false;
        }
    }.check;

    try vm.addCondition(.{ .id = "cond1", .check_fn = check_fn, .enabled = true });
    try vm.addCondition(.{ .id = "cond2", .check_fn = check_fn, .enabled = false });
    try vm.addCondition(.{ .id = "cond3", .check_fn = check_fn, .enabled = true });

    const enabled = try vm.getEnabledConditions(std.testing.allocator);
    defer std.testing.allocator.free(enabled);

    try std.testing.expectEqual(@as(usize, 2), enabled.len);
}

test "VictoryManager - built-in domination" {
    var vm = VictoryManager.init(std.testing.allocator, .{ .player_count = 3 });
    defer vm.deinit();

    try vm.addCondition(dominationCondition());

    // No winner yet
    try std.testing.expect(vm.checkVictory(null) == null);

    // Eliminate 2 players
    vm.eliminatePlayer(1);
    vm.eliminatePlayer(2);

    const result = vm.checkVictory(null).?;
    try std.testing.expectEqual(@as(u8, 0), result.winner);
}
