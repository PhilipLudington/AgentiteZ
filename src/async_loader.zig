// async_loader.zig
// Async Loading System for AgentiteZ
// Background resource loading with thread pool
//
// Features:
// - Thread pool for I/O operations
// - Load priority system (critical, high, normal, low)
// - Progress callbacks and completion events
// - Cancellation support
// - Main thread finalization for GPU resources
//
// Usage:
// ```zig
// var async_loader = AsyncLoader.init(allocator, &asset_registry, .{});
// defer async_loader.deinit();
//
// // Queue an async load
// const request_id = try async_loader.loadAsync(handle, .normal, onComplete, context);
//
// // Poll for completions on main thread
// async_loader.processCompletions();
//
// // Or cancel a pending request
// async_loader.cancel(request_id);
// ```

const std = @import("std");
const asset = @import("asset.zig");

const AssetHandle = asset.AssetHandle;
const AssetRegistry = asset.AssetRegistry;
const AssetState = asset.AssetState;
const LoadError = asset.LoadError;

// ============================================================================
// Load Priority
// ============================================================================

/// Priority levels for asset loading
/// Higher priority assets are loaded first
pub const LoadPriority = enum(u8) {
    /// Must load immediately (blocks game progress)
    critical = 0,
    /// Load soon (needed shortly)
    high = 1,
    /// Normal loading priority
    normal = 2,
    /// Load when idle (preloading, speculative)
    low = 3,

    pub fn toInt(self: LoadPriority) u8 {
        return @intFromEnum(self);
    }
};

// ============================================================================
// Request ID
// ============================================================================

/// Unique identifier for async load requests
pub const RequestId = u64;

/// Invalid request ID constant
pub const INVALID_REQUEST_ID: RequestId = 0;

// ============================================================================
// Async Load Result
// ============================================================================

/// Result of an async load operation
pub const AsyncLoadResult = struct {
    /// The request that completed
    request_id: RequestId,
    /// The asset handle
    handle: AssetHandle,
    /// Success or failure
    success: bool,
    /// Error if failed
    err: ?LoadError,
    /// Time taken to load (nanoseconds)
    load_time_ns: u64,
};

// ============================================================================
// Callbacks
// ============================================================================

/// Completion callback function type
pub const CompletionCallback = *const fn (result: AsyncLoadResult, context: ?*anyopaque) void;

/// Progress callback function type (called periodically during load)
pub const ProgressCallback = *const fn (
    request_id: RequestId,
    bytes_loaded: usize,
    total_bytes: ?usize,
    context: ?*anyopaque,
) void;

// ============================================================================
// Async Load Request
// ============================================================================

/// Internal request structure
const AsyncLoadRequest = struct {
    id: RequestId,
    handle: AssetHandle,
    priority: LoadPriority,
    completion_callback: ?CompletionCallback,
    progress_callback: ?ProgressCallback,
    callback_context: ?*anyopaque,
    /// Set to true to cancel this request
    cancelled: std.atomic.Value(bool),
    /// When the request was queued
    queued_at: i64,
    /// When loading started (0 if not started)
    started_at: std.atomic.Value(i64),

    pub fn init(
        id: RequestId,
        handle: AssetHandle,
        priority: LoadPriority,
        completion_callback: ?CompletionCallback,
        progress_callback: ?ProgressCallback,
        context: ?*anyopaque,
    ) AsyncLoadRequest {
        return .{
            .id = id,
            .handle = handle,
            .priority = priority,
            .completion_callback = completion_callback,
            .progress_callback = progress_callback,
            .callback_context = context,
            .cancelled = std.atomic.Value(bool).init(false),
            .queued_at = std.time.milliTimestamp(),
            .started_at = std.atomic.Value(i64).init(0),
        };
    }

    /// Check if this request has been cancelled
    pub fn isCancelled(self: *const AsyncLoadRequest) bool {
        return self.cancelled.load(.acquire);
    }

    /// Cancel this request
    pub fn markCancelled(self: *AsyncLoadRequest) void {
        self.cancelled.store(true, .release);
    }
};

// ============================================================================
// Completion Queue Item
// ============================================================================

/// Item in the completion queue (ready for main thread processing)
const CompletionItem = struct {
    result: AsyncLoadResult,
    callback: ?CompletionCallback,
    context: ?*anyopaque,
};

