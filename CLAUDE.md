# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Important Notes

- **NEVER commit PLAN.md** - This is a local planning document that should not be committed to the repository.

## Project Overview

AgentiteZ is a modern game engine framework built with Zig 0.15.1, providing production-ready foundation systems for game development. It currently powers **Stellar Throne** (4X strategy game) and **Machinae** (factory-building game).

**Production Status:** ✅ **8.5/10 - Production Quality** (see IMPROVEMENTS.md for detailed review)

**Core Features:**
- **ECS Architecture** - Entity-Component-System with sparse-set storage, generation counters, and dependency ordering
- **UI System** - 10 widget types with automatic layout, DPI scaling, and centralized Theme system
- **Rendering** - SDL3 + bgfx for cross-platform graphics (Metal/Vulkan/DirectX/OpenGL)
- **Audio System** - Sound effects and music playback with mixing, volume control, and 2D panning
- **Camera System** - 2D camera with zoom, rotation, smooth follow, bounds, and screen shake
- **Animation System** - Frame-based sprite animation with clips, events, and state machine
- **Tilemap System** - Chunk-based tile storage with multiple layers, collision, and auto-tiling
- **Spatial Index** - Grid-based spatial hashing for O(1) entity lookup and fast proximity queries
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
   - `audio` - Sound effects and music playback system
   - `camera` - 2D camera system with zoom, follow, and shake
   - `animation` - Frame-based sprite animation with state machine
   - `tilemap` - Chunk-based tilemap with layers, collision, and auto-tiling
   - `spatial` - Grid-based spatial indexing for fast proximity queries

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

### Audio System

Sound effects and music playback built on SDL3 (`src/audio.zig`):

**Features:**
- **Sound effects** - Load and play WAV files with automatic format conversion
- **Background music** - Looping music playback with pause/resume
- **Volume control** - Master, sound effects, and music channel volumes
- **2D panning** - Stereo positioning (-1.0 left to +1.0 right)
- **Channel pooling** - 32 simultaneous sound channels
- **Thread-safe** - Mutex-protected callback for audio mixing

**Usage Pattern:**
```zig
const audio = @import("AgentiteZ").audio;

// Initialize audio system
var audio_system = try audio.AudioSystem.init(allocator);
defer audio_system.deinit();

// Load sounds
var explosion = try audio_system.loadSound("sounds/explosion.wav");
defer explosion.deinit();

var music = try audio_system.loadMusic("music/theme.wav");
defer music.deinit();

// Play sound with options
const handle = audio_system.playSoundEx(&explosion, .{
    .volume = 0.8,
    .pan = -0.5, // Slightly left
    .loop = false,
});

// Play background music (loops by default)
audio_system.playMusic(&music);

// Control music
audio_system.pauseMusic();
audio_system.resumeMusic();
audio_system.setMusicChannelVolume(0.7);

// Control master volume
audio_system.setMasterVolume(0.9);

// Check if sound is still playing
if (audio_system.isPlaying(handle)) {
    // Still playing...
}

// Stop specific sound
audio_system.stopSound(handle);

// Stop all sounds
audio_system.stopAllSounds();
```

**Volume Hierarchy:**
- `master_volume` - Affects all audio output
- `sound_volume` - Affects all sound effects (multiplied with master)
- `global_music_volume` - Affects music playback (multiplied with master)
- Per-sound `volume` - Individual sound volume (multiplied with sound_volume and master)
- Per-music `music_volume` - Current track volume (multiplied with global_music_volume and master)

**Data Structures:**
- `AudioSystem` - Main system managing channels, mixing, and playback
- `Sound` - Loaded sound effect (converted to float32 stereo)
- `Music` - Loaded music track (converted to float32 stereo)
- `SoundHandle` - Handle to a playing sound instance
- `PlayOptions` - Volume, pan, and loop settings

**Technical Details:**
- Output format: 48kHz, stereo, float32
- Audio is mixed in a callback using SDL3's audio stream API
- All input formats automatically converted to device format
- Channel stealing when all 32 channels are in use

### Camera System

2D camera system for game rendering (`src/camera.zig`):

**Features:**
- **Position, zoom, rotation** - Full 2D camera transform
- **Smooth follow** - Frame-rate independent lerp to target position
- **Camera bounds** - Constrain camera to world limits
- **Screen shake** - Configurable intensity, duration, decay, and frequency
- **Coordinate conversion** - World-to-screen and screen-to-world transforms
- **Visibility testing** - Check if points/rects are visible in camera view
- **View matrix** - Get transformation matrix for bgfx rendering

