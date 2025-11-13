// config_loader_test.zig
// Tests for the config loading system

const std = @import("std");
const config_loader = @import("config_loader.zig");

test "load rooms from TOML" {
    var room_map = try config_loader.loadRooms(std.testing.allocator);
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
    var item_map = try config_loader.loadItems(std.testing.allocator);
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
    var npc_map = try config_loader.loadNPCs(std.testing.allocator);
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
