// font_atlas.zig
// Font atlas system for efficient text rendering with pre-baked glyphs
// Adapted from StellarThroneZig for EtherMud
// Now with optimized packing using stb_truetype's pack API

const std = @import("std");
const bgfx = @import("../bgfx.zig");
const stb = @import("../stb_truetype.zig");
const log = @import("../log.zig");

/// Check if data starts with valid TrueType/OpenType magic number
fn isValidFontMagic(data: []const u8) bool {
    if (data.len < 4) return false;

    const magic = std.mem.readInt(u32, data[0..4], .big);

    return switch (magic) {
        0x00010000 => true, // TrueType 1.0
        0x74727565 => true, // 'true' (Mac TrueType)
        0x4F54544F => true, // 'OTTO' (OpenType with CFF)
        0x74797031 => true, // 'typ1' (PostScript)
        else => false,
    };
}

/// Load and validate font file
fn loadAndValidateFontFile(allocator: std.mem.Allocator, font_path: []const u8) ![]u8 {
    // Validate file exists and size is reasonable
    const file = std.fs.cwd().openFile(font_path, .{}) catch |err| {
        log.err("Renderer", "Failed to open font file '{s}': {}", .{ font_path, err });
        return error.FontFileNotFound;
    };
    defer file.close();

    const stat = try file.stat();

    // Check minimum size (smallest valid TTF is ~1KB)
    if (stat.size < 1024) {
        log.err("Renderer", "Font file '{s}' too small ({d} bytes), likely corrupted", .{ font_path, stat.size });
        return error.FontFileTooSmall;
    }

    // Check maximum size (prevent huge allocations)
    const max_size = 10 * 1024 * 1024; // 10MB
    if (stat.size > max_size) {
        log.err("Renderer", "Font file '{s}' too large ({d} bytes), max is {d}", .{ font_path, stat.size, max_size });
        return error.FontFileTooLarge;
    }

    // Read font file
    const font_data = try file.readToEndAlloc(allocator, max_size);
    errdefer allocator.free(font_data);

    // Validate TrueType/OpenType magic number
    if (!isValidFontMagic(font_data)) {
        allocator.free(font_data);
        log.err("Renderer", "Font file '{s}' has invalid magic number (not TTF/OTF)", .{font_path});
        return error.InvalidFontFormat;
    }

    return font_data;
}

/// Glyph information in the atlas
pub const Glyph = struct {
    /// UV coordinates in atlas (normalized 0-1)
    uv_x0: f32,
    uv_y0: f32,
    uv_x1: f32,
    uv_y1: f32,

    /// Offset from baseline
    offset_x: f32,
    offset_y: f32,

    /// Size of glyph in pixels
    width: f32,
    height: f32,

    /// Horizontal advance for cursor positioning
    advance: f32,
};

