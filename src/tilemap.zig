// tilemap.zig
// Tilemap System for AgentiteZ
//
// Features:
// - Chunk-based storage (32x32 tiles per chunk) for efficient large maps
// - Multiple layers (up to 16) for ground/vegetation/objects
// - Tile collision data
// - Auto-tiling for terrain transitions (8-neighbor based)
// - Tileset management for sprite-based tile rendering
// - Integration with Camera2D for culling

const std = @import("std");
const camera = @import("camera.zig");
const Vec2 = camera.Vec2;

/// Chunk size in tiles (32x32 = 1024 tiles per chunk)
pub const CHUNK_SIZE: u32 = 32;
pub const CHUNK_TILE_COUNT: u32 = CHUNK_SIZE * CHUNK_SIZE;

/// Maximum number of layers
pub const MAX_LAYERS: u32 = 16;

/// Tile ID type (0 = empty, 1+ = valid tile index in tileset)
pub const TileID = u16;

/// Empty tile constant
pub const EMPTY_TILE: TileID = 0;

/// Tile collision flags
pub const CollisionFlags = packed struct {
    solid: bool = false, // Cannot walk through
    water: bool = false, // Water tile (swimming)
    pit: bool = false, // Hazard/pit
    platform: bool = false, // One-way platform (can jump through)
    ladder: bool = false, // Climbable
    damage: bool = false, // Deals damage on contact
    trigger: bool = false, // Triggers an event
    _padding: u1 = 0,

    pub const none = CollisionFlags{};
    pub const solid_only = CollisionFlags{ .solid = true };
};

/// Tile data stored in chunks
pub const Tile = struct {
    id: TileID = EMPTY_TILE,
    collision: CollisionFlags = CollisionFlags.none,
    /// Auto-tile variant index (0-255 based on neighbor configuration)
    auto_tile_variant: u8 = 0,
    /// Custom user data (e.g., for scripting)
    user_data: u8 = 0,
};

/// A 32x32 chunk of tiles
pub const TileChunk = struct {
    tiles: [CHUNK_TILE_COUNT]Tile,
    /// Number of non-empty tiles (for optimization)
    tile_count: u32,
    /// Dirty flag for auto-tiling updates
    dirty: bool,

    pub fn init() TileChunk {
        return .{
            .tiles = [_]Tile{.{}} ** CHUNK_TILE_COUNT,
            .tile_count = 0,
            .dirty = false,
        };
    }

    /// Get tile at local chunk coordinates (0-31, 0-31)
    pub fn getTile(self: *const TileChunk, local_x: u32, local_y: u32) Tile {
        if (local_x >= CHUNK_SIZE or local_y >= CHUNK_SIZE) {
            return .{}; // Out of bounds returns empty tile
        }
        return self.tiles[local_y * CHUNK_SIZE + local_x];
    }

    /// Set tile at local chunk coordinates
    pub fn setTile(self: *TileChunk, local_x: u32, local_y: u32, tile: Tile) void {
        if (local_x >= CHUNK_SIZE or local_y >= CHUNK_SIZE) {
            return;
        }
        const idx = local_y * CHUNK_SIZE + local_x;
        const old_tile = self.tiles[idx];

        // Update tile count
        if (old_tile.id == EMPTY_TILE and tile.id != EMPTY_TILE) {
            self.tile_count += 1;
        } else if (old_tile.id != EMPTY_TILE and tile.id == EMPTY_TILE) {
            self.tile_count -= 1;
        }

        self.tiles[idx] = tile;
        self.dirty = true;
    }

    /// Check if chunk is empty (optimization for rendering)
    pub fn isEmpty(self: *const TileChunk) bool {
        return self.tile_count == 0;
    }
};

