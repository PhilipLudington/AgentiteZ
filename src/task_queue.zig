const std = @import("std");
const Allocator = std.mem.Allocator;

/// Task Queue System - Prioritized task management for AI agents
///
/// Provides sequential task execution for autonomous entities:
/// - Multiple task types (move, collect, build, attack, etc.)
/// - Task state management (pending, in_progress, completed, failed)
/// - Priority-based insertion
/// - Progress tracking
/// - Completion callbacks
///
/// Example usage:
/// ```zig
/// var queue = TaskQueue.init(allocator);
/// defer queue.deinit();
///
/// // Add tasks
/// try queue.addMove(100.0, 200.0);
/// try queue.addCollect(50.0, 75.0, .wood);
/// try queue.addBuild(200.0, 200.0, .barracks);
///
/// // Process tasks
/// if (queue.current()) |task| {
///     task.status = .in_progress;
///     // ... execute task logic ...
///     if (task_completed) {
///         queue.complete();
///     }
/// }
/// ```

/// Task status
pub const TaskStatus = enum(u8) {
    pending,
    in_progress,
    completed,
    failed,
    cancelled,
};

/// Task type enumeration
pub const TaskType = enum(u8) {
    // Movement
    move,
    explore,
    patrol,
    follow,

    // Resources
    collect,
    deposit,
    withdraw,
    mine,

    // Building
    build,
    repair,
    demolish,

    // Crafting
    craft,

    // Combat
    attack,
    defend,
    flee,

    // Utility
    wait,
    interact,
    interact_entity,

    // Custom
    custom,

    pub fn name(self: TaskType) []const u8 {
        return switch (self) {
            .move => "Move",
            .explore => "Explore",
            .patrol => "Patrol",
            .follow => "Follow",
            .collect => "Collect",
            .deposit => "Deposit",
            .withdraw => "Withdraw",
            .mine => "Mine",
            .build => "Build",
            .repair => "Repair",
            .demolish => "Demolish",
            .craft => "Craft",
            .attack => "Attack",
            .defend => "Defend",
            .flee => "Flee",
            .wait => "Wait",
            .interact => "Interact",
            .interact_entity => "Interact Entity",
            .custom => "Custom",
        };
    }
};

/// Resource type for collection/deposit tasks
pub const ResourceType = enum(u8) {
    none,
    wood,
    stone,
    iron,
    gold,
    food,
    energy,
    custom,
};

/// Building type for construction tasks
pub const BuildingType = enum(u8) {
    none,
    house,
    barracks,
    farm,
    mine,
    factory,
    wall,
    tower,
    custom,
};

/// Interaction type
pub const InteractionType = enum(u8) {
    none,
    use,
    activate,
    talk,
    trade,
    pickup,
    open,
    close,
    custom,
};

/// Direction for building placement
pub const Direction = enum(u8) {
    none,
    north,
    south,
    east,
    west,
    north_east,
    north_west,
    south_east,
    south_west,
};

/// 2D position
pub const Vec2 = struct {
    x: f32,
    y: f32,

    pub fn init(x: f32, y: f32) Vec2 {
        return .{ .x = x, .y = y };
    }

    pub fn zero() Vec2 {
        return .{ .x = 0.0, .y = 0.0 };
    }

    pub fn distance(self: Vec2, other: Vec2) f32 {
        const dx = other.x - self.x;
        const dy = other.y - self.y;
        return @sqrt(dx * dx + dy * dy);
    }
};

/// Move task data
pub const MoveData = struct {
    target: Vec2,
    run: bool = false,
};

/// Explore task data
pub const ExploreData = struct {
    center: Vec2,
    radius: f32,
};

/// Patrol task data (max 16 waypoints)
pub const PatrolData = struct {
    waypoints: [16]Vec2 = undefined,
    waypoint_count: u8 = 0,
    current_waypoint: u8 = 0,
    loop: bool = true,

    pub fn addWaypoint(self: *PatrolData, pos: Vec2) bool {
        if (self.waypoint_count >= 16) return false;
        self.waypoints[self.waypoint_count] = pos;
        self.waypoint_count += 1;
        return true;
    }

    pub fn getCurrentWaypoint(self: *const PatrolData) ?Vec2 {
        if (self.current_waypoint >= self.waypoint_count) return null;
        return self.waypoints[self.current_waypoint];
    }

    pub fn advanceWaypoint(self: *PatrolData) void {
        self.current_waypoint += 1;
        if (self.current_waypoint >= self.waypoint_count) {
            if (self.loop) {
                self.current_waypoint = 0;
            }
        }
    }
};

/// Follow task data
pub const FollowData = struct {
    target_entity: u32,
    min_distance: f32 = 1.0,
    max_distance: f32 = 5.0,
};

