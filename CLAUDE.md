# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

EtherMud is a custom game engine built with Zig 0.15.1 featuring:
- **ECS Architecture** - Entity-Component-System with sparse-set storage and generation counters
- **UI System** - 10 widget types with automatic layout and DPI scaling
- **Rendering** - SDL3 + bgfx for cross-platform graphics (Metal/Vulkan/DirectX/OpenGL)
- **Virtual Resolution** - Fixed 1920x1080 coordinate space with automatic aspect-ratio preservation

## Build Commands

```bash
# Build the project
zig build

# Build and run
zig build run

# Run tests
zig build test

# Run executable directly (after building)
./zig-out/bin/EtherMud
```

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
1. **EtherMud module** (`src/root.zig`) - Library module exposing:
   - `sdl` - SDL3 wrapper utilities
   - `bgfx` - bgfx rendering bindings
   - `stb_truetype` - TrueType font rendering
   - `ui` - Complete UI system with widgets, layout, and DPI handling
   - `ecs` - Entity-Component-System architecture

2. **Executable** (`src/main.zig`) - Main application entry point that imports the EtherMud module

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
const stb = @import("EtherMud").stb_truetype;

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
- **System Registry** - Sequential execution in registration order

**Usage Pattern:**
```zig
const ecs = @import("EtherMud").ecs;

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

// Register and update systems
try world.registerSystem(ecs.System.init(&movement_system));
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
const ui = @import("EtherMud").ui;

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

Fixed 1920x1080 coordinate space (`src/ui/dpi.zig`):

**Benefits:**
- Resolution-independent game code
- Automatic aspect-ratio preservation
- Letterboxing on ultra-wide displays
- Automatic mouse coordinate conversion

**Usage Pattern:**
```zig
const ui = @import("EtherMud").ui;

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

## Important Notes

- `src/bgfx.zig` is auto-generated from the bgfx C API - modifications should be made to the bgfx binding generator, not this file
- The build system links multiple frameworks on macOS: Metal, QuartzCore, Cocoa, IOKit
- External dependencies are in `external/`:
  - `bx`, `bimg`, `bgfx` - git submodules for rendering
  - `stb` - stb_truetype header-only library (downloaded directly)
- Zig 0.15.1 is the target version - newer Zig releases may have breaking changes
