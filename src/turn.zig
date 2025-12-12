//! Turn/Phase Manager - Turn-Based Game Flow Control
//!
//! A flexible turn and phase management system for turn-based games.
//! Supports configurable phases, callbacks, and multiple turn modes.
//!
//! Features:
//! - Generic phase types (works with any enum)
//! - Configurable phase ordering
//! - Phase callbacks with context
//! - Turn number and phase tracking
//! - Phase result/error handling
//! - Progress tracking for UI
//! - Simultaneous vs sequential player turns
//! - Phase timing/profiling
//!
//! Usage:
//! ```zig
//! const Phase = enum { upkeep, main, combat, end };
//!
//! var manager = TurnManager(Phase).init(allocator);
//! defer manager.deinit();
//!
//! try manager.setPhaseOrder(&.{ .upkeep, .main, .combat, .end });
//! try manager.registerPhase(.main, mainPhaseHandler, &game_state);
//!
//! const result = try manager.processTurn();
//! ```

const std = @import("std");

const log = std.log.scoped(.turn);

/// Result of processing a single phase
pub const PhaseResult = struct {
    success: bool = true,
    /// Error message if failed
    error_message: ?[]const u8 = null,
    /// Duration in nanoseconds (if profiling enabled)
    duration_ns: u64 = 0,
    /// Whether to skip remaining phases
    skip_remaining: bool = false,
};

/// Result of processing a complete turn
pub fn TurnResult(comptime PhaseType: type) type {
    return struct {
        const Self = @This();

        turn_number: u32,
        success: bool = true,
        total_duration_ns: u64 = 0,
        phases_completed: usize = 0,
        phases_skipped: usize = 0,
        /// Phase that caused failure (if any)
        failed_phase: ?PhaseType = null,
        /// Error message from failed phase
        error_message: ?[]const u8 = null,
    };
}

/// Turn mode for multiplayer games
pub const TurnMode = enum {
    /// Each player takes their turn sequentially
    sequential,
    /// All players act simultaneously, then resolve
    simultaneous,
    /// Real-time with pauses (like Paradox games)
    real_time_with_pause,
};

/// Configuration for TurnManager
pub const TurnManagerConfig = struct {
    /// Enable timing profiling
    profiling_enabled: bool = false,
    /// Continue processing phases after a failure
    continue_on_failure: bool = false,
    /// Turn mode for multiplayer
    turn_mode: TurnMode = .sequential,
    /// Maximum phases per turn (0 = unlimited)
    max_phases: usize = 0,
};