/// Collect task data
pub const CollectData = struct {
    position: Vec2,
    resource_type: ResourceType,
    quantity: i32 = 1,
};

/// Deposit task data
pub const DepositData = struct {
    storage_position: Vec2,
    resource_type: ResourceType,
    quantity: i32 = -1, // -1 = all
};

/// Withdraw task data
pub const WithdrawData = struct {
    storage_position: Vec2,
    resource_type: ResourceType,
    quantity: i32,
};

/// Mine task data
pub const MineData = struct {
    position: Vec2,
    quantity: i32 = 1,
};

/// Build task data
pub const BuildData = struct {
    position: Vec2,
    building_type: BuildingType,
    direction: Direction = .none,
};

/// Repair task data
pub const RepairData = struct {
    position: Vec2,
    target_entity: u32 = 0,
};

/// Demolish task data
pub const DemolishData = struct {
    position: Vec2,
    target_entity: u32 = 0,
};

/// Craft task data
pub const CraftData = struct {
    recipe_id: u32,
    quantity: i32 = 1,
};

/// Attack task data
pub const AttackData = struct {
    target_entity: u32,
    pursue: bool = true,
};

/// Defend task data
pub const DefendData = struct {
    center: Vec2,
    radius: f32,
};

/// Flee task data
pub const FleeData = struct {
    from_entity: u32 = 0,
    from_position: Vec2 = Vec2.zero(),
    distance: f32 = 100.0,
};

/// Wait task data
pub const WaitData = struct {
    duration: f32,
    elapsed: f32 = 0.0,
};

/// Interact task data
pub const InteractData = struct {
    position: Vec2,
    interaction_type: InteractionType,
};

/// Interact entity task data
pub const InteractEntityData = struct {
    target_entity: u32,
    interaction_type: InteractionType,
};

/// Custom task data (user-defined)
pub const CustomData = struct {
    type_id: u32,
    data: [64]u8 = undefined,
    data_len: u8 = 0,

    pub fn setData(self: *CustomData, bytes: []const u8) void {
        const len = @min(bytes.len, 64);
        @memcpy(self.data[0..len], bytes[0..len]);
        self.data_len = @intCast(len);
    }

    pub fn getData(self: *const CustomData) []const u8 {
        return self.data[0..self.data_len];
    }
};

/// Task data union
pub const TaskData = union(TaskType) {
    move: MoveData,
    explore: ExploreData,
    patrol: PatrolData,
    follow: FollowData,
    collect: CollectData,
    deposit: DepositData,
    withdraw: WithdrawData,
    mine: MineData,
    build: BuildData,
    repair: RepairData,
    demolish: DemolishData,
    craft: CraftData,
    attack: AttackData,
    defend: DefendData,
    flee: FleeData,
    wait: WaitData,
    interact: InteractData,
    interact_entity: InteractEntityData,
    custom: CustomData,
};

/// Maximum length for fail reason string
pub const MAX_FAIL_REASON_LENGTH: usize = 127;

/// A task in the queue
pub const Task = struct {
    data: TaskData,
    status: TaskStatus,
    progress: f32, // 0.0 to 1.0
    priority: f32,
    assigned_entity: u32,
    fail_reason: [MAX_FAIL_REASON_LENGTH + 1]u8 = undefined,
    fail_reason_len: u8 = 0,

    pub fn getType(self: *const Task) TaskType {
        return self.data;
    }

    pub fn getTypeName(self: *const Task) []const u8 {
        return self.getType().name();
    }

    pub fn getFailReason(self: *const Task) []const u8 {
        return self.fail_reason[0..self.fail_reason_len];
    }

    pub fn setFailReason(self: *Task, reason: []const u8) void {
        const len = @min(reason.len, MAX_FAIL_REASON_LENGTH);
        @memcpy(self.fail_reason[0..len], reason[0..len]);
        self.fail_reason_len = @intCast(len);
    }

    pub fn isPending(self: *const Task) bool {
        return self.status == .pending;
    }

    pub fn isInProgress(self: *const Task) bool {
        return self.status == .in_progress;
    }

    pub fn isComplete(self: *const Task) bool {
        return self.status == .completed;
    }

    pub fn isFailed(self: *const Task) bool {
        return self.status == .failed;
    }

    pub fn isCancelled(self: *const Task) bool {
        return self.status == .cancelled;
    }

    pub fn isDone(self: *const Task) bool {
        return self.status == .completed or self.status == .failed or self.status == .cancelled;
    }
};

/// Task completion callback
pub const TaskCallback = *const fn (queue: *TaskQueue, task: *const Task, userdata: ?*anyopaque) void;

/// Task queue statistics
pub const TaskQueueStats = struct {
    total_tasks: usize,
    pending_tasks: usize,
    completed_tasks: usize,
    failed_tasks: usize,
    cancelled_tasks: usize,
};

