// asset.zig
// Asset System for AgentiteZ
// Unified resource management with reference counting
//
// Features:
// - Asset registry with reference counting
// - Type-safe asset handles with generation counters
// - Asset loading abstraction layer
// - Asset unloading with dependency tracking
// - Support for: textures, sounds, fonts, scenes, prefabs

const std = @import("std");

// ============================================================================
// Asset Types
// ============================================================================

/// Supported asset types
pub const AssetType = enum(u8) {
    texture,
    sound,
    music,
    font,
    prefab,
    scene,
    tilemap,
    shader,
    data, // Generic data files (JSON, TOML, etc.)
    other,

    pub fn fromExtension(ext: []const u8) AssetType {
        const map = std.StaticStringMap(AssetType).initComptime(.{
            // Textures
            .{ ".png", .texture },
            .{ ".jpg", .texture },
            .{ ".jpeg", .texture },
            .{ ".bmp", .texture },
            .{ ".tga", .texture },
            // Audio
            .{ ".wav", .sound },
            .{ ".ogg", .music },
            .{ ".mp3", .music },
            // Fonts
            .{ ".ttf", .font },
            .{ ".otf", .font },
            // Data
            .{ ".toml", .data },
            .{ ".json", .data },
            // Engine-specific
            .{ ".prefab", .prefab },
            .{ ".scene", .scene },
            .{ ".tilemap", .tilemap },
        });
        return map.get(ext) orelse .other;
    }

    pub fn toString(self: AssetType) []const u8 {
        return switch (self) {
            .texture => "texture",
            .sound => "sound",
            .music => "music",
            .font => "font",
            .prefab => "prefab",
            .scene => "scene",
            .tilemap => "tilemap",
            .shader => "shader",
            .data => "data",
            .other => "other",
        };
    }
};

/// Asset loading state
pub const AssetState = enum(u8) {
    /// Asset is not loaded
    unloaded,
    /// Asset is currently being loaded
    loading,
    /// Asset is loaded and ready to use
    loaded,
    /// Asset failed to load
    failed,
    /// Asset is being unloaded
    unloading,
};

// ============================================================================
// Asset Handle
// ============================================================================

/// Generation counter type (prevents dangling handle access)
pub const Generation = u16;

/// Index type for asset slots
pub const AssetIndex = u16;

/// Invalid handle constant
pub const INVALID_HANDLE = AssetHandle{ .index = std.math.maxInt(AssetIndex), .generation = 0 };

/// Type-safe handle to an asset
/// Uses generation counters to detect stale references
pub const AssetHandle = struct {
    /// Index into the asset registry
    index: AssetIndex,
    /// Generation counter to detect stale handles
    generation: Generation,

    /// Check if this is a valid (non-null) handle
    pub fn isValid(self: AssetHandle) bool {
        return self.index != std.math.maxInt(AssetIndex);
    }

    /// Create an invalid/null handle
    pub fn invalid() AssetHandle {
        return INVALID_HANDLE;
    }

    pub fn format(
        self: AssetHandle,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (self.isValid()) {
            try writer.print("Handle({d}:{d})", .{ self.index, self.generation });
        } else {
            try writer.writeAll("Handle(invalid)");
        }
    }
};

// ============================================================================
// Asset Metadata
// ============================================================================

