//! Command Queue System
//!
//! A command pattern implementation with validation, execution, history replay, and batching.
//! Commands are registered with type names, optional validators, and required executors.
//! Supports 8 parameter types matching the Agentite C implementation.
//!
//! ## Features
//! - Type registration with custom validators and executors
//! - FIFO command queue with sequence numbers
//! - Circular buffer history for replay (NOT traditional undo/redo)
//! - Command batching for grouped execution
//! - Statistics tracking (total and per-type)
//! - Post-execution callbacks
//!
//! ## Example
//! ```zig
//! var queue = CommandQueue.init(allocator);
//! defer queue.deinit();
//!
//! // Register a command type
//! _ = try queue.registerType(.{
//!     .name = "move_unit",
//!     .executor = executeMoveUnit,
//!     .validator = validateMoveUnit,
//! });
//!
//! // Queue a command
//! var builder = try queue.createCommand("move_unit", "player1");
//! _ = builder.setEntity("unit", 42).setInt("x", 10).setInt("y", 5);
//! try builder.submit();
//!
//! // Execute all queued commands
//! const result = queue.executeAll();
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;

// =============================================================================
// Constants
// =============================================================================

/// Maximum number of parameters per command
pub const MAX_PARAMS: usize = 16;

/// Maximum commands in queue
pub const MAX_QUEUE: usize = 64;

/// Maximum registered command types
pub const MAX_TYPES: usize = 64;

/// Maximum commands in history (circular buffer)
pub const MAX_HISTORY: usize = 256;

/// Maximum length for command type names
pub const MAX_NAME_LENGTH: usize = 63;

/// Maximum length for parameter keys
pub const MAX_KEY_LENGTH: usize = 31;

/// Maximum length for string parameter values
pub const MAX_STRING_LENGTH: usize = 255;

/// Maximum length for source identifier
pub const MAX_SOURCE_LENGTH: usize = 63;

// =============================================================================
// Parameter Types
// =============================================================================

/// Parameter value types supported by commands
pub const ParamType = enum(u8) {
    int32,
    int64,
    float32,
    float64,
    boolean,
    entity,
    string,
    pointer,
};

/// A command parameter value (tagged union)
pub const CommandParam = union(ParamType) {
    int32: i32,
    int64: i64,
    float32: f32,
    float64: f64,
    boolean: bool,
    entity: u32,
    string: []const u8,
    pointer: ?*anyopaque,

    /// Convert to integer (with coercion)
    pub fn toInt(self: CommandParam) i32 {
        return switch (self) {
            .int32 => |v| v,
            .int64 => |v| @intCast(@min(@max(v, std.math.minInt(i32)), std.math.maxInt(i32))),
            .float32 => |v| @intFromFloat(v),
            .float64 => |v| @intFromFloat(v),
            .boolean => |v| if (v) @as(i32, 1) else 0,
            .entity => |v| @intCast(v),
            .string => 0,
            .pointer => 0,
        };
    }

    /// Convert to 64-bit integer (with coercion)
    pub fn toInt64(self: CommandParam) i64 {
        return switch (self) {
            .int32 => |v| v,
            .int64 => |v| v,
            .float32 => |v| @intFromFloat(v),
            .float64 => |v| @intFromFloat(v),
            .boolean => |v| if (v) @as(i64, 1) else 0,
            .entity => |v| v,
            .string => 0,
            .pointer => 0,
        };
    }

    /// Convert to float (with coercion)
    pub fn toFloat(self: CommandParam) f32 {
        return switch (self) {
            .int32 => |v| @floatFromInt(v),
            .int64 => |v| @floatFromInt(v),
            .float32 => |v| v,
            .float64 => |v| @floatCast(v),
            .boolean => |v| if (v) @as(f32, 1.0) else 0.0,
            .entity => |v| @floatFromInt(v),
            .string => 0.0,
            .pointer => 0.0,
        };
    }

    /// Convert to 64-bit float (with coercion)
    pub fn toFloat64(self: CommandParam) f64 {
        return switch (self) {
            .int32 => |v| @floatFromInt(v),
            .int64 => |v| @floatFromInt(v),
            .float32 => |v| v,
            .float64 => |v| v,
            .boolean => |v| if (v) @as(f64, 1.0) else 0.0,
            .entity => |v| @floatFromInt(v),
            .string => 0.0,
            .pointer => 0.0,
        };
    }

    /// Convert to boolean
    pub fn toBool(self: CommandParam) bool {
        return switch (self) {
            .int32 => |v| v != 0,
            .int64 => |v| v != 0,
            .float32 => |v| v != 0.0,
            .float64 => |v| v != 0.0,
            .boolean => |v| v,
            .entity => |v| v != 0,
            .string => |v| v.len > 0,
            .pointer => |v| v != null,
        };
    }

    /// Convert to entity ID (0 if not applicable)
    pub fn toEntity(self: CommandParam) u32 {
        return switch (self) {
            .int32 => |v| if (v >= 0) @intCast(v) else 0,
            .int64 => |v| if (v >= 0 and v <= std.math.maxInt(u32)) @intCast(v) else 0,
            .float32 => |v| if (v >= 0) @intFromFloat(v) else 0,
            .float64 => |v| if (v >= 0) @intFromFloat(v) else 0,
            .boolean => |v| if (v) @as(u32, 1) else 0,
            .entity => |v| v,
            .string => 0,
            .pointer => 0,
        };
    }
};

// =============================================================================
// Stored Parameter (with inline storage)
// =============================================================================

/// Stored parameter with inline key and value storage
const StoredParam = struct {
    key: [MAX_KEY_LENGTH + 1]u8 = undefined,
    key_len: u8 = 0,
    value: CommandParam = .{ .int32 = 0 },
    // For string values, store data inline
    string_storage: [MAX_STRING_LENGTH + 1]u8 = undefined,
    string_len: u8 = 0,
    active: bool = false,

    fn init(key: []const u8, value: CommandParam) StoredParam {
        var param = StoredParam{};
        param.setKey(key);
        param.setValue(value);
        return param;
    }

    fn setKey(self: *StoredParam, key: []const u8) void {
        const len = @min(key.len, MAX_KEY_LENGTH);
        @memcpy(self.key[0..len], key[0..len]);
        self.key[len] = 0;
        self.key_len = @intCast(len);
        self.active = true;
    }

    fn setValue(self: *StoredParam, value: CommandParam) void {
        switch (value) {
            .string => |s| {
                const len = @min(s.len, MAX_STRING_LENGTH);
                @memcpy(self.string_storage[0..len], s[0..len]);
                self.string_storage[len] = 0;
                self.string_len = @intCast(len);
                self.value = .{ .string = self.string_storage[0..self.string_len] };
            },
            else => {
                self.value = value;
            },
        }
    }

    fn getKey(self: *const StoredParam) []const u8 {
        return self.key[0..self.key_len];
    }

    fn getValue(self: *const StoredParam) CommandParam {
        if (self.value == .string) {
            return .{ .string = self.string_storage[0..self.string_len] };
        }
        return self.value;
    }
};

