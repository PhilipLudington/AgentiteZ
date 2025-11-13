// save_load_test.zig
// Tests for game state serialization and deserialization

const std = @import("std");
const save_load = @import("save_load.zig");
const GameState = save_load.GameState;
const PlayerState = save_load.PlayerState;
const RoomState = save_load.RoomState;
const NPCState = save_load.NPCState;
const DroppedItem = save_load.DroppedItem;

test "GameState init and deinit" {
    const allocator = std.testing.allocator;
    var state = GameState.init(allocator);
    defer state.deinit();

    try std.testing.expectEqual(@as(u32, 0), state.current_tick);
    try std.testing.expectEqual(@as(usize, 0), state.inventory.items.len);
    try std.testing.expectEqual(@as(u32, 0), state.modified_rooms.count());
}

test "Save and load empty game state" {
    const allocator = std.testing.allocator;
    const test_filename = "test_empty.toml";

    // Create empty state
    var state = GameState.init(allocator);
    state.current_tick = 42;
    state.timestamp = 1234567890;
    state.current_room_id = try allocator.dupe(u8, "tavern");
    defer state.deinit();

    // Save to file
    try save_load.saveGame(&state, test_filename);

    // Load from file
    var loaded_state = try save_load.loadGame(allocator, test_filename);
    defer loaded_state.deinit();

    // Verify loaded state
    try std.testing.expectEqual(@as(u32, 42), loaded_state.current_tick);
    try std.testing.expectEqual(@as(i64, 1234567890), loaded_state.timestamp);
    try std.testing.expectEqualStrings("tavern", loaded_state.current_room_id);

    // Clean up test file
    const full_path = "saves/" ++ test_filename;
    std.fs.cwd().deleteFile(full_path) catch {};
}

test "Save and load player state" {
    const allocator = std.testing.allocator;
    const test_filename = "test_player.toml";

    // Create state with player data
    var state = GameState.init(allocator);
    state.player = PlayerState{
        .name = try allocator.dupe(u8, "TestHero"),
        .health = 85.5,
        .max_health = 100.0,
        .mana = 30.0,
        .max_mana = 50.0,
        .experience = 1500,
        .level = 5,
        .gold = 250,
    };
    defer state.deinit();

    // Save to file
    try save_load.saveGame(&state, test_filename);

    // Load from file
    var loaded_state = try save_load.loadGame(allocator, test_filename);
    defer loaded_state.deinit();

    // Verify player state
    try std.testing.expectEqualStrings("TestHero", loaded_state.player.name);
    try std.testing.expectApproxEqAbs(@as(f32, 85.5), loaded_state.player.health, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), loaded_state.player.max_health, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 30.0), loaded_state.player.mana, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), loaded_state.player.max_mana, 0.01);
    try std.testing.expectEqual(@as(u32, 1500), loaded_state.player.experience);
    try std.testing.expectEqual(@as(u32, 5), loaded_state.player.level);
    try std.testing.expectEqual(@as(u32, 250), loaded_state.player.gold);

    // Clean up test file
    const full_path = "saves/" ++ test_filename;
    std.fs.cwd().deleteFile(full_path) catch {};
}

test "Save and load inventory" {
    const allocator = std.testing.allocator;
    const test_filename = "test_inventory.toml";

    // Create state with inventory
    var state = GameState.init(allocator);
    try state.inventory.append(try allocator.dupe(u8, "rusty_sword"));
    try state.inventory.append(try allocator.dupe(u8, "health_potion"));
    try state.inventory.append(try allocator.dupe(u8, "leather_armor"));
    defer state.deinit();

    // Save to file
    try save_load.saveGame(&state, test_filename);

    // Load from file
    var loaded_state = try save_load.loadGame(allocator, test_filename);
    defer loaded_state.deinit();

    // Verify inventory
    try std.testing.expectEqual(@as(usize, 3), loaded_state.inventory.items.len);
    try std.testing.expectEqualStrings("rusty_sword", loaded_state.inventory.items[0]);
    try std.testing.expectEqualStrings("health_potion", loaded_state.inventory.items[1]);
    try std.testing.expectEqualStrings("leather_armor", loaded_state.inventory.items[2]);

    // Clean up test file
    const full_path = "saves/" ++ test_filename;
    std.fs.cwd().deleteFile(full_path) catch {};
}

