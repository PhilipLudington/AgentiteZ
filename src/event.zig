//! Event System - Generic Pub/Sub Event Dispatcher
//!
//! A flexible event system for decoupled communication between game systems.
//! Supports both immediate and deferred (queued) event dispatch.
//!
//! Features:
//! - Generic event types (works with any enum or tagged union)
//! - Subscription handles for safe unsubscription
//! - Context pointers for stateful callbacks
//! - Event queuing to prevent recursion during dispatch
//! - "All events" subscription for debugging/logging
//! - Batch unsubscription by context
//!
//! Usage:
//! ```zig
//! const GameEvent = union(enum) {
//!     entity_spawned: struct { id: u32 },
//!     entity_died: struct { id: u32, killer_id: ?u32 },
//!     level_completed: struct { level: u32, score: u32 },
//! };
//!
//! var dispatcher = EventDispatcher(GameEvent).init(allocator);
//! defer dispatcher.deinit();
//!
//! const handle = try dispatcher.subscribe(.entity_died, onEntityDied, &game_state);
//! try dispatcher.dispatch(.{ .entity_died = .{ .id = 42, .killer_id = 7 } });
//! dispatcher.unsubscribe(handle);
//! ```

const std = @import("std");

const log = std.log.scoped(.event);

/// Subscription handle for managing event subscriptions
pub const SubscriptionHandle = struct {
    id: u32,
    event_tag: u32, // Tag value of the subscribed event type (or max for "all")
};

/// Configuration for EventDispatcher
pub const EventDispatcherConfig = struct {
    /// Initial capacity for subscriptions array
    initial_subscription_capacity: usize = 16,
    /// Initial capacity for event queue
    initial_queue_capacity: usize = 32,
    /// Log events with no subscribers (useful for debugging)
    warn_no_subscribers: bool = true,
};

