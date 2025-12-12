const std = @import("std");
const Allocator = std.mem.Allocator;

/// Blackboard System - Type-safe key-value storage for AI communication
///
/// Provides cross-system communication without direct coupling:
/// - Generic value storage with type safety
/// - Resource reservations for multi-agent coordination
/// - Plan publication for intent broadcasting
/// - Decision history/audit logging
/// - Change notifications via subscriptions
///
/// Example usage:
/// ```zig
/// var bb = Blackboard.init(allocator);
/// defer bb.deinit();
///
/// // Store typed values
/// try bb.setInt("player_health", 100);
/// try bb.setFloat("threat_level", 0.75);
/// try bb.setVec2("target_pos", .{ 100.0, 200.0 });
///
/// // Retrieve with defaults
/// const health = bb.getIntOr("player_health", 0);
/// const pos = bb.getVec2Or("target_pos", .{ 0.0, 0.0 });
///
/// // Resource reservations
/// try bb.reserve("gold", 500, "build_barracks");
/// const available = bb.getAvailable("gold", 1000);
///
/// // Subscribe to changes
/// const sub_id = try bb.subscribe("threat_level", onThreatChanged, null);
/// defer bb.unsubscribe(sub_id);
/// ```

/// Maximum length for string values
pub const MAX_STRING_LENGTH: usize = 255;

/// Maximum length for keys
pub const MAX_KEY_LENGTH: usize = 63;

/// Vec2 type for 2D positions/vectors
pub const Vec2 = [2]f32;

/// Vec3 type for 3D positions/vectors
pub const Vec3 = [3]f32;

/// Value types supported by the blackboard
pub const ValueType = enum(u8) {
    int32,
    int64,
    float32,
    float64,
    boolean,
    string,
    pointer,
    vec2,
    vec3,
};

/// A blackboard value (tagged union)
pub const Value = union(ValueType) {
    int32: i32,
    int64: i64,
    float32: f32,
    float64: f64,
    boolean: bool,
    string: []const u8,
    pointer: ?*anyopaque,
    vec2: Vec2,
    vec3: Vec3,

    /// Convert to integer (with coercion)
    pub fn toInt(self: Value) i32 {
        return switch (self) {
            .int32 => |v| v,
            .int64 => |v| @intCast(@min(@max(v, std.math.minInt(i32)), std.math.maxInt(i32))),
            .float32 => |v| @intFromFloat(@min(@max(v, @as(f32, @floatFromInt(std.math.minInt(i32)))), @as(f32, @floatFromInt(std.math.maxInt(i32))))),
            .float64 => |v| @intFromFloat(@min(@max(v, @as(f64, @floatFromInt(std.math.minInt(i32)))), @as(f64, @floatFromInt(std.math.maxInt(i32))))),
            .boolean => |v| if (v) @as(i32, 1) else @as(i32, 0),
            .string => 0,
            .pointer => 0,
            .vec2 => 0,
            .vec3 => 0,
        };
    }

    /// Convert to float (with coercion)
    pub fn toFloat(self: Value) f32 {
        return switch (self) {
            .int32 => |v| @floatFromInt(v),
            .int64 => |v| @floatFromInt(v),
            .float32 => |v| v,
            .float64 => |v| @floatCast(v),
            .boolean => |v| if (v) @as(f32, 1.0) else @as(f32, 0.0),
            .string => 0.0,
            .pointer => 0.0,
            .vec2 => |v| v[0],
            .vec3 => |v| v[0],
        };
    }

    /// Convert to boolean
    pub fn toBool(self: Value) bool {
        return switch (self) {
            .int32 => |v| v != 0,
            .int64 => |v| v != 0,
            .float32 => |v| v != 0.0,
            .float64 => |v| v != 0.0,
            .boolean => |v| v,
            .string => |v| v.len > 0,
            .pointer => |v| v != null,
            .vec2 => |v| v[0] != 0.0 or v[1] != 0.0,
            .vec3 => |v| v[0] != 0.0 or v[1] != 0.0 or v[2] != 0.0,
        };
    }
};

/// A stored entry in the blackboard
const Entry = struct {
    key: [MAX_KEY_LENGTH + 1]u8,
    key_len: u8,
    value: Value,
    // For string values, we store the data inline
    string_storage: [MAX_STRING_LENGTH + 1]u8 = undefined,
    string_len: u8 = 0,

    fn getKey(self: *const Entry) []const u8 {
        return self.key[0..self.key_len];
    }

    fn getValue(self: *const Entry) Value {
        if (self.value == .string) {
            return .{ .string = self.string_storage[0..self.string_len] };
        }
        return self.value;
    }
};

/// Resource reservation for multi-agent coordination
pub const Reservation = struct {
    resource: [MAX_KEY_LENGTH + 1]u8,
    resource_len: u8,
    owner: [MAX_KEY_LENGTH + 1]u8,
    owner_len: u8,
    amount: i32,
    turns_remaining: i32, // -1 = permanent

    pub fn getResource(self: *const Reservation) []const u8 {
        return self.resource[0..self.resource_len];
    }

    pub fn getOwner(self: *const Reservation) []const u8 {
        return self.owner[0..self.owner_len];
    }
};

