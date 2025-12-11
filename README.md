# AgentiteZ

A modern game engine framework built with Zig 0.15.1, providing production-ready foundation systems for game development.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Zig](https://img.shields.io/badge/Zig-0.15.1-orange.svg)](https://ziglang.org/)

## Features

- **ECS Architecture** - Entity-Component-System with sparse-set storage, generation counters, and dependency ordering
- **UI System** - 10 widget types (Button, Checkbox, Slider, TextInput, Dropdown, etc.) with automatic layout
- **Cross-Platform Rendering** - SDL3 + bgfx for Metal/Vulkan/DirectX/OpenGL support
- **Virtual Resolution** - Fixed 1920x1080 coordinate space with automatic aspect-ratio preservation
- **HiDPI Support** - Automatic DPI scaling for Retina/4K displays
- **Configuration System** - Pure Zig TOML parser with validation
- **Save/Load System** - Human-readable TOML-based game state persistence
- **Comprehensive Tests** - 269 tests across all major systems

**Production Status:** Rated 8.5/10 - Powers [Stellar Throne](https://github.com/PhilipLudington/StellarThroneZig) (4X strategy) and Machinae (factory-building)

## Quick Start

```zig
const std = @import("std");
const AgentiteZ = @import("AgentiteZ");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create ECS world
    var world = AgentiteZ.ecs.World.init(allocator);
    defer world.deinit();

    // Create entities with components
    const player = try world.createEntity();

    // Create component storage
    var positions = AgentiteZ.ecs.ComponentArray(Position).init(allocator);
    defer positions.deinit();

    try positions.add(player, .{ .x = 100, .y = 200 });
}
```

See [examples/minimal.zig](examples/minimal.zig) for a complete working example (~140 lines).

## Installation

### Prerequisites

**macOS:**
```bash
brew install sdl3
xcode-select --install  # For Metal framework
```

**Linux:**
```bash
# Ubuntu/Debian
sudo apt install libsdl3-dev

# Fedora
sudo dnf install SDL3-devel
```

### Clone & Build

```bash
git clone --recursive https://github.com/PhilipLudington/AgentiteZ.git
cd AgentiteZ
zig build
```

If you already cloned without `--recursive`:
```bash
git submodule update --init --recursive
```

## Usage

```bash
# Build the project
zig build

# Run the full demo (UI showcase with all widgets)
zig build run

# Run minimal example (simple window, ~140 lines)
zig build run-minimal

# Run other examples
zig build run-shapes      # 2D rendering demo
zig build run-ecs-game    # ECS game example
zig build run-ui-forms    # Form widgets demo

# Run tests
zig build test
```

## Examples

| Example | Description | Command |
|---------|-------------|---------|
| [minimal.zig](examples/minimal.zig) | Bare-bones SDL3 + bgfx setup | `zig build run-minimal` |
| [demo_ui.zig](examples/demo_ui.zig) | Full UI widget showcase | `zig build run` |
| [shapes_demo.zig](examples/shapes_demo.zig) | 2D rendering primitives | `zig build run-shapes` |
| [ecs_game.zig](examples/ecs_game.zig) | ECS with systems | `zig build run-ecs-game` |
| [ui_forms.zig](examples/ui_forms.zig) | Form input handling | `zig build run-ui-forms` |

## Architecture

```
AgentiteZ/
├── src/
│   ├── ecs/           # Entity-Component-System
│   │   ├── entity.zig     # Entity with generation counters
│   │   ├── component.zig  # Sparse-set component storage
│   │   ├── system.zig     # VTable-based systems
│   │   └── world.zig      # Central coordinator
│   ├── ui/            # UI System
│   │   ├── context.zig    # UI state management
│   │   ├── layout.zig     # Auto-layout (vertical/horizontal)
│   │   ├── dpi.zig        # Virtual resolution & DPI scaling
│   │   └── widgets/       # 10 widget types
│   ├── platform/      # Platform Abstraction
│   │   └── input_state.zig
│   ├── renderer/      # Rendering Utilities
│   │   ├── font_atlas.zig # HiDPI-aware bitmap font atlas
│   │   └── viewport.zig   # Letterbox viewport calculation
│   ├── config/        # TOML Configuration
│   └── data/          # Data Utilities
├── examples/          # 5 comprehensive examples
├── assets/            # Fonts and example data
├── shaders/           # bgfx shaders (source + compiled)
└── external/          # Git submodules (bgfx, bx, bimg, stb)
```

## Documentation

- [API Documentation](docs/api/index.md) - Complete API reference
- [ECS Module](docs/api/ecs.md) - Entity-Component-System guide
- [Widget ID Best Practices](docs/WIDGET_ID_BEST_PRACTICES.md) - Avoiding state collision

## Dependencies

All dependencies are included as git submodules or built from source:

| Dependency | License | Purpose |
|------------|---------|---------|
| [bgfx](https://github.com/bkaradzic/bgfx) | BSD 2-Clause | Cross-platform rendering |
| [bx](https://github.com/bkaradzic/bx) | BSD 2-Clause | Base library for bgfx |
| [bimg](https://github.com/bkaradzic/bimg) | BSD 2-Clause | Image library for bgfx |
| [SDL3](https://github.com/libsdl-org/SDL) | Zlib | Windowing and input |
| [stb_truetype](https://github.com/nothings/stb) | Public Domain | Font rasterization |

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Run tests (`zig build test`)
4. Commit your changes
5. Push to the branch
6. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
