# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AgentiteZ is a modern game engine framework built with Zig 0.15.1, providing production-ready foundation systems for game development. It currently powers **Stellar Throne** (4X strategy game) and **Machinae** (factory-building game).

**Production Status:** ✅ **8.5/10 - Production Quality** (see IMPROVEMENTS.md for detailed review)

**Core Features:**
- **ECS Architecture** - Entity-Component-System with sparse-set storage, generation counters, and dependency ordering
- **UI System** - 10 widget types with automatic layout, DPI scaling, and centralized Theme system
- **Rendering** - SDL3 + bgfx for cross-platform graphics (Metal/Vulkan/DirectX/OpenGL)
- **Virtual Resolution** - Fixed 1920x1080 coordinate space with automatic aspect-ratio preservation
- **Configuration System** - Pure Zig TOML parser with validation and escape sequence support
- **Save/Load System** - Human-readable TOML-based game state persistence

**Design Philosophy:** Framework-agnostic engine layer that any game can build upon, not tied to specific game genres.

**Test Coverage:** 76+ comprehensive tests across all major systems (ECS, UI, rendering, config, input)

## Build Commands

```bash
# Build the project
zig build

# Build and run main demo (full UI showcase)
zig build run

# Run minimal example (simple window, ~140 lines)
zig build run-minimal

# Run tests
zig build test

# Run executable directly (after building)
./zig-out/bin/AgentiteZ
```

## Examples

### Minimal Example (`examples/minimal.zig`)
A bare-bones example showing:
- SDL3 window creation
- bgfx initialization
- Main render loop
- Blue screen (cornflower blue)
- ~140 lines of code

Perfect starting point for new users!

**Run with:** `zig build run-minimal`

### Full Demo (`src/main.zig`)
Complete showcase of all engine features:
- 10 UI widgets (buttons, checkboxes, sliders, text input, dropdowns, etc.)
- ECS system with bouncing entities
- Layout system with automatic positioning
- Input state visualization
- Font atlas text rendering
- Configuration loading (rooms, items, NPCs)
- Virtual resolution with DPI scaling

**Run with:** `zig build run`

## System Requirements

### macOS
- SDL3 (install via: `brew install sdl3`)
- Xcode Command Line Tools (for Metal framework)

### Git Submodules
The project uses git submodules for bgfx dependencies. If cloning fresh:
```bash
git submodule update --init --recursive
```

## Architecture

### Module Structure

The project has two main modules:
1. **AgentiteZ module** (`src/root.zig`) - Library module exposing:
   - `sdl` - SDL3 wrapper utilities
   - `bgfx` - bgfx rendering bindings
   - `stb_truetype` - TrueType font rendering
   - `ui` - Complete UI system with widgets, layout, and DPI handling
   - `ecs` - Entity-Component-System architecture
   - `platform` - Platform abstraction layer (input handling, etc.)
   - `data` - TOML parsing utilities (no external dependencies)
   - `config` - Configuration loaders for game content (rooms, items, NPCs)

2. **Executable** (`src/main.zig`) - Main application entry point that imports the AgentiteZ module

### Key Source Files

- `src/main.zig` - Main game loop, window creation, bgfx initialization
- `src/root.zig` - Module exports for SDL, bgfx, and stb_truetype wrappers
- `src/sdl.zig` - SDL3 wrapper providing Zig-friendly interfaces
- `src/bgfx.zig` - Auto-generated bgfx bindings (62K+ lines, DO NOT EDIT)
- `src/stb_truetype.zig` - stb_truetype wrapper for TrueType font rendering

### SDL3 Integration

SDL3 is linked as a system library. Key patterns:
- Raw C API accessed via `sdl.c` namespace
- Native window handles extracted via SDL3's properties system
- On macOS: Uses `SDL_PROP_WINDOW_COCOA_WINDOW_POINTER` to get NSWindow handle

### bgfx Integration

bgfx is built from source using amalgamated builds:
- **bx** (base library) - `external/bx/src/amalgamated.cpp`
- **bimg** (image library) - minimal build with `image.cpp` and `image_gnf.cpp`
- **bgfx** (rendering library) - Platform-specific:
  - macOS: Uses `amalgamated.mm` for Metal support
  - Others: Uses `amalgamated.cpp`

