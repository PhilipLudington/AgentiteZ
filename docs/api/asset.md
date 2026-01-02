# Asset System

Unified resource management with reference counting (`src/asset.zig`).

## Features

- **Asset handles** - Type-safe references with generation counters to detect stale handles
- **Asset registry** - Central storage with automatic reference counting
- **Loading abstraction** - Register custom loaders for any asset type
- **Dependency tracking** - Assets can depend on other assets
- **Asset bundles** - Group related assets for batch loading/unloading
- **Type safety** - Generic typed handles for compile-time type checking

## Usage

### Basic Setup

```zig
const asset = @import("AgentiteZ").asset;

// Initialize registry
var registry = asset.AssetRegistry.init(allocator);
defer registry.deinit();

// Optionally set asset root directory
try registry.setAssetRoot("assets");
```

### Registering a Loader

```zig
const TextureData = struct {
    width: u32,
    height: u32,
    pixels: []u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *TextureData) void {
        self.allocator.free(self.pixels);
    }
};

// Define loader functions
const TextureLoader = struct {
    fn load(path: []const u8, alloc: std.mem.Allocator) asset.LoadError!*anyopaque {
        const file = std.fs.cwd().openFile(path, .{}) catch return asset.LoadError.FileNotFound;
        defer file.close();

        // Load texture data...
        const data = alloc.create(TextureData) catch return asset.LoadError.OutOfMemory;
        data.* = .{
            .width = 256,
            .height = 256,
            .pixels = alloc.alloc(u8, 256 * 256 * 4) catch return asset.LoadError.OutOfMemory,
            .allocator = alloc,
        };
        return @ptrCast(data);
    }

    fn unload(data: *anyopaque, alloc: std.mem.Allocator) void {
        const typed: *TextureData = @ptrCast(@alignCast(data));
        typed.deinit();
        alloc.destroy(typed);
    }
};

// Register the loader
try registry.registerLoader(.texture, TextureLoader.load, TextureLoader.unload);
```

### Loading Assets

```zig
// Get or create a handle for an asset
const handle = try registry.getOrCreateHandle("player.png");

// Load the asset (increases reference count)
try registry.load(handle);

// Or use convenience function
const handle2 = try registry.loadByPath("enemy.png");

// Check if loaded
if (registry.isLoaded(handle)) {
    // Use the asset
}
```

### Accessing Asset Data

```zig
// Type-safe access
const texture = registry.getData(TextureData, handle);
if (texture) |tex| {
    // Use tex.width, tex.height, tex.pixels
}

// Raw data access
const raw = registry.getRawData(handle);
```

### Reference Counting

```zig
// Load same asset multiple times
try registry.load(handle); // ref_count = 1
try registry.load(handle); // ref_count = 2

// Add reference without loading
registry.addRef(handle); // ref_count = 3

// Release references
registry.release(handle); // ref_count = 2
registry.release(handle); // ref_count = 1
registry.release(handle); // ref_count = 0, asset unloaded

// Force unload regardless of reference count
registry.forceUnload(handle);
```

### Typed Handles

```zig
const TextureHandle = asset.TypedHandle(TextureData);

// Create typed handle from raw handle
const typed = TextureHandle.init(raw_handle);

// Type-safe access
const tex = typed.get(&registry);

// Release
typed.release(&registry);
```

### Dependency Tracking

```zig
// asset_a depends on asset_b
const handle_a = try registry.getOrCreateHandle("sprite_sheet.png");
const handle_b = try registry.getOrCreateHandle("palette.dat");

try registry.addDependency(handle_a, handle_b);

// When handle_a is loaded, handle_b's ref_count increases
// When handle_a is released, handle_b is also released (if ref_count reaches 0)
```

### Asset Bundles