/// Published plan for intent broadcasting
pub const Plan = struct {
    owner: [MAX_KEY_LENGTH + 1]u8,
    owner_len: u8,
    description: [MAX_STRING_LENGTH + 1]u8,
    description_len: u8,
    target: [MAX_KEY_LENGTH + 1]u8,
    target_len: u8,
    turns_remaining: i32,
    active: bool,

    pub fn getOwner(self: *const Plan) []const u8 {
        return self.owner[0..self.owner_len];
    }

    pub fn getDescription(self: *const Plan) []const u8 {
        return self.description[0..self.description_len];
    }

    pub fn getTarget(self: *const Plan) []const u8 {
        return self.target[0..self.target_len];
    }
};

/// History entry for decision audit logging
pub const HistoryEntry = struct {
    text: [511]u8,
    text_len: u16,
    turn: i32,
    timestamp: i64,

    pub fn getText(self: *const HistoryEntry) []const u8 {
        return self.text[0..self.text_len];
    }
};

/// Subscription callback type
pub const SubscriptionCallback = *const fn (
    bb: *Blackboard,
    key: []const u8,
    old_value: ?Value,
    new_value: Value,
    userdata: ?*anyopaque,
) void;

/// Subscription handle
pub const SubscriptionHandle = u32;

/// Subscription entry
const Subscription = struct {
    id: SubscriptionHandle,
    key: [MAX_KEY_LENGTH + 1]u8,
    key_len: u8,
    is_wildcard: bool,
    callback: SubscriptionCallback,
    userdata: ?*anyopaque,

    fn getKey(self: *const Subscription) []const u8 {
        return self.key[0..self.key_len];
    }
};

/// Blackboard statistics
pub const BlackboardStats = struct {
    entry_count: usize,
    reservation_count: usize,
    plan_count: usize,
    history_count: usize,
    subscription_count: usize,
};

