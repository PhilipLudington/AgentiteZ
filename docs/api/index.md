# AgentiteZ Engine API Documentation

**Version:** 0.2.0
**Zig Version:** 0.15.1
**Last Updated:** January 2025

## Overview

AgentiteZ is a custom game engine built with Zig featuring an Entity-Component-System architecture, comprehensive UI system, and cross-platform rendering via SDL3 + bgfx.

## Quick Navigation

### Core Systems
- **[Integration Guide](integration.md)** - SDL3, bgfx, stb_truetype integration patterns
- **[Input System](input.md)** - Event-driven to immediate-mode input abstraction
- **[Config System](config.md)** - TOML-based configuration loading
- **[Storage System](storage.md)** - Save/load game state persistence
- **[Font Atlas](font-atlas.md)** - HiDPI-aware bitmap font rendering

### Phase 1: Foundation
- **[Audio](audio.md)** - Sound effects and music playback
- **[Camera](camera.md)** - 2D camera with zoom, follow, and shake
- **[Animation](animation.md)** - Frame-based sprite animation with state machine

### Phase 2: Spatial Systems
- **[Tilemap](tilemap.md)** - Chunk-based tilemap with layers and collision
- **[Spatial Index](spatial.md)** - Grid-based spatial hashing for proximity queries
- **[Pathfinding](pathfinding.md)** - A* algorithm with diagonal movement and costs

### Phase 3: Strategy Core
- **[Event System](event.md)** - Generic pub/sub event dispatcher
- **[Resource System](resource.md)** - Resource storage with rates and transfers
- **[Modifier System](modifier.md)** - Stackable value modifiers with source tracking
- **[Turn Manager](turn.md)** - Turn-based game flow with phases

### Phase 4: AI Foundation
- **[Blackboard](blackboard.md)** - Type-safe key-value storage for AI communication
- **[Task Queue](task-queue.md)** - Sequential task execution for AI agents
- **[AI Personality](personality.md)** - Trait-weighted decision scoring

## Key Features

### Entity-Component-System (ECS)
- Sparse-set storage for cache-friendly iteration
- Generation counters for safe entity recycling
- VTable-based polymorphic systems
- Zero external dependencies

### UI System
- **10 Widget Types**: Button, Checkbox, Radio, Slider, TextInput, Dropdown, ScrollList, TabBar, ProgressBar, Panel
- **Automatic Layout**: Vertical/horizontal stacking with alignment
- **DPI Scaling**: Resolution-independent coordinate system (1920x1080 virtual space)
- **Input Abstraction**: Immediate-mode API from event-driven SDL3
- **Font Atlas**: Optimized glyph packing with stb_truetype
- **UI Atlas**: Textured UI with 9-slice border support (NEW in 0.2.0)

### Rendering
- **bgfx Backend**: Metal (macOS), Vulkan, DirectX, OpenGL support
- **Virtual Resolution**: Fixed 1920x1080 coordinate space
- **Letterboxing**: Automatic aspect-ratio preservation
- **Font Rendering**: Pre-baked glyph atlas with 2x2 oversampling
- **Optimized Packing**: 30-50% smaller font atlases (NEW in 0.2.0)

### Platform Support
- **macOS**: Primary development platform (Metal rendering)
- **Linux**: Supported via Vulkan backend
- **Windows**: Supported via DirectX backend

## Module Architecture

```
AgentiteZ/
├── ecs/          # Entity-Component-System
│   ├── entity.zig
│   ├── component.zig
│   ├── system.zig
│   └── world.zig
├── ui/           # UI System
│   ├── context.zig
│   ├── types.zig
│   ├── layout.zig
│   ├── dpi.zig
│   ├── renderer_2d.zig
│   └── widgets/
│       ├── button.zig
│       ├── checkbox.zig
│       └── ... (8 more widgets)
├── platform/     # Platform Abstraction
│   └── input_state.zig
├── renderer/     # Rendering Utilities
│   ├── font_atlas.zig
│   ├── ui_atlas.zig (NEW)
│   └── viewport.zig
├── config/       # Configuration
│   └── loader.zig
├── data/         # Data Utilities
│   └── toml.zig
└── storage.zig   # Save/Load System
```

## Getting Started

### Basic Setup