// =============================================================================
// Command
// =============================================================================

/// A command with parameters and metadata
pub const Command = struct {
    /// Command type ID (index into registered types)
    type_id: u16 = 0,
    /// Sequence number for ordering
    sequence: u64 = 0,
    /// Parameters (inline storage)
    params: [MAX_PARAMS]StoredParam = [_]StoredParam{.{}} ** MAX_PARAMS,
    param_count: u8 = 0,
    /// Source identifier (who issued the command)
    source: [MAX_SOURCE_LENGTH + 1]u8 = undefined,
    source_len: u8 = 0,
    /// Timestamp when queued (nanoseconds)
    timestamp: i128 = 0,
    /// Batch ID (0 = not part of batch)
    batch_id: u64 = 0,

    /// Set source identifier
    pub fn setSource(self: *Command, src: []const u8) void {
        const len = @min(src.len, MAX_SOURCE_LENGTH);
        @memcpy(self.source[0..len], src[0..len]);
        self.source[len] = 0;
        self.source_len = @intCast(len);
    }

    /// Get source identifier
    pub fn getSource(self: *const Command) []const u8 {
        return self.source[0..self.source_len];
    }

    /// Set parameter by key
    pub fn setParam(self: *Command, key: []const u8, value: CommandParam) bool {
        // Check if key already exists
        for (&self.params) |*param| {
            if (param.active and std.mem.eql(u8, param.getKey(), key)) {
                param.setValue(value);
                return true;
            }
        }
        // Add new parameter
        if (self.param_count >= MAX_PARAMS) return false;
        self.params[self.param_count] = StoredParam.init(key, value);
        self.param_count += 1;
        return true;
    }

    /// Get parameter by key
    pub fn getParam(self: *const Command, key: []const u8) ?CommandParam {
        for (&self.params) |*param| {
            if (param.active and std.mem.eql(u8, param.getKey(), key)) {
                return param.getValue();
            }
        }
        return null;
    }

    /// Get parameter as i32 with default
    pub fn getIntOr(self: *const Command, key: []const u8, default: i32) i32 {
        if (self.getParam(key)) |p| return p.toInt();
        return default;
    }

    /// Get parameter as i64 with default
    pub fn getInt64Or(self: *const Command, key: []const u8, default: i64) i64 {
        if (self.getParam(key)) |p| return p.toInt64();
        return default;
    }

    /// Get parameter as f32 with default
    pub fn getFloatOr(self: *const Command, key: []const u8, default: f32) f32 {
        if (self.getParam(key)) |p| return p.toFloat();
        return default;
    }

    /// Get parameter as f64 with default
    pub fn getFloat64Or(self: *const Command, key: []const u8, default: f64) f64 {
        if (self.getParam(key)) |p| return p.toFloat64();
        return default;
    }

    /// Get parameter as bool with default
    pub fn getBoolOr(self: *const Command, key: []const u8, default: bool) bool {
        if (self.getParam(key)) |p| return p.toBool();
        return default;
    }

    /// Get parameter as entity with default
    pub fn getEntityOr(self: *const Command, key: []const u8, default: u32) u32 {
        if (self.getParam(key)) |p| return p.toEntity();
        return default;
    }

    /// Get parameter as string with default
    pub fn getStringOr(self: *const Command, key: []const u8, default: []const u8) []const u8 {
        if (self.getParam(key)) |p| {
            if (p == .string) return p.string;
        }
        return default;
    }

    /// Get parameter as pointer (null if not found or not a pointer)
    pub fn getPointer(self: *const Command, key: []const u8) ?*anyopaque {
        if (self.getParam(key)) |p| {
            if (p == .pointer) return p.pointer;
        }
        return null;
    }

    /// Get parameter count
    pub fn getParamCount(self: *const Command) u8 {
        return self.param_count;
    }

    /// Check if command has parameter
    pub fn hasParam(self: *const Command, key: []const u8) bool {
        return self.getParam(key) != null;
    }

    /// Clone this command (deep copy)
    pub fn clone(self: *const Command) Command {
        var copy = self.*;
        // Fix up string pointers to point to copy's storage
        for (&copy.params, 0..) |*param, i| {
            if (param.active and self.params[i].value == .string) {
                param.value = .{ .string = param.string_storage[0..param.string_len] };
            }
        }
        return copy;
    }
};

// =============================================================================
// Execution Result
// =============================================================================

/// Result of command execution
pub const ExecutionStatus = enum {
    success,
    failed,
    invalid,
    skipped,
};

/// Detailed execution outcome
pub const CommandResult = struct {
    status: ExecutionStatus = .success,
    error_message: ?[]const u8 = null,
    /// Return value (optional)
    return_value: ?CommandParam = null,
};

/// Result of executing all commands
pub const ExecuteAllResult = struct {
    executed: usize = 0,
    succeeded: usize = 0,
    failed: usize = 0,
    invalid: usize = 0,
    remaining: usize = 0,
    /// First failure (if any)
    first_failure: ?CommandResult = null,
    /// Sequence of first failed command
    first_failure_sequence: ?u64 = null,
};

// =============================================================================
// Callbacks
// =============================================================================

/// Validator callback - returns true if command is valid
pub const ValidatorFn = *const fn (cmd: *const Command, context: ?*anyopaque) bool;

/// Executor callback - executes the command
pub const ExecutorFn = *const fn (cmd: *const Command, context: ?*anyopaque) CommandResult;

/// Post-execution callback
pub const PostExecutionFn = *const fn (cmd: *const Command, result: CommandResult, context: ?*anyopaque) void;

// =============================================================================
// Command Type Registration
// =============================================================================

