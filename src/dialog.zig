const std = @import("std");
const Allocator = std.mem.Allocator;

/// Dialog System - Branching conversation trees with conditional responses
///
/// Provides a complete dialog system for RPG/adventure games:
/// - Dialog tree structure with nodes and options
/// - Branching conversations with multiple paths
/// - Conditional responses based on game state
/// - Dialog state tracking and history
/// - Event callbacks for scripting
///
/// Example usage:
/// ```zig
/// var dialog = DialogSystem.init(allocator);
/// defer dialog.deinit();
///
/// // Define dialog nodes
/// const greeting = try dialog.addNode(.{
///     .id = "greeting",
///     .speaker = "Merchant",
///     .text = "Welcome to my shop! What can I help you with?",
/// });
///
/// // Add options with conditions
/// try dialog.addOption(greeting, .{
///     .text = "Show me your weapons.",
///     .next_node = "weapons_menu",
/// });
///
/// try dialog.addOption(greeting, .{
///     .text = "I have a special item to sell. [Requires: rare_item]",
///     .next_node = "rare_sale",
///     .condition = .{ .has_flag = "rare_item" },
/// });
///
/// // Start conversation
/// try dialog.start("greeting");
/// const current = dialog.getCurrentNode();
/// const options = dialog.getAvailableOptions(&game_state);
/// try dialog.selectOption(0);
/// ```

/// Maximum lengths for strings
pub const MAX_ID_LENGTH: usize = 63;
pub const MAX_TEXT_LENGTH: usize = 1023;
pub const MAX_SPEAKER_LENGTH: usize = 63;

/// Condition operators for conditional responses
pub const ConditionOp = enum(u8) {
    none, // Always true
    has_flag, // Check if flag is set
    not_flag, // Check if flag is NOT set
    int_equals, // Integer comparison
    int_greater, // Integer > value
    int_less, // Integer < value
    int_greater_eq, // Integer >= value
    int_less_eq, // Integer <= value
};

/// A condition for showing/enabling a dialog option
pub const Condition = struct {
    op: ConditionOp = .none,
    key: [MAX_ID_LENGTH + 1]u8 = undefined,
    key_len: u8 = 0,
    int_value: i32 = 0,

    pub fn none() Condition {
        return .{ .op = .none };
    }

    pub fn hasFlag(flag: []const u8) Condition {
        var cond = Condition{ .op = .has_flag };
        const len = @min(flag.len, MAX_ID_LENGTH);
        @memcpy(cond.key[0..len], flag[0..len]);
        cond.key_len = @intCast(len);
        return cond;
    }

    pub fn notFlag(flag: []const u8) Condition {
        var cond = Condition{ .op = .not_flag };
        const len = @min(flag.len, MAX_ID_LENGTH);
        @memcpy(cond.key[0..len], flag[0..len]);
        cond.key_len = @intCast(len);
        return cond;
    }

    pub fn intEquals(key: []const u8, value: i32) Condition {
        var cond = Condition{ .op = .int_equals, .int_value = value };
        const len = @min(key.len, MAX_ID_LENGTH);
        @memcpy(cond.key[0..len], key[0..len]);
        cond.key_len = @intCast(len);
        return cond;
    }

    pub fn intGreater(key: []const u8, value: i32) Condition {
        var cond = Condition{ .op = .int_greater, .int_value = value };
        const len = @min(key.len, MAX_ID_LENGTH);
        @memcpy(cond.key[0..len], key[0..len]);
        cond.key_len = @intCast(len);
        return cond;
    }

    pub fn intLess(key: []const u8, value: i32) Condition {
        var cond = Condition{ .op = .int_less, .int_value = value };
        const len = @min(key.len, MAX_ID_LENGTH);
        @memcpy(cond.key[0..len], key[0..len]);
        cond.key_len = @intCast(len);
        return cond;
    }

    pub fn intGreaterEq(key: []const u8, value: i32) Condition {
        var cond = Condition{ .op = .int_greater_eq, .int_value = value };
        const len = @min(key.len, MAX_ID_LENGTH);
        @memcpy(cond.key[0..len], key[0..len]);
        cond.key_len = @intCast(len);
        return cond;
    }

    pub fn intLessEq(key: []const u8, value: i32) Condition {
        var cond = Condition{ .op = .int_less_eq, .int_value = value };
        const len = @min(key.len, MAX_ID_LENGTH);
        @memcpy(cond.key[0..len], key[0..len]);
        cond.key_len = @intCast(len);
        return cond;
    }

    pub fn getKey(self: *const Condition) []const u8 {
        return self.key[0..self.key_len];
    }

    /// Evaluate condition against a state provider
    pub fn evaluate(self: *const Condition, state: *const DialogState) bool {
        switch (self.op) {
            .none => return true,
            .has_flag => return state.getFlag(self.getKey()),
            .not_flag => return !state.getFlag(self.getKey()),
            .int_equals => return state.getInt(self.getKey()) == self.int_value,
            .int_greater => return state.getInt(self.getKey()) > self.int_value,
            .int_less => return state.getInt(self.getKey()) < self.int_value,
            .int_greater_eq => return state.getInt(self.getKey()) >= self.int_value,
            .int_less_eq => return state.getInt(self.getKey()) <= self.int_value,
        }
    }
};

/// Effect types that can be triggered by dialog options
pub const EffectType = enum(u8) {
    none,
    set_flag, // Set a boolean flag
    clear_flag, // Clear a boolean flag
    set_int, // Set an integer value
    add_int, // Add to an integer value
    trigger_event, // Trigger a named event
};

