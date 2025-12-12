# Event System

Generic pub/sub event dispatcher for decoupled game system communication (`src/event.zig`).

## Features

- **Generic event types** - Works with any tagged union for type-safe events
- **Subscription handles** - Safe unsubscription using returned handles
- **Context pointers** - Pass state to callbacks without closures
- **Event queuing** - Automatic queue during dispatch prevents recursion
- **"All events" subscription** - Subscribe to every event type for debugging/logging
- **Batch unsubscription** - Remove all subscriptions for a context at once
- **Statistics tracking** - Monitor events dispatched, queued, and subscription counts

## Usage

### Basic Events

```zig
const event = @import("AgentiteZ").event;

// Define game events as a tagged union
const GameEvent = union(enum) {
    entity_spawned: struct { id: u32, x: f32, y: f32 },
    entity_died: struct { id: u32, killer_id: ?u32 },
    level_completed: struct { level: u32, score: u32 },
    damage_dealt: struct { target: u32, amount: u32, source: u32 },
};

// Create dispatcher
var dispatcher = event.EventDispatcher(GameEvent).init(allocator);
defer dispatcher.deinit();

// Subscribe to specific event type
const handle = try dispatcher.subscribe(.entity_died, onEntityDied, &game_state);

// Dispatch events
try dispatcher.dispatch(.{ .entity_died = .{ .id = 42, .killer_id = 7 } });

// Unsubscribe when done
dispatcher.unsubscribe(handle);
```

### Event Callbacks

```zig
const GameState = struct {
    score: u32 = 0,
    enemies_killed: u32 = 0,

    fn onEntityDied(evt: GameEvent, ctx: ?*anyopaque) void {
        const self: *GameState = @ptrCast(@alignCast(ctx.?));
        switch (evt) {
            .entity_died => |data| {
                self.enemies_killed += 1;
                if (data.killer_id != null) {
                    self.score += 100;
                }
            },
            else => {},
        }
    }
};

var state = GameState{};
_ = try dispatcher.subscribe(.entity_died, GameState.onEntityDied, &state);
```

### Subscribe to All Events

```zig
fn logAllEvents(evt: GameEvent, _: ?*anyopaque) void {
    std.log.info("Event: {s}", .{@tagName(evt)});
}

_ = try dispatcher.subscribeAll(logAllEvents, null);
```

### Event Queuing

```zig
// Queue events for later processing
try dispatcher.queue(.{ .damage_dealt = .{ .target = 5, .amount = 10, .source = 1 } });
try dispatcher.queue(.{ .damage_dealt = .{ .target = 5, .amount = 15, .source = 2 } });

// Process all queued events at end of frame
dispatcher.processQueue();

// Events dispatched from within callbacks are automatically queued
```

### Cleanup

```zig
// Remove all subscriptions for a destroyed object
const removed = dispatcher.unsubscribeContext(&dying_object);

// Clear all subscriptions
dispatcher.clearSubscriptions();

// Clear pending events without processing
dispatcher.clearQueue();
```

### Statistics

```zig
const stats = dispatcher.getStats();
std.debug.print("Subscriptions: {}, Queued: {}, Dispatched: {}\n", .{
    stats.subscriptions,
    stats.queued,
    stats.events_dispatched,
});

const death_listeners = dispatcher.getSubscriptionCountFor(.entity_died);
```

## Data Structures

- `EventDispatcher(EventType)` - Generic dispatcher parameterized by event union
- `SubscriptionHandle` - Handle for unsubscription (id + event_tag)
- `EventDispatcherConfig` - Configuration (initial capacities, warning settings)

## Configuration

```zig
var dispatcher = event.EventDispatcher(GameEvent).initWithConfig(allocator, .{
    .initial_subscription_capacity = 32,
    .initial_queue_capacity = 64,
    .warn_no_subscribers = true,
});
```

## Key Methods

- `subscribe(event_tag, callback, context)` - Subscribe to specific event type
- `subscribeAll(callback, context)` - Subscribe to all events
- `unsubscribe(handle)` - Remove subscription by handle
- `unsubscribeContext(context)` - Remove all subscriptions for a context
- `dispatch(event)` - Send event immediately (queues if mid-dispatch)
- `queue(event)` - Queue event for later processing
- `processQueue()` - Process all queued events

## Tests

16 comprehensive tests covering subscribe/unsubscribe, event filtering, queuing, recursion prevention, context cleanup, statistics, and complex event data.