/// Type-safe key-value storage for AI communication
pub const Blackboard = struct {
    allocator: Allocator,

    // Key-value storage
    entries: std.ArrayList(Entry),

    // Resource reservations
    reservations: std.ArrayList(Reservation),

    // Published plans
    plans: std.ArrayList(Plan),

    // Decision history (circular buffer)
    history: std.ArrayList(HistoryEntry),
    max_history: usize,

    // Change subscriptions
    subscriptions: std.ArrayList(Subscription),
    next_subscription_id: SubscriptionHandle,

    // Current turn for history logging
    current_turn: i32,

    /// Configuration options
    pub const Config = struct {
        initial_entry_capacity: usize = 64,
        initial_reservation_capacity: usize = 16,
        initial_plan_capacity: usize = 16,
        max_history: usize = 256,
        initial_subscription_capacity: usize = 16,
    };

    /// Initialize blackboard with default configuration
    pub fn init(allocator: Allocator) Blackboard {
        return initWithConfig(allocator, .{});
    }

    /// Initialize blackboard with custom configuration
    pub fn initWithConfig(allocator: Allocator, config: Config) Blackboard {
        return .{
            .allocator = allocator,
            .entries = std.ArrayList(Entry).initCapacity(allocator, config.initial_entry_capacity) catch std.ArrayList(Entry).init(allocator),
            .reservations = std.ArrayList(Reservation).initCapacity(allocator, config.initial_reservation_capacity) catch std.ArrayList(Reservation).init(allocator),
            .plans = std.ArrayList(Plan).initCapacity(allocator, config.initial_plan_capacity) catch std.ArrayList(Plan).init(allocator),
            .history = std.ArrayList(HistoryEntry).initCapacity(allocator, config.max_history) catch std.ArrayList(HistoryEntry).init(allocator),
            .max_history = config.max_history,
            .subscriptions = std.ArrayList(Subscription).initCapacity(allocator, config.initial_subscription_capacity) catch std.ArrayList(Subscription).init(allocator),
            .next_subscription_id = 1,
            .current_turn = 0,
        };
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Blackboard) void {
        self.entries.deinit();
        self.reservations.deinit();
        self.plans.deinit();
        self.history.deinit();
        self.subscriptions.deinit();
    }

    // ============================================================
    // Key-Value Storage
    // ============================================================

    /// Find entry index by key
    fn findEntry(self: *const Blackboard, key: []const u8) ?usize {
        for (self.entries.items, 0..) |*entry, i| {
            if (std.mem.eql(u8, entry.getKey(), key)) {
                return i;
            }
        }
        return null;
    }

    /// Set a value, notifying subscribers of changes
    fn setValue(self: *Blackboard, key: []const u8, value: Value) !void {
        if (key.len > MAX_KEY_LENGTH) return error.KeyTooLong;

        const old_value: ?Value = if (self.findEntry(key)) |idx|
            self.entries.items[idx].getValue()
        else
            null;

        if (self.findEntry(key)) |idx| {
            // Update existing
            var entry = &self.entries.items[idx];
            if (value == .string) {
                const str = value.string;
                if (str.len > MAX_STRING_LENGTH) return error.StringTooLong;
                @memcpy(entry.string_storage[0..str.len], str);
                entry.string_len = @intCast(str.len);
                entry.value = .{ .string = undefined };
            } else {
                entry.value = value;
            }
        } else {
            // Create new entry
            var entry: Entry = undefined;
            @memcpy(entry.key[0..key.len], key);
            entry.key_len = @intCast(key.len);

            if (value == .string) {
                const str = value.string;
                if (str.len > MAX_STRING_LENGTH) return error.StringTooLong;
                @memcpy(entry.string_storage[0..str.len], str);
                entry.string_len = @intCast(str.len);
                entry.value = .{ .string = undefined };
            } else {
                entry.value = value;
            }

            try self.entries.append(entry);
        }

        // Notify subscribers
        self.notifySubscribers(key, old_value, value);
    }

    /// Get a value by key
    pub fn get(self: *const Blackboard, key: []const u8) ?Value {
        if (self.findEntry(key)) |idx| {
            return self.entries.items[idx].getValue();
        }
        return null;
    }

    /// Check if key exists
    pub fn has(self: *const Blackboard, key: []const u8) bool {
        return self.findEntry(key) != null;
    }

    /// Remove a key-value pair
    pub fn remove(self: *Blackboard, key: []const u8) bool {
        if (self.findEntry(key)) |idx| {
            _ = self.entries.swapRemove(idx);
            return true;
        }
        return false;
    }

    /// Clear all entries
    pub fn clear(self: *Blackboard) void {
        self.entries.clearRetainingCapacity();
    }

    /// Get number of entries
    pub fn count(self: *const Blackboard) usize {
        return self.entries.items.len;
    }

    // Type-specific setters

    pub fn setInt(self: *Blackboard, key: []const u8, value: i32) !void {
        try self.setValue(key, .{ .int32 = value });
    }

    pub fn setInt64(self: *Blackboard, key: []const u8, value: i64) !void {
        try self.setValue(key, .{ .int64 = value });
    }

    pub fn setFloat(self: *Blackboard, key: []const u8, value: f32) !void {
        try self.setValue(key, .{ .float32 = value });
    }

    pub fn setFloat64(self: *Blackboard, key: []const u8, value: f64) !void {
        try self.setValue(key, .{ .float64 = value });
    }

    pub fn setBool(self: *Blackboard, key: []const u8, value: bool) !void {
        try self.setValue(key, .{ .boolean = value });
    }

    pub fn setString(self: *Blackboard, key: []const u8, value: []const u8) !void {
        try self.setValue(key, .{ .string = value });
    }

    pub fn setPointer(self: *Blackboard, key: []const u8, value: ?*anyopaque) !void {
        try self.setValue(key, .{ .pointer = value });
    }

    pub fn setVec2(self: *Blackboard, key: []const u8, value: Vec2) !void {
        try self.setValue(key, .{ .vec2 = value });
    }

    pub fn setVec3(self: *Blackboard, key: []const u8, value: Vec3) !void {
        try self.setValue(key, .{ .vec3 = value });
    }

    // Type-specific getters

    pub fn getInt(self: *const Blackboard, key: []const u8) ?i32 {
        if (self.get(key)) |v| return v.toInt();
        return null;
    }

    pub fn getIntOr(self: *const Blackboard, key: []const u8, default: i32) i32 {
        return self.getInt(key) orelse default;
    }

    pub fn getInt64(self: *const Blackboard, key: []const u8) ?i64 {
        if (self.get(key)) |v| {
            return switch (v) {
                .int64 => |val| val,
                .int32 => |val| val,
                else => null,
            };
        }
        return null;
    }

    pub fn getInt64Or(self: *const Blackboard, key: []const u8, default: i64) i64 {
        return self.getInt64(key) orelse default;
    }

    pub fn getFloat(self: *const Blackboard, key: []const u8) ?f32 {
        if (self.get(key)) |v| return v.toFloat();
        return null;
    }

    pub fn getFloatOr(self: *const Blackboard, key: []const u8, default: f32) f32 {
        return self.getFloat(key) orelse default;
    }

    pub fn getFloat64(self: *const Blackboard, key: []const u8) ?f64 {
        if (self.get(key)) |v| {
            return switch (v) {
                .float64 => |val| val,
                .float32 => |val| val,
                else => null,
            };
        }
        return null;
    }

    pub fn getFloat64Or(self: *const Blackboard, key: []const u8, default: f64) f64 {
        return self.getFloat64(key) orelse default;
    }

    pub fn getBool(self: *const Blackboard, key: []const u8) ?bool {
        if (self.get(key)) |v| return v.toBool();
        return null;
    }

    pub fn getBoolOr(self: *const Blackboard, key: []const u8, default: bool) bool {
        return self.getBool(key) orelse default;
    }

    pub fn getString(self: *const Blackboard, key: []const u8) ?[]const u8 {
        if (self.get(key)) |v| {
            return switch (v) {
                .string => |s| s,
                else => null,
            };
        }
        return null;
    }

    pub fn getStringOr(self: *const Blackboard, key: []const u8, default: []const u8) []const u8 {
        return self.getString(key) orelse default;
    }

    pub fn getPointer(self: *const Blackboard, key: []const u8) ?*anyopaque {
        if (self.get(key)) |v| {
            return switch (v) {
                .pointer => |p| p,
                else => null,
            };
        }
        return null;
    }

    pub fn getVec2(self: *const Blackboard, key: []const u8) ?Vec2 {
        if (self.get(key)) |v| {
            return switch (v) {
                .vec2 => |vec| vec,
                else => null,
            };
        }
        return null;
    }

    pub fn getVec2Or(self: *const Blackboard, key: []const u8, default: Vec2) Vec2 {
        return self.getVec2(key) orelse default;
    }

    pub fn getVec3(self: *const Blackboard, key: []const u8) ?Vec3 {
        if (self.get(key)) |v| {
            return switch (v) {
                .vec3 => |vec| vec,
                else => null,
            };
        }
        return null;
    }

    pub fn getVec3Or(self: *const Blackboard, key: []const u8, default: Vec3) Vec3 {
        return self.getVec3(key) orelse default;
    }

    /// Get all keys
    pub fn getKeys(self: *const Blackboard, allocator: Allocator) ![][]const u8 {
        var keys = try allocator.alloc([]const u8, self.entries.items.len);
        for (self.entries.items, 0..) |*entry, i| {
            keys[i] = entry.getKey();
        }
        return keys;
    }

    // ============================================================
    // Resource Reservations
    // ============================================================

    /// Find reservation by resource and owner
    fn findReservation(self: *const Blackboard, resource: []const u8, owner: []const u8) ?usize {
        for (self.reservations.items, 0..) |*res, i| {
            if (std.mem.eql(u8, res.getResource(), resource) and
                std.mem.eql(u8, res.getOwner(), owner))
            {
                return i;
            }
        }
        return null;
    }

    /// Reserve a resource amount
    pub fn reserve(self: *Blackboard, resource: []const u8, amount: i32, owner: []const u8) !void {
        try self.reserveEx(resource, amount, owner, -1);
    }

    /// Reserve a resource amount with expiration
    pub fn reserveEx(self: *Blackboard, resource: []const u8, amount: i32, owner: []const u8, turns: i32) !void {
        if (resource.len > MAX_KEY_LENGTH) return error.KeyTooLong;
        if (owner.len > MAX_KEY_LENGTH) return error.KeyTooLong;

        if (self.findReservation(resource, owner)) |idx| {
            // Update existing reservation
            self.reservations.items[idx].amount = amount;
            self.reservations.items[idx].turns_remaining = turns;
        } else {
            // Create new reservation
            var res: Reservation = undefined;
            @memcpy(res.resource[0..resource.len], resource);
            res.resource_len = @intCast(resource.len);
            @memcpy(res.owner[0..owner.len], owner);
            res.owner_len = @intCast(owner.len);
            res.amount = amount;
            res.turns_remaining = turns;
            try self.reservations.append(res);
        }
    }

    /// Release a specific reservation
    pub fn release(self: *Blackboard, resource: []const u8, owner: []const u8) bool {
        if (self.findReservation(resource, owner)) |idx| {
            _ = self.reservations.swapRemove(idx);
            return true;
        }
        return false;
    }

    /// Release all reservations by owner
    pub fn releaseAll(self: *Blackboard, owner: []const u8) usize {
        var removed: usize = 0;
        var i: usize = 0;
        while (i < self.reservations.items.len) {
            if (std.mem.eql(u8, self.reservations.items[i].getOwner(), owner)) {
                _ = self.reservations.swapRemove(i);
                removed += 1;
            } else {
                i += 1;
            }
        }
        return removed;
    }

    /// Get total reserved amount for a resource
    pub fn getReserved(self: *const Blackboard, resource: []const u8) i32 {
        var total: i32 = 0;
        for (self.reservations.items) |*res| {
            if (std.mem.eql(u8, res.getResource(), resource)) {
                total += res.amount;
            }
        }
        return total;
    }

    /// Get available amount (total - reserved)
    pub fn getAvailable(self: *const Blackboard, resource: []const u8, total: i32) i32 {
        return total - self.getReserved(resource);
    }

    /// Check if any reservation exists for resource
    pub fn hasReservation(self: *const Blackboard, resource: []const u8) bool {
        for (self.reservations.items) |*res| {
            if (std.mem.eql(u8, res.getResource(), resource)) {
                return true;
            }
        }
        return false;
    }

    /// Get reservation amount by specific owner
    pub fn getReservation(self: *const Blackboard, resource: []const u8, owner: []const u8) i32 {
        if (self.findReservation(resource, owner)) |idx| {
            return self.reservations.items[idx].amount;
        }
        return 0;
    }

    // ============================================================
    // Plan Publication
    // ============================================================

    /// Find plan by owner
    fn findPlan(self: *const Blackboard, owner: []const u8) ?usize {
        for (self.plans.items, 0..) |*plan, i| {
            if (plan.active and std.mem.eql(u8, plan.getOwner(), owner)) {
                return i;
            }
        }
        return null;
    }

    /// Publish a plan
    pub fn publishPlan(self: *Blackboard, owner: []const u8, description: []const u8) !void {
        try self.publishPlanEx(owner, description, "", -1);
    }

    /// Publish a plan with target and duration
    pub fn publishPlanEx(self: *Blackboard, owner: []const u8, description: []const u8, target: []const u8, turns: i32) !void {
        if (owner.len > MAX_KEY_LENGTH) return error.KeyTooLong;
        if (description.len > MAX_STRING_LENGTH) return error.StringTooLong;
        if (target.len > MAX_KEY_LENGTH) return error.KeyTooLong;

        // Cancel existing plan from this owner
        _ = self.cancelPlan(owner);

        var plan: Plan = undefined;
        @memcpy(plan.owner[0..owner.len], owner);
        plan.owner_len = @intCast(owner.len);
        @memcpy(plan.description[0..description.len], description);
        plan.description_len = @intCast(description.len);
        @memcpy(plan.target[0..target.len], target);
        plan.target_len = @intCast(target.len);
        plan.turns_remaining = turns;
        plan.active = true;

        try self.plans.append(plan);
    }

    /// Cancel a plan by owner
    pub fn cancelPlan(self: *Blackboard, owner: []const u8) bool {
        if (self.findPlan(owner)) |idx| {
            self.plans.items[idx].active = false;
            return true;
        }
        return false;
    }

    /// Check if there's a conflicting plan targeting the same entity
    pub fn hasConflictingPlan(self: *const Blackboard, target: []const u8) bool {
        for (self.plans.items) |*plan| {
            if (plan.active and std.mem.eql(u8, plan.getTarget(), target)) {
                return true;
            }
        }
        return false;
    }

    /// Get plan by owner
    pub fn getPlan(self: *const Blackboard, owner: []const u8) ?*const Plan {
        if (self.findPlan(owner)) |idx| {
            return &self.plans.items[idx];
        }
        return null;
    }

    /// Get all active plans
    pub fn getActivePlans(self: *const Blackboard, allocator: Allocator) ![]const Plan {
        var active = std.ArrayList(Plan).init(allocator);
        errdefer active.deinit();

        for (self.plans.items) |*plan| {
            if (plan.active) {
                try active.append(plan.*);
            }
        }

        return active.toOwnedSlice();
    }

    // ============================================================
    // Decision History
    // ============================================================

    /// Log a decision with current turn
    pub fn log(self: *Blackboard, comptime fmt: []const u8, args: anytype) void {
        self.logTurn(self.current_turn, fmt, args);
    }

    /// Log a decision with explicit turn
    pub fn logTurn(self: *Blackboard, turn: i32, comptime fmt: []const u8, args: anytype) void {
        var entry: HistoryEntry = undefined;
        entry.turn = turn;
        entry.timestamp = std.time.milliTimestamp();

        const result = std.fmt.bufPrint(&entry.text, fmt, args) catch |err| {
            if (err == error.NoSpaceLeft) {
                entry.text_len = @intCast(entry.text.len);
            } else {
                return;
            }
            self.addHistoryEntry(entry);
            return;
        };
        entry.text_len = @intCast(result.len);
        self.addHistoryEntry(entry);
    }

    fn addHistoryEntry(self: *Blackboard, entry: HistoryEntry) void {
        if (self.history.items.len >= self.max_history) {
            // Remove oldest (circular buffer behavior)
            _ = self.history.orderedRemove(0);
        }
        self.history.append(entry) catch {};
    }

    /// Get history entries (newest first)
    pub fn getHistory(self: *const Blackboard, allocator: Allocator, max: usize) ![]HistoryEntry {
        const result_count = @min(max, self.history.items.len);
        var result = try allocator.alloc(HistoryEntry, result_count);

        // Copy in reverse order (newest first)
        for (0..result_count) |i| {
            result[i] = self.history.items[self.history.items.len - 1 - i];
        }

        return result;
    }

    /// Get history count
    pub fn getHistoryCount(self: *const Blackboard) usize {
        return self.history.items.len;
    }

    /// Clear history
    pub fn clearHistory(self: *Blackboard) void {
        self.history.clearRetainingCapacity();
    }

    /// Set current turn
    pub fn setTurn(self: *Blackboard, turn: i32) void {
        self.current_turn = turn;
    }

    /// Get current turn
    pub fn getTurn(self: *const Blackboard) i32 {
        return self.current_turn;
    }

    // ============================================================
    // Change Subscriptions
    // ============================================================

    /// Subscribe to changes on a specific key
    pub fn subscribe(self: *Blackboard, key: []const u8, callback: SubscriptionCallback, userdata: ?*anyopaque) !SubscriptionHandle {
        if (key.len > MAX_KEY_LENGTH) return error.KeyTooLong;

        const id = self.next_subscription_id;
        self.next_subscription_id += 1;

        var sub: Subscription = undefined;
        sub.id = id;
        @memcpy(sub.key[0..key.len], key);
        sub.key_len = @intCast(key.len);
        sub.is_wildcard = false;
        sub.callback = callback;
        sub.userdata = userdata;

        try self.subscriptions.append(sub);
        return id;
    }

    /// Subscribe to all key changes (wildcard)
    pub fn subscribeAll(self: *Blackboard, callback: SubscriptionCallback, userdata: ?*anyopaque) !SubscriptionHandle {
        const id = self.next_subscription_id;
        self.next_subscription_id += 1;

        var sub: Subscription = undefined;
        sub.id = id;
        sub.key_len = 0;
        sub.is_wildcard = true;
        sub.callback = callback;
        sub.userdata = userdata;

        try self.subscriptions.append(sub);
        return id;
    }

    /// Unsubscribe by handle
    pub fn unsubscribe(self: *Blackboard, handle: SubscriptionHandle) bool {
        for (self.subscriptions.items, 0..) |*sub, i| {
            if (sub.id == handle) {
                _ = self.subscriptions.swapRemove(i);
                return true;
            }
        }
        return false;
    }

    /// Notify subscribers of a change
    fn notifySubscribers(self: *Blackboard, key: []const u8, old_value: ?Value, new_value: Value) void {
        for (self.subscriptions.items) |*sub| {
            if (sub.is_wildcard or std.mem.eql(u8, sub.getKey(), key)) {
                sub.callback(self, key, old_value, new_value, sub.userdata);
            }
        }
    }

    // ============================================================
    // Update / Maintenance
    // ============================================================

    /// Update blackboard (expire reservations and plans)
    pub fn update(self: *Blackboard) void {
        // Expire reservations
        var i: usize = 0;
        while (i < self.reservations.items.len) {
            var res = &self.reservations.items[i];
            if (res.turns_remaining > 0) {
                res.turns_remaining -= 1;
                if (res.turns_remaining == 0) {
                    _ = self.reservations.swapRemove(i);
                    continue;
                }
            }
            i += 1;
        }

        // Expire plans
        i = 0;
        while (i < self.plans.items.len) {
            var plan = &self.plans.items[i];
            if (plan.active and plan.turns_remaining > 0) {
                plan.turns_remaining -= 1;
                if (plan.turns_remaining == 0) {
                    plan.active = false;
                }
            }
            i += 1;
        }

        // Clean up inactive plans
        i = 0;
        while (i < self.plans.items.len) {
            if (!self.plans.items[i].active) {
                _ = self.plans.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Get statistics
    pub fn getStats(self: *const Blackboard) BlackboardStats {
        var active_plans: usize = 0;
        for (self.plans.items) |*plan| {
            if (plan.active) active_plans += 1;
        }

        return .{
            .entry_count = self.entries.items.len,
            .reservation_count = self.reservations.items.len,
            .plan_count = active_plans,
            .history_count = self.history.items.len,
            .subscription_count = self.subscriptions.items.len,
        };
    }

    /// Copy all entries from another blackboard
    pub fn copy(self: *Blackboard, source: *const Blackboard) !void {
        self.clear();

        for (source.entries.items) |*entry| {
            try self.entries.append(entry.*);
        }
    }

    /// Merge entries from another blackboard (overwrites existing keys)
    pub fn merge(self: *Blackboard, source: *const Blackboard) !void {
        for (source.entries.items) |*entry| {
            const key = entry.getKey();
            const value = entry.getValue();
            try self.setValue(key, value);
        }
    }
};

// ============================================================
// Tests
// ============================================================

test "Blackboard: basic value storage" {
    const allocator = std.testing.allocator;
    var bb = Blackboard.init(allocator);
    defer bb.deinit();

    // Test int
    try bb.setInt("health", 100);
    try std.testing.expectEqual(@as(i32, 100), bb.getIntOr("health", 0));

    // Test float
    try bb.setFloat("threat", 0.75);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), bb.getFloatOr("threat", 0.0), 0.001);

    // Test bool
    try bb.setBool("is_enemy", true);
    try std.testing.expectEqual(true, bb.getBoolOr("is_enemy", false));

    // Test string
    try bb.setString("name", "Guard");
    try std.testing.expectEqualStrings("Guard", bb.getStringOr("name", ""));

    // Test vec2
    try bb.setVec2("position", .{ 100.0, 200.0 });
    const pos = bb.getVec2Or("position", .{ 0.0, 0.0 });
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), pos[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 200.0), pos[1], 0.001);

    try std.testing.expectEqual(@as(usize, 5), bb.count());
}

