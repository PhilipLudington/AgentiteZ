// storage.zig
// Game state serialization and deserialization to TOML format
// Adapted from StellarThroneZig for MUD-specific game state

const std = @import("std");
const toml = @import("data/toml.zig");
const config = @import("config.zig");
const log = @import("log.zig");

/// Represents the complete state of a MUD game session
pub const GameState = struct {
    /// Game metadata
    version: []const u8 = "1.0",
    current_tick: u32 = 0,
    timestamp: i64 = 0,

    /// Player state
    player: PlayerState = .{},

    /// Current room the player is in
    current_room_id: []const u8 = "",

    /// Player inventory (item IDs)
    inventory: std.ArrayList([]const u8),

    /// World state - rooms that have been modified
    modified_rooms: std.StringHashMap(RoomState),

    /// NPCs that have been modified (position, health, etc.)
    modified_npcs: std.StringHashMap(NPCState),

    /// Items that have been dropped in rooms
    dropped_items: std.ArrayList(DroppedItem),

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) GameState {
        return .{
            .inventory = std.ArrayList([]const u8).init(allocator),
            .modified_rooms = std.StringHashMap(RoomState).init(allocator),
            .modified_npcs = std.StringHashMap(NPCState).init(allocator),
            .dropped_items = std.ArrayList(DroppedItem).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *GameState) void {
        // Free inventory strings
        for (self.inventory.items) |item_id| {
            self.allocator.free(item_id);
        }
        self.inventory.deinit();

        // Free modified rooms
        var room_iter = self.modified_rooms.iterator();
        while (room_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            var room_state = entry.value_ptr.*;
            room_state.deinit(self.allocator);
        }
        self.modified_rooms.deinit();

        // Free modified NPCs
        var npc_iter = self.modified_npcs.iterator();
        while (npc_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            var npc_state = entry.value_ptr.*;
            npc_state.deinit(self.allocator);
        }
        self.modified_npcs.deinit();

        // Free dropped items
        for (self.dropped_items.items) |*item| {
            var item_mut = item.*;
            item_mut.deinit(self.allocator);
        }
        self.dropped_items.deinit();

        // Free current room ID if allocated
        if (self.current_room_id.len > 0) {
            self.allocator.free(self.current_room_id);
        }
    }
};

/// Player state
pub const PlayerState = struct {
    name: []const u8 = "",
    health: f32 = 100.0,
    max_health: f32 = 100.0,
    mana: f32 = 50.0,
    max_mana: f32 = 50.0,
    experience: u32 = 0,
    level: u32 = 1,
    gold: u32 = 0,

    pub fn deinit(self: *PlayerState, allocator: std.mem.Allocator) void {
        if (self.name.len > 0) {
            allocator.free(self.name);
        }
    }
};

