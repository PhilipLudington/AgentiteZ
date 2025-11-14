// loader_test.zig
// Tests for the config loading system

const std = @import("std");
const loader = @import("loader.zig");

test "load rooms from TOML" {
    var room_map = try loader.loadRooms(std.testing.allocator);
    defer {
        var iter = room_map.valueIterator();
        while (iter.next()) |room| {
            var room_mut = room.*;
            room_mut.deinit();
        }
        room_map.deinit();
    }

    // Verify we loaded some rooms
    std.debug.print("\n[Test] Loaded {d} rooms\n", .{room_map.count()});

    // If we found the config file, verify specific rooms exist
    if (room_map.count() > 0) {
        // Check for tavern
        if (room_map.get("tavern")) |tavern| {
            try std.testing.expectEqualStrings("The Rusty Tankard Tavern", tavern.name);
            try std.testing.expect(tavern.exits.items.len >= 2); // Should have at least 2 exits
            std.debug.print("[Test] ✓ Tavern loaded with {d} exits\n", .{tavern.exits.items.len});
        }

        // Check for town_square
        if (room_map.get("town_square")) |square| {
            try std.testing.expectEqualStrings("Town Square", square.name);
            try std.testing.expect(square.exits.items.len >= 4); // Should have 4+ exits
            std.debug.print("[Test] ✓ Town Square loaded with {d} exits\n", .{square.exits.items.len});
        }
    }
}

test "load items from TOML" {
    var item_map = try loader.loadItems(std.testing.allocator);
    defer {
        var iter = item_map.valueIterator();
        while (iter.next()) |item| {
            var item_mut = item.*;
            item_mut.deinit();
        }
        item_map.deinit();
    }

    // Verify we loaded some items
    std.debug.print("\n[Test] Loaded {d} items\n", .{item_map.count()});

    // If we found the config file, verify specific items exist
    if (item_map.count() > 0) {
        // Check for health potion
        if (item_map.get("health_potion")) |potion| {
            try std.testing.expectEqualStrings("Health Potion", potion.name);
            try std.testing.expect(potion.consumable);
            try std.testing.expect(!potion.equippable);
            std.debug.print("[Test] ✓ Health Potion: consumable={}, value={d}\n", .{ potion.consumable, potion.value });
        }

        // Check for iron sword
        if (item_map.get("iron_sword")) |sword| {
            try std.testing.expectEqualStrings("Iron Sword", sword.name);
            try std.testing.expect(sword.equippable);
            try std.testing.expect(!sword.consumable);
            std.debug.print("[Test] ✓ Iron Sword: equippable={}, weight={d:.1}\n", .{ sword.equippable, sword.weight });
        }
    }
}

test "load NPCs from TOML" {
    var npc_map = try loader.loadNPCs(std.testing.allocator);
    defer {
        var iter = npc_map.valueIterator();
        while (iter.next()) |npc| {
            var npc_mut = npc.*;
            npc_mut.deinit();
        }
        npc_map.deinit();
    }

    // Verify we loaded some NPCs
    std.debug.print("\n[Test] Loaded {d} NPCs\n", .{npc_map.count()});

    // If we found the config file, verify specific NPCs exist
    if (npc_map.count() > 0) {
        // Check for innkeeper
        if (npc_map.get("innkeeper_tom")) |innkeeper| {
            try std.testing.expectEqualStrings("Tom the Innkeeper", innkeeper.name);
            try std.testing.expect(innkeeper.friendly);
            std.debug.print("[Test] ✓ Innkeeper: friendly={}, health={d}\n", .{ innkeeper.friendly, innkeeper.health });
        }

        // Check for hostile NPC
        if (npc_map.get("goblin_raider")) |goblin| {
            try std.testing.expectEqualStrings("Goblin Raider", goblin.name);
            try std.testing.expect(!goblin.friendly);
            std.debug.print("[Test] ✓ Goblin: friendly={}, health={d}\n", .{ goblin.friendly, goblin.health });
        }
    }
}

// ============================================================================
// Validation Tests
// ============================================================================

test "validate valid rooms" {
    // Load real config data
    var room_map = try loader.loadRooms(std.testing.allocator);
    defer {
        var iter = room_map.valueIterator();
        while (iter.next()) |room| {
            var room_mut = room.*;
            room_mut.deinit();
        }
        room_map.deinit();
    }

    // Validate all loaded rooms
    if (room_map.count() > 0) {
        var errors = try loader.validateRooms(&room_map);
        defer errors.deinit();

        std.debug.print("\n[Test] Validated {d} rooms, found {d} errors\n", .{ room_map.count(), errors.count() });
        try std.testing.expect(errors.count() == 0);
    }
}