**Usage Pattern:**
```zig
const camera = @import("AgentiteZ").camera;

// Create camera with default settings (centered at origin, zoom 1.0)
var cam = camera.Camera2D.init(.{});

// Or with custom initial position and zoom
var cam = camera.Camera2D.init(.{
    .position = camera.Vec2.init(500.0, 300.0),
    .zoom = 1.5,
    .rotation = 0.0,
});

// Set smooth follow target (camera will lerp to target each update)
cam.setTarget(player_position);
cam.setFollowSmoothing(0.1); // 0 = instant, higher = slower

// Set camera movement bounds (world limits)
cam.setBounds(camera.CameraBounds.fromRect(0, 0, 4000, 3000));

// Set zoom limits
cam.setZoomLimits(0.5, 4.0);

// Update camera each frame (handles follow, bounds, shake)
cam.update(delta_time);

// Screen shake effect
cam.shake(.{
    .intensity = 10.0,  // Max pixels offset
    .duration = 0.3,    // Seconds
    .decay = true,      // Fade out over duration
    .frequency = 30.0,  // Oscillations per second
});

// Coordinate conversion (uses 1920x1080 virtual resolution)
const screen_pos = cam.worldToScreen(entity_x, entity_y);
const world_pos = cam.screenToWorld(mouse_x, mouse_y);

// Visibility checks
if (cam.isPointVisible(enemy_x, enemy_y)) {
    // Render enemy
}
if (cam.isRectVisible(tile_x, tile_y, tile_w, tile_h)) {
    // Render tile
}

// Get visible world area (for culling)
const visible = cam.getVisibleRect();
// visible.x, visible.y, visible.width, visible.height

// Camera controls
cam.setZoom(2.0);
cam.adjustZoom(0.1);     // Add to zoom
cam.multiplyZoom(1.1);   // Multiply zoom (good for scroll wheel)
cam.zoomTowards(world_point, 0.5); // Zoom keeping point stationary

cam.move(camera.Vec2.init(10.0, 0.0));      // Move in world space
cam.moveScreen(camera.Vec2.init(10.0, 0.0)); // Move in screen space
cam.centerOn(camera.Vec2.init(500.0, 300.0)); // Instant reposition

cam.setRotation(std.math.pi / 4.0);  // Radians
cam.setRotationDegrees(45.0);         // Degrees

// Get view matrix for bgfx (4x4 row-major)
const view_matrix = cam.getViewMatrix();
```

**Data Structures:**
- `Camera2D` - Main camera with position, zoom, rotation, follow, bounds, shake
- `Vec2` - 2D vector with math operations (add, sub, scale, lerp, rotate, normalize)
- `CameraBounds` - World bounds for constraining camera movement
- `ShakeConfig` - Screen shake parameters (intensity, duration, decay, frequency)

**Integration with Renderer2D:**
The Camera2D system works with virtual resolution (1920x1080). To integrate with Renderer2D:
1. Transform world positions using `worldToScreen()` before drawing
2. Use `getVisibleRect()` for efficient culling of off-screen objects
3. Use `screenToWorld()` to convert mouse input to world coordinates

**Tests:** 25 comprehensive tests covering Vec2 math, bounds, zoom, follow, shake, and coordinate conversion.

### Animation System

Frame-based sprite animation system (`src/animation.zig`):

**Features:**
- **Animation clips** - Define animations by frame range, fps, and loop settings
- **Playback controls** - Play, pause, unpause, stop, reverse playback
- **Playback speed** - Variable speed multiplier (slow motion, fast forward)
- **Frame events** - Callbacks triggered at specific frames (footsteps, impacts)
- **Progress tracking** - Get current frame, progress (0-1), finished state
- **State machine** - Automatic transitions between animations with conditions
- **Blend transitions** - Cross-fade between animations

**Usage Pattern - Basic Animation:**
```zig
const animation = @import("AgentiteZ").animation;

// Create animation state
var anim = animation.Animation.init(allocator);
defer anim.deinit();

// Define clips (frame indices in sprite sheet)
try anim.addClip("idle", .{ .start = 0, .end = 3, .fps = 8, .loop = true });
try anim.addClip("walk", .{ .start = 4, .end = 11, .fps = 12, .loop = true });
try anim.addClip("attack", .{ .start = 12, .end = 17, .fps = 15, .loop = false });

// Play animation
anim.play("idle");

// Update each frame
anim.update(delta_time);

// Get current frame for rendering
const frame = anim.getCurrentFrame();

// Playback controls
anim.pause();
anim.unpause();
anim.stop();
anim.playReversed("walk");

// Speed control
anim.setSpeed(2.0);  // 2x speed
anim.setSpeed(0.5);  // Half speed

// Check state
if (anim.isFinished()) {
    // Non-looping animation completed
}
const progress = anim.getProgress();  // 0.0 to 1.0
```

