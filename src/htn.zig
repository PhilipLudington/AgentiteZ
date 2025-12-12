const std = @import("std");
const Allocator = std.mem.Allocator;
const blackboard = @import("blackboard.zig");

/// HTN (Hierarchical Task Network) Planner
///
/// Enables AI agents to decompose high-level goals into executable primitive tasks.
/// Uses a world state (Blackboard) to track conditions and effects.
///
/// Key concepts:
/// - **Primitive tasks**: Basic actions that can be executed directly
/// - **Compound tasks**: High-level tasks that decompose into subtasks via methods
/// - **Methods**: Ways to decompose compound tasks (with preconditions)
/// - **Preconditions**: Conditions that must be true for a task/method
/// - **Effects**: Changes to world state when a task executes
///
/// Example usage:
/// ```zig
/// var planner = HTNPlanner.init(allocator);
/// defer planner.deinit();
///
/// // Define primitive tasks
/// try planner.definePrimitive("move_to_target", .{
///     .preconditions = &.{.{ .key = "has_target", .op = .equals, .value = .{ .boolean = true } }},
///     .effects = &.{.{ .key = "at_target", .value = .{ .boolean = true } }},
/// });
///
/// try planner.definePrimitive("attack", .{
///     .preconditions = &.{.{ .key = "at_target", .op = .equals, .value = .{ .boolean = true } }},
///     .effects = &.{.{ .key = "target_attacked", .value = .{ .boolean = true } }},
/// });
///
/// // Define compound task with methods
/// try planner.defineCompound("combat", .{
///     .methods = &.{
///         .{ .name = "melee_attack", .subtasks = &.{ "move_to_target", "attack" } },
///     },
/// });
///
/// // Create world state and plan
/// var world = blackboard.Blackboard.init(allocator);
/// defer world.deinit();
/// try world.setBool("has_target", true);
///
/// const plan = try planner.plan(&world, "combat");
/// defer allocator.free(plan);
/// // plan = ["move_to_target", "attack"]
/// ```

/// Maximum length for task/method names
pub const MAX_NAME_LENGTH: usize = 63;

/// Maximum number of preconditions per task/method
pub const MAX_PRECONDITIONS: usize = 16;

/// Maximum number of effects per task
pub const MAX_EFFECTS: usize = 16;

/// Maximum number of subtasks in a method
pub const MAX_SUBTASKS: usize = 16;

/// Maximum number of methods per compound task
pub const MAX_METHODS: usize = 8;

/// Maximum planning depth (prevents infinite recursion)
pub const MAX_PLAN_DEPTH: usize = 100;

/// Comparison operators for preconditions
pub const CompareOp = enum(u8) {
    equals,
    not_equals,
    less_than,
    less_equal,
    greater_than,
    greater_equal,
    exists, // Key exists (any value)
    not_exists, // Key does not exist
};

/// A condition that must be satisfied
pub const Condition = struct {
    key: []const u8,
    op: CompareOp = .equals,
    value: blackboard.Value = .{ .boolean = true },

    /// Check if this condition is satisfied by the world state
    pub fn isSatisfied(self: Condition, world: *const blackboard.Blackboard) bool {
        const actual = world.get(self.key);

        return switch (self.op) {
            .exists => actual != null,
            .not_exists => actual == null,
            .equals => if (actual) |v| compareValues(v, self.value) == .eq else false,
            .not_equals => if (actual) |v| compareValues(v, self.value) != .eq else true,
            .less_than => if (actual) |v| compareValues(v, self.value) == .lt else false,
            .less_equal => if (actual) |v| blk: {
                const cmp = compareValues(v, self.value);
                break :blk cmp == .lt or cmp == .eq;
            } else false,
            .greater_than => if (actual) |v| compareValues(v, self.value) == .gt else false,
            .greater_equal => if (actual) |v| blk: {
                const cmp = compareValues(v, self.value);
                break :blk cmp == .gt or cmp == .eq;
            } else false,
        };
    }
};

/// Comparison result
const Ordering = enum { lt, eq, gt };

/// Compare two blackboard values
fn compareValues(a: blackboard.Value, b: blackboard.Value) Ordering {
    // Convert to comparable types
    const a_float = a.toFloat();
    const b_float = b.toFloat();

    if (a_float < b_float) return .lt;
    if (a_float > b_float) return .gt;
    return .eq;
}

/// An effect that modifies world state
pub const Effect = struct {
    key: []const u8,
    value: blackboard.Value,
    operation: EffectOp = .set,

    pub const EffectOp = enum(u8) {
        set, // Set to value
        add, // Add to current value (numeric)
        remove, // Remove the key
    };

    /// Apply this effect to the world state
    pub fn apply(self: Effect, world: *blackboard.Blackboard) !void {
        switch (self.operation) {
            .set => {
                switch (self.value) {
                    .int32 => |v| try world.setInt(self.key, v),
                    .int64 => |v| try world.setInt64(self.key, v),
                    .float32 => |v| try world.setFloat(self.key, v),
                    .float64 => |v| try world.setFloat64(self.key, v),
                    .boolean => |v| try world.setBool(self.key, v),
                    .string => |v| try world.setString(self.key, v),
                    .pointer => |v| try world.setPointer(self.key, v),
                    .vec2 => |v| try world.setVec2(self.key, v),
                    .vec3 => |v| try world.setVec3(self.key, v),
                }
            },
            .add => {
                const current = world.getFloat(self.key) orelse 0.0;
                const delta = self.value.toFloat();
                try world.setFloat(self.key, current + delta);
            },
            .remove => {
                _ = world.remove(self.key);
            },
        }
    }
};