test "Save and load modified rooms" {
    const allocator = std.testing.allocator;
    const test_filename = "test_rooms.toml";

    // Create state with modified rooms
    var state = GameState.init(allocator);
    defer state.deinit();

    // Add a modified room
    var room1 = RoomState.init(allocator);
    room1.room_id = try allocator.dupe(u8, "tavern");
    room1.visited = true;
    try room1.items_removed.append(try allocator.dupe(u8, "gold_coins"));
    try room1.npcs_defeated.append(try allocator.dupe(u8, "bandit"));

    const room1_key = try allocator.dupe(u8, "tavern");
    try state.modified_rooms.put(room1_key, room1);

    // Add another modified room
    var room2 = RoomState.init(allocator);
    room2.room_id = try allocator.dupe(u8, "dungeon");
    room2.visited = true;
    try room2.items_removed.append(try allocator.dupe(u8, "key"));

    const room2_key = try allocator.dupe(u8, "dungeon");
    try state.modified_rooms.put(room2_key, room2);

    // Save to file
    try save_load.saveGame(&state, test_filename);

    // Load from file
    var loaded_state = try save_load.loadGame(allocator, test_filename);
    defer loaded_state.deinit();

    // Verify modified rooms
    try std.testing.expectEqual(@as(u32, 2), loaded_state.modified_rooms.count());

    const loaded_room1 = loaded_state.modified_rooms.get("tavern").?;
    try std.testing.expect(loaded_room1.visited);
    try std.testing.expectEqual(@as(usize, 1), loaded_room1.items_removed.items.len);
    try std.testing.expectEqualStrings("gold_coins", loaded_room1.items_removed.items[0]);
    try std.testing.expectEqual(@as(usize, 1), loaded_room1.npcs_defeated.items.len);
    try std.testing.expectEqualStrings("bandit", loaded_room1.npcs_defeated.items[0]);

    const loaded_room2 = loaded_state.modified_rooms.get("dungeon").?;
    try std.testing.expect(loaded_room2.visited);
    try std.testing.expectEqual(@as(usize, 1), loaded_room2.items_removed.items.len);
    try std.testing.expectEqualStrings("key", loaded_room2.items_removed.items[0]);

    // Clean up test file
    const full_path = "saves/" ++ test_filename;
    std.fs.cwd().deleteFile(full_path) catch {};
}

test "Save and load modified NPCs" {
    const allocator = std.testing.allocator;
    const test_filename = "test_npcs.toml";

    // Create state with modified NPCs
    var state = GameState.init(allocator);
    defer state.deinit();

    // Add a modified NPC
    const npc1 = NPCState{
        .npc_id = try allocator.dupe(u8, "innkeeper_tom"),
        .current_room_id = try allocator.dupe(u8, "tavern"),
        .health = 80.0,
        .defeated = false,
        .dialogue_state = 2,
    };
    const npc1_key = try allocator.dupe(u8, "innkeeper_tom");
    try state.modified_npcs.put(npc1_key, npc1);

    // Add another modified NPC
    const npc2 = NPCState{
        .npc_id = try allocator.dupe(u8, "goblin_warrior"),
        .current_room_id = try allocator.dupe(u8, "forest"),
        .health = 0.0,
        .defeated = true,
        .dialogue_state = 0,
    };
    const npc2_key = try allocator.dupe(u8, "goblin_warrior");
    try state.modified_npcs.put(npc2_key, npc2);

    // Save to file
    try save_load.saveGame(&state, test_filename);

    // Load from file
    var loaded_state = try save_load.loadGame(allocator, test_filename);
    defer loaded_state.deinit();

    // Verify modified NPCs
    try std.testing.expectEqual(@as(u32, 2), loaded_state.modified_npcs.count());

    const loaded_npc1 = loaded_state.modified_npcs.get("innkeeper_tom").?;
    try std.testing.expectEqualStrings("innkeeper_tom", loaded_npc1.npc_id);
    try std.testing.expectEqualStrings("tavern", loaded_npc1.current_room_id);
    try std.testing.expectApproxEqAbs(@as(f32, 80.0), loaded_npc1.health, 0.01);
    try std.testing.expectEqual(false, loaded_npc1.defeated);
    try std.testing.expectEqual(@as(u32, 2), loaded_npc1.dialogue_state);

    const loaded_npc2 = loaded_state.modified_npcs.get("goblin_warrior").?;
    try std.testing.expectEqualStrings("goblin_warrior", loaded_npc2.npc_id);
    try std.testing.expectEqualStrings("forest", loaded_npc2.current_room_id);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), loaded_npc2.health, 0.01);
    try std.testing.expectEqual(true, loaded_npc2.defeated);

    // Clean up test file
    const full_path = "saves/" ++ test_filename;
    std.fs.cwd().deleteFile(full_path) catch {};
}