test "Blackboard: value updates" {
    const allocator = std.testing.allocator;
    var bb = Blackboard.init(allocator);
    defer bb.deinit();

    try bb.setInt("counter", 1);
    try std.testing.expectEqual(@as(i32, 1), bb.getIntOr("counter", 0));

    try bb.setInt("counter", 2);
    try std.testing.expectEqual(@as(i32, 2), bb.getIntOr("counter", 0));
    try std.testing.expectEqual(@as(usize, 1), bb.count()); // Still only 1 entry
}

test "Blackboard: has and remove" {
    const allocator = std.testing.allocator;
    var bb = Blackboard.init(allocator);
    defer bb.deinit();

    try bb.setInt("test", 42);
    try std.testing.expect(bb.has("test"));
    try std.testing.expect(!bb.has("nonexistent"));

    try std.testing.expect(bb.remove("test"));
    try std.testing.expect(!bb.has("test"));
    try std.testing.expect(!bb.remove("test")); // Already removed
}

test "Blackboard: type coercion" {
    const allocator = std.testing.allocator;
    var bb = Blackboard.init(allocator);
    defer bb.deinit();

    // Int to float
    try bb.setInt("value", 42);
    try std.testing.expectApproxEqAbs(@as(f32, 42.0), bb.getFloatOr("value", 0.0), 0.001);

    // Float to int
    try bb.setFloat("value", 3.7);
    try std.testing.expectEqual(@as(i32, 3), bb.getIntOr("value", 0));

    // Bool from int
    try bb.setInt("flag", 1);
    try std.testing.expect(bb.getBoolOr("flag", false));

    try bb.setInt("flag", 0);
    try std.testing.expect(!bb.getBoolOr("flag", true));
}

