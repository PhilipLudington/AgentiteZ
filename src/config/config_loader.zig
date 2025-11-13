// config_loader.zig
// TOML configuration loader for EtherMud
// Provides data structures and loaders for MUD game content

const std = @import("std");
const toml = @import("../data/toml.zig");

// ============================================================================
// Room Configuration
// ============================================================================

/// Exit direction from a room
pub const Exit = struct {
    direction: []const u8, // "north", "south", "east", "west", etc.
    target_room_id: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Exit) void {
        self.allocator.free(self.direction);
        self.allocator.free(self.target_room_id);
    }
};

/// Room data loaded from TOML config
pub const RoomData = struct {
    id: []const u8,
    name: []const u8,
    description: []const u8,
    exits: std.ArrayList(Exit),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *RoomData) void {
        self.allocator.free(self.id);
        self.allocator.free(self.name);
        self.allocator.free(self.description);
        for (self.exits.items) |*exit| {
            exit.deinit();
        }
        self.exits.deinit(self.allocator);
    }
};

/// Load rooms from TOML config
pub fn loadRooms(allocator: std.mem.Allocator) !std.StringHashMap(RoomData) {
    var room_map = std.StringHashMap(RoomData).init(allocator);

    const config_paths = [_][]const u8{
        "assets/data/rooms.toml",
        "../assets/data/rooms.toml",
        "assets/config/rooms.toml",
    };

    const content = try toml.loadFile(allocator, &config_paths, "rooms.toml") orelse {
        std.debug.print("[ConfigLoader] Using empty room database\n", .{});
        return room_map;
    };
    defer allocator.free(content);

    var lines = std.mem.splitScalar(u8, content, '\n');
    var current_id: []const u8 = "";
    var current_name: []const u8 = "";
    var current_description: []const u8 = "";
    var current_exits = std.ArrayList(Exit){};

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Skip comments and empty lines
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Check for [[room]] section
        if (std.mem.eql(u8, trimmed, "[[room]]")) {
            // Save previous room if complete
            if (current_id.len > 0) {
                const id_copy = try allocator.dupe(u8, current_id);
                const room_data = RoomData{
                    .id = id_copy,
                    .name = try allocator.dupe(u8, current_name),
                    .description = try allocator.dupe(u8, current_description),
                    .exits = current_exits,
                    .allocator = allocator,
                };
                try room_map.put(id_copy, room_data);
            }

            // Reset for new room
            current_id = "";
            current_name = "";
            current_description = "";
            current_exits = std.ArrayList(Exit){};
            continue;
        }

        // Parse key-value pairs
        if (toml.parseKeyValue(trimmed)) |kv| {
            if (std.mem.eql(u8, kv.key, "id")) {
                current_id = toml.trimQuotes(kv.value);
            } else if (std.mem.eql(u8, kv.key, "name")) {
                current_name = toml.trimQuotes(kv.value);
            } else if (std.mem.eql(u8, kv.key, "description")) {
                current_description = toml.trimQuotes(kv.value);
            } else if (std.mem.startsWith(u8, kv.key, "exit_")) {
                // Parse exit: exit_north = "room_tavern"
                const direction = kv.key[5..]; // Skip "exit_"
                const target = toml.trimQuotes(kv.value);
                const exit = Exit{
                    .direction = try allocator.dupe(u8, direction),
                    .target_room_id = try allocator.dupe(u8, target),
                    .allocator = allocator,
                };
                try current_exits.append(allocator, exit);
            }
        }
    }

    // Save last room if exists
    if (current_id.len > 0) {
        const id_copy = try allocator.dupe(u8, current_id);
        const room_data = RoomData{
            .id = id_copy,
            .name = try allocator.dupe(u8, current_name),
            .description = try allocator.dupe(u8, current_description),
            .exits = current_exits,
            .allocator = allocator,
        };
        try room_map.put(id_copy, room_data);
    }

    std.debug.print("[ConfigLoader] Loaded {d} rooms\n", .{room_map.count()});
    return room_map;
}

// ============================================================================
// Item Configuration
// ============================================================================

/// Item data loaded from TOML config
pub const ItemData = struct {
    id: []const u8,
    name: []const u8,
    description: []const u8,
    weight: f32,
    value: i32,
    equippable: bool,
    consumable: bool,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ItemData) void {
        self.allocator.free(self.id);
        self.allocator.free(self.name);
        self.allocator.free(self.description);
    }
};