test "Save and load dropped items" {
    const allocator = std.testing.allocator;
    const test_filename = "test_dropped.toml";

    // Create state with dropped items
    var state = GameState.init(allocator);
    defer state.deinit();

    try state.dropped_items.append(DroppedItem{
        .item_id = try allocator.dupe(u8, "health_potion"),
        .room_id = try allocator.dupe(u8, "tavern"),
    });

    try state.dropped_items.append(DroppedItem{
        .item_id = try allocator.dupe(u8, "iron_key"),
        .room_id = try allocator.dupe(u8, "dungeon_entrance"),
    });

    // Save to file
    try save_load.saveGame(&state, test_filename);

    // Load from file
    var loaded_state = try save_load.loadGame(allocator, test_filename);
    defer loaded_state.deinit();

    // Verify dropped items
    try std.testing.expectEqual(@as(usize, 2), loaded_state.dropped_items.items.len);

    const item1 = loaded_state.dropped_items.items[0];
    try std.testing.expectEqualStrings("health_potion", item1.item_id);
    try std.testing.expectEqualStrings("tavern", item1.room_id);

    const item2 = loaded_state.dropped_items.items[1];
    try std.testing.expectEqualStrings("iron_key", item2.item_id);
    try std.testing.expectEqualStrings("dungeon_entrance", item2.room_id);

    // Clean up test file
    const full_path = "saves/" ++ test_filename;
    std.fs.cwd().deleteFile(full_path) catch {};
}

test "Save and load complex game state" {
    const allocator = std.testing.allocator;
    const test_filename = "test_complex.toml";

    // Create a complex game state with all features
    var state = GameState.init(allocator);
    state.current_tick = 1000;
    state.timestamp = 1234567890;
    state.current_room_id = try allocator.dupe(u8, "town_square");

    // Set player state
    state.player = PlayerState{
        .name = try allocator.dupe(u8, "Adventurer"),
        .health = 75.0,
        .max_health = 100.0,
        .mana = 40.0,
        .max_mana = 60.0,
        .experience = 2500,
        .level = 8,
        .gold = 500,
    };

    // Add inventory
    try state.inventory.append(try allocator.dupe(u8, "longsword"));
    try state.inventory.append(try allocator.dupe(u8, "health_potion"));

    // Add modified rooms
    var room = RoomState.init(allocator);
    room.room_id = try allocator.dupe(u8, "cave");
    room.visited = true;
    try room.items_removed.append(try allocator.dupe(u8, "treasure_chest"));
    const room_key = try allocator.dupe(u8, "cave");
    try state.modified_rooms.put(room_key, room);

    // Add modified NPCs
    const npc = NPCState{
        .npc_id = try allocator.dupe(u8, "merchant"),
        .current_room_id = try allocator.dupe(u8, "market"),
        .health = 100.0,
        .defeated = false,
        .dialogue_state = 1,
    };
    const npc_key = try allocator.dupe(u8, "merchant");
    try state.modified_npcs.put(npc_key, npc);

    // Add dropped items
    try state.dropped_items.append(DroppedItem{
        .item_id = try allocator.dupe(u8, "shield"),
        .room_id = try allocator.dupe(u8, "armory"),
    });

    defer state.deinit();

    // Save to file
    try save_load.saveGame(&state, test_filename);

    // Load from file
    var loaded_state = try save_load.loadGame(allocator, test_filename);
    defer loaded_state.deinit();

    // Verify all aspects of the loaded state
    try std.testing.expectEqual(@as(u32, 1000), loaded_state.current_tick);
    try std.testing.expectEqualStrings("town_square", loaded_state.current_room_id);
    try std.testing.expectEqualStrings("Adventurer", loaded_state.player.name);
    try std.testing.expectEqual(@as(u32, 8), loaded_state.player.level);
    try std.testing.expectEqual(@as(usize, 2), loaded_state.inventory.items.len);
    try std.testing.expectEqual(@as(u32, 1), loaded_state.modified_rooms.count());
    try std.testing.expectEqual(@as(u32, 1), loaded_state.modified_npcs.count());
    try std.testing.expectEqual(@as(usize, 1), loaded_state.dropped_items.items.len);

    // Clean up test file
    const full_path = "saves/" ++ test_filename;
    std.fs.cwd().deleteFile(full_path) catch {};
}