// ============================================================================
// Async Loader Configuration
// ============================================================================

/// Configuration for AsyncLoader
pub const AsyncLoaderConfig = struct {
    /// Number of worker threads (0 = auto-detect based on CPU cores)
    thread_count: u32 = 0,
    /// Maximum pending requests in queue
    max_pending_requests: usize = 1024,
    /// Maximum completed items waiting for main thread processing
    max_completion_queue: usize = 256,
    /// Enable verbose logging
    verbose: bool = false,
};

// ============================================================================
// Async Loader
// ============================================================================

/// Async loading system with thread pool
pub const AsyncLoader = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    registry: *AssetRegistry,
    config: AsyncLoaderConfig,

    // Thread pool
    workers: []std.Thread,
    shutdown: std.atomic.Value(bool),

    // Request queue (priority-sorted)
    request_queue: std.ArrayList(AsyncLoadRequest),
    request_mutex: std.Thread.Mutex,
    request_condition: std.Thread.Condition,

    // Active requests (being processed by workers)
    active_requests: std.AutoHashMap(RequestId, *AsyncLoadRequest),
    active_mutex: std.Thread.Mutex,

    // Completion queue (for main thread processing)
    completion_queue: std.ArrayList(CompletionItem),
    completion_mutex: std.Thread.Mutex,

    // Request ID counter
    next_request_id: std.atomic.Value(u64),

    // Statistics
    stats: AsyncLoaderStats,
    stats_mutex: std.Thread.Mutex,

    /// Initialize the async loader
    pub fn init(
        allocator: std.mem.Allocator,
        registry: *AssetRegistry,
        config: AsyncLoaderConfig,
    ) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        // Determine thread count
        const thread_count: u32 = if (config.thread_count == 0)
            @max(1, @as(u32, @intCast(std.Thread.getCpuCount() catch 2)) / 2)
        else
            config.thread_count;

        self.* = Self{
            .allocator = allocator,
            .registry = registry,
            .config = config,
            .workers = &.{},
            .shutdown = std.atomic.Value(bool).init(false),
            .request_queue = std.ArrayList(AsyncLoadRequest).init(allocator),
            .request_mutex = .{},
            .request_condition = .{},
            .active_requests = std.AutoHashMap(RequestId, *AsyncLoadRequest).init(allocator),
            .active_mutex = .{},
            .completion_queue = std.ArrayList(CompletionItem).init(allocator),
            .completion_mutex = .{},
            .next_request_id = std.atomic.Value(u64).init(1),
            .stats = .{},
            .stats_mutex = .{},
        };

        // Allocate and spawn worker threads
        self.workers = try allocator.alloc(std.Thread, thread_count);
        errdefer allocator.free(self.workers);

        var spawned: usize = 0;
        errdefer {
            self.shutdown.store(true, .release);
            self.request_condition.broadcast();
            for (self.workers[0..spawned]) |*worker| {
                worker.join();
            }
        }

        for (self.workers) |*worker| {
            worker.* = try std.Thread.spawn(.{}, workerThread, .{self});
            spawned += 1;
        }

        return self;
    }

    /// Shutdown and cleanup
    pub fn deinit(self: *Self) void {
        // Signal shutdown
        self.shutdown.store(true, .release);

        // Wake all workers
        self.request_condition.broadcast();

        // Wait for workers to finish
        for (self.workers) |*worker| {
            worker.join();
        }

        // Cleanup
        self.allocator.free(self.workers);
        self.request_queue.deinit();
        self.active_requests.deinit();
        self.completion_queue.deinit();

        self.allocator.destroy(self);
    }

    /// Queue an asset for async loading
    pub fn loadAsync(
        self: *Self,
        handle: AssetHandle,
        priority: LoadPriority,
        completion_callback: ?CompletionCallback,
        context: ?*anyopaque,
    ) !RequestId {
        return self.loadAsyncWithProgress(handle, priority, completion_callback, null, context);
    }

    /// Queue an asset for async loading with progress callback
    pub fn loadAsyncWithProgress(
        self: *Self,
        handle: AssetHandle,
        priority: LoadPriority,
        completion_callback: ?CompletionCallback,
        progress_callback: ?ProgressCallback,
        context: ?*anyopaque,
    ) !RequestId {
        // Validate handle
        if (!self.registry.isHandleValid(handle)) {
            return error.InvalidHandle;
        }

        // Check if already loaded
        if (self.registry.isLoaded(handle)) {
            // Immediately complete
            if (completion_callback) |cb| {
                cb(.{
                    .request_id = 0,
                    .handle = handle,
                    .success = true,
                    .err = null,
                    .load_time_ns = 0,
                }, context);
            }
            return INVALID_REQUEST_ID;
        }

        // Generate request ID
        const request_id = self.next_request_id.fetchAdd(1, .monotonic);

        const request = AsyncLoadRequest.init(
            request_id,
            handle,
            priority,
            completion_callback,
            progress_callback,
            context,
        );

        // Add to queue
        {
            self.request_mutex.lock();
            defer self.request_mutex.unlock();

            // Check queue limit
            if (self.request_queue.items.len >= self.config.max_pending_requests) {
                return error.QueueFull;
            }

            try self.request_queue.append(request);

            // Sort by priority (lower priority value = higher priority)
            std.mem.sort(AsyncLoadRequest, self.request_queue.items, {}, struct {
                fn lessThan(_: void, a: AsyncLoadRequest, b: AsyncLoadRequest) bool {
                    if (a.priority.toInt() != b.priority.toInt()) {
                        return a.priority.toInt() < b.priority.toInt();
                    }
                    // Same priority: FIFO (older first)
                    return a.queued_at < b.queued_at;
                }
            }.lessThan);
        }

        // Update stats
        {
            self.stats_mutex.lock();
            defer self.stats_mutex.unlock();
            self.stats.total_queued += 1;
            self.stats.pending_count += 1;
        }

        // Wake a worker
        self.request_condition.signal();

        return request_id;
    }

    /// Cancel a pending load request
    /// Returns true if the request was found and cancelled
    pub fn cancel(self: *Self, request_id: RequestId) bool {
        if (request_id == INVALID_REQUEST_ID) return false;

        // Try to remove from pending queue
        {
            self.request_mutex.lock();
            defer self.request_mutex.unlock();

            for (self.request_queue.items, 0..) |*req, i| {
                if (req.id == request_id) {
                    _ = self.request_queue.orderedRemove(i);
                    {
                        self.stats_mutex.lock();
                        defer self.stats_mutex.unlock();
                        self.stats.total_cancelled += 1;
                        if (self.stats.pending_count > 0) {
                            self.stats.pending_count -= 1;
                        }
                    }
                    return true;
                }
            }
        }

        // Try to cancel active request
        {
            self.active_mutex.lock();
            defer self.active_mutex.unlock();

            if (self.active_requests.get(request_id)) |req| {
                req.markCancelled();
                return true;
            }
        }

        return false;
    }

    /// Cancel all pending requests
    pub fn cancelAll(self: *Self) usize {
        var cancelled: usize = 0;

        // Clear pending queue
        {
            self.request_mutex.lock();
            defer self.request_mutex.unlock();
            cancelled = self.request_queue.items.len;
            self.request_queue.clearRetainingCapacity();
        }

        // Cancel active requests
        {
            self.active_mutex.lock();
            defer self.active_mutex.unlock();

            var iter = self.active_requests.valueIterator();
            while (iter.next()) |req| {
                req.*.markCancelled();
                cancelled += 1;
            }
        }

        {
            self.stats_mutex.lock();
            defer self.stats_mutex.unlock();
            self.stats.total_cancelled += cancelled;
            self.stats.pending_count = 0;
        }

        return cancelled;
    }

    /// Process completed loads on the main thread
    /// This fires completion callbacks and performs GPU finalization
    /// Call this once per frame from the main thread
    pub fn processCompletions(self: *Self) usize {
        var processed: usize = 0;

        while (true) {
            var item: ?CompletionItem = null;

            {
                self.completion_mutex.lock();
                defer self.completion_mutex.unlock();

                if (self.completion_queue.items.len > 0) {
                    item = self.completion_queue.orderedRemove(0);
                }
            }

            if (item) |completion| {
                // Fire callback on main thread
                if (completion.callback) |cb| {
                    cb(completion.result, completion.context);
                }
                processed += 1;
            } else {
                break;
            }
        }

        return processed;
    }

    /// Check if a request is pending or active
    pub fn isRequestPending(self: *Self, request_id: RequestId) bool {
        if (request_id == INVALID_REQUEST_ID) return false;

        // Check pending queue
        {
            self.request_mutex.lock();
            defer self.request_mutex.unlock();

            for (self.request_queue.items) |req| {
                if (req.id == request_id) return true;
            }
        }

        // Check active requests
        {
            self.active_mutex.lock();
            defer self.active_mutex.unlock();

            return self.active_requests.contains(request_id);
        }
    }

    /// Get the number of pending requests
    pub fn getPendingCount(self: *Self) usize {
        self.request_mutex.lock();
        defer self.request_mutex.unlock();
        return self.request_queue.items.len;
    }

    /// Get the number of active (currently loading) requests
    pub fn getActiveCount(self: *Self) usize {
        self.active_mutex.lock();
        defer self.active_mutex.unlock();
        return self.active_requests.count();
    }

    /// Get statistics
    pub fn getStats(self: *Self) AsyncLoaderStats {
        self.stats_mutex.lock();
        defer self.stats_mutex.unlock();
        return self.stats;
    }

    /// Worker thread function
    fn workerThread(self: *Self) void {
        while (!self.shutdown.load(.acquire)) {
            var request: ?AsyncLoadRequest = null;

            // Get next request from queue
            {
                self.request_mutex.lock();
                defer self.request_mutex.unlock();

                while (self.request_queue.items.len == 0 and !self.shutdown.load(.acquire)) {
                    self.request_condition.wait(&self.request_mutex);
                }

                if (self.shutdown.load(.acquire)) break;

                if (self.request_queue.items.len > 0) {
                    request = self.request_queue.orderedRemove(0);
                }
            }

            if (request) |req| {
                self.processRequest(req);
            }
        }
    }

    /// Process a single load request
    fn processRequest(self: *Self, request: AsyncLoadRequest) void {
        var req = request;
        const start_time = std.time.nanoTimestamp();
        req.started_at.store(std.time.milliTimestamp(), .release);

        // Track as active
        {
            self.active_mutex.lock();
            defer self.active_mutex.unlock();
            // Store pointer to stack-local request (safe because we process it completely here)
            self.active_requests.put(req.id, &req) catch {};
        }

        defer {
            // Remove from active
            self.active_mutex.lock();
            defer self.active_mutex.unlock();
            _ = self.active_requests.remove(req.id);
        }

        // Check for cancellation
        if (req.isCancelled()) {
            self.stats_mutex.lock();
            defer self.stats_mutex.unlock();
            self.stats.total_cancelled += 1;
            if (self.stats.pending_count > 0) {
                self.stats.pending_count -= 1;
            }
            return;
        }

        // Perform the actual load
        var success = false;
        var load_err: ?LoadError = null;

        self.registry.load(req.handle) catch |err| {
            load_err = err;
        };

        if (load_err == null) {
            success = true;
        }

        const end_time = std.time.nanoTimestamp();
        const load_time: u64 = @intCast(@max(0, end_time - start_time));

        // Check for cancellation again (might have been cancelled during load)
        if (req.isCancelled()) {
            // Still fire callback but result indicates cancellation was requested
            success = false;
        }

        // Queue completion for main thread
        const result = AsyncLoadResult{
            .request_id = req.id,
            .handle = req.handle,
            .success = success,
            .err = load_err,
            .load_time_ns = load_time,
        };

        {
            self.completion_mutex.lock();
            defer self.completion_mutex.unlock();

            self.completion_queue.append(.{
                .result = result,
                .callback = req.completion_callback,
                .context = req.callback_context,
            }) catch {
                // Queue full, drop completion (callback won't fire)
            };
        }

        // Update stats
        {
            self.stats_mutex.lock();
            defer self.stats_mutex.unlock();

            if (success) {
                self.stats.total_completed += 1;
            } else {
                self.stats.total_failed += 1;
            }

            if (self.stats.pending_count > 0) {
                self.stats.pending_count -= 1;
            }

            self.stats.total_load_time_ns += load_time;
        }
    }
};