/// Stored command type registration
const StoredCommandType = struct {
    name: [MAX_NAME_LENGTH + 1]u8 = undefined,
    name_len: u8 = 0,
    executor: ?ExecutorFn = null,
    validator: ?ValidatorFn = null,
    executor_context: ?*anyopaque = null,
    validator_context: ?*anyopaque = null,
    description: [MAX_STRING_LENGTH + 1]u8 = undefined,
    description_len: u8 = 0,
    active: bool = false,

    fn getName(self: *const StoredCommandType) []const u8 {
        return self.name[0..self.name_len];
    }

    fn getDescription(self: *const StoredCommandType) []const u8 {
        return self.description[0..self.description_len];
    }

    fn setName(self: *StoredCommandType, name_str: []const u8) void {
        const len = @min(name_str.len, MAX_NAME_LENGTH);
        @memcpy(self.name[0..len], name_str[0..len]);
        self.name[len] = 0;
        self.name_len = @intCast(len);
    }

    fn setDescription(self: *StoredCommandType, desc: []const u8) void {
        const len = @min(desc.len, MAX_STRING_LENGTH);
        @memcpy(self.description[0..len], desc[0..len]);
        self.description[len] = 0;
        self.description_len = @intCast(len);
    }
};

/// Options for registering a command type
pub const CommandTypeOptions = struct {
    /// Command type name
    name: []const u8,
    /// Required executor function
    executor: ExecutorFn,
    /// Optional validator function
    validator: ?ValidatorFn = null,
    /// Context for executor
    executor_context: ?*anyopaque = null,
    /// Context for validator
    validator_context: ?*anyopaque = null,
    /// Description for debugging/UI
    description: []const u8 = "",
};

// =============================================================================
// Statistics
// =============================================================================

/// Command queue statistics
pub const CommandQueueStats = struct {
    total_executed: u64 = 0,
    total_succeeded: u64 = 0,
    total_failed: u64 = 0,
    total_invalid: u64 = 0,
    total_queued: u64 = 0,
    current_queue_size: usize = 0,
    history_size: usize = 0,
    registered_types: usize = 0,
};

// =============================================================================
// Configuration
// =============================================================================

/// Configuration for CommandQueue
pub const CommandQueueConfig = struct {
    /// Enable history recording
    history_enabled: bool = true,
    /// Continue executing after failures
    continue_on_failure: bool = true,
};

// =============================================================================
// Command Builder (Fluent API)
// =============================================================================

/// Builder for constructing commands with fluent API
pub const CommandBuilder = struct {
    queue: *CommandQueue,
    command: Command,
    validate_on_submit: bool,

    /// Set integer parameter
    pub fn setInt(self: *CommandBuilder, key: []const u8, value: i32) *CommandBuilder {
        _ = self.command.setParam(key, .{ .int32 = value });
        return self;
    }

    /// Set 64-bit integer parameter
    pub fn setInt64(self: *CommandBuilder, key: []const u8, value: i64) *CommandBuilder {
        _ = self.command.setParam(key, .{ .int64 = value });
        return self;
    }

    /// Set float parameter
    pub fn setFloat(self: *CommandBuilder, key: []const u8, value: f32) *CommandBuilder {
        _ = self.command.setParam(key, .{ .float32 = value });
        return self;
    }

    /// Set 64-bit float parameter
    pub fn setFloat64(self: *CommandBuilder, key: []const u8, value: f64) *CommandBuilder {
        _ = self.command.setParam(key, .{ .float64 = value });
        return self;
    }

    /// Set boolean parameter
    pub fn setBool(self: *CommandBuilder, key: []const u8, value: bool) *CommandBuilder {
        _ = self.command.setParam(key, .{ .boolean = value });
        return self;
    }

    /// Set entity parameter
    pub fn setEntity(self: *CommandBuilder, key: []const u8, entity_id: u32) *CommandBuilder {
        _ = self.command.setParam(key, .{ .entity = entity_id });
        return self;
    }

    /// Set string parameter
    pub fn setString(self: *CommandBuilder, key: []const u8, value: []const u8) *CommandBuilder {
        _ = self.command.setParam(key, .{ .string = value });
        return self;
    }

    /// Set pointer parameter
    pub fn setPointer(self: *CommandBuilder, key: []const u8, ptr: ?*anyopaque) *CommandBuilder {
        _ = self.command.setParam(key, .{ .pointer = ptr });
        return self;
    }

    /// Build and submit the command to queue
    pub fn submit(self: *CommandBuilder) !void {
        if (self.validate_on_submit) {
            if (!self.queue.validateCommand(&self.command)) {
                return error.ValidationFailed;
            }
        }
        try self.queue.submitCommand(self.command);
    }

    /// Build command without submitting (for inspection)
    pub fn build(self: *CommandBuilder) Command {
        return self.command;
    }
};

// =============================================================================
// Command Queue
// =============================================================================

