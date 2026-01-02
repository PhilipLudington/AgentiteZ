# Async Loading System

Background resource loading with thread pool (`src/async_loader.zig`).

## Features

- **Thread pool** - Configurable worker threads for I/O operations
- **Load priorities** - Critical, high, normal, low priority levels
- **Progress callbacks** - Optional per-asset progress tracking
- **Completion events** - Callbacks fired on main thread when loading completes
- **Cancellation** - Cancel pending or in-progress loads
- **Batch loading** - Helper for loading multiple assets with aggregate progress

## Usage

### Basic Setup

```zig
const AgentiteZ = @import("AgentiteZ");
const asset = AgentiteZ.asset;
const async_loader = AgentiteZ.async_loader;

// First initialize asset registry
var registry = asset.AssetRegistry.init(allocator);
defer registry.deinit();

// Register loaders as usual
try registry.registerLoader(.texture, TextureLoader.load, TextureLoader.unload);

// Initialize async loader
var loader = try async_loader.AsyncLoader.init(allocator, &registry, .{});
defer loader.deinit();
```

### Configuration

```zig
const config = async_loader.AsyncLoaderConfig{
    // Number of worker threads (0 = auto-detect from CPU cores)
    .thread_count = 4,
    // Maximum pending requests in queue
    .max_pending_requests = 1024,
    // Maximum completed items waiting for main thread
    .max_completion_queue = 256,
    // Enable verbose logging
    .verbose = false,
};

var loader = try async_loader.AsyncLoader.init(allocator, &registry, config);
```

### Loading Assets Asynchronously

```zig
// Define completion callback
fn onTextureLoaded(result: async_loader.AsyncLoadResult, context: ?*anyopaque) void {
    const game: *Game = @ptrCast(@alignCast(context.?));

    if (result.success) {
        std.debug.print("Loaded asset in {d}ms\n", .{result.load_time_ns / 1_000_000});
        game.textureReady(result.handle);
    } else {
        std.debug.print("Failed to load: {any}\n", .{result.err});
    }
}

// Queue an async load
const handle = try registry.getOrCreateHandle("player.png");
const request_id = try loader.loadAsync(handle, .normal, onTextureLoaded, game);
```

### Load Priorities

```zig
// Critical - blocks game progress (loading screens)
_ = try loader.loadAsync(handle, .critical, callback, ctx);

// High - needed soon (next area preload)
_ = try loader.loadAsync(handle, .high, callback, ctx);

// Normal - standard loading
_ = try loader.loadAsync(handle, .normal, callback, ctx);

// Low - speculative preloading
_ = try loader.loadAsync(handle, .low, callback, ctx);
```

Higher priority assets are loaded first. Within the same priority, requests are processed FIFO (oldest first).

### Progress Callbacks

```zig
fn onProgress(
    request_id: async_loader.RequestId,
    bytes_loaded: usize,
    total_bytes: ?usize,
    context: ?*anyopaque,
) void {
    if (total_bytes) |total| {
        const percent = @as(f32, @floatFromInt(bytes_loaded)) / @as(f32, @floatFromInt(total)) * 100.0;
        std.debug.print("Loading: {d:.1}%\n", .{percent});
    }
}

_ = try loader.loadAsyncWithProgress(handle, .normal, onComplete, onProgress, ctx);
```

### Processing Completions

Call this once per frame from the main thread to fire completion callbacks:

```zig
// In your game loop
fn update(loader: *async_loader.AsyncLoader) void {
    // Process all completed loads
    const processed = loader.processCompletions();

    // Do other game updates...
}
```

This is important because:
- Callbacks run on the main thread (safe for GPU operations)
- Allows controlled timing of asset initialization
- Prevents race conditions in game state

### Cancellation

```zig
// Cancel a specific request
const request_id = try loader.loadAsync(handle, .normal, callback, ctx);
// ...later...
const cancelled = loader.cancel(request_id);
if (cancelled) {
    std.debug.print("Request was cancelled\n", .{});
}

// Cancel all pending requests
const count = loader.cancelAll();
std.debug.print("Cancelled {d} requests\n", .{count});
```

Cancelled requests don't fire completion callbacks.

### Batch Loading

For loading multiple assets with aggregate progress tracking:

```zig
var batch = async_loader.BatchLoader.init(allocator, loader);
defer batch.deinit();

// Set batch progress callback
batch.setCallback(struct {
    fn onBatchProgress(completed: usize, total: usize, all_done: bool, ctx: ?*anyopaque) void {
        const progress = @as(f32, @floatFromInt(completed)) / @as(f32, @floatFromInt(total));
        updateLoadingBar(progress);

        if (all_done) {
            transitionToGameplay();
        }
    }
}.onBatchProgress, game);

// Add assets to batch
try batch.add(try registry.getOrCreateHandle("level1/bg.png"), .normal);
try batch.add(try registry.getOrCreateHandle("level1/tileset.png"), .normal);
try batch.add(try registry.getOrCreateHandle("level1/music.ogg"), .low);
try batch.add(try registry.getOrCreateHandle("level1/enemies.png"), .normal);

// Check progress
const progress = batch.getProgress(); // 0.0 to 1.0

// Check completion
if (batch.isComplete()) {
    const loaded = batch.getCompletedCount();
    const failed = batch.getFailedCount();
}

// Cancel batch if needed
batch.cancelAll();
```