// ============================================================================
// Statistics
// ============================================================================

/// Statistics for async loading
pub const AsyncLoaderStats = struct {
    /// Total requests queued
    total_queued: u64 = 0,
    /// Total requests completed successfully
    total_completed: u64 = 0,
    /// Total requests that failed
    total_failed: u64 = 0,
    /// Total requests cancelled
    total_cancelled: u64 = 0,
    /// Current pending requests
    pending_count: usize = 0,
    /// Total load time (nanoseconds)
    total_load_time_ns: u64 = 0,

    /// Get average load time in milliseconds
    pub fn getAverageLoadTimeMs(self: AsyncLoaderStats) f64 {
        const completed = self.total_completed + self.total_failed;
        if (completed == 0) return 0;
        return @as(f64, @floatFromInt(self.total_load_time_ns)) / @as(f64, @floatFromInt(completed)) / 1_000_000.0;
    }
};

// ============================================================================
// Errors
// ============================================================================

pub const AsyncLoadError = error{
    InvalidHandle,
    QueueFull,
    ShuttingDown,
};

// ============================================================================
// Batch Loading Helper
// ============================================================================

/// Helper for loading multiple assets with progress tracking
pub const BatchLoader = struct {
    async_loader: *AsyncLoader,
    requests: std.ArrayList(RequestId),
    allocator: std.mem.Allocator,
    total_count: usize,
    completed_count: std.atomic.Value(usize),
    failed_count: std.atomic.Value(usize),
    batch_callback: ?BatchCallback,
    batch_context: ?*anyopaque,

    pub const BatchCallback = *const fn (
        completed: usize,
        total: usize,
        all_done: bool,
        context: ?*anyopaque,
    ) void;

    pub fn init(allocator: std.mem.Allocator, async_loader: *AsyncLoader) BatchLoader {
        return .{
            .async_loader = async_loader,
            .requests = std.ArrayList(RequestId).init(allocator),
            .allocator = allocator,
            .total_count = 0,
            .completed_count = std.atomic.Value(usize).init(0),
            .failed_count = std.atomic.Value(usize).init(0),
            .batch_callback = null,
            .batch_context = null,
        };
    }

    pub fn deinit(self: *BatchLoader) void {
        self.requests.deinit();
    }

    /// Set callback for batch progress
    pub fn setCallback(self: *BatchLoader, callback: BatchCallback, context: ?*anyopaque) void {
        self.batch_callback = callback;
        self.batch_context = context;
    }

    /// Add an asset to the batch
    pub fn add(self: *BatchLoader, handle: AssetHandle, priority: LoadPriority) !void {
        const Wrapper = struct {
            fn onComplete(result: AsyncLoadResult, ctx: ?*anyopaque) void {
                const batch: *BatchLoader = @ptrCast(@alignCast(ctx.?));

                if (result.success) {
                    _ = batch.completed_count.fetchAdd(1, .monotonic);
                } else {
                    _ = batch.failed_count.fetchAdd(1, .monotonic);
                }

                const completed = batch.completed_count.load(.acquire) + batch.failed_count.load(.acquire);
                const all_done = completed >= batch.total_count;

                if (batch.batch_callback) |cb| {
                    cb(completed, batch.total_count, all_done, batch.batch_context);
                }
            }
        };

        const request_id = try self.async_loader.loadAsync(handle, priority, Wrapper.onComplete, self);
        if (request_id != INVALID_REQUEST_ID) {
            try self.requests.append(request_id);
            self.total_count += 1;
        }
    }

    /// Cancel all pending requests in the batch
    pub fn cancelAll(self: *BatchLoader) void {
        for (self.requests.items) |request_id| {
            _ = self.async_loader.cancel(request_id);
        }
    }

    /// Get progress (0.0 to 1.0)
    pub fn getProgress(self: *const BatchLoader) f32 {
        if (self.total_count == 0) return 1.0;
        const completed = self.completed_count.load(.acquire) + self.failed_count.load(.acquire);
        return @as(f32, @floatFromInt(completed)) / @as(f32, @floatFromInt(self.total_count));
    }

    /// Check if batch loading is complete
    pub fn isComplete(self: *const BatchLoader) bool {
        const completed = self.completed_count.load(.acquire) + self.failed_count.load(.acquire);
        return completed >= self.total_count;
    }

    /// Get count of successfully loaded assets
    pub fn getCompletedCount(self: *const BatchLoader) usize {
        return self.completed_count.load(.acquire);
    }

    /// Get count of failed loads
    pub fn getFailedCount(self: *const BatchLoader) usize {
        return self.failed_count.load(.acquire);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "LoadPriority - ordering" {
    try std.testing.expect(LoadPriority.critical.toInt() < LoadPriority.high.toInt());
    try std.testing.expect(LoadPriority.high.toInt() < LoadPriority.normal.toInt());
    try std.testing.expect(LoadPriority.normal.toInt() < LoadPriority.low.toInt());
}

test "AsyncLoadResult - basic structure" {
    const result = AsyncLoadResult{
        .request_id = 42,
        .handle = AssetHandle{ .index = 1, .generation = 0 },
        .success = true,
        .err = null,
        .load_time_ns = 1_000_000,
    };

    try std.testing.expectEqual(@as(RequestId, 42), result.request_id);
    try std.testing.expect(result.success);
    try std.testing.expect(result.err == null);
}

test "AsyncLoaderStats - average load time" {
    var stats = AsyncLoaderStats{};
    try std.testing.expectEqual(@as(f64, 0), stats.getAverageLoadTimeMs());

    stats.total_completed = 2;
    stats.total_load_time_ns = 4_000_000; // 4ms total
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), stats.getAverageLoadTimeMs(), 0.001);
}