/// Command queue for sequential command execution
pub const CommandQueue = struct {
    allocator: Allocator,
    config: CommandQueueConfig,

    // Command type registry (fixed array for inline storage)
    types: [MAX_TYPES]StoredCommandType = [_]StoredCommandType{.{}} ** MAX_TYPES,
    type_count: usize = 0,

    // Command queue (ArrayList for dynamic sizing)
    queue: std.ArrayList(Command),

    // History (circular buffer for replay)
    history: [MAX_HISTORY]Command = undefined,
    history_head: usize = 0,
    history_count: usize = 0,

    // State
    next_sequence: u64 = 1,
    next_batch_id: u64 = 1,
    current_batch: u64 = 0, // 0 = not in batch
    is_executing: bool = false,

    // Callbacks
    post_execution_callback: ?PostExecutionFn = null,
    post_execution_context: ?*anyopaque = null,

    // Statistics
    stats: CommandQueueStats = .{},

    // Current builder (for fluent API)
    current_builder: ?CommandBuilder = null,

    // ========================================================================
    // Initialization
    // ========================================================================

    /// Initialize with default configuration
    pub fn init(allocator: Allocator) CommandQueue {
        return initWithConfig(allocator, .{});
    }

    /// Initialize with custom configuration
    pub fn initWithConfig(allocator: Allocator, config: CommandQueueConfig) CommandQueue {
        return CommandQueue{
            .allocator = allocator,
            .config = config,
            .queue = std.ArrayList(Command).init(allocator),
        };
    }

    /// Clean up resources
    pub fn deinit(self: *CommandQueue) void {
        self.queue.deinit();
    }

    // ========================================================================
    // Type Registration
    // ========================================================================

    /// Register a command type
    pub fn registerType(self: *CommandQueue, options: CommandTypeOptions) !u16 {
        // Check if type already exists
        if (self.findTypeIndex(options.name) != null) {
            return error.TypeAlreadyExists;
        }

        // Find free slot
        if (self.type_count >= MAX_TYPES) {
            return error.TooManyTypes;
        }

        const index = self.type_count;
        self.types[index].setName(options.name);
        self.types[index].executor = options.executor;
        self.types[index].validator = options.validator;
        self.types[index].executor_context = options.executor_context;
        self.types[index].validator_context = options.validator_context;
        if (options.description.len > 0) {
            self.types[index].setDescription(options.description);
        }
        self.types[index].active = true;
        self.type_count += 1;
        self.stats.registered_types = self.type_count;

        return @intCast(index);
    }

    /// Unregister a command type (marks inactive)
    pub fn unregisterType(self: *CommandQueue, name: []const u8) bool {
        if (self.findTypeIndex(name)) |index| {
            self.types[index].active = false;
            return true;
        }
        return false;
    }

    /// Check if type is registered and active
    pub fn hasType(self: *const CommandQueue, name: []const u8) bool {
        if (self.findTypeIndex(name)) |index| {
            return self.types[index].active;
        }
        return false;
    }

    /// Get type ID by name
    pub fn getTypeId(self: *const CommandQueue, name: []const u8) ?u16 {
        if (self.findTypeIndex(name)) |index| {
            if (self.types[index].active) {
                return @intCast(index);
            }
        }
        return null;
    }

    /// Get type name by ID
    pub fn getTypeName(self: *const CommandQueue, type_id: u16) ?[]const u8 {
        if (type_id < self.type_count and self.types[type_id].active) {
            return self.types[type_id].getName();
        }
        return null;
    }

    /// Get registered type count
    pub fn getTypeCount(self: *const CommandQueue) usize {
        var count: usize = 0;
        for (0..self.type_count) |i| {
            if (self.types[i].active) count += 1;
        }
        return count;
    }

    // ========================================================================
    // Queue Operations
    // ========================================================================

    /// Create a command builder (skips validation on submit)
    pub fn createCommand(self: *CommandQueue, type_name: []const u8, source: []const u8) !*CommandBuilder {
        const type_id = self.getTypeId(type_name) orelse return error.UnknownType;

        self.current_builder = CommandBuilder{
            .queue = self,
            .command = Command{
                .type_id = type_id,
                .sequence = 0, // Set on submit
                .timestamp = 0, // Set on submit
                .batch_id = self.current_batch,
            },
            .validate_on_submit = false,
        };
        self.current_builder.?.command.setSource(source);

        return &self.current_builder.?;
    }

    /// Create a command builder with validation on submit
    pub fn createValidatedCommand(self: *CommandQueue, type_name: []const u8, source: []const u8) !*CommandBuilder {
        const type_id = self.getTypeId(type_name) orelse return error.UnknownType;

        self.current_builder = CommandBuilder{
            .queue = self,
            .command = Command{
                .type_id = type_id,
                .sequence = 0,
                .timestamp = 0,
                .batch_id = self.current_batch,
            },
            .validate_on_submit = true,
        };
        self.current_builder.?.command.setSource(source);

        return &self.current_builder.?;
    }

    /// Submit a command to the queue (internal)
    fn submitCommand(self: *CommandQueue, cmd: Command) !void {
        if (self.queue.items.len >= MAX_QUEUE) {
            return error.QueueFull;
        }

        var command = cmd;
        command.sequence = self.next_sequence;
        command.timestamp = std.time.nanoTimestamp();
        self.next_sequence += 1;

        try self.queue.append(command);
        self.stats.total_queued += 1;
        self.stats.current_queue_size = self.queue.items.len;
    }

    /// Queue a command directly (for advanced use)
    pub fn queueDirect(self: *CommandQueue, cmd: Command) !void {
        try self.submitCommand(cmd);
    }

    /// Execute next command in queue
    pub fn executeNext(self: *CommandQueue) ?CommandResult {
        if (self.queue.items.len == 0) return null;

        self.is_executing = true;
        defer self.is_executing = false;

        const cmd = self.queue.orderedRemove(0);
        self.stats.current_queue_size = self.queue.items.len;

        const result = self.executeCommand(&cmd);

        // Add to history if enabled
        if (self.config.history_enabled and result.status == .success) {
            self.addToHistory(cmd);
        }

        // Call post-execution callback
        if (self.post_execution_callback) |callback| {
            callback(&cmd, result, self.post_execution_context);
        }

        return result;
    }

    /// Execute all commands in queue
    pub fn executeAll(self: *CommandQueue) ExecuteAllResult {
        var result = ExecuteAllResult{};

        while (self.queue.items.len > 0) {
            if (self.executeNext()) |cmd_result| {
                result.executed += 1;
                switch (cmd_result.status) {
                    .success => result.succeeded += 1,
                    .failed => {
                        result.failed += 1;
                        if (result.first_failure == null) {
                            result.first_failure = cmd_result;
                        }
                        if (!self.config.continue_on_failure) {
                            result.remaining = self.queue.items.len;
                            return result;
                        }
                    },
                    .invalid => {
                        result.invalid += 1;
                        if (result.first_failure == null) {
                            result.first_failure = cmd_result;
                        }
                    },
                    .skipped => {},
                }
            }
        }

        return result;
    }

    /// Clear the queue without executing
    pub fn clear(self: *CommandQueue) void {
        self.queue.clearRetainingCapacity();
        self.stats.current_queue_size = 0;
    }

    /// Get number of pending commands
    pub fn getPendingCount(self: *const CommandQueue) usize {
        return self.queue.items.len;
    }

    /// Check if queue is empty
    pub fn isEmpty(self: *const CommandQueue) bool {
        return self.queue.items.len == 0;
    }

    /// Peek at next command without removing
    pub fn peek(self: *const CommandQueue) ?*const Command {
        if (self.queue.items.len == 0) return null;
        return &self.queue.items[0];
    }

    /// Get command at index
    pub fn getAt(self: *const CommandQueue, index: usize) ?*const Command {
        if (index >= self.queue.items.len) return null;
        return &self.queue.items[index];
    }

    // ========================================================================
    // Validation
    // ========================================================================

    /// Validate a command against its type's validator
    pub fn validateCommand(self: *const CommandQueue, cmd: *const Command) bool {
        if (cmd.type_id >= self.type_count) return false;

        const cmd_type = &self.types[cmd.type_id];
        if (!cmd_type.active) return false;

        if (cmd_type.validator) |validator| {
            return validator(cmd, cmd_type.validator_context);
        }

        // No validator = always valid
        return true;
    }

    // ========================================================================
    // History Operations (Replay)
    // ========================================================================

    /// Enable/disable history recording
    pub fn setHistoryEnabled(self: *CommandQueue, enabled: bool) void {
        self.config.history_enabled = enabled;
    }

    /// Get history count
    pub fn getHistoryCount(self: *const CommandQueue) usize {
        return self.history_count;
    }

    /// Clear history
    pub fn clearHistory(self: *CommandQueue) void {
        self.history_count = 0;
        self.history_head = 0;
        self.stats.history_size = 0;
    }

    /// Get command from history by index (0 = most recent)
    pub fn getHistoryAt(self: *const CommandQueue, index: usize) ?*const Command {
        if (index >= self.history_count) return null;

        // Calculate actual index in circular buffer (newest first)
        const actual_index = if (self.history_head >= index + 1)
            self.history_head - index - 1
        else
            MAX_HISTORY - (index + 1 - self.history_head);

        return &self.history[actual_index];
    }

    /// Replay commands from history by sequence range
    pub fn replay(self: *CommandQueue, from_sequence: u64, to_sequence: u64) !usize {
        var count: usize = 0;

        // Find and re-queue commands in sequence range
        for (0..self.history_count) |i| {
            if (self.getHistoryAt(i)) |cmd| {
                if (cmd.sequence >= from_sequence and cmd.sequence <= to_sequence) {
                    // Clone and re-queue
                    var clone = cmd.clone();
                    clone.sequence = self.next_sequence;
                    clone.timestamp = std.time.nanoTimestamp();
                    self.next_sequence += 1;
                    try self.queue.append(clone);
                    count += 1;
                }
            }
        }

        self.stats.current_queue_size = self.queue.items.len;
        return count;
    }

    /// Replay last N commands from history
    pub fn replayLast(self: *CommandQueue, count: usize) !usize {
        const actual_count = @min(count, self.history_count);
        var replayed: usize = 0;

        for (0..actual_count) |i| {
            if (self.getHistoryAt(actual_count - 1 - i)) |cmd| {
                var clone = cmd.clone();
                clone.sequence = self.next_sequence;
                clone.timestamp = std.time.nanoTimestamp();
                self.next_sequence += 1;
                try self.queue.append(clone);
                replayed += 1;
            }
        }

        self.stats.current_queue_size = self.queue.items.len;
        return replayed;
    }

    // ========================================================================
    // Batching
    // ========================================================================

    /// Begin a command batch (atomic execution group)
    pub fn beginBatch(self: *CommandQueue) u64 {
        self.current_batch = self.next_batch_id;
        self.next_batch_id += 1;
        return self.current_batch;
    }

    /// End current batch
    pub fn endBatch(self: *CommandQueue) void {
        self.current_batch = 0;
    }

    /// Check if in batch mode
    pub fn isInBatch(self: *const CommandQueue) bool {
        return self.current_batch != 0;
    }

    /// Get current batch ID
    pub fn getCurrentBatchId(self: *const CommandQueue) u64 {
        return self.current_batch;
    }

    // ========================================================================
    // Callbacks
    // ========================================================================

    /// Set post-execution callback
    pub fn setPostExecutionCallback(
        self: *CommandQueue,
        callback: ?PostExecutionFn,
        context: ?*anyopaque,
    ) void {
        self.post_execution_callback = callback;
        self.post_execution_context = context;
    }

    // ========================================================================
    // Statistics
    // ========================================================================

    /// Get statistics
    pub fn getStats(self: *const CommandQueue) CommandQueueStats {
        var stats = self.stats;
        stats.current_queue_size = self.queue.items.len;
        stats.history_size = self.history_count;
        stats.registered_types = self.getTypeCount();
        return stats;
    }

    /// Reset statistics
    pub fn resetStats(self: *CommandQueue) void {
        self.stats = .{};
        self.stats.current_queue_size = self.queue.items.len;
        self.stats.history_size = self.history_count;
        self.stats.registered_types = self.getTypeCount();
    }

    // ========================================================================
    // Internal Methods
    // ========================================================================

    fn findTypeIndex(self: *const CommandQueue, name: []const u8) ?usize {
        for (0..self.type_count) |i| {
            if (std.mem.eql(u8, self.types[i].getName(), name)) {
                return i;
            }
        }
        return null;
    }

    fn addToHistory(self: *CommandQueue, cmd: Command) void {
        self.history[self.history_head] = cmd.clone();
        self.history_head = (self.history_head + 1) % MAX_HISTORY;
        if (self.history_count < MAX_HISTORY) {
            self.history_count += 1;
        }
        self.stats.history_size = self.history_count;
    }

    fn executeCommand(self: *CommandQueue, cmd: *const Command) CommandResult {
        if (cmd.type_id >= self.type_count) {
            self.stats.total_invalid += 1;
            return .{ .status = .invalid, .error_message = "Unknown command type" };
        }

        const cmd_type = &self.types[cmd.type_id];
        if (!cmd_type.active) {
            self.stats.total_invalid += 1;
            return .{ .status = .invalid, .error_message = "Command type inactive" };
        }

        // Validate if validator exists
        if (cmd_type.validator) |validator| {
            if (!validator(cmd, cmd_type.validator_context)) {
                self.stats.total_invalid += 1;
                return .{ .status = .invalid, .error_message = "Validation failed" };
            }
        }

        // Execute
        self.stats.total_executed += 1;

        if (cmd_type.executor) |executor| {
            const result = executor(cmd, cmd_type.executor_context);
            switch (result.status) {
                .success => self.stats.total_succeeded += 1,
                .failed => self.stats.total_failed += 1,
                .invalid => self.stats.total_invalid += 1,
                .skipped => {},
            }
            return result;
        }

        self.stats.total_failed += 1;
        return .{ .status = .failed, .error_message = "No executor" };
    }
};

