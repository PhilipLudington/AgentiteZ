# Font Atlas System

HiDPI-aware bitmap font rendering with optimized glyph packing (`src/renderer/font_atlas.zig`).

## Features

- **HiDPI/Retina Support** - Automatic DPI scaling for crisp text on 2x/3x displays
- **Pre-baked 94 printable ASCII glyphs** - All standard chars rendered at load time
- **Fast text measurement** - No stb_truetype calls during rendering
- **Proper glyph metrics** - UV coords, offsets, advances for perfect positioning
- **16x16 atlas grid** - Efficient packing of 256 characters
- **RGBA8 format** - Metal-compatible texture format (glyph in alpha channel)
- **Text truncation** - Ellipsis support for overflow detection
- **~50ms startup** - Fast atlas generation

## Usage (with HiDPI)

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
    std.debug.print("Truncated to {d} chars (width: {d:.1}px)\n",
        .{result.truncated_len, result.width});
}

// Access individual glyph metrics
const glyph = font_atlas.getGlyph('A');
std.debug.print("Glyph 'A': UV=({d:.3},{d:.3})-({d:.3},{d:.3}), advance={d:.2}px\n",
    .{glyph.uv_x0, glyph.uv_y0, glyph.uv_x1, glyph.uv_y1, glyph.advance});

// Use texture in rendering
const texture_handle = font_atlas.texture;
```

## Data Structures

- `FontAtlas` - Complete atlas with texture handle, 256 glyphs, metrics
- `Glyph` - UV coordinates, offsets, size, advance

### Glyph Structure

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

## Atlas Generation Process

1. Load TrueType font file with stb_truetype
2. Calculate font metrics (ascent, descent, line height)
3. Render all 256 ASCII glyphs to grayscale atlas (16x16 grid)
4. Calculate UV coordinates for each glyph
5. Convert grayscale to RGBA8 (white RGB, glyph in alpha)
6. Upload to bgfx texture

## Key Features

- **16x16 grid layout** - 256 glyphs in square atlas
- **Automatic sizing** - Atlas size based on font size + padding
- **Missing glyph handling** - Empty glyph info for unsupported characters
- **Debug output** - Logs glyph rendering stats and sample characters
- **Row wrapping** - Glyphs wrap to next row when needed

## Performance Benefits

- **No runtime font rasterization** - All glyphs pre-rendered
- **Fast measurement** - Simple advance summation, no stb calls
- **GPU-friendly** - Single texture for all text rendering
- **Cache-friendly** - All glyph data in contiguous array

## Available Fonts

The project includes several fonts from bgfx examples:
- `external/bgfx/examples/runtime/font/roboto-regular.ttf` - Clean sans-serif
- `external/bgfx/examples/runtime/font/droidsans.ttf` - Android default
- `external/bgfx/examples/runtime/font/droidsansmono.ttf` - Monospace

## HiDPI Support Details

The engine includes full HiDPI/Retina display support:
- SDL3 window created with `SDL_WINDOW_HIGH_PIXEL_DENSITY` flag
- DPI scale calculated from logical vs physical pixel dimensions
- bgfx initialized and viewport set to physical pixel dimensions
- Font atlas generated at DPI-scaled size (e.g., 48px on 2x Retina)
- UI coordinates remain in logical 1920x1080 virtual space

## Experimental: Runtime SDF Mode

**Status:** Implemented but not recommended for production use. SDF rendering quality was found to be inferior to bitmap atlas on HiDPI displays.

Runtime SDF (Signed Distance Field) is available via `FontAtlas.initSDF()` for zoom-heavy applications, but bitmap atlas with proper DPI scaling provides superior quality for fixed-scale UI.

## Tests

10 comprehensive tests covering glyph layout, UV calculation, atlas sizing, text measurement, ellipsis truncation, line height, RGBA conversion, and grid packing.