/// Task queue for sequential task execution
pub const TaskQueue = struct {
    allocator: Allocator,
    tasks: std.ArrayList(Task),
    assigned_entity: u32,
    callback: ?TaskCallback,
    callback_userdata: ?*anyopaque,

    // Statistics
    completed_count: usize,
    failed_count: usize,
    cancelled_count: usize,

    /// Configuration
    pub const Config = struct {
        initial_capacity: usize = 32,
        assigned_entity: u32 = 0,
    };

    /// Initialize with default configuration
    pub fn init(allocator: Allocator) TaskQueue {
        return initWithConfig(allocator, .{});
    }

    /// Initialize with custom configuration
    pub fn initWithConfig(allocator: Allocator, config: Config) TaskQueue {
        return .{
            .allocator = allocator,
            .tasks = std.ArrayList(Task).initCapacity(allocator, config.initial_capacity) catch std.ArrayList(Task).init(allocator),
            .assigned_entity = config.assigned_entity,
            .callback = null,
            .callback_userdata = null,
            .completed_count = 0,
            .failed_count = 0,
            .cancelled_count = 0,
        };
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *TaskQueue) void {
        self.tasks.deinit();
    }

    /// Set completion callback
    pub fn setCallback(self: *TaskQueue, callback: TaskCallback, userdata: ?*anyopaque) void {
        self.callback = callback;
        self.callback_userdata = userdata;
    }

    /// Set assigned entity
    pub fn setAssignedEntity(self: *TaskQueue, entity_id: u32) void {
        self.assigned_entity = entity_id;
    }

    /// Get assigned entity
    pub fn getAssignedEntity(self: *const TaskQueue) u32 {
        return self.assigned_entity;
    }

    // ============================================================
    // Task Addition
    // ============================================================

    /// Add a task with specified priority
    fn addTask(self: *TaskQueue, data: TaskData, priority: f32) !void {
        const task = Task{
            .data = data,
            .status = .pending,
            .progress = 0.0,
            .priority = priority,
            .assigned_entity = self.assigned_entity,
        };
        try self.tasks.append(task);
    }

    /// Add move task
    pub fn addMove(self: *TaskQueue, x: f32, y: f32) !void {
        try self.addMoveEx(x, y, false, 0.5);
    }

    /// Add move task with options
    pub fn addMoveEx(self: *TaskQueue, x: f32, y: f32, run: bool, priority: f32) !void {
        try self.addTask(.{ .move = .{
            .target = Vec2.init(x, y),
            .run = run,
        } }, priority);
    }

    /// Add explore task
    pub fn addExplore(self: *TaskQueue, center_x: f32, center_y: f32, radius: f32) !void {
        try self.addExploreEx(center_x, center_y, radius, 0.3);
    }

    /// Add explore task with priority
    pub fn addExploreEx(self: *TaskQueue, center_x: f32, center_y: f32, radius: f32, priority: f32) !void {
        try self.addTask(.{ .explore = .{
            .center = Vec2.init(center_x, center_y),
            .radius = radius,
        } }, priority);
    }

    /// Add patrol task
    pub fn addPatrol(self: *TaskQueue, waypoints: []const Vec2, loop: bool) !void {
        try self.addPatrolEx(waypoints, loop, 0.4);
    }

    /// Add patrol task with priority
    pub fn addPatrolEx(self: *TaskQueue, waypoints: []const Vec2, loop: bool, priority: f32) !void {
        var patrol_data = PatrolData{
            .loop = loop,
        };
        for (waypoints) |wp| {
            if (!patrol_data.addWaypoint(wp)) break;
        }
        try self.addTask(.{ .patrol = patrol_data }, priority);
    }

    /// Add follow task
    pub fn addFollow(self: *TaskQueue, target_entity: u32, min_dist: f32, max_dist: f32) !void {
        try self.addFollowEx(target_entity, min_dist, max_dist, 0.6);
    }

    /// Add follow task with priority
    pub fn addFollowEx(self: *TaskQueue, target_entity: u32, min_dist: f32, max_dist: f32, priority: f32) !void {
        try self.addTask(.{ .follow = .{
            .target_entity = target_entity,
            .min_distance = min_dist,
            .max_distance = max_dist,
        } }, priority);
    }

    /// Add collect task
    pub fn addCollect(self: *TaskQueue, x: f32, y: f32, resource: ResourceType) !void {
        try self.addCollectEx(x, y, resource, 1, 0.5);
    }

    /// Add collect task with quantity and priority
    pub fn addCollectEx(self: *TaskQueue, x: f32, y: f32, resource: ResourceType, quantity: i32, priority: f32) !void {
        try self.addTask(.{ .collect = .{
            .position = Vec2.init(x, y),
            .resource_type = resource,
            .quantity = quantity,
        } }, priority);
    }

    /// Add deposit task
    pub fn addDeposit(self: *TaskQueue, storage_x: f32, storage_y: f32, resource: ResourceType) !void {
        try self.addDepositEx(storage_x, storage_y, resource, -1, 0.5);
    }

    /// Add deposit task with quantity and priority
    pub fn addDepositEx(self: *TaskQueue, storage_x: f32, storage_y: f32, resource: ResourceType, quantity: i32, priority: f32) !void {
        try self.addTask(.{ .deposit = .{
            .storage_position = Vec2.init(storage_x, storage_y),
            .resource_type = resource,
            .quantity = quantity,
        } }, priority);
    }

    /// Add withdraw task
    pub fn addWithdraw(self: *TaskQueue, storage_x: f32, storage_y: f32, resource: ResourceType, quantity: i32) !void {
        try self.addWithdrawEx(storage_x, storage_y, resource, quantity, 0.5);
    }

    /// Add withdraw task with priority
    pub fn addWithdrawEx(self: *TaskQueue, storage_x: f32, storage_y: f32, resource: ResourceType, quantity: i32, priority: f32) !void {
        try self.addTask(.{ .withdraw = .{
            .storage_position = Vec2.init(storage_x, storage_y),
            .resource_type = resource,
            .quantity = quantity,
        } }, priority);
    }

    /// Add mine task
    pub fn addMine(self: *TaskQueue, x: f32, y: f32, quantity: i32) !void {
        try self.addMineEx(x, y, quantity, 0.5);
    }

    /// Add mine task with priority
    pub fn addMineEx(self: *TaskQueue, x: f32, y: f32, quantity: i32, priority: f32) !void {
        try self.addTask(.{ .mine = .{
            .position = Vec2.init(x, y),
            .quantity = quantity,
        } }, priority);
    }

    /// Add build task
    pub fn addBuild(self: *TaskQueue, x: f32, y: f32, building: BuildingType) !void {
        try self.addBuildEx(x, y, building, .none, 0.6);
    }

    /// Add build task with direction and priority
    pub fn addBuildEx(self: *TaskQueue, x: f32, y: f32, building: BuildingType, direction: Direction, priority: f32) !void {
        try self.addTask(.{ .build = .{
            .position = Vec2.init(x, y),
            .building_type = building,
            .direction = direction,
        } }, priority);
    }

    /// Add repair task
    pub fn addRepair(self: *TaskQueue, x: f32, y: f32) !void {
        try self.addRepairEx(x, y, 0, 0.5);
    }

    /// Add repair task with entity and priority
    pub fn addRepairEx(self: *TaskQueue, x: f32, y: f32, target_entity: u32, priority: f32) !void {
        try self.addTask(.{ .repair = .{
            .position = Vec2.init(x, y),
            .target_entity = target_entity,
        } }, priority);
    }

    /// Add demolish task
    pub fn addDemolish(self: *TaskQueue, x: f32, y: f32) !void {
        try self.addDemolishEx(x, y, 0, 0.4);
    }

    /// Add demolish task with entity and priority
    pub fn addDemolishEx(self: *TaskQueue, x: f32, y: f32, target_entity: u32, priority: f32) !void {
        try self.addTask(.{ .demolish = .{
            .position = Vec2.init(x, y),
            .target_entity = target_entity,
        } }, priority);
    }

    /// Add craft task
    pub fn addCraft(self: *TaskQueue, recipe_id: u32, quantity: i32) !void {
        try self.addCraftEx(recipe_id, quantity, 0.5);
    }

    /// Add craft task with priority
    pub fn addCraftEx(self: *TaskQueue, recipe_id: u32, quantity: i32, priority: f32) !void {
        try self.addTask(.{ .craft = .{
            .recipe_id = recipe_id,
            .quantity = quantity,
        } }, priority);
    }

    /// Add attack task
    pub fn addAttack(self: *TaskQueue, target_entity: u32, pursue: bool) !void {
        try self.addAttackEx(target_entity, pursue, 0.8);
    }

    /// Add attack task with priority
    pub fn addAttackEx(self: *TaskQueue, target_entity: u32, pursue: bool, priority: f32) !void {
        try self.addTask(.{ .attack = .{
            .target_entity = target_entity,
            .pursue = pursue,
        } }, priority);
    }

    /// Add defend task
    pub fn addDefend(self: *TaskQueue, center_x: f32, center_y: f32, radius: f32) !void {
        try self.addDefendEx(center_x, center_y, radius, 0.7);
    }

    /// Add defend task with priority
    pub fn addDefendEx(self: *TaskQueue, center_x: f32, center_y: f32, radius: f32, priority: f32) !void {
        try self.addTask(.{ .defend = .{
            .center = Vec2.init(center_x, center_y),
            .radius = radius,
        } }, priority);
    }

    /// Add flee task from entity
    pub fn addFleeFromEntity(self: *TaskQueue, from_entity: u32, distance: f32) !void {
        try self.addTask(.{ .flee = .{
            .from_entity = from_entity,
            .distance = distance,
        } }, 0.9);
    }

    /// Add flee task from position
    pub fn addFleeFromPosition(self: *TaskQueue, x: f32, y: f32, distance: f32) !void {
        try self.addTask(.{ .flee = .{
            .from_position = Vec2.init(x, y),
            .distance = distance,
        } }, 0.9);
    }

    /// Add wait task
    pub fn addWait(self: *TaskQueue, duration: f32) !void {
        try self.addWaitEx(duration, 0.1);
    }

    /// Add wait task with priority
    pub fn addWaitEx(self: *TaskQueue, duration: f32, priority: f32) !void {
        try self.addTask(.{ .wait = .{
            .duration = duration,
            .elapsed = 0.0,
        } }, priority);
    }

    /// Add interact task
    pub fn addInteract(self: *TaskQueue, x: f32, y: f32, interaction: InteractionType) !void {
        try self.addInteractEx(x, y, interaction, 0.5);
    }

    /// Add interact task with priority
    pub fn addInteractEx(self: *TaskQueue, x: f32, y: f32, interaction: InteractionType, priority: f32) !void {
        try self.addTask(.{ .interact = .{
            .position = Vec2.init(x, y),
            .interaction_type = interaction,
        } }, priority);
    }

    /// Add interact entity task
    pub fn addInteractEntity(self: *TaskQueue, target_entity: u32, interaction: InteractionType) !void {
        try self.addInteractEntityEx(target_entity, interaction, 0.5);
    }

    /// Add interact entity task with priority
    pub fn addInteractEntityEx(self: *TaskQueue, target_entity: u32, interaction: InteractionType, priority: f32) !void {
        try self.addTask(.{ .interact_entity = .{
            .target_entity = target_entity,
            .interaction_type = interaction,
        } }, priority);
    }

    /// Add custom task
    pub fn addCustom(self: *TaskQueue, type_id: u32, data: []const u8) !void {
        try self.addCustomEx(type_id, data, 0.5);
    }

    /// Add custom task with priority
    pub fn addCustomEx(self: *TaskQueue, type_id: u32, data: []const u8, priority: f32) !void {
        var custom_data = CustomData{ .type_id = type_id };
        custom_data.setData(data);
        try self.addTask(.{ .custom = custom_data }, priority);
    }

    /// Insert task at front (after current task)
    pub fn insertFront(self: *TaskQueue, data: TaskData, priority: f32) !void {
        const task = Task{
            .data = data,
            .status = .pending,
            .progress = 0.0,
            .priority = priority,
            .assigned_entity = self.assigned_entity,
        };

        // Find first pending task (skip in-progress current task)
        var insert_idx: usize = 0;
        for (self.tasks.items, 0..) |*t, i| {
            if (t.status == .pending) {
                insert_idx = i;
                break;
            }
            insert_idx = i + 1;
        }

        try self.tasks.insert(insert_idx, task);
    }

    // ============================================================
    // Task State Management
    // ============================================================

    /// Get current task (first pending or in_progress)
    pub fn current(self: *TaskQueue) ?*Task {
        for (self.tasks.items) |*task| {
            if (task.status == .pending or task.status == .in_progress) {
                return task;
            }
        }
        return null;
    }

    /// Get current task (const)
    pub fn currentConst(self: *const TaskQueue) ?*const Task {
        for (self.tasks.items) |*task| {
            if (task.status == .pending or task.status == .in_progress) {
                return task;
            }
        }
        return null;
    }

    /// Start current task
    pub fn start(self: *TaskQueue) bool {
        if (self.current()) |task| {
            if (task.status == .pending) {
                task.status = .in_progress;
                return true;
            }
        }
        return false;
    }

    /// Complete current task
    pub fn complete(self: *TaskQueue) void {
        if (self.current()) |task| {
            task.status = .completed;
            task.progress = 1.0;
            self.completed_count += 1;

            if (self.callback) |cb| {
                cb(self, task, self.callback_userdata);
            }

            self.advanceQueue();
        }
    }

    /// Fail current task
    pub fn fail(self: *TaskQueue, reason: []const u8) void {
        if (self.current()) |task| {
            task.status = .failed;
            task.setFailReason(reason);
            self.failed_count += 1;

            if (self.callback) |cb| {
                cb(self, task, self.callback_userdata);
            }

            self.advanceQueue();
        }
    }

    /// Cancel current task
    pub fn cancel(self: *TaskQueue) void {
        if (self.current()) |task| {
            task.status = .cancelled;
            self.cancelled_count += 1;

            if (self.callback) |cb| {
                cb(self, task, self.callback_userdata);
            }

            self.advanceQueue();
        }
    }

    /// Set progress on current task
    pub fn setProgress(self: *TaskQueue, progress: f32) void {
        if (self.current()) |task| {
            task.progress = std.math.clamp(progress, 0.0, 1.0);
        }
    }

    /// Update wait task (returns true if wait completed)
    pub fn updateWait(self: *TaskQueue, delta_time: f32) bool {
        if (self.current()) |task| {
            if (task.data == .wait) {
                var wait_data = &task.data.wait;
                wait_data.elapsed += delta_time;
                task.progress = @min(wait_data.elapsed / wait_data.duration, 1.0);

                if (wait_data.elapsed >= wait_data.duration) {
                    self.complete();
                    return true;
                }
            }
        }
        return false;
    }

    /// Remove completed/failed/cancelled tasks from front
    fn advanceQueue(self: *TaskQueue) void {
        while (self.tasks.items.len > 0) {
            const task = &self.tasks.items[0];
            if (task.isDone()) {
                _ = self.tasks.orderedRemove(0);
            } else {
                break;
            }
        }
    }

    // ============================================================
    // Queue Operations
    // ============================================================

    /// Get task at index
    pub fn get(self: *TaskQueue, index: usize) ?*Task {
        if (index >= self.tasks.items.len) return null;
        return &self.tasks.items[index];
    }

    /// Get task at index (const)
    pub fn getConst(self: *const TaskQueue, index: usize) ?*const Task {
        if (index >= self.tasks.items.len) return null;
        return &self.tasks.items[index];
    }

    /// Remove task at index
    pub fn remove(self: *TaskQueue, index: usize) bool {
        if (index >= self.tasks.items.len) return false;
        _ = self.tasks.orderedRemove(index);
        return true;
    }

    /// Clear all tasks (cancels current)
    pub fn clearAll(self: *TaskQueue) void {
        // Cancel current if in progress
        if (self.current()) |task| {
            if (task.status == .in_progress) {
                task.status = .cancelled;
                self.cancelled_count += 1;

                if (self.callback) |cb| {
                    cb(self, task, self.callback_userdata);
                }
            }
        }
        self.tasks.clearRetainingCapacity();
    }

    /// Get number of tasks
    pub fn len(self: *const TaskQueue) usize {
        return self.tasks.items.len;
    }

    /// Get number of pending tasks
    pub fn pendingCount(self: *const TaskQueue) usize {
        var count: usize = 0;
        for (self.tasks.items) |*task| {
            if (task.status == .pending or task.status == .in_progress) {
                count += 1;
            }
        }
        return count;
    }

    /// Check if queue is empty
    pub fn isEmpty(self: *const TaskQueue) bool {
        return self.tasks.items.len == 0;
    }

    /// Check if queue is idle (no pending tasks)
    pub fn isIdle(self: *const TaskQueue) bool {
        return self.current() == null;
    }

    /// Get statistics
    pub fn getStats(self: *const TaskQueue) TaskQueueStats {
        var pending: usize = 0;
        for (self.tasks.items) |*task| {
            if (task.status == .pending or task.status == .in_progress) {
                pending += 1;
            }
        }

        return .{
            .total_tasks = self.tasks.items.len,
            .pending_tasks = pending,
            .completed_tasks = self.completed_count,
            .failed_tasks = self.failed_count,
            .cancelled_tasks = self.cancelled_count,
        };
    }

    /// Sort tasks by priority (highest first)
    pub fn sortByPriority(self: *TaskQueue) void {
        // Don't sort the current in-progress task
        var start_idx: usize = 0;
        if (self.tasks.items.len > 0 and self.tasks.items[0].status == .in_progress) {
            start_idx = 1;
        }

        if (start_idx >= self.tasks.items.len) return;

        const slice = self.tasks.items[start_idx..];
        std.sort.pdq(Task, slice, {}, struct {
            fn cmp(_: void, a: Task, b: Task) bool {
                return a.priority > b.priority;
            }
        }.cmp);
    }
};

