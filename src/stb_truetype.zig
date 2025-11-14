const std = @import("std");

// stb_truetype C API bindings
pub const c = @cImport({
    @cInclude("stb_truetype.h");
});

// =============================================================================
// Allocator Bridge for stb_truetype C API
// =============================================================================
// stb_truetype's pack API uses STBTT_malloc/free with NULL context.
// We bridge Zig's allocator to C via thread-local storage and allocation tracking.

/// Thread-local allocator for C callbacks
threadlocal var current_allocator: ?std.mem.Allocator = null;

/// Allocation tracking for proper deallocation
/// Maps pointer -> (size, alignment) so we can free correctly
const AllocationInfo = struct {
    slice: []u8,
};

var allocation_map: std.AutoHashMap(usize, AllocationInfo) = undefined;
var map_mutex: std.Thread.Mutex = .{};
var map_initialized: bool = false;

/// Initialize the allocation tracking system (call once at startup)
pub fn initAllocatorBridge(allocator: std.mem.Allocator) void {
    map_mutex.lock();
    defer map_mutex.unlock();

    if (!map_initialized) {
        allocation_map = std.AutoHashMap(usize, AllocationInfo).init(allocator);
        map_initialized = true;
    }
}

/// Deinitialize the allocation tracking system (call at shutdown)
pub fn deinitAllocatorBridge() void {
    map_mutex.lock();
    defer map_mutex.unlock();

    if (map_initialized) {
        allocation_map.deinit();
        map_initialized = false;
    }
}

/// Set the allocator for the current thread (call before using pack API)
pub fn setThreadAllocator(allocator: std.mem.Allocator) void {
    current_allocator = allocator;
}

/// Clear the thread allocator (call after pack API completes)
pub fn clearThreadAllocator() void {
    current_allocator = null;
}

/// C callback for allocation
export fn zig_stb_alloc(size: usize) callconv(.c) ?*anyopaque {
    const allocator = current_allocator orelse {
        std.debug.print("ERROR: zig_stb_alloc called with no allocator set!\n", .{});
        return null;
    };

    const bytes = allocator.alloc(u8, size) catch |err| {
        std.debug.print("ERROR: zig_stb_alloc failed: {}\n", .{err});
        return null;
    };

    const ptr = @intFromPtr(bytes.ptr);

    // Track allocation
    map_mutex.lock();
    defer map_mutex.unlock();

    allocation_map.put(ptr, .{ .slice = bytes }) catch |err| {
        std.debug.print("ERROR: Failed to track allocation: {}\n", .{err});
        allocator.free(bytes);
        return null;
    };

    return bytes.ptr;
}

/// C callback for deallocation
export fn zig_stb_free(ptr: ?*anyopaque) callconv(.c) void {
    if (ptr == null) return;

    const allocator = current_allocator orelse {
        std.debug.print("ERROR: zig_stb_free called with no allocator set!\n", .{});
        return;
    };

    const ptr_val = @intFromPtr(ptr.?);

    // Retrieve allocation info
    map_mutex.lock();
    defer map_mutex.unlock();

    const info = allocation_map.get(ptr_val) orelse {
        std.debug.print("ERROR: zig_stb_free called with untracked pointer!\n", .{});
        return;
    };

    // Free the memory
    allocator.free(info.slice);

    // Remove from tracking map
    _ = allocation_map.remove(ptr_val);
}

// Re-export commonly used types and functions with Zig-friendly names

// Core types
pub const FontInfo = c.stbtt_fontinfo;
pub const BakedChar = c.stbtt_bakedchar;
pub const AlignedQuad = c.stbtt_aligned_quad;
pub const PackContext = c.stbtt_pack_context;
pub const PackedChar = c.stbtt_packedchar;
pub const PackRange = c.stbtt_pack_range;
pub const Rect = c.stbrp_rect;
pub const Vertex = c.stbtt_vertex;

// Font initialization
pub const initFont = c.stbtt_InitFont;
pub const getFontOffsetForIndex = c.stbtt_GetFontOffsetForIndex;

// Character to glyph mapping
pub const findGlyphIndex = c.stbtt_FindGlyphIndex;

// Font metrics
pub const scaleForPixelHeight = c.stbtt_ScaleForPixelHeight;
pub const scaleForMappingEmToPixels = c.stbtt_ScaleForMappingEmToPixels;
pub const getFontVMetrics = c.stbtt_GetFontVMetrics;
pub const getFontVMetricsOS2 = c.stbtt_GetFontVMetricsOS2;
pub const getFontBoundingBox = c.stbtt_GetFontBoundingBox;

