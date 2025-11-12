const std = @import("std");

// stb_truetype C API bindings
pub const c = @cImport({
    @cDefine("STB_TRUETYPE_IMPLEMENTATION", "");
    @cInclude("stb_truetype.h");
});

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