test "Blackboard: reservations" {
    const allocator = std.testing.allocator;
    var bb = Blackboard.init(allocator);
    defer bb.deinit();

    // Make reservations
    try bb.reserve("gold", 500, "build_barracks");
    try bb.reserve("gold", 200, "train_soldier");

    try std.testing.expectEqual(@as(i32, 700), bb.getReserved("gold"));
    try std.testing.expectEqual(@as(i32, 300), bb.getAvailable("gold", 1000));

    try std.testing.expectEqual(@as(i32, 500), bb.getReservation("gold", "build_barracks"));
    try std.testing.expectEqual(@as(i32, 200), bb.getReservation("gold", "train_soldier"));

    // Release one
    try std.testing.expect(bb.release("gold", "build_barracks"));
    try std.testing.expectEqual(@as(i32, 200), bb.getReserved("gold"));
}

test "Blackboard: reservation expiration" {
    const allocator = std.testing.allocator;
    var bb = Blackboard.init(allocator);
    defer bb.deinit();

    try bb.reserveEx("iron", 100, "builder", 2); // Expires in 2 turns

    try std.testing.expectEqual(@as(i32, 100), bb.getReserved("iron"));

    bb.update(); // Turn 1
    try std.testing.expectEqual(@as(i32, 100), bb.getReserved("iron"));

    bb.update(); // Turn 2 - expires
    try std.testing.expectEqual(@as(i32, 0), bb.getReserved("iron"));
}