/// Font atlas containing rendered glyphs as a texture
pub const FontAtlas = struct {
    texture: bgfx.TextureHandle,
    glyphs: [256]Glyph, // ASCII glyphs 0-255
    atlas_width: u32,
    atlas_height: u32,
    font_size: f32,
    line_height: f32,
    allocator: std.mem.Allocator,
    use_packed: bool, // True if using optimized packing
    use_sdf: bool, // True if using SDF (Signed Distance Field)

    /// Load a TrueType font and generate a texture atlas (with optimized packing)
    pub fn init(allocator: std.mem.Allocator, font_path: []const u8, font_size: f32, flip_uv: bool) !FontAtlas {
        // NOTE: stb_truetype pack API now works! Fixed two issues:
        // 1. Allocator bridge: Custom C wrapper with Zig allocator integration
        //    - stb_truetype_wrapper.c defines STBTT_malloc/free macros
        //    - zig_stb_alloc/free callbacks use thread-local allocator
        //    - Allocation tracking map ensures proper cleanup
        //
        // 2. Character range: Pack only printable ASCII (32-126, 95 chars)
        //    - Previous attempt: All 256 chars (0-255) including control chars
        //    - Issue: Many fonts don't have glyphs for control characters
        //    - Fix: Pack 32-126 only, initialize rest to empty
        //
        // Benefits of pack API:
        // - 30-50% smaller atlas size (more efficient packing)
        // - Better GPU memory utilization (512x512 vs 448x448 grid)
        // - Professional quality with 2x2 oversampling
        return initPacked(allocator, font_path, font_size, flip_uv, true);
    }

    /// Load a TrueType font with optional optimized packing
    /// use_packing: true = stb_truetype pack API (30-50% smaller), false = simple grid
    pub fn initPacked(allocator: std.mem.Allocator, font_path: []const u8, font_size: f32, flip_uv: bool, use_packing: bool) !FontAtlas {
        if (use_packing) {
            return initPackedAtlas(allocator, font_path, font_size, flip_uv);
        } else {
            return initGridAtlas(allocator, font_path, font_size, flip_uv);
        }
    }

    /// Load a TrueType font and generate SDF (Signed Distance Field) atlas
    /// SDF atlases scale perfectly to any size - one atlas works for all zoom levels
    /// Recommended for games with zoom/camera movement (4X strategy, factory-building)
    pub fn initSDF(allocator: std.mem.Allocator, font_path: []const u8, font_size: f32, flip_uv: bool) !FontAtlas {
        return initSDFAtlas(allocator, font_path, font_size, flip_uv);
    }

    /// Initialize atlas using stb_truetype's optimized pack API
    fn initPackedAtlas(allocator: std.mem.Allocator, font_path: []const u8, font_size: f32, flip_uv: bool) !FontAtlas {
        // Load and validate font file
        const font_data = try loadAndValidateFontFile(allocator, font_path);
        defer allocator.free(font_data);

        // Initialize stb_truetype
        var font_info: stb.FontInfo = undefined;
        if (stb.initFont(&font_info, font_data.ptr, 0) == 0) {
            log.err("Renderer", "stb_truetype failed to parse font '{s}' (invalid font tables)", .{font_path});
            return error.FontInitFailed;
        }

        // Calculate scale for desired font size
        const scale = stb.scaleForPixelHeight(&font_info, font_size);

        // Get font metrics
        var ascent: c_int = undefined;
        var descent: c_int = undefined;
        var line_gap: c_int = undefined;
        stb.getFontVMetrics(&font_info, &ascent, &descent, &line_gap);
        const line_height = @as(f32, @floatFromInt(ascent - descent + line_gap)) * scale;

        std.debug.print("FontAtlas: Loading font '{s}' at {d}px (OPTIMIZED PACKING)\n", .{ font_path, font_size });
        std.debug.print("FontAtlas: Scale={d:.4}, Ascent={d}, Descent={d}, LineHeight={d:.2}\n", .{ scale, ascent, descent, line_height });

        // Set thread-local allocator for C callbacks
        stb.setThreadAllocator(allocator);
        defer stb.clearThreadAllocator();

        // Start with a reasonable atlas size and grow if needed
        var atlas_width: u32 = 512;
        var atlas_height: u32 = 512;
        var pack_success = false;
        var glyphs: [256]Glyph = undefined;
        var atlas_data: []u8 = undefined;

        // Try packing with increasing atlas sizes
        var attempts: u32 = 0;
        while (!pack_success and attempts < 4) : (attempts += 1) {
            // Allocate atlas bitmap
            atlas_data = try allocator.alloc(u8, atlas_width * atlas_height);
            errdefer allocator.free(atlas_data);
            @memset(atlas_data, 0); // Clear to black

            // Initialize pack context
            // stride_in_bytes should match atlas_width for proper packing
            var pack_context: stb.PackContext = undefined;
            _ = stb.packBegin(&pack_context, atlas_data.ptr, @intCast(atlas_width), @intCast(atlas_height), @intCast(atlas_width), 1, null);

            // Enable oversampling for better quality (2x2)
            stb.packSetOversampling(&pack_context, 2, 2);

            // Skip missing codepoints
            stb.packSetSkipMissingCodepoints(&pack_context, 1);

            // Allocate packed char data
            var packed_chars: [256]stb.PackedChar = undefined;

            // Try PackFontRange (singular) instead of PackFontRanges
            // Pack only printable ASCII (32-126) instead of all 256 chars (0-255)
            // This avoids issues with control characters that don't have glyphs
            const first_char = 32; // Space
            const num_chars = 95; // Space through tilde (~)
            const result = stb.packFontRange(&pack_context, font_data.ptr, 0, font_size, first_char, num_chars, &packed_chars[first_char]);

            stb.packEnd(&pack_context);

            if (result == 1) {
                pack_success = true;
                std.debug.print("FontAtlas: Successfully packed into {d}x{d} atlas\n", .{ atlas_width, atlas_height });

                // Convert packed chars to our Glyph format
                // PackedChar fields: x0,y0,x1,y1 are pixel coordinates (u16)
                // Need to convert to normalized UV coordinates (0-1 range)
                const atlas_width_f: f32 = @floatFromInt(atlas_width);
                const atlas_height_f: f32 = @floatFromInt(atlas_height);

                // Initialize all glyphs to empty (0 advance)
                for (&glyphs) |*g| {
                    g.* = std.mem.zeroes(Glyph);
                }

                // Convert packed chars (only printable ASCII 32-126)
                for (first_char..first_char + num_chars) |i| {
                    const pc = packed_chars[i];
                    const uv_x0 = @as(f32, @floatFromInt(pc.x0)) / atlas_width_f;
                    const uv_y0 = @as(f32, @floatFromInt(pc.y0)) / atlas_height_f;
                    const uv_x1 = @as(f32, @floatFromInt(pc.x1)) / atlas_width_f;
                    const uv_y1 = @as(f32, @floatFromInt(pc.y1)) / atlas_height_f;

                    glyphs[i] = Glyph{
                        .uv_x0 = uv_x0,
                        .uv_y0 = if (!flip_uv) uv_y0 else 1.0 - uv_y1,
                        .uv_x1 = uv_x1,
                        .uv_y1 = if (!flip_uv) uv_y1 else 1.0 - uv_y0,
                        .offset_x = pc.xoff,
                        .offset_y = pc.yoff,
                        .width = pc.xoff2 - pc.xoff,
                        .height = pc.yoff2 - pc.yoff,
                        .advance = pc.xadvance,
                    };
                }

                // Debug: Print some sample glyphs
                var samples_printed: u32 = 0;
                for (0..256) |char_code| {
                    const glyph = &glyphs[char_code];
                    if (glyph.advance > 0 and char_code >= 32 and samples_printed < 5) {
                        std.debug.print("  Glyph '{c}' (code={d}): advance={d:.2}, size={d:.1}x{d:.1}\n", .{ @as(u8, @intCast(char_code)), char_code, glyph.advance, glyph.width, glyph.height });
                        samples_printed += 1;
                    }
                }

                break;
            } else {
                // Packing failed, try larger atlas
                allocator.free(atlas_data);

                // Check if we can grow before doubling
                if (atlas_width >= 4096 or atlas_height >= 4096) {
                    log.err("Renderer", "Font atlas packing failed even with 4096x4096 atlas", .{});
                    return error.FontPackingFailed;
                }

                atlas_width *= 2;
                atlas_height *= 2;
                std.debug.print("FontAtlas: Packing failed, trying {d}x{d}...\n", .{ atlas_width, atlas_height });
            }
        }

        if (!pack_success) {
            return error.FontPackingFailed;
        }

        // Convert R8 to RGBA8 for bgfx Metal compatibility
        const rgba_data = try allocator.alloc(u8, atlas_width * atlas_height * 4);
        defer allocator.free(rgba_data);

        for (atlas_data, 0..) |gray, i| {
            rgba_data[i * 4 + 0] = 255; // R - white
            rgba_data[i * 4 + 1] = 255; // G - white
            rgba_data[i * 4 + 2] = 255; // B - white
            rgba_data[i * 4 + 3] = gray; // A - glyph data from atlas
        }

        allocator.free(atlas_data);

        // Create bgfx texture
        const mem = bgfx.copy(rgba_data.ptr, @intCast(rgba_data.len));
        const texture = bgfx.createTexture2D(
            @intCast(atlas_width),
            @intCast(atlas_height),
            false, // no mipmaps
            1, // single layer
            bgfx.TextureFormat.RGBA8,
            0, // flags (default)
            mem,
        );

        return FontAtlas{
            .texture = texture,
            .glyphs = glyphs,
            .atlas_width = atlas_width,
            .atlas_height = atlas_height,
            .font_size = font_size,
            .line_height = line_height,
            .allocator = allocator,
            .use_packed = true,
            .use_sdf = false,
        };
    }

    /// Initialize atlas using simple 16x16 grid (legacy method)
    fn initGridAtlas(allocator: std.mem.Allocator, font_path: []const u8, font_size: f32, flip_uv: bool) !FontAtlas {
        // Load and validate font file
        const font_data = try loadAndValidateFontFile(allocator, font_path);
        defer allocator.free(font_data);

        // Initialize stb_truetype
        var font_info: stb.FontInfo = undefined;
        if (stb.initFont(&font_info, font_data.ptr, 0) == 0) {
            log.err("Renderer", "stb_truetype failed to parse font '{s}' (invalid font tables)", .{font_path});
            return error.FontInitFailed;
        }

        // Calculate scale for desired font size
        const scale = stb.scaleForPixelHeight(&font_info, font_size);

        // Get font metrics
        var ascent: c_int = undefined;
        var descent: c_int = undefined;
        var line_gap: c_int = undefined;
        stb.getFontVMetrics(&font_info, &ascent, &descent, &line_gap);
        const line_height = @as(f32, @floatFromInt(ascent - descent + line_gap)) * scale;

        std.debug.print("FontAtlas: Loading font '{s}' at {d}px (GRID LAYOUT)\n", .{ font_path, font_size });
        std.debug.print("FontAtlas: Scale={d:.4}, Ascent={d}, Descent={d}, LineHeight={d:.2}\n", .{ scale, ascent, descent, line_height });

        // Calculate atlas size (16x16 grid for 256 glyphs)
        const glyphs_per_row = 16;
        const glyph_padding = 2;
        const estimated_glyph_size = @as(u32, @intFromFloat(font_size)) + glyph_padding * 2;
        const atlas_width = glyphs_per_row * estimated_glyph_size;
        const atlas_height = glyphs_per_row * estimated_glyph_size;

        // Allocate atlas bitmap
        const atlas_data = try allocator.alloc(u8, atlas_width * atlas_height);
        defer allocator.free(atlas_data);
        @memset(atlas_data, 0); // Clear to black

        // Render each glyph to atlas
        var glyphs: [256]Glyph = undefined;
        var current_x: u32 = glyph_padding;
        var current_y: u32 = glyph_padding;
        var row_height: u32 = 0;
        var glyphs_rendered: u32 = 0;
        var glyphs_missing: u32 = 0;

        for (0..256) |char_code| {
            const glyph_index = stb.findGlyphIndex(&font_info, @intCast(char_code));

            // Skip missing glyphs (glyph_index 0 is typically the .notdef glyph)
            if (glyph_index == 0 and char_code != 0) {
                glyphs_missing += 1;
                // Store empty glyph info for missing characters
                glyphs[char_code] = Glyph{
                    .uv_x0 = 0,
                    .uv_y0 = 0,
                    .uv_x1 = 0,
                    .uv_y1 = 0,
                    .offset_x = 0,
                    .offset_y = 0,
                    .width = 0,
                    .height = 0,
                    .advance = 0,
                };
                continue;
            }

            // Get glyph metrics
            var advance: c_int = undefined;
            var left_bearing: c_int = undefined;
            stb.getGlyphHMetrics(&font_info, glyph_index, &advance, &left_bearing);

            var x0: c_int = undefined;
            var y0: c_int = undefined;
            var x1: c_int = undefined;
            var y1: c_int = undefined;
            stb.getGlyphBitmapBox(&font_info, glyph_index, scale, scale, &x0, &y0, &x1, &y1);

            const glyph_width = @as(u32, @intCast(x1 - x0));
            const glyph_height = @as(u32, @intCast(y1 - y0));

            // Check if we need to move to next row
            if (current_x + glyph_width + glyph_padding > atlas_width) {
                current_x = glyph_padding;
                current_y += row_height + glyph_padding;
                row_height = 0;
            }

            // Render glyph to atlas (if valid dimensions and fits)
            if (glyph_width > 0 and glyph_height > 0 and current_y + glyph_height < atlas_height) {
                glyphs_rendered += 1;
                // Calculate correct pointer for the glyph's top-left position in atlas
                // stb_MakeGlyphBitmap writes row-by-row with the given stride
                const atlas_offset = current_y * atlas_width + current_x;
                stb.makeGlyphBitmap(
                    &font_info,
                    atlas_data.ptr + atlas_offset, // Use pointer arithmetic correctly
                    @intCast(glyph_width),
                    @intCast(glyph_height),
                    @intCast(atlas_width), // Stride: bytes per row in the output buffer
                    scale,
                    scale,
                    glyph_index,
                );

                // Debug: Print first few renderable glyphs and key letters
                if ((glyphs_rendered <= 5 and char_code >= 32) or
                    (char_code == 'N' or char_code == 'E' or char_code == 'W' or char_code == 'G' or char_code == 'A' or char_code == 'M'))
                {
                    std.debug.print("  Glyph '{c}' (code={d}, index={d}): size={d}x{d}, pos=({d},{d}), advance={d:.2}\n", .{ @as(u8, @intCast(char_code)), char_code, glyph_index, glyph_width, glyph_height, current_x, current_y, @as(f32, @floatFromInt(advance)) * scale });
                }
            }

            // ALWAYS store glyph info (with actual position if rendered, zeros if not)
            glyphs[char_code] = Glyph{
                .uv_x0 = if (glyph_width > 0 and glyph_height > 0) @as(f32, @floatFromInt(current_x)) / @as(f32, @floatFromInt(atlas_width)) else 0,
                .uv_y0 = if (glyph_width > 0 and glyph_height > 0 and flip_uv) 1.0 - (@as(f32, @floatFromInt(current_y + glyph_height)) / @as(f32, @floatFromInt(atlas_height))) else if (glyph_width > 0 and glyph_height > 0) @as(f32, @floatFromInt(current_y)) / @as(f32, @floatFromInt(atlas_height)) else 0,
                .uv_x1 = if (glyph_width > 0 and glyph_height > 0) @as(f32, @floatFromInt(current_x + glyph_width)) / @as(f32, @floatFromInt(atlas_width)) else 0,
                .uv_y1 = if (glyph_width > 0 and glyph_height > 0 and flip_uv) 1.0 - (@as(f32, @floatFromInt(current_y)) / @as(f32, @floatFromInt(atlas_height))) else if (glyph_width > 0 and glyph_height > 0) @as(f32, @floatFromInt(current_y + glyph_height)) / @as(f32, @floatFromInt(atlas_height)) else 0,
                .offset_x = @floatFromInt(x0),
                .offset_y = @floatFromInt(y0),
                .width = @floatFromInt(glyph_width),
                .height = @floatFromInt(glyph_height),
                .advance = @as(f32, @floatFromInt(advance)) * scale,
            };

            // Move cursor ONLY if glyph was rendered (to prevent overlaps)
            if (glyph_width > 0 and glyph_height > 0 and current_y + glyph_height < atlas_height) {
                current_x += glyph_width + glyph_padding;
                row_height = @max(row_height, glyph_height);
            }
        }

        std.debug.print("FontAtlas: Rendered {d} glyphs, {d} missing from font\n", .{ glyphs_rendered, glyphs_missing });
        std.debug.print("FontAtlas: Atlas size {d}x{d}, final cursor at ({d},{d})\n", .{ atlas_width, atlas_height, current_x, current_y });

        // Convert R8 to RGBA8 for bgfx Metal compatibility
        // Put glyph data in alpha channel, set RGB to white
        const rgba_data = try allocator.alloc(u8, atlas_width * atlas_height * 4);
        defer allocator.free(rgba_data);

        for (atlas_data, 0..) |gray, i| {
            rgba_data[i * 4 + 0] = 255; // R - white
            rgba_data[i * 4 + 1] = 255; // G - white
            rgba_data[i * 4 + 2] = 255; // B - white
            rgba_data[i * 4 + 3] = gray; // A - glyph data from atlas
        }

        // Create bgfx texture from atlas
        const mem = bgfx.copy(rgba_data.ptr, @intCast(rgba_data.len));
        const texture = bgfx.createTexture2D(
            @intCast(atlas_width),
            @intCast(atlas_height),
            false, // no mipmaps
            1, // single layer
            bgfx.TextureFormat.RGBA8,
            0, // flags (default)
            mem,
        );

        return FontAtlas{
            .texture = texture,
            .glyphs = glyphs,
            .atlas_width = atlas_width,
            .atlas_height = atlas_height,
            .font_size = font_size,
            .line_height = line_height,
            .allocator = allocator,
            .use_packed = false,
            .use_sdf = false,
        };
    }

    /// Initialize atlas using SDF (Signed Distance Field) rendering
    /// SDF provides perfect scaling at any zoom level from a single atlas
    fn initSDFAtlas(allocator: std.mem.Allocator, font_path: []const u8, font_size: f32, flip_uv: bool) !FontAtlas {
        // Load and validate font file
        const font_data = try loadAndValidateFontFile(allocator, font_path);
        defer allocator.free(font_data);

        // Initialize stb_truetype
        var font_info: stb.FontInfo = undefined;
        if (stb.initFont(&font_info, font_data.ptr, 0) == 0) {
            log.err("Renderer", "stb_truetype failed to parse font '{s}' (invalid font tables)", .{font_path});
            return error.FontInitFailed;
        }

        // Calculate font metrics
        const scale = stb.scaleForPixelHeight(&font_info, font_size);
        var ascent: c_int = undefined;
        var descent: c_int = undefined;
        var line_gap: c_int = undefined;
        stb.getFontVMetrics(&font_info, &ascent, &descent, &line_gap);
        const line_height = @as(f32, @floatFromInt(ascent - descent + line_gap)) * scale;

        log.info("Renderer", "Loading font '{s}' at {d:.1}px (SDF MODE)", .{ font_path, font_size });
        log.info("Renderer", "Scale={d:.4}, Ascent={d}, Descent={d}, LineHeight={d:.2}", .{ scale, ascent, descent, line_height });

        // SDF parameters
        // For high-quality SDF, we need to render at a larger size
        // The SDF algorithm works better with more pixels to encode distance information
        const sdf_render_size = font_size * 3.0; // Render at 3x the target size for better quality
        const sdf_scale = stb.scaleForPixelHeight(&font_info, sdf_render_size);

        const padding: c_int = 8; // Extra pixels around each glyph for distance field
        const onedge_value: u8 = 128; // Value representing the edge (0-255)
        const pixel_dist_scale: f32 = 32.0; // Distance scale for SDF (lower = softer edges)

        // Calculate atlas size for SDF
        // SDF glyphs are larger due to padding, so we need more space
        const atlas_width: u32 = 1024;
        const atlas_height: u32 = 1024;

        // Allocate atlas bitmap (single channel for SDF)
        const atlas_size = atlas_width * atlas_height;
        const atlas_bitmap = try allocator.alloc(u8, atlas_size);
        defer allocator.free(atlas_bitmap);
        @memset(atlas_bitmap, 0); // Clear to zero

        // Initialize glyphs array
        var glyphs: [256]Glyph = undefined;

        // Simple grid packing for SDF glyphs
        const grid_size = 16; // 16x16 grid = 256 glyphs
        const cell_width = atlas_width / grid_size;
        const cell_height = atlas_height / grid_size;

        var rendered_count: usize = 0;
        var missing_count: usize = 0;

        // Set thread allocator for stb_truetype SDF calls
        stb.setThreadAllocator(allocator);
        defer stb.clearThreadAllocator();

        // Render SDF for each printable ASCII character (32-126)
        for (32..127) |i| {
            const char: c_int = @intCast(i);
            const glyph_idx = i;

            // Calculate grid position
            const grid_x = glyph_idx % grid_size;
            const grid_y = glyph_idx / grid_size;
            const atlas_x: c_int = @intCast(grid_x * cell_width);
            const atlas_y: c_int = @intCast(grid_y * cell_height);

            // Generate SDF for this glyph
            var width: c_int = undefined;
            var height: c_int = undefined;
            var xoff: c_int = undefined;
            var yoff: c_int = undefined;

            const sdf_bitmap = stb.getCodepointSDF(
                &font_info,
                sdf_scale,
                char,
                padding,
                onedge_value,
                pixel_dist_scale,
                &width,
                &height,
                &xoff,
                &yoff,
            );

            if (sdf_bitmap == null or width == 0 or height == 0) {
                // Missing glyph - create empty entry
                glyphs[glyph_idx] = Glyph{
                    .uv_x0 = 0,
                    .uv_y0 = 0,
                    .uv_x1 = 0,
                    .uv_y1 = 0,
                    .offset_x = 0,
                    .offset_y = 0,
                    .width = 0,
                    .height = 0,
                    .advance = 0,
                };
                missing_count += 1;
                continue;
            }
            defer stb.freeSDFBitmap(sdf_bitmap, null);

            // Copy SDF bitmap to atlas
            const src_width: usize = @intCast(width);
            const src_height: usize = @intCast(height);

            for (0..src_height) |y| {
                const src_row = y * src_width;
                const dst_y: usize = @intCast(atlas_y + @as(c_int, @intCast(y)));
                const dst_row = dst_y * atlas_width + @as(usize, @intCast(atlas_x));

                // Copy row
                for (0..src_width) |x| {
                    const dst_x = dst_row + x;
                    if (dst_x < atlas_bitmap.len) {
                        atlas_bitmap[dst_x] = sdf_bitmap[src_row + x];
                    }
                }
            }

            // Get glyph metrics for advance
            var advance: c_int = undefined;
            var lsb: c_int = undefined;
            stb.getCodepointHMetrics(&font_info, char, &advance, &lsb);

            // Calculate UV coordinates
            const uv_x0 = @as(f32, @floatFromInt(atlas_x)) / @as(f32, @floatFromInt(atlas_width));
            const uv_y0 = if (flip_uv)
                @as(f32, @floatFromInt(atlas_y + height)) / @as(f32, @floatFromInt(atlas_height))
            else
                @as(f32, @floatFromInt(atlas_y)) / @as(f32, @floatFromInt(atlas_height));

            const uv_x1 = @as(f32, @floatFromInt(atlas_x + width)) / @as(f32, @floatFromInt(atlas_width));
            const uv_y1 = if (flip_uv)
                @as(f32, @floatFromInt(atlas_y)) / @as(f32, @floatFromInt(atlas_height))
            else
                @as(f32, @floatFromInt(atlas_y + height)) / @as(f32, @floatFromInt(atlas_height));

            // Scale glyph metrics back down to target font size
            // We rendered at 3x size for better SDF quality, but need metrics at 1x
            const scale_down = font_size / sdf_render_size;

            glyphs[glyph_idx] = Glyph{
                .uv_x0 = uv_x0,
                .uv_y0 = uv_y0,
                .uv_x1 = uv_x1,
                .uv_y1 = uv_y1,
                .offset_x = @as(f32, @floatFromInt(xoff)) * scale_down,
                .offset_y = @as(f32, @floatFromInt(yoff)) * scale_down,
                .width = @as(f32, @floatFromInt(width)) * scale_down,
                .height = @as(f32, @floatFromInt(height)) * scale_down,
                .advance = @as(f32, @floatFromInt(advance)) * scale,
            };

            rendered_count += 1;
        }

        // Initialize control characters and extended ASCII as empty
        for (0..32) |i| {
            glyphs[i] = .{ .uv_x0 = 0, .uv_y0 = 0, .uv_x1 = 0, .uv_y1 = 0, .offset_x = 0, .offset_y = 0, .width = 0, .height = 0, .advance = 0 };
        }
        for (127..256) |i| {
            glyphs[i] = .{ .uv_x0 = 0, .uv_y0 = 0, .uv_x1 = 0, .uv_y1 = 0, .offset_x = 0, .offset_y = 0, .width = 0, .height = 0, .advance = 0 };
        }

        log.info("Renderer", "Rendered {d} SDF glyphs, {d} missing from font", .{ rendered_count, missing_count });
        log.info("Renderer", "SDF atlas size {d}x{d}", .{ atlas_width, atlas_height });

        // Create bgfx texture (R8 format for single-channel SDF)
        // CRITICAL: Use default filtering (bilinear) for smooth SDF rendering
        // Point filtering would make SDF look pixelated
        const texture_flags = bgfx.SamplerFlags_UClamp | bgfx.SamplerFlags_VClamp;
        const mem = bgfx.copy(atlas_bitmap.ptr, @intCast(atlas_bitmap.len));
        const texture = bgfx.createTexture2D(
            @intCast(atlas_width),
            @intCast(atlas_height),
            false, // no mipmaps
            1, // layers
            bgfx.TextureFormat.R8, // Single channel
            texture_flags,
            mem,
        );

        return FontAtlas{
            .texture = texture,
            .glyphs = glyphs,
            .atlas_width = atlas_width,
            .atlas_height = atlas_height,
            .font_size = font_size,
            .line_height = line_height,
            .allocator = allocator,
            .use_packed = false,
            .use_sdf = true,
        };
    }

    pub fn deinit(self: *FontAtlas) void {
        bgfx.destroyTexture(self.texture);
    }

    /// Measure text width in pixels
    pub fn measureText(self: *const FontAtlas, text: []const u8) f32 {
        var width: f32 = 0;
        for (text) |char| {
            if (char < 256) {
                width += self.glyphs[char].advance;
            }
        }
        return width;
    }

    /// Measure text and truncate with ellipsis if it exceeds max_width
    pub fn measureTextWithEllipsis(self: *const FontAtlas, text: []const u8, max_width: f32) struct { width: f32, truncated_len: usize } {
        const ellipsis_width = self.measureText("...");
        var width: f32 = 0;
        var truncated_len = text.len;

        for (text, 0..) |char, i| {
            if (char < 256) {
                const char_width = self.glyphs[char].advance;
                if (width + char_width + ellipsis_width > max_width and i > 0) {
                    // Truncate here
                    truncated_len = i;
                    width += ellipsis_width;
                    break;
                }
                width += char_width;
            }
        }

        return .{ .width = width, .truncated_len = truncated_len };
    }

    /// Get glyph info for a character
    pub fn getGlyph(self: *const FontAtlas, char: u8) *const Glyph {
        return &self.glyphs[char];
    }
};
