// loader.zig
// TOML configuration loader for AgentiteZ
// Provides data structures and loaders for MUD game content

const std = @import("std");
const toml = @import("../data/toml.zig");
const log = @import("../log.zig");

// ============================================================================
// Validation Error Types
// ============================================================================

/// Validation error type for configuration data
pub const ValidationError = error{
    MissingRequiredField,
    InvalidValue,
    DanglingReference,
    EmptyField,
};

/// Result of validating a single piece of data
pub const ValidationResult = struct {
    valid: bool,
    error_message: ?[]const u8 = null,

    pub fn ok() ValidationResult {
        return .{ .valid = true };
    }

    pub fn err(message: []const u8) ValidationResult {
        return .{ .valid = false, .error_message = message };
    }
};

/// Collection of validation errors
pub const ValidationErrors = struct {
    errors: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ValidationErrors {
        return .{
            .errors = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ValidationErrors) void {
        for (self.errors.items) |err_msg| {
            self.allocator.free(err_msg);
        }
        self.errors.deinit();
    }

    pub fn add(self: *ValidationErrors, message: []const u8) !void {
        const msg_copy = try self.allocator.dupe(u8, message);
        try self.errors.append(msg_copy);
    }

    pub fn hasErrors(self: *const ValidationErrors) bool {
        return self.errors.items.len > 0;
    }

    pub fn count(self: *const ValidationErrors) usize {
        return self.errors.items.len;
    }
};

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

// ============================================================================
// Validation Functions
// ============================================================================

/// Validate a single room's data
pub fn validateRoom(room: *const RoomData, all_rooms: *const std.StringHashMap(RoomData), errors: *ValidationErrors) !void {
    // Check required fields are not empty
    if (room.id.len == 0) {
        try errors.add("Room has empty ID");
    }
    if (room.name.len == 0) {
        const msg = try std.fmt.allocPrint(errors.allocator, "Room '{s}' has empty name", .{room.id});
        defer errors.allocator.free(msg);
        try errors.add(msg);
    }
    if (room.description.len == 0) {
        const msg = try std.fmt.allocPrint(errors.allocator, "Room '{s}' has empty description", .{room.id});
        defer errors.allocator.free(msg);
        try errors.add(msg);
    }

    // Validate all exits point to valid rooms
    for (room.exits.items) |exit| {
        if (exit.target_room_id.len == 0) {
            const msg = try std.fmt.allocPrint(errors.allocator, "Room '{s}' has exit '{s}' with empty target", .{ room.id, exit.direction });
            defer errors.allocator.free(msg);
            try errors.add(msg);
            continue;
        }

        if (!all_rooms.contains(exit.target_room_id)) {
            const msg = try std.fmt.allocPrint(errors.allocator, "Room '{s}' has exit '{s}' pointing to non-existent room '{s}'", .{ room.id, exit.direction, exit.target_room_id });
            defer errors.allocator.free(msg);
            try errors.add(msg);
        }
    }
}

/// Validate all rooms in the map
pub fn validateRooms(rooms: *const std.StringHashMap(RoomData)) !ValidationErrors {
    var errors = ValidationErrors.init(rooms.allocator);

    var iter = rooms.valueIterator();
    while (iter.next()) |room| {
        try validateRoom(room, rooms, &errors);
    }

    if (errors.hasErrors()) {
        std.debug.print("[Validation] Found {d} room validation error(s):\n", .{errors.count()});
        for (errors.errors.items) |err_msg| {
            std.debug.print("  - {s}\n", .{err_msg});
        }
    }

    return errors;
}

/// Validate a single item's data
pub fn validateItem(item: *const ItemData, errors: *ValidationErrors) !void {
    // Check required fields are not empty
    if (item.id.len == 0) {
        try errors.add("Item has empty ID");
    }
    if (item.name.len == 0) {
        const msg = try std.fmt.allocPrint(errors.allocator, "Item '{s}' has empty name", .{item.id});
        defer errors.allocator.free(msg);
        try errors.add(msg);
    }
    if (item.description.len == 0) {
        const msg = try std.fmt.allocPrint(errors.allocator, "Item '{s}' has empty description", .{item.id});
        defer errors.allocator.free(msg);
        try errors.add(msg);
    }

    // Validate numeric ranges
    if (item.weight < 0.0) {
        const msg = try std.fmt.allocPrint(errors.allocator, "Item '{s}' has negative weight: {d:.2}", .{ item.id, item.weight });
        defer errors.allocator.free(msg);
        try errors.add(msg);
    }
    if (item.value < 0) {
        const msg = try std.fmt.allocPrint(errors.allocator, "Item '{s}' has negative value: {d}", .{ item.id, item.value });
        defer errors.allocator.free(msg);
        try errors.add(msg);
    }

    // Warn about unrealistic values (but don't fail validation)
    if (item.weight > 1000.0) {
        const msg = try std.fmt.allocPrint(errors.allocator, "Item '{s}' has unusually high weight: {d:.2} (warning)", .{ item.id, item.weight });
        defer errors.allocator.free(msg);
        try errors.add(msg);
    }
}

/// Validate all items in the map
pub fn validateItems(items: *const std.StringHashMap(ItemData)) !ValidationErrors {
    var errors = ValidationErrors.init(items.allocator);

    var iter = items.valueIterator();
    while (iter.next()) |item| {
        try validateItem(item, &errors);
    }

    if (errors.hasErrors()) {
        std.debug.print("[Validation] Found {d} item validation error(s):\n", .{errors.count()});
        for (errors.errors.items) |err_msg| {
            std.debug.print("  - {s}\n", .{err_msg});
        }
    }

    return errors;
}

/// Validate a single NPC's data
pub fn validateNPC(npc: *const NPCData, errors: *ValidationErrors) !void {
    // Check required fields are not empty
    if (npc.id.len == 0) {
        try errors.add("NPC has empty ID");
    }
    if (npc.name.len == 0) {
        const msg = try std.fmt.allocPrint(errors.allocator, "NPC '{s}' has empty name", .{npc.id});
        defer errors.allocator.free(msg);
        try errors.add(msg);
    }
    if (npc.description.len == 0) {
        const msg = try std.fmt.allocPrint(errors.allocator, "NPC '{s}' has empty description", .{npc.id});
        defer errors.allocator.free(msg);
        try errors.add(msg);
    }
    if (npc.greeting.len == 0) {
        const msg = try std.fmt.allocPrint(errors.allocator, "NPC '{s}' has empty greeting", .{npc.id});
        defer errors.allocator.free(msg);
        try errors.add(msg);
    }

    // Validate health is positive
    if (npc.health <= 0) {
        const msg = try std.fmt.allocPrint(errors.allocator, "NPC '{s}' has invalid health: {d} (must be > 0)", .{ npc.id, npc.health });
        defer errors.allocator.free(msg);
        try errors.add(msg);
    }

    // Warn about unusual health values
    if (npc.health > 10000) {
        const msg = try std.fmt.allocPrint(errors.allocator, "NPC '{s}' has unusually high health: {d} (warning)", .{ npc.id, npc.health });
        defer errors.allocator.free(msg);
        try errors.add(msg);
    }
}

/// Validate all NPCs in the map
pub fn validateNPCs(npcs: *const std.StringHashMap(NPCData)) !ValidationErrors {
    var errors = ValidationErrors.init(npcs.allocator);

    var iter = npcs.valueIterator();
    while (iter.next()) |npc| {
        try validateNPC(npc, &errors);
    }

    if (errors.hasErrors()) {
        std.debug.print("[Validation] Found {d} NPC validation error(s):\n", .{errors.count()});
        for (errors.errors.items) |err_msg| {
            std.debug.print("  - {s}\n", .{err_msg});
        }
    }

    return errors;
}

/// Validate all configuration data (rooms, items, NPCs)
pub fn validateAll(
    rooms: *const std.StringHashMap(RoomData),
    items: *const std.StringHashMap(ItemData),
    npcs: *const std.StringHashMap(NPCData),
) !ValidationErrors {
    var all_errors = ValidationErrors.init(rooms.allocator);

    // Validate rooms
    var room_errors = try validateRooms(rooms);
    defer room_errors.deinit();
    for (room_errors.errors.items) |err_msg| {
        try all_errors.add(err_msg);
    }

    // Validate items
    var item_errors = try validateItems(items);
    defer item_errors.deinit();
    for (item_errors.errors.items) |err_msg| {
        try all_errors.add(err_msg);
    }

    // Validate NPCs
    var npc_errors = try validateNPCs(npcs);
    defer npc_errors.deinit();
    for (npc_errors.errors.items) |err_msg| {
        try all_errors.add(err_msg);
    }

    if (all_errors.hasErrors()) {
        std.debug.print("\n[Validation] Total validation errors: {d}\n", .{all_errors.count()});
    } else {
        std.debug.print("\n[Validation] All configuration data is valid!\n", .{});
    }

    return all_errors;
}
