# AgentiteZ Shaders

This directory contains shader source files for the 2D UI renderer.

## Shader Files

- `vs_color.sc` / `fs_color.sc` - Vertex/Fragment shaders for colored primitives (rectangles, lines)
- `vs_texture.sc` / `fs_texture.sc` - Vertex/Fragment shaders for textured primitives (fonts, images)

## Compilation

Shaders are written in bgfx's shader language (.sc files) and must be compiled to platform-specific binaries.

### Building shaderc

```bash
cd external/bgfx
make shaderc
```

This builds the shaderc tool to: `external/bgfx/.build/osx-arm64/bin/shaderc`

### Compiling Shaders

Shaders need to be compiled for each platform. For macOS (Metal):

```bash
# Color shaders
./external/bgfx/.build/osx-arm64/bin/shaderc \
  -f shaders/vs_color.sc \
  -o shaders/compiled/vs_color.bin \
  --type vertex \
  --platform osx \
  -i external/bgfx/src \
  --profile metal

./external/bgfx/.build/osx-arm64/bin/shaderc \
  -f shaders/fs_color.sc \
  -o shaders/compiled/fs_color.bin \
  --type fragment \
  --platform osx \
  -i external/bgfx/src \
  --profile metal

# Texture shaders
./external/bgfx/.build/osx-arm64/bin/shaderc \
  -f shaders/vs_texture.sc \
  -o shaders/compiled/vs_texture.bin \
  --type vertex \
  --platform osx \
  -i external/bgfx/src \
  --profile metal

./external/bgfx/.build/osx-arm64/bin/shaderc \
  -f shaders/fs_texture.sc \
  -o shaders/compiled/fs_texture.bin \
  --type fragment \
  --platform osx \
  -i external/bgfx/src \
  --profile metal
```

## Shader Compilation in build.zig

The build.zig file should automatically compile shaders when they change, embedding them into the binary.