/// A method for decomposing a compound task
pub const Method = struct {
    name: []const u8,
    preconditions: []const Condition = &.{},
    subtasks: []const []const u8,

    /// Check if all preconditions are satisfied
    pub fn canExecute(self: Method, world: *const blackboard.Blackboard) bool {
        for (self.preconditions) |cond| {
            if (!cond.isSatisfied(world)) return false;
        }
        return true;
    }
};

/// Stored method with inline storage
const StoredMethod = struct {
    name: [MAX_NAME_LENGTH + 1]u8,
    name_len: u8,
    preconditions: [MAX_PRECONDITIONS]StoredCondition,
    precondition_count: u8,
    subtasks: [MAX_SUBTASKS][MAX_NAME_LENGTH + 1]u8,
    subtask_lens: [MAX_SUBTASKS]u8,
    subtask_count: u8,

    fn getName(self: *const StoredMethod) []const u8 {
        return self.name[0..self.name_len];
    }

    fn getSubtask(self: *const StoredMethod, index: usize) []const u8 {
        return self.subtasks[index][0..self.subtask_lens[index]];
    }

    fn canExecute(self: *const StoredMethod, world: *const blackboard.Blackboard) bool {
        for (self.preconditions[0..self.precondition_count]) |*cond| {
            if (!cond.isSatisfied(world)) return false;
        }
        return true;
    }
};

/// Stored condition with inline storage
const StoredCondition = struct {
    key: [MAX_NAME_LENGTH + 1]u8,
    key_len: u8,
    op: CompareOp,
    value: blackboard.Value,
    // For string values
    string_storage: [blackboard.MAX_STRING_LENGTH + 1]u8 = undefined,
    string_len: u8 = 0,

    fn getKey(self: *const StoredCondition) []const u8 {
        return self.key[0..self.key_len];
    }

    fn getValue(self: *const StoredCondition) blackboard.Value {
        if (self.value == .string) {
            return .{ .string = self.string_storage[0..self.string_len] };
        }
        return self.value;
    }

    fn isSatisfied(self: *const StoredCondition, world: *const blackboard.Blackboard) bool {
        const actual = world.get(self.getKey());

        return switch (self.op) {
            .exists => actual != null,
            .not_exists => actual == null,
            .equals => if (actual) |v| compareValues(v, self.getValue()) == .eq else false,
            .not_equals => if (actual) |v| compareValues(v, self.getValue()) != .eq else true,
            .less_than => if (actual) |v| compareValues(v, self.getValue()) == .lt else false,
            .less_equal => if (actual) |v| blk: {
                const cmp = compareValues(v, self.getValue());
                break :blk cmp == .lt or cmp == .eq;
            } else false,
            .greater_than => if (actual) |v| compareValues(v, self.getValue()) == .gt else false,
            .greater_equal => if (actual) |v| blk: {
                const cmp = compareValues(v, self.getValue());
                break :blk cmp == .gt or cmp == .eq;
            } else false,
        };
    }
};

/// Stored effect with inline storage
const StoredEffect = struct {
    key: [MAX_NAME_LENGTH + 1]u8,
    key_len: u8,
    value: blackboard.Value,
    operation: Effect.EffectOp,
    // For string values
    string_storage: [blackboard.MAX_STRING_LENGTH + 1]u8 = undefined,
    string_len: u8 = 0,

    fn getKey(self: *const StoredEffect) []const u8 {
        return self.key[0..self.key_len];
    }

    fn getValue(self: *const StoredEffect) blackboard.Value {
        if (self.value == .string) {
            return .{ .string = self.string_storage[0..self.string_len] };
        }
        return self.value;
    }

    fn apply(self: *const StoredEffect, world: *blackboard.Blackboard) !void {
        const key = self.getKey();
        const value = self.getValue();

        switch (self.operation) {
            .set => {
                switch (value) {
                    .int32 => |v| try world.setInt(key, v),
                    .int64 => |v| try world.setInt64(key, v),
                    .float32 => |v| try world.setFloat(key, v),
                    .float64 => |v| try world.setFloat64(key, v),
                    .boolean => |v| try world.setBool(key, v),
                    .string => |v| try world.setString(key, v),
                    .pointer => |v| try world.setPointer(key, v),
                    .vec2 => |v| try world.setVec2(key, v),
                    .vec3 => |v| try world.setVec3(key, v),
                }
            },
            .add => {
                const current = world.getFloat(key) orelse 0.0;
                const delta = value.toFloat();
                try world.setFloat(key, current + delta);
            },
            .remove => {
                _ = world.remove(key);
            },
        }
    }
};

