# Blackboard System

Type-safe key-value storage for AI cross-system communication (`src/blackboard.zig`).

## Features

- **Type-safe value storage** - int32, int64, float32, float64, bool, string, pointer, vec2, vec3
- **Resource reservations** - Multi-agent coordination with expiration
- **Plan publication** - Intent broadcasting with conflict detection
- **Decision history** - Audit logging with circular buffer
- **Change subscriptions** - Key-specific or wildcard callbacks
- **Copy and merge** - Blackboard duplication and combining

## Usage

### Basic Storage

```zig
const blackboard = @import("AgentiteZ").blackboard;

var bb = blackboard.Blackboard.init(allocator);
defer bb.deinit();

// Store typed values
try bb.setInt("player_health", 100);
try bb.setFloat("threat_level", 0.75);
try bb.setVec2("target_pos", .{ 100.0, 200.0 });
try bb.setString("current_state", "patrol");

// Retrieve with defaults
const health = bb.getIntOr("player_health", 0);
const threat = bb.getFloatOr("threat_level", 0.0);
const pos = bb.getVec2Or("target_pos", .{ 0.0, 0.0 });

// Check existence
if (bb.has("enemy_spotted")) {
    // React to enemy
}
```

### Resource Reservations

```zig
// Reserve resources for planned actions
try bb.reserve("gold", 500, "build_barracks");
try bb.reserveEx("iron", 100, "craft_sword", 5); // Expires in 5 turns

// Check availability
const total_gold: i32 = 1000;
const available = bb.getAvailable("gold", total_gold); // 500

// Get reservation by owner
const reserved = bb.getReservation("gold", "build_barracks"); // 500

// Release when done
_ = bb.release("gold", "build_barracks");
_ = bb.releaseAll("builder_1"); // Release all from owner

// Update to expire time-limited reservations
bb.update();
```

### Plan Publication

```zig
// Publish intent for coordination
try bb.publishPlan("army_1", "Attack enemy base");
try bb.publishPlanEx("army_2", "Defend home", "home_base", 10);

// Check for conflicts
if (bb.hasConflictingPlan("enemy_base")) {
    // Another unit already targeting this
}

// Get plan details
if (bb.getPlan("army_1")) |plan| {
    std.debug.print("Plan: {s}\n", .{plan.getDescription()});
}

// Cancel plan
_ = bb.cancelPlan("army_1");
```

### Decision History

```zig
bb.setTurn(5);
bb.log("AI decided to attack {s} with priority {d:.2}", .{ "enemy_base", 0.85 });
bb.log("Resource check: gold={d}, iron={d}", .{ 500, 200 });

// Retrieve history (newest first)
const history = try bb.getHistory(allocator, 10);
defer allocator.free(history);

for (history) |entry| {
    std.debug.print("[Turn {d}] {s}\n", .{ entry.turn, entry.getText() });
}
```

### Change Subscriptions

```zig
fn onThreatChanged(
    bb: *blackboard.Blackboard,
    key: []const u8,
    old_value: ?blackboard.Value,
    new_value: blackboard.Value,
    userdata: ?*anyopaque,
) void {
    const game: *Game = @ptrCast(@alignCast(userdata.?));
    if (new_value.toFloat() > 0.8) {
        game.triggerAlert();
    }
}

const handle = try bb.subscribe("threat_level", onThreatChanged, &game);

// Or subscribe to all changes
_ = try bb.subscribeAll(logAllChanges, null);

// Unsubscribe when done
_ = bb.unsubscribe(handle);
```

## Data Structures

- `Blackboard` - Main storage with entries, reservations, plans, history, subscriptions
- `Value` - Tagged union of all value types with coercion methods
- `Reservation` - Resource reservation with owner and expiration
- `Plan` - Published plan with description, target, and duration
- `HistoryEntry` - Decision log entry with text, turn, and timestamp
- `BlackboardStats` - Statistics (entry_count, reservation_count, etc.)

## Constants

- `MAX_STRING_LENGTH` = 255
- `MAX_KEY_LENGTH` = 63

## Tests

18 comprehensive tests covering value storage, type coercion, reservations, plans, history, subscriptions, and edge cases.