// ============================================================
// Tests
// ============================================================

test "TaskQueue: basic operations" {
    const allocator = std.testing.allocator;
    var queue = TaskQueue.init(allocator);
    defer queue.deinit();

    try std.testing.expect(queue.isEmpty());
    try std.testing.expect(queue.isIdle());

    try queue.addMove(100.0, 200.0);
    try std.testing.expectEqual(@as(usize, 1), queue.len());
    try std.testing.expect(!queue.isEmpty());
}

test "TaskQueue: task lifecycle" {
    const allocator = std.testing.allocator;
    var queue = TaskQueue.init(allocator);
    defer queue.deinit();

    try queue.addMove(100.0, 200.0);
    try queue.addMove(200.0, 300.0);

    // Start first task
    try std.testing.expect(queue.start());
    var task = queue.current().?;
    try std.testing.expectEqual(TaskStatus.in_progress, task.status);

    // Complete first task
    queue.complete();
    try std.testing.expectEqual(@as(usize, 1), queue.len());

    // Second task should now be current
    task = queue.current().?;
    try std.testing.expectEqual(TaskStatus.pending, task.status);
}

test "TaskQueue: task failure" {
    const allocator = std.testing.allocator;
    var queue = TaskQueue.init(allocator);
    defer queue.deinit();

    try queue.addMove(100.0, 200.0);

    _ = queue.start();
    queue.fail("Path blocked");

    try std.testing.expect(queue.isIdle());

    const stats = queue.getStats();
    try std.testing.expectEqual(@as(usize, 1), stats.failed_tasks);
}