/// Load items from TOML config
pub fn loadItems(allocator: std.mem.Allocator) !std.StringHashMap(ItemData) {
    var item_map = std.StringHashMap(ItemData).init(allocator);

    const config_paths = [_][]const u8{
        "assets/data/items.toml",
        "../assets/data/items.toml",
        "assets/config/items.toml",
    };

    const content = try toml.loadFile(allocator, &config_paths, "items.toml") orelse {
        std.debug.print("[ConfigLoader] Using empty item database\n", .{});
        return item_map;
    };
    defer allocator.free(content);

    var lines = std.mem.splitScalar(u8, content, '\n');
    var current_id: []const u8 = "";
    var current_name: []const u8 = "";
    var current_description: []const u8 = "";
    var current_weight: f32 = 0.0;
    var current_value: i32 = 0;
    var current_equippable: bool = false;
    var current_consumable: bool = false;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Skip comments and empty lines
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Check for [[item]] section
        if (std.mem.eql(u8, trimmed, "[[item]]")) {
            // Save previous item if complete
            if (current_id.len > 0) {
                const id_copy = try allocator.dupe(u8, current_id);
                const item_data = ItemData{
                    .id = id_copy,
                    .name = try allocator.dupe(u8, current_name),
                    .description = try allocator.dupe(u8, current_description),
                    .weight = current_weight,
                    .value = current_value,
                    .equippable = current_equippable,
                    .consumable = current_consumable,
                    .allocator = allocator,
                };
                try item_map.put(id_copy, item_data);
            }

            // Reset for new item
            current_id = "";
            current_name = "";
            current_description = "";
            current_weight = 0.0;
            current_value = 0;
            current_equippable = false;
            current_consumable = false;
            continue;
        }

        // Parse key-value pairs
        if (toml.parseKeyValue(trimmed)) |kv| {
            if (std.mem.eql(u8, kv.key, "id")) {
                current_id = toml.trimQuotes(kv.value);
            } else if (std.mem.eql(u8, kv.key, "name")) {
                current_name = toml.trimQuotes(kv.value);
            } else if (std.mem.eql(u8, kv.key, "description")) {
                current_description = toml.trimQuotes(kv.value);
            } else if (std.mem.eql(u8, kv.key, "weight")) {
                current_weight = toml.parseF32(kv.value) catch 0.0;
            } else if (std.mem.eql(u8, kv.key, "value")) {
                current_value = toml.parseInt32(kv.value) catch 0;
            } else if (std.mem.eql(u8, kv.key, "equippable")) {
                current_equippable = toml.parseBool(kv.value);
            } else if (std.mem.eql(u8, kv.key, "consumable")) {
                current_consumable = toml.parseBool(kv.value);
            }
        }
    }

    // Save last item if exists
    if (current_id.len > 0) {
        const id_copy = try allocator.dupe(u8, current_id);
        const item_data = ItemData{
            .id = id_copy,
            .name = try allocator.dupe(u8, current_name),
            .description = try allocator.dupe(u8, current_description),
            .weight = current_weight,
            .value = current_value,
            .equippable = current_equippable,
            .consumable = current_consumable,
            .allocator = allocator,
        };
        try item_map.put(id_copy, item_data);
    }

    std.debug.print("[ConfigLoader] Loaded {d} items\n", .{item_map.count()});
    return item_map;
}

// ============================================================================
// NPC Configuration
// ============================================================================

/// NPC data loaded from TOML config
pub const NPCData = struct {
    id: []const u8,
    name: []const u8,
    description: []const u8,
    greeting: []const u8,
    friendly: bool,
    health: i32,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *NPCData) void {
        self.allocator.free(self.id);
        self.allocator.free(self.name);
        self.allocator.free(self.description);
        self.allocator.free(self.greeting);
    }
};

/// Load NPCs from TOML config
pub fn loadNPCs(allocator: std.mem.Allocator) !std.StringHashMap(NPCData) {
    var npc_map = std.StringHashMap(NPCData).init(allocator);

    const config_paths = [_][]const u8{
        "assets/data/npcs.toml",
        "../assets/data/npcs.toml",
        "assets/config/npcs.toml",
    };

    const content = try toml.loadFile(allocator, &config_paths, "npcs.toml") orelse {
        std.debug.print("[ConfigLoader] Using empty NPC database\n", .{});
        return npc_map;
    };
    defer allocator.free(content);

    var lines = std.mem.splitScalar(u8, content, '\n');
    var current_id: []const u8 = "";
    var current_name: []const u8 = "";
    var current_description: []const u8 = "";
    var current_greeting: []const u8 = "";
    var current_friendly: bool = true;
    var current_health: i32 = 100;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Skip comments and empty lines
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Check for [[npc]] section
        if (std.mem.eql(u8, trimmed, "[[npc]]")) {
            // Save previous NPC if complete
            if (current_id.len > 0) {
                const id_copy = try allocator.dupe(u8, current_id);
                const npc_data = NPCData{
                    .id = id_copy,
                    .name = try allocator.dupe(u8, current_name),
                    .description = try allocator.dupe(u8, current_description),
                    .greeting = try allocator.dupe(u8, current_greeting),
                    .friendly = current_friendly,
                    .health = current_health,
                    .allocator = allocator,
                };
                try npc_map.put(id_copy, npc_data);
            }

            // Reset for new NPC
            current_id = "";
            current_name = "";
            current_description = "";
            current_greeting = "";
            current_friendly = true;
            current_health = 100;
            continue;
        }

        // Parse key-value pairs
        if (toml.parseKeyValue(trimmed)) |kv| {
            if (std.mem.eql(u8, kv.key, "id")) {
                current_id = toml.trimQuotes(kv.value);
            } else if (std.mem.eql(u8, kv.key, "name")) {
                current_name = toml.trimQuotes(kv.value);
            } else if (std.mem.eql(u8, kv.key, "description")) {
                current_description = toml.trimQuotes(kv.value);
            } else if (std.mem.eql(u8, kv.key, "greeting")) {
                current_greeting = toml.trimQuotes(kv.value);
            } else if (std.mem.eql(u8, kv.key, "friendly")) {
                current_friendly = toml.parseBool(kv.value);
            } else if (std.mem.eql(u8, kv.key, "health")) {
                current_health = toml.parseInt32(kv.value) catch 100;
            }
        }
    }

    // Save last NPC if exists
    if (current_id.len > 0) {
        const id_copy = try allocator.dupe(u8, current_id);
        const npc_data = NPCData{
            .id = id_copy,
            .name = try allocator.dupe(u8, current_name),
            .description = try allocator.dupe(u8, current_description),
            .greeting = try allocator.dupe(u8, current_greeting),
            .friendly = current_friendly,
            .health = current_health,
            .allocator = allocator,
        };
        try npc_map.put(id_copy, npc_data);
    }

    std.debug.print("[ConfigLoader] Loaded {d} NPCs\n", .{npc_map.count()});
    return npc_map;
}