test "validate room with missing required fields" {
    var room_map = std.StringHashMap(loader.RoomData).init(std.testing.allocator);
    defer room_map.deinit();

    // Create room with empty name
    var invalid_room = loader.RoomData{
        .id = try std.testing.allocator.dupe(u8, "test_room"),
        .name = try std.testing.allocator.dupe(u8, ""), // Empty name
        .description = try std.testing.allocator.dupe(u8, "Test description"),
        .exits = std.ArrayList(loader.Exit){},
        .allocator = std.testing.allocator,
    };
    defer invalid_room.deinit();

    try room_map.put(invalid_room.id, invalid_room);

    var errors = try loader.validateRooms(&room_map);
    defer errors.deinit();

    std.debug.print("\n[Test] Empty name validation: {d} errors found\n", .{errors.count()});
    try std.testing.expect(errors.count() > 0);
}

test "validate room with dangling exit reference" {
    var room_map = std.StringHashMap(loader.RoomData).init(std.testing.allocator);
    defer room_map.deinit();

    // Create room with exit pointing to non-existent room
    var exits = std.ArrayList(loader.Exit){};
    const bad_exit = loader.Exit{
        .direction = try std.testing.allocator.dupe(u8, "north"),
        .target_room_id = try std.testing.allocator.dupe(u8, "nonexistent_room"),
        .allocator = std.testing.allocator,
    };
    try exits.append(std.testing.allocator, bad_exit);

    var room = loader.RoomData{
        .id = try std.testing.allocator.dupe(u8, "test_room"),
        .name = try std.testing.allocator.dupe(u8, "Test Room"),
        .description = try std.testing.allocator.dupe(u8, "A test room"),
        .exits = exits,
        .allocator = std.testing.allocator,
    };
    defer room.deinit();

    try room_map.put(room.id, room);

    var errors = try loader.validateRooms(&room_map);
    defer errors.deinit();

    std.debug.print("\n[Test] Dangling exit validation: {d} errors found\n", .{errors.count()});
    try std.testing.expect(errors.count() > 0);
}

test "validate valid items" {
    // Load real config data
    var item_map = try loader.loadItems(std.testing.allocator);
    defer {
        var iter = item_map.valueIterator();
        while (iter.next()) |item| {
            var item_mut = item.*;
            item_mut.deinit();
        }
        item_map.deinit();
    }

    // Validate all loaded items
    if (item_map.count() > 0) {
        var errors = try loader.validateItems(&item_map);
        defer errors.deinit();

        std.debug.print("\n[Test] Validated {d} items, found {d} errors\n", .{ item_map.count(), errors.count() });
        try std.testing.expect(errors.count() == 0);
    }
}

test "validate item with negative weight" {
    var item_map = std.StringHashMap(loader.ItemData).init(std.testing.allocator);
    defer item_map.deinit();

    // Create item with negative weight
    var invalid_item = loader.ItemData{
        .id = try std.testing.allocator.dupe(u8, "bad_item"),
        .name = try std.testing.allocator.dupe(u8, "Bad Item"),
        .description = try std.testing.allocator.dupe(u8, "This item has invalid weight"),
        .weight = -5.0, // Invalid
        .value = 10,
        .equippable = false,
        .consumable = false,
        .allocator = std.testing.allocator,
    };
    defer invalid_item.deinit();

    try item_map.put(invalid_item.id, invalid_item);

    var errors = try loader.validateItems(&item_map);
    defer errors.deinit();

    std.debug.print("\n[Test] Negative weight validation: {d} errors found\n", .{errors.count()});
    try std.testing.expect(errors.count() > 0);
}

test "validate item with negative value" {
    var item_map = std.StringHashMap(loader.ItemData).init(std.testing.allocator);
    defer item_map.deinit();

    // Create item with negative value
    var invalid_item = loader.ItemData{
        .id = try std.testing.allocator.dupe(u8, "bad_item"),
        .name = try std.testing.allocator.dupe(u8, "Bad Item"),
        .description = try std.testing.allocator.dupe(u8, "This item has invalid value"),
        .weight = 1.0,
        .value = -50, // Invalid
        .equippable = false,
        .consumable = false,
        .allocator = std.testing.allocator,
    };
    defer invalid_item.deinit();

    try item_map.put(invalid_item.id, invalid_item);

    var errors = try loader.validateItems(&item_map);
    defer errors.deinit();

    std.debug.print("\n[Test] Negative value validation: {d} errors found\n", .{errors.count()});
    try std.testing.expect(errors.count() > 0);
}

test "validate valid NPCs" {
    // Load real config data
    var npc_map = try loader.loadNPCs(std.testing.allocator);
    defer {
        var iter = npc_map.valueIterator();
        while (iter.next()) |npc| {
            var npc_mut = npc.*;
            npc_mut.deinit();
        }
        npc_map.deinit();
    }

    // Validate all loaded NPCs
    if (npc_map.count() > 0) {
        var errors = try loader.validateNPCs(&npc_map);
        defer errors.deinit();

        std.debug.print("\n[Test] Validated {d} NPCs, found {d} errors\n", .{ npc_map.count(), errors.count() });
        try std.testing.expect(errors.count() == 0);
    }
}

