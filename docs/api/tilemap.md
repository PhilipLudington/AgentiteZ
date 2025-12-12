# Tilemap System

Chunk-based tilemap system for efficient large map storage and rendering (`src/tilemap.zig`).

## Features

- **Chunk-based storage** - 32x32 tiles per chunk for memory efficiency
- **Sparse allocation** - Only allocates chunks when tiles are placed
- **Multiple layers** - Up to 16 layers (ground, vegetation, objects, etc.)
- **Tile collision** - Per-tile collision flags (solid, water, pit, platform, ladder, damage, trigger)
- **Auto-tiling** - 8-neighbor based terrain transitions
- **Tileset management** - UV calculation, collision flags, auto-tile terrain types
- **Camera integration** - Efficient culling with visible tile/chunk range queries
- **Coordinate conversion** - World-to-tile and tile-to-world transforms

## Usage

### Basic Tilemap

```zig
const tilemap = @import("AgentiteZ").tilemap;

// Create tilemap (100x100 tiles, 32px per tile)
var map = tilemap.Tilemap.init(allocator, .{
    .width = 100,
    .height = 100,
    .tile_width = 32,
    .tile_height = 32,
});
defer map.deinit();

// Add layers
const ground = try map.addLayer("ground");
const objects = try map.addLayerWithOptions("objects", .{
    .z_order = 1,
    .visible = true,
    .opacity = 1.0,
});

// Set tiles by ID
try map.setTileID(ground, 5, 5, 1);
try map.setTileID(objects, 5, 5, 10);

// Set tiles with full control
try map.setTile(ground, 10, 10, .{
    .id = 2,
    .collision = .{ .solid = true },
});

// Fill a region
try map.fill(ground, 0, 0, 50, 50, .{ .id = 1 });
```

### Tileset

```zig
var tileset = try tilemap.Tileset.init(allocator, .{
    .tile_width = 32,
    .tile_height = 32,
    .texture_width = 512,
    .texture_height = 512,
});
defer tileset.deinit();

tileset.setCollision(1, .{ .solid = true });
tileset.setCollisionRange(10, 20, .{ .solid = true, .water = true });
map.setTileset(&tileset);

if (tileset.getTileUV(1)) |uv| {
    // uv.u0, uv.v0, uv.u1, uv.v1
}
```

### Collision Detection

```zig
if (map.isSolid(player_x, player_y)) {
    // Block movement
}

const flags = map.checkCollision(player_x, player_y);
if (flags.water) { /* in water */ }
if (flags.damage) { /* takes damage */ }
```

### Camera Integration

```zig
const range = map.getVisibleTileRange(&cam);
const chunks = map.getVisibleChunkRange(&cam);

if (map.visibleTileIterator(ground, &cam)) |*iter| {
    while (iter.next()) |entry| {
        renderTile(entry);
    }
}
```

### Coordinate Conversion

```zig
const coord = map.worldToTile(150.0, 200.0);
const world_pos = map.tileToWorld(5, 5);
const center = map.tileToWorldCenter(5, 5);
const bounds = map.getWorldBounds();
```

### Auto-Tiling

```zig
try map.addAutoTileRule(.{
    .terrain = 1,
    .base_tile_id = 1,
    .variant_map = variant_map,
});

map.updateAutoTileRegion(ground, 0, 0, 50, 50);
const mask = map.getNeighborMask(ground, 5, 5, 1);
```

## Data Structures

- `Tilemap` - Main tilemap with layers, tileset, and auto-tile rules
- `TileLayer` - Single layer with sparse chunk storage
- `TileChunk` - 32x32 tile block (allocated on demand)
- `Tile` - Tile data (id, collision, auto_tile_variant, user_data)
- `Tileset` - Texture atlas with UV coords, collision, and terrain data
- `TileCoord` - Integer tile coordinate with conversion helpers
- `CollisionFlags` - Packed collision flags (solid, water, pit, etc.)
- `NeighborMask` - 8-bit neighbor configuration for auto-tiling

## Constants

- `CHUNK_SIZE` = 32 (tiles per chunk dimension)
- `MAX_LAYERS` = 16
- `EMPTY_TILE` = 0 (tile ID for empty)

## Tests

18 comprehensive tests covering chunks, layers, collision, UV calculation, coordinate conversion, and visibility culling.