test "Blackboard: plans" {
    const allocator = std.testing.allocator;
    var bb = Blackboard.init(allocator);
    defer bb.deinit();

    try bb.publishPlanEx("army1", "Attack enemy base", "enemy_base", 3);

    try std.testing.expect(bb.hasConflictingPlan("enemy_base"));
    try std.testing.expect(!bb.hasConflictingPlan("other_target"));

    const plan = bb.getPlan("army1").?;
    try std.testing.expectEqualStrings("Attack enemy base", plan.getDescription());
    try std.testing.expectEqualStrings("enemy_base", plan.getTarget());

    // Cancel plan
    try std.testing.expect(bb.cancelPlan("army1"));
    try std.testing.expect(!bb.hasConflictingPlan("enemy_base"));
}

test "Blackboard: history logging" {
    const allocator = std.testing.allocator;
    var bb = Blackboard.init(allocator);
    defer bb.deinit();

    bb.setTurn(1);
    bb.log("Decision: {s} with value {d}", .{ "attack", 42 });

    bb.setTurn(2);
    bb.log("Decision: {s}", .{"defend"});

    const history = try bb.getHistory(allocator, 10);
    defer allocator.free(history);

    try std.testing.expectEqual(@as(usize, 2), history.len);
    // Newest first
    try std.testing.expectEqual(@as(i32, 2), history[0].turn);
    try std.testing.expectEqual(@as(i32, 1), history[1].turn);
}