test "TaskQueue: task cancellation" {
    const allocator = std.testing.allocator;
    var queue = TaskQueue.init(allocator);
    defer queue.deinit();

    try queue.addMove(100.0, 200.0);
    _ = queue.start();
    queue.cancel();

    try std.testing.expect(queue.isIdle());

    const stats = queue.getStats();
    try std.testing.expectEqual(@as(usize, 1), stats.cancelled_tasks);
}

test "TaskQueue: progress tracking" {
    const allocator = std.testing.allocator;
    var queue = TaskQueue.init(allocator);
    defer queue.deinit();

    try queue.addMove(100.0, 200.0);
    _ = queue.start();

    queue.setProgress(0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), queue.current().?.progress, 0.001);

    queue.setProgress(1.5); // Should clamp
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), queue.current().?.progress, 0.001);
}

test "TaskQueue: wait task" {
    const allocator = std.testing.allocator;
    var queue = TaskQueue.init(allocator);
    defer queue.deinit();

    try queue.addWait(1.0); // 1 second wait
    _ = queue.start();

    // Update partial
    try std.testing.expect(!queue.updateWait(0.5));
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), queue.current().?.progress, 0.001);

    // Update to completion
    try std.testing.expect(queue.updateWait(0.6));
    try std.testing.expect(queue.isIdle());
}