Compiler flags defined in `build.zig` include:
- `-DBGFX_CONFIG_MULTITHREADED=0` - Single-threaded mode
- `-DBX_CONFIG_DEBUG=0` - Debug config disabled
- Image format support flags for ASTC encoding/decoding

### Rendering Architecture

Current rendering setup:
- View 0 used as default viewport (1920x1080)
- VSync enabled via `ResetFlags_Vsync`
- Clear color: cornflower blue (0x6495edff)
- Frame submission via `bgfx.touch(0)` and `bgfx.frame(false)`

Window resize events trigger `bgfx.reset()` with new dimensions.

## Development Patterns

### Native Window Handle Extraction

macOS uses SDL3's property system to get the native NSWindow:
```zig
const props = SDL_GetWindowProperties(window);
const native_window = SDL_GetPointerProperty(
    props,
    SDL_PROP_WINDOW_COCOA_WINDOW_POINTER,
    null
);
```

For other platforms, use appropriate property constants (e.g., `SDL_PROP_WINDOW_WIN32_HWND_POINTER` for Windows).

### bgfx Initialization

Platform data must be set before calling `bgfx.init()`:
```zig
init.platformData.nwh = native_window;
init.platformData.type = bgfx.NativeWindowHandleType.Default;
init.type = bgfx.RendererType.Count; // Auto-select renderer
```

The renderer auto-selects based on platform (Metal on macOS).

### stb_truetype Integration

stb_truetype is integrated as a header-only library:
- Header file: `external/stb/stb_truetype.h`
- Zig wrapper: `src/stb_truetype.zig` provides Zig-friendly bindings
- Implementation is included via `STB_TRUETYPE_IMPLEMENTATION` define in the wrapper

Key features available:
- **Font loading**: `initFont()` to initialize font from TTF/OTF data
- **Glyph metrics**: `getCodepointHMetrics()`, `getCodepointBox()`, etc.
- **Bitmap rendering**: `getCodepointBitmap()` for rasterizing glyphs
- **SDF rendering**: `getCodepointSDF()` for distance field fonts
- **Texture packing**: `bakeFontBitmap()` for simple atlas generation, or `packBegin()`/`packFontRanges()` for advanced packing

Usage pattern:
```zig
const stb = @import("AgentiteZ").stb_truetype;

var font_info: stb.FontInfo = undefined;
_ = stb.initFont(&font_info, font_data.ptr, 0);

const scale = stb.scaleForPixelHeight(&font_info, pixel_height);
// Use font_info and scale to render glyphs...
```

### ECS (Entity-Component-System)

The engine features a professional ECS architecture ported from StellarThroneZig:

**Core Components:**
- **Entity** (`src/ecs/entity.zig`) - Unique ID + generation counter for safe recycling
- **ComponentArray** (`src/ecs/component.zig`) - Sparse-set storage for cache-friendly iteration
- **System** (`src/ecs/system.zig`) - VTable-based polymorphic systems
- **World** (`src/ecs/world.zig`) - Central coordinator for entities and systems

**Key Features:**
- **Generation Counters** - Prevents use-after-free with recycled entity IDs
- **Sparse-Set Pattern** - O(1) component lookup, O(n) cache-optimal iteration
- **Component Recycling** - Efficient memory reuse with free list
- **System Dependencies** - Topological sorting with automatic cycle detection
- **System Registry** - Ordered execution with dependency graph support

**Usage Pattern:**
```zig
const ecs = @import("AgentiteZ").ecs;

// Create world
var world = ecs.World.init(allocator);
defer world.deinit();

// Create entities
const player = try world.createEntity();
const enemy = try world.createEntity();

// Create component storage
var positions = ecs.ComponentArray(Position).init(allocator);
defer positions.deinit();

// Add components
try positions.add(player, .{ .x = 100, .y = 200 });
try positions.add(enemy, .{ .x = 300, .y = 400 });

// Iterate components (cache-friendly)
var iter = positions.iterator();
while (iter.next()) |entry| {
    entry.component.x += 1; // Move right
}

// Register systems with dependencies
const physics_id = try world.registerSystem(ecs.System.init(&physics_system));
const movement_id = try world.registerSystemWithOptions(
    ecs.System.init(&movement_system),
    .{ .depends_on = &.{physics_id} }
);
const render_id = try world.registerSystemWithOptions(
    ecs.System.init(&render_system),
    .{ .depends_on = &.{movement_id} }
);

// Systems execute in correct order: physics -> movement -> render
try world.update(delta_time);
```