/// An effect that modifies game state when an option is selected
pub const Effect = struct {
    effect_type: EffectType = .none,
    key: [MAX_ID_LENGTH + 1]u8 = undefined,
    key_len: u8 = 0,
    int_value: i32 = 0,

    pub fn none() Effect {
        return .{ .effect_type = .none };
    }

    pub fn setFlag(flag: []const u8) Effect {
        var eff = Effect{ .effect_type = .set_flag };
        const len = @min(flag.len, MAX_ID_LENGTH);
        @memcpy(eff.key[0..len], flag[0..len]);
        eff.key_len = @intCast(len);
        return eff;
    }

    pub fn clearFlag(flag: []const u8) Effect {
        var eff = Effect{ .effect_type = .clear_flag };
        const len = @min(flag.len, MAX_ID_LENGTH);
        @memcpy(eff.key[0..len], flag[0..len]);
        eff.key_len = @intCast(len);
        return eff;
    }

    pub fn setInt(key: []const u8, value: i32) Effect {
        var eff = Effect{ .effect_type = .set_int, .int_value = value };
        const len = @min(key.len, MAX_ID_LENGTH);
        @memcpy(eff.key[0..len], key[0..len]);
        eff.key_len = @intCast(len);
        return eff;
    }

    pub fn addInt(key: []const u8, value: i32) Effect {
        var eff = Effect{ .effect_type = .add_int, .int_value = value };
        const len = @min(key.len, MAX_ID_LENGTH);
        @memcpy(eff.key[0..len], key[0..len]);
        eff.key_len = @intCast(len);
        return eff;
    }

    pub fn triggerEvent(event: []const u8) Effect {
        var eff = Effect{ .effect_type = .trigger_event };
        const len = @min(event.len, MAX_ID_LENGTH);
        @memcpy(eff.key[0..len], event[0..len]);
        eff.key_len = @intCast(len);
        return eff;
    }

    pub fn getKey(self: *const Effect) []const u8 {
        return self.key[0..self.key_len];
    }

    /// Apply effect to state
    pub fn apply(self: *const Effect, state: *DialogState) void {
        switch (self.effect_type) {
            .none => {},
            .set_flag => state.setFlag(self.getKey(), true),
            .clear_flag => state.setFlag(self.getKey(), false),
            .set_int => state.setInt(self.getKey(), self.int_value),
            .add_int => {
                const current = state.getInt(self.getKey());
                state.setInt(self.getKey(), current + self.int_value);
            },
            .trigger_event => {
                // Events are handled by callbacks, not state modification
                // The DialogSystem will notify callbacks when this effect is applied
            },
        }
    }
};

/// Maximum effects per option
pub const MAX_EFFECTS_PER_OPTION: usize = 4;

/// A dialog option (player response choice)
pub const DialogOption = struct {
    text: [MAX_TEXT_LENGTH + 1]u8 = undefined,
    text_len: u16 = 0,
    next_node: [MAX_ID_LENGTH + 1]u8 = undefined,
    next_node_len: u8 = 0,
    condition: Condition = Condition.none(),
    effects: [MAX_EFFECTS_PER_OPTION]Effect = [_]Effect{Effect.none()} ** MAX_EFFECTS_PER_OPTION,
    effect_count: u8 = 0,
    ends_dialog: bool = false,

    pub fn getText(self: *const DialogOption) []const u8 {
        return self.text[0..self.text_len];
    }

    pub fn getNextNode(self: *const DialogOption) []const u8 {
        return self.next_node[0..self.next_node_len];
    }

    pub fn isAvailable(self: *const DialogOption, state: *const DialogState) bool {
        return self.condition.evaluate(state);
    }
};

/// A dialog node (NPC speech with options)
pub const DialogNode = struct {
    id: [MAX_ID_LENGTH + 1]u8 = undefined,
    id_len: u8 = 0,
    speaker: [MAX_SPEAKER_LENGTH + 1]u8 = undefined,
    speaker_len: u8 = 0,
    text: [MAX_TEXT_LENGTH + 1]u8 = undefined,
    text_len: u16 = 0,
    options: std.ArrayList(DialogOption),

    pub fn getId(self: *const DialogNode) []const u8 {
        return self.id[0..self.id_len];
    }

    pub fn getSpeaker(self: *const DialogNode) []const u8 {
        return self.speaker[0..self.speaker_len];
    }

    pub fn getText(self: *const DialogNode) []const u8 {
        return self.text[0..self.text_len];
    }
};

/// Configuration for adding a dialog node
pub const NodeConfig = struct {
    id: []const u8,
    speaker: []const u8 = "",
    text: []const u8 = "",
};

/// Configuration for adding a dialog option
pub const OptionConfig = struct {
    text: []const u8,
    next_node: []const u8 = "",
    condition: Condition = Condition.none(),
    effects: []const Effect = &.{},
    ends_dialog: bool = false,
};

/// History entry for tracking dialog flow
pub const HistoryEntry = struct {
    node_id: [MAX_ID_LENGTH + 1]u8 = undefined,
    node_id_len: u8 = 0,
    option_index: ?u8 = null,
    timestamp: i64 = 0,

    pub fn getNodeId(self: *const HistoryEntry) []const u8 {
        return self.node_id[0..self.node_id_len];
    }
};