// =============================================================================
// Tests
// =============================================================================

test "CommandQueue: init and deinit" {
    var queue = CommandQueue.init(std.testing.allocator);
    defer queue.deinit();

    try std.testing.expect(queue.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), queue.getPendingCount());
    try std.testing.expectEqual(@as(usize, 0), queue.getTypeCount());
}

test "CommandQueue: register type" {
    var queue = CommandQueue.init(std.testing.allocator);
    defer queue.deinit();

    const type_id = try queue.registerType(.{
        .name = "test_command",
        .executor = struct {
            fn exec(_: *const Command, _: ?*anyopaque) CommandResult {
                return .{ .status = .success };
            }
        }.exec,
    });

    try std.testing.expectEqual(@as(u16, 0), type_id);
    try std.testing.expect(queue.hasType("test_command"));
    try std.testing.expectEqual(@as(usize, 1), queue.getTypeCount());
}

test "CommandQueue: register duplicate type error" {
    var queue = CommandQueue.init(std.testing.allocator);
    defer queue.deinit();

    _ = try queue.registerType(.{
        .name = "test_command",
        .executor = struct {
            fn exec(_: *const Command, _: ?*anyopaque) CommandResult {
                return .{ .status = .success };
            }
        }.exec,
    });

    const result = queue.registerType(.{
        .name = "test_command",
        .executor = struct {
            fn exec(_: *const Command, _: ?*anyopaque) CommandResult {
                return .{ .status = .success };
            }
        }.exec,
    });

    try std.testing.expectError(error.TypeAlreadyExists, result);
}