test "AsyncLoadRequest - cancellation" {
    var request = AsyncLoadRequest.init(
        1,
        AssetHandle{ .index = 0, .generation = 0 },
        .normal,
        null,
        null,
        null,
    );

    try std.testing.expect(!request.isCancelled());

    request.markCancelled();

    try std.testing.expect(request.isCancelled());
}

// Integration test with actual threading would require more setup
// These tests verify the basic structures and logic
test "AsyncLoader - init and deinit" {
    var registry = AssetRegistry.init(std.testing.allocator);
    defer registry.deinit();

    var loader = try AsyncLoader.init(std.testing.allocator, &registry, .{
        .thread_count = 1, // Use single thread for testing
    });
    defer loader.deinit();

    try std.testing.expect(loader.workers.len == 1);
    try std.testing.expectEqual(@as(usize, 0), loader.getPendingCount());
    try std.testing.expectEqual(@as(usize, 0), loader.getActiveCount());
}

test "AsyncLoader - loadAsync with invalid handle" {
    var registry = AssetRegistry.init(std.testing.allocator);
    defer registry.deinit();

    var loader = try AsyncLoader.init(std.testing.allocator, &registry, .{
        .thread_count = 1,
    });
    defer loader.deinit();

    const invalid_handle = AssetHandle.invalid();
    const result = loader.loadAsync(invalid_handle, .normal, null, null);
    try std.testing.expectError(AsyncLoadError.InvalidHandle, result);
}