/// A primitive task (directly executable action)
const PrimitiveTask = struct {
    name: [MAX_NAME_LENGTH + 1]u8,
    name_len: u8,
    preconditions: [MAX_PRECONDITIONS]StoredCondition,
    precondition_count: u8,
    effects: [MAX_EFFECTS]StoredEffect,
    effect_count: u8,
    cost: f32,

    fn getName(self: *const PrimitiveTask) []const u8 {
        return self.name[0..self.name_len];
    }

    fn canExecute(self: *const PrimitiveTask, world: *const blackboard.Blackboard) bool {
        for (self.preconditions[0..self.precondition_count]) |*cond| {
            if (!cond.isSatisfied(world)) return false;
        }
        return true;
    }

    fn applyEffects(self: *const PrimitiveTask, world: *blackboard.Blackboard) !void {
        for (self.effects[0..self.effect_count]) |*eff| {
            try eff.apply(world);
        }
    }
};

/// A compound task (decomposes into subtasks)
const CompoundTask = struct {
    name: [MAX_NAME_LENGTH + 1]u8,
    name_len: u8,
    methods: [MAX_METHODS]StoredMethod,
    method_count: u8,

    fn getName(self: *const CompoundTask) []const u8 {
        return self.name[0..self.name_len];
    }

    /// Find the first method whose preconditions are satisfied
    fn findApplicableMethod(self: *const CompoundTask, world: *const blackboard.Blackboard) ?*const StoredMethod {
        for (self.methods[0..self.method_count]) |*method| {
            if (method.canExecute(world)) {
                return method;
            }
        }
        return null;
    }
};

/// Task type (primitive or compound)
pub const TaskType = enum {
    primitive,
    compound,
};

/// A planned task in the output plan
pub const PlannedTask = struct {
    name: [MAX_NAME_LENGTH + 1]u8,
    name_len: u8,

    pub fn getName(self: *const PlannedTask) []const u8 {
        return self.name[0..self.name_len];
    }
};

/// Primitive task definition options
pub const PrimitiveOptions = struct {
    preconditions: []const Condition = &.{},
    effects: []const Effect = &.{},
    cost: f32 = 1.0,
};

/// Compound task definition options
pub const CompoundOptions = struct {
    methods: []const Method,
};

/// Planning statistics
pub const PlanStats = struct {
    primitive_count: usize,
    compound_count: usize,
    plans_generated: usize,
    plans_failed: usize,
    max_depth_reached: usize,
};