### UI Layout System

Automatic widget positioning with the Layout system (`src/ui/layout.zig`):

**Features:**
- **Vertical/Horizontal** stacking
- **Alignment** - start, center, end
- **Spacing** - configurable gaps between widgets
- **Padding** - container margins

**Usage Pattern:**
```zig
const ui = @import("AgentiteZ").ui;

// Create vertical layout with center alignment
const panel_rect = ui.Rect.init(100, 100, 400, 600);
var layout = ui.Layout.vertical(panel_rect, .center)
    .withSpacing(10)
    .withPadding(20);

// Widgets auto-advance
const button1_rect = layout.nextRect(150, 40);
const button2_rect = layout.nextRect(150, 40);
const button3_rect = layout.nextRect(150, 40);

// Manual positioning
const pos = layout.nextPosition(200, 50);
layout.advance(200, 50);
```

### Virtual Resolution System

Fixed 1920x1080 coordinate space with two complementary systems:

#### RenderScale (`src/ui/dpi.zig`)
High-level system for UI coordinate conversion with DPI awareness:

**Features:**
- Resolution-independent game code (1920x1080 virtual space)
- Automatic aspect-ratio preservation
- Letterboxing on ultra-wide displays
- Automatic mouse coordinate conversion
- DPI scaling support

**Usage Pattern:**
```zig
const ui = @import("AgentiteZ").ui;

// Create from window info
const window_info = ui.WindowInfo{
    .width = window_width,
    .height = window_height,
    .dpi_scale = dpi_scale,
};
const render_scale = ui.RenderScale.init(window_info);

// Convert mouse coordinates
const virtual_mouse = render_scale.screenToVirtual(physical_x, physical_y);

// All game code uses 1920x1080 coordinates
ui.button(&ctx, "Click Me", ui.Rect.init(960, 540, 200, 50));
```

#### Viewport System (`src/renderer/viewport.zig`)
Low-level letterbox viewport calculation for bgfx rendering:

**Purpose:**
- Calculate viewport position and size for maintaining aspect ratio
- Determine letterbox bar placement (horizontal or vertical)
- Provide scale factor for rendering

**Usage Pattern:**
```zig
const renderer = @import("AgentiteZ").renderer;

// Calculate letterbox viewport
const viewport = renderer.calculateLetterboxViewport(
    physical_width,
    physical_height,
    1920, // virtual width
    1080, // virtual height
);

// Set bgfx viewport with letterboxing
bgfx.setViewRect(
    0,
    viewport.x,
    viewport.y,
    viewport.width,
    viewport.height,
);

// Or use with Renderer2D
renderer_2d.setViewportOffset(viewport.x, viewport.y);
```

**Difference:**
- **RenderScale**: UI coordinate system with DPI awareness (high-level)
- **Viewport**: bgfx rendering viewport with letterboxing (low-level)
- Both work together for complete resolution-independent rendering

### Input State Abstraction

Clean event-driven to immediate-mode input API (`src/platform/input_state.zig`):

**Features:**
- **Persistent state** - One instance per game loop, not rebuilt each frame
- **Press vs Down** - Distinguish between `isKeyPressed()` (one frame) and `isKeyDown()` (held)
- **Frame lifecycle** - Automatic reset of transient states via `beginFrame()`
- **All mouse buttons** - Support for left, right, middle buttons
- **Text input** - Built-in buffering for UI widgets with overflow detection
- **SDL event handling** - Automatic processing via `handleEvent()`

**Usage Pattern:**
```zig
const platform = @import("AgentiteZ").platform;

// Initialize once
var input_state = platform.InputState.init(allocator);
defer input_state.deinit();

// Main loop
while (running) {
    // Clear transient states
    input_state.beginFrame();

    // Process events
    while (SDL_PollEvent(&event)) {
        try input_state.handleEvent(&event);
        // Handle quit, resize, etc.
    }

    // Query input (immediate-mode)
    if (input_state.isKeyPressed(.escape)) {
        // Only true on frame of press
        running = false;
    }
    if (input_state.isMouseButtonDown()) {
        // True while held
        const pos = input_state.getMousePosition();
    }

    // Convert to UI InputState for widgets
    const ui_input = input_state.toUIInputState();
}
```