test "TaskQueue: callback" {
    const allocator = std.testing.allocator;
    var queue = TaskQueue.init(allocator);
    defer queue.deinit();

    var callback_count: usize = 0;
    queue.setCallback(struct {
        fn cb(_: *TaskQueue, _: *const Task, userdata: ?*anyopaque) void {
            const count: *usize = @ptrCast(@alignCast(userdata.?));
            count.* += 1;
        }
    }.cb, &callback_count);

    try queue.addMove(100.0, 200.0);
    _ = queue.start();
    queue.complete();

    try std.testing.expectEqual(@as(usize, 1), callback_count);
}

test "TaskQueue: multiple task types" {
    const allocator = std.testing.allocator;
    var queue = TaskQueue.init(allocator);
    defer queue.deinit();

    try queue.addMove(100.0, 200.0);
    try queue.addCollect(50.0, 50.0, .wood);
    try queue.addBuild(200.0, 200.0, .barracks);
    try queue.addAttack(42, true);

    try std.testing.expectEqual(@as(usize, 4), queue.len());

    try std.testing.expectEqual(TaskType.move, queue.get(0).?.getType());
    try std.testing.expectEqual(TaskType.collect, queue.get(1).?.getType());
    try std.testing.expectEqual(TaskType.build, queue.get(2).?.getType());
    try std.testing.expectEqual(TaskType.attack, queue.get(3).?.getType());
}