/// A single tilemap layer
pub const TileLayer = struct {
    name: []const u8,
    /// Sparse chunk storage: chunks[chunk_y * chunks_x + chunk_x]
    /// null = unallocated (all empty)
    chunks: []?*TileChunk,
    chunks_x: u32,
    chunks_y: u32,
    visible: bool,
    opacity: f32,
    /// Z-order for rendering (higher = rendered on top)
    z_order: i32,
    allocator: std.mem.Allocator,

    /// Internal name storage
    name_buffer: []u8,

    pub fn init(
        allocator: std.mem.Allocator,
        name: []const u8,
        chunks_x: u32,
        chunks_y: u32,
        z_order: i32,
    ) !TileLayer {
        const chunk_count = chunks_x * chunks_y;
        const chunks = try allocator.alloc(?*TileChunk, chunk_count);
        @memset(chunks, null);

        const name_buffer = try allocator.alloc(u8, name.len);
        @memcpy(name_buffer, name);

        return .{
            .name = name_buffer,
            .chunks = chunks,
            .chunks_x = chunks_x,
            .chunks_y = chunks_y,
            .visible = true,
            .opacity = 1.0,
            .z_order = z_order,
            .allocator = allocator,
            .name_buffer = name_buffer,
        };
    }

    pub fn deinit(self: *TileLayer) void {
        // Free all allocated chunks
        for (self.chunks) |chunk_opt| {
            if (chunk_opt) |chunk| {
                self.allocator.destroy(chunk);
            }
        }
        self.allocator.free(self.chunks);
        self.allocator.free(self.name_buffer);
    }

    /// Get chunk at chunk coordinates, or null if not allocated
    pub fn getChunk(self: *const TileLayer, chunk_x: u32, chunk_y: u32) ?*TileChunk {
        if (chunk_x >= self.chunks_x or chunk_y >= self.chunks_y) {
            return null;
        }
        return self.chunks[chunk_y * self.chunks_x + chunk_x];
    }

    /// Get or create chunk at chunk coordinates
    pub fn getOrCreateChunk(self: *TileLayer, chunk_x: u32, chunk_y: u32) !*TileChunk {
        if (chunk_x >= self.chunks_x or chunk_y >= self.chunks_y) {
            return error.OutOfBounds;
        }
        const idx = chunk_y * self.chunks_x + chunk_x;
        if (self.chunks[idx]) |chunk| {
            return chunk;
        }
        const chunk = try self.allocator.create(TileChunk);
        chunk.* = TileChunk.init();
        self.chunks[idx] = chunk;
        return chunk;
    }

    /// Get tile at tile coordinates
    pub fn getTile(self: *const TileLayer, tile_x: i32, tile_y: i32) Tile {
        if (tile_x < 0 or tile_y < 0) return .{};

        const utile_x: u32 = @intCast(tile_x);
        const utile_y: u32 = @intCast(tile_y);

        const chunk_x = utile_x / CHUNK_SIZE;
        const chunk_y = utile_y / CHUNK_SIZE;
        const local_x = utile_x % CHUNK_SIZE;
        const local_y = utile_y % CHUNK_SIZE;

        if (self.getChunk(chunk_x, chunk_y)) |chunk| {
            return chunk.getTile(local_x, local_y);
        }
        return .{}; // Unallocated chunk = empty tiles
    }

    /// Set tile at tile coordinates
    pub fn setTile(self: *TileLayer, tile_x: i32, tile_y: i32, tile: Tile) !void {
        if (tile_x < 0 or tile_y < 0) return;

        const utile_x: u32 = @intCast(tile_x);
        const utile_y: u32 = @intCast(tile_y);

        const chunk_x = utile_x / CHUNK_SIZE;
        const chunk_y = utile_y / CHUNK_SIZE;
        const local_x = utile_x % CHUNK_SIZE;
        const local_y = utile_y % CHUNK_SIZE;

        const chunk = try self.getOrCreateChunk(chunk_x, chunk_y);
        chunk.setTile(local_x, local_y, tile);
    }

    /// Fill a rectangular region with tiles
    pub fn fill(self: *TileLayer, x: i32, y: i32, w: u32, h: u32, tile: Tile) !void {
        var ty: i32 = y;
        while (ty < y + @as(i32, @intCast(h))) : (ty += 1) {
            var tx: i32 = x;
            while (tx < x + @as(i32, @intCast(w))) : (tx += 1) {
                try self.setTile(tx, ty, tile);
            }
        }
    }

    /// Clear all tiles in the layer
    pub fn clear(self: *TileLayer) void {
        for (self.chunks) |*chunk_opt| {
            if (chunk_opt.*) |chunk| {
                self.allocator.destroy(chunk);
                chunk_opt.* = null;
            }
        }
    }
};

/// UV coordinates for a tile in a tileset
pub const TileUV = struct {
    u0: f32,
    v0: f32,
    u1: f32,
    v1: f32,
};

/// Tileset configuration
pub const TilesetConfig = struct {
    /// Tile dimensions in pixels
    tile_width: u32,
    tile_height: u32,
    /// Tileset texture dimensions in pixels
    texture_width: u32,
    texture_height: u32,
    /// Spacing between tiles in texture
    spacing: u32 = 0,
    /// Margin around tileset edges
    margin: u32 = 0,
};