/// HTN Planner - generates plans from hierarchical task definitions
pub const HTNPlanner = struct {
    allocator: Allocator,

    // Task storage
    primitives: std.ArrayList(PrimitiveTask),
    compounds: std.ArrayList(CompoundTask),

    // Statistics
    plans_generated: usize,
    plans_failed: usize,
    max_depth_reached: usize,

    /// Configuration options
    pub const Config = struct {
        initial_primitive_capacity: usize = 32,
        initial_compound_capacity: usize = 16,
        max_plan_depth: usize = MAX_PLAN_DEPTH,
    };

    /// Initialize with default configuration
    pub fn init(allocator: Allocator) HTNPlanner {
        return initWithConfig(allocator, .{});
    }

    /// Initialize with custom configuration
    pub fn initWithConfig(allocator: Allocator, config: Config) HTNPlanner {
        _ = config;
        return .{
            .allocator = allocator,
            .primitives = std.ArrayList(PrimitiveTask).init(allocator),
            .compounds = std.ArrayList(CompoundTask).init(allocator),
            .plans_generated = 0,
            .plans_failed = 0,
            .max_depth_reached = 0,
        };
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *HTNPlanner) void {
        self.primitives.deinit();
        self.compounds.deinit();
    }

    /// Define a primitive task
    pub fn definePrimitive(self: *HTNPlanner, name: []const u8, options: PrimitiveOptions) !void {
        if (name.len > MAX_NAME_LENGTH) return error.NameTooLong;
        if (options.preconditions.len > MAX_PRECONDITIONS) return error.TooManyPreconditions;
        if (options.effects.len > MAX_EFFECTS) return error.TooManyEffects;

        // Check for duplicate
        if (self.findPrimitive(name) != null or self.findCompound(name) != null) {
            return error.DuplicateTask;
        }

        var task: PrimitiveTask = undefined;
        @memcpy(task.name[0..name.len], name);
        task.name_len = @intCast(name.len);
        task.cost = options.cost;

        // Copy preconditions
        task.precondition_count = @intCast(options.preconditions.len);
        for (options.preconditions, 0..) |cond, i| {
            try self.storeCondition(&task.preconditions[i], cond);
        }

        // Copy effects
        task.effect_count = @intCast(options.effects.len);
        for (options.effects, 0..) |eff, i| {
            try self.storeEffect(&task.effects[i], eff);
        }

        try self.primitives.append(task);
    }

    /// Define a compound task
    pub fn defineCompound(self: *HTNPlanner, name: []const u8, options: CompoundOptions) !void {
        if (name.len > MAX_NAME_LENGTH) return error.NameTooLong;
        if (options.methods.len > MAX_METHODS) return error.TooManyMethods;
        if (options.methods.len == 0) return error.NoMethods;

        // Check for duplicate
        if (self.findPrimitive(name) != null or self.findCompound(name) != null) {
            return error.DuplicateTask;
        }

        var task: CompoundTask = undefined;
        @memcpy(task.name[0..name.len], name);
        task.name_len = @intCast(name.len);

        // Copy methods
        task.method_count = @intCast(options.methods.len);
        for (options.methods, 0..) |method, i| {
            try self.storeMethod(&task.methods[i], method);
        }

        try self.compounds.append(task);
    }

    fn storeCondition(self: *HTNPlanner, stored: *StoredCondition, cond: Condition) !void {
        _ = self;
        if (cond.key.len > MAX_NAME_LENGTH) return error.NameTooLong;

        @memcpy(stored.key[0..cond.key.len], cond.key);
        stored.key_len = @intCast(cond.key.len);
        stored.op = cond.op;

        if (cond.value == .string) {
            const str = cond.value.string;
            if (str.len > blackboard.MAX_STRING_LENGTH) return error.StringTooLong;
            @memcpy(stored.string_storage[0..str.len], str);
            stored.string_len = @intCast(str.len);
            stored.value = .{ .string = undefined };
        } else {
            stored.value = cond.value;
        }
    }

    fn storeEffect(self: *HTNPlanner, stored: *StoredEffect, eff: Effect) !void {
        _ = self;
        if (eff.key.len > MAX_NAME_LENGTH) return error.NameTooLong;

        @memcpy(stored.key[0..eff.key.len], eff.key);
        stored.key_len = @intCast(eff.key.len);
        stored.operation = eff.operation;

        if (eff.value == .string) {
            const str = eff.value.string;
            if (str.len > blackboard.MAX_STRING_LENGTH) return error.StringTooLong;
            @memcpy(stored.string_storage[0..str.len], str);
            stored.string_len = @intCast(str.len);
            stored.value = .{ .string = undefined };
        } else {
            stored.value = eff.value;
        }
    }

    fn storeMethod(self: *HTNPlanner, stored: *StoredMethod, method: Method) !void {
        if (method.name.len > MAX_NAME_LENGTH) return error.NameTooLong;
        if (method.preconditions.len > MAX_PRECONDITIONS) return error.TooManyPreconditions;
        if (method.subtasks.len > MAX_SUBTASKS) return error.TooManySubtasks;
        if (method.subtasks.len == 0) return error.NoSubtasks;

        @memcpy(stored.name[0..method.name.len], method.name);
        stored.name_len = @intCast(method.name.len);

        // Copy preconditions
        stored.precondition_count = @intCast(method.preconditions.len);
        for (method.preconditions, 0..) |cond, i| {
            try self.storeCondition(&stored.preconditions[i], cond);
        }

        // Copy subtasks
        stored.subtask_count = @intCast(method.subtasks.len);
        for (method.subtasks, 0..) |subtask, i| {
            if (subtask.len > MAX_NAME_LENGTH) return error.NameTooLong;
            @memcpy(stored.subtasks[i][0..subtask.len], subtask);
            stored.subtask_lens[i] = @intCast(subtask.len);
        }
    }

    /// Find a primitive task by name
    fn findPrimitive(self: *const HTNPlanner, name: []const u8) ?*const PrimitiveTask {
        for (self.primitives.items) |*task| {
            if (std.mem.eql(u8, task.getName(), name)) {
                return task;
            }
        }
        return null;
    }

    /// Find a compound task by name
    fn findCompound(self: *const HTNPlanner, name: []const u8) ?*const CompoundTask {
        for (self.compounds.items) |*task| {
            if (std.mem.eql(u8, task.getName(), name)) {
                return task;
            }
        }
        return null;
    }

    /// Get task type
    pub fn getTaskType(self: *const HTNPlanner, name: []const u8) ?TaskType {
        if (self.findPrimitive(name) != null) return .primitive;
        if (self.findCompound(name) != null) return .compound;
        return null;
    }

    /// Check if a task exists
    pub fn hasTask(self: *const HTNPlanner, name: []const u8) bool {
        return self.getTaskType(name) != null;
    }

    /// Generate a plan to achieve the given task
    pub fn plan(self: *HTNPlanner, world: *blackboard.Blackboard, root_task: []const u8) ![]PlannedTask {
        // Create a copy of world state for planning
        var plan_world = blackboard.Blackboard.init(self.allocator);
        defer plan_world.deinit();
        try plan_world.copy(world);

        // Plan storage
        var result = std.ArrayList(PlannedTask).init(self.allocator);
        errdefer result.deinit();

        // Decompose the root task
        const success = try self.decompose(&plan_world, root_task, &result, 0);

        if (success) {
            self.plans_generated += 1;
            return result.toOwnedSlice();
        } else {
            self.plans_failed += 1;
            result.deinit();
            return error.PlanningFailed;
        }
    }

    /// Recursively decompose a task
    fn decompose(
        self: *HTNPlanner,
        world: *blackboard.Blackboard,
        task_name: []const u8,
        result: *std.ArrayList(PlannedTask),
        depth: usize,
    ) !bool {
        if (depth > MAX_PLAN_DEPTH) {
            if (depth > self.max_depth_reached) {
                self.max_depth_reached = depth;
            }
            return false;
        }

        // Check if primitive
        if (self.findPrimitive(task_name)) |primitive| {
            // Check preconditions
            if (!primitive.canExecute(world)) {
                return false;
            }

            // Add to plan
            var planned: PlannedTask = undefined;
            @memcpy(planned.name[0..task_name.len], task_name);
            planned.name_len = @intCast(task_name.len);
            try result.append(planned);

            // Apply effects to planning world state
            try primitive.applyEffects(world);

            return true;
        }

        // Check if compound
        if (self.findCompound(task_name)) |compound| {
            // Find applicable method
            if (compound.findApplicableMethod(world)) |method| {
                // Decompose all subtasks
                for (0..method.subtask_count) |i| {
                    const subtask = method.getSubtask(i);
                    const success = try self.decompose(world, subtask, result, depth + 1);
                    if (!success) {
                        return false;
                    }
                }
                return true;
            }
            return false; // No applicable method
        }

        // Task not found
        return error.UnknownTask;
    }

    /// Check if a task can be executed in the current world state
    pub fn canExecute(self: *const HTNPlanner, world: *const blackboard.Blackboard, task_name: []const u8) bool {
        if (self.findPrimitive(task_name)) |primitive| {
            return primitive.canExecute(world);
        }
        if (self.findCompound(task_name)) |compound| {
            return compound.findApplicableMethod(world) != null;
        }
        return false;
    }

    /// Execute a primitive task (apply its effects)
    pub fn execute(self: *const HTNPlanner, world: *blackboard.Blackboard, task_name: []const u8) !void {
        if (self.findPrimitive(task_name)) |primitive| {
            if (!primitive.canExecute(world)) {
                return error.PreconditionsNotMet;
            }
            try primitive.applyEffects(world);
        } else {
            return error.NotPrimitive;
        }
    }

    /// Get task cost (for primitive tasks)
    pub fn getTaskCost(self: *const HTNPlanner, task_name: []const u8) ?f32 {
        if (self.findPrimitive(task_name)) |primitive| {
            return primitive.cost;
        }
        return null;
    }

    /// Calculate total cost of a plan
    pub fn getPlanCost(self: *const HTNPlanner, planned: []const PlannedTask) f32 {
        var total: f32 = 0.0;
        for (planned) |*task| {
            if (self.getTaskCost(task.getName())) |cost| {
                total += cost;
            }
        }
        return total;
    }

    /// Get planner statistics
    pub fn getStats(self: *const HTNPlanner) PlanStats {
        return .{
            .primitive_count = self.primitives.items.len,
            .compound_count = self.compounds.items.len,
            .plans_generated = self.plans_generated,
            .plans_failed = self.plans_failed,
            .max_depth_reached = self.max_depth_reached,
        };
    }

    /// Clear all task definitions
    pub fn clear(self: *HTNPlanner) void {
        self.primitives.clearRetainingCapacity();
        self.compounds.clearRetainingCapacity();
    }

    /// Reset statistics
    pub fn resetStats(self: *HTNPlanner) void {
        self.plans_generated = 0;
        self.plans_failed = 0;
        self.max_depth_reached = 0;
    }

    /// Get all primitive task names
    pub fn getPrimitiveNames(self: *const HTNPlanner, allocator: Allocator) ![][]const u8 {
        var names = try allocator.alloc([]const u8, self.primitives.items.len);
        for (self.primitives.items, 0..) |*task, i| {
            names[i] = task.getName();
        }
        return names;
    }

    /// Get all compound task names
    pub fn getCompoundNames(self: *const HTNPlanner, allocator: Allocator) ![][]const u8 {
        var names = try allocator.alloc([]const u8, self.compounds.items.len);
        for (self.compounds.items, 0..) |*task, i| {
            names[i] = task.getName();
        }
        return names;
    }
};