/// Metadata stored for each asset
pub const AssetMetadata = struct {
    /// File path (relative to asset root)
    path: []const u8,
    /// Asset type
    asset_type: AssetType,
    /// Current loading state
    state: AssetState,
    /// Reference count (number of active handles)
    ref_count: u32,
    /// Generation counter for this slot
    generation: Generation,
    /// Dependencies (other assets this asset requires)
    dependencies: std.ArrayList(AssetHandle),
    /// Dependents (assets that depend on this one)
    dependents: std.ArrayList(AssetHandle),
    /// Size in bytes (0 if unknown)
    size_bytes: usize,
    /// Error message if loading failed
    error_message: ?[]const u8,
    /// Allocator for this metadata
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, path: []const u8, asset_type: AssetType, generation: Generation) !AssetMetadata {
        return .{
            .path = try allocator.dupe(u8, path),
            .asset_type = asset_type,
            .state = .unloaded,
            .ref_count = 0,
            .generation = generation,
            .dependencies = std.ArrayList(AssetHandle).init(allocator),
            .dependents = std.ArrayList(AssetHandle).init(allocator),
            .size_bytes = 0,
            .error_message = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *AssetMetadata) void {
        self.allocator.free(self.path);
        if (self.error_message) |msg| {
            self.allocator.free(msg);
        }
        self.dependencies.deinit();
        self.dependents.deinit();
    }

    /// Add a dependency
    pub fn addDependency(self: *AssetMetadata, dep: AssetHandle) !void {
        // Check for duplicates
        for (self.dependencies.items) |existing| {
            if (existing.index == dep.index and existing.generation == dep.generation) {
                return;
            }
        }
        try self.dependencies.append(dep);
    }

    /// Add a dependent
    pub fn addDependent(self: *AssetMetadata, dep: AssetHandle) !void {
        // Check for duplicates
        for (self.dependents.items) |existing| {
            if (existing.index == dep.index and existing.generation == dep.generation) {
                return;
            }
        }
        try self.dependents.append(dep);
    }

    /// Remove a dependent
    pub fn removeDependent(self: *AssetMetadata, dep: AssetHandle) void {
        for (self.dependents.items, 0..) |existing, i| {
            if (existing.index == dep.index and existing.generation == dep.generation) {
                _ = self.dependents.swapRemove(i);
                return;
            }
        }
    }

    /// Set error message
    pub fn setError(self: *AssetMetadata, message: []const u8) !void {
        if (self.error_message) |old| {
            self.allocator.free(old);
        }
        self.error_message = try self.allocator.dupe(u8, message);
        self.state = .failed;
    }
};

// ============================================================================
// Asset Loader Interface
// ============================================================================

/// Error type for asset loading
pub const LoadError = error{
    FileNotFound,
    InvalidFormat,
    OutOfMemory,
    IoError,
    UnsupportedFormat,
    DependencyFailed,
    LoaderNotRegistered,
    AlreadyLoaded,
};

/// Loader function type
/// Takes path and allocator, returns opaque pointer to loaded data
pub const LoaderFn = *const fn (path: []const u8, allocator: std.mem.Allocator) LoadError!*anyopaque;

/// Unloader function type
/// Takes the opaque pointer and frees all associated memory
pub const UnloaderFn = *const fn (data: *anyopaque, allocator: std.mem.Allocator) void;

/// Loader registration info
pub const LoaderInfo = struct {
    loader: LoaderFn,
    unloader: UnloaderFn,
    asset_type: AssetType,
};

// ============================================================================
// Asset Slot
// ============================================================================

/// Internal storage slot for an asset
const AssetSlot = struct {
    /// Metadata for this asset
    metadata: ?AssetMetadata,
    /// Loaded data (opaque pointer)
    data: ?*anyopaque,
    /// Whether this slot is in use
    in_use: bool,

    pub fn init() AssetSlot {
        return .{
            .metadata = null,
            .data = null,
            .in_use = false,
        };
    }
};

// ============================================================================
// Asset Registry
// ============================================================================