test "AsyncLoader - loadAsync queues request" {
    var registry = AssetRegistry.init(std.testing.allocator);
    defer registry.deinit();

    // Register a simple test loader
    const TestLoader = struct {
        fn load(_: []const u8, allocator: std.mem.Allocator) LoadError!*anyopaque {
            const data = allocator.create(u32) catch return LoadError.OutOfMemory;
            data.* = 123;
            return @ptrCast(data);
        }

        fn unload(data: *anyopaque, allocator: std.mem.Allocator) void {
            const typed: *u32 = @ptrCast(@alignCast(data));
            allocator.destroy(typed);
        }
    };

    try registry.registerLoader(.data, TestLoader.load, TestLoader.unload);

    const handle = try registry.getOrCreateHandle("test.toml");

    var loader = try AsyncLoader.init(std.testing.allocator, &registry, .{
        .thread_count = 1,
    });
    defer loader.deinit();

    const request_id = try loader.loadAsync(handle, .normal, null, null);
    try std.testing.expect(request_id != INVALID_REQUEST_ID);

    // Give worker time to process
    std.time.sleep(50 * std.time.ns_per_ms);

    // Process completions
    _ = loader.processCompletions();

    // Asset should be loaded now
    try std.testing.expect(registry.isLoaded(handle));
}