### Querying State

```zig
// Check if a request is still pending/active
if (loader.isRequestPending(request_id)) {
    // Still loading...
}

// Get counts
const pending = loader.getPendingCount();
const active = loader.getActiveCount();
```

### Statistics

```zig
const stats = loader.getStats();
std.debug.print("Queued: {d}\n", .{stats.total_queued});
std.debug.print("Completed: {d}\n", .{stats.total_completed});
std.debug.print("Failed: {d}\n", .{stats.total_failed});
std.debug.print("Cancelled: {d}\n", .{stats.total_cancelled});
std.debug.print("Pending: {d}\n", .{stats.pending_count});
std.debug.print("Avg load time: {d:.2}ms\n", .{stats.getAverageLoadTimeMs()});
```

## Load Priorities

| Priority | Value | Use Case |
|----------|-------|----------|
| `critical` | 0 | Required for progress (loading screens) |
| `high` | 1 | Needed soon (next area, imminent spawns) |
| `normal` | 2 | Standard loading |
| `low` | 3 | Speculative preloading, optional content |

## Data Structures

- `LoadPriority` - Enum for load priority levels
- `RequestId` - Unique identifier for tracking requests
- `AsyncLoadResult` - Result struct with success/error and timing
- `CompletionCallback` - Function pointer for completion notifications
- `ProgressCallback` - Function pointer for progress updates
- `AsyncLoader` - Main async loading system with thread pool
- `AsyncLoaderStats` - Statistics counters
- `BatchLoader` - Helper for multi-asset loading

## Thread Safety

The async loader uses internal mutexes for thread safety:

- Request queue protected by `request_mutex`
- Active requests protected by `active_mutex`
- Completion queue protected by `completion_mutex`
- Statistics protected by `stats_mutex`

**Important:** Completion callbacks are always called on the main thread (via `processCompletions()`), so they can safely access game state and perform GPU operations.

## Error Handling

```zig
const result = loader.loadAsync(handle, .normal, callback, ctx);
result catch |err| switch (err) {
    async_loader.AsyncLoadError.InvalidHandle => {},
    async_loader.AsyncLoadError.QueueFull => {},
    async_loader.AsyncLoadError.ShuttingDown => {},
};
```

Load errors are reported via the completion callback's `result.err` field.

## Integration with Asset System

The async loader builds on top of the `AssetRegistry`:

```zig
// Async loader wraps synchronous registry.load()
// Worker threads call registry.load() in background
// Completion callbacks fire after load completes
// Asset reference counting works normally
```

Assets loaded asynchronously follow the same reference counting rules:

```zig
// Async load increases ref_count like sync load
_ = try loader.loadAsync(handle, .normal, callback, ctx);
// When done, release normally
registry.release(handle);
```

## Typical Loading Screen Pattern

```zig
const LoadingScreen = struct {
    batch: async_loader.BatchLoader,
    progress: f32,
    done: bool,

    pub fn init(allocator: std.mem.Allocator, loader: *async_loader.AsyncLoader) LoadingScreen {
        var batch = async_loader.BatchLoader.init(allocator, loader);
        batch.setCallback(onProgress, null);
        return .{ .batch = batch, .progress = 0, .done = false };
    }

    pub fn loadLevel(self: *LoadingScreen, registry: *asset.AssetRegistry, level: []const u8) !void {
        // Add all level assets
        try self.batch.add(try registry.getOrCreateHandle("levels/{s}/bg.png", .{level}), .critical);
        try self.batch.add(try registry.getOrCreateHandle("levels/{s}/tileset.png", .{level}), .critical);
        try self.batch.add(try registry.getOrCreateHandle("levels/{s}/music.ogg", .{level}), .normal);
    }

    pub fn update(self: *LoadingScreen, loader: *async_loader.AsyncLoader) void {
        _ = loader.processCompletions();
        self.progress = self.batch.getProgress();
        self.done = self.batch.isComplete();
    }

    pub fn render(self: *LoadingScreen) void {
        drawProgressBar(self.progress);
        if (self.done) {
            drawPressStartPrompt();
        }
    }

    fn onProgress(completed: usize, total: usize, all_done: bool, _: ?*anyopaque) void {
        _ = completed;
        _ = total;
        _ = all_done;
        // Progress is tracked via getProgress()
    }
};
```

## Technical Details

- Worker threads wait on condition variable when queue is empty
- Requests are sorted by priority on insert (stable sort)
- Atomic operations used for cancellation flags
- Completion queue is FIFO for deterministic callback order
- Thread count auto-detection uses half of available CPU cores

## Tests

12 tests covering priority ordering, statistics, request lifecycle, cancellation, queue management, and batch operations.