// ============================================================
// Tests
// ============================================================

test "HTNPlanner: define primitive task" {
    const allocator = std.testing.allocator;
    var planner = HTNPlanner.init(allocator);
    defer planner.deinit();

    try planner.definePrimitive("attack", .{
        .preconditions = &.{
            .{ .key = "has_weapon", .op = .equals, .value = .{ .boolean = true } },
        },
        .effects = &.{
            .{ .key = "enemy_damaged", .value = .{ .boolean = true } },
        },
        .cost = 2.0,
    });

    try std.testing.expect(planner.hasTask("attack"));
    try std.testing.expectEqual(TaskType.primitive, planner.getTaskType("attack").?);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), planner.getTaskCost("attack").?, 0.001);
}

test "HTNPlanner: define compound task" {
    const allocator = std.testing.allocator;
    var planner = HTNPlanner.init(allocator);
    defer planner.deinit();

    try planner.definePrimitive("move", .{});
    try planner.definePrimitive("attack", .{});

    try planner.defineCompound("combat", .{
        .methods = &.{
            .{ .name = "melee", .subtasks = &.{ "move", "attack" } },
        },
    });

    try std.testing.expect(planner.hasTask("combat"));
    try std.testing.expectEqual(TaskType.compound, planner.getTaskType("combat").?);
}