```zig
var bundle = try asset.AssetBundle.init(allocator, "level1");
defer bundle.deinit();

// Add assets to bundle
try bundle.add(try registry.getOrCreateHandle("bg.png"));
try bundle.add(try registry.getOrCreateHandle("music.ogg"));
try bundle.add(try registry.getOrCreateHandle("tileset.png"));

// Load all at once
try bundle.loadAll(&registry);

// Check progress
const progress = bundle.getProgress(&registry); // 0.0 to 1.0

// Check if fully loaded
if (bundle.isLoaded(&registry)) {
    // All assets ready
}

// Release all when done
bundle.releaseAll(&registry);
```

### Querying Asset State

```zig
// Get current state
const state = registry.getState(handle);
switch (state.?) {
    .unloaded => {},
    .loading => {},
    .loaded => {},
    .failed => {},
    .unloading => {},
}

// Get metadata
if (registry.getMetadata(handle)) |meta| {
    const path = meta.path;
    const asset_type = meta.asset_type;
    const ref_count = meta.ref_count;
    const size = meta.size_bytes;

    // Check for errors
    if (meta.error_message) |err| {
        std.debug.print("Load failed: {s}\n", .{err});
    }
}
```

### Iterating Loaded Assets

```zig
var iter = registry.iterateLoaded();
while (iter.next()) |handle| {
    const meta = registry.getMetadata(handle).?;
    std.debug.print("Loaded: {s}\n", .{meta.path});
}
```

### Statistics

```zig
const stats = registry.getStats();
std.debug.print("Active: {d}, Loaded: {d}, Failed: {d}\n", .{
    stats.active_assets,
    stats.total_loaded,
    stats.total_failed,
});

// Memory usage estimate
const bytes = registry.getTotalMemoryUsage();
```

## Asset Types

The system auto-detects asset types from file extensions:

| Extension | Type |
|-----------|------|
| `.png`, `.jpg`, `.jpeg`, `.bmp`, `.tga` | texture |
| `.wav` | sound |
| `.ogg`, `.mp3` | music |
| `.ttf`, `.otf` | font |
| `.toml`, `.json` | data |
| `.prefab` | prefab |
| `.scene` | scene |
| `.tilemap` | tilemap |

## Data Structures

- `AssetHandle` - Index + generation counter for safe references
- `AssetMetadata` - Path, type, state, ref count, dependencies
- `AssetRegistry` - Central manager with loaders and slot storage
- `AssetBundle` - Collection of related assets
- `TypedHandle(T)` - Generic compile-time type-safe handle wrapper

## Handle Safety

Handles use generation counters to prevent use-after-free bugs:

```zig
// Get handle to asset
const handle = try registry.getOrCreateHandle("texture.png");
try registry.load(handle);
registry.release(handle); // Asset unloaded, slot freed

// Later, slot gets reused for different asset
const new_handle = try registry.getOrCreateHandle("other.png");

// Old handle is detected as invalid (generation mismatch)
if (!registry.isHandleValid(handle)) {
    // Handle is stale, don't use it
}
```

## Error Handling

```zig
const result = registry.load(handle);
result catch |err| switch (err) {
    LoadError.FileNotFound => {},
    LoadError.InvalidFormat => {},
    LoadError.OutOfMemory => {},
    LoadError.IoError => {},
    LoadError.UnsupportedFormat => {},
    LoadError.DependencyFailed => {},
    LoadError.LoaderNotRegistered => {},
    LoadError.AlreadyLoaded => {},
};
```

## Integration with Scene System

The asset system integrates with the scene system for automatic asset lifecycle:

```zig
// Scene definition lists required assets
// When scene loads, assets are loaded via AssetRegistry
// When scene unloads, asset references are released
```

## Technical Details

- Sparse slot array with free list for efficient allocation/reuse
- Path-to-handle HashMap for O(1) lookup by path
- Reference counting with automatic unload at zero refs
- Dependency graph prevents premature unloading of shared assets
- Thread-safe design (mutex protection for async loading - future)

## Tests

14 tests covering handle operations, type detection, metadata, registry operations, loader registration, reference counting, dependency tracking, bundles, iteration, and path lookup.