**Usage Pattern - Frame Events:**
```zig
const events = [_]animation.FrameEvent{
    .{ .frame = 0, .name = "start" },
    .{ .frame = 4, .name = "footstep_left" },
    .{ .frame = 8, .name = "footstep_right" },
};

try anim.addClip("walk", .{
    .start = 0,
    .end = 11,
    .fps = 12,
    .loop = true,
    .events = &events,
});

// Set callback for events
anim.setEventCallback(onAnimationEvent, user_data);

fn onAnimationEvent(event_name: []const u8, user_data: ?*anyopaque) void {
    if (std.mem.eql(u8, event_name, "footstep_left")) {
        // Play footstep sound
    }
}
```

**Usage Pattern - State Machine:**
```zig
var sm = animation.AnimationStateMachine.init(allocator);
defer sm.deinit();

// Add clips
try sm.addClip("idle", .{ .start = 0, .end = 3, .fps = 8, .loop = true });
try sm.addClip("walk", .{ .start = 4, .end = 11, .fps = 12, .loop = true });
try sm.addClip("attack", .{ .start = 12, .end = 17, .fps = 15, .loop = false });

// Add automatic transitions
try sm.addTransition("attack", "idle", .{
    .on_finish = true,  // Transition when attack finishes
    .blend_duration = 0.1,  // 100ms cross-fade
});

// Conditional transitions (with callback)
try sm.addTransition("idle", "walk", .{
    .condition = isMoving,
    .user_data = &player,
});

// Set initial state
sm.setState("idle");

// Update each frame
sm.update(delta_time);

// Manual transition
sm.transitionTo("attack", 0.05);  // 50ms blend

// Get current frame for rendering
const frame = sm.getCurrentFrame();

// During blend transitions
if (sm.getBlendProgress()) |progress| {
    const from_frame = sm.getBlendFromFrame().?;
    // Blend between from_frame and getCurrentFrame() by progress
}
```

**Data Structures:**
- `Animation` - Animation state with clips, playback, and events
- `AnimationClip` - Clip definition (name, start/end frame, fps, loop, events)
- `AnimationStateMachine` - State machine for automatic transitions
- `FrameEvent` - Event triggered at specific frame
- `PlaybackState` - stopped, playing, paused

**Tests:** 20 comprehensive tests covering clips, playback, looping, events, and state machine.

### Tilemap System

Chunk-based tilemap system for efficient large map storage and rendering (`src/tilemap.zig`):

**Features:**
- **Chunk-based storage** - 32x32 tiles per chunk for memory efficiency
- **Sparse allocation** - Only allocates chunks when tiles are placed
- **Multiple layers** - Up to 16 layers (ground, vegetation, objects, etc.)
- **Tile collision** - Per-tile collision flags (solid, water, pit, platform, ladder, damage, trigger)
- **Auto-tiling** - 8-neighbor based terrain transitions
- **Tileset management** - UV calculation, collision flags, auto-tile terrain types
- **Camera integration** - Efficient culling with visible tile/chunk range queries
- **Coordinate conversion** - World-to-tile and tile-to-world transforms

**Usage Pattern - Basic Tilemap:**
```zig
const tilemap = @import("AgentiteZ").tilemap;

// Create tilemap (100x100 tiles, 32px per tile)
var map = tilemap.Tilemap.init(allocator, .{
    .width = 100,
    .height = 100,
    .tile_width = 32,
    .tile_height = 32,
});
defer map.deinit();

// Add layers
const ground = try map.addLayer("ground");
const objects = try map.addLayerWithOptions("objects", .{
    .z_order = 1,
    .visible = true,
    .opacity = 1.0,
});

// Set tiles by ID
try map.setTileID(ground, 5, 5, 1);  // Tile ID 1 at position (5, 5)
try map.setTileID(objects, 5, 5, 10);

// Set tiles with full control
try map.setTile(ground, 10, 10, .{
    .id = 2,
    .collision = .{ .solid = true },
});

// Fill a region
try map.fill(ground, 0, 0, 50, 50, .{ .id = 1 });

// Get tile info
const tile = map.getTile(ground, 5, 5);
const tile_id = map.getTileID(ground, 5, 5);
```