/// Tileset for sprite-based tiles
pub const Tileset = struct {
    config: TilesetConfig,
    /// Number of columns in the tileset
    columns: u32,
    /// Number of rows in the tileset
    rows: u32,
    /// Total number of tiles
    tile_count: u32,
    /// Precomputed UV coordinates for each tile
    tile_uvs: []TileUV,
    /// Collision flags per tile (indexed by TileID - 1)
    collision_flags: []CollisionFlags,
    /// Auto-tile terrain type per tile (0 = not auto-tile)
    auto_tile_terrain: []u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, config: TilesetConfig) !Tileset {
        const effective_tile_w = config.tile_width + config.spacing;
        const effective_tile_h = config.tile_height + config.spacing;

        const usable_width = config.texture_width - 2 * config.margin;
        const usable_height = config.texture_height - 2 * config.margin;

        const columns = (usable_width + config.spacing) / effective_tile_w;
        const rows = (usable_height + config.spacing) / effective_tile_h;
        const tile_count = columns * rows;

        // Precompute UV coordinates
        const tile_uvs = try allocator.alloc(TileUV, tile_count);
        const tex_w: f32 = @floatFromInt(config.texture_width);
        const tex_h: f32 = @floatFromInt(config.texture_height);

        for (0..tile_count) |i| {
            const col: u32 = @intCast(i % columns);
            const row: u32 = @intCast(i / columns);

            const px: f32 = @floatFromInt(config.margin + col * effective_tile_w);
            const py: f32 = @floatFromInt(config.margin + row * effective_tile_h);
            const pw: f32 = @floatFromInt(config.tile_width);
            const ph: f32 = @floatFromInt(config.tile_height);

            tile_uvs[i] = .{
                .u0 = px / tex_w,
                .v0 = py / tex_h,
                .u1 = (px + pw) / tex_w,
                .v1 = (py + ph) / tex_h,
            };
        }

        // Initialize collision flags (default: no collision)
        const collision_flags = try allocator.alloc(CollisionFlags, tile_count);
        @memset(collision_flags, CollisionFlags.none);

        // Initialize auto-tile terrain (default: 0 = no auto-tile)
        const auto_tile_terrain = try allocator.alloc(u8, tile_count);
        @memset(auto_tile_terrain, 0);

        return .{
            .config = config,
            .columns = columns,
            .rows = rows,
            .tile_count = tile_count,
            .tile_uvs = tile_uvs,
            .collision_flags = collision_flags,
            .auto_tile_terrain = auto_tile_terrain,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Tileset) void {
        self.allocator.free(self.tile_uvs);
        self.allocator.free(self.collision_flags);
        self.allocator.free(self.auto_tile_terrain);
    }

    /// Get UV coordinates for a tile ID (1-indexed)
    pub fn getTileUV(self: *const Tileset, tile_id: TileID) ?TileUV {
        if (tile_id == EMPTY_TILE or tile_id > self.tile_count) {
            return null;
        }
        return self.tile_uvs[tile_id - 1];
    }

    /// Get collision flags for a tile ID
    pub fn getCollision(self: *const Tileset, tile_id: TileID) CollisionFlags {
        if (tile_id == EMPTY_TILE or tile_id > self.tile_count) {
            return CollisionFlags.none;
        }
        return self.collision_flags[tile_id - 1];
    }

    /// Set collision flags for a tile ID
    pub fn setCollision(self: *Tileset, tile_id: TileID, flags: CollisionFlags) void {
        if (tile_id == EMPTY_TILE or tile_id > self.tile_count) {
            return;
        }
        self.collision_flags[tile_id - 1] = flags;
    }

    /// Set collision flags for a range of tile IDs
    pub fn setCollisionRange(self: *Tileset, start_id: TileID, end_id: TileID, flags: CollisionFlags) void {
        var id = start_id;
        while (id <= end_id) : (id += 1) {
            self.setCollision(id, flags);
        }
    }

    /// Get auto-tile terrain type for a tile ID
    pub fn getAutoTileTerrain(self: *const Tileset, tile_id: TileID) u8 {
        if (tile_id == EMPTY_TILE or tile_id > self.tile_count) {
            return 0;
        }
        return self.auto_tile_terrain[tile_id - 1];
    }

    /// Set auto-tile terrain type for a tile ID
    pub fn setAutoTileTerrain(self: *Tileset, tile_id: TileID, terrain: u8) void {
        if (tile_id == EMPTY_TILE or tile_id > self.tile_count) {
            return;
        }
        self.auto_tile_terrain[tile_id - 1] = terrain;
    }
};

/// Neighbor configuration for auto-tiling (8 bits for 8 neighbors)
/// Bit order: NW, N, NE, W, E, SW, S, SE
pub const NeighborMask = packed struct {
    nw: bool = false,
    n: bool = false,
    ne: bool = false,
    w: bool = false,
    e: bool = false,
    sw: bool = false,
    s: bool = false,
    se: bool = false,

    pub fn toU8(self: NeighborMask) u8 {
        return @bitCast(self);
    }

    pub fn fromU8(value: u8) NeighborMask {
        return @bitCast(value);
    }
};

/// Auto-tiling rule for mapping neighbor configurations to tile variants
pub const AutoTileRule = struct {
    /// Terrain type this rule applies to
    terrain: u8,
    /// Base tile ID for this terrain
    base_tile_id: TileID,
    /// Mapping from neighbor mask to variant offset
    /// Index = neighbor mask as u8, value = tile offset from base
    variant_map: [256]u8,
};

/// Coordinate conversion helpers
pub const TileCoord = struct {
    x: i32,
    y: i32,

    pub fn init(x: i32, y: i32) TileCoord {
        return .{ .x = x, .y = y };
    }

    /// Convert from world coordinates to tile coordinates
    pub fn fromWorld(world_x: f32, world_y: f32, tile_size: u32) TileCoord {
        const ts: f32 = @floatFromInt(tile_size);
        return .{
            .x = @intFromFloat(@floor(world_x / ts)),
            .y = @intFromFloat(@floor(world_y / ts)),
        };
    }

    /// Convert to world coordinates (top-left corner of tile)
    pub fn toWorld(self: TileCoord, tile_size: u32) Vec2 {
        const ts: f32 = @floatFromInt(tile_size);
        return Vec2.init(
            @as(f32, @floatFromInt(self.x)) * ts,
            @as(f32, @floatFromInt(self.y)) * ts,
        );
    }

    /// Convert to world coordinates (center of tile)
    pub fn toWorldCenter(self: TileCoord, tile_size: u32) Vec2 {
        const ts: f32 = @floatFromInt(tile_size);
        const half: f32 = ts / 2.0;
        return Vec2.init(
            @as(f32, @floatFromInt(self.x)) * ts + half,
            @as(f32, @floatFromInt(self.y)) * ts + half,
        );
    }

    /// Check if coordinate is within bounds
    pub fn isInBounds(self: TileCoord, width: u32, height: u32) bool {
        return self.x >= 0 and self.y >= 0 and
            self.x < @as(i32, @intCast(width)) and
            self.y < @as(i32, @intCast(height));
    }
};