// Glyph metrics
pub const getCodepointHMetrics = c.stbtt_GetCodepointHMetrics;
pub const getCodepointKernAdvance = c.stbtt_GetCodepointKernAdvance;
pub const getCodepointBox = c.stbtt_GetCodepointBox;
pub const getGlyphHMetrics = c.stbtt_GetGlyphHMetrics;
pub const getGlyphKernAdvance = c.stbtt_GetGlyphKernAdvance;
pub const getGlyphBox = c.stbtt_GetGlyphBox;

// Glyph shapes
pub const getGlyphShape = c.stbtt_GetGlyphShape;
pub const getCodepointShape = c.stbtt_GetCodepointShape;
pub const freeShape = c.stbtt_FreeShape;

// Bitmap rendering
pub const freeBitmap = c.stbtt_FreeBitmap;
pub const getCodepointBitmap = c.stbtt_GetCodepointBitmap;
pub const getCodepointBitmapSubpixel = c.stbtt_GetCodepointBitmapSubpixel;
pub const makeCodepointBitmap = c.stbtt_MakeCodepointBitmap;
pub const makeCodepointBitmapSubpixel = c.stbtt_MakeCodepointBitmapSubpixel;
pub const getCodepointBitmapBox = c.stbtt_GetCodepointBitmapBox;
pub const getCodepointBitmapBoxSubpixel = c.stbtt_GetCodepointBitmapBoxSubpixel;

// Glyph bitmap rendering
pub const getGlyphBitmap = c.stbtt_GetGlyphBitmap;
pub const getGlyphBitmapSubpixel = c.stbtt_GetGlyphBitmapSubpixel;
pub const makeGlyphBitmap = c.stbtt_MakeGlyphBitmap;
pub const makeGlyphBitmapSubpixel = c.stbtt_MakeGlyphBitmapSubpixel;
pub const getGlyphBitmapBox = c.stbtt_GetGlyphBitmapBox;
pub const getGlyphBitmapBoxSubpixel = c.stbtt_GetGlyphBitmapBoxSubpixel;

// SDF (Signed Distance Field) rendering
pub const getGlyphSDF = c.stbtt_GetGlyphSDF;
pub const getCodepointSDF = c.stbtt_GetCodepointSDF;
pub const freeSDFBitmap = c.stbtt_FreeSDF;

// Bitmap baking (simple texture atlas generation)
pub const bakeFontBitmap = c.stbtt_BakeFontBitmap;
pub const getBakedQuad = c.stbtt_GetBakedQuad;

// Packing (advanced texture atlas generation)
pub const packBegin = c.stbtt_PackBegin;
pub const packEnd = c.stbtt_PackEnd;
pub const packFontRange = c.stbtt_PackFontRange;
pub const packFontRanges = c.stbtt_PackFontRanges;
pub const packFontRangesGatherRects = c.stbtt_PackFontRangesGatherRects;
pub const packFontRangesPackRects = c.stbtt_PackFontRangesPackRects;
pub const packFontRangesRenderIntoRects = c.stbtt_PackFontRangesRenderIntoRects;
pub const packSetOversampling = c.stbtt_PackSetOversampling;
pub const packSetSkipMissingCodepoints = c.stbtt_PackSetSkipMissingCodepoints;
pub const getPackedQuad = c.stbtt_GetPackedQuad;

// Font name information
pub const getFontNameString = c.stbtt_GetFontNameString;

// Constants
pub const MACSTYLE_DONTCARE = c.STBTT_MACSTYLE_DONTCARE;
pub const MACSTYLE_BOLD = c.STBTT_MACSTYLE_BOLD;
pub const MACSTYLE_ITALIC = c.STBTT_MACSTYLE_ITALIC;
pub const MACSTYLE_UNDERSCORE = c.STBTT_MACSTYLE_UNDERSCORE;
pub const MACSTYLE_NONE = c.STBTT_MACSTYLE_NONE;

// Platform IDs
pub const PLATFORM_ID_UNICODE = c.STBTT_PLATFORM_ID_UNICODE;
pub const PLATFORM_ID_MAC = c.STBTT_PLATFORM_ID_MAC;
pub const PLATFORM_ID_ISO = c.STBTT_PLATFORM_ID_ISO;
pub const PLATFORM_ID_MICROSOFT = c.STBTT_PLATFORM_ID_MICROSOFT;

// Vertex types for glyph shapes
pub const vmove = c.STBTT_vmove;
pub const vline = c.STBTT_vline;
pub const vcurve = c.STBTT_vcurve;
pub const vcubic = c.STBTT_vcubic;

test "stb_truetype imports correctly" {
    const testing = std.testing;
    _ = testing;
    // Just verify the module compiles
}