test "CommandQueue: unregister type" {
    var queue = CommandQueue.init(std.testing.allocator);
    defer queue.deinit();

    _ = try queue.registerType(.{
        .name = "test_command",
        .executor = struct {
            fn exec(_: *const Command, _: ?*anyopaque) CommandResult {
                return .{ .status = .success };
            }
        }.exec,
    });

    try std.testing.expect(queue.hasType("test_command"));
    try std.testing.expect(queue.unregisterType("test_command"));
    try std.testing.expect(!queue.hasType("test_command"));
}

test "CommandParam: all param types" {
    var cmd = Command{};

    _ = cmd.setParam("int", .{ .int32 = 42 });
    _ = cmd.setParam("int64", .{ .int64 = 9999999999 });
    _ = cmd.setParam("float", .{ .float32 = 3.14 });
    _ = cmd.setParam("float64", .{ .float64 = 3.14159265359 });
    _ = cmd.setParam("bool", .{ .boolean = true });
    _ = cmd.setParam("entity", .{ .entity = 100 });
    _ = cmd.setParam("string", .{ .string = "hello" });

    try std.testing.expectEqual(@as(i32, 42), cmd.getIntOr("int", 0));
    try std.testing.expectEqual(@as(i64, 9999999999), cmd.getInt64Or("int64", 0));
    try std.testing.expectApproxEqAbs(@as(f32, 3.14), cmd.getFloatOr("float", 0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 3.14159265359), cmd.getFloat64Or("float64", 0), 0.0001);
    try std.testing.expect(cmd.getBoolOr("bool", false));
    try std.testing.expectEqual(@as(u32, 100), cmd.getEntityOr("entity", 0));
    try std.testing.expectEqualStrings("hello", cmd.getStringOr("string", ""));
}

test "CommandParam: type coercion" {
    const int_param = CommandParam{ .int32 = 42 };
    try std.testing.expectApproxEqAbs(@as(f32, 42.0), int_param.toFloat(), 0.001);
    try std.testing.expect(int_param.toBool());

    const float_param = CommandParam{ .float32 = 3.7 };
    try std.testing.expectEqual(@as(i32, 3), float_param.toInt());

    const bool_param = CommandParam{ .boolean = true };
    try std.testing.expectEqual(@as(i32, 1), bool_param.toInt());
}

test "CommandParam: default values" {
    var cmd = Command{};

    try std.testing.expectEqual(@as(i32, 99), cmd.getIntOr("missing", 99));
    try std.testing.expectEqual(@as(f32, 1.5), cmd.getFloatOr("missing", 1.5));
    try std.testing.expect(!cmd.getBoolOr("missing", false));
    try std.testing.expectEqualStrings("default", cmd.getStringOr("missing", "default"));
}

test "CommandQueue: queue and execute single" {
    var executed = false;

    var queue = CommandQueue.init(std.testing.allocator);
    defer queue.deinit();

    _ = try queue.registerType(.{
        .name = "test",
        .executor = struct {
            fn exec(_: *const Command, ctx: ?*anyopaque) CommandResult {
                const flag: *bool = @ptrCast(@alignCast(ctx.?));
                flag.* = true;
                return .{ .status = .success };
            }
        }.exec,
        .executor_context = &executed,
    });

    var builder = try queue.createCommand("test", "player1");
    try builder.submit();

    try std.testing.expectEqual(@as(usize, 1), queue.getPendingCount());

    const result = queue.executeNext();
    try std.testing.expect(result != null);
    try std.testing.expectEqual(ExecutionStatus.success, result.?.status);
    try std.testing.expect(executed);
    try std.testing.expect(queue.isEmpty());
}

test "CommandQueue: queue multiple FIFO order" {
    var order = std.ArrayList(i32).init(std.testing.allocator);
    defer order.deinit();

    var queue = CommandQueue.init(std.testing.allocator);
    defer queue.deinit();

    _ = try queue.registerType(.{
        .name = "numbered",
        .executor = struct {
            fn exec(cmd: *const Command, ctx: ?*anyopaque) CommandResult {
                const list: *std.ArrayList(i32) = @ptrCast(@alignCast(ctx.?));
                list.append(cmd.getIntOr("num", 0)) catch {};
                return .{ .status = .success };
            }
        }.exec,
        .executor_context = &order,
    });

    // Queue commands 1, 2, 3
    for ([_]i32{ 1, 2, 3 }) |n| {
        var builder = try queue.createCommand("numbered", "test");
        _ = builder.setInt("num", n);
        try builder.submit();
    }

    _ = queue.executeAll();

    // Should execute in FIFO order
    try std.testing.expectEqual(@as(i32, 1), order.items[0]);
    try std.testing.expectEqual(@as(i32, 2), order.items[1]);
    try std.testing.expectEqual(@as(i32, 3), order.items[2]);
}

test "CommandQueue: executeAll" {
    var count: u32 = 0;

    var queue = CommandQueue.init(std.testing.allocator);
    defer queue.deinit();

    _ = try queue.registerType(.{
        .name = "count",
        .executor = struct {
            fn exec(_: *const Command, ctx: ?*anyopaque) CommandResult {
                const c: *u32 = @ptrCast(@alignCast(ctx.?));
                c.* += 1;
                return .{ .status = .success };
            }
        }.exec,
        .executor_context = &count,
    });

    for (0..5) |_| {
        var builder = try queue.createCommand("count", "test");
        try builder.submit();
    }

    const result = queue.executeAll();

    try std.testing.expectEqual(@as(usize, 5), result.executed);
    try std.testing.expectEqual(@as(usize, 5), result.succeeded);
    try std.testing.expectEqual(@as(usize, 0), result.failed);
    try std.testing.expectEqual(@as(u32, 5), count);
}

test "CommandQueue: clear queue" {
    var queue = CommandQueue.init(std.testing.allocator);
    defer queue.deinit();

    _ = try queue.registerType(.{
        .name = "test",
        .executor = struct {
            fn exec(_: *const Command, _: ?*anyopaque) CommandResult {
                return .{ .status = .success };
            }
        }.exec,
    });

    for (0..3) |_| {
        var builder = try queue.createCommand("test", "test");
        try builder.submit();
    }

    try std.testing.expectEqual(@as(usize, 3), queue.getPendingCount());
    queue.clear();
    try std.testing.expect(queue.isEmpty());
}

