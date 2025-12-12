# HTN Planner

Hierarchical Task Network planner for AI planning (`src/htn.zig`).

## Features

- **Primitive tasks** - Basic executable actions with preconditions and effects
- **Compound tasks** - High-level tasks that decompose into subtasks via methods
- **Preconditions** - Conditions that must be satisfied (comparison operators, exists/not_exists)
- **Effects** - World state modifications (set, add, remove operations)
- **Method selection** - Automatic selection based on preconditions
- **Plan generation** - Decompose goals into executable primitive task sequences
- **Cost tracking** - Task costs for plan optimization
- **Blackboard integration** - Uses Blackboard for world state representation

## Usage

### Basic Task Definition

```zig
const htn = @import("AgentiteZ").htn;
const blackboard = @import("AgentiteZ").blackboard;

var planner = htn.HTNPlanner.init(allocator);
defer planner.deinit();

// Define primitive tasks
try planner.definePrimitive("move_to_target", .{
    .preconditions = &.{
        .{ .key = "has_target", .op = .equals, .value = .{ .boolean = true } },
    },
    .effects = &.{
        .{ .key = "at_target", .value = .{ .boolean = true } },
    },
    .cost = 1.0,
});

try planner.definePrimitive("attack", .{
    .preconditions = &.{
        .{ .key = "at_target", .op = .equals, .value = .{ .boolean = true } },
    },
    .effects = &.{
        .{ .key = "target_attacked", .value = .{ .boolean = true } },
    },
    .cost = 2.0,
});
```

### Compound Tasks with Methods

```zig
// Define compound task with multiple methods
try planner.defineCompound("attack_enemy", .{
    .methods = &.{
        // Ranged method (preferred if has_bow)
        .{
            .name = "ranged_attack",
            .preconditions = &.{
                .{ .key = "has_bow", .op = .equals, .value = .{ .boolean = true } },
            },
            .subtasks = &.{ "aim", "shoot" },
        },
        // Melee method (fallback)
        .{
            .name = "melee_attack",
            .subtasks = &.{ "move_to_target", "attack" },
        },
    },
});
```

### Plan Generation

```zig
// Create world state
var world = blackboard.Blackboard.init(allocator);
defer world.deinit();
try world.setBool("has_target", true);

// Generate plan
const plan = try planner.plan(&world, "attack_enemy");
defer allocator.free(plan);

// Execute plan
for (plan) |*task| {
    std.debug.print("Execute: {s}\n", .{task.getName()});
    try planner.execute(&world, task.getName());
}
```

### Precondition Operators

```zig
// Available comparison operators
try planner.definePrimitive("heal", .{
    .preconditions = &.{
        .{ .key = "health", .op = .less_than, .value = .{ .int32 = 50 } },
        .{ .key = "has_potion", .op = .equals, .value = .{ .boolean = true } },
    },
});

// Check existence
try planner.definePrimitive("find_target", .{
    .preconditions = &.{
        .{ .key = "target", .op = .not_exists }, // No current target
    },
    .effects = &.{
        .{ .key = "target", .value = .{ .int32 = 1 } },
    },
});
```

### Effect Operations

```zig
// Set value
.{ .key = "has_weapon", .value = .{ .boolean = true }, .operation = .set }

// Add to value (numeric)
.{ .key = "gold", .value = .{ .int32 = 100 }, .operation = .add }

// Remove key
.{ .key = "quest_item", .value = .{ .boolean = false }, .operation = .remove }
```

### Nested Compound Tasks

```zig
// Compound tasks can reference other compound tasks
try planner.defineCompound("full_battle", .{
    .methods = &.{
        .{
            .name = "engage",
            .subtasks = &.{ "prepare_weapons", "attack_enemy", "loot" },
        },
    },
});
```

### Task Costs and Plan Optimization

```zig
// Define costs for planning decisions
try planner.definePrimitive("walk", .{ .cost = 1.0 });
try planner.definePrimitive("run", .{ .cost = 0.5 });  // Faster but uses stamina

// Calculate total plan cost
const cost = planner.getPlanCost(plan);
```

### Checking Executability

```zig
// Check if task can execute in current world state
if (planner.canExecute(&world, "attack")) {
    // Task preconditions are satisfied
}

// Execute and apply effects
try planner.execute(&world, "attack");
```

## Data Structures

- `HTNPlanner` - Main planner with task definitions and planning algorithm
- `PlannedTask` - A task in the generated plan (name reference)
- `Condition` - Precondition with key, operator, and expected value
- `Effect` - State modification with key, value, and operation
- `Method` - Decomposition method with preconditions and subtask list
- `PlanStats` - Statistics (primitive_count, compound_count, plans generated/failed)

### Condition Operators

- `equals`, `not_equals` - Value comparison
- `less_than`, `less_equal`, `greater_than`, `greater_equal` - Numeric comparison
- `exists`, `not_exists` - Key presence check

### Effect Operations

- `set` - Set key to value
- `add` - Add to current numeric value
- `remove` - Remove key from world state

## Constants

- `MAX_NAME_LENGTH` = 63
- `MAX_PRECONDITIONS` = 16
- `MAX_EFFECTS` = 16
- `MAX_SUBTASKS` = 16
- `MAX_METHODS` = 8
- `MAX_PLAN_DEPTH` = 100

## Error Handling

- `error.NameTooLong` - Task/key name exceeds MAX_NAME_LENGTH
- `error.TooManyPreconditions` - Exceeds MAX_PRECONDITIONS
- `error.TooManyEffects` - Exceeds MAX_EFFECTS
- `error.TooManyMethods` - Exceeds MAX_METHODS
- `error.TooManySubtasks` - Exceeds MAX_SUBTASKS
- `error.NoMethods` - Compound task has no methods
- `error.NoSubtasks` - Method has no subtasks
- `error.DuplicateTask` - Task name already defined
- `error.UnknownTask` - Referenced task not found
- `error.PlanningFailed` - No valid plan found (preconditions unsatisfied)
- `error.PreconditionsNotMet` - Cannot execute task
- `error.NotPrimitive` - Cannot execute compound task directly

## Tests

20 comprehensive tests covering primitive/compound tasks, preconditions, effects, method selection, nested tasks, costs, and complex scenarios.
