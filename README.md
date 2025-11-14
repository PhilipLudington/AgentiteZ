# EtherMud

A modern game engine framework built with Zig 0.15.1, providing production-ready foundation systems for game development.

**Powers:** Stellar Throne (4X strategy game), Machinae

**Core Technologies:**
- **Zig 0.15.1** - Modern systems programming language
- **SDL3** - Cross-platform multimedia library for windowing and input
- **bgfx** - Cross-platform rendering library with Metal/Vulkan/DirectX support

## Building

```bash
zig build
```

## Running

```bash
zig build run
```

Or directly:

```bash
./zig-out/bin/EtherMud
```

## Architecture

The engine integrates:
- SDL3 for window management and event handling
- bgfx for cross-platform 3D rendering (Metal on macOS)
- Official bgfx Zig bindings from the bgfx repository
- bx and bimg libraries as dependencies for bgfx

## Dependencies

### System Requirements (macOS)
- SDL3 (install via Homebrew: `brew install sdl3`)
- Xcode Command Line Tools (for Metal framework)

### Included as Submodules
- bgfx - Rendering library
- bx - Base library for bgfx
- bimg - Image library for bgfx
