# Task Queue System

Sequential task execution for AI agents (`src/task_queue.zig`).

## Features

- **19 task types** - move, explore, patrol, follow, collect, deposit, withdraw, mine, build, repair, demolish, craft, attack, defend, flee, wait, interact, interact_entity, custom
- **Task lifecycle** - pending, in_progress, completed, failed, cancelled states
- **Priority-based execution** - Sort and insert by priority
- **Progress tracking** - 0.0 to 1.0 progress per task
- **Completion callbacks** - Notify on task completion/failure/cancellation
- **Wait task support** - Time-based waiting with auto-completion

## Usage

### Basic Queue

```zig
const task_queue = @import("AgentiteZ").task_queue;

var queue = task_queue.TaskQueue.init(allocator);
defer queue.deinit();

queue.setAssignedEntity(player_entity_id);

// Add tasks
try queue.addMove(100.0, 200.0);
try queue.addCollect(50.0, 50.0, .wood);
try queue.addBuild(200.0, 200.0, .barracks);
try queue.addWait(2.0); // Wait 2 seconds

// Process current task
if (queue.current()) |task| {
    if (task.status == .pending) {
        _ = queue.start();
    }

    switch (task.data) {
        .move => |move| {
            if (reached_target) {
                queue.complete();
            }
        },
        .wait => {
            _ = queue.updateWait(delta_time);
        },
        else => {},
    }
}
```

### Task Types

```zig
// Movement tasks
try queue.addMove(x, y);
try queue.addMoveEx(x, y, true, 0.8); // run=true, priority=0.8
try queue.addExplore(center_x, center_y, radius);
try queue.addPatrol(&waypoints, true); // loop=true
try queue.addFollow(target_entity, min_dist, max_dist);

// Resource tasks
try queue.addCollect(x, y, .iron);
try queue.addCollectEx(x, y, .iron, 10, 0.5);
try queue.addDeposit(storage_x, storage_y, .iron);
try queue.addWithdraw(storage_x, storage_y, .gold, 100);
try queue.addMine(x, y, 50);

// Building tasks
try queue.addBuild(x, y, .barracks);
try queue.addBuildEx(x, y, .wall, .north, 0.6);
try queue.addRepair(x, y);
try queue.addDemolish(x, y);

// Combat tasks
try queue.addAttack(target_entity, true); // pursue=true
try queue.addDefend(center_x, center_y, radius);
try queue.addFleeFromEntity(enemy_id, 100.0);
try queue.addFleeFromPosition(danger_x, danger_y, 50.0);

// Utility tasks
try queue.addWait(duration);
try queue.addInteract(x, y, .use);
try queue.addInteractEntity(npc_id, .talk);
try queue.addCraft(recipe_id, quantity);

// Custom tasks
try queue.addCustom(my_type_id, &custom_data);
```

### Priority and Control

```zig
// Add high-priority task at front
try queue.insertFront(.{ .attack = .{
    .target_entity = 42,
    .pursue = true,
} }, 1.0);

// Sort by priority
queue.sortByPriority();

// Get task at index
if (queue.get(2)) |task| {
    std.debug.print("Task 2: {s}\n", .{task.getTypeName()});
}

// Remove specific task
_ = queue.remove(1);

// Clear all tasks
queue.clearAll();
```

### Callbacks

```zig
queue.setCallback(struct {
    fn onTaskComplete(q: *task_queue.TaskQueue, task: *const task_queue.Task, userdata: ?*anyopaque) void {
        const game: *Game = @ptrCast(@alignCast(userdata.?));

        switch (task.status) {
            .completed => game.onTaskDone(task),
            .failed => game.onTaskFailed(task.getFailReason()),
            .cancelled => game.onTaskCancelled(),
            else => {},
        }
    }
}.onTaskComplete, &game);
```

## Data Structures

- `TaskQueue` - Queue with tasks, callbacks, and statistics
- `Task` - Task entry with data, status, progress, priority
- `TaskData` - Tagged union of all 19 task type data
- `TaskStatus` - pending, in_progress, completed, failed, cancelled
- `TaskType` - Enum of task types with `.name()` method
- `Vec2` - 2D position with distance calculation
- `ResourceType` - none, wood, stone, iron, gold, food, energy, custom
- `BuildingType` - none, house, barracks, farm, mine, factory, wall, tower, custom
- `InteractionType` - none, use, activate, talk, trade, pickup, open, close, custom
- `Direction` - none, north, south, east, west, etc.

## Key Methods

- `addMove()`, `addCollect()`, `addBuild()`, etc. - Add specific task types
- `insertFront(data, priority)` - Insert after current task
- `current()` - Get active task
- `start()` - Mark current task as in_progress
- `complete()` - Mark task done and advance
- `fail(reason)` - Mark task failed
- `cancel()` - Cancel current task
- `setProgress(0.0-1.0)` - Update progress
- `updateWait(delta)` - Progress wait tasks
- `sortByPriority()` - Reorder by priority
- `getStats()` - Get queue statistics

## Tests

18 comprehensive tests covering task lifecycle, all task types, callbacks, priority sorting, and statistics.