test "CommandQueue: peek without remove" {
    var queue = CommandQueue.init(std.testing.allocator);
    defer queue.deinit();

    _ = try queue.registerType(.{
        .name = "test",
        .executor = struct {
            fn exec(_: *const Command, _: ?*anyopaque) CommandResult {
                return .{ .status = .success };
            }
        }.exec,
    });

    var builder = try queue.createCommand("test", "player1");
    _ = builder.setInt("value", 42);
    try builder.submit();

    const peeked = queue.peek();
    try std.testing.expect(peeked != null);
    try std.testing.expectEqual(@as(i32, 42), peeked.?.getIntOr("value", 0));

    // Should still be in queue
    try std.testing.expectEqual(@as(usize, 1), queue.getPendingCount());
}

test "CommandQueue: validation with validator" {
    var queue = CommandQueue.init(std.testing.allocator);
    defer queue.deinit();

    _ = try queue.registerType(.{
        .name = "validated",
        .executor = struct {
            fn exec(_: *const Command, _: ?*anyopaque) CommandResult {
                return .{ .status = .success };
            }
        }.exec,
        .validator = struct {
            fn validate(cmd: *const Command, _: ?*anyopaque) bool {
                return cmd.hasParam("required");
            }
        }.validate,
    });

    // With validation enabled, missing param should fail
    var builder1 = try queue.createValidatedCommand("validated", "test");
    const submit_result = builder1.submit();
    try std.testing.expectError(error.ValidationFailed, submit_result);

    // With required param, should succeed
    var builder2 = try queue.createValidatedCommand("validated", "test");
    _ = builder2.setInt("required", 1);
    try builder2.submit();

    try std.testing.expectEqual(@as(usize, 1), queue.getPendingCount());
}

test "CommandQueue: execution failure handling" {
    var queue = CommandQueue.init(std.testing.allocator);
    defer queue.deinit();

    _ = try queue.registerType(.{
        .name = "failing",
        .executor = struct {
            fn exec(_: *const Command, _: ?*anyopaque) CommandResult {
                return .{ .status = .failed, .error_message = "intentional failure" };
            }
        }.exec,
    });

    var builder = try queue.createCommand("failing", "test");
    try builder.submit();

    const result = queue.executeNext();
    try std.testing.expect(result != null);
    try std.testing.expectEqual(ExecutionStatus.failed, result.?.status);
    try std.testing.expectEqualStrings("intentional failure", result.?.error_message.?);
}

test "CommandQueue: continue on failure config" {
    var queue = CommandQueue.initWithConfig(std.testing.allocator, .{
        .continue_on_failure = false,
    });
    defer queue.deinit();

    var exec_count: u32 = 0;

    _ = try queue.registerType(.{
        .name = "test",
        .executor = struct {
            fn exec(cmd: *const Command, ctx: ?*anyopaque) CommandResult {
                const count: *u32 = @ptrCast(@alignCast(ctx.?));
                count.* += 1;
                if (cmd.getIntOr("fail", 0) == 1) {
                    return .{ .status = .failed };
                }
                return .{ .status = .success };
            }
        }.exec,
        .executor_context = &exec_count,
    });

    // Queue: success, fail, success
    var b1 = try queue.createCommand("test", "test");
    try b1.submit();

    var b2 = try queue.createCommand("test", "test");
    _ = b2.setInt("fail", 1);
    try b2.submit();

    var b3 = try queue.createCommand("test", "test");
    try b3.submit();

    const result = queue.executeAll();

    // Should stop after failure
    try std.testing.expectEqual(@as(usize, 2), result.executed);
    try std.testing.expectEqual(@as(usize, 1), result.remaining);
    try std.testing.expectEqual(@as(u32, 2), exec_count);
}

test "CommandQueue: history recording" {
    var queue = CommandQueue.init(std.testing.allocator);
    defer queue.deinit();

    _ = try queue.registerType(.{
        .name = "test",
        .executor = struct {
            fn exec(_: *const Command, _: ?*anyopaque) CommandResult {
                return .{ .status = .success };
            }
        }.exec,
    });

    for (0..3) |i| {
        var builder = try queue.createCommand("test", "test");
        _ = builder.setInt("num", @intCast(i));
        try builder.submit();
    }

    _ = queue.executeAll();

    try std.testing.expectEqual(@as(usize, 3), queue.getHistoryCount());

    // Most recent first
    const recent = queue.getHistoryAt(0);
    try std.testing.expect(recent != null);
    try std.testing.expectEqual(@as(i32, 2), recent.?.getIntOr("num", -1));
}

test "CommandQueue: history disabled" {
    var queue = CommandQueue.initWithConfig(std.testing.allocator, .{
        .history_enabled = false,
    });
    defer queue.deinit();

    _ = try queue.registerType(.{
        .name = "test",
        .executor = struct {
            fn exec(_: *const Command, _: ?*anyopaque) CommandResult {
                return .{ .status = .success };
            }
        }.exec,
    });

    var builder = try queue.createCommand("test", "test");
    try builder.submit();
    _ = queue.executeAll();

    try std.testing.expectEqual(@as(usize, 0), queue.getHistoryCount());
}

test "CommandQueue: replay last N" {
    var exec_order = std.ArrayList(i32).init(std.testing.allocator);
    defer exec_order.deinit();

    var queue = CommandQueue.init(std.testing.allocator);
    defer queue.deinit();

    _ = try queue.registerType(.{
        .name = "numbered",
        .executor = struct {
            fn exec(cmd: *const Command, ctx: ?*anyopaque) CommandResult {
                const list: *std.ArrayList(i32) = @ptrCast(@alignCast(ctx.?));
                list.append(cmd.getIntOr("num", 0)) catch {};
                return .{ .status = .success };
            }
        }.exec,
        .executor_context = &exec_order,
    });

    // Execute commands 1, 2, 3
    for ([_]i32{ 1, 2, 3 }) |n| {
        var builder = try queue.createCommand("numbered", "test");
        _ = builder.setInt("num", n);
        try builder.submit();
    }
    _ = queue.executeAll();

    // Clear execution order tracking
    exec_order.clearRetainingCapacity();

    // Replay last 2
    const replayed = try queue.replayLast(2);
    try std.testing.expectEqual(@as(usize, 2), replayed);
    _ = queue.executeAll();

    // Should have replayed 2 and 3
    try std.testing.expectEqual(@as(usize, 2), exec_order.items.len);
    try std.testing.expectEqual(@as(i32, 2), exec_order.items[0]);
    try std.testing.expectEqual(@as(i32, 3), exec_order.items[1]);
}

