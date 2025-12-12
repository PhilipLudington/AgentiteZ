# Integration & Development Patterns

Platform integration guides for SDL3, bgfx, stb_truetype, and core engine systems.

## Native Window Handle Extraction

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

## bgfx Initialization

Platform data must be set before calling `bgfx.init()`:

```zig
init.platformData.nwh = native_window;
init.platformData.type = bgfx.NativeWindowHandleType.Default;
init.type = bgfx.RendererType.Count; // Auto-select renderer
```

The renderer auto-selects based on platform (Metal on macOS).

## stb_truetype Integration

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

## ECS (Entity-Component-System)

The engine features a professional ECS architecture:

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

## UI Layout System

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

## Virtual Resolution System

Fixed 1920x1080 coordinate space with two complementary systems:

### RenderScale (`src/ui/dpi.zig`)

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

### Viewport System (`src/renderer/viewport.zig`)

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