**Usage Pattern - Tileset:**
```zig
// Create tileset from texture atlas
var tileset = try tilemap.Tileset.init(allocator, .{
    .tile_width = 32,
    .tile_height = 32,
    .texture_width = 512,
    .texture_height = 512,
    .spacing = 0,
    .margin = 0,
});
defer tileset.deinit();

// Set collision for specific tiles
tileset.setCollision(1, .{ .solid = true });  // Tile 1 is solid
tileset.setCollisionRange(10, 20, .{ .solid = true, .water = true });

// Set auto-tile terrain types
tileset.setAutoTileTerrain(1, 1);  // Tile 1 is terrain type 1

// Attach tileset to map
map.setTileset(&tileset);

// Get UV coordinates for rendering
if (tileset.getTileUV(1)) |uv| {
    // uv.u0, uv.v0, uv.u1, uv.v1 for texture mapping
}
```

**Usage Pattern - Collision Detection:**
```zig
// Check collision at world coordinates
if (map.isSolid(player_x, player_y)) {
    // Block movement
}

// Get detailed collision flags
const flags = map.checkCollision(player_x, player_y);
if (flags.water) {
    // Player is in water
}
if (flags.damage) {
    // Player takes damage
}

// Check collision at tile coordinates
const tile_flags = map.checkCollisionTile(5, 5);
```

**Usage Pattern - Camera Integration:**
```zig
const camera = @import("AgentiteZ").camera;

var cam = camera.Camera2D.init(.{
    .position = camera.Vec2.init(500.0, 300.0),
    .zoom = 1.0,
});

// Get visible tile range for culling
const range = map.getVisibleTileRange(&cam);
// range.min_x, range.min_y, range.max_x, range.max_y

// Get visible chunk range (more efficient for large maps)
const chunks = map.getVisibleChunkRange(&cam);

// Iterate visible tiles efficiently
if (map.visibleTileIterator(ground, &cam)) |*iter| {
    while (iter.next()) |entry| {
        // entry.x, entry.y - tile coordinates
        // entry.tile - Tile struct
        // entry.world_x, entry.world_y - world position
        renderTile(entry);
    }
}
```

**Usage Pattern - Coordinate Conversion:**
```zig
// World to tile coordinates
const coord = map.worldToTile(150.0, 200.0);
// coord.x, coord.y

// Tile to world (top-left corner)
const world_pos = map.tileToWorld(5, 5);
// world_pos.x, world_pos.y

// Tile to world (center)
const center = map.tileToWorldCenter(5, 5);

// Get map world bounds
const bounds = map.getWorldBounds();
// bounds.x, bounds.y, bounds.width, bounds.height

// Using TileCoord directly
const tile_coord = tilemap.TileCoord.fromWorld(100.0, 75.0, 32);
const world = tile_coord.toWorld(32);
const is_valid = tile_coord.isInBounds(100, 100);
```

**Usage Pattern - Auto-Tiling:**
```zig
// Define auto-tile rule (maps neighbor configurations to tile variants)
var variant_map: [256]u8 = undefined;
// ... populate variant_map based on neighbor configurations

try map.addAutoTileRule(.{
    .terrain = 1,  // Terrain type
    .base_tile_id = 1,  // Base tile ID for this terrain
    .variant_map = variant_map,
});

// Update auto-tiling for a region after placing tiles
map.updateAutoTileRegion(ground, 0, 0, 50, 50);

// Update single tile
map.updateAutoTile(ground, 5, 5);

// Get neighbor mask for custom logic
const mask = map.getNeighborMask(ground, 5, 5, 1);
// mask.n, mask.s, mask.e, mask.w, mask.ne, mask.nw, mask.se, mask.sw
```

**Data Structures:**
- `Tilemap` - Main tilemap with layers, tileset, and auto-tile rules
- `TileLayer` - Single layer with sparse chunk storage
- `TileChunk` - 32x32 tile block (allocated on demand)
- `Tile` - Tile data (id, collision, auto_tile_variant, user_data)
- `Tileset` - Texture atlas with UV coords, collision, and terrain data
- `TileCoord` - Integer tile coordinate with conversion helpers
- `TileUV` - UV coordinates for texture mapping
- `CollisionFlags` - Packed collision flags (solid, water, pit, etc.)
- `NeighborMask` - 8-bit neighbor configuration for auto-tiling

**Constants:**
- `CHUNK_SIZE` = 32 (tiles per chunk dimension)
- `MAX_LAYERS` = 16
- `EMPTY_TILE` = 0 (tile ID for empty)

**Tests:** 18 comprehensive tests covering chunks, layers, collision, UV calculation, coordinate conversion, and visibility culling.

### Spatial Index

High-performance grid-based spatial indexing for fast proximity queries (`src/spatial.zig`):