**Key Methods:**
- `isMouseButtonPressed()` / `isMouseButtonDown()` - Left mouse
- `isMouseRightButtonPressed()` / `isMouseRightButtonDown()` - Right mouse
- `isMouseMiddleButtonPressed()` / `isMouseMiddleButtonDown()` - Middle mouse
- `isKeyPressed(key)` / `isKeyDown(key)` - Keyboard
- `getMousePosition()` - Current mouse coordinates
- `getMouseWheelMove()` - Wheel delta this frame
- `toUIInputState()` - Convert to UI widget format

### Configuration Loading System

TOML-based data loading without external dependencies (`src/data/toml.zig`, `src/config/config_loader.zig`):

**Features:**
- **Pure Zig implementation** - No external TOML library dependencies
- **Full escape sequence support** - Handles `\"`, `\\`, `\n`, `\t`, `\r`, `\b`, `\f`
- **Comprehensive validation** - Validates rooms, items, NPCs with detailed error reporting
- **Multiple search paths** - Graceful fallback for file locations
- **Game data loaders** - Rooms, items, NPCs from TOML files (example data included for demonstration)
- **Type-safe parsing** - u32, i32, f32, bool, strings, arrays

**Usage Pattern:**
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

    // Iterate exits
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

**TOML File Format:**
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

**Data Types:**
- `RoomData` - id, name, description, exits[] (direction + target_room_id)
- `ItemData` - id, name, description, weight, value, equippable, consumable
- `NPCData` - id, name, description, greeting, friendly, health

**Example Data:**
- 7 rooms with interconnected exits
- 10 items (weapons, armor, potions, keys, currency)
- 10 NPCs (friendly merchants, hostile enemies, quest givers)

**Low-Level TOML Utilities:**
Available in `@import("AgentiteZ").data.toml`:
- `parseU32()`, `parseInt32()`, `parseF32()`, `parseU8()`, `parseBool()` - Type parsing
- `trimQuotes()` - String cleaning
- `parseU8Array()`, `parseStringArray()` - Array parsing
- `loadFile()` - Multi-path file loading
- `parseKeyValue()` - TOML line parsing
- `removeInlineComment()` - Comment stripping

### Save/Load System

Game state persistence with TOML serialization (`src/save_load.zig`):

**Features:**
- **GameState struct** - Complete game state representation (example data structure)
- **Human-readable format** - TOML files for easy debugging and manual editing
- **Selective persistence** - Only saves modified state (rooms, NPCs, items)
- **Player state** - Health, mana, level, experience, gold, inventory
- **World state** - Modified rooms, NPC positions/health, dropped items
- **Automatic directory creation** - Creates `saves/` directory automatically

**Usage Pattern:**
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

// Save game to file (creates saves/ directory automatically)
try save_load.saveGame(&state, "savegame.toml");

// Load game from file
var loaded_state = try save_load.loadGame(allocator, "savegame.toml");
defer loaded_state.deinit();