test "Blackboard: subscriptions" {
    const allocator = std.testing.allocator;
    var bb = Blackboard.init(allocator);
    defer bb.deinit();

    var callback_count: usize = 0;
    const callback = struct {
        fn cb(_: *Blackboard, _: []const u8, _: ?Value, _: Value, userdata: ?*anyopaque) void {
            const count: *usize = @ptrCast(@alignCast(userdata.?));
            count.* += 1;
        }
    }.cb;

    const handle = try bb.subscribe("watched_key", callback, &callback_count);

    try bb.setInt("watched_key", 1);
    try std.testing.expectEqual(@as(usize, 1), callback_count);

    try bb.setInt("watched_key", 2);
    try std.testing.expectEqual(@as(usize, 2), callback_count);

    try bb.setInt("other_key", 3);
    try std.testing.expectEqual(@as(usize, 2), callback_count); // Not watched

    try std.testing.expect(bb.unsubscribe(handle));

    try bb.setInt("watched_key", 3);
    try std.testing.expectEqual(@as(usize, 2), callback_count); // Unsubscribed
}

test "Blackboard: wildcard subscription" {
    const allocator = std.testing.allocator;
    var bb = Blackboard.init(allocator);
    defer bb.deinit();

    var callback_count: usize = 0;
    const callback = struct {
        fn cb(_: *Blackboard, _: []const u8, _: ?Value, _: Value, userdata: ?*anyopaque) void {
            const count: *usize = @ptrCast(@alignCast(userdata.?));
            count.* += 1;
        }
    }.cb;

    _ = try bb.subscribeAll(callback, &callback_count);

    try bb.setInt("key1", 1);
    try bb.setInt("key2", 2);
    try bb.setFloat("key3", 3.0);

    try std.testing.expectEqual(@as(usize, 3), callback_count);
}