test "validate NPC with invalid health" {
    var npc_map = std.StringHashMap(loader.NPCData).init(std.testing.allocator);
    defer npc_map.deinit();

    // Create NPC with zero health
    var invalid_npc = loader.NPCData{
        .id = try std.testing.allocator.dupe(u8, "dead_npc"),
        .name = try std.testing.allocator.dupe(u8, "Dead NPC"),
        .description = try std.testing.allocator.dupe(u8, "This NPC has no health"),
        .greeting = try std.testing.allocator.dupe(u8, "..."),
        .friendly = true,
        .health = 0, // Invalid
        .allocator = std.testing.allocator,
    };
    defer invalid_npc.deinit();

    try npc_map.put(invalid_npc.id, invalid_npc);

    var errors = try loader.validateNPCs(&npc_map);
    defer errors.deinit();

    std.debug.print("\n[Test] Zero health validation: {d} errors found\n", .{errors.count()});
    try std.testing.expect(errors.count() > 0);
}

test "validate NPC with negative health" {
    var npc_map = std.StringHashMap(loader.NPCData).init(std.testing.allocator);
    defer npc_map.deinit();

    // Create NPC with negative health
    var invalid_npc = loader.NPCData{
        .id = try std.testing.allocator.dupe(u8, "negative_npc"),
        .name = try std.testing.allocator.dupe(u8, "Negative NPC"),
        .description = try std.testing.allocator.dupe(u8, "This NPC has negative health"),
        .greeting = try std.testing.allocator.dupe(u8, "Hello!"),
        .friendly = true,
        .health = -10, // Invalid
        .allocator = std.testing.allocator,
    };
    defer invalid_npc.deinit();

    try npc_map.put(invalid_npc.id, invalid_npc);

    var errors = try loader.validateNPCs(&npc_map);
    defer errors.deinit();

    std.debug.print("\n[Test] Negative health validation: {d} errors found\n", .{errors.count()});
    try std.testing.expect(errors.count() > 0);
}

test "validate NPC with empty greeting" {
    var npc_map = std.StringHashMap(loader.NPCData).init(std.testing.allocator);
    defer npc_map.deinit();

    // Create NPC with empty greeting
    var invalid_npc = loader.NPCData{
        .id = try std.testing.allocator.dupe(u8, "silent_npc"),
        .name = try std.testing.allocator.dupe(u8, "Silent NPC"),
        .description = try std.testing.allocator.dupe(u8, "This NPC has no greeting"),
        .greeting = try std.testing.allocator.dupe(u8, ""), // Empty
        .friendly = true,
        .health = 100,
        .allocator = std.testing.allocator,
    };
    defer invalid_npc.deinit();

    try npc_map.put(invalid_npc.id, invalid_npc);

    var errors = try loader.validateNPCs(&npc_map);
    defer errors.deinit();

    std.debug.print("\n[Test] Empty greeting validation: {d} errors found\n", .{errors.count()});
    try std.testing.expect(errors.count() > 0);
}

test "validate all configuration data" {
    // Load all config data
    var rooms = try loader.loadRooms(std.testing.allocator);
    defer {
        var iter = rooms.valueIterator();
        while (iter.next()) |room| {
            var room_mut = room.*;
            room_mut.deinit();
        }
        rooms.deinit();
    }

    var items = try loader.loadItems(std.testing.allocator);
    defer {
        var iter = items.valueIterator();
        while (iter.next()) |item| {
            var item_mut = item.*;
            item_mut.deinit();
        }
        items.deinit();
    }

    var npcs = try loader.loadNPCs(std.testing.allocator);
    defer {
        var iter = npcs.valueIterator();
        while (iter.next()) |npc| {
            var npc_mut = npc.*;
            npc_mut.deinit();
        }
        npcs.deinit();
    }

    // Validate everything
    if (rooms.count() > 0 or items.count() > 0 or npcs.count() > 0) {
        var errors = try loader.validateAll(&rooms, &items, &npcs);
        defer errors.deinit();

        std.debug.print("\n[Test] Validated all config data: {d} total errors\n", .{errors.count()});
        try std.testing.expect(errors.count() == 0);
    }
}

test "ValidationErrors collection" {
    var errors = loader.ValidationErrors.init(std.testing.allocator);
    defer errors.deinit();

    // Initially empty
    try std.testing.expect(!errors.hasErrors());
    try std.testing.expect(errors.count() == 0);

    // Add some errors
    try errors.add("Error 1");
    try errors.add("Error 2");
    try errors.add("Error 3");

    // Verify state
    try std.testing.expect(errors.hasErrors());
    try std.testing.expect(errors.count() == 3);

    std.debug.print("\n[Test] ValidationErrors: {d} errors collected\n", .{errors.count()});
}