test "TaskQueue: patrol waypoints" {
    const allocator = std.testing.allocator;
    var queue = TaskQueue.init(allocator);
    defer queue.deinit();

    const waypoints = [_]Vec2{
        Vec2.init(0.0, 0.0),
        Vec2.init(100.0, 0.0),
        Vec2.init(100.0, 100.0),
        Vec2.init(0.0, 100.0),
    };

    try queue.addPatrol(&waypoints, true);

    const task = queue.current().?;
    try std.testing.expectEqual(TaskType.patrol, task.getType());

    const patrol = &task.data.patrol;
    try std.testing.expectEqual(@as(u8, 4), patrol.waypoint_count);

    const wp0 = patrol.getCurrentWaypoint().?;
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), wp0.x, 0.001);
}

test "TaskQueue: insert front" {
    const allocator = std.testing.allocator;
    var queue = TaskQueue.init(allocator);
    defer queue.deinit();

    try queue.addMove(100.0, 100.0);
    try queue.addMove(200.0, 200.0);

    // Insert urgent task at front
    try queue.insertFront(.{ .attack = .{ .target_entity = 1, .pursue = true } }, 1.0);

    // First should still be move (pending)
    try std.testing.expectEqual(TaskType.move, queue.get(0).?.getType());
    // Second should be attack (inserted)
    try std.testing.expectEqual(TaskType.attack, queue.get(1).?.getType());
}