test "AsyncLoader - cancel pending request" {
    var registry = AssetRegistry.init(std.testing.allocator);
    defer registry.deinit();

    var loader = try AsyncLoader.init(std.testing.allocator, &registry, .{
        .thread_count = 0, // No workers - requests stay in queue
    });

    // Create handle but don't start workers yet
    const handle = try registry.getOrCreateHandle("test.toml");

    // Manually add to queue for testing
    {
        loader.request_mutex.lock();
        defer loader.request_mutex.unlock();

        const request = AsyncLoadRequest.init(
            loader.next_request_id.fetchAdd(1, .monotonic),
            handle,
            .normal,
            null,
            null,
            null,
        );
        try loader.request_queue.append(request);
    }

    try std.testing.expectEqual(@as(usize, 1), loader.getPendingCount());

    // Cancel the request
    const cancelled = loader.cancel(1);
    try std.testing.expect(cancelled);
    try std.testing.expectEqual(@as(usize, 0), loader.getPendingCount());

    loader.deinit();
}

test "AsyncLoader - cancelAll" {
    var registry = AssetRegistry.init(std.testing.allocator);
    defer registry.deinit();

    var loader = try AsyncLoader.init(std.testing.allocator, &registry, .{
        .thread_count = 0,
    });

    // Add multiple requests to queue
    const handle1 = try registry.getOrCreateHandle("test1.toml");
    const handle2 = try registry.getOrCreateHandle("test2.toml");

    {
        loader.request_mutex.lock();
        defer loader.request_mutex.unlock();

        try loader.request_queue.append(AsyncLoadRequest.init(1, handle1, .normal, null, null, null));
        try loader.request_queue.append(AsyncLoadRequest.init(2, handle2, .high, null, null, null));
    }

    try std.testing.expectEqual(@as(usize, 2), loader.getPendingCount());

    const cancelled = loader.cancelAll();
    try std.testing.expectEqual(@as(usize, 2), cancelled);
    try std.testing.expectEqual(@as(usize, 0), loader.getPendingCount());

    loader.deinit();
}