test "HTNPlanner: simple plan" {
    const allocator = std.testing.allocator;
    var planner = HTNPlanner.init(allocator);
    defer planner.deinit();

    // Define tasks
    try planner.definePrimitive("move_to_target", .{
        .effects = &.{.{ .key = "at_target", .value = .{ .boolean = true } }},
    });

    try planner.definePrimitive("attack", .{
        .preconditions = &.{.{ .key = "at_target", .op = .equals, .value = .{ .boolean = true } }},
        .effects = &.{.{ .key = "target_attacked", .value = .{ .boolean = true } }},
    });

    try planner.defineCompound("combat", .{
        .methods = &.{
            .{ .name = "melee_attack", .subtasks = &.{ "move_to_target", "attack" } },
        },
    });

    // Create world state
    var world = blackboard.Blackboard.init(allocator);
    defer world.deinit();

    // Generate plan
    const plan = try planner.plan(&world, "combat");
    defer allocator.free(plan);

    try std.testing.expectEqual(@as(usize, 2), plan.len);
    try std.testing.expectEqualStrings("move_to_target", plan[0].getName());
    try std.testing.expectEqualStrings("attack", plan[1].getName());
}

test "HTNPlanner: precondition failure" {
    const allocator = std.testing.allocator;
    var planner = HTNPlanner.init(allocator);
    defer planner.deinit();

    try planner.definePrimitive("attack", .{
        .preconditions = &.{.{ .key = "has_weapon", .op = .equals, .value = .{ .boolean = true } }},
    });

    var world = blackboard.Blackboard.init(allocator);
    defer world.deinit();
    // No weapon

    try std.testing.expectError(error.PlanningFailed, planner.plan(&world, "attack"));
}

test "HTNPlanner: method selection" {
    const allocator = std.testing.allocator;
    var planner = HTNPlanner.init(allocator);
    defer planner.deinit();

    try planner.definePrimitive("ranged_attack", .{
        .preconditions = &.{.{ .key = "has_bow", .op = .equals, .value = .{ .boolean = true } }},
    });

    try planner.definePrimitive("melee_attack", .{});

    try planner.defineCompound("attack", .{
        .methods = &.{
            .{
                .name = "ranged",
                .preconditions = &.{.{ .key = "has_bow", .op = .equals, .value = .{ .boolean = true } }},
                .subtasks = &.{"ranged_attack"},
            },
            .{
                .name = "melee",
                .subtasks = &.{"melee_attack"},
            },
        },
    });

    var world = blackboard.Blackboard.init(allocator);
    defer world.deinit();

    // Without bow - should use melee
    {
        const plan = try planner.plan(&world, "attack");
        defer allocator.free(plan);
        try std.testing.expectEqual(@as(usize, 1), plan.len);
        try std.testing.expectEqualStrings("melee_attack", plan[0].getName());
    }

    // With bow - should use ranged
    try world.setBool("has_bow", true);
    {
        const plan = try planner.plan(&world, "attack");
        defer allocator.free(plan);
        try std.testing.expectEqual(@as(usize, 1), plan.len);
        try std.testing.expectEqualStrings("ranged_attack", plan[0].getName());
    }
}

test "HTNPlanner: canExecute" {
    const allocator = std.testing.allocator;
    var planner = HTNPlanner.init(allocator);
    defer planner.deinit();

    try planner.definePrimitive("attack", .{
        .preconditions = &.{.{ .key = "has_weapon", .op = .equals, .value = .{ .boolean = true } }},
    });

    var world = blackboard.Blackboard.init(allocator);
    defer world.deinit();

    try std.testing.expect(!planner.canExecute(&world, "attack"));

    try world.setBool("has_weapon", true);
    try std.testing.expect(planner.canExecute(&world, "attack"));
}

test "HTNPlanner: execute primitive" {
    const allocator = std.testing.allocator;
    var planner = HTNPlanner.init(allocator);
    defer planner.deinit();

    try planner.definePrimitive("heal", .{
        .effects = &.{.{ .key = "health", .value = .{ .int32 = 100 } }},
    });

    var world = blackboard.Blackboard.init(allocator);
    defer world.deinit();

    try planner.execute(&world, "heal");
    try std.testing.expectEqual(@as(i32, 100), world.getIntOr("health", 0));
}

test "HTNPlanner: effect add operation" {
    const allocator = std.testing.allocator;
    var planner = HTNPlanner.init(allocator);
    defer planner.deinit();

    try planner.definePrimitive("gain_gold", .{
        .effects = &.{.{ .key = "gold", .value = .{ .int32 = 50 }, .operation = .add }},
    });

    var world = blackboard.Blackboard.init(allocator);
    defer world.deinit();
    try world.setFloat("gold", 100.0);

    try planner.execute(&world, "gain_gold");
    try std.testing.expectApproxEqAbs(@as(f32, 150.0), world.getFloatOr("gold", 0.0), 0.001);
}

test "HTNPlanner: effect remove operation" {
    const allocator = std.testing.allocator;
    var planner = HTNPlanner.init(allocator);
    defer planner.deinit();

    try planner.definePrimitive("drop_weapon", .{
        .effects = &.{.{ .key = "has_weapon", .value = .{ .boolean = false }, .operation = .remove }},
    });

    var world = blackboard.Blackboard.init(allocator);
    defer world.deinit();
    try world.setBool("has_weapon", true);

    try std.testing.expect(world.has("has_weapon"));
    try planner.execute(&world, "drop_weapon");
    try std.testing.expect(!world.has("has_weapon"));
}

