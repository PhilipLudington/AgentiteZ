# Configuration Loading System

TOML-based data loading without external dependencies (`src/data/toml.zig`, `src/config/config_loader.zig`).

## Features

- **Pure Zig implementation** - No external TOML library dependencies
- **Full escape sequence support** - Handles `\"`, `\\`, `\n`, `\t`, `\r`, `\b`, `\f`
- **Comprehensive validation** - Validates rooms, items, NPCs with detailed error reporting
- **Multiple search paths** - Graceful fallback for file locations
- **Game data loaders** - Rooms, items, NPCs from TOML files (example data included)
- **Type-safe parsing** - u32, i32, f32, bool, strings, arrays

## Usage

```zig
const config = @import("AgentiteZ").config;

// Load game data from TOML files
var rooms = try config.loadRooms(allocator);
defer {
    var iter = rooms.valueIterator();
    while (iter.next()) |room| {
        var room_mut = room.*;
        room_mut.deinit();
    }
    rooms.deinit();
}

var items = try config.loadItems(allocator);
defer {
    var iter = items.valueIterator();
    while (iter.next()) |item| {
        var item_mut = item.*;
        item_mut.deinit();
    }
    items.deinit();
}

var npcs = try config.loadNPCs(allocator);
defer {
    var iter = npcs.valueIterator();
    while (iter.next()) |npc| {
        var npc_mut = npc.*;
        npc_mut.deinit();
    }
    npcs.deinit();
}

// Access loaded data
if (rooms.get("tavern")) |tavern_room| {
    std.debug.print("Room: {s}\n", .{tavern_room.name});
    std.debug.print("Description: {s}\n", .{tavern_room.description});

    for (tavern_room.exits.items) |exit| {
        std.debug.print("  Exit {s} -> {s}\n", .{exit.direction, exit.target_room_id});
    }
}

if (items.get("health_potion")) |potion| {
    std.debug.print("Item: {s} (value: {d}, weight: {d:.1})\n",
        .{potion.name, potion.value, potion.weight});
}

if (npcs.get("innkeeper_tom")) |innkeeper| {
    std.debug.print("NPC: {s}\n", .{innkeeper.name});
    std.debug.print("Greeting: {s}\n", .{innkeeper.greeting});
}
```

## TOML File Format

```toml
# rooms.toml
[[room]]
id = "tavern"
name = "The Rusty Tankard Tavern"
description = "A cozy tavern filled with the scent of ale..."
exit_north = "town_square"
exit_east = "tavern_upstairs"

# items.toml
[[item]]
id = "health_potion"
name = "Health Potion"
description = "A small glass vial..."
weight = 0.3
value = 25
equippable = false
consumable = true

# npcs.toml
[[npc]]
id = "innkeeper_tom"
name = "Tom the Innkeeper"
description = "A portly man with a jovial face..."
greeting = "Welcome to The Rusty Tankard!"
friendly = true
health = 80
```

## Data Types

- `RoomData` - id, name, description, exits[] (direction + target_room_id)
- `ItemData` - id, name, description, weight, value, equippable, consumable
- `NPCData` - id, name, description, greeting, friendly, health

## Example Data

- 7 rooms with interconnected exits
- 10 items (weapons, armor, potions, keys, currency)
- 10 NPCs (friendly merchants, hostile enemies, quest givers)

## Low-Level TOML Utilities

Available in `@import("AgentiteZ").data.toml`:
- `parseU32()`, `parseInt32()`, `parseF32()`, `parseU8()`, `parseBool()` - Type parsing
- `trimQuotes()` - String cleaning
- `parseU8Array()`, `parseStringArray()` - Array parsing
- `loadFile()` - Multi-path file loading
- `parseKeyValue()` - TOML line parsing
- `removeInlineComment()` - Comment stripping