test "TaskQueue: sort by priority" {
    const allocator = std.testing.allocator;
    var queue = TaskQueue.init(allocator);
    defer queue.deinit();

    try queue.addMoveEx(100.0, 100.0, false, 0.2);
    try queue.addMoveEx(200.0, 200.0, false, 0.8);
    try queue.addMoveEx(300.0, 300.0, false, 0.5);

    queue.sortByPriority();

    try std.testing.expectApproxEqAbs(@as(f32, 0.8), queue.get(0).?.priority, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), queue.get(1).?.priority, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), queue.get(2).?.priority, 0.001);
}

test "TaskQueue: assigned entity" {
    const allocator = std.testing.allocator;
    var queue = TaskQueue.initWithConfig(allocator, .{ .assigned_entity = 42 });
    defer queue.deinit();

    try queue.addMove(100.0, 100.0);

    try std.testing.expectEqual(@as(u32, 42), queue.getAssignedEntity());
    try std.testing.expectEqual(@as(u32, 42), queue.current().?.assigned_entity);
}

test "TaskQueue: clear all" {
    const allocator = std.testing.allocator;
    var queue = TaskQueue.init(allocator);
    defer queue.deinit();

    try queue.addMove(100.0, 100.0);
    try queue.addMove(200.0, 200.0);

    _ = queue.start();
    queue.clearAll();

    try std.testing.expect(queue.isEmpty());
}

test "TaskQueue: custom task" {
    const allocator = std.testing.allocator;
    var queue = TaskQueue.init(allocator);
    defer queue.deinit();

    const custom_data = "hello world";
    try queue.addCustom(999, custom_data);

    const task = queue.current().?;
    try std.testing.expectEqual(TaskType.custom, task.getType());
    try std.testing.expectEqual(@as(u32, 999), task.data.custom.type_id);
    try std.testing.expectEqualStrings(custom_data, task.data.custom.getData());
}

test "TaskQueue: task type names" {
    try std.testing.expectEqualStrings("Move", TaskType.move.name());
    try std.testing.expectEqualStrings("Attack", TaskType.attack.name());
    try std.testing.expectEqualStrings("Build", TaskType.build.name());
}

test "TaskQueue: remove task" {
    const allocator = std.testing.allocator;
    var queue = TaskQueue.init(allocator);
    defer queue.deinit();

    try queue.addMove(100.0, 100.0);
    try queue.addMove(200.0, 200.0);
    try queue.addMove(300.0, 300.0);

    try std.testing.expect(queue.remove(1));
    try std.testing.expectEqual(@as(usize, 2), queue.len());

    // Check remaining tasks
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), queue.get(0).?.data.move.target.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 300.0), queue.get(1).?.data.move.target.x, 0.001);
}

test "TaskQueue: Vec2 distance" {
    const a = Vec2.init(0.0, 0.0);
    const b = Vec2.init(3.0, 4.0);

    try std.testing.expectApproxEqAbs(@as(f32, 5.0), a.distance(b), 0.001);
}

test "TaskQueue: stats" {
    const allocator = std.testing.allocator;
    var queue = TaskQueue.init(allocator);
    defer queue.deinit();

    try queue.addMove(100.0, 100.0);
    try queue.addMove(200.0, 200.0);

    _ = queue.start();
    queue.complete();

    _ = queue.start();
    queue.fail("error");

    const stats = queue.getStats();
    try std.testing.expectEqual(@as(usize, 1), stats.completed_tasks);
    try std.testing.expectEqual(@as(usize, 1), stats.failed_tasks);
    try std.testing.expectEqual(@as(usize, 0), stats.pending_tasks);
}

test "TaskQueue: defend and flee tasks" {
    const allocator = std.testing.allocator;
    var queue = TaskQueue.init(allocator);
    defer queue.deinit();

    try queue.addDefend(50.0, 50.0, 25.0);
    try queue.addFleeFromEntity(99, 100.0);
    try queue.addFleeFromPosition(0.0, 0.0, 50.0);

    try std.testing.expectEqual(@as(usize, 3), queue.len());

    const defend = queue.get(0).?.data.defend;
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), defend.center.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 25.0), defend.radius, 0.001);

    const flee1 = queue.get(1).?.data.flee;
    try std.testing.expectEqual(@as(u32, 99), flee1.from_entity);

    const flee2 = queue.get(2).?.data.flee;
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), flee2.from_position.x, 0.001);
}
