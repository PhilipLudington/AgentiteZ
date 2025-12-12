# Save/Load System

Game state persistence with TOML serialization (`src/save_load.zig`).

## Features

- **GameState struct** - Complete game state representation
- **Human-readable format** - TOML files for easy debugging and manual editing
- **Selective persistence** - Only saves modified state (rooms, NPCs, items)
- **Player state** - Health, mana, level, experience, gold, inventory
- **World state** - Modified rooms, NPC positions/health, dropped items
- **Automatic directory creation** - Creates `saves/` directory automatically

## Usage

```zig
const save_load = @import("AgentiteZ").save_load;

// Create game state
var state = save_load.GameState.init(allocator);
defer state.deinit();

// Set player state
state.player = save_load.PlayerState{
    .name = try allocator.dupe(u8, "Hero"),
    .health = 85.0,
    .max_health = 100.0,
    .mana = 40.0,
    .max_mana = 50.0,
    .experience = 1500,
    .level = 5,
    .gold = 250,
};

// Set current room
state.current_room_id = try allocator.dupe(u8, "tavern");
state.current_tick = 1000;
state.timestamp = std.time.timestamp();

// Add items to inventory
try state.inventory.append(try allocator.dupe(u8, "rusty_sword"));
try state.inventory.append(try allocator.dupe(u8, "health_potion"));

// Mark a room as visited with items removed
var room = save_load.RoomState.init(allocator);
room.room_id = try allocator.dupe(u8, "cave");
room.visited = true;
try room.items_removed.append(try allocator.dupe(u8, "treasure_chest"));
try room.npcs_defeated.append(try allocator.dupe(u8, "bandit"));
const room_key = try allocator.dupe(u8, "cave");
try state.modified_rooms.put(room_key, room);

// Track modified NPC state
const npc = save_load.NPCState{
    .npc_id = try allocator.dupe(u8, "merchant"),
    .current_room_id = try allocator.dupe(u8, "market"),
    .health = 100.0,
    .defeated = false,
    .dialogue_state = 1,
};
const npc_key = try allocator.dupe(u8, "merchant");
try state.modified_npcs.put(npc_key, npc);

// Track dropped items
try state.dropped_items.append(save_load.DroppedItem{
    .item_id = try allocator.dupe(u8, "shield"),
    .room_id = try allocator.dupe(u8, "armory"),
});

// Save game to file
try save_load.saveGame(&state, "savegame.toml");

// Load game from file
var loaded_state = try save_load.loadGame(allocator, "savegame.toml");
defer loaded_state.deinit();

// Access loaded data
std.debug.print("Player: {s} (Level {d})\n", .{loaded_state.player.name, loaded_state.player.level});
std.debug.print("Health: {d:.1}/{d:.1}\n", .{loaded_state.player.health, loaded_state.player.max_health});
std.debug.print("Current room: {s}\n", .{loaded_state.current_room_id});
```

## Data Structures

- `GameState` - Complete game state with metadata, player, world state
- `PlayerState` - name, health, max_health, mana, max_mana, experience, level, gold
- `RoomState` - room_id, visited, items_removed[], npcs_defeated[]
- `NPCState` - npc_id, current_room_id, health, defeated, dialogue_state
- `DroppedItem` - item_id, room_id

## Save File Format

```toml
# AgentiteZ Save Game
# Auto-generated - manual edits may be lost

[game]
version = "1.0"
current_tick = 1000
timestamp = 1234567890
current_room_id = "tavern"

[player]
name = "Hero"
health = 85.00
max_health = 100.00
mana = 40.00
max_mana = 50.00
experience = 1500
level = 5
gold = 250

[inventory]
items = ["rusty_sword", "health_potion"]

[[room]]
id = "cave"
visited = true
items_removed = ["treasure_chest"]
npcs_defeated = ["bandit"]

[[npc]]
id = "merchant"
current_room_id = "market"
health = 100.00
defeated = false
dialogue_state = 1

[[dropped_item]]
item_id = "shield"
room_id = "armory"
```

## Key Features

- **Saves directory** - All saves stored in `saves/` subdirectory
- **Selective state** - Only modified rooms/NPCs are saved (efficiency)
- **Array support** - Inventory, items_removed, npcs_defeated stored as arrays
- **Null handling** - Proper optional field support
- **Memory management** - All strings properly allocated/freed
- **Error handling** - Comprehensive error propagation

## Tests

8 comprehensive tests covering all data structures, save/load round-trip, and memory leak detection.