// Access loaded data
std.debug.print("Player: {s} (Level {d})\n", .{loaded_state.player.name, loaded_state.player.level});
std.debug.print("Health: {d:.1}/{d:.1}\n", .{loaded_state.player.health, loaded_state.player.max_health});
std.debug.print("Current room: {s}\n", .{loaded_state.current_room_id});
```

**Data Structures:**
- `GameState` - Complete game state with metadata, player, world state
- `PlayerState` - name, health, max_health, mana, max_mana, experience, level, gold
- `RoomState` - room_id, visited, items_removed[], npcs_defeated[]
- `NPCState` - npc_id, current_room_id, health, defeated, dialogue_state
- `DroppedItem` - item_id, room_id

**Save File Format:**
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

**Key Features:**
- **Saves directory** - All saves stored in `saves/` subdirectory
- **Selective state** - Only modified rooms/NPCs are saved (efficiency)
- **Array support** - Inventory, items_removed, npcs_defeated stored as arrays
- **Null handling** - Proper optional field support
- **Memory management** - All strings properly allocated/freed
- **Error handling** - Comprehensive error propagation

**Tests:**
- 8 comprehensive tests covering all data structures
- Test save/load round-trip for all state types
- Memory leak detection via std.testing.allocator
- All tests pass successfully

### Font Atlas System 🎯 **HiDPI-Aware Bitmap Atlas**

Professional font rendering with **HiDPI/Retina support** and optimized bitmap packing (`src/renderer/font_atlas.zig`):

#### 📦 **Bitmap Mode** (Production-Ready, HiDPI-Aware)

**Perfect for:** All UI rendering, HiDPI displays, Retina/4K/5K monitors

**Currently Used in Main Demo** - Provides crystal-clear text on all displays with automatic DPI scaling.

Optimized font rendering with pre-baked glyph atlas and full HiDPI support:

**Features:**
- ✅ **HiDPI/Retina Support** - Automatic DPI scaling for crisp text on 2x/3x displays
- ✅ **Pre-baked 94 printable ASCII glyphs** - All standard chars rendered at load time
- ✅ **Fast text measurement** - No stb_truetype calls during rendering
- ✅ **Proper glyph metrics** - UV coords, offsets, advances for perfect positioning
- ✅ **16x16 atlas grid** - Efficient packing of 256 characters
- ✅ **RGBA8 format** - Metal-compatible texture format (glyph in alpha channel)
- ✅ **Text truncation** - Ellipsis support for overflow detection
- ✅ **~50ms startup** - Fast atlas generation

**Usage Pattern (with HiDPI):**
```zig
const renderer = @import("AgentiteZ").renderer;

// Get DPI scale from SDL3 (comparing logical vs physical pixels)
var pixel_width: c_int = undefined;
var pixel_height: c_int = undefined;
_ = c.SDL_GetWindowSizeInPixels(window, &pixel_width, &pixel_height);
const dpi_scale = @as(f32, @floatFromInt(pixel_width)) / @as(f32, @floatFromInt(window_width));

// Load font at DPI-scaled size for sharp rendering on Retina
const base_font_size: f32 = 24.0;
const dpi_font_size = base_font_size * dpi_scale; // 48.0 on 2x Retina

var font_atlas = try renderer.FontAtlas.init(
    allocator,
    "external/bgfx/examples/runtime/font/roboto-regular.ttf",
    dpi_font_size, // DPI-adjusted font size
    false // flip_uv
);
defer font_atlas.deinit();

// Wire up to Renderer2D
renderer_2d.setExternalFontAtlas(&font_atlas);

// Fast text measurement (no stb calls)
const text = "Hello, World!";
const width = font_atlas.measureText(text);
std.debug.print("Text width: {d:.1}px\n", .{width});

// Text measurement with ellipsis truncation
const max_width: f32 = 200.0;
const result = font_atlas.measureTextWithEllipsis(text, max_width);
if (result.truncated_len < text.len) {
    // Text was truncated, render: text[0..result.truncated_len] + "..."
    std.debug.print("Truncated to {d} chars (width: {d:.1}px)\n",
        .{result.truncated_len, result.width});
}

// Access individual glyph metrics
const glyph = font_atlas.getGlyph('A');
std.debug.print("Glyph 'A': UV=({d:.3},{d:.3})-({d:.3},{d:.3}), advance={d:.2}px\n",
    .{glyph.uv_x0, glyph.uv_y0, glyph.uv_x1, glyph.uv_y1, glyph.advance});