```zig
const std = @import("std");
const AgentiteZ = @import("AgentiteZ");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize SDL3 and bgfx
    // ... (see examples/minimal.zig for complete setup)

    // Create ECS world
    var world = AgentiteZ.ecs.World.init(allocator);
    defer world.deinit();

    // Create UI context
    var ui_ctx = try AgentiteZ.ui.Context.init(allocator, window_width, window_height);
    defer ui_ctx.deinit();

    // Main loop
    while (running) {
        // Update game logic
        try world.update(delta_time);

        // Render UI
        const input = input_state.toUIInputState();
        ui_ctx.beginFrame(input, null);

        _ = AgentiteZ.ui.button(&ui_ctx, "Click Me", AgentiteZ.ui.Rect.init(100, 100, 150, 40));

        ui_ctx.endFrame();
    }
}
```

### Examples

The project includes multiple examples demonstrating different features:

```bash
# Minimal example (~140 lines): Window + blue screen
zig build run-minimal

# Full demo: All UI widgets + ECS + Font Atlas
zig build run

# Run tests
zig build test
```

## API Conventions

### Memory Management
- All public APIs accept `std.mem.Allocator`
- Callers are responsible for `defer deinit()` on all initialized structures
- String fields are caller-owned unless documented otherwise

### Error Handling
- All fallible operations return `!T` (error union)
- Common errors: `OutOfMemory`, `InvalidFormat`, `FileNotFound`
- Use `try` for error propagation, `catch` for recovery

### Naming Conventions
- **Types**: PascalCase (e.g., `EntityManager`, `FontAtlas`)
- **Functions**: camelCase (e.g., `createEntity`, `measureText`)
- **Constants**: UPPER_SNAKE_CASE (e.g., `MAX_ENTITIES`)

### Coordinate System
- Origin (0,0) is top-left
- Virtual resolution: 1920x1080 (automatic scaling)
- Mouse coordinates automatically converted to virtual space

## Recent Changes (v0.2.0)

### Phase 3 Enhancements (January 2025)

#### ✅ Task 3.1: Font Atlas Optimization
- Implemented stb_truetype pack API for 30-50% smaller atlases
- Added 2x2 oversampling for improved glyph quality
- Dynamic atlas sizing (512x512 → 4096x4096 automatic growth)
- Backward compatible grid method available

#### ✅ Task 3.2: UI Texture Atlas (Core)
- New `UIAtlas` system for textured UI elements
- 9-slice border rendering support
- Procedural atlas generation (10+ regions)
- Ready for image-based atlas loading (future)

#### 🔧 Task 3.3: Visual Regression Tests
- Deferred to future release (requires headless rendering setup)

#### ✅ Task 3.4: API Documentation
- Comprehensive module documentation (this document)
- Usage examples for all major systems
- Architecture diagrams and patterns

## Performance Characteristics

### ECS Performance
- **Component Access**: O(1) lookup via sparse set
- **Component Iteration**: O(n) cache-optimal (packed array)
- **Entity Creation**: O(1) amortized (free list)
- **Memory**: ~16 bytes per entity + component storage

### UI Performance
- **Widget Rendering**: Immediate-mode (no retained state)
- **Layout Calculation**: O(n) where n = widget count
- **Input Handling**: O(1) per widget (AABB check)
- **Text Measurement**: O(m) where m = character count

### Font Atlas
- **Init Time**: ~50-100ms for 256 ASCII glyphs
- **Atlas Size**: 512x512 typical (RGBA8 = 1MB)
- **Lookup**: O(1) array access by character code

## Thread Safety

**Current Status**: Single-threaded only
- bgfx configured with `BGFX_CONFIG_MULTITHREADED=0`
- All ECS operations must be on main thread
- UI rendering is not thread-safe

**Future**: Multithreading support planned for Phase 4

## External Dependencies

- **SDL3**: Window management, input, events
- **bgfx**: Cross-platform rendering abstraction
- **stb_truetype**: TrueType font rasterization

All dependencies linked/built automatically by `build.zig`.

## License

This project is licensed under the MIT License. See [LICENSE](../../LICENSE) for details.

## Contributing

Contributions are welcome! Please see the [README](../../README.md) for contribution guidelines.

---

**Next Steps**: Explore individual module documentation for detailed API references.