test "Blackboard: copy and merge" {
    const allocator = std.testing.allocator;
    var bb1 = Blackboard.init(allocator);
    defer bb1.deinit();

    var bb2 = Blackboard.init(allocator);
    defer bb2.deinit();

    try bb1.setInt("a", 1);
    try bb1.setInt("b", 2);

    try bb2.copy(&bb1);
    try std.testing.expectEqual(@as(i32, 1), bb2.getIntOr("a", 0));
    try std.testing.expectEqual(@as(i32, 2), bb2.getIntOr("b", 0));

    // Merge with overwrites
    try bb1.setInt("a", 10);
    try bb1.setInt("c", 3);

    try bb2.merge(&bb1);
    try std.testing.expectEqual(@as(i32, 10), bb2.getIntOr("a", 0)); // Overwritten
    try std.testing.expectEqual(@as(i32, 2), bb2.getIntOr("b", 0)); // Unchanged
    try std.testing.expectEqual(@as(i32, 3), bb2.getIntOr("c", 0)); // Added
}

test "Blackboard: stats" {
    const allocator = std.testing.allocator;
    var bb = Blackboard.init(allocator);
    defer bb.deinit();

    try bb.setInt("a", 1);
    try bb.setInt("b", 2);
    try bb.reserve("gold", 100, "test");
    try bb.publishPlan("ai1", "test plan");
    bb.log("test log", .{});
    _ = try bb.subscribe("a", struct {
        fn cb(_: *Blackboard, _: []const u8, _: ?Value, _: Value, _: ?*anyopaque) void {}
    }.cb, null);

    const stats = bb.getStats();
    try std.testing.expectEqual(@as(usize, 2), stats.entry_count);
    try std.testing.expectEqual(@as(usize, 1), stats.reservation_count);
    try std.testing.expectEqual(@as(usize, 1), stats.plan_count);
    try std.testing.expectEqual(@as(usize, 1), stats.history_count);
    try std.testing.expectEqual(@as(usize, 1), stats.subscription_count);
}

test "Blackboard: getKeys" {
    const allocator = std.testing.allocator;
    var bb = Blackboard.init(allocator);
    defer bb.deinit();

    try bb.setInt("alpha", 1);
    try bb.setInt("beta", 2);
    try bb.setInt("gamma", 3);

    const keys = try bb.getKeys(allocator);
    defer allocator.free(keys);

    try std.testing.expectEqual(@as(usize, 3), keys.len);
}

test "Blackboard: releaseAll" {
    const allocator = std.testing.allocator;
    var bb = Blackboard.init(allocator);
    defer bb.deinit();

    try bb.reserve("gold", 100, "builder1");
    try bb.reserve("iron", 50, "builder1");
    try bb.reserve("gold", 200, "builder2");

    try std.testing.expectEqual(@as(i32, 300), bb.getReserved("gold"));

    const removed = bb.releaseAll("builder1");
    try std.testing.expectEqual(@as(usize, 2), removed);
    try std.testing.expectEqual(@as(i32, 200), bb.getReserved("gold"));
    try std.testing.expectEqual(@as(i32, 0), bb.getReserved("iron"));
}

test "Blackboard: int64 and float64" {
    const allocator = std.testing.allocator;
    var bb = Blackboard.init(allocator);
    defer bb.deinit();

    try bb.setInt64("big_number", 9_000_000_000_000);
    try std.testing.expectEqual(@as(i64, 9_000_000_000_000), bb.getInt64Or("big_number", 0));

    try bb.setFloat64("precise", 3.141592653589793);
    try std.testing.expectApproxEqAbs(@as(f64, 3.141592653589793), bb.getFloat64Or("precise", 0.0), 0.0000001);
}

test "Blackboard: vec3" {
    const allocator = std.testing.allocator;
    var bb = Blackboard.init(allocator);
    defer bb.deinit();

    try bb.setVec3("position3d", .{ 1.0, 2.0, 3.0 });
    const pos = bb.getVec3Or("position3d", .{ 0.0, 0.0, 0.0 });
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), pos[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), pos[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), pos[2], 0.001);
}

test "Blackboard: pointer storage" {
    const allocator = std.testing.allocator;
    var bb = Blackboard.init(allocator);
    defer bb.deinit();

    var data: i32 = 42;
    try bb.setPointer("entity_ref", &data);

    const ptr = bb.getPointer("entity_ref");
    try std.testing.expect(ptr != null);

    const retrieved: *i32 = @ptrCast(@alignCast(ptr.?));
    try std.testing.expectEqual(@as(i32, 42), retrieved.*);
}

test "Blackboard: key too long error" {
    const allocator = std.testing.allocator;
    var bb = Blackboard.init(allocator);
    defer bb.deinit();

    const long_key = "a" ** 100; // 100 characters, exceeds MAX_KEY_LENGTH
    try std.testing.expectError(error.KeyTooLong, bb.setInt(long_key, 1));
}

test "Blackboard: string too long error" {
    const allocator = std.testing.allocator;
    var bb = Blackboard.init(allocator);
    defer bb.deinit();

    const long_string = "a" ** 300; // 300 characters, exceeds MAX_STRING_LENGTH
    try std.testing.expectError(error.StringTooLong, bb.setString("key", long_string));
}