// Use texture in rendering
const texture_handle = font_atlas.texture;
// ... set texture for rendering with bgfx
```

**Data Structures:**
- `FontAtlas` - Complete atlas with texture handle, 256 glyphs, metrics
- `Glyph` - UV coordinates (uv_x0, uv_y0, uv_x1, uv_y1), offsets, size, advance

**Glyph Structure:**
```zig
pub const Glyph = struct {
    // UV coordinates in atlas (normalized 0-1)
    uv_x0: f32,
    uv_y0: f32,
    uv_x1: f32,
    uv_y1: f32,

    // Offset from baseline
    offset_x: f32,
    offset_y: f32,

    // Size of glyph in pixels
    width: f32,
    height: f32,

    // Horizontal advance for cursor positioning
    advance: f32,
};
```

**Atlas Generation Process:**
1. Load TrueType font file with stb_truetype
2. Calculate font metrics (ascent, descent, line height)
3. Render all 256 ASCII glyphs to grayscale atlas (16x16 grid)
4. Calculate UV coordinates for each glyph
5. Convert grayscale to RGBA8 (white RGB, glyph in alpha)
6. Upload to bgfx texture

**Key Features:**
- **16x16 grid layout** - 256 glyphs in square atlas
- **Automatic sizing** - Atlas size based on font size + padding
- **Missing glyph handling** - Empty glyph info for unsupported characters
- **Debug output** - Logs glyph rendering stats and sample characters
- **Row wrapping** - Glyphs wrap to next row when needed

**Performance Benefits:**
- **No runtime font rasterization** - All glyphs pre-rendered
- **Fast measurement** - Simple advance summation, no stb calls
- **GPU-friendly** - Single texture for all text rendering
- **Cache-friendly** - All glyph data in contiguous array

**Available Fonts:**
The project includes several fonts from bgfx examples:
- `external/bgfx/examples/runtime/font/roboto-regular.ttf` - Clean sans-serif
- `external/bgfx/examples/runtime/font/droidsans.ttf` - Android default
- `external/bgfx/examples/runtime/font/droidsansmono.ttf` - Monospace

**HiDPI Support Details:**
The engine includes full HiDPI/Retina display support:
- SDL3 window created with `SDL_WINDOW_HIGH_PIXEL_DENSITY` flag
- DPI scale calculated from logical vs physical pixel dimensions
- bgfx initialized and viewport set to physical pixel dimensions
- Font atlas generated at DPI-scaled size (e.g., 48px on 2x Retina)
- UI coordinates remain in logical 1920x1080 virtual space

**Tests:**
- 10 comprehensive tests covering all algorithms
- Glyph struct layout and UV calculation
- Atlas size calculation for 256 glyphs
- Text measurement logic with known advances
- Ellipsis truncation logic
- Line height calculation from font metrics
- RGBA conversion for Metal compatibility
- Glyph packing grid layout
- All tests pass successfully

---

#### 🔬 **Experimental: Runtime SDF Mode**

**Status:** Implemented but not recommended for production use. SDF rendering quality was found to be inferior to bitmap atlas on HiDPI displays.

Runtime SDF (Signed Distance Field) is available via `FontAtlas.initSDF()` for zoom-heavy applications, but bitmap atlas with proper DPI scaling provides superior quality for fixed-scale UI. SDF code and shaders remain in the codebase for future experimentation.

## Recent Improvements (All Complete)

The engine has undergone comprehensive improvements documented in `IMPROVEMENTS.md`:

### ✅ Completed High Priority Items
1. **Theme System** - Centralized UI theming with 40+ color and dimension properties
2. **Widget ID Best Practices** - Comprehensive documentation preventing state collision

### ✅ Completed Medium Priority Items
3. **TOML Escape Sequences** - Full support for `\"`, `\\`, `\n`, `\t`, `\r`, `\b`, `\f`
4. **Configuration Validation** - Validates rooms, items, NPCs with detailed error reporting
5. **ECS System Dependencies** - Topological sorting with automatic cycle detection
6. **Text Input Overflow Detection** - Warning logs when 64-byte buffer overflows

### ✅ Completed Low Priority Items
7. **Deprecated Code Removal** - Removed unused OldFontAtlas code
8. **Build System Refactoring** - Eliminated 230 lines of duplication

### ✅ Comprehensive Test Coverage Added
- **UI Widget Tests** - 37 tests covering all 10 widget types
- **Input State Tests** - 21 tests covering edge cases and frame boundaries
- **ECS Error Tests** - 18 tests covering error conditions across all ECS components
- **Total New Tests** - 76+ comprehensive tests with zero memory leaks

**Result:** Engine upgraded from good foundation to **production-quality 8.5/10**.

## Important Notes

- `src/bgfx.zig` is auto-generated from the bgfx C API - modifications should be made to the bgfx binding generator, not this file
- The build system links multiple frameworks on macOS: Metal, QuartzCore, Cocoa, IOKit
- External dependencies are in `external/`:
  - `bx`, `bimg`, `bgfx` - git submodules for rendering
  - `stb` - stb_truetype header-only library (downloaded directly)
- Zig 0.15.1 is the target version - newer Zig releases may have breaking changes
- For detailed code review and improvement history, see `IMPROVEMENTS.md`
- For widget ID collision prevention, see `docs/WIDGET_ID_BEST_PRACTICES.md`