test "HTNPlanner: comparison operators" {
    const allocator = std.testing.allocator;
    var planner = HTNPlanner.init(allocator);
    defer planner.deinit();

    try planner.definePrimitive("heal", .{
        .preconditions = &.{.{ .key = "health", .op = .less_than, .value = .{ .int32 = 50 } }},
    });

    var world = blackboard.Blackboard.init(allocator);
    defer world.deinit();

    try world.setInt("health", 30);
    try std.testing.expect(planner.canExecute(&world, "heal"));

    try world.setInt("health", 50);
    try std.testing.expect(!planner.canExecute(&world, "heal"));

    try world.setInt("health", 70);
    try std.testing.expect(!planner.canExecute(&world, "heal"));
}

test "HTNPlanner: exists/not_exists operators" {
    const allocator = std.testing.allocator;
    var planner = HTNPlanner.init(allocator);
    defer planner.deinit();

    try planner.definePrimitive("find_target", .{
        .preconditions = &.{.{ .key = "target", .op = .not_exists }},
        .effects = &.{.{ .key = "target", .value = .{ .int32 = 1 } }},
    });

    try planner.definePrimitive("attack_target", .{
        .preconditions = &.{.{ .key = "target", .op = .exists }},
    });

    var world = blackboard.Blackboard.init(allocator);
    defer world.deinit();

    try std.testing.expect(planner.canExecute(&world, "find_target"));
    try std.testing.expect(!planner.canExecute(&world, "attack_target"));

    try world.setInt("target", 42);
    try std.testing.expect(!planner.canExecute(&world, "find_target"));
    try std.testing.expect(planner.canExecute(&world, "attack_target"));
}

test "HTNPlanner: plan cost" {
    const allocator = std.testing.allocator;
    var planner = HTNPlanner.init(allocator);
    defer planner.deinit();

    try planner.definePrimitive("move", .{ .cost = 1.0 });
    try planner.definePrimitive("attack", .{ .cost = 2.5 });

    try planner.defineCompound("combat", .{
        .methods = &.{
            .{ .name = "engage", .subtasks = &.{ "move", "attack" } },
        },
    });

    var world = blackboard.Blackboard.init(allocator);
    defer world.deinit();

    const plan = try planner.plan(&world, "combat");
    defer allocator.free(plan);

    try std.testing.expectApproxEqAbs(@as(f32, 3.5), planner.getPlanCost(plan), 0.001);
}

test "HTNPlanner: duplicate task error" {
    const allocator = std.testing.allocator;
    var planner = HTNPlanner.init(allocator);
    defer planner.deinit();

    try planner.definePrimitive("attack", .{});
    try std.testing.expectError(error.DuplicateTask, planner.definePrimitive("attack", .{}));
    try std.testing.expectError(error.DuplicateTask, planner.defineCompound("attack", .{
        .methods = &.{.{ .name = "m", .subtasks = &.{"attack"} }},
    }));
}

test "HTNPlanner: unknown task error" {
    const allocator = std.testing.allocator;
    var planner = HTNPlanner.init(allocator);
    defer planner.deinit();

    var world = blackboard.Blackboard.init(allocator);
    defer world.deinit();

    try std.testing.expectError(error.UnknownTask, planner.plan(&world, "nonexistent"));
}

test "HTNPlanner: statistics" {
    const allocator = std.testing.allocator;
    var planner = HTNPlanner.init(allocator);
    defer planner.deinit();

    try planner.definePrimitive("task1", .{});
    try planner.definePrimitive("task2", .{});
    try planner.defineCompound("compound1", .{
        .methods = &.{.{ .name = "m", .subtasks = &.{"task1"} }},
    });

    var world = blackboard.Blackboard.init(allocator);
    defer world.deinit();

    const plan = try planner.plan(&world, "task1");
    allocator.free(plan);

    const stats = planner.getStats();
    try std.testing.expectEqual(@as(usize, 2), stats.primitive_count);
    try std.testing.expectEqual(@as(usize, 1), stats.compound_count);
    try std.testing.expectEqual(@as(usize, 1), stats.plans_generated);
}

test "HTNPlanner: nested compound tasks" {
    const allocator = std.testing.allocator;
    var planner = HTNPlanner.init(allocator);
    defer planner.deinit();

    try planner.definePrimitive("step1", .{});
    try planner.definePrimitive("step2", .{});
    try planner.definePrimitive("step3", .{});

    try planner.defineCompound("phase1", .{
        .methods = &.{.{ .name = "m1", .subtasks = &.{ "step1", "step2" } }},
    });

    try planner.defineCompound("full_plan", .{
        .methods = &.{.{ .name = "m2", .subtasks = &.{ "phase1", "step3" } }},
    });

    var world = blackboard.Blackboard.init(allocator);
    defer world.deinit();

    const plan = try planner.plan(&world, "full_plan");
    defer allocator.free(plan);

    try std.testing.expectEqual(@as(usize, 3), plan.len);
    try std.testing.expectEqualStrings("step1", plan[0].getName());
    try std.testing.expectEqualStrings("step2", plan[1].getName());
    try std.testing.expectEqualStrings("step3", plan[2].getName());
}

