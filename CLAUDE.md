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
- **Pathfinding** - A* algorithm with diagonal movement, variable costs, smoothing, and dynamic obstacles
- **Event System** - Generic pub/sub dispatcher with queuing, context support, and recursion prevention
- **Resource System** - Generic resource storage with capacity limits, rates, and transfers
- **Modifier System** - Stackable value modifiers with source tracking and duration
- **Turn Manager** - Turn-based game flow with configurable phases and callbacks
- **Blackboard System** - Type-safe key-value storage for AI cross-system communication
- **Task Queue** - Sequential task execution for AI agents with 19 task types
- **AI Personality** - Trait-weighted decision scoring with 8 personality templates
- **Tech Tree** - Research system with prerequisites (AND/OR), progress tracking, and unlocks
- **Fog of War** - Per-player visibility with vision sources, line-of-sight, and shared vision
- **Victory Conditions** - Multiple victory types with progress tracking and custom callbacks
- **HTN Planner** - Hierarchical Task Network for AI planning with primitive/compound tasks
- **AI Tracks** - Parallel decision tracks (combat, economy, diplomacy) with coordination
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
   - `pathfinding` - A* pathfinding with configurable movement and costs
   - `event` - Generic pub/sub event dispatcher
   - `resource` - Resource storage with capacity, rates, and transfers
   - `modifier` - Stackable value modifiers with source tracking
   - `turn` - Turn-based game flow with phases and callbacks
   - `blackboard` - Type-safe key-value storage for AI communication
   - `task_queue` - Sequential task execution for AI agents
   - `personality` - Trait-weighted decision scoring for AI
   - `tech` - Technology tree with research and unlocks
   - `fog` - Fog of war visibility system
   - `victory` - Victory conditions and win state management
   - `htn` - Hierarchical Task Network planner for AI
   - `ai_tracks` - Parallel decision tracks for AI agents

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

See **[Integration Guide](docs/api/integration.md)** for detailed patterns on:
- Native window handle extraction (SDL3 properties)
- bgfx initialization and platform data
- stb_truetype font loading and rendering
- ECS architecture with sparse-set storage and system dependencies
- UI layout system with automatic widget positioning
- Virtual resolution system (RenderScale + Viewport)

---

## Game Systems API Reference

Detailed API documentation for all game systems is available in `docs/api/`. Below are quick summaries with links.

### Audio System (`src/audio.zig`) **[Full docs](docs/api/audio.md)**
Sound effects and music playback with 32 channels, volume control, 2D panning, and SDL3 audio stream mixing.

### Camera System (`src/camera.zig`) **[Full docs](docs/api/camera.md)**
2D camera with position, zoom, rotation, smooth follow, bounds constraints, screen shake, and world/screen coordinate conversion.

### Animation System (`src/animation.zig`) **[Full docs](docs/api/animation.md)**
Frame-based sprite animation with clips, playback controls, frame events, state machine, and blend transitions.

### Tilemap System (`src/tilemap.zig`) **[Full docs](docs/api/tilemap.md)**
Chunk-based tile storage (32x32 per chunk) with up to 16 layers, collision flags, auto-tiling, and camera-based culling.

### Spatial Index (`src/spatial.zig`) **[Full docs](docs/api/spatial.md)**
Grid-based spatial hashing with O(1) insert/remove, radius/rectangle queries, and K-nearest neighbor search.

### Pathfinding System (`src/pathfinding.zig`) **[Full docs](docs/api/pathfinding.md)**
A* algorithm with diagonal movement, variable terrain costs, path smoothing, dynamic obstacles, and line-of-sight checks.

### Event System (`src/event.zig`) **[Full docs](docs/api/event.md)**
Generic pub/sub dispatcher with typed events, subscription handles, event queuing, and recursion prevention.

### Resource System (`src/resource.zig`) **[Full docs](docs/api/resource.md)**
Generic resource storage with capacity limits, production/consumption rates, transfers, and atomic cost operations.

### Modifier System (`src/modifier.zig`) **[Full docs](docs/api/modifier.md)**
Stackable value modifiers with flat/percent/multiplier types, source tracking, temporary durations, and configurable stacking rules.

### Turn Manager (`src/turn.zig`) **[Full docs](docs/api/turn.md)**
Turn-based game flow with configurable phases, lifecycle callbacks, error handling, and progress tracking.

### Blackboard System (`src/blackboard.zig`) **[Full docs](docs/api/blackboard.md)**
Type-safe key-value storage for AI with resource reservations, plan publishing, decision history, and change subscriptions.

### Task Queue System (`src/task_queue.zig`) **[Full docs](docs/api/task-queue.md)**
Sequential task execution with 19 task types (move, build, attack, etc.), lifecycle states, priority sorting, and callbacks.

### AI Personality System (`src/personality.zig`) **[Full docs](docs/api/personality.md)**
Trait-weighted decision scoring with 8 personality templates, threat/goal management, cooldowns, and situational modifiers.

### Tech Tree System (`src/tech.zig`) **[Full docs](docs/api/tech.md)**
Technology research with prerequisites (AND/OR logic), progress tracking, research queues, categories/eras, and unlock management.

### Fog of War System (`src/fog.zig`) **[Full docs](docs/api/fog.md)**
Per-player visibility with three states (unexplored/explored/visible), vision sources with range, line-of-sight blocking, and shared vision.

### Victory Conditions (`src/victory.zig`) **[Full docs](docs/api/victory.md)**
Multiple victory types with custom condition callbacks, progress tracking, player elimination, turn limits, and victory notifications.

### HTN Planner (`src/htn.zig`) **[Full docs](docs/api/htn.md)**
Hierarchical Task Network planner for AI with primitive/compound tasks, preconditions, effects, method selection, and plan generation.

### AI Tracks (`src/ai_tracks.zig`) **[Full docs](docs/api/ai-tracks.md)**
Parallel decision tracks for AI with combat/economy/diplomacy domains, urgency-based scoring, conflict detection, and cross-track coordination.

---

### Input State (`src/platform/input_state.zig`) **[Full docs](docs/api/input.md)**
Event-driven to immediate-mode input abstraction with press/down distinction, mouse buttons, text buffering, and SDL3 integration.

### Configuration System (`src/config/`) **[Full docs](docs/api/config.md)**
Pure Zig TOML parser with escape sequences, validation, and game data loaders (rooms, items, NPCs).

### Save/Load System (`src/save_load.zig`) **[Full docs](docs/api/storage.md)**
Human-readable TOML game state persistence with player, inventory, room, NPC, and dropped item tracking.

### Font Atlas System (`src/renderer/font_atlas.zig`) **[Full docs](docs/api/font-atlas.md)**
HiDPI-aware bitmap font rendering with pre-baked glyph atlas, fast text measurement, and ellipsis truncation.

## Important Notes

- `src/bgfx.zig` is auto-generated from the bgfx C API - modifications should be made to the bgfx binding generator, not this file
- The build system links multiple frameworks on macOS: Metal, QuartzCore, Cocoa, IOKit
- External dependencies are in `external/`:
  - `bx`, `bimg`, `bgfx` - git submodules for rendering
  - `stb` - stb_truetype header-only library (downloaded directly)
- Zig 0.15.1 is the target version - newer Zig releases may have breaking changes
- For detailed code review and improvement history, see `IMPROVEMENTS.md`
- For widget ID collision prevention, see `docs/WIDGET_ID_BEST_PRACTICES.md`
