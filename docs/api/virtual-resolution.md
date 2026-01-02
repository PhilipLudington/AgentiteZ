# Virtual Resolution System

The Virtual Resolution system provides resolution-independent rendering with a fixed coordinate space (default 1920x1080) that automatically scales to any physical window size.

## Overview

**File:** `src/renderer/viewport.zig`

**Key Features:**
- Fixed virtual coordinate space (default 1920x1080)
- Three scaling modes: fit (letterbox), fill (crop), stretch
- Mouse coordinate transformation (screen ↔ virtual)
- Automatic viewport calculation with caching
- Letterbox/pillarbox support

## Core Types

### ScaleMode

```zig
pub const ScaleMode = enum {
    fit,     // Maintain aspect ratio, letterbox as needed (default)
    fill,    // Maintain aspect ratio, crop to fill
    stretch, // Stretch to fill, may distort
};
```

### VirtualResolution

Main manager for virtual resolution handling:

```zig
pub const VirtualResolution = struct {
    virtual_width: u32,
    virtual_height: u32,
    physical_width: u32,
    physical_height: u32,
    scale_mode: ScaleMode,
    // ... cached viewport
};
```

## Basic Usage

```zig
const renderer = @import("agentitez").renderer;

// Create with default 1920x1080 virtual resolution
var vr = renderer.VirtualResolution.initDefault();

// Or with custom virtual resolution
var vr = renderer.VirtualResolution.init(1280, 720);

// Update on window resize
vr.setPhysicalSize(window_width, window_height);

// Get viewport for bgfx rendering
const viewport = vr.getViewport();
bgfx.setViewRect(0, viewport.x, viewport.y, viewport.width, viewport.height);
```

## Mouse Coordinate Transformation

### Screen to Virtual

Transform physical screen coordinates (e.g., from SDL mouse events) to virtual coordinates:

```zig
// Returns null if in letterbox area (fit mode only)
if (vr.screenToVirtual(mouse_x, mouse_y)) |pos| {
    // pos.x and pos.y are in virtual coordinates
    handleClick(pos.x, pos.y);
}

// Or use clamped version (always returns valid position)
const pos = vr.screenToVirtualClamped(mouse_x, mouse_y);
```

### Virtual to Screen

Transform virtual coordinates to physical screen coordinates:

```zig
const screen = vr.virtualToScreen(virtual_x, virtual_y);
// screen.x and screen.y are in physical screen coordinates
```

### Check Viewport Bounds

```zig
if (vr.isInsideViewport(screen_x, screen_y)) {
    // Mouse is in active game area, not letterbox
}
```

## Scaling Modes

### Fit Mode (Default)

Content maintains aspect ratio. Black bars (letterbox/pillarbox) appear on edges when aspect ratios don't match.

```zig
vr.setScaleMode(.fit);
```

**Best for:** Most games. Ensures entire game is visible.

### Fill Mode

Content maintains aspect ratio but fills the entire window. Edges may be cropped.

```zig
vr.setScaleMode(.fill);
```

**Best for:** Immersive games where edge content can be hidden.

### Stretch Mode

Content stretches to fill window, ignoring aspect ratio. May cause distortion.

```zig
vr.setScaleMode(.stretch);
```

**Best for:** Pixel-perfect retro games or when distortion is acceptable.

## Integration with Renderer2D

```zig
const viewport = vr.getViewport();
renderer_2d.setViewportFromInfo(viewport);
```

## Standalone Functions

For simple cases, use the standalone viewport calculation functions:

```zig
// Fit mode (letterbox)
const viewport = renderer.calculateFitViewport(
    physical_width, physical_height,
    virtual_width, virtual_height,
);

// Fill mode (crop)
const viewport = renderer.calculateFillViewport(
    physical_width, physical_height,
    virtual_width, virtual_height,
);

// Stretch mode
const viewport = renderer.calculateStretchViewport(
    physical_width, physical_height,
    virtual_width, virtual_height,
);

// Legacy alias for fit mode
const viewport = renderer.calculateLetterboxViewport(...);
```

## ViewportInfo

All viewport functions return `ViewportInfo`:

```zig
pub const ViewportInfo = struct {
    x: u16,      // Viewport X offset in physical pixels
    y: u16,      // Viewport Y offset in physical pixels
    width: u16,  // Viewport width in physical pixels
    height: u16, // Viewport height in physical pixels
    scale: f32,  // Viewport pixels per virtual pixel
};
```

## Complete Example

```zig
const std = @import("std");
const agentitez = @import("agentitez");
const renderer = agentitez.renderer;

pub fn main() !void {
    // Initialize virtual resolution
    var vr = renderer.VirtualResolution.initDefault();

    // Game loop
    while (running) {
        // Handle window resize
        if (window_resized) {
            vr.setPhysicalSize(new_width, new_height);
            const viewport = vr.getViewport();
            bgfx.reset(new_width, new_height, reset_flags, format);
            bgfx.setViewRect(0, viewport.x, viewport.y, viewport.width, viewport.height);
        }

        // Handle mouse input
        if (vr.screenToVirtual(mouse_x, mouse_y)) |pos| {
            // Game logic uses virtual coordinates (0-1920, 0-1080)
            handleMouseMove(pos.x, pos.y);
        }

        // All rendering uses virtual coordinate space
        renderer_2d.drawRect(100, 100, 200, 150, color);  // Always same position

        bgfx.frame(false);
    }
}
```

## Performance Notes

- Viewport calculation is cached; only recalculated on size/mode change
- Coordinate transformation is O(1) with simple arithmetic
- No allocations required