**Features:**
- **Grid-based spatial hashing** - O(1) insertion and removal
- **Generic entity ID type** - Works with u32, u64, or custom ID types
- **Position tracking** - Automatic tracking for efficient updates
- **Range queries** - Query by radius or axis-aligned bounding box
- **Nearest neighbor** - Find closest entity or K-nearest neighbors
- **Statistics** - Built-in profiling for cell distribution

**Usage Pattern - Basic Operations:**
```zig
const spatial = @import("AgentiteZ").spatial;

// Create spatial index with 64-pixel cells
var index = spatial.SpatialIndex(u32).init(allocator, .{ .cell_size = 64.0 });
defer index.deinit();

// Insert entities at positions
try index.insert(player_id, spatial.Vec2.init(100.0, 200.0));
try index.insert(enemy_id, spatial.Vec2.init(150.0, 180.0));

// Update position (more efficient than remove+insert for moving entities)
try index.update(player_id, spatial.Vec2.init(105.0, 205.0));

// Remove entity
const old_pos = index.remove(enemy_id);

// Check if entity exists
if (index.contains(player_id)) {
    const pos = index.getPosition(player_id).?;
}
```

**Usage Pattern - Radius Query:**
```zig
// Find all entities within 100 units of a point
var nearby = try index.queryRadius(
    spatial.Vec2.init(100.0, 100.0),
    100.0,  // radius
    allocator,
);
defer nearby.deinit();

for (nearby.items) |entry| {
    // entry.id - entity ID
    // entry.position - Vec2 position
    handleNearbyEntity(entry.id, entry.position);
}
```

**Usage Pattern - Rectangle Query:**
```zig
// Find all entities within a bounding box
const search_area = spatial.AABB.fromRect(0.0, 0.0, 200.0, 200.0);
var entities = try index.queryRect(search_area, allocator);
defer entities.deinit();

for (entities.items) |entry| {
    processEntity(entry.id);
}
```

**Usage Pattern - Nearest Neighbor:**
```zig
// Find single nearest entity within max radius
if (index.findNearest(spatial.Vec2.init(100.0, 100.0), 500.0)) |nearest| {
    // nearest.id - entity ID
    // nearest.position - Vec2 position
    // nearest.distance - distance from query point
    attackTarget(nearest.id);
}

// Find K nearest entities
var k_nearest = try index.findKNearest(
    spatial.Vec2.init(100.0, 100.0),
    5,      // k - number of results
    500.0,  // max radius
    allocator,
);
defer k_nearest.deinit();

// Results are sorted by distance (closest first)
for (k_nearest.items) |result| {
    std.debug.print("Entity {d} at distance {d:.1}\n", .{result.id, result.distance});
}
```

**Usage Pattern - Statistics and Debugging:**
```zig
// Get spatial index statistics for profiling
const stats = index.getStats();
std.debug.print("Entities: {d}, Cells: {d}, Max/cell: {d}, Avg/cell: {d:.1}\n", .{
    stats.total_entities,
    stats.non_empty_cells,
    stats.max_entities_per_cell,
    stats.avg_entities_per_cell,
});

// Get entities in a specific cell
const cell_coords = index.getCellCoords(spatial.Vec2.init(100.0, 100.0));
if (index.getCell(cell_coords.x, cell_coords.y)) |entries| {
    for (entries) |entry| {
        std.debug.print("Entity {d} in cell\n", .{entry.id});
    }
}
```

**Data Structures:**
- `SpatialIndex(T)` - Generic spatial index parameterized by entity ID type
- `Vec2` - 2D vector with add, sub, scale, length, distance operations
- `AABB` - Axis-aligned bounding box with containment and overlap tests
- `NearestResult(T)` - Result from nearest neighbor queries (id, position, distance)
- `SpatialIndexStats` - Statistics about index distribution
- `SpatialIndexConfig` - Configuration (cell_size, initial capacities)

**Performance Characteristics:**
- Insert: O(1) amortized
- Remove: O(k) where k is entities in the cell
- Update position: O(k) for old cell + O(1) for new cell
- Query radius: O(cells_checked × entities_per_cell)
- Query rectangle: O(cells_checked × entities_per_cell)
- Nearest neighbor: O(cells_checked × entities_per_cell)

**Cell Size Selection:**
For optimal performance, set `cell_size` approximately equal to your typical query radius.
Smaller cells = more overhead for large queries, but faster for small queries.
Larger cells = less cell lookups, but more entities to filter per cell.

**Tests:** 18 comprehensive tests covering Vec2, AABB, insert/remove/update, queries, nearest neighbor, edge cases, and custom ID types.

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