test "HTNPlanner: clear and reset" {
    const allocator = std.testing.allocator;
    var planner = HTNPlanner.init(allocator);
    defer planner.deinit();

    try planner.definePrimitive("task", .{});

    var world = blackboard.Blackboard.init(allocator);
    defer world.deinit();

    const plan = try planner.plan(&world, "task");
    allocator.free(plan);

    try std.testing.expectEqual(@as(usize, 1), planner.getStats().plans_generated);

    planner.resetStats();
    try std.testing.expectEqual(@as(usize, 0), planner.getStats().plans_generated);

    planner.clear();
    try std.testing.expectEqual(@as(usize, 0), planner.getStats().primitive_count);
}

test "HTNPlanner: get task names" {
    const allocator = std.testing.allocator;
    var planner = HTNPlanner.init(allocator);
    defer planner.deinit();

    try planner.definePrimitive("move", .{});
    try planner.definePrimitive("attack", .{});
    try planner.defineCompound("combat", .{
        .methods = &.{.{ .name = "m", .subtasks = &.{"move"} }},
    });

    const primitives = try planner.getPrimitiveNames(allocator);
    defer allocator.free(primitives);
    try std.testing.expectEqual(@as(usize, 2), primitives.len);

    const compounds = try planner.getCompoundNames(allocator);
    defer allocator.free(compounds);
    try std.testing.expectEqual(@as(usize, 1), compounds.len);
}

test "HTNPlanner: execute preconditions not met" {
    const allocator = std.testing.allocator;
    var planner = HTNPlanner.init(allocator);
    defer planner.deinit();

    try planner.definePrimitive("attack", .{
        .preconditions = &.{.{ .key = "has_weapon", .op = .equals, .value = .{ .boolean = true } }},
    });

    var world = blackboard.Blackboard.init(allocator);
    defer world.deinit();

    try std.testing.expectError(error.PreconditionsNotMet, planner.execute(&world, "attack"));
}

test "HTNPlanner: execute not primitive" {
    const allocator = std.testing.allocator;
    var planner = HTNPlanner.init(allocator);
    defer planner.deinit();

    try planner.definePrimitive("step", .{});
    try planner.defineCompound("compound", .{
        .methods = &.{.{ .name = "m", .subtasks = &.{"step"} }},
    });

    var world = blackboard.Blackboard.init(allocator);
    defer world.deinit();

    try std.testing.expectError(error.NotPrimitive, planner.execute(&world, "compound"));
}

test "HTNPlanner: complex game scenario" {
    const allocator = std.testing.allocator;
    var planner = HTNPlanner.init(allocator);
    defer planner.deinit();

    // Define primitive tasks for a strategy game AI
    try planner.definePrimitive("gather_resources", .{
        .preconditions = &.{.{ .key = "workers", .op = .greater_than, .value = .{ .int32 = 0 } }},
        .effects = &.{.{ .key = "resources", .value = .{ .int32 = 100 }, .operation = .add }},
        .cost = 1.0,
    });

    try planner.definePrimitive("build_barracks", .{
        .preconditions = &.{.{ .key = "resources", .op = .greater_equal, .value = .{ .int32 = 150 } }},
        .effects = &.{
            .{ .key = "has_barracks", .value = .{ .boolean = true } },
            .{ .key = "resources", .value = .{ .int32 = -150 }, .operation = .add },
        },
        .cost = 3.0,
    });

    try planner.definePrimitive("train_soldier", .{
        .preconditions = &.{
            .{ .key = "has_barracks", .op = .equals, .value = .{ .boolean = true } },
            .{ .key = "resources", .op = .greater_equal, .value = .{ .int32 = 50 } },
        },
        .effects = &.{
            .{ .key = "soldiers", .value = .{ .int32 = 1 }, .operation = .add },
            .{ .key = "resources", .value = .{ .int32 = -50 }, .operation = .add },
        },
        .cost = 2.0,
    });

    // Define compound tasks
    try planner.defineCompound("build_army", .{
        .methods = &.{
            .{
                .name = "standard_army",
                .subtasks = &.{ "gather_resources", "gather_resources", "build_barracks", "train_soldier", "train_soldier" },
            },
        },
    });

    // Create world state
    var world = blackboard.Blackboard.init(allocator);
    defer world.deinit();
    try world.setInt("workers", 5);
    try world.setFloat("resources", 0.0);

    // Generate plan
    const plan = try planner.plan(&world, "build_army");
    defer allocator.free(plan);

    try std.testing.expectEqual(@as(usize, 5), plan.len);
    try std.testing.expectEqualStrings("gather_resources", plan[0].getName());
    try std.testing.expectEqualStrings("gather_resources", plan[1].getName());
    try std.testing.expectEqualStrings("build_barracks", plan[2].getName());
    try std.testing.expectEqualStrings("train_soldier", plan[3].getName());
    try std.testing.expectEqualStrings("train_soldier", plan[4].getName());

    // Total cost
    try std.testing.expectApproxEqAbs(@as(f32, 9.0), planner.getPlanCost(plan), 0.001);
}