/// Generic turn manager parameterized by phase type
pub fn TurnManager(comptime PhaseType: type) type {
    const phase_info = @typeInfo(PhaseType);
    if (phase_info != .@"enum") {
        @compileError("TurnManager requires an enum type for phases, got " ++ @typeName(PhaseType));
    }

    return struct {
        const Self = @This();

        /// Phase callback function type
        pub const PhaseCallback = *const fn (phase: PhaseType, context: ?*anyopaque) PhaseResult;

        /// Registered phase handler
        const PhaseHandler = struct {
            callback: PhaseCallback,
            context: ?*anyopaque,
        };

        allocator: std.mem.Allocator,
        config: TurnManagerConfig,

        // Turn state
        current_turn: u32 = 0,
        current_phase_index: usize = 0,
        is_processing: bool = false,

        // Phase configuration
        phase_order: std.ArrayList(PhaseType),
        phase_handlers: std.AutoHashMap(PhaseType, PhaseHandler),

        // Turn callbacks
        on_turn_start: ?*const fn (turn: u32, context: ?*anyopaque) void = null,
        on_turn_end: ?*const fn (turn: u32, context: ?*anyopaque) void = null,
        on_phase_start: ?*const fn (phase: PhaseType, context: ?*anyopaque) void = null,
        on_phase_end: ?*const fn (phase: PhaseType, result: PhaseResult, context: ?*anyopaque) void = null,
        callback_context: ?*anyopaque = null,

        /// Initialize the turn manager
        pub fn init(allocator: std.mem.Allocator) Self {
            return initWithConfig(allocator, .{});
        }

        /// Initialize with custom configuration
        pub fn initWithConfig(allocator: std.mem.Allocator, config: TurnManagerConfig) Self {
            return Self{
                .allocator = allocator,
                .config = config,
                .phase_order = std.ArrayList(PhaseType).init(allocator),
                .phase_handlers = std.AutoHashMap(PhaseType, PhaseHandler).init(allocator),
            };
        }

        /// Clean up resources
        pub fn deinit(self: *Self) void {
            self.phase_order.deinit();
            self.phase_handlers.deinit();
        }

        /// Set the phase execution order
        pub fn setPhaseOrder(self: *Self, phases: []const PhaseType) !void {
            self.phase_order.clearRetainingCapacity();
            try self.phase_order.appendSlice(phases);
        }

        /// Add a phase to the end of the order
        pub fn addPhase(self: *Self, phase: PhaseType) !void {
            try self.phase_order.append(phase);
        }

        /// Insert a phase at a specific position
        pub fn insertPhase(self: *Self, index: usize, phase: PhaseType) !void {
            try self.phase_order.insert(index, phase);
        }

        /// Remove a phase from the order
        pub fn removePhase(self: *Self, phase: PhaseType) bool {
            for (self.phase_order.items, 0..) |p, i| {
                if (p == phase) {
                    _ = self.phase_order.orderedRemove(i);
                    return true;
                }
            }
            return false;
        }

        /// Register a handler for a phase
        pub fn registerPhase(self: *Self, phase: PhaseType, callback: PhaseCallback, context: ?*anyopaque) !void {
            try self.phase_handlers.put(phase, .{
                .callback = callback,
                .context = context,
            });
        }

        /// Unregister a phase handler
        pub fn unregisterPhase(self: *Self, phase: PhaseType) bool {
            return self.phase_handlers.remove(phase);
        }

        /// Set turn lifecycle callbacks
        pub fn setCallbacks(
            self: *Self,
            on_turn_start: ?*const fn (u32, ?*anyopaque) void,
            on_turn_end: ?*const fn (u32, ?*anyopaque) void,
            on_phase_start: ?*const fn (PhaseType, ?*anyopaque) void,
            on_phase_end: ?*const fn (PhaseType, PhaseResult, ?*anyopaque) void,
            context: ?*anyopaque,
        ) void {
            self.on_turn_start = on_turn_start;
            self.on_turn_end = on_turn_end;
            self.on_phase_start = on_phase_start;
            self.on_phase_end = on_phase_end;
            self.callback_context = context;
        }

        /// Process a complete turn
        pub fn processTurn(self: *Self) TurnResult(PhaseType) {
            if (self.is_processing) {
                return .{
                    .turn_number = self.current_turn,
                    .success = false,
                    .error_message = "Turn already in progress",
                };
            }

            self.is_processing = true;
            defer self.is_processing = false;

            self.current_turn += 1;
            self.current_phase_index = 0;

            var result = TurnResult(PhaseType){
                .turn_number = self.current_turn,
                .success = true,
            };

            // Turn start callback
            if (self.on_turn_start) |callback| {
                callback(self.current_turn, self.callback_context);
            }

            const turn_start = if (self.config.profiling_enabled) std.time.nanoTimestamp() else 0;

            // Process each phase
            for (self.phase_order.items, 0..) |phase, i| {
                self.current_phase_index = i;

                // Check max phases limit
                if (self.config.max_phases > 0 and i >= self.config.max_phases) {
                    result.phases_skipped = self.phase_order.items.len - i;
                    break;
                }

                // Phase start callback
                if (self.on_phase_start) |callback| {
                    callback(phase, self.callback_context);
                }

                const phase_start = if (self.config.profiling_enabled) std.time.nanoTimestamp() else 0;

                // Execute phase handler
                var phase_result = PhaseResult{ .success = true };
                if (self.phase_handlers.get(phase)) |handler| {
                    phase_result = handler.callback(phase, handler.context);
                }
                // If no handler registered, phase is considered successful

                if (self.config.profiling_enabled) {
                    const phase_end = std.time.nanoTimestamp();
                    phase_result.duration_ns = @intCast(@as(i128, phase_end) - @as(i128, phase_start));
                }

                // Phase end callback
                if (self.on_phase_end) |callback| {
                    callback(phase, phase_result, self.callback_context);
                }

                if (phase_result.success) {
                    result.phases_completed += 1;
                } else {
                    result.success = false;
                    result.failed_phase = phase;
                    result.error_message = phase_result.error_message;

                    if (!self.config.continue_on_failure) {
                        result.phases_skipped = self.phase_order.items.len - i - 1;
                        break;
                    }
                }

                // Check if phase requested skip
                if (phase_result.skip_remaining) {
                    result.phases_skipped = self.phase_order.items.len - i - 1;
                    break;
                }
            }

            if (self.config.profiling_enabled) {
                const turn_end = std.time.nanoTimestamp();
                result.total_duration_ns = @intCast(@as(i128, turn_end) - @as(i128, turn_start));
            }

            self.current_phase_index = self.phase_order.items.len;

            // Turn end callback
            if (self.on_turn_end) |callback| {
                callback(self.current_turn, self.callback_context);
            }

            return result;
        }

        /// Process a single phase (for step-by-step execution)
        pub fn processPhase(self: *Self, phase: PhaseType) PhaseResult {
            if (self.on_phase_start) |callback| {
                callback(phase, self.callback_context);
            }

            const phase_start = if (self.config.profiling_enabled) std.time.nanoTimestamp() else 0;

            var result = PhaseResult{ .success = true };
            if (self.phase_handlers.get(phase)) |handler| {
                result = handler.callback(phase, handler.context);
            }

            if (self.config.profiling_enabled) {
                const phase_end = std.time.nanoTimestamp();
                result.duration_ns = @intCast(@as(i128, phase_end) - @as(i128, phase_start));
            }

            if (self.on_phase_end) |callback| {
                callback(phase, result, self.callback_context);
            }

            return result;
        }

        /// Advance to next turn without processing (for manual control)
        pub fn nextTurn(self: *Self) u32 {
            self.current_turn += 1;
            self.current_phase_index = 0;
            return self.current_turn;
        }

        /// Get the current turn number
        pub fn getTurnNumber(self: *const Self) u32 {
            return self.current_turn;
        }

        /// Get the current phase being processed
        pub fn getCurrentPhase(self: *const Self) ?PhaseType {
            if (self.current_phase_index >= self.phase_order.items.len) {
                return null;
            }
            return self.phase_order.items[self.current_phase_index];
        }

        /// Get progress through the turn (0.0 to 1.0)
        pub fn getProgress(self: *const Self) f32 {
            if (self.phase_order.items.len == 0) {
                return 1.0;
            }
            return @as(f32, @floatFromInt(self.current_phase_index)) /
                @as(f32, @floatFromInt(self.phase_order.items.len));
        }

        /// Check if a phase has been completed this turn
        pub fn hasPhaseCompleted(self: *const Self, phase: PhaseType) bool {
            for (self.phase_order.items, 0..) |p, i| {
                if (p == phase) {
                    return self.current_phase_index > i;
                }
            }
            return false;
        }

        /// Check if currently processing a turn
        pub fn isProcessing(self: *const Self) bool {
            return self.is_processing;
        }

        /// Get the number of phases
        pub fn getPhaseCount(self: *const Self) usize {
            return self.phase_order.items.len;
        }

        /// Get all phases in order
        pub fn getPhases(self: *const Self) []const PhaseType {
            return self.phase_order.items;
        }

        /// Reset to turn 0
        pub fn reset(self: *Self) void {
            self.current_turn = 0;
            self.current_phase_index = 0;
            self.is_processing = false;
        }

        /// Set the current turn number (for loading saves)
        pub fn setTurnNumber(self: *Self, turn: u32) void {
            self.current_turn = turn;
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

const TestPhase = enum {
    setup,
    upkeep,
    main,
    combat,
    cleanup,
};

test "TurnManager - init and deinit" {
    var manager = TurnManager(TestPhase).init(std.testing.allocator);
    defer manager.deinit();

    try std.testing.expectEqual(@as(u32, 0), manager.getTurnNumber());
    try std.testing.expect(!manager.isProcessing());
}

test "TurnManager - setPhaseOrder" {
    var manager = TurnManager(TestPhase).init(std.testing.allocator);
    defer manager.deinit();

    try manager.setPhaseOrder(&.{ .setup, .main, .cleanup });

    try std.testing.expectEqual(@as(usize, 3), manager.getPhaseCount());
    try std.testing.expectEqual(TestPhase.setup, manager.getPhases()[0]);
    try std.testing.expectEqual(TestPhase.main, manager.getPhases()[1]);
    try std.testing.expectEqual(TestPhase.cleanup, manager.getPhases()[2]);
}

test "TurnManager - addPhase and removePhase" {
    var manager = TurnManager(TestPhase).init(std.testing.allocator);
    defer manager.deinit();

    try manager.addPhase(.setup);
    try manager.addPhase(.main);
    try manager.addPhase(.cleanup);

    try std.testing.expectEqual(@as(usize, 3), manager.getPhaseCount());

    const removed = manager.removePhase(.main);
    try std.testing.expect(removed);
    try std.testing.expectEqual(@as(usize, 2), manager.getPhaseCount());
}

test "TurnManager - insertPhase" {
    var manager = TurnManager(TestPhase).init(std.testing.allocator);
    defer manager.deinit();

    try manager.addPhase(.setup);
    try manager.addPhase(.cleanup);
    try manager.insertPhase(1, .main);

    try std.testing.expectEqual(@as(usize, 3), manager.getPhaseCount());
    try std.testing.expectEqual(TestPhase.main, manager.getPhases()[1]);
}

test "TurnManager - processTurn basic" {
    var manager = TurnManager(TestPhase).init(std.testing.allocator);
    defer manager.deinit();

    try manager.setPhaseOrder(&.{ .setup, .main, .cleanup });

    const result = manager.processTurn();

    try std.testing.expect(result.success);
    try std.testing.expectEqual(@as(u32, 1), result.turn_number);
    try std.testing.expectEqual(@as(usize, 3), result.phases_completed);
    try std.testing.expectEqual(@as(usize, 0), result.phases_skipped);
}

test "TurnManager - processTurn increments turn number" {
    var manager = TurnManager(TestPhase).init(std.testing.allocator);
    defer manager.deinit();

    try manager.setPhaseOrder(&.{.main});

    _ = manager.processTurn();
    try std.testing.expectEqual(@as(u32, 1), manager.getTurnNumber());

    _ = manager.processTurn();
    try std.testing.expectEqual(@as(u32, 2), manager.getTurnNumber());

    _ = manager.processTurn();
    try std.testing.expectEqual(@as(u32, 3), manager.getTurnNumber());
}

test "TurnManager - registerPhase callback" {
    var manager = TurnManager(TestPhase).init(std.testing.allocator);
    defer manager.deinit();

    var call_count: u32 = 0;

    const handler = struct {
        fn callback(_: TestPhase, ctx: ?*anyopaque) PhaseResult {
            const count: *u32 = @ptrCast(@alignCast(ctx.?));
            count.* += 1;
            return .{ .success = true };
        }
    }.callback;

    try manager.setPhaseOrder(&.{ .setup, .main, .cleanup });
    try manager.registerPhase(.main, handler, &call_count);

    _ = manager.processTurn();

    try std.testing.expectEqual(@as(u32, 1), call_count);
}

test "TurnManager - phase failure stops processing" {
    var manager = TurnManager(TestPhase).init(std.testing.allocator);
    defer manager.deinit();

    const failing_handler = struct {
        fn callback(_: TestPhase, _: ?*anyopaque) PhaseResult {
            return .{ .success = false, .error_message = "Test failure" };
        }
    }.callback;

    try manager.setPhaseOrder(&.{ .setup, .main, .cleanup });
    try manager.registerPhase(.main, failing_handler, null);

    const result = manager.processTurn();

    try std.testing.expect(!result.success);
    try std.testing.expectEqual(TestPhase.main, result.failed_phase.?);
    try std.testing.expectEqual(@as(usize, 2), result.phases_completed); // setup + main (failed)
    try std.testing.expectEqual(@as(usize, 1), result.phases_skipped); // cleanup
}

test "TurnManager - continue_on_failure" {
    var manager = TurnManager(TestPhase).initWithConfig(std.testing.allocator, .{
        .continue_on_failure = true,
    });
    defer manager.deinit();

    const failing_handler = struct {
        fn callback(_: TestPhase, _: ?*anyopaque) PhaseResult {
            return .{ .success = false };
        }
    }.callback;

    try manager.setPhaseOrder(&.{ .setup, .main, .cleanup });
    try manager.registerPhase(.main, failing_handler, null);

    const result = manager.processTurn();

    try std.testing.expect(!result.success);
    try std.testing.expectEqual(@as(usize, 3), result.phases_completed); // All phases ran
    try std.testing.expectEqual(@as(usize, 0), result.phases_skipped);
}

test "TurnManager - skip_remaining" {
    var manager = TurnManager(TestPhase).init(std.testing.allocator);
    defer manager.deinit();

    const skip_handler = struct {
        fn callback(_: TestPhase, _: ?*anyopaque) PhaseResult {
            return .{ .success = true, .skip_remaining = true };
        }
    }.callback;

    try manager.setPhaseOrder(&.{ .setup, .main, .cleanup });
    try manager.registerPhase(.main, skip_handler, null);

    const result = manager.processTurn();

    try std.testing.expect(result.success);
    try std.testing.expectEqual(@as(usize, 2), result.phases_completed); // setup + main
    try std.testing.expectEqual(@as(usize, 1), result.phases_skipped); // cleanup
}

test "TurnManager - getProgress" {
    var manager = TurnManager(TestPhase).init(std.testing.allocator);
    defer manager.deinit();

    try manager.setPhaseOrder(&.{ .setup, .main, .combat, .cleanup });

    try std.testing.expectEqual(@as(f32, 0.0), manager.getProgress());

    manager.current_phase_index = 2;
    try std.testing.expectEqual(@as(f32, 0.5), manager.getProgress());

    manager.current_phase_index = 4;
    try std.testing.expectEqual(@as(f32, 1.0), manager.getProgress());
}

test "TurnManager - getCurrentPhase" {
    var manager = TurnManager(TestPhase).init(std.testing.allocator);
    defer manager.deinit();

    try manager.setPhaseOrder(&.{ .setup, .main, .cleanup });

    manager.current_phase_index = 0;
    try std.testing.expectEqual(TestPhase.setup, manager.getCurrentPhase().?);

    manager.current_phase_index = 1;
    try std.testing.expectEqual(TestPhase.main, manager.getCurrentPhase().?);

    manager.current_phase_index = 3;
    try std.testing.expect(manager.getCurrentPhase() == null);
}

test "TurnManager - hasPhaseCompleted" {
    var manager = TurnManager(TestPhase).init(std.testing.allocator);
    defer manager.deinit();

    try manager.setPhaseOrder(&.{ .setup, .main, .cleanup });
    manager.current_phase_index = 2; // At cleanup

    try std.testing.expect(manager.hasPhaseCompleted(.setup));
    try std.testing.expect(manager.hasPhaseCompleted(.main));
    try std.testing.expect(!manager.hasPhaseCompleted(.cleanup));
}

test "TurnManager - processPhase single" {
    var manager = TurnManager(TestPhase).init(std.testing.allocator);
    defer manager.deinit();

    var called = false;

    const handler = struct {
        fn callback(_: TestPhase, ctx: ?*anyopaque) PhaseResult {
            const flag: *bool = @ptrCast(@alignCast(ctx.?));
            flag.* = true;
            return .{ .success = true };
        }
    }.callback;

    try manager.registerPhase(.main, handler, &called);

    const result = manager.processPhase(.main);

    try std.testing.expect(result.success);
    try std.testing.expect(called);
}

test "TurnManager - nextTurn manual" {
    var manager = TurnManager(TestPhase).init(std.testing.allocator);
    defer manager.deinit();

    try std.testing.expectEqual(@as(u32, 0), manager.getTurnNumber());

    const turn1 = manager.nextTurn();
    try std.testing.expectEqual(@as(u32, 1), turn1);
    try std.testing.expectEqual(@as(u32, 1), manager.getTurnNumber());

    const turn2 = manager.nextTurn();
    try std.testing.expectEqual(@as(u32, 2), turn2);
}

test "TurnManager - reset" {
    var manager = TurnManager(TestPhase).init(std.testing.allocator);
    defer manager.deinit();

    try manager.setPhaseOrder(&.{.main});
    _ = manager.processTurn();
    _ = manager.processTurn();

    try std.testing.expectEqual(@as(u32, 2), manager.getTurnNumber());

    manager.reset();

    try std.testing.expectEqual(@as(u32, 0), manager.getTurnNumber());
    try std.testing.expectEqual(@as(usize, 0), manager.current_phase_index);
}

test "TurnManager - setTurnNumber" {
    var manager = TurnManager(TestPhase).init(std.testing.allocator);
    defer manager.deinit();

    manager.setTurnNumber(100);
    try std.testing.expectEqual(@as(u32, 100), manager.getTurnNumber());
}

test "TurnManager - lifecycle callbacks" {
    var manager = TurnManager(TestPhase).init(std.testing.allocator);
    defer manager.deinit();

    const State = struct {
        turn_started: bool = false,
        turn_ended: bool = false,
        phases_started: u32 = 0,
        phases_ended: u32 = 0,
    };

    var state = State{};

    const Callbacks = struct {
        fn onTurnStart(_: u32, ctx: ?*anyopaque) void {
            const s: *State = @ptrCast(@alignCast(ctx.?));
            s.turn_started = true;
        }

        fn onTurnEnd(_: u32, ctx: ?*anyopaque) void {
            const s: *State = @ptrCast(@alignCast(ctx.?));
            s.turn_ended = true;
        }

        fn onPhaseStart(_: TestPhase, ctx: ?*anyopaque) void {
            const s: *State = @ptrCast(@alignCast(ctx.?));
            s.phases_started += 1;
        }

        fn onPhaseEnd(_: TestPhase, _: PhaseResult, ctx: ?*anyopaque) void {
            const s: *State = @ptrCast(@alignCast(ctx.?));
            s.phases_ended += 1;
        }
    };

    manager.setCallbacks(
        Callbacks.onTurnStart,
        Callbacks.onTurnEnd,
        Callbacks.onPhaseStart,
        Callbacks.onPhaseEnd,
        &state,
    );

    try manager.setPhaseOrder(&.{ .setup, .main, .cleanup });
    _ = manager.processTurn();

    try std.testing.expect(state.turn_started);
    try std.testing.expect(state.turn_ended);
    try std.testing.expectEqual(@as(u32, 3), state.phases_started);
    try std.testing.expectEqual(@as(u32, 3), state.phases_ended);
}

test "TurnManager - profiling enabled" {
    var manager = TurnManager(TestPhase).initWithConfig(std.testing.allocator, .{
        .profiling_enabled = true,
    });
    defer manager.deinit();

    try manager.setPhaseOrder(&.{ .setup, .main, .cleanup });

    const result = manager.processTurn();

    try std.testing.expect(result.total_duration_ns > 0);
}

test "TurnManager - max_phases limit" {
    var manager = TurnManager(TestPhase).initWithConfig(std.testing.allocator, .{
        .max_phases = 2,
    });
    defer manager.deinit();

    try manager.setPhaseOrder(&.{ .setup, .main, .combat, .cleanup });

    const result = manager.processTurn();

    try std.testing.expect(result.success);
    try std.testing.expectEqual(@as(usize, 2), result.phases_completed);
    try std.testing.expectEqual(@as(usize, 2), result.phases_skipped);
}

test "TurnManager - unregisterPhase" {
    var manager = TurnManager(TestPhase).init(std.testing.allocator);
    defer manager.deinit();

    var call_count: u32 = 0;

    const handler = struct {
        fn callback(_: TestPhase, ctx: ?*anyopaque) PhaseResult {
            const count: *u32 = @ptrCast(@alignCast(ctx.?));
            count.* += 1;
            return .{ .success = true };
        }
    }.callback;

    try manager.setPhaseOrder(&.{.main});
    try manager.registerPhase(.main, handler, &call_count);

    _ = manager.processTurn();
    try std.testing.expectEqual(@as(u32, 1), call_count);

    const removed = manager.unregisterPhase(.main);
    try std.testing.expect(removed);

    _ = manager.processTurn();
    try std.testing.expectEqual(@as(u32, 1), call_count); // Still 1, handler not called
}

test "TurnManager - empty phase order" {
    var manager = TurnManager(TestPhase).init(std.testing.allocator);
    defer manager.deinit();

    const result = manager.processTurn();

    try std.testing.expect(result.success);
    try std.testing.expectEqual(@as(u32, 1), result.turn_number);
    try std.testing.expectEqual(@as(usize, 0), result.phases_completed);
}

test "TurnManager - prevents concurrent processing" {
    var manager = TurnManager(TestPhase).init(std.testing.allocator);
    defer manager.deinit();

    manager.is_processing = true;

    const result = manager.processTurn();

    try std.testing.expect(!result.success);
    try std.testing.expectEqualStrings("Turn already in progress", result.error_message.?);
}