/// Tilemap containing multiple layers
pub const Tilemap = struct {
    /// Map dimensions in tiles
    width: u32,
    height: u32,
    /// Tile dimensions in pixels
    tile_width: u32,
    tile_height: u32,
    /// Layers (indexed by layer ID)
    layers: [MAX_LAYERS]?*TileLayer,
    layer_count: u32,
    /// Active tileset
    tileset: ?*Tileset,
    /// Number of chunks in X and Y
    chunks_x: u32,
    chunks_y: u32,
    /// Auto-tile rules
    auto_tile_rules: std.ArrayList(AutoTileRule),
    allocator: std.mem.Allocator,

    pub const Config = struct {
        width: u32,
        height: u32,
        tile_width: u32 = 32,
        tile_height: u32 = 32,
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) Tilemap {
        const chunks_x = (config.width + CHUNK_SIZE - 1) / CHUNK_SIZE;
        const chunks_y = (config.height + CHUNK_SIZE - 1) / CHUNK_SIZE;

        return .{
            .width = config.width,
            .height = config.height,
            .tile_width = config.tile_width,
            .tile_height = config.tile_height,
            .layers = [_]?*TileLayer{null} ** MAX_LAYERS,
            .layer_count = 0,
            .tileset = null,
            .chunks_x = chunks_x,
            .chunks_y = chunks_y,
            .auto_tile_rules = std.ArrayList(AutoTileRule).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Tilemap) void {
        for (&self.layers) |*layer_opt| {
            if (layer_opt.*) |layer| {
                layer.deinit();
                self.allocator.destroy(layer);
                layer_opt.* = null;
            }
        }
        self.auto_tile_rules.deinit();
    }

    /// Set the tileset for rendering
    pub fn setTileset(self: *Tilemap, tileset: *Tileset) void {
        self.tileset = tileset;
    }

    /// Add a new layer with the given name
    /// Returns the layer index
    pub fn addLayer(self: *Tilemap, name: []const u8) !u32 {
        return self.addLayerWithOptions(name, .{});
    }

    pub const LayerOptions = struct {
        z_order: i32 = 0,
        visible: bool = true,
        opacity: f32 = 1.0,
    };

    /// Add a new layer with options
    pub fn addLayerWithOptions(self: *Tilemap, name: []const u8, options: LayerOptions) !u32 {
        if (self.layer_count >= MAX_LAYERS) {
            return error.TooManyLayers;
        }

        const layer = try self.allocator.create(TileLayer);
        layer.* = try TileLayer.init(
            self.allocator,
            name,
            self.chunks_x,
            self.chunks_y,
            options.z_order,
        );
        layer.visible = options.visible;
        layer.opacity = options.opacity;

        const layer_idx = self.layer_count;
        self.layers[layer_idx] = layer;
        self.layer_count += 1;

        return layer_idx;
    }

    /// Get layer by index
    pub fn getLayer(self: *Tilemap, layer_idx: u32) ?*TileLayer {
        if (layer_idx >= MAX_LAYERS) return null;
        return self.layers[layer_idx];
    }

    /// Get layer by name
    pub fn getLayerByName(self: *Tilemap, name: []const u8) ?*TileLayer {
        for (&self.layers) |layer_opt| {
            if (layer_opt) |layer| {
                if (std.mem.eql(u8, layer.name, name)) {
                    return layer;
                }
            }
        }
        return null;
    }

    /// Set tile at coordinates on specified layer
    pub fn setTile(self: *Tilemap, layer_idx: u32, x: i32, y: i32, tile: Tile) !void {
        if (self.getLayer(layer_idx)) |layer| {
            try layer.setTile(x, y, tile);
        }
    }

    /// Get tile at coordinates on specified layer
    pub fn getTile(self: *Tilemap, layer_idx: u32, x: i32, y: i32) Tile {
        if (self.getLayer(layer_idx)) |layer| {
            return layer.getTile(x, y);
        }
        return .{};
    }

    /// Set tile by ID (convenience method that creates a Tile struct)
    pub fn setTileID(self: *Tilemap, layer_idx: u32, x: i32, y: i32, tile_id: TileID) !void {
        var tile = Tile{ .id = tile_id };

        // Apply collision from tileset if available
        if (self.tileset) |tileset| {
            tile.collision = tileset.getCollision(tile_id);
        }

        try self.setTile(layer_idx, x, y, tile);
    }

    /// Get tile ID at coordinates
    pub fn getTileID(self: *Tilemap, layer_idx: u32, x: i32, y: i32) TileID {
        return self.getTile(layer_idx, x, y).id;
    }

    /// Fill a rectangular region on a layer
    pub fn fill(self: *Tilemap, layer_idx: u32, x: i32, y: i32, w: u32, h: u32, tile: Tile) !void {
        if (self.getLayer(layer_idx)) |layer| {
            try layer.fill(x, y, w, h, tile);
        }
    }

    /// Check collision at world coordinates (checks all layers)
    pub fn checkCollision(self: *Tilemap, world_x: f32, world_y: f32) CollisionFlags {
        const coord = TileCoord.fromWorld(world_x, world_y, self.tile_width);
        return self.checkCollisionTile(coord.x, coord.y);
    }

    /// Check collision at tile coordinates (checks all layers)
    pub fn checkCollisionTile(self: *Tilemap, tile_x: i32, tile_y: i32) CollisionFlags {
        var combined = CollisionFlags.none;

        for (self.layers) |layer_opt| {
            if (layer_opt) |layer| {
                const tile = layer.getTile(tile_x, tile_y);
                // Combine collision flags using OR
                combined = @bitCast(@as(u8, @bitCast(combined)) | @as(u8, @bitCast(tile.collision)));
            }
        }

        return combined;
    }

    /// Check if a world point has solid collision
    pub fn isSolid(self: *Tilemap, world_x: f32, world_y: f32) bool {
        return self.checkCollision(world_x, world_y).solid;
    }

    /// Convert world coordinates to tile coordinates
    pub fn worldToTile(self: *Tilemap, world_x: f32, world_y: f32) TileCoord {
        return TileCoord.fromWorld(world_x, world_y, self.tile_width);
    }

    /// Convert tile coordinates to world coordinates (top-left)
    pub fn tileToWorld(self: *Tilemap, tile_x: i32, tile_y: i32) Vec2 {
        return TileCoord.init(tile_x, tile_y).toWorld(self.tile_width);
    }

    /// Convert tile coordinates to world coordinates (center)
    pub fn tileToWorldCenter(self: *Tilemap, tile_x: i32, tile_y: i32) Vec2 {
        return TileCoord.init(tile_x, tile_y).toWorldCenter(self.tile_width);
    }

    /// Get world bounds of the tilemap
    pub fn getWorldBounds(self: *Tilemap) struct { x: f32, y: f32, width: f32, height: f32 } {
        return .{
            .x = 0,
            .y = 0,
            .width = @as(f32, @floatFromInt(self.width * self.tile_width)),
            .height = @as(f32, @floatFromInt(self.height * self.tile_height)),
        };
    }

    /// Get visible tile range for a camera (for culling)
    pub fn getVisibleTileRange(self: *Tilemap, cam: *const camera.Camera2D) struct {
        min_x: i32,
        min_y: i32,
        max_x: i32,
        max_y: i32,
    } {
        const visible = cam.getVisibleRect();

        // Add padding of 1 tile for safety
        const ts_w: f32 = @floatFromInt(self.tile_width);
        const ts_h: f32 = @floatFromInt(self.tile_height);

        const min_x: i32 = @as(i32, @intFromFloat(@floor(visible.x / ts_w))) - 1;
        const min_y: i32 = @as(i32, @intFromFloat(@floor(visible.y / ts_h))) - 1;
        const max_x: i32 = @as(i32, @intFromFloat(@ceil((visible.x + visible.width) / ts_w))) + 1;
        const max_y: i32 = @as(i32, @intFromFloat(@ceil((visible.y + visible.height) / ts_h))) + 1;

        // Clamp to map bounds
        return .{
            .min_x = @max(0, min_x),
            .min_y = @max(0, min_y),
            .max_x = @min(@as(i32, @intCast(self.width)), max_x),
            .max_y = @min(@as(i32, @intCast(self.height)), max_y),
        };
    }

    /// Get visible chunk range for a camera (for efficient rendering)
    pub fn getVisibleChunkRange(self: *Tilemap, cam: *const camera.Camera2D) struct {
        min_x: u32,
        min_y: u32,
        max_x: u32,
        max_y: u32,
    } {
        const tile_range = self.getVisibleTileRange(cam);

        // Convert tile range to chunk range
        const min_cx: u32 = @intCast(@max(0, @divFloor(tile_range.min_x, @as(i32, CHUNK_SIZE))));
        const min_cy: u32 = @intCast(@max(0, @divFloor(tile_range.min_y, @as(i32, CHUNK_SIZE))));
        const max_cx: u32 = @intCast(@max(0, @divFloor(tile_range.max_x + @as(i32, CHUNK_SIZE) - 1, @as(i32, CHUNK_SIZE))));
        const max_cy: u32 = @intCast(@max(0, @divFloor(tile_range.max_y + @as(i32, CHUNK_SIZE) - 1, @as(i32, CHUNK_SIZE))));

        return .{
            .min_x = @min(min_cx, self.chunks_x),
            .min_y = @min(min_cy, self.chunks_y),
            .max_x = @min(max_cx, self.chunks_x),
            .max_y = @min(max_cy, self.chunks_y),
        };
    }

    // =========================================================================
    // Auto-Tiling
    // =========================================================================

    /// Add an auto-tile rule for a terrain type
    pub fn addAutoTileRule(self: *Tilemap, rule: AutoTileRule) !void {
        try self.auto_tile_rules.append(rule);
    }

    /// Get neighbor mask for a tile position on a layer (for auto-tiling)
    pub fn getNeighborMask(self: *Tilemap, layer_idx: u32, x: i32, y: i32, terrain: u8) NeighborMask {
        const layer = self.getLayer(layer_idx) orelse return .{};

        const isSameTerrain = struct {
            fn check(l: *const TileLayer, ts: ?*Tileset, tx: i32, ty: i32, t: u8) bool {
                const tile = l.getTile(tx, ty);
                if (tile.id == EMPTY_TILE) return false;
                if (ts) |tileset| {
                    return tileset.getAutoTileTerrain(tile.id) == t;
                }
                return false;
            }
        }.check;

        return .{
            .nw = isSameTerrain(layer, self.tileset, x - 1, y - 1, terrain),
            .n = isSameTerrain(layer, self.tileset, x, y - 1, terrain),
            .ne = isSameTerrain(layer, self.tileset, x + 1, y - 1, terrain),
            .w = isSameTerrain(layer, self.tileset, x - 1, y, terrain),
            .e = isSameTerrain(layer, self.tileset, x + 1, y, terrain),
            .sw = isSameTerrain(layer, self.tileset, x - 1, y + 1, terrain),
            .s = isSameTerrain(layer, self.tileset, x, y + 1, terrain),
            .se = isSameTerrain(layer, self.tileset, x + 1, y + 1, terrain),
        };
    }

    /// Apply auto-tiling to update tile variants based on neighbors
    pub fn updateAutoTile(self: *Tilemap, layer_idx: u32, x: i32, y: i32) void {
        const layer = self.getLayer(layer_idx) orelse return;
        const tileset = self.tileset orelse return;

        var tile = layer.getTile(x, y);
        if (tile.id == EMPTY_TILE) return;

        const terrain = tileset.getAutoTileTerrain(tile.id);
        if (terrain == 0) return; // Not an auto-tile

        // Find matching rule
        for (self.auto_tile_rules.items) |rule| {
            if (rule.terrain == terrain) {
                const mask = self.getNeighborMask(layer_idx, x, y, terrain);
                tile.auto_tile_variant = rule.variant_map[mask.toU8()];
                // Update the tile ID based on variant
                tile.id = rule.base_tile_id + tile.auto_tile_variant;
                layer.setTile(x, y, tile) catch {};
                return;
            }
        }
    }

    /// Update auto-tiling for a region
    pub fn updateAutoTileRegion(self: *Tilemap, layer_idx: u32, x: i32, y: i32, w: u32, h: u32) void {
        // Expand region by 1 to update neighbors
        const start_x = x - 1;
        const start_y = y - 1;
        const end_x = x + @as(i32, @intCast(w)) + 1;
        const end_y = y + @as(i32, @intCast(h)) + 1;

        var ty = start_y;
        while (ty < end_y) : (ty += 1) {
            var tx = start_x;
            while (tx < end_x) : (tx += 1) {
                self.updateAutoTile(layer_idx, tx, ty);
            }
        }
    }

    // =========================================================================
    // Iterator for efficient rendering
    // =========================================================================

    /// Iterator over visible tiles for a layer
    pub const VisibleTileIterator = struct {
        tilemap: *Tilemap,
        layer: *TileLayer,
        current_x: i32,
        current_y: i32,
        min_x: i32,
        max_x: i32,
        max_y: i32,

        pub const Entry = struct {
            x: i32,
            y: i32,
            tile: Tile,
            world_x: f32,
            world_y: f32,
        };

        pub fn next(self: *VisibleTileIterator) ?Entry {
            while (self.current_y < self.max_y) {
                while (self.current_x < self.max_x) {
                    const x = self.current_x;
                    const y = self.current_y;
                    self.current_x += 1;

                    const tile = self.layer.getTile(x, y);
                    if (tile.id != EMPTY_TILE) {
                        const world_pos = self.tilemap.tileToWorld(x, y);
                        return .{
                            .x = x,
                            .y = y,
                            .tile = tile,
                            .world_x = world_pos.x,
                            .world_y = world_pos.y,
                        };
                    }
                }
                self.current_x = self.min_x;
                self.current_y += 1;
            }
            return null;
        }
    };

    /// Get iterator over visible tiles for a layer
    pub fn visibleTileIterator(self: *Tilemap, layer_idx: u32, cam: *const camera.Camera2D) ?VisibleTileIterator {
        const layer = self.getLayer(layer_idx) orelse return null;
        const range = self.getVisibleTileRange(cam);

        return .{
            .tilemap = self,
            .layer = layer,
            .current_x = range.min_x,
            .current_y = range.min_y,
            .min_x = range.min_x,
            .max_x = range.max_x,
            .max_y = range.max_y,
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "tilemap - TileCoord world conversion" {
    const coord = TileCoord.fromWorld(100.0, 75.0, 32);
    try std.testing.expectEqual(@as(i32, 3), coord.x);
    try std.testing.expectEqual(@as(i32, 2), coord.y);

    const world = coord.toWorld(32);
    try std.testing.expectApproxEqRel(@as(f32, 96.0), world.x, 0.001);
    try std.testing.expectApproxEqRel(@as(f32, 64.0), world.y, 0.001);

    const center = coord.toWorldCenter(32);
    try std.testing.expectApproxEqRel(@as(f32, 112.0), center.x, 0.001);
    try std.testing.expectApproxEqRel(@as(f32, 80.0), center.y, 0.001);
}

test "tilemap - TileCoord bounds checking" {
    const in_bounds = TileCoord.init(5, 5);
    try std.testing.expect(in_bounds.isInBounds(10, 10));
    try std.testing.expect(!in_bounds.isInBounds(5, 5));

    const negative = TileCoord.init(-1, 5);
    try std.testing.expect(!negative.isInBounds(10, 10));
}

test "tilemap - TileChunk basic operations" {
    var chunk = TileChunk.init();

    try std.testing.expect(chunk.isEmpty());
    try std.testing.expectEqual(@as(u32, 0), chunk.tile_count);

    // Set a tile
    chunk.setTile(5, 5, .{ .id = 1 });
    try std.testing.expect(!chunk.isEmpty());
    try std.testing.expectEqual(@as(u32, 1), chunk.tile_count);

    // Get the tile
    const tile = chunk.getTile(5, 5);
    try std.testing.expectEqual(@as(TileID, 1), tile.id);

    // Clear the tile
    chunk.setTile(5, 5, .{ .id = EMPTY_TILE });
    try std.testing.expect(chunk.isEmpty());
}

test "tilemap - TileChunk out of bounds" {
    var chunk = TileChunk.init();

    // Out of bounds get returns empty
    const tile = chunk.getTile(100, 100);
    try std.testing.expectEqual(EMPTY_TILE, tile.id);

    // Out of bounds set is ignored
    chunk.setTile(100, 100, .{ .id = 1 });
    try std.testing.expect(chunk.isEmpty());
}

test "tilemap - TileLayer basic operations" {
    const allocator = std.testing.allocator;

    var layer = try TileLayer.init(allocator, "test", 4, 4, 0);
    defer layer.deinit();

    // Initially all empty
    const tile = layer.getTile(0, 0);
    try std.testing.expectEqual(EMPTY_TILE, tile.id);

    // Set and get tile
    try layer.setTile(10, 10, .{ .id = 5, .collision = CollisionFlags.solid_only });
    const tile2 = layer.getTile(10, 10);
    try std.testing.expectEqual(@as(TileID, 5), tile2.id);
    try std.testing.expect(tile2.collision.solid);
}

test "tilemap - TileLayer fill" {
    const allocator = std.testing.allocator;

    var layer = try TileLayer.init(allocator, "test", 4, 4, 0);
    defer layer.deinit();

    try layer.fill(0, 0, 5, 5, .{ .id = 1 });

    // Check corners
    try std.testing.expectEqual(@as(TileID, 1), layer.getTile(0, 0).id);
    try std.testing.expectEqual(@as(TileID, 1), layer.getTile(4, 4).id);
    try std.testing.expectEqual(EMPTY_TILE, layer.getTile(5, 5).id);
}

test "tilemap - TileLayer clear" {
    const allocator = std.testing.allocator;

    var layer = try TileLayer.init(allocator, "test", 2, 2, 0);
    defer layer.deinit();

    try layer.fill(0, 0, 32, 32, .{ .id = 1 });
    try std.testing.expectEqual(@as(TileID, 1), layer.getTile(0, 0).id);

    layer.clear();
    try std.testing.expectEqual(EMPTY_TILE, layer.getTile(0, 0).id);
}

test "tilemap - Tileset UV calculation" {
    const allocator = std.testing.allocator;

    var tileset = try Tileset.init(allocator, .{
        .tile_width = 32,
        .tile_height = 32,
        .texture_width = 128,
        .texture_height = 128,
        .spacing = 0,
        .margin = 0,
    });
    defer tileset.deinit();

    try std.testing.expectEqual(@as(u32, 4), tileset.columns);
    try std.testing.expectEqual(@as(u32, 4), tileset.rows);
    try std.testing.expectEqual(@as(u32, 16), tileset.tile_count);

    // First tile (ID 1)
    const uv1 = tileset.getTileUV(1).?;
    try std.testing.expectApproxEqRel(@as(f32, 0.0), uv1.u0, 0.001);
    try std.testing.expectApproxEqRel(@as(f32, 0.0), uv1.v0, 0.001);
    try std.testing.expectApproxEqRel(@as(f32, 0.25), uv1.u1, 0.001);
    try std.testing.expectApproxEqRel(@as(f32, 0.25), uv1.v1, 0.001);

    // Second tile (ID 2) - next column
    const uv2 = tileset.getTileUV(2).?;
    try std.testing.expectApproxEqRel(@as(f32, 0.25), uv2.u0, 0.001);
    try std.testing.expectApproxEqRel(@as(f32, 0.0), uv2.v0, 0.001);
}

test "tilemap - Tileset collision flags" {
    const allocator = std.testing.allocator;

    var tileset = try Tileset.init(allocator, .{
        .tile_width = 32,
        .tile_height = 32,
        .texture_width = 128,
        .texture_height = 128,
    });
    defer tileset.deinit();

    // Default is no collision
    try std.testing.expect(!tileset.getCollision(1).solid);

    // Set collision
    tileset.setCollision(1, CollisionFlags.solid_only);
    try std.testing.expect(tileset.getCollision(1).solid);

    // Set range
    tileset.setCollisionRange(5, 10, .{ .solid = true, .water = true });
    try std.testing.expect(tileset.getCollision(5).solid);
    try std.testing.expect(tileset.getCollision(5).water);
    try std.testing.expect(tileset.getCollision(10).solid);
}

test "tilemap - Tilemap basic operations" {
    const allocator = std.testing.allocator;

    var tilemap = Tilemap.init(allocator, .{ .width = 100, .height = 100, .tile_width = 32, .tile_height = 32 });
    defer tilemap.deinit();

    // Add layers
    const ground = try tilemap.addLayer("ground");
    const objects = try tilemap.addLayer("objects");

    try std.testing.expectEqual(@as(u32, 0), ground);
    try std.testing.expectEqual(@as(u32, 1), objects);
    try std.testing.expectEqual(@as(u32, 2), tilemap.layer_count);

    // Get layer by name
    const found = tilemap.getLayerByName("ground");
    try std.testing.expect(found != null);
    try std.testing.expect(std.mem.eql(u8, found.?.name, "ground"));

    // Set and get tiles
    try tilemap.setTileID(ground, 5, 5, 1);
    try std.testing.expectEqual(@as(TileID, 1), tilemap.getTileID(ground, 5, 5));
}

test "tilemap - Tilemap collision checking" {
    const allocator = std.testing.allocator;

    var tileset = try Tileset.init(allocator, .{
        .tile_width = 32,
        .tile_height = 32,
        .texture_width = 128,
        .texture_height = 128,
    });
    defer tileset.deinit();

    tileset.setCollision(1, CollisionFlags.solid_only);

    var tilemap = Tilemap.init(allocator, .{ .width = 100, .height = 100, .tile_width = 32, .tile_height = 32 });
    defer tilemap.deinit();

    tilemap.setTileset(&tileset);

    const layer = try tilemap.addLayer("ground");
    try tilemap.setTileID(layer, 5, 5, 1);

    // Check collision at tile coordinates
    try std.testing.expect(tilemap.checkCollisionTile(5, 5).solid);
    try std.testing.expect(!tilemap.checkCollisionTile(6, 6).solid);

    // Check collision at world coordinates (tile 5,5 = world 160-192, 160-192)
    try std.testing.expect(tilemap.isSolid(170.0, 170.0));
    try std.testing.expect(!tilemap.isSolid(200.0, 200.0));
}

test "tilemap - Tilemap world coordinate conversion" {
    const allocator = std.testing.allocator;

    var tilemap = Tilemap.init(allocator, .{ .width = 100, .height = 100, .tile_width = 32, .tile_height = 32 });
    defer tilemap.deinit();

    // World to tile
    const coord = tilemap.worldToTile(100.0, 75.0);
    try std.testing.expectEqual(@as(i32, 3), coord.x);
    try std.testing.expectEqual(@as(i32, 2), coord.y);

    // Tile to world
    const world = tilemap.tileToWorld(3, 2);
    try std.testing.expectApproxEqRel(@as(f32, 96.0), world.x, 0.001);
    try std.testing.expectApproxEqRel(@as(f32, 64.0), world.y, 0.001);

    // World bounds
    const bounds = tilemap.getWorldBounds();
    try std.testing.expectApproxEqRel(@as(f32, 3200.0), bounds.width, 0.001);
    try std.testing.expectApproxEqRel(@as(f32, 3200.0), bounds.height, 0.001);
}

test "tilemap - Tilemap visible tile range" {
    const allocator = std.testing.allocator;

    var tilemap = Tilemap.init(allocator, .{ .width = 100, .height = 100, .tile_width = 32, .tile_height = 32 });
    defer tilemap.deinit();

    // Create camera centered at (500, 300) with zoom 1.0
    var cam = camera.Camera2D.init(.{
        .position = camera.Vec2.init(500.0, 300.0),
        .zoom = 1.0,
    });

    const range = tilemap.getVisibleTileRange(&cam);

    // Visible rect is 1920x1080 centered at (500, 300)
    // Min: (500 - 960, 300 - 540) = (-460, -240) -> tile (-15, -8) but clamped to (0, 0)
    // Max: (500 + 960, 300 + 540) = (1460, 840) -> tile (46, 27)
    try std.testing.expect(range.min_x >= 0);
    try std.testing.expect(range.min_y >= 0);
    try std.testing.expect(range.max_x <= 100);
    try std.testing.expect(range.max_y <= 100);
}

test "tilemap - NeighborMask bit operations" {
    const mask = NeighborMask{
        .n = true,
        .s = true,
        .e = true,
        .w = true,
    };

    const value = mask.toU8();
    const recovered = NeighborMask.fromU8(value);

    try std.testing.expect(recovered.n);
    try std.testing.expect(recovered.s);
    try std.testing.expect(recovered.e);
    try std.testing.expect(recovered.w);
    try std.testing.expect(!recovered.ne);
    try std.testing.expect(!recovered.nw);
}

test "tilemap - CollisionFlags packed struct" {
    const flags = CollisionFlags{
        .solid = true,
        .water = true,
        .damage = true,
    };

    try std.testing.expect(flags.solid);
    try std.testing.expect(flags.water);
    try std.testing.expect(flags.damage);
    try std.testing.expect(!flags.pit);
    try std.testing.expect(!flags.platform);

    // Test combining flags with bitwise OR
    const flags2 = CollisionFlags{ .pit = true };
    const combined: CollisionFlags = @bitCast(@as(u8, @bitCast(flags)) | @as(u8, @bitCast(flags2)));

    try std.testing.expect(combined.solid);
    try std.testing.expect(combined.pit);
}

test "tilemap - Tilemap chunk calculation" {
    const allocator = std.testing.allocator;

    // 100x100 tiles should need 4x4 chunks (32 tiles per chunk)
    var tilemap = Tilemap.init(allocator, .{ .width = 100, .height = 100 });
    defer tilemap.deinit();

    try std.testing.expectEqual(@as(u32, 4), tilemap.chunks_x);
    try std.testing.expectEqual(@as(u32, 4), tilemap.chunks_y);

    // 33x33 tiles should need 2x2 chunks
    var tilemap2 = Tilemap.init(allocator, .{ .width = 33, .height = 33 });
    defer tilemap2.deinit();

    try std.testing.expectEqual(@as(u32, 2), tilemap2.chunks_x);
    try std.testing.expectEqual(@as(u32, 2), tilemap2.chunks_y);
}

test "tilemap - Tilemap visible tile iterator" {
    const allocator = std.testing.allocator;

    var tilemap = Tilemap.init(allocator, .{ .width = 100, .height = 100, .tile_width = 32 });
    defer tilemap.deinit();

    const layer = try tilemap.addLayer("ground");

    // Set some tiles
    try tilemap.setTileID(layer, 5, 5, 1);
    try tilemap.setTileID(layer, 10, 10, 2);
    try tilemap.setTileID(layer, 50, 50, 3); // Outside visible area

    // Create camera that can see tiles 0-60
    var cam = camera.Camera2D.init(.{
        .position = camera.Vec2.init(960.0, 540.0), // Center at screen center
        .zoom = 1.0,
    });

    var iter = tilemap.visibleTileIterator(layer, &cam).?;
    var count: u32 = 0;

    while (iter.next()) |entry| {
        count += 1;
        try std.testing.expect(entry.tile.id != EMPTY_TILE);
        // All found tiles should be in visible range
        try std.testing.expect(entry.x >= 0);
        try std.testing.expect(entry.y >= 0);
        _ = entry.world_x; // Used for rendering
        _ = entry.world_y;
    }

    // Should find at least the tiles in visible range
    try std.testing.expect(count >= 2);
}

test "tilemap - sparse chunk allocation" {
    const allocator = std.testing.allocator;

    var layer = try TileLayer.init(allocator, "test", 10, 10, 0);
    defer layer.deinit();

    // Initially no chunks allocated
    for (layer.chunks) |chunk| {
        try std.testing.expect(chunk == null);
    }

    // Setting a tile allocates the chunk
    try layer.setTile(0, 0, .{ .id = 1 });
    try std.testing.expect(layer.chunks[0] != null);

    // Other chunks still null
    try std.testing.expect(layer.chunks[1] == null);

    // Setting tile in another chunk allocates it
    try layer.setTile(32, 0, .{ .id = 2 });
    try std.testing.expect(layer.chunks[1] != null);
}
