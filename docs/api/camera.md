# Camera System

2D camera system for game rendering (`src/camera.zig`).

## Features

- **Position, zoom, rotation** - Full 2D camera transform
- **Smooth follow** - Frame-rate independent lerp to target position
- **Camera bounds** - Constrain camera to world limits
- **Screen shake** - Configurable intensity, duration, decay, and frequency
- **Coordinate conversion** - World-to-screen and screen-to-world transforms
- **Visibility testing** - Check if points/rects are visible in camera view
- **View matrix** - Get transformation matrix for bgfx rendering

## Usage

### Basic Setup

```zig
const camera = @import("AgentiteZ").camera;

// Create camera with default settings (centered at origin, zoom 1.0)
var cam = camera.Camera2D.init(.{});

// Or with custom initial position and zoom
var cam = camera.Camera2D.init(.{
    .position = camera.Vec2.init(500.0, 300.0),
    .zoom = 1.5,
    .rotation = 0.0,
});
```

### Follow and Bounds

```zig
// Set smooth follow target (camera will lerp to target each update)
cam.setTarget(player_position);
cam.setFollowSmoothing(0.1); // 0 = instant, higher = slower

// Set camera movement bounds (world limits)
cam.setBounds(camera.CameraBounds.fromRect(0, 0, 4000, 3000));

// Set zoom limits
cam.setZoomLimits(0.5, 4.0);

// Update camera each frame (handles follow, bounds, shake)
cam.update(delta_time);
```

### Screen Shake

```zig
cam.shake(.{
    .intensity = 10.0,  // Max pixels offset
    .duration = 0.3,    // Seconds
    .decay = true,      // Fade out over duration
    .frequency = 30.0,  // Oscillations per second
});
```

### Coordinate Conversion

```zig
// Coordinate conversion (uses 1920x1080 virtual resolution)
const screen_pos = cam.worldToScreen(entity_x, entity_y);
const world_pos = cam.screenToWorld(mouse_x, mouse_y);

// Visibility checks
if (cam.isPointVisible(enemy_x, enemy_y)) {
    // Render enemy
}
if (cam.isRectVisible(tile_x, tile_y, tile_w, tile_h)) {
    // Render tile
}

// Get visible world area (for culling)
const visible = cam.getVisibleRect();
```

### Camera Controls

```zig
cam.setZoom(2.0);
cam.adjustZoom(0.1);     // Add to zoom
cam.multiplyZoom(1.1);   // Multiply zoom (good for scroll wheel)
cam.zoomTowards(world_point, 0.5); // Zoom keeping point stationary

cam.move(camera.Vec2.init(10.0, 0.0));      // Move in world space
cam.moveScreen(camera.Vec2.init(10.0, 0.0)); // Move in screen space
cam.centerOn(camera.Vec2.init(500.0, 300.0)); // Instant reposition

cam.setRotation(std.math.pi / 4.0);  // Radians
cam.setRotationDegrees(45.0);         // Degrees

// Get view matrix for bgfx (4x4 row-major)
const view_matrix = cam.getViewMatrix();
```

## Data Structures

- `Camera2D` - Main camera with position, zoom, rotation, follow, bounds, shake
- `Vec2` - 2D vector with math operations (add, sub, scale, lerp, rotate, normalize)
- `CameraBounds` - World bounds for constraining camera movement
- `ShakeConfig` - Screen shake parameters (intensity, duration, decay, frequency)

## Integration with Renderer2D

The Camera2D system works with virtual resolution (1920x1080). To integrate with Renderer2D:
1. Transform world positions using `worldToScreen()` before drawing
2. Use `getVisibleRect()` for efficient culling of off-screen objects
3. Use `screenToWorld()` to convert mouse input to world coordinates

## Tests

25 comprehensive tests covering Vec2 math, bounds, zoom, follow, shake, and coordinate conversion.