/// Central registry for all assets
/// Manages loading, unloading, and reference counting
pub const AssetRegistry = struct {
    /// Storage for asset slots
    slots: std.ArrayList(AssetSlot),
    /// Path to handle mapping for quick lookup
    path_to_handle: std.StringHashMap(AssetHandle),
    /// Registered loaders by asset type
    loaders: std.AutoHashMap(AssetType, LoaderInfo),
    /// Free slot indices (for reuse)
    free_slots: std.ArrayList(AssetIndex),
    /// Asset root directory
    asset_root: []const u8,
    /// Allocator
    allocator: std.mem.Allocator,
    /// Statistics
    stats: AssetStats,

    /// Asset statistics
    pub const AssetStats = struct {
        total_loaded: usize = 0,
        total_unloaded: usize = 0,
        total_failed: usize = 0,
        total_bytes: usize = 0,
        active_assets: usize = 0,
    };

    pub fn init(allocator: std.mem.Allocator) AssetRegistry {
        return .{
            .slots = std.ArrayList(AssetSlot).init(allocator),
            .path_to_handle = std.StringHashMap(AssetHandle).init(allocator),
            .loaders = std.AutoHashMap(AssetType, LoaderInfo).init(allocator),
            .free_slots = std.ArrayList(AssetIndex).init(allocator),
            .asset_root = "",
            .allocator = allocator,
            .stats = .{},
        };
    }

    pub fn deinit(self: *AssetRegistry) void {
        // Unload all assets
        for (self.slots.items, 0..) |*slot, i| {
            if (slot.in_use and slot.metadata != null) {
                self.unloadSlot(@intCast(i));
            }
            if (slot.metadata) |*meta| {
                meta.deinit();
            }
        }

        // Free path keys
        var path_iter = self.path_to_handle.keyIterator();
        while (path_iter.next()) |key| {
            self.allocator.free(key.*);
        }

        self.slots.deinit();
        self.path_to_handle.deinit();
        self.loaders.deinit();
        self.free_slots.deinit();

        if (self.asset_root.len > 0) {
            self.allocator.free(self.asset_root);
        }
    }

    /// Set the asset root directory
    pub fn setAssetRoot(self: *AssetRegistry, root: []const u8) !void {
        if (self.asset_root.len > 0) {
            self.allocator.free(self.asset_root);
        }
        self.asset_root = try self.allocator.dupe(u8, root);
    }

    /// Register a loader for an asset type
    pub fn registerLoader(
        self: *AssetRegistry,
        asset_type: AssetType,
        loader: LoaderFn,
        unloader: UnloaderFn,
    ) !void {
        try self.loaders.put(asset_type, .{
            .loader = loader,
            .unloader = unloader,
            .asset_type = asset_type,
        });
    }

    /// Register a typed loader using comptime type information
    pub fn registerTypedLoader(
        self: *AssetRegistry,
        comptime T: type,
        asset_type: AssetType,
        loader: *const fn (path: []const u8, allocator: std.mem.Allocator) LoadError!*T,
    ) !void {
        // Create wrapper functions
        const Wrapper = struct {
            fn load(path: []const u8, allocator: std.mem.Allocator) LoadError!*anyopaque {
                const result = loader(path, allocator) catch |err| return err;
                return @ptrCast(result);
            }

            fn unload(data: *anyopaque, allocator: std.mem.Allocator) void {
                const typed: *T = @ptrCast(@alignCast(data));
                if (@hasDecl(T, "deinit")) {
                    typed.deinit();
                }
                allocator.destroy(typed);
            }
        };

        try self.registerLoader(asset_type, Wrapper.load, Wrapper.unload);
    }

    /// Allocate a new slot or reuse a free one
    fn allocateSlot(self: *AssetRegistry) !AssetIndex {
        if (self.free_slots.items.len > 0) {
            return self.free_slots.pop();
        }

        // Allocate new slot
        const index: AssetIndex = @intCast(self.slots.items.len);
        try self.slots.append(AssetSlot.init());
        return index;
    }

    /// Get or create a handle for an asset path
    pub fn getOrCreateHandle(self: *AssetRegistry, path: []const u8) !AssetHandle {
        // Check if already registered
        if (self.path_to_handle.get(path)) |existing| {
            if (self.isHandleValid(existing)) {
                return existing;
            }
        }

        // Allocate new slot
        const index = try self.allocateSlot();
        const slot = &self.slots.items[index];

        // Determine generation (increment if slot was previously used)
        const generation: Generation = if (slot.metadata) |meta| meta.generation +% 1 else 0;

        // Determine asset type from extension
        const ext = std.fs.path.extension(path);
        const asset_type = AssetType.fromExtension(ext);

        // Initialize metadata
        if (slot.metadata) |*meta| {
            meta.deinit();
        }
        slot.metadata = try AssetMetadata.init(self.allocator, path, asset_type, generation);
        slot.in_use = true;

        const handle = AssetHandle{ .index = index, .generation = generation };

        // Store path mapping
        const path_copy = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(path_copy);

        // Remove old mapping if exists
        if (self.path_to_handle.fetchRemove(path)) |old| {
            self.allocator.free(old.key);
        }

        try self.path_to_handle.put(path_copy, handle);

        return handle;
    }

    /// Check if a handle is valid (slot exists and generation matches)
    pub fn isHandleValid(self: *const AssetRegistry, handle: AssetHandle) bool {
        if (!handle.isValid()) return false;
        if (handle.index >= self.slots.items.len) return false;

        const slot = &self.slots.items[handle.index];
        if (!slot.in_use) return false;
        if (slot.metadata) |meta| {
            return meta.generation == handle.generation;
        }
        return false;
    }

    /// Get metadata for a handle
    pub fn getMetadata(self: *const AssetRegistry, handle: AssetHandle) ?*const AssetMetadata {
        if (!self.isHandleValid(handle)) return null;
        return &self.slots.items[handle.index].metadata.?;
    }

    /// Get mutable metadata for a handle
    fn getMetadataMut(self: *AssetRegistry, handle: AssetHandle) ?*AssetMetadata {
        if (!self.isHandleValid(handle)) return null;
        return &self.slots.items[handle.index].metadata.?;
    }

    /// Get handle by path
    pub fn getHandle(self: *const AssetRegistry, path: []const u8) ?AssetHandle {
        const handle = self.path_to_handle.get(path) orelse return null;
        if (self.isHandleValid(handle)) {
            return handle;
        }
        return null;
    }

    /// Load an asset (increases reference count)
    pub fn load(self: *AssetRegistry, handle: AssetHandle) LoadError!void {
        const meta = self.getMetadataMut(handle) orelse return LoadError.FileNotFound;
        const slot = &self.slots.items[handle.index];

        // Increase reference count
        meta.ref_count += 1;

        // If already loaded, we're done
        if (meta.state == .loaded) {
            return;
        }

        // If already loading, wait (in async version) or error
        if (meta.state == .loading) {
            return LoadError.AlreadyLoaded;
        }

        // Get loader
        const loader_info = self.loaders.get(meta.asset_type) orelse {
            meta.state = .failed;
            meta.setError("No loader registered for asset type") catch {};
            self.stats.total_failed += 1;
            return LoadError.LoaderNotRegistered;
        };

        // Build full path
        var full_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const full_path = if (self.asset_root.len > 0)
            std.fmt.bufPrint(&full_path_buf, "{s}/{s}", .{ self.asset_root, meta.path }) catch meta.path
        else
            meta.path;

        // Mark as loading
        meta.state = .loading;

        // Call loader
        slot.data = loader_info.loader(full_path, self.allocator) catch |err| {
            meta.state = .failed;
            const err_msg = switch (err) {
                LoadError.FileNotFound => "File not found",
                LoadError.InvalidFormat => "Invalid format",
                LoadError.OutOfMemory => "Out of memory",
                LoadError.IoError => "I/O error",
                LoadError.UnsupportedFormat => "Unsupported format",
                LoadError.DependencyFailed => "Dependency failed to load",
                LoadError.LoaderNotRegistered => "No loader registered",
                LoadError.AlreadyLoaded => "Already loaded",
            };
            meta.setError(err_msg) catch {};
            self.stats.total_failed += 1;
            return err;
        };

        // Mark as loaded
        meta.state = .loaded;
        self.stats.total_loaded += 1;
        self.stats.active_assets += 1;
    }

    /// Load an asset by path (convenience function)
    pub fn loadByPath(self: *AssetRegistry, path: []const u8) LoadError!AssetHandle {
        const handle = self.getOrCreateHandle(path) catch return LoadError.OutOfMemory;
        try self.load(handle);
        return handle;
    }

    /// Release a reference to an asset (decreases reference count)
    /// Asset is unloaded when reference count reaches zero
    pub fn release(self: *AssetRegistry, handle: AssetHandle) void {
        const meta = self.getMetadataMut(handle) orelse return;

        if (meta.ref_count == 0) return;
        meta.ref_count -= 1;

        // Unload if no more references and no dependents
        if (meta.ref_count == 0 and meta.dependents.items.len == 0) {
            self.unloadSlot(handle.index);
        }
    }

    /// Add reference to an asset (increases reference count without loading)
    pub fn addRef(self: *AssetRegistry, handle: AssetHandle) void {
        if (self.getMetadataMut(handle)) |meta| {
            meta.ref_count += 1;
        }
    }

    /// Unload a slot's data
    fn unloadSlot(self: *AssetRegistry, index: AssetIndex) void {
        const slot = &self.slots.items[index];
        const meta = &slot.metadata.?;

        if (slot.data) |data| {
            if (self.loaders.get(meta.asset_type)) |loader_info| {
                loader_info.unloader(data, self.allocator);
            }
            slot.data = null;
        }

        // Release dependencies
        for (meta.dependencies.items) |dep_handle| {
            if (self.getMetadataMut(dep_handle)) |dep_meta| {
                dep_meta.removeDependent(.{ .index = index, .generation = meta.generation });
            }
            self.release(dep_handle);
        }
        meta.dependencies.clearRetainingCapacity();

        meta.state = .unloaded;
        if (self.stats.active_assets > 0) {
            self.stats.active_assets -= 1;
        }
        self.stats.total_unloaded += 1;
    }

    /// Force unload an asset regardless of reference count
    pub fn forceUnload(self: *AssetRegistry, handle: AssetHandle) void {
        if (!self.isHandleValid(handle)) return;

        const meta = self.getMetadataMut(handle).?;

        // Notify dependents (they should handle the loss)
        for (meta.dependents.items) |dep| {
            if (self.getMetadataMut(dep)) |dep_meta| {
                dep_meta.state = .failed;
                dep_meta.setError("Dependency was force unloaded") catch {};
            }
        }

        meta.ref_count = 0;
        self.unloadSlot(handle.index);
    }

    /// Get the loaded data for an asset (type-safe version)
    pub fn getData(self: *const AssetRegistry, comptime T: type, handle: AssetHandle) ?*T {
        if (!self.isHandleValid(handle)) return null;
        const slot = &self.slots.items[handle.index];
        if (slot.data) |data| {
            return @ptrCast(@alignCast(data));
        }
        return null;
    }

    /// Get raw data pointer
    pub fn getRawData(self: *const AssetRegistry, handle: AssetHandle) ?*anyopaque {
        if (!self.isHandleValid(handle)) return null;
        return self.slots.items[handle.index].data;
    }

    /// Check if an asset is loaded
    pub fn isLoaded(self: *const AssetRegistry, handle: AssetHandle) bool {
        if (self.getMetadata(handle)) |meta| {
            return meta.state == .loaded;
        }
        return false;
    }

    /// Get the state of an asset
    pub fn getState(self: *const AssetRegistry, handle: AssetHandle) ?AssetState {
        if (self.getMetadata(handle)) |meta| {
            return meta.state;
        }
        return null;
    }

    /// Add a dependency relationship between assets
    pub fn addDependency(self: *AssetRegistry, asset: AssetHandle, dependency: AssetHandle) !void {
        const asset_meta = self.getMetadataMut(asset) orelse return;
        const dep_meta = self.getMetadataMut(dependency) orelse return;

        try asset_meta.addDependency(dependency);
        try dep_meta.addDependent(asset);

        // Increase reference count on dependency
        dep_meta.ref_count += 1;
    }

    /// Get total memory usage estimate
    pub fn getTotalMemoryUsage(self: *const AssetRegistry) usize {
        var total: usize = 0;
        for (self.slots.items) |slot| {
            if (slot.metadata) |meta| {
                total += meta.size_bytes;
            }
        }
        return total;
    }

    /// Get number of active assets
    pub fn getActiveCount(self: *const AssetRegistry) usize {
        return self.stats.active_assets;
    }

    /// Get statistics
    pub fn getStats(self: *const AssetRegistry) AssetStats {
        return self.stats;
    }

    /// Iterate over all loaded assets
    pub fn iterateLoaded(self: *const AssetRegistry) LoadedIterator {
        return LoadedIterator{ .registry = self, .index = 0 };
    }

    pub const LoadedIterator = struct {
        registry: *const AssetRegistry,
        index: usize,

        pub fn next(self: *LoadedIterator) ?AssetHandle {
            while (self.index < self.registry.slots.items.len) {
                const slot = &self.registry.slots.items[self.index];
                self.index += 1;

                if (slot.in_use) {
                    if (slot.metadata) |meta| {
                        if (meta.state == .loaded) {
                            return .{
                                .index = @intCast(self.index - 1),
                                .generation = meta.generation,
                            };
                        }
                    }
                }
            }
            return null;
        }
    };
};