/// Room state (for rooms that have been modified)
pub const RoomState = struct {
    room_id: []const u8 = "",
    visited: bool = false,
    items_removed: std.ArrayList([]const u8), // Items taken from room
    npcs_defeated: std.ArrayList([]const u8), // NPCs defeated in room

    pub fn init(allocator: std.mem.Allocator) RoomState {
        return .{
            .items_removed = std.ArrayList([]const u8).init(allocator),
            .npcs_defeated = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *RoomState, allocator: std.mem.Allocator) void {
        for (self.items_removed.items) |item_id| {
            allocator.free(item_id);
        }
        self.items_removed.deinit();

        for (self.npcs_defeated.items) |npc_id| {
            allocator.free(npc_id);
        }
        self.npcs_defeated.deinit();

        if (self.room_id.len > 0) {
            allocator.free(self.room_id);
        }
    }
};

/// NPC state (for NPCs that have been modified)
pub const NPCState = struct {
    npc_id: []const u8 = "",
    current_room_id: []const u8 = "", // NPCs can move between rooms
    health: f32 = 100.0,
    defeated: bool = false,
    dialogue_state: u32 = 0, // Current dialogue state/progress

    pub fn deinit(self: *NPCState, allocator: std.mem.Allocator) void {
        if (self.npc_id.len > 0) {
            allocator.free(self.npc_id);
        }
        if (self.current_room_id.len > 0) {
            allocator.free(self.current_room_id);
        }
    }
};

/// Item dropped in a room
pub const DroppedItem = struct {
    item_id: []const u8 = "",
    room_id: []const u8 = "",

    pub fn deinit(self: *DroppedItem, allocator: std.mem.Allocator) void {
        if (self.item_id.len > 0) {
            allocator.free(self.item_id);
        }
        if (self.room_id.len > 0) {
            allocator.free(self.room_id);
        }
    }
};

/// Save game state to TOML file
pub fn saveGame(state: *const GameState, filepath: []const u8) !void {
    const allocator = state.allocator;

    // Build TOML content in memory first
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    const writer = buffer.writer();

    // Write header
    try writer.writeAll("# AgentiteZ Save Game\n");
    try writer.writeAll("# Auto-generated - manual edits may be lost\n\n");

    // Write game metadata
    try writer.writeAll("[game]\n");
    try writer.print("version = \"{s}\"\n", .{state.version});
    try writer.print("current_tick = {d}\n", .{state.current_tick});
    try writer.print("timestamp = {d}\n", .{state.timestamp});
    try writer.print("current_room_id = \"{s}\"\n", .{state.current_room_id});
    try writer.writeAll("\n");

    // Write player state
    try writer.writeAll("[player]\n");
    try writer.print("name = \"{s}\"\n", .{state.player.name});
    try writer.print("health = {d:.2}\n", .{state.player.health});
    try writer.print("max_health = {d:.2}\n", .{state.player.max_health});
    try writer.print("mana = {d:.2}\n", .{state.player.mana});
    try writer.print("max_mana = {d:.2}\n", .{state.player.max_mana});
    try writer.print("experience = {d}\n", .{state.player.experience});
    try writer.print("level = {d}\n", .{state.player.level});
    try writer.print("gold = {d}\n", .{state.player.gold});
    try writer.writeAll("\n");

    // Write inventory
    if (state.inventory.items.len > 0) {
        try writer.writeAll("[inventory]\n");
        try writer.writeAll("items = [");
        for (state.inventory.items, 0..) |item_id, i| {
            if (i > 0) try writer.writeAll(", ");
            try writer.print("\"{s}\"", .{item_id});
        }
        try writer.writeAll("]\n\n");
    }

    // Write modified rooms
    var room_iter = state.modified_rooms.iterator();
    while (room_iter.next()) |entry| {
        const room = entry.value_ptr.*;
        try writer.writeAll("[[room]]\n");
        try writer.print("id = \"{s}\"\n", .{room.room_id});
        try writer.print("visited = {}\n", .{room.visited});

        if (room.items_removed.items.len > 0) {
            try writer.writeAll("items_removed = [");
            for (room.items_removed.items, 0..) |item_id, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("\"{s}\"", .{item_id});
            }
            try writer.writeAll("]\n");
        }

        if (room.npcs_defeated.items.len > 0) {
            try writer.writeAll("npcs_defeated = [");
            for (room.npcs_defeated.items, 0..) |npc_id, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("\"{s}\"", .{npc_id});
            }
            try writer.writeAll("]\n");
        }

        try writer.writeAll("\n");
    }

    // Write modified NPCs
    var npc_iter = state.modified_npcs.iterator();
    while (npc_iter.next()) |entry| {
        const npc = entry.value_ptr.*;
        try writer.writeAll("[[npc]]\n");
        try writer.print("id = \"{s}\"\n", .{npc.npc_id});
        try writer.print("current_room_id = \"{s}\"\n", .{npc.current_room_id});
        try writer.print("health = {d:.2}\n", .{npc.health});
        try writer.print("defeated = {}\n", .{npc.defeated});
        try writer.print("dialogue_state = {d}\n", .{npc.dialogue_state});
        try writer.writeAll("\n");
    }

    // Write dropped items
    for (state.dropped_items.items) |item| {
        try writer.writeAll("[[dropped_item]]\n");
        try writer.print("item_id = \"{s}\"\n", .{item.item_id});
        try writer.print("room_id = \"{s}\"\n", .{item.room_id});
        try writer.writeAll("\n");
    }

    // Ensure saves directory exists
    std.fs.cwd().makeDir("saves") catch |err| {
        if (err != error.PathAlreadyExists) {
            log.err("Storage", "Failed to create saves directory: {}", .{err});
            return err;
        }
    };

    // Build full path with saves directory
    var full_path_buf: [256]u8 = undefined;
    const full_path = try std.fmt.bufPrint(&full_path_buf, "saves/{s}", .{filepath});

    // Write buffer to file
    const file = std.fs.cwd().createFile(full_path, .{}) catch |err| {
        log.err("Storage", "Failed to create save file '{s}': {}", .{ full_path, err });
        return err;
    };
    defer file.close();

    file.writeAll(buffer.items) catch |err| {
        log.err("Storage", "Failed to write to save file '{s}': {}", .{ full_path, err });
        return err;
    };

    log.info("Storage", "Game saved to '{s}'", .{full_path});
}

