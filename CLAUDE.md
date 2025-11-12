# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

EtherMud is a custom game engine built with Zig 0.15.1 that integrates SDL3 for windowing/input and bgfx for cross-platform 3D rendering. The engine currently provides a foundational rendering loop with a cornflower blue clear color.

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

2. **Executable** (`src/main.zig`) - Main application entry point that imports the EtherMud module

### Key Source Files

- `src/main.zig` - Main game loop, window creation, bgfx initialization
- `src/root.zig` - Module exports for SDL and bgfx wrappers
- `src/sdl.zig` - SDL3 wrapper providing Zig-friendly interfaces
- `src/bgfx.zig` - Auto-generated bgfx bindings (62K+ lines, DO NOT EDIT)

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

## Important Notes

- `src/bgfx.zig` is auto-generated from the bgfx C API - modifications should be made to the bgfx binding generator, not this file
- The build system links multiple frameworks on macOS: Metal, QuartzCore, Cocoa, IOKit
- External dependencies (bx, bimg, bgfx) are in `external/` as git submodules
- Zig 0.15.1 is the target version - newer Zig releases may have breaking changes