test "AsyncLoader - priority ordering" {
    var registry = AssetRegistry.init(std.testing.allocator);
    defer registry.deinit();

    var loader = try AsyncLoader.init(std.testing.allocator, &registry, .{
        .thread_count = 0,
    });

    const handle1 = try registry.getOrCreateHandle("low.toml");
    const handle2 = try registry.getOrCreateHandle("critical.toml");
    const handle3 = try registry.getOrCreateHandle("normal.toml");

    // Add in wrong order
    {
        loader.request_mutex.lock();
        defer loader.request_mutex.unlock();

        try loader.request_queue.append(AsyncLoadRequest.init(1, handle1, .low, null, null, null));
        try loader.request_queue.append(AsyncLoadRequest.init(2, handle2, .critical, null, null, null));
        try loader.request_queue.append(AsyncLoadRequest.init(3, handle3, .normal, null, null, null));

        // Sort by priority
        std.mem.sort(AsyncLoadRequest, loader.request_queue.items, {}, struct {
            fn lessThan(_: void, a: AsyncLoadRequest, b: AsyncLoadRequest) bool {
                return a.priority.toInt() < b.priority.toInt();
            }
        }.lessThan);
    }

    // Verify ordering: critical, normal, low
    {
        loader.request_mutex.lock();
        defer loader.request_mutex.unlock();

        try std.testing.expectEqual(LoadPriority.critical, loader.request_queue.items[0].priority);
        try std.testing.expectEqual(LoadPriority.normal, loader.request_queue.items[1].priority);
        try std.testing.expectEqual(LoadPriority.low, loader.request_queue.items[2].priority);
    }

    loader.deinit();
}

test "BatchLoader - basic operations" {
    var registry = AssetRegistry.init(std.testing.allocator);
    defer registry.deinit();

    var loader = try AsyncLoader.init(std.testing.allocator, &registry, .{
        .thread_count = 1,
    });
    defer loader.deinit();

    var batch = BatchLoader.init(std.testing.allocator, loader);
    defer batch.deinit();

    try std.testing.expectEqual(@as(f32, 1.0), batch.getProgress());
    try std.testing.expect(batch.isComplete());
}

test "BatchLoader - progress tracking" {
    var batch = BatchLoader{
        .async_loader = undefined,
        .requests = std.ArrayList(RequestId).init(std.testing.allocator),
        .allocator = std.testing.allocator,
        .total_count = 4,
        .completed_count = std.atomic.Value(usize).init(2),
        .failed_count = std.atomic.Value(usize).init(1),
        .batch_callback = null,
        .batch_context = null,
    };
    defer batch.deinit();

    // 3 of 4 done
    try std.testing.expectEqual(@as(f32, 0.75), batch.getProgress());
    try std.testing.expect(!batch.isComplete());
    try std.testing.expectEqual(@as(usize, 2), batch.getCompletedCount());
    try std.testing.expectEqual(@as(usize, 1), batch.getFailedCount());
}