/// Load game state from TOML file
pub fn loadGame(allocator: std.mem.Allocator, filepath: []const u8) !GameState {
    // Build full path with saves directory
    var full_path_buf: [256]u8 = undefined;
    const full_path = try std.fmt.bufPrint(&full_path_buf, "saves/{s}", .{filepath});

    const file = std.fs.cwd().openFile(full_path, .{}) catch |err| {
        log.err("Storage", "Failed to open save file '{s}': {}", .{ full_path, err });
        return err;
    };
    defer file.close();

    const content = file.readToEndAlloc(allocator, 10 * 1024 * 1024) catch |err| {
        log.err("Storage", "Failed to read save file '{s}': {}", .{ full_path, err });
        return err;
    };
    defer allocator.free(content);

    log.info("Storage", "Loading game from '{s}'", .{full_path});

    var state = GameState.init(allocator);
    errdefer state.deinit();

    // Temporary storage for parsing
    var current_section: []const u8 = "";
    var current_room: ?RoomState = null;
    var current_npc: ?NPCState = null;
    var current_dropped_item: ?DroppedItem = null;

    // Parse line by line
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        // Check for section headers
        if (toml.isSectionHeader(line)) {
            // Save pending data before switching sections
            if (current_room) |room| {
                const room_id_key = try allocator.dupe(u8, room.room_id);
                try state.modified_rooms.put(room_id_key, room);
                current_room = null;
            }
            if (current_npc) |npc| {
                const npc_id_key = try allocator.dupe(u8, npc.npc_id);
                try state.modified_npcs.put(npc_id_key, npc);
                current_npc = null;
            }
            if (current_dropped_item) |item| {
                try state.dropped_items.append(item);
                current_dropped_item = null;
            }

            if (std.mem.eql(u8, line, "[game]")) {
                current_section = "game";
            } else if (std.mem.eql(u8, line, "[player]")) {
                current_section = "player";
            } else if (std.mem.eql(u8, line, "[inventory]")) {
                current_section = "inventory";
            } else if (std.mem.eql(u8, line, "[[room]]")) {
                current_section = "room";
                current_room = RoomState.init(allocator);
            } else if (std.mem.eql(u8, line, "[[npc]]")) {
                current_section = "npc";
                current_npc = NPCState{};
            } else if (std.mem.eql(u8, line, "[[dropped_item]]")) {
                current_section = "dropped_item";
                current_dropped_item = DroppedItem{};
            }
            continue;
        }

        // Parse key-value pairs
        if (toml.parseKeyValue(line)) |kv| {
            if (std.mem.eql(u8, current_section, "game")) {
                try parseGameKeyValue(&state, kv, allocator);
            } else if (std.mem.eql(u8, current_section, "player")) {
                try parsePlayerKeyValue(&state.player, kv, allocator);
            } else if (std.mem.eql(u8, current_section, "inventory")) {
                if (std.mem.eql(u8, kv.key, "items")) {
                    try parseInventoryArray(&state.inventory, kv.value, allocator);
                }
            } else if (std.mem.eql(u8, current_section, "room")) {
                if (current_room) |*room| {
                    try parseRoomKeyValue(room, kv, allocator);
                }
            } else if (std.mem.eql(u8, current_section, "npc")) {
                if (current_npc) |*npc| {
                    try parseNPCKeyValue(npc, kv, allocator);
                }
            } else if (std.mem.eql(u8, current_section, "dropped_item")) {
                if (current_dropped_item) |*item| {
                    try parseDroppedItemKeyValue(item, kv, allocator);
                }
            }
        }
    }

    // Save any pending data
    if (current_room) |room| {
        const room_id_key = try allocator.dupe(u8, room.room_id);
        try state.modified_rooms.put(room_id_key, room);
    }
    if (current_npc) |npc| {
        const npc_id_key = try allocator.dupe(u8, npc.npc_id);
        try state.modified_npcs.put(npc_id_key, npc);
    }
    if (current_dropped_item) |item| {
        try state.dropped_items.append(item);
    }

    std.debug.print("[LOAD] Game loaded from: {s} (Tick {d})\n", .{ filepath, state.current_tick });
    return state;
}

// Helper functions for parsing

fn parseGameKeyValue(state: *GameState, kv: toml.KeyValue, allocator: std.mem.Allocator) !void {
    if (std.mem.eql(u8, kv.key, "current_tick")) {
        state.current_tick = try toml.parseU32(kv.value);
    } else if (std.mem.eql(u8, kv.key, "timestamp")) {
        state.timestamp = try toml.parseInt32(kv.value);
    } else if (std.mem.eql(u8, kv.key, "current_room_id")) {
        const room_id = toml.trimQuotes(kv.value);
        state.current_room_id = try allocator.dupe(u8, room_id);
    }
}