// ============================================================================
// Typed Asset Handle
// ============================================================================

/// Type-safe wrapper around AssetHandle for compile-time type checking
pub fn TypedHandle(comptime T: type) type {
    return struct {
        handle: AssetHandle,

        const Self = @This();

        pub fn init(handle: AssetHandle) Self {
            return .{ .handle = handle };
        }

        pub fn invalid() Self {
            return .{ .handle = AssetHandle.invalid() };
        }

        pub fn isValid(self: Self) bool {
            return self.handle.isValid();
        }

        /// Get the typed data from the registry
        pub fn get(self: Self, registry: *const AssetRegistry) ?*T {
            return registry.getData(T, self.handle);
        }

        /// Release this handle
        pub fn release(self: Self, registry: *AssetRegistry) void {
            registry.release(self.handle);
        }
    };
}

// Common typed handles for convenience
pub const TextureHandle = TypedHandle(void); // Actual texture type would go here
pub const SoundHandle = TypedHandle(void); // Actual sound type would go here
pub const FontHandle = TypedHandle(void); // Actual font type would go here

// ============================================================================
// Asset Bundle
// ============================================================================

/// A collection of related assets loaded together
pub const AssetBundle = struct {
    name: []const u8,
    assets: std.ArrayList(AssetHandle),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !AssetBundle {
        return .{
            .name = try allocator.dupe(u8, name),
            .assets = std.ArrayList(AssetHandle).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *AssetBundle) void {
        self.allocator.free(self.name);
        self.assets.deinit();
    }

    /// Add an asset to the bundle
    pub fn add(self: *AssetBundle, handle: AssetHandle) !void {
        try self.assets.append(handle);
    }

    /// Load all assets in the bundle
    pub fn loadAll(self: *AssetBundle, registry: *AssetRegistry) !void {
        for (self.assets.items) |handle| {
            try registry.load(handle);
        }
    }

    /// Release all assets in the bundle
    pub fn releaseAll(self: *AssetBundle, registry: *AssetRegistry) void {
        for (self.assets.items) |handle| {
            registry.release(handle);
        }
    }

    /// Check if all assets are loaded
    pub fn isLoaded(self: *const AssetBundle, registry: *const AssetRegistry) bool {
        for (self.assets.items) |handle| {
            if (!registry.isLoaded(handle)) {
                return false;
            }
        }
        return true;
    }

    /// Get loading progress (0.0 to 1.0)
    pub fn getProgress(self: *const AssetBundle, registry: *const AssetRegistry) f32 {
        if (self.assets.items.len == 0) return 1.0;

        var loaded_count: usize = 0;
        for (self.assets.items) |handle| {
            if (registry.isLoaded(handle)) {
                loaded_count += 1;
            }
        }

        return @as(f32, @floatFromInt(loaded_count)) / @as(f32, @floatFromInt(self.assets.items.len));
    }
};

// ============================================================================
// Tests
// ============================================================================

test "AssetHandle - basic operations" {
    const handle = AssetHandle{ .index = 5, .generation = 2 };
    try std.testing.expect(handle.isValid());
    try std.testing.expectEqual(@as(AssetIndex, 5), handle.index);
    try std.testing.expectEqual(@as(Generation, 2), handle.generation);

    const invalid = AssetHandle.invalid();
    try std.testing.expect(!invalid.isValid());
}

test "AssetType - fromExtension" {
    try std.testing.expectEqual(AssetType.texture, AssetType.fromExtension(".png"));
    try std.testing.expectEqual(AssetType.texture, AssetType.fromExtension(".jpg"));
    try std.testing.expectEqual(AssetType.sound, AssetType.fromExtension(".wav"));
    try std.testing.expectEqual(AssetType.music, AssetType.fromExtension(".ogg"));
    try std.testing.expectEqual(AssetType.font, AssetType.fromExtension(".ttf"));
    try std.testing.expectEqual(AssetType.data, AssetType.fromExtension(".toml"));
    try std.testing.expectEqual(AssetType.other, AssetType.fromExtension(".xyz"));
}

test "AssetMetadata - basic operations" {
    var meta = try AssetMetadata.init(std.testing.allocator, "test/asset.png", .texture, 0);
    defer meta.deinit();

    try std.testing.expectEqualStrings("test/asset.png", meta.path);
    try std.testing.expectEqual(AssetType.texture, meta.asset_type);
    try std.testing.expectEqual(AssetState.unloaded, meta.state);
    try std.testing.expectEqual(@as(u32, 0), meta.ref_count);
}

test "AssetMetadata - dependencies" {
    var meta = try AssetMetadata.init(std.testing.allocator, "test.png", .texture, 0);
    defer meta.deinit();

    const dep1 = AssetHandle{ .index = 1, .generation = 0 };
    const dep2 = AssetHandle{ .index = 2, .generation = 0 };

    try meta.addDependency(dep1);
    try meta.addDependency(dep2);
    try meta.addDependency(dep1); // Duplicate, should be ignored

    try std.testing.expectEqual(@as(usize, 2), meta.dependencies.items.len);

    try meta.addDependent(dep1);
    try std.testing.expectEqual(@as(usize, 1), meta.dependents.items.len);

    meta.removeDependent(dep1);
    try std.testing.expectEqual(@as(usize, 0), meta.dependents.items.len);
}

test "AssetRegistry - init and deinit" {
    var registry = AssetRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try std.testing.expectEqual(@as(usize, 0), registry.getActiveCount());
}

test "AssetRegistry - getOrCreateHandle" {
    var registry = AssetRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const handle1 = try registry.getOrCreateHandle("assets/player.png");
    try std.testing.expect(handle1.isValid());
    try std.testing.expect(registry.isHandleValid(handle1));

    // Same path should return same handle
    const handle2 = try registry.getOrCreateHandle("assets/player.png");
    try std.testing.expectEqual(handle1.index, handle2.index);
    try std.testing.expectEqual(handle1.generation, handle2.generation);

    // Different path should return different handle
    const handle3 = try registry.getOrCreateHandle("assets/enemy.png");
    try std.testing.expect(handle3.index != handle1.index);

    // Check metadata
    const meta = registry.getMetadata(handle1).?;
    try std.testing.expectEqualStrings("assets/player.png", meta.path);
    try std.testing.expectEqual(AssetType.texture, meta.asset_type);
}

test "AssetRegistry - registerLoader and load" {
    var registry = AssetRegistry.init(std.testing.allocator);
    defer registry.deinit();

    // Simple test data
    const TestData = struct {
        value: u32,
    };

    // Register a test loader
    const TestLoader = struct {
        fn load(_: []const u8, allocator: std.mem.Allocator) LoadError!*anyopaque {
            const data = allocator.create(TestData) catch return LoadError.OutOfMemory;
            data.value = 42;
            return @ptrCast(data);
        }

        fn unload(data: *anyopaque, allocator: std.mem.Allocator) void {
            const typed: *TestData = @ptrCast(@alignCast(data));
            allocator.destroy(typed);
        }
    };

    try registry.registerLoader(.data, TestLoader.load, TestLoader.unload);

    const handle = try registry.getOrCreateHandle("test.toml");
    try registry.load(handle);

    try std.testing.expect(registry.isLoaded(handle));
    try std.testing.expectEqual(AssetState.loaded, registry.getState(handle).?);

    const data = registry.getData(TestData, handle).?;
    try std.testing.expectEqual(@as(u32, 42), data.value);

    // Check stats
    const stats = registry.getStats();
    try std.testing.expectEqual(@as(usize, 1), stats.total_loaded);
    try std.testing.expectEqual(@as(usize, 1), stats.active_assets);

    // Release
    registry.release(handle);
    try std.testing.expect(!registry.isLoaded(handle));
    try std.testing.expectEqual(@as(usize, 1), registry.getStats().total_unloaded);
}

test "AssetRegistry - reference counting" {
    var registry = AssetRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const TestData = struct { value: u32 };

    const TestLoader = struct {
        fn load(_: []const u8, allocator: std.mem.Allocator) LoadError!*anyopaque {
            const data = allocator.create(TestData) catch return LoadError.OutOfMemory;
            data.value = 100;
            return @ptrCast(data);
        }

        fn unload(data: *anyopaque, allocator: std.mem.Allocator) void {
            const typed: *TestData = @ptrCast(@alignCast(data));
            allocator.destroy(typed);
        }
    };

    try registry.registerLoader(.data, TestLoader.load, TestLoader.unload);

    const handle = try registry.getOrCreateHandle("shared.toml");

    // Load twice (simulating two systems using the same asset)
    try registry.load(handle);
    try registry.load(handle);

    try std.testing.expectEqual(@as(u32, 2), registry.getMetadata(handle).?.ref_count);

    // Release once - should still be loaded
    registry.release(handle);
    try std.testing.expect(registry.isLoaded(handle));
    try std.testing.expectEqual(@as(u32, 1), registry.getMetadata(handle).?.ref_count);

    // Release again - should be unloaded
    registry.release(handle);
    try std.testing.expect(!registry.isLoaded(handle));
}

test "AssetRegistry - dependency tracking" {
    var registry = AssetRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const handle_a = try registry.getOrCreateHandle("asset_a.toml");
    const handle_b = try registry.getOrCreateHandle("asset_b.toml");

    // A depends on B
    try registry.addDependency(handle_a, handle_b);

    const meta_a = registry.getMetadata(handle_a).?;
    const meta_b = registry.getMetadata(handle_b).?;

    try std.testing.expectEqual(@as(usize, 1), meta_a.dependencies.items.len);
    try std.testing.expectEqual(@as(usize, 1), meta_b.dependents.items.len);
    try std.testing.expectEqual(@as(u32, 1), meta_b.ref_count); // Dependency adds ref
}

test "AssetBundle - basic operations" {
    var registry = AssetRegistry.init(std.testing.allocator);
    defer registry.deinit();

    var bundle = try AssetBundle.init(std.testing.allocator, "level1");
    defer bundle.deinit();

    const h1 = try registry.getOrCreateHandle("texture1.png");
    const h2 = try registry.getOrCreateHandle("texture2.png");

    try bundle.add(h1);
    try bundle.add(h2);

    try std.testing.expectEqual(@as(usize, 2), bundle.assets.items.len);
    try std.testing.expectEqualStrings("level1", bundle.name);

    // Progress should be 0 since nothing is loaded
    try std.testing.expectEqual(@as(f32, 0.0), bundle.getProgress(&registry));
}

test "TypedHandle - type safety" {
    var registry = AssetRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const MyData = struct { x: i32 };

    const raw_handle = try registry.getOrCreateHandle("data.toml");
    const typed = TypedHandle(MyData).init(raw_handle);

    try std.testing.expect(typed.isValid());
    try std.testing.expectEqual(raw_handle.index, typed.handle.index);

    const invalid_typed = TypedHandle(MyData).invalid();
    try std.testing.expect(!invalid_typed.isValid());
}

test "AssetRegistry - iterate loaded" {
    var registry = AssetRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const TestData = struct { value: u32 };

    const TestLoader = struct {
        fn load(_: []const u8, allocator: std.mem.Allocator) LoadError!*anyopaque {
            const data = allocator.create(TestData) catch return LoadError.OutOfMemory;
            data.value = 1;
            return @ptrCast(data);
        }

        fn unload(data: *anyopaque, allocator: std.mem.Allocator) void {
            const typed: *TestData = @ptrCast(@alignCast(data));
            allocator.destroy(typed);
        }
    };

    try registry.registerLoader(.data, TestLoader.load, TestLoader.unload);

    _ = try registry.loadByPath("a.toml");
    _ = try registry.loadByPath("b.toml");

    var count: usize = 0;
    var iter = registry.iterateLoaded();
    while (iter.next()) |_| {
        count += 1;
    }

    try std.testing.expectEqual(@as(usize, 2), count);
}

test "AssetRegistry - getHandle" {
    var registry = AssetRegistry.init(std.testing.allocator);
    defer registry.deinit();

    // Non-existent path should return null
    try std.testing.expect(registry.getHandle("nonexistent.png") == null);

    // Create a handle
    const created = try registry.getOrCreateHandle("exists.png");

    // Should be able to find it
    const found = registry.getHandle("exists.png");
    try std.testing.expect(found != null);
    try std.testing.expectEqual(created.index, found.?.index);
}

test "AssetRegistry - setAssetRoot" {
    var registry = AssetRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try registry.setAssetRoot("game/assets");
    try std.testing.expectEqualStrings("game/assets", registry.asset_root);

    // Change it
    try registry.setAssetRoot("other/path");
    try std.testing.expectEqualStrings("other/path", registry.asset_root);
}