/// Dialog state - tracks flags, integers, and other game state for conditions
pub const DialogState = struct {
    allocator: Allocator,
    flags: std.StringHashMap(bool),
    integers: std.StringHashMap(i32),

    pub fn init(allocator: Allocator) DialogState {
        return .{
            .allocator = allocator,
            .flags = std.StringHashMap(bool).init(allocator),
            .integers = std.StringHashMap(i32).init(allocator),
        };
    }

    pub fn deinit(self: *DialogState) void {
        // Free all keys
        var flag_iter = self.flags.keyIterator();
        while (flag_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.flags.deinit();

        var int_iter = self.integers.keyIterator();
        while (int_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.integers.deinit();
    }

    pub fn getFlag(self: *const DialogState, key: []const u8) bool {
        return self.flags.get(key) orelse false;
    }

    pub fn setFlag(self: *DialogState, key: []const u8, value: bool) void {
        if (self.flags.getKey(key)) |existing_key| {
            self.flags.put(existing_key, value) catch {};
        } else {
            const owned_key = self.allocator.dupe(u8, key) catch return;
            self.flags.put(owned_key, value) catch {
                self.allocator.free(owned_key);
            };
        }
    }

    pub fn getInt(self: *const DialogState, key: []const u8) i32 {
        return self.integers.get(key) orelse 0;
    }

    pub fn setInt(self: *DialogState, key: []const u8, value: i32) void {
        if (self.integers.getKey(key)) |existing_key| {
            self.integers.put(existing_key, value) catch {};
        } else {
            const owned_key = self.allocator.dupe(u8, key) catch return;
            self.integers.put(owned_key, value) catch {
                self.allocator.free(owned_key);
            };
        }
    }

    pub fn clearAll(self: *DialogState) void {
        var flag_iter = self.flags.keyIterator();
        while (flag_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.flags.clearRetainingCapacity();

        var int_iter = self.integers.keyIterator();
        while (int_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.integers.clearRetainingCapacity();
    }
};

/// Event callback type
pub const EventCallback = *const fn (system: *DialogSystem, event: []const u8, userdata: ?*anyopaque) void;

/// Event subscription
const EventSubscription = struct {
    callback: EventCallback,
    userdata: ?*anyopaque,
};

/// Dialog system statistics
pub const DialogStats = struct {
    node_count: usize,
    total_options: usize,
    history_length: usize,
    state_flags: usize,
    state_integers: usize,
    is_active: bool,
};

/// Node handle for referencing nodes
pub const NodeHandle = u32;

/// Main dialog system
pub const DialogSystem = struct {
    allocator: Allocator,
    nodes: std.ArrayList(DialogNode),
    node_map: std.StringHashMap(NodeHandle),
    state: DialogState,
    history: std.ArrayList(HistoryEntry),
    max_history: usize,
    current_node: ?NodeHandle = null,
    is_active: bool = false,
    event_callbacks: std.ArrayList(EventSubscription),

    pub const Config = struct {
        initial_node_capacity: usize = 64,
        max_history: usize = 256,
    };

    pub fn init(allocator: Allocator) DialogSystem {
        return initWithConfig(allocator, .{});
    }

    pub fn initWithConfig(allocator: Allocator, config: Config) DialogSystem {
        return .{
            .allocator = allocator,
            .nodes = std.ArrayList(DialogNode).initCapacity(allocator, config.initial_node_capacity) catch std.ArrayList(DialogNode).init(allocator),
            .node_map = std.StringHashMap(NodeHandle).init(allocator),
            .state = DialogState.init(allocator),
            .history = std.ArrayList(HistoryEntry).initCapacity(allocator, config.max_history) catch std.ArrayList(HistoryEntry).init(allocator),
            .max_history = config.max_history,
            .event_callbacks = std.ArrayList(EventSubscription).init(allocator),
        };
    }

    pub fn deinit(self: *DialogSystem) void {
        // Free node options
        for (self.nodes.items) |*node| {
            node.options.deinit();
        }
        self.nodes.deinit();

        // Free node map keys
        var iter = self.node_map.keyIterator();
        while (iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.node_map.deinit();

        self.state.deinit();
        self.history.deinit();
        self.event_callbacks.deinit();
    }

    // ============================================================
    // Node Management
    // ============================================================

    /// Add a dialog node
    pub fn addNode(self: *DialogSystem, config: NodeConfig) !NodeHandle {
        if (config.id.len > MAX_ID_LENGTH) return error.IdTooLong;
        if (config.speaker.len > MAX_SPEAKER_LENGTH) return error.SpeakerTooLong;
        if (config.text.len > MAX_TEXT_LENGTH) return error.TextTooLong;

        // Check for duplicate ID
        if (self.node_map.contains(config.id)) return error.DuplicateId;

        const handle: NodeHandle = @intCast(self.nodes.items.len);

        var node: DialogNode = .{
            .options = std.ArrayList(DialogOption).init(self.allocator),
        };

        @memcpy(node.id[0..config.id.len], config.id);
        node.id_len = @intCast(config.id.len);

        @memcpy(node.speaker[0..config.speaker.len], config.speaker);
        node.speaker_len = @intCast(config.speaker.len);

        @memcpy(node.text[0..config.text.len], config.text);
        node.text_len = @intCast(config.text.len);

        try self.nodes.append(node);

        // Add to map
        const owned_id = try self.allocator.dupe(u8, config.id);
        errdefer self.allocator.free(owned_id);
        try self.node_map.put(owned_id, handle);

        return handle;
    }

    /// Get node by handle
    pub fn getNode(self: *const DialogSystem, handle: NodeHandle) ?*const DialogNode {
        if (handle >= self.nodes.items.len) return null;
        return &self.nodes.items[handle];
    }

    /// Get node by ID
    pub fn getNodeById(self: *const DialogSystem, id: []const u8) ?*const DialogNode {
        const handle = self.node_map.get(id) orelse return null;
        return self.getNode(handle);
    }

    /// Get node handle by ID
    pub fn getNodeHandle(self: *const DialogSystem, id: []const u8) ?NodeHandle {
        return self.node_map.get(id);
    }

    /// Update node text
    pub fn setNodeText(self: *DialogSystem, handle: NodeHandle, text: []const u8) !void {
        if (text.len > MAX_TEXT_LENGTH) return error.TextTooLong;
        if (handle >= self.nodes.items.len) return error.InvalidHandle;

        var node = &self.nodes.items[handle];
        @memcpy(node.text[0..text.len], text);
        node.text_len = @intCast(text.len);
    }

    /// Update node speaker
    pub fn setNodeSpeaker(self: *DialogSystem, handle: NodeHandle, speaker: []const u8) !void {
        if (speaker.len > MAX_SPEAKER_LENGTH) return error.SpeakerTooLong;
        if (handle >= self.nodes.items.len) return error.InvalidHandle;

        var node = &self.nodes.items[handle];
        @memcpy(node.speaker[0..speaker.len], speaker);
        node.speaker_len = @intCast(speaker.len);
    }

    // ============================================================
    // Option Management
    // ============================================================

    /// Add an option to a node
    pub fn addOption(self: *DialogSystem, node_handle: NodeHandle, config: OptionConfig) !void {
        if (config.text.len > MAX_TEXT_LENGTH) return error.TextTooLong;
        if (config.next_node.len > MAX_ID_LENGTH) return error.IdTooLong;
        if (node_handle >= self.nodes.items.len) return error.InvalidHandle;

        var option: DialogOption = .{
            .condition = config.condition,
            .ends_dialog = config.ends_dialog,
        };

        @memcpy(option.text[0..config.text.len], config.text);
        option.text_len = @intCast(config.text.len);

        @memcpy(option.next_node[0..config.next_node.len], config.next_node);
        option.next_node_len = @intCast(config.next_node.len);

        // Copy effects
        const effect_count = @min(config.effects.len, MAX_EFFECTS_PER_OPTION);
        for (config.effects[0..effect_count], 0..) |effect, i| {
            option.effects[i] = effect;
        }
        option.effect_count = @intCast(effect_count);

        try self.nodes.items[node_handle].options.append(option);
    }

    /// Get options for a node (all options, regardless of availability)
    pub fn getOptions(self: *const DialogSystem, node_handle: NodeHandle) ?[]const DialogOption {
        if (node_handle >= self.nodes.items.len) return null;
        return self.nodes.items[node_handle].options.items;
    }

    /// Get available options (filtered by conditions)
    pub fn getAvailableOptions(self: *const DialogSystem, node_handle: NodeHandle, allocator: Allocator) ![]const DialogOption {
        if (node_handle >= self.nodes.items.len) return error.InvalidHandle;

        const node = &self.nodes.items[node_handle];
        var available = std.ArrayList(DialogOption).init(allocator);
        errdefer available.deinit();

        for (node.options.items) |*opt| {
            if (opt.isAvailable(&self.state)) {
                try available.append(opt.*);
            }
        }

        return available.toOwnedSlice();
    }

    /// Get available option indices
    pub fn getAvailableOptionIndices(self: *const DialogSystem, node_handle: NodeHandle, allocator: Allocator) ![]usize {
        if (node_handle >= self.nodes.items.len) return error.InvalidHandle;

        const node = &self.nodes.items[node_handle];
        var indices = std.ArrayList(usize).init(allocator);
        errdefer indices.deinit();

        for (node.options.items, 0..) |*opt, i| {
            if (opt.isAvailable(&self.state)) {
                try indices.append(i);
            }
        }

        return indices.toOwnedSlice();
    }

    // ============================================================
    // Dialog Flow
    // ============================================================

    /// Start a dialog at the given node
    pub fn start(self: *DialogSystem, node_id: []const u8) !void {
        const handle = self.node_map.get(node_id) orelse return error.NodeNotFound;
        self.current_node = handle;
        self.is_active = true;

        // Add to history
        try self.addHistoryEntry(node_id, null);
    }

    /// Start a dialog at the given node handle
    pub fn startAt(self: *DialogSystem, handle: NodeHandle) !void {
        if (handle >= self.nodes.items.len) return error.InvalidHandle;
        self.current_node = handle;
        self.is_active = true;

        const node = &self.nodes.items[handle];
        try self.addHistoryEntry(node.getId(), null);
    }

    /// Get current node handle
    pub fn getCurrentNodeHandle(self: *const DialogSystem) ?NodeHandle {
        return self.current_node;
    }

    /// Get current node
    pub fn getCurrentNode(self: *const DialogSystem) ?*const DialogNode {
        const handle = self.current_node orelse return null;
        return self.getNode(handle);
    }

    /// Select an option by index (0-based, filtered index)
    pub fn selectOption(self: *DialogSystem, filtered_index: usize) !void {
        const handle = self.current_node orelse return error.NoActiveDialog;
        const node = &self.nodes.items[handle];

        // Find the actual option index from filtered index
        var count: usize = 0;
        var actual_index: ?usize = null;
        for (node.options.items, 0..) |*opt, i| {
            if (opt.isAvailable(&self.state)) {
                if (count == filtered_index) {
                    actual_index = i;
                    break;
                }
                count += 1;
            }
        }

        const idx = actual_index orelse return error.InvalidOptionIndex;
        try self.selectOptionRaw(idx);
    }

    /// Select an option by raw index (0-based, unfiltered)
    pub fn selectOptionRaw(self: *DialogSystem, option_index: usize) !void {
        const handle = self.current_node orelse return error.NoActiveDialog;
        const node = &self.nodes.items[handle];

        if (option_index >= node.options.items.len) return error.InvalidOptionIndex;

        const option = &node.options.items[option_index];

        // Check condition
        if (!option.isAvailable(&self.state)) return error.OptionNotAvailable;

        // Apply effects
        for (option.effects[0..option.effect_count]) |*effect| {
            if (effect.effect_type == .trigger_event) {
                self.fireEvent(effect.getKey());
            } else {
                effect.apply(&self.state);
            }
        }

        // Handle ending or transitioning
        if (option.ends_dialog) {
            try self.addHistoryEntry(node.getId(), @intCast(option_index));
            self.is_active = false;
            self.current_node = null;
        } else {
            const next_id = option.getNextNode();
            if (next_id.len > 0) {
                const next_handle = self.node_map.get(next_id) orelse return error.NodeNotFound;
                try self.addHistoryEntry(node.getId(), @intCast(option_index));
                self.current_node = next_handle;
            } else {
                // No next node and doesn't end - stay at current node
                try self.addHistoryEntry(node.getId(), @intCast(option_index));
            }
        }
    }

    /// End the current dialog
    pub fn endDialog(self: *DialogSystem) void {
        self.is_active = false;
        self.current_node = null;
    }

    /// Check if dialog is active
    pub fn isActive(self: *const DialogSystem) bool {
        return self.is_active;
    }

    /// Jump to a specific node (without selecting an option)
    pub fn jumpTo(self: *DialogSystem, node_id: []const u8) !void {
        const handle = self.node_map.get(node_id) orelse return error.NodeNotFound;
        if (!self.is_active) return error.NoActiveDialog;

        self.current_node = handle;
        try self.addHistoryEntry(node_id, null);
    }

    // ============================================================
    // State Management
    // ============================================================

    /// Get dialog state (for external modification)
    pub fn getState(self: *DialogSystem) *DialogState {
        return &self.state;
    }

    /// Set a flag
    pub fn setFlag(self: *DialogSystem, key: []const u8, value: bool) void {
        self.state.setFlag(key, value);
    }

    /// Get a flag
    pub fn getFlag(self: *const DialogSystem, key: []const u8) bool {
        return self.state.getFlag(key);
    }

    /// Set an integer
    pub fn setInt(self: *DialogSystem, key: []const u8, value: i32) void {
        self.state.setInt(key, value);
    }

    /// Get an integer
    pub fn getInt(self: *const DialogSystem, key: []const u8) i32 {
        return self.state.getInt(key);
    }

    // ============================================================
    // History
    // ============================================================

    fn addHistoryEntry(self: *DialogSystem, node_id: []const u8, option_index: ?u8) !void {
        if (self.history.items.len >= self.max_history) {
            _ = self.history.orderedRemove(0);
        }

        var entry: HistoryEntry = .{
            .option_index = option_index,
            .timestamp = std.time.milliTimestamp(),
        };

        const len = @min(node_id.len, MAX_ID_LENGTH);
        @memcpy(entry.node_id[0..len], node_id[0..len]);
        entry.node_id_len = @intCast(len);

        try self.history.append(entry);
    }

    /// Get dialog history (newest first)
    pub fn getHistory(self: *const DialogSystem, allocator: Allocator, max: usize) ![]HistoryEntry {
        const count = @min(max, self.history.items.len);
        var result = try allocator.alloc(HistoryEntry, count);

        for (0..count) |i| {
            result[i] = self.history.items[self.history.items.len - 1 - i];
        }

        return result;
    }

    /// Get history count
    pub fn getHistoryCount(self: *const DialogSystem) usize {
        return self.history.items.len;
    }

    /// Clear history
    pub fn clearHistory(self: *DialogSystem) void {
        self.history.clearRetainingCapacity();
    }

    /// Check if a node was visited
    pub fn wasNodeVisited(self: *const DialogSystem, node_id: []const u8) bool {
        for (self.history.items) |*entry| {
            if (std.mem.eql(u8, entry.getNodeId(), node_id)) {
                return true;
            }
        }
        return false;
    }

    /// Count visits to a node
    pub fn getNodeVisitCount(self: *const DialogSystem, node_id: []const u8) usize {
        var count: usize = 0;
        for (self.history.items) |*entry| {
            if (std.mem.eql(u8, entry.getNodeId(), node_id)) {
                count += 1;
            }
        }
        return count;
    }

    // ============================================================
    // Event Callbacks
    // ============================================================

    /// Register an event callback
    pub fn onEvent(self: *DialogSystem, callback: EventCallback, userdata: ?*anyopaque) !void {
        try self.event_callbacks.append(.{
            .callback = callback,
            .userdata = userdata,
        });
    }

    /// Fire an event to all callbacks
    fn fireEvent(self: *DialogSystem, event: []const u8) void {
        for (self.event_callbacks.items) |*sub| {
            sub.callback(self, event, sub.userdata);
        }
    }

    /// Clear all event callbacks
    pub fn clearEventCallbacks(self: *DialogSystem) void {
        self.event_callbacks.clearRetainingCapacity();
    }

    // ============================================================
    // Statistics
    // ============================================================

    /// Get dialog statistics
    pub fn getStats(self: *const DialogSystem) DialogStats {
        var total_options: usize = 0;
        for (self.nodes.items) |*node| {
            total_options += node.options.items.len;
        }

        return .{
            .node_count = self.nodes.items.len,
            .total_options = total_options,
            .history_length = self.history.items.len,
            .state_flags = self.state.flags.count(),
            .state_integers = self.state.integers.count(),
            .is_active = self.is_active,
        };
    }

    /// Get node count
    pub fn getNodeCount(self: *const DialogSystem) usize {
        return self.nodes.items.len;
    }

    // ============================================================
    // Serialization helpers
    // ============================================================

    /// Get all node IDs
    pub fn getNodeIds(self: *const DialogSystem, allocator: Allocator) ![][]const u8 {
        var ids = try allocator.alloc([]const u8, self.nodes.items.len);
        for (self.nodes.items, 0..) |*node, i| {
            ids[i] = node.getId();
        }
        return ids;
    }

    /// Reset dialog system (keep nodes, reset state and history)
    pub fn reset(self: *DialogSystem) void {
        self.state.clearAll();
        self.history.clearRetainingCapacity();
        self.current_node = null;
        self.is_active = false;
    }

    /// Clear all nodes and reset
    pub fn clear(self: *DialogSystem) void {
        for (self.nodes.items) |*node| {
            node.options.deinit();
        }
        self.nodes.clearRetainingCapacity();

        var iter = self.node_map.keyIterator();
        while (iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.node_map.clearRetainingCapacity();

        self.reset();
    }
};

// ============================================================
// Tests
// ============================================================

test "DialogSystem: basic node creation" {
    const allocator = std.testing.allocator;
    var dialog = DialogSystem.init(allocator);
    defer dialog.deinit();

    const handle = try dialog.addNode(.{
        .id = "greeting",
        .speaker = "Merchant",
        .text = "Welcome to my shop!",
    });

    try std.testing.expectEqual(@as(NodeHandle, 0), handle);
    try std.testing.expectEqual(@as(usize, 1), dialog.getNodeCount());

    const node = dialog.getNode(handle).?;
    try std.testing.expectEqualStrings("greeting", node.getId());
    try std.testing.expectEqualStrings("Merchant", node.getSpeaker());
    try std.testing.expectEqualStrings("Welcome to my shop!", node.getText());
}

test "DialogSystem: duplicate node ID error" {
    const allocator = std.testing.allocator;
    var dialog = DialogSystem.init(allocator);
    defer dialog.deinit();

    _ = try dialog.addNode(.{ .id = "greeting" });
    try std.testing.expectError(error.DuplicateId, dialog.addNode(.{ .id = "greeting" }));
}

test "DialogSystem: node lookup by ID" {
    const allocator = std.testing.allocator;
    var dialog = DialogSystem.init(allocator);
    defer dialog.deinit();

    _ = try dialog.addNode(.{ .id = "node1", .text = "First" });
    _ = try dialog.addNode(.{ .id = "node2", .text = "Second" });

    const node1 = dialog.getNodeById("node1").?;
    try std.testing.expectEqualStrings("First", node1.getText());

    const node2 = dialog.getNodeById("node2").?;
    try std.testing.expectEqualStrings("Second", node2.getText());

    try std.testing.expect(dialog.getNodeById("nonexistent") == null);
}

test "DialogSystem: add options" {
    const allocator = std.testing.allocator;
    var dialog = DialogSystem.init(allocator);
    defer dialog.deinit();

    const handle = try dialog.addNode(.{
        .id = "greeting",
        .text = "Hello!",
    });

    try dialog.addOption(handle, .{ .text = "Hi there!", .next_node = "response" });
    try dialog.addOption(handle, .{ .text = "Goodbye", .ends_dialog = true });

    const options = dialog.getOptions(handle).?;
    try std.testing.expectEqual(@as(usize, 2), options.len);
    try std.testing.expectEqualStrings("Hi there!", options[0].getText());
    try std.testing.expectEqualStrings("Goodbye", options[1].getText());
}

test "DialogSystem: conditional options" {
    const allocator = std.testing.allocator;
    var dialog = DialogSystem.init(allocator);
    defer dialog.deinit();

    const handle = try dialog.addNode(.{ .id = "shop" });

    try dialog.addOption(handle, .{
        .text = "Buy sword",
        .next_node = "buy_sword",
    });

    try dialog.addOption(handle, .{
        .text = "Sell rare item",
        .next_node = "sell_rare",
        .condition = Condition.hasFlag("has_rare_item"),
    });

    // Without flag - only 1 available option
    const available1 = try dialog.getAvailableOptions(handle, allocator);
    defer allocator.free(available1);
    try std.testing.expectEqual(@as(usize, 1), available1.len);

    // Set flag - now 2 available
    dialog.setFlag("has_rare_item", true);
    const available2 = try dialog.getAvailableOptions(handle, allocator);
    defer allocator.free(available2);
    try std.testing.expectEqual(@as(usize, 2), available2.len);
}

test "DialogSystem: integer conditions" {
    const allocator = std.testing.allocator;
    var dialog = DialogSystem.init(allocator);
    defer dialog.deinit();

    const handle = try dialog.addNode(.{ .id = "shop" });

    try dialog.addOption(handle, .{
        .text = "Buy expensive item",
        .condition = Condition.intGreaterEq("gold", 100),
    });

    dialog.setInt("gold", 50);
    const available1 = try dialog.getAvailableOptions(handle, allocator);
    defer allocator.free(available1);
    try std.testing.expectEqual(@as(usize, 0), available1.len);

    dialog.setInt("gold", 100);
    const available2 = try dialog.getAvailableOptions(handle, allocator);
    defer allocator.free(available2);
    try std.testing.expectEqual(@as(usize, 1), available2.len);
}

test "DialogSystem: start and navigate" {
    const allocator = std.testing.allocator;
    var dialog = DialogSystem.init(allocator);
    defer dialog.deinit();

    const greeting = try dialog.addNode(.{ .id = "greeting", .text = "Hello!" });
    _ = try dialog.addNode(.{ .id = "farewell", .text = "Goodbye!" });

    try dialog.addOption(greeting, .{ .text = "Say bye", .next_node = "farewell" });

    try dialog.start("greeting");
    try std.testing.expect(dialog.isActive());

    const current = dialog.getCurrentNode().?;
    try std.testing.expectEqualStrings("Hello!", current.getText());

    try dialog.selectOption(0);
    const next = dialog.getCurrentNode().?;
    try std.testing.expectEqualStrings("Goodbye!", next.getText());
}

test "DialogSystem: end dialog" {
    const allocator = std.testing.allocator;
    var dialog = DialogSystem.init(allocator);
    defer dialog.deinit();

    const handle = try dialog.addNode(.{ .id = "greeting" });
    try dialog.addOption(handle, .{ .text = "Bye", .ends_dialog = true });

    try dialog.start("greeting");
    try std.testing.expect(dialog.isActive());

    try dialog.selectOption(0);
    try std.testing.expect(!dialog.isActive());
    try std.testing.expect(dialog.getCurrentNode() == null);
}

test "DialogSystem: effects" {
    const allocator = std.testing.allocator;
    var dialog = DialogSystem.init(allocator);
    defer dialog.deinit();

    const handle = try dialog.addNode(.{ .id = "quest" });
    try dialog.addOption(handle, .{
        .text = "Accept quest",
        .effects = &.{
            Effect.setFlag("quest_accepted"),
            Effect.addInt("reputation", 10),
        },
        .ends_dialog = true,
    });

    dialog.setInt("reputation", 50);

    try dialog.start("quest");
    try dialog.selectOption(0);

    try std.testing.expect(dialog.getFlag("quest_accepted"));
    try std.testing.expectEqual(@as(i32, 60), dialog.getInt("reputation"));
}

test "DialogSystem: event callbacks" {
    const allocator = std.testing.allocator;
    var dialog = DialogSystem.init(allocator);
    defer dialog.deinit();

    var event_fired = false;

    const callback = struct {
        fn cb(_: *DialogSystem, event: []const u8, userdata: ?*anyopaque) void {
            const fired: *bool = @ptrCast(@alignCast(userdata.?));
            if (std.mem.eql(u8, event, "quest_complete")) {
                fired.* = true;
            }
        }
    }.cb;

    try dialog.onEvent(callback, &event_fired);

    const handle = try dialog.addNode(.{ .id = "quest_end" });
    try dialog.addOption(handle, .{
        .text = "Complete quest",
        .effects = &.{Effect.triggerEvent("quest_complete")},
        .ends_dialog = true,
    });

    try dialog.start("quest_end");
    try dialog.selectOption(0);

    try std.testing.expect(event_fired);
}

test "DialogSystem: history tracking" {
    const allocator = std.testing.allocator;
    var dialog = DialogSystem.init(allocator);
    defer dialog.deinit();

    const n1 = try dialog.addNode(.{ .id = "node1" });
    _ = try dialog.addNode(.{ .id = "node2" });
    try dialog.addOption(n1, .{ .text = "Go to node2", .next_node = "node2" });

    try dialog.start("node1");
    try dialog.selectOption(0);

    const history = try dialog.getHistory(allocator, 10);
    defer allocator.free(history);

    try std.testing.expectEqual(@as(usize, 2), history.len);
    // Newest first
    try std.testing.expectEqualStrings("node1", history[0].getNodeId());
    try std.testing.expectEqual(@as(?u8, 0), history[0].option_index);
}

test "DialogSystem: wasNodeVisited" {
    const allocator = std.testing.allocator;
    var dialog = DialogSystem.init(allocator);
    defer dialog.deinit();

    _ = try dialog.addNode(.{ .id = "visited" });
    _ = try dialog.addNode(.{ .id = "not_visited" });

    try std.testing.expect(!dialog.wasNodeVisited("visited"));

    try dialog.start("visited");
    try std.testing.expect(dialog.wasNodeVisited("visited"));
    try std.testing.expect(!dialog.wasNodeVisited("not_visited"));
}

test "DialogSystem: jumpTo" {
    const allocator = std.testing.allocator;
    var dialog = DialogSystem.init(allocator);
    defer dialog.deinit();

    _ = try dialog.addNode(.{ .id = "start", .text = "Start" });
    _ = try dialog.addNode(.{ .id = "middle", .text = "Middle" });
    _ = try dialog.addNode(.{ .id = "end", .text = "End" });

    try dialog.start("start");
    try dialog.jumpTo("end");

    const current = dialog.getCurrentNode().?;
    try std.testing.expectEqualStrings("End", current.getText());
}

test "DialogSystem: reset and clear" {
    const allocator = std.testing.allocator;
    var dialog = DialogSystem.init(allocator);
    defer dialog.deinit();

    _ = try dialog.addNode(.{ .id = "test" });
    dialog.setFlag("test_flag", true);
    try dialog.start("test");

    // Reset keeps nodes but clears state
    dialog.reset();
    try std.testing.expect(!dialog.isActive());
    try std.testing.expect(!dialog.getFlag("test_flag"));
    try std.testing.expectEqual(@as(usize, 1), dialog.getNodeCount());

    // Clear removes everything
    dialog.clear();
    try std.testing.expectEqual(@as(usize, 0), dialog.getNodeCount());
}

test "DialogSystem: stats" {
    const allocator = std.testing.allocator;
    var dialog = DialogSystem.init(allocator);
    defer dialog.deinit();

    const handle = try dialog.addNode(.{ .id = "test" });
    try dialog.addOption(handle, .{ .text = "Option 1" });
    try dialog.addOption(handle, .{ .text = "Option 2" });
    dialog.setFlag("flag1", true);
    dialog.setInt("counter", 42);

    const stats = dialog.getStats();
    try std.testing.expectEqual(@as(usize, 1), stats.node_count);
    try std.testing.expectEqual(@as(usize, 2), stats.total_options);
    try std.testing.expectEqual(@as(usize, 1), stats.state_flags);
    try std.testing.expectEqual(@as(usize, 1), stats.state_integers);
}

test "DialogSystem: Condition operators" {
    const allocator = std.testing.allocator;
    var state = DialogState.init(allocator);
    defer state.deinit();

    state.setInt("level", 10);
    state.setFlag("is_member", true);

    try std.testing.expect(Condition.none().evaluate(&state));
    try std.testing.expect(Condition.hasFlag("is_member").evaluate(&state));
    try std.testing.expect(!Condition.hasFlag("nonexistent").evaluate(&state));
    try std.testing.expect(Condition.notFlag("nonexistent").evaluate(&state));
    try std.testing.expect(!Condition.notFlag("is_member").evaluate(&state));

    try std.testing.expect(Condition.intEquals("level", 10).evaluate(&state));
    try std.testing.expect(!Condition.intEquals("level", 5).evaluate(&state));
    try std.testing.expect(Condition.intGreater("level", 5).evaluate(&state));
    try std.testing.expect(!Condition.intGreater("level", 10).evaluate(&state));
    try std.testing.expect(Condition.intGreaterEq("level", 10).evaluate(&state));
    try std.testing.expect(Condition.intLess("level", 15).evaluate(&state));
    try std.testing.expect(Condition.intLessEq("level", 10).evaluate(&state));
}

test "DialogSystem: Effect application" {
    const allocator = std.testing.allocator;
    var state = DialogState.init(allocator);
    defer state.deinit();

    Effect.setFlag("completed").apply(&state);
    try std.testing.expect(state.getFlag("completed"));

    Effect.clearFlag("completed").apply(&state);
    try std.testing.expect(!state.getFlag("completed"));

    Effect.setInt("gold", 100).apply(&state);
    try std.testing.expectEqual(@as(i32, 100), state.getInt("gold"));

    Effect.addInt("gold", 50).apply(&state);
    try std.testing.expectEqual(@as(i32, 150), state.getInt("gold"));

    Effect.addInt("gold", -30).apply(&state);
    try std.testing.expectEqual(@as(i32, 120), state.getInt("gold"));
}

test "DialogSystem: filtered option selection" {
    const allocator = std.testing.allocator;
    var dialog = DialogSystem.init(allocator);
    defer dialog.deinit();

    const handle = try dialog.addNode(.{ .id = "shop" });
    try dialog.addOption(handle, .{
        .text = "Hidden option",
        .condition = Condition.hasFlag("special"),
        .next_node = "special",
    });
    try dialog.addOption(handle, .{ .text = "Normal option", .next_node = "normal" });

    _ = try dialog.addNode(.{ .id = "special", .text = "Special!" });
    _ = try dialog.addNode(.{ .id = "normal", .text = "Normal" });

    try dialog.start("shop");

    // Without flag, index 0 should select "Normal option" (second in raw list)
    try dialog.selectOption(0);
    try std.testing.expectEqualStrings("Normal", dialog.getCurrentNode().?.getText());
}

test "DialogSystem: node text update" {
    const allocator = std.testing.allocator;
    var dialog = DialogSystem.init(allocator);
    defer dialog.deinit();

    const handle = try dialog.addNode(.{
        .id = "dynamic",
        .text = "Original text",
    });

    try dialog.setNodeText(handle, "Updated text");

    const node = dialog.getNode(handle).?;
    try std.testing.expectEqualStrings("Updated text", node.getText());
}

test "DialogSystem: visit count" {
    const allocator = std.testing.allocator;
    var dialog = DialogSystem.init(allocator);
    defer dialog.deinit();

    const n1 = try dialog.addNode(.{ .id = "hub" });
    _ = try dialog.addNode(.{ .id = "branch" });
    try dialog.addOption(n1, .{ .text = "Visit branch", .next_node = "branch" });

    try dialog.start("hub");
    try std.testing.expectEqual(@as(usize, 1), dialog.getNodeVisitCount("hub"));

    try dialog.jumpTo("hub");
    try std.testing.expectEqual(@as(usize, 2), dialog.getNodeVisitCount("hub"));

    try dialog.jumpTo("hub");
    try std.testing.expectEqual(@as(usize, 3), dialog.getNodeVisitCount("hub"));
}

test "DialogSystem: getNodeIds" {
    const allocator = std.testing.allocator;
    var dialog = DialogSystem.init(allocator);
    defer dialog.deinit();

    _ = try dialog.addNode(.{ .id = "alpha" });
    _ = try dialog.addNode(.{ .id = "beta" });
    _ = try dialog.addNode(.{ .id = "gamma" });

    const ids = try dialog.getNodeIds(allocator);
    defer allocator.free(ids);

    try std.testing.expectEqual(@as(usize, 3), ids.len);
}

test "DialogSystem: error cases" {
    const allocator = std.testing.allocator;
    var dialog = DialogSystem.init(allocator);
    defer dialog.deinit();

    // Start non-existent node
    try std.testing.expectError(error.NodeNotFound, dialog.start("nonexistent"));

    // Select option without active dialog
    try std.testing.expectError(error.NoActiveDialog, dialog.selectOption(0));

    // Jump without active dialog
    try std.testing.expectError(error.NoActiveDialog, dialog.jumpTo("somewhere"));

    // Invalid handle
    try std.testing.expectError(error.InvalidHandle, dialog.addOption(999, .{ .text = "test" }));
}
