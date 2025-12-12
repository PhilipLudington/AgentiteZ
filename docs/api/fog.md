# Fog of War System

Per-player visibility system with vision sources, line-of-sight, and shared vision.

## Overview

The Fog of War system provides:
- Three visibility states (unexplored, explored, visible)
- Per-player visibility grids
- Vision sources with configurable range
- Line-of-sight blocking for terrain
- Shared vision between allied players
- Efficient dirty-flag updates

## Quick Start

```zig
const fog = @import("AgentiteZ").fog;

var fow = try fog.FogOfWar.init(allocator, .{
    .width = 100,
    .height = 100,
    .player_count = 4,
});
defer fow.deinit();

// Add a vision source (unit)
const handle = try fow.addVisionSource(.{
    .x = 50,
    .y = 50,
    .range = 8,
    .player_id = 0,
});

// Update visibility
fow.update();

// Check visibility
if (fow.isVisible(55, 50, 0)) {
    // Player 0 can see this tile
}
```

## API Reference

### FogOfWar

Main manager for fog of war.

#### Initialization

```zig
pub fn init(allocator: std.mem.Allocator, config: FogConfig) !FogOfWar
pub fn deinit(self: *FogOfWar) void
```

#### Vision Sources

```zig
pub fn addVisionSource(self: *FogOfWar, source: struct {
    x: i32,
    y: i32,
    range: ?u8 = null,
    player_id: u8,
    active: bool = true,
    ignores_blockers: bool = false,
}) !VisionSourceHandle

pub fn removeVisionSource(self: *FogOfWar, handle: VisionSourceHandle) bool
pub fn moveVisionSource(self: *FogOfWar, handle: VisionSourceHandle, x: i32, y: i32) bool
pub fn setVisionRange(self: *FogOfWar, handle: VisionSourceHandle, range: u8) bool
pub fn setVisionActive(self: *FogOfWar, handle: VisionSourceHandle, active: bool) bool
```

#### Blocking Terrain

```zig
pub fn setBlocker(self: *FogOfWar, x: i32, y: i32, blocks: bool) void
pub fn isBlocker(self: *const FogOfWar, x: i32, y: i32) bool
pub fn clearBlockers(self: *FogOfWar) void
```

#### Shared Vision

```zig
pub fn setSharedVision(self: *FogOfWar, player_a: u8, player_b: u8, shared: bool) !void
pub fn hasSharedVision(self: *const FogOfWar, player_a: u8, player_b: u8) bool
```

#### Update

```zig
pub fn update(self: *FogOfWar) void
pub fn forceUpdate(self: *FogOfWar) void
```

#### Visibility Queries

```zig
pub fn getVisibility(self: *const FogOfWar, x: i32, y: i32, player_id: u8) Visibility
pub fn isVisible(self: *const FogOfWar, x: i32, y: i32, player_id: u8) bool
pub fn isExplored(self: *const FogOfWar, x: i32, y: i32, player_id: u8) bool
pub fn isVisibleToAny(self: *const FogOfWar, x: i32, y: i32) bool
```

#### Map Operations

```zig
pub fn revealAll(self: *FogOfWar, player_id: u8) void
pub fn hideAll(self: *FogOfWar, player_id: u8) void
pub fn revealArea(self: *FogOfWar, center_x: i32, center_y: i32, radius: u8, player_id: u8) void
```

#### Statistics

```zig
pub fn getExploredPercentage(self: *const FogOfWar, player_id: u8) f32
pub fn getVisiblePercentage(self: *const FogOfWar, player_id: u8) f32
pub fn getSourceCount(self: *const FogOfWar) usize
pub fn getActiveSourceCount(self: *const FogOfWar) usize
pub fn getPlayerSources(self: *const FogOfWar, player_id: u8, allocator: std.mem.Allocator) ![]VisionSourceHandle
```

### FogConfig

```zig
pub const FogConfig = struct {
    width: u32,                      // Map width in tiles
    height: u32,                     // Map height in tiles
    player_count: u8 = 2,            // Number of players
    remember_explored: bool = true,  // Keep explored areas visible
    default_vision_range: u8 = 5,    // Default range for new sources
};
```

### Visibility

```zig
pub const Visibility = enum(u8) {
    unexplored = 0,  // Never seen
    explored = 1,    // Previously seen
    visible = 2,     // Currently visible
};
```

### VisionSource

```zig
pub const VisionSource = struct {
    id: u32,
    x: i32,
    y: i32,
    range: u8,
    player_id: u8,
    active: bool = true,
    ignores_blockers: bool = false,
};
```

## Examples

### Moving Units

```zig
// When unit moves, update its vision source
fn onUnitMove(unit: *Unit, new_x: i32, new_y: i32) void {
    _ = fow.moveVisionSource(unit.vision_handle, new_x, new_y);
    fow.update();
}
```

### Terrain Blockers

```zig
// Mark mountains and forests as blocking
for (tilemap.getTiles()) |tile| {
    if (tile.type == .mountain or tile.type == .forest) {
        fow.setBlocker(tile.x, tile.y, true);
    }
}
```

### Allied Vision

```zig
// Players 0 and 1 are allies
try fow.setSharedVision(0, 1, true);

// Now both players see what either can see
```

### Revealed Units (ignores blockers)

```zig
// Scout unit can see over obstacles
const scout_vision = try fow.addVisionSource(.{
    .x = scout.x,
    .y = scout.y,
    .range = 12,
    .player_id = 0,
    .ignores_blockers = true,
});
```

### Rendering with Fog

```zig
for (0..map_height) |y| {
    for (0..map_width) |x| {
        const vis = fow.getVisibility(@intCast(x), @intCast(y), current_player);
        switch (vis) {
            .unexplored => {}, // Don't render
            .explored => renderTile(x, y, 0.5), // Half brightness
            .visible => renderTile(x, y, 1.0), // Full brightness
        }
    }
}
```

### Exploration Progress

```zig
const explored = fow.getExploredPercentage(player_id);
ui.drawText("Map explored: {d:.0}%", .{explored * 100});
```

## Test Coverage

20 tests covering:
- Basic visibility
- Vision sources
- Moving sources
- Blockers and LOS
- Ignoring blockers
- Shared vision
- Reveal/hide operations
- Edge cases (out of bounds, invalid players)
- Circular vision shape