test "CommandQueue: begin and end batch" {
    var queue = CommandQueue.init(std.testing.allocator);
    defer queue.deinit();

    try std.testing.expect(!queue.isInBatch());

    const batch_id = queue.beginBatch();
    try std.testing.expect(batch_id > 0);
    try std.testing.expect(queue.isInBatch());
    try std.testing.expectEqual(batch_id, queue.getCurrentBatchId());

    queue.endBatch();
    try std.testing.expect(!queue.isInBatch());
}

test "CommandQueue: batch IDs assigned" {
    var queue = CommandQueue.init(std.testing.allocator);
    defer queue.deinit();

    _ = try queue.registerType(.{
        .name = "test",
        .executor = struct {
            fn exec(_: *const Command, _: ?*anyopaque) CommandResult {
                return .{ .status = .success };
            }
        }.exec,
    });

    // Command outside batch
    var b1 = try queue.createCommand("test", "test");
    try b1.submit();

    // Commands inside batch
    const batch_id = queue.beginBatch();
    var b2 = try queue.createCommand("test", "test");
    try b2.submit();
    var b3 = try queue.createCommand("test", "test");
    try b3.submit();
    queue.endBatch();

    // Check batch IDs
    try std.testing.expectEqual(@as(u64, 0), queue.getAt(0).?.batch_id);
    try std.testing.expectEqual(batch_id, queue.getAt(1).?.batch_id);
    try std.testing.expectEqual(batch_id, queue.getAt(2).?.batch_id);
}

test "CommandQueue: post execution callback" {
    const CallbackData = struct {
        call_count: u32 = 0,
        last_status: ExecutionStatus = .success,
    };

    var data = CallbackData{};

    var queue = CommandQueue.init(std.testing.allocator);
    defer queue.deinit();

    queue.setPostExecutionCallback(struct {
        fn callback(_: *const Command, result: CommandResult, ctx: ?*anyopaque) void {
            const cb_data: *CallbackData = @ptrCast(@alignCast(ctx.?));
            cb_data.call_count += 1;
            cb_data.last_status = result.status;
        }
    }.callback, &data);

    _ = try queue.registerType(.{
        .name = "test",
        .executor = struct {
            fn exec(_: *const Command, _: ?*anyopaque) CommandResult {
                return .{ .status = .success };
            }
        }.exec,
    });

    var builder = try queue.createCommand("test", "test");
    try builder.submit();
    _ = queue.executeNext();

    try std.testing.expectEqual(@as(u32, 1), data.call_count);
    try std.testing.expectEqual(ExecutionStatus.success, data.last_status);
}

test "CommandQueue: statistics tracking" {
    var queue = CommandQueue.init(std.testing.allocator);
    defer queue.deinit();

    _ = try queue.registerType(.{
        .name = "success",
        .executor = struct {
            fn exec(_: *const Command, _: ?*anyopaque) CommandResult {
                return .{ .status = .success };
            }
        }.exec,
    });

    _ = try queue.registerType(.{
        .name = "fail",
        .executor = struct {
            fn exec(_: *const Command, _: ?*anyopaque) CommandResult {
                return .{ .status = .failed };
            }
        }.exec,
    });

    var b1 = try queue.createCommand("success", "test");
    try b1.submit();
    var b2 = try queue.createCommand("success", "test");
    try b2.submit();
    var b3 = try queue.createCommand("fail", "test");
    try b3.submit();

    _ = queue.executeAll();

    const stats = queue.getStats();
    try std.testing.expectEqual(@as(u64, 3), stats.total_executed);
    try std.testing.expectEqual(@as(u64, 2), stats.total_succeeded);
    try std.testing.expectEqual(@as(u64, 1), stats.total_failed);
    try std.testing.expectEqual(@as(u64, 3), stats.total_queued);
}

test "CommandQueue: reset statistics" {
    var queue = CommandQueue.init(std.testing.allocator);
    defer queue.deinit();

    _ = try queue.registerType(.{
        .name = "test",
        .executor = struct {
            fn exec(_: *const Command, _: ?*anyopaque) CommandResult {
                return .{ .status = .success };
            }
        }.exec,
    });

    var builder = try queue.createCommand("test", "test");
    try builder.submit();
    _ = queue.executeAll();

    try std.testing.expect(queue.getStats().total_executed > 0);

    queue.resetStats();

    try std.testing.expectEqual(@as(u64, 0), queue.getStats().total_executed);
}

test "CommandQueue: empty queue operations" {
    var queue = CommandQueue.init(std.testing.allocator);
    defer queue.deinit();

    try std.testing.expect(queue.isEmpty());
    try std.testing.expect(queue.peek() == null);
    try std.testing.expect(queue.executeNext() == null);

    const result = queue.executeAll();
    try std.testing.expectEqual(@as(usize, 0), result.executed);
}

test "CommandQueue: unknown type error" {
    var queue = CommandQueue.init(std.testing.allocator);
    defer queue.deinit();

    const result = queue.createCommand("nonexistent", "test");
    try std.testing.expectError(error.UnknownType, result);
}

test "CommandQueue: sequence number increment" {
    var queue = CommandQueue.init(std.testing.allocator);
    defer queue.deinit();

    _ = try queue.registerType(.{
        .name = "test",
        .executor = struct {
            fn exec(_: *const Command, _: ?*anyopaque) CommandResult {
                return .{ .status = .success };
            }
        }.exec,
    });

    var b1 = try queue.createCommand("test", "test");
    try b1.submit();
    var b2 = try queue.createCommand("test", "test");
    try b2.submit();
    var b3 = try queue.createCommand("test", "test");
    try b3.submit();

    const seq1 = queue.getAt(0).?.sequence;
    const seq2 = queue.getAt(1).?.sequence;
    const seq3 = queue.getAt(2).?.sequence;

    try std.testing.expect(seq2 == seq1 + 1);
    try std.testing.expect(seq3 == seq2 + 1);
}

test "Command: clone preserves strings" {
    var original = Command{};
    _ = original.setParam("name", .{ .string = "test_value" });
    original.setSource("player1");

    const cloned = original.clone();

    try std.testing.expectEqualStrings("test_value", cloned.getStringOr("name", ""));
    try std.testing.expectEqualStrings("player1", cloned.getSource());
}

test "Command: max params limit" {
    var cmd = Command{};

    // Fill all params
    for (0..MAX_PARAMS) |i| {
        var key_buf: [32]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "key{d}", .{i}) catch unreachable;
        try std.testing.expect(cmd.setParam(key, .{ .int32 = @intCast(i) }));
    }

    // Should fail to add more
    try std.testing.expect(!cmd.setParam("overflow", .{ .int32 = 999 }));
}