fn parsePlayerKeyValue(player: *PlayerState, kv: toml.KeyValue, allocator: std.mem.Allocator) !void {
    if (std.mem.eql(u8, kv.key, "name")) {
        const name = toml.trimQuotes(kv.value);
        player.name = try allocator.dupe(u8, name);
    } else if (std.mem.eql(u8, kv.key, "health")) {
        player.health = try toml.parseF32(kv.value);
    } else if (std.mem.eql(u8, kv.key, "max_health")) {
        player.max_health = try toml.parseF32(kv.value);
    } else if (std.mem.eql(u8, kv.key, "mana")) {
        player.mana = try toml.parseF32(kv.value);
    } else if (std.mem.eql(u8, kv.key, "max_mana")) {
        player.max_mana = try toml.parseF32(kv.value);
    } else if (std.mem.eql(u8, kv.key, "experience")) {
        player.experience = try toml.parseU32(kv.value);
    } else if (std.mem.eql(u8, kv.key, "level")) {
        player.level = try toml.parseU32(kv.value);
    } else if (std.mem.eql(u8, kv.key, "gold")) {
        player.gold = try toml.parseU32(kv.value);
    }
}

fn parseInventoryArray(inventory: *std.ArrayList([]const u8), value: []const u8, allocator: std.mem.Allocator) !void {
    var items_str = value;
    // Skip the opening '['
    if (items_str.len > 0 and items_str[0] == '[') {
        items_str = items_str[1..];
    }
    // Skip the closing ']'
    if (items_str.len > 0 and items_str[items_str.len - 1] == ']') {
        items_str = items_str[0 .. items_str.len - 1];
    }

    // Parse each item ID
    var iter = std.mem.splitSequence(u8, items_str, ",");
    while (iter.next()) |item_str| {
        const trimmed = std.mem.trim(u8, item_str, " \t\"");
        if (trimmed.len == 0) continue;
        const item_id = try allocator.dupe(u8, trimmed);
        try inventory.append(item_id);
    }
}

fn parseRoomKeyValue(room: *RoomState, kv: toml.KeyValue, allocator: std.mem.Allocator) !void {
    if (std.mem.eql(u8, kv.key, "id")) {
        const room_id = toml.trimQuotes(kv.value);
        room.room_id = try allocator.dupe(u8, room_id);
    } else if (std.mem.eql(u8, kv.key, "visited")) {
        room.visited = toml.parseBool(kv.value);
    } else if (std.mem.eql(u8, kv.key, "items_removed")) {
        try parseStringArray(&room.items_removed, kv.value, allocator);
    } else if (std.mem.eql(u8, kv.key, "npcs_defeated")) {
        try parseStringArray(&room.npcs_defeated, kv.value, allocator);
    }
}

fn parseNPCKeyValue(npc: *NPCState, kv: toml.KeyValue, allocator: std.mem.Allocator) !void {
    if (std.mem.eql(u8, kv.key, "id")) {
        const npc_id = toml.trimQuotes(kv.value);
        npc.npc_id = try allocator.dupe(u8, npc_id);
    } else if (std.mem.eql(u8, kv.key, "current_room_id")) {
        const room_id = toml.trimQuotes(kv.value);
        npc.current_room_id = try allocator.dupe(u8, room_id);
    } else if (std.mem.eql(u8, kv.key, "health")) {
        npc.health = try toml.parseF32(kv.value);
    } else if (std.mem.eql(u8, kv.key, "defeated")) {
        npc.defeated = toml.parseBool(kv.value);
    } else if (std.mem.eql(u8, kv.key, "dialogue_state")) {
        npc.dialogue_state = try toml.parseU32(kv.value);
    }
}

fn parseDroppedItemKeyValue(item: *DroppedItem, kv: toml.KeyValue, allocator: std.mem.Allocator) !void {
    if (std.mem.eql(u8, kv.key, "item_id")) {
        const item_id = toml.trimQuotes(kv.value);
        item.item_id = try allocator.dupe(u8, item_id);
    } else if (std.mem.eql(u8, kv.key, "room_id")) {
        const room_id = toml.trimQuotes(kv.value);
        item.room_id = try allocator.dupe(u8, room_id);
    }
}

fn parseStringArray(array: *std.ArrayList([]const u8), value: []const u8, allocator: std.mem.Allocator) !void {
    var items_str = value;
    // Skip the opening '['
    if (items_str.len > 0 and items_str[0] == '[') {
        items_str = items_str[1..];
    }
    // Skip the closing ']'
    if (items_str.len > 0 and items_str[items_str.len - 1] == ']') {
        items_str = items_str[0 .. items_str.len - 1];
    }

    // Parse each string
    var iter = std.mem.splitSequence(u8, items_str, ",");
    while (iter.next()) |item_str| {
        const trimmed = std.mem.trim(u8, item_str, " \t\"");
        if (trimmed.len == 0) continue;
        const item = try allocator.dupe(u8, trimmed);
        try array.append(item);
    }
}