/// Generic event dispatcher for pub/sub event handling
///
/// `EventType` should be a tagged union where each variant represents an event kind.
/// Each variant can contain event-specific data.
pub fn EventDispatcher(comptime EventType: type) type {
    const event_info = @typeInfo(EventType);
    if (event_info != .@"union") {
        @compileError("EventDispatcher requires a tagged union type, got " ++ @typeName(EventType));
    }
    const union_info = event_info.@"union";
    if (union_info.tag_type == null) {
        @compileError("EventDispatcher requires a tagged union (with enum tag), got untagged union");
    }

    const TagType = union_info.tag_type.?;

    return struct {
        const Self = @This();

        /// Event callback function type
        /// Returns true to continue processing, false to stop propagation
        pub const EventCallback = *const fn (event: EventType, context: ?*anyopaque) void;

        /// Internal subscription record
        const Subscription = struct {
            handle: SubscriptionHandle,
            callback: EventCallback,
            context: ?*anyopaque,
        };

        allocator: std.mem.Allocator,
        subscriptions: std.ArrayList(Subscription),
        next_subscription_id: u32,
        event_queue: std.ArrayList(EventType),
        processing_events: bool,
        config: EventDispatcherConfig,

        // Statistics
        events_dispatched: u64 = 0,
        events_queued: u64 = 0,

        /// Special tag value indicating subscription to all events
        pub const ALL_EVENTS_TAG: u32 = std.math.maxInt(u32);

        /// Initialize the event dispatcher
        pub fn init(allocator: std.mem.Allocator) Self {
            return initWithConfig(allocator, .{});
        }

        /// Initialize with custom configuration
        pub fn initWithConfig(allocator: std.mem.Allocator, config: EventDispatcherConfig) Self {
            return Self{
                .allocator = allocator,
                .subscriptions = std.ArrayList(Subscription).initCapacity(allocator, config.initial_subscription_capacity) catch std.ArrayList(Subscription).init(allocator),
                .next_subscription_id = 1,
                .event_queue = std.ArrayList(EventType).initCapacity(allocator, config.initial_queue_capacity) catch std.ArrayList(EventType).init(allocator),
                .processing_events = false,
                .config = config,
            };
        }

        /// Clean up resources
        pub fn deinit(self: *Self) void {
            self.subscriptions.deinit();
            self.event_queue.deinit();
        }

        /// Subscribe to a specific event type
        ///
        /// Returns a handle that can be used to unsubscribe later.
        pub fn subscribe(
            self: *Self,
            event_tag: TagType,
            callback: EventCallback,
            context: ?*anyopaque,
        ) !SubscriptionHandle {
            const handle = SubscriptionHandle{
                .id = self.next_subscription_id,
                .event_tag = @intFromEnum(event_tag),
            };
            self.next_subscription_id += 1;

            try self.subscriptions.append(.{
                .handle = handle,
                .callback = callback,
                .context = context,
            });

            log.debug("Subscription created: id={}, event={s}", .{ handle.id, @tagName(event_tag) });

            return handle;
        }

        /// Subscribe to all events (useful for logging/debugging)
        pub fn subscribeAll(
            self: *Self,
            callback: EventCallback,
            context: ?*anyopaque,
        ) !SubscriptionHandle {
            const handle = SubscriptionHandle{
                .id = self.next_subscription_id,
                .event_tag = ALL_EVENTS_TAG,
            };
            self.next_subscription_id += 1;

            try self.subscriptions.append(.{
                .handle = handle,
                .callback = callback,
                .context = context,
            });

            log.debug("Subscription created: id={}, event=ALL", .{handle.id});

            return handle;
        }

        /// Unsubscribe using a subscription handle
        pub fn unsubscribe(self: *Self, handle: SubscriptionHandle) void {
            for (self.subscriptions.items, 0..) |sub, i| {
                if (sub.handle.id == handle.id) {
                    _ = self.subscriptions.swapRemove(i);
                    log.debug("Subscription removed: id={}", .{handle.id});
                    return;
                }
            }
            log.warn("Attempted to unsubscribe non-existent handle: id={}", .{handle.id});
        }

        /// Unsubscribe all subscriptions for a given context
        ///
        /// Useful when destroying an object that has multiple subscriptions.
        pub fn unsubscribeContext(self: *Self, context: *anyopaque) usize {
            var i: usize = 0;
            var removed: usize = 0;
            while (i < self.subscriptions.items.len) {
                if (self.subscriptions.items[i].context == context) {
                    _ = self.subscriptions.swapRemove(i);
                    removed += 1;
                } else {
                    i += 1;
                }
            }
            if (removed > 0) {
                log.debug("Removed {} subscriptions for context", .{removed});
            }
            return removed;
        }

        /// Dispatch an event immediately to all subscribers
        ///
        /// If called during event processing (from within a callback),
        /// the event will be queued and processed after the current event.
        pub fn dispatch(self: *Self, event: EventType) !void {
            // If we're already processing events, queue this one to avoid recursion
            if (self.processing_events) {
                try self.event_queue.append(event);
                self.events_queued += 1;
                return;
            }

            self.processing_events = true;
            defer self.processing_events = false;

            // Process the immediate event
            self.processEvent(event);
            self.events_dispatched += 1;

            // Process any queued events (handles recursive dispatch)
            while (self.event_queue.items.len > 0) {
                const queued = self.event_queue.orderedRemove(0);
                self.processEvent(queued);
                self.events_dispatched += 1;
            }
        }

        /// Queue an event for later processing
        ///
        /// Events queued this way will be processed on the next call to
        /// `dispatch()` or `processQueue()`.
        pub fn queue(self: *Self, event: EventType) !void {
            try self.event_queue.append(event);
            self.events_queued += 1;
        }

        /// Process all queued events
        ///
        /// Call this once per frame to process deferred events.
        pub fn processQueue(self: *Self) void {
            if (self.processing_events) {
                // Already processing, queue will be drained by dispatch()
                return;
            }

            self.processing_events = true;
            defer self.processing_events = false;

            while (self.event_queue.items.len > 0) {
                const event = self.event_queue.orderedRemove(0);
                self.processEvent(event);
                self.events_dispatched += 1;
            }
        }

        /// Internal: process a single event
        fn processEvent(self: *Self, event: EventType) void {
            const event_tag: u32 = @intFromEnum(event);
            var delivered_count: u32 = 0;

            for (self.subscriptions.items) |sub| {
                // Deliver to subscribers of this specific event type or ALL events
                if (sub.handle.event_tag == event_tag or sub.handle.event_tag == ALL_EVENTS_TAG) {
                    sub.callback(event, sub.context);
                    delivered_count += 1;
                }
            }

            if (delivered_count == 0 and self.config.warn_no_subscribers) {
                log.warn("Event dispatched with no subscribers: {s}", .{@tagName(event)});
            }
        }

        /// Get the number of active subscriptions
        pub fn getSubscriptionCount(self: *const Self) usize {
            return self.subscriptions.items.len;
        }

        /// Get the number of subscriptions for a specific event type
        pub fn getSubscriptionCountFor(self: *const Self, event_tag: TagType) usize {
            const tag: u32 = @intFromEnum(event_tag);
            var count: usize = 0;
            for (self.subscriptions.items) |sub| {
                if (sub.handle.event_tag == tag or sub.handle.event_tag == ALL_EVENTS_TAG) {
                    count += 1;
                }
            }
            return count;
        }

        /// Get the number of queued events
        pub fn getQueuedEventCount(self: *const Self) usize {
            return self.event_queue.items.len;
        }

        /// Check if currently processing events
        pub fn isProcessing(self: *const Self) bool {
            return self.processing_events;
        }

        /// Get dispatch statistics
        pub fn getStats(self: *const Self) struct {
            subscriptions: usize,
            queued: usize,
            events_dispatched: u64,
            events_queued: u64,
        } {
            return .{
                .subscriptions = self.subscriptions.items.len,
                .queued = self.event_queue.items.len,
                .events_dispatched = self.events_dispatched,
                .events_queued = self.events_queued,
            };
        }

        /// Clear all subscriptions
        pub fn clearSubscriptions(self: *Self) void {
            self.subscriptions.clearRetainingCapacity();
            log.debug("All subscriptions cleared", .{});
        }

        /// Clear the event queue without processing
        pub fn clearQueue(self: *Self) void {
            self.event_queue.clearRetainingCapacity();
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "EventDispatcher - basic subscribe and dispatch" {
    const TestEvent = union(enum) {
        player_joined: struct { id: u32 },
        player_left: struct { id: u32 },
    };

    const Context = struct {
        call_count: u32 = 0,
        last_player_id: u32 = 0,

        fn onPlayerJoined(event: TestEvent, ctx: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            self.call_count += 1;
            switch (event) {
                .player_joined => |data| self.last_player_id = data.id,
                else => {},
            }
        }
    };

    var ctx = Context{};
    var dispatcher = EventDispatcher(TestEvent).init(std.testing.allocator);
    defer dispatcher.deinit();

    const handle = try dispatcher.subscribe(.player_joined, Context.onPlayerJoined, &ctx);
    _ = handle;

    try dispatcher.dispatch(.{ .player_joined = .{ .id = 42 } });

    try std.testing.expectEqual(@as(u32, 1), ctx.call_count);
    try std.testing.expectEqual(@as(u32, 42), ctx.last_player_id);
}

test "EventDispatcher - unsubscribe" {
    const TestEvent = union(enum) {
        tick: struct {},
    };

    const Context = struct {
        call_count: u32 = 0,

        fn onTick(_: TestEvent, ctx: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            self.call_count += 1;
        }
    };

    var ctx = Context{};
    var dispatcher = EventDispatcher(TestEvent).init(std.testing.allocator);
    defer dispatcher.deinit();

    const handle = try dispatcher.subscribe(.tick, Context.onTick, &ctx);

    try dispatcher.dispatch(.{ .tick = .{} });
    try std.testing.expectEqual(@as(u32, 1), ctx.call_count);

    dispatcher.unsubscribe(handle);

    try dispatcher.dispatch(.{ .tick = .{} });
    try std.testing.expectEqual(@as(u32, 1), ctx.call_count); // No change
}

test "EventDispatcher - subscribeAll receives all events" {
    const TestEvent = union(enum) {
        event_a: struct {},
        event_b: struct {},
        event_c: struct {},
    };

    const Context = struct {
        call_count: u32 = 0,

        fn onAnyEvent(_: TestEvent, ctx: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            self.call_count += 1;
        }
    };

    var ctx = Context{};
    var dispatcher = EventDispatcher(TestEvent).init(std.testing.allocator);
    defer dispatcher.deinit();

    _ = try dispatcher.subscribeAll(Context.onAnyEvent, &ctx);

    try dispatcher.dispatch(.{ .event_a = .{} });
    try dispatcher.dispatch(.{ .event_b = .{} });
    try dispatcher.dispatch(.{ .event_c = .{} });

    try std.testing.expectEqual(@as(u32, 3), ctx.call_count);
}

test "EventDispatcher - unsubscribeContext removes all subscriptions for context" {
    const TestEvent = union(enum) {
        event_a: struct {},
        event_b: struct {},
    };

    const Context = struct {
        call_count: u32 = 0,

        fn handler(_: TestEvent, ctx: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            self.call_count += 1;
        }
    };

    var ctx1 = Context{};
    var ctx2 = Context{};
    var dispatcher = EventDispatcher(TestEvent).init(std.testing.allocator);
    defer dispatcher.deinit();

    _ = try dispatcher.subscribe(.event_a, Context.handler, &ctx1);
    _ = try dispatcher.subscribe(.event_b, Context.handler, &ctx1);
    _ = try dispatcher.subscribe(.event_a, Context.handler, &ctx2);

    try std.testing.expectEqual(@as(usize, 3), dispatcher.getSubscriptionCount());

    const removed = dispatcher.unsubscribeContext(&ctx1);
    try std.testing.expectEqual(@as(usize, 2), removed);
    try std.testing.expectEqual(@as(usize, 1), dispatcher.getSubscriptionCount());

    try dispatcher.dispatch(.{ .event_a = .{} });
    try std.testing.expectEqual(@as(u32, 0), ctx1.call_count);
    try std.testing.expectEqual(@as(u32, 1), ctx2.call_count);
}

test "EventDispatcher - event queuing prevents recursion" {
    const TestEvent = union(enum) {
        start: struct {},
        middle: struct {},
        end: struct {},
    };

    const Context = struct {
        order: std.ArrayList(u8),
        dispatcher: *EventDispatcher(TestEvent),

        fn onStart(_: TestEvent, ctx: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            self.order.append(1) catch {};
            // Dispatch another event from within callback - should be queued
            self.dispatcher.dispatch(.{ .middle = .{} }) catch {};
        }

        fn onMiddle(_: TestEvent, ctx: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            self.order.append(2) catch {};
            self.dispatcher.dispatch(.{ .end = .{} }) catch {};
        }

        fn onEnd(_: TestEvent, ctx: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            self.order.append(3) catch {};
        }
    };

    var dispatcher = EventDispatcher(TestEvent).init(std.testing.allocator);
    defer dispatcher.deinit();

    var ctx = Context{
        .order = std.ArrayList(u8).init(std.testing.allocator),
        .dispatcher = &dispatcher,
    };
    defer ctx.order.deinit();

    _ = try dispatcher.subscribe(.start, Context.onStart, &ctx);
    _ = try dispatcher.subscribe(.middle, Context.onMiddle, &ctx);
    _ = try dispatcher.subscribe(.end, Context.onEnd, &ctx);

    try dispatcher.dispatch(.{ .start = .{} });

    // Events should be processed in order: 1, 2, 3
    try std.testing.expectEqual(@as(usize, 3), ctx.order.items.len);
    try std.testing.expectEqual(@as(u8, 1), ctx.order.items[0]);
    try std.testing.expectEqual(@as(u8, 2), ctx.order.items[1]);
    try std.testing.expectEqual(@as(u8, 3), ctx.order.items[2]);
}

test "EventDispatcher - queue and processQueue" {
    const TestEvent = union(enum) {
        event: struct { value: u32 },
    };

    const Context = struct {
        sum: u32 = 0,

        fn handler(event: TestEvent, ctx: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            switch (event) {
                .event => |data| self.sum += data.value,
            }
        }
    };

    var ctx = Context{};
    var dispatcher = EventDispatcher(TestEvent).init(std.testing.allocator);
    defer dispatcher.deinit();

    _ = try dispatcher.subscribe(.event, Context.handler, &ctx);

    // Queue events without processing
    try dispatcher.queue(.{ .event = .{ .value = 10 } });
    try dispatcher.queue(.{ .event = .{ .value = 20 } });
    try dispatcher.queue(.{ .event = .{ .value = 30 } });

    try std.testing.expectEqual(@as(usize, 3), dispatcher.getQueuedEventCount());
    try std.testing.expectEqual(@as(u32, 0), ctx.sum);

    // Process queued events
    dispatcher.processQueue();

    try std.testing.expectEqual(@as(usize, 0), dispatcher.getQueuedEventCount());
    try std.testing.expectEqual(@as(u32, 60), ctx.sum);
}

test "EventDispatcher - multiple subscribers same event" {
    const TestEvent = union(enum) {
        damage: struct { amount: u32 },
    };

    const Counter = struct {
        count: u32 = 0,

        fn handler(_: TestEvent, ctx: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            self.count += 1;
        }
    };

    var counter1 = Counter{};
    var counter2 = Counter{};
    var counter3 = Counter{};

    var dispatcher = EventDispatcher(TestEvent).init(std.testing.allocator);
    defer dispatcher.deinit();

    _ = try dispatcher.subscribe(.damage, Counter.handler, &counter1);
    _ = try dispatcher.subscribe(.damage, Counter.handler, &counter2);
    _ = try dispatcher.subscribe(.damage, Counter.handler, &counter3);

    try dispatcher.dispatch(.{ .damage = .{ .amount = 50 } });

    try std.testing.expectEqual(@as(u32, 1), counter1.count);
    try std.testing.expectEqual(@as(u32, 1), counter2.count);
    try std.testing.expectEqual(@as(u32, 1), counter3.count);
}

test "EventDispatcher - event filtering by type" {
    const TestEvent = union(enum) {
        attack: struct {},
        defend: struct {},
        heal: struct {},
    };

    const Context = struct {
        attacks: u32 = 0,
        defends: u32 = 0,
        heals: u32 = 0,

        fn onAttack(_: TestEvent, ctx: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            self.attacks += 1;
        }

        fn onDefend(_: TestEvent, ctx: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            self.defends += 1;
        }

        fn onHeal(_: TestEvent, ctx: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            self.heals += 1;
        }
    };

    var ctx = Context{};
    var dispatcher = EventDispatcher(TestEvent).init(std.testing.allocator);
    defer dispatcher.deinit();

    _ = try dispatcher.subscribe(.attack, Context.onAttack, &ctx);
    _ = try dispatcher.subscribe(.defend, Context.onDefend, &ctx);
    _ = try dispatcher.subscribe(.heal, Context.onHeal, &ctx);

    try dispatcher.dispatch(.{ .attack = .{} });
    try dispatcher.dispatch(.{ .attack = .{} });
    try dispatcher.dispatch(.{ .defend = .{} });
    try dispatcher.dispatch(.{ .heal = .{} });
    try dispatcher.dispatch(.{ .heal = .{} });
    try dispatcher.dispatch(.{ .heal = .{} });

    try std.testing.expectEqual(@as(u32, 2), ctx.attacks);
    try std.testing.expectEqual(@as(u32, 1), ctx.defends);
    try std.testing.expectEqual(@as(u32, 3), ctx.heals);
}

test "EventDispatcher - getSubscriptionCountFor" {
    const TestEvent = union(enum) {
        event_a: struct {},
        event_b: struct {},
    };

    const noop = struct {
        fn handler(_: TestEvent, _: ?*anyopaque) void {}
    }.handler;

    var dispatcher = EventDispatcher(TestEvent).init(std.testing.allocator);
    defer dispatcher.deinit();

    _ = try dispatcher.subscribe(.event_a, noop, null);
    _ = try dispatcher.subscribe(.event_a, noop, null);
    _ = try dispatcher.subscribe(.event_b, noop, null);
    _ = try dispatcher.subscribeAll(noop, null);

    // event_a has 2 direct + 1 all = 3
    try std.testing.expectEqual(@as(usize, 3), dispatcher.getSubscriptionCountFor(.event_a));
    // event_b has 1 direct + 1 all = 2
    try std.testing.expectEqual(@as(usize, 2), dispatcher.getSubscriptionCountFor(.event_b));
}

test "EventDispatcher - getStats" {
    const TestEvent = union(enum) {
        event: struct {},
    };

    const noop = struct {
        fn handler(_: TestEvent, _: ?*anyopaque) void {}
    }.handler;

    var dispatcher = EventDispatcher(TestEvent).init(std.testing.allocator);
    defer dispatcher.deinit();

    _ = try dispatcher.subscribe(.event, noop, null);
    _ = try dispatcher.subscribe(.event, noop, null);

    try dispatcher.dispatch(.{ .event = .{} });
    try dispatcher.queue(.{ .event = .{} });

    const stats = dispatcher.getStats();
    try std.testing.expectEqual(@as(usize, 2), stats.subscriptions);
    try std.testing.expectEqual(@as(usize, 1), stats.queued);
    try std.testing.expectEqual(@as(u64, 1), stats.events_dispatched);
    try std.testing.expectEqual(@as(u64, 1), stats.events_queued);
}

test "EventDispatcher - clearSubscriptions" {
    const TestEvent = union(enum) {
        event: struct {},
    };

    const noop = struct {
        fn handler(_: TestEvent, _: ?*anyopaque) void {}
    }.handler;

    var dispatcher = EventDispatcher(TestEvent).init(std.testing.allocator);
    defer dispatcher.deinit();

    _ = try dispatcher.subscribe(.event, noop, null);
    _ = try dispatcher.subscribe(.event, noop, null);
    _ = try dispatcher.subscribeAll(noop, null);

    try std.testing.expectEqual(@as(usize, 3), dispatcher.getSubscriptionCount());

    dispatcher.clearSubscriptions();

    try std.testing.expectEqual(@as(usize, 0), dispatcher.getSubscriptionCount());
}

test "EventDispatcher - clearQueue" {
    const TestEvent = union(enum) {
        event: struct {},
    };

    var dispatcher = EventDispatcher(TestEvent).init(std.testing.allocator);
    defer dispatcher.deinit();

    try dispatcher.queue(.{ .event = .{} });
    try dispatcher.queue(.{ .event = .{} });
    try dispatcher.queue(.{ .event = .{} });

    try std.testing.expectEqual(@as(usize, 3), dispatcher.getQueuedEventCount());

    dispatcher.clearQueue();

    try std.testing.expectEqual(@as(usize, 0), dispatcher.getQueuedEventCount());
}

test "EventDispatcher - null context" {
    const TestEvent = union(enum) {
        event: struct {},
    };

    const Global = struct {
        var was_called: bool = false;

        fn handler(_: TestEvent, _: ?*anyopaque) void {
            was_called = true;
        }
    };

    // Reset for test isolation
    Global.was_called = false;

    var dispatcher = EventDispatcher(TestEvent).init(std.testing.allocator);
    defer dispatcher.deinit();

    _ = try dispatcher.subscribe(.event, Global.handler, null);

    try dispatcher.dispatch(.{ .event = .{} });

    try std.testing.expect(Global.was_called);
}

test "EventDispatcher - unsubscribe non-existent handle" {
    const TestEvent = union(enum) {
        event: struct {},
    };

    var dispatcher = EventDispatcher(TestEvent).init(std.testing.allocator);
    defer dispatcher.deinit();

    // Should not crash, just log warning
    dispatcher.unsubscribe(.{ .id = 999, .event_tag = 0 });

    try std.testing.expectEqual(@as(usize, 0), dispatcher.getSubscriptionCount());
}

test "EventDispatcher - complex event data" {
    const Vec3 = struct { x: f32, y: f32, z: f32 };

    const TestEvent = union(enum) {
        position_changed: struct {
            entity_id: u32,
            old_pos: Vec3,
            new_pos: Vec3,
        },
        collision: struct {
            entity_a: u32,
            entity_b: u32,
            point: Vec3,
            normal: Vec3,
        },
    };

    const Context = struct {
        last_entity: u32 = 0,
        last_pos: Vec3 = .{ .x = 0, .y = 0, .z = 0 },

        fn onPositionChanged(event: TestEvent, ctx: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            switch (event) {
                .position_changed => |data| {
                    self.last_entity = data.entity_id;
                    self.last_pos = data.new_pos;
                },
                else => {},
            }
        }
    };

    var ctx = Context{};
    var dispatcher = EventDispatcher(TestEvent).init(std.testing.allocator);
    defer dispatcher.deinit();

    _ = try dispatcher.subscribe(.position_changed, Context.onPositionChanged, &ctx);

    try dispatcher.dispatch(.{
        .position_changed = .{
            .entity_id = 42,
            .old_pos = .{ .x = 0, .y = 0, .z = 0 },
            .new_pos = .{ .x = 10, .y = 20, .z = 30 },
        },
    });

    try std.testing.expectEqual(@as(u32, 42), ctx.last_entity);
    try std.testing.expectEqual(@as(f32, 10), ctx.last_pos.x);
    try std.testing.expectEqual(@as(f32, 20), ctx.last_pos.y);
    try std.testing.expectEqual(@as(f32, 30), ctx.last_pos.z);
}

test "EventDispatcher - config warn_no_subscribers" {
    const TestEvent = union(enum) {
        event: struct {},
    };

    // With warning disabled, should still work but not log
    var dispatcher = EventDispatcher(TestEvent).initWithConfig(std.testing.allocator, .{
        .warn_no_subscribers = false,
    });
    defer dispatcher.deinit();

    // Should not crash even with no subscribers
    try dispatcher.dispatch(.{ .event = .{} });

    try std.testing.expectEqual(@as(u64, 1), dispatcher.events_dispatched);
}
