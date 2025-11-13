const std = @import("std");
const root = @import("../root.zig");
const bgfx = root.bgfx;
const stb = root.stb_truetype;
const types = @import("types.zig");
const shaders = @import("shaders.zig");
const log = @import("../log.zig");

pub const Rect = types.Rect;
pub const Color = types.Color;
pub const Vec2 = types.Vec2;

/// Vertex for colored 2D primitives
const ColorVertex = extern struct {
    x: f32,
    y: f32,
    abgr: u32,

    fn init(x: f32, y: f32, color: Color) ColorVertex {
        return .{
            .x = x,
            .y = y,
            .abgr = colorToABGR(color),
        };
    }
};

/// Vertex for textured 2D primitives (fonts, images)
const TextureVertex = extern struct {
    x: f32,
    y: f32,
    u: f32,
    v: f32,
    abgr: u32,

    fn init(x: f32, y: f32, u: f32, v: f32, color: Color) TextureVertex {
        return .{
            .x = x,
            .y = y,
            .u = u,
            .v = v,
            .abgr = colorToABGR(color),
        };
    }
};

/// Convert Color to ABGR format
fn colorToABGR(color: Color) u32 {
    return (@as(u32, color.a) << 24) |
        (@as(u32, color.b) << 16) |
        (@as(u32, color.g) << 8) |
        (@as(u32, color.r) << 0);
}

/// Font atlas for text rendering
const FontAtlas = struct {
    texture: bgfx.TextureHandle,
    width: u32,
    height: u32,
    char_data: [96]stb.c.stbtt_bakedchar, // ASCII 32-127
    font_size: f32,
    ascent: f32,
    descent: f32,
    line_gap: f32,

    fn init(allocator: std.mem.Allocator, font_data: []const u8, font_size: f32) !FontAtlas {
        const atlas_width: u32 = 1024;
        const atlas_height: u32 = 1024;

        // Initialize font info to get metrics
        var font_info: stb.FontInfo = undefined;
        if (stb.initFont(&font_info, font_data.ptr, 0) == 0) {
            return error.FontInitFailed;
        }

        // Get font vertical metrics
        var ascent: c_int = undefined;
        var descent: c_int = undefined;
        var line_gap: c_int = undefined;
        stb.getFontVMetrics(&font_info, &ascent, &descent, &line_gap);

        // Scale metrics to pixel height
        const scale = stb.scaleForPixelHeight(&font_info, font_size);
        const scaled_ascent = @as(f32, @floatFromInt(ascent)) * scale;
        const scaled_descent = @as(f32, @floatFromInt(descent)) * scale;
        const scaled_line_gap = @as(f32, @floatFromInt(line_gap)) * scale;

        // Allocate bitmap for font atlas
        const bitmap = try allocator.alloc(u8, atlas_width * atlas_height);
        defer allocator.free(bitmap);
        @memset(bitmap, 0);

        var char_data: [96]stb.c.stbtt_bakedchar = undefined;

        // Bake font into bitmap
        const result = stb.bakeFontBitmap(
            font_data.ptr,
            0,
            font_size,
            bitmap.ptr,
            @intCast(atlas_width),
            @intCast(atlas_height),
            32, // First char (space)
            96, // Num chars
            &char_data,
        );

        if (result < 0) {
            return error.FontBakeFailed;
        }

        // Convert grayscale to RGBA
        const rgba_bitmap = try allocator.alloc(u8, atlas_width * atlas_height * 4);
        defer allocator.free(rgba_bitmap);

        for (bitmap, 0..) |gray, i| {
            rgba_bitmap[i * 4 + 0] = 255; // R
            rgba_bitmap[i * 4 + 1] = 255; // G
            rgba_bitmap[i * 4 + 2] = 255; // B
            rgba_bitmap[i * 4 + 3] = gray; // A
        }

        // Create bgfx texture with clamp sampling to prevent bleeding at edges
        // Use linear filtering for smooth text rendering
        const texture_mem = bgfx.copy(rgba_bitmap.ptr, @intCast(rgba_bitmap.len));
        const texture_flags = bgfx.SamplerFlags_UClamp | bgfx.SamplerFlags_VClamp;
        const texture = bgfx.createTexture2D(
            @intCast(atlas_width),
            @intCast(atlas_height),
            false,
            1,
            bgfx.TextureFormat.RGBA8,
            texture_flags,
            texture_mem,
        );

        return .{
            .texture = texture,
            .width = atlas_width,
            .height = atlas_height,
            .char_data = char_data,
            .font_size = font_size,
            .ascent = scaled_ascent,
            .descent = scaled_descent,
            .line_gap = scaled_line_gap,
        };
    }

    fn deinit(self: *FontAtlas) void {
        bgfx.destroyTexture(self.texture);
    }
};

/// Batch for collecting colored draw calls
const DrawBatch = struct {
    allocator: std.mem.Allocator,
    vertices: std.ArrayList(ColorVertex),
    indices: std.ArrayList(u16),

    fn init(allocator: std.mem.Allocator) DrawBatch {
        return .{
            .allocator = allocator,
            .vertices = .{},
            .indices = .{},
        };
    }

    fn deinit(self: *DrawBatch) void {
        self.vertices.deinit(self.allocator);
        self.indices.deinit(self.allocator);
    }

    fn clear(self: *DrawBatch) void {
        self.vertices.clearRetainingCapacity();
        self.indices.clearRetainingCapacity();
    }

    fn addQuad(self: *DrawBatch, x: f32, y: f32, w: f32, h: f32, color: Color) !void {
        const base_idx: u16 = @intCast(self.vertices.items.len);

        // Add vertices
        try self.vertices.append(self.allocator, ColorVertex.init(x, y, color));
        try self.vertices.append(self.allocator, ColorVertex.init(x + w, y, color));
        try self.vertices.append(self.allocator, ColorVertex.init(x + w, y + h, color));
        try self.vertices.append(self.allocator, ColorVertex.init(x, y + h, color));

        // Add indices (two triangles)
        try self.indices.append(self.allocator, base_idx + 0);
        try self.indices.append(self.allocator, base_idx + 1);
        try self.indices.append(self.allocator, base_idx + 2);

        try self.indices.append(self.allocator, base_idx + 0);
        try self.indices.append(self.allocator, base_idx + 2);
        try self.indices.append(self.allocator, base_idx + 3);
    }
};

/// Batch for collecting textured draw calls (fonts, images)
const TextureBatch = struct {
    allocator: std.mem.Allocator,
    vertices: std.ArrayList(TextureVertex),
    indices: std.ArrayList(u16),

    fn init(allocator: std.mem.Allocator) TextureBatch {
        return .{
            .allocator = allocator,
            .vertices = .{},
            .indices = .{},
        };
    }

    fn deinit(self: *TextureBatch) void {
        self.vertices.deinit(self.allocator);
        self.indices.deinit(self.allocator);
    }

    fn clear(self: *TextureBatch) void {
        self.vertices.clearRetainingCapacity();
        self.indices.clearRetainingCapacity();
    }

    fn addQuad(self: *TextureBatch, x: f32, y: f32, w: f32, h: f32, uv_x0: f32, uv_y0: f32, uv_x1: f32, uv_y1: f32, color: Color) !void {
        const base_idx: u16 = @intCast(self.vertices.items.len);

        // Add vertices with UVs
        try self.vertices.append(self.allocator, TextureVertex.init(x, y, uv_x0, uv_y0, color));
        try self.vertices.append(self.allocator, TextureVertex.init(x + w, y, uv_x1, uv_y0, color));
        try self.vertices.append(self.allocator, TextureVertex.init(x + w, y + h, uv_x1, uv_y1, color));
        try self.vertices.append(self.allocator, TextureVertex.init(x, y + h, uv_x0, uv_y1, color));

        // Add indices (two triangles)
        try self.indices.append(self.allocator, base_idx + 0);
        try self.indices.append(self.allocator, base_idx + 1);
        try self.indices.append(self.allocator, base_idx + 2);

        try self.indices.append(self.allocator, base_idx + 0);
        try self.indices.append(self.allocator, base_idx + 2);
        try self.indices.append(self.allocator, base_idx + 3);
    }
};

/// Proper 2D Renderer with batching
pub const Renderer2DProper = struct {
    allocator: std.mem.Allocator,
    window_width: u32,
    window_height: u32,

    // Shader programs
    shader_programs: shaders.ShaderPrograms,

    // Vertex layouts
    color_vertex_layout: bgfx.VertexLayout,
    texture_vertex_layout: bgfx.VertexLayout,

    // Draw batches
    color_batch: DrawBatch,
    texture_batch: TextureBatch,

    // Font atlas for text rendering
    font_atlas: FontAtlas,

    // View ID for UI rendering
    view_id: bgfx.ViewId,
    default_view_id: bgfx.ViewId,  // Store the default view
    overlay_view_id: bgfx.ViewId,   // Overlay view for dropdowns/modals

    // Scissor state - store the actual rect, not the cache handle
    scissor_rect: Rect,
    scissor_enabled: bool,

    pub fn init(allocator: std.mem.Allocator, window_width: u32, window_height: u32) !Renderer2DProper {
        // Initialize shader programs
        const shader_programs = try shaders.ShaderPrograms.init();

        // Create vertex layout for colored vertices
        var color_vertex_layout: bgfx.VertexLayout = undefined;
        _ = color_vertex_layout.begin(bgfx.RendererType.Noop);
        _ = color_vertex_layout.add(
            bgfx.Attrib.Position,
            2,
            bgfx.AttribType.Float,
            false,
            false,
        );
        _ = color_vertex_layout.add(
            bgfx.Attrib.Color0,
            4,
            bgfx.AttribType.Uint8,
            true,
            false,
        );
        color_vertex_layout.end();

        // Create vertex layout for textured vertices
        var texture_vertex_layout: bgfx.VertexLayout = undefined;
        _ = texture_vertex_layout.begin(bgfx.RendererType.Noop);
        _ = texture_vertex_layout.add(
            bgfx.Attrib.Position,
            2,
            bgfx.AttribType.Float,
            false,
            false,
        );
        _ = texture_vertex_layout.add(
            bgfx.Attrib.TexCoord0,
            2,
            bgfx.AttribType.Float,
            false,
            false,
        );
        _ = texture_vertex_layout.add(
            bgfx.Attrib.Color0,
            4,
            bgfx.AttribType.Uint8,
            true,
            false,
        );
        texture_vertex_layout.end();

        // Load font atlas
        const font_data = @embedFile("../assets/fonts/Roboto-Regular.ttf");
        const font_atlas = try FontAtlas.init(allocator, font_data, 24.0);

        return .{
            .allocator = allocator,
            .window_width = window_width,
            .window_height = window_height,
            .shader_programs = shader_programs,
            .color_vertex_layout = color_vertex_layout,
            .texture_vertex_layout = texture_vertex_layout,
            .color_batch = DrawBatch.init(allocator),
            .texture_batch = TextureBatch.init(allocator),
            .font_atlas = font_atlas,
            .view_id = 0,
            .default_view_id = 0,
            .overlay_view_id = 1,
            .scissor_rect = Rect{ .x = 0, .y = 0, .width = @floatFromInt(window_width), .height = @floatFromInt(window_height) },
            .scissor_enabled = false,
        };
    }

    pub fn deinit(self: *Renderer2DProper) void {
        self.shader_programs.deinit();
        self.color_batch.deinit();
        self.texture_batch.deinit();
        var atlas = self.font_atlas;
        atlas.deinit();
    }

    pub fn updateWindowSize(self: *Renderer2DProper, width: u32, height: u32) void {
        self.window_width = width;
        self.window_height = height;
    }

    /// Begin frame - clear batches
    pub fn beginFrame(self: *Renderer2DProper) void {
        self.color_batch.clear();
        self.texture_batch.clear();
        // Reset scissor to full window at frame start
        self.scissor_rect = Rect{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(self.window_width),
            .height = @floatFromInt(self.window_height),
        };
        self.scissor_enabled = true;
    }

    /// End frame - flush batches
    pub fn endFrame(self: *Renderer2DProper) void {
        self.flushColorBatch();
        self.flushTextureBatch();
    }

    /// Flush colored draw batch to GPU
    fn flushColorBatch(self: *Renderer2DProper) void {
        if (self.color_batch.vertices.items.len == 0) return;

        // Allocate transient buffers
        var tvb: bgfx.TransientVertexBuffer = undefined;
        var tib: bgfx.TransientIndexBuffer = undefined;

        const num_vertices: u32 = @intCast(self.color_batch.vertices.items.len);
        const num_indices: u32 = @intCast(self.color_batch.indices.items.len);

        if (!bgfx.allocTransientBuffers(
            &tvb,
            &self.color_vertex_layout,
            num_vertices,
            &tib,
            num_indices,
            false,
        )) {
            return; // Not enough space
        }

        // Copy vertex data
        const vertex_size = @sizeOf(ColorVertex);
        const vertices_bytes = self.color_batch.vertices.items.len * vertex_size;
        @memcpy(
            @as([*]u8, @ptrCast(tvb.data))[0..vertices_bytes],
            std.mem.sliceAsBytes(self.color_batch.vertices.items),
        );

        // Copy index data
        const indices_bytes = self.color_batch.indices.items.len * @sizeOf(u16);
        @memcpy(
            @as([*]u8, @ptrCast(tib.data))[0..indices_bytes],
            std.mem.sliceAsBytes(self.color_batch.indices.items),
        );

        // Set up orthographic projection
        const proj = orthoProjection(
            0,
            @floatFromInt(self.window_width),
            @floatFromInt(self.window_height),
            0,
            -1,
            1,
        );
        bgfx.setViewTransform(self.view_id, null, &proj);

        // Set vertex and index buffers
        bgfx.setTransientVertexBuffer(0, &tvb, 0, num_vertices);
        bgfx.setTransientIndexBuffer(&tib, 0, num_indices);

        // Apply scissor if enabled - call setScissor fresh each time
        if (self.scissor_enabled) {
            _ = bgfx.setScissor(
                @intFromFloat(self.scissor_rect.x),
                @intFromFloat(self.scissor_rect.y),
                @intFromFloat(self.scissor_rect.width),
                @intFromFloat(self.scissor_rect.height)
            );
        }

        // Set render state (alpha blending: src_alpha, inv_src_alpha)
        bgfx.setState(
            bgfx.StateFlags_WriteRgb |
                bgfx.StateFlags_WriteA |
                bgfx.StateFlags_BlendSrcAlpha |
                ((bgfx.StateFlags_BlendInvSrcAlpha) << 4),
            0,
        );

        // Submit draw call with color shader program
        _ = bgfx.submit(self.view_id, self.shader_programs.color_program, 0, bgfx.DiscardFlags_All);

        // Clear the batch after submitting
        self.color_batch.clear();
    }

    /// Flush textured draw batch to GPU
    fn flushTextureBatch(self: *Renderer2DProper) void {
        if (self.texture_batch.vertices.items.len == 0) return;

        // Allocate transient buffers
        var tvb: bgfx.TransientVertexBuffer = undefined;
        var tib: bgfx.TransientIndexBuffer = undefined;

        const num_vertices: u32 = @intCast(self.texture_batch.vertices.items.len);
        const num_indices: u32 = @intCast(self.texture_batch.indices.items.len);

        if (!bgfx.allocTransientBuffers(
            &tvb,
            &self.texture_vertex_layout,
            num_vertices,
            &tib,
            num_indices,
            false,
        )) {
            return; // Not enough space
        }

        // Copy vertex data
        const vertex_size = @sizeOf(TextureVertex);
        const vertices_bytes = self.texture_batch.vertices.items.len * vertex_size;
        @memcpy(
            @as([*]u8, @ptrCast(tvb.data))[0..vertices_bytes],
            std.mem.sliceAsBytes(self.texture_batch.vertices.items),
        );

        // Copy index data
        const indices_bytes = self.texture_batch.indices.items.len * @sizeOf(u16);
        @memcpy(
            @as([*]u8, @ptrCast(tib.data))[0..indices_bytes],
            std.mem.sliceAsBytes(self.texture_batch.indices.items),
        );

        // Set up orthographic projection
        const proj = orthoProjection(
            0,
            @floatFromInt(self.window_width),
            @floatFromInt(self.window_height),
            0,
            -1,
            1,
        );
        bgfx.setViewTransform(self.view_id, null, &proj);

        // Set vertex and index buffers
        bgfx.setTransientVertexBuffer(0, &tvb, 0, num_vertices);
        bgfx.setTransientIndexBuffer(&tib, 0, num_indices);

        // Set texture
        bgfx.setTexture(0, self.shader_programs.texture_sampler, self.font_atlas.texture, 0xffffffff);

        // Apply scissor if enabled - call setScissor fresh each time
        if (self.scissor_enabled) {
            _ = bgfx.setScissor(
                @intFromFloat(self.scissor_rect.x),
                @intFromFloat(self.scissor_rect.y),
                @intFromFloat(self.scissor_rect.width),
                @intFromFloat(self.scissor_rect.height)
            );
        }

        // Set render state (alpha blending: src_alpha, inv_src_alpha)
        bgfx.setState(
            bgfx.StateFlags_WriteRgb |
                bgfx.StateFlags_WriteA |
                bgfx.StateFlags_BlendSrcAlpha |
                ((bgfx.StateFlags_BlendInvSrcAlpha) << 4),
            0,
        );

        // Submit draw call with texture shader program
        _ = bgfx.submit(self.view_id, self.shader_programs.texture_program, 0, bgfx.DiscardFlags_All);

        // Clear the batch after submitting
        self.texture_batch.clear();
    }

    /// Draw a filled rectangle
    pub fn drawRect(self: *Renderer2DProper, rect: Rect, color: Color) void {
        self.color_batch.addQuad(rect.x, rect.y, rect.width, rect.height, color) catch |err| {
            log.renderer.warn("Failed to add rectangle to batch, skipping: {}", .{err});
            return;
        };
    }

    /// Draw rectangle outline
    pub fn drawRectOutline(self: *Renderer2DProper, rect: Rect, color: Color, thickness: f32) void {
        // Top
        self.drawRect(.{ .x = rect.x, .y = rect.y, .width = rect.width, .height = thickness }, color);
        // Bottom
        self.drawRect(.{ .x = rect.x, .y = rect.y + rect.height - thickness, .width = rect.width, .height = thickness }, color);
        // Left
        self.drawRect(.{ .x = rect.x, .y = rect.y + thickness, .width = thickness, .height = rect.height - (thickness * 2) }, color);
        // Right
        self.drawRect(.{ .x = rect.x + rect.width - thickness, .y = rect.y + thickness, .width = thickness, .height = rect.height - (thickness * 2) }, color);
    }

    /// Draw text using font atlas
    pub fn drawText(self: *Renderer2DProper, text: []const u8, pos: Vec2, size: f32, color: Color) void {
        const scale = size / self.font_atlas.font_size;
        var cursor_x = pos.x;
        const cursor_y = pos.y;

        for (text) |char| {
            if (char < 32 or char >= 128) continue; // Skip non-ASCII

            const char_index: usize = char - 32;
            const char_info = &self.font_atlas.char_data[char_index];

            // Calculate quad position and size
            const x0 = cursor_x + char_info.xoff * scale;
            const y0 = cursor_y + char_info.yoff * scale;
            const x1 = x0 + (@as(f32, @floatFromInt(char_info.x1)) - @as(f32, @floatFromInt(char_info.x0))) * scale;
            const y1 = y0 + (@as(f32, @floatFromInt(char_info.y1)) - @as(f32, @floatFromInt(char_info.y0))) * scale;

            // Calculate UV coordinates (normalized 0-1)
            // TEXTURE ATLAS SAFEGUARDS:
            // 1. Half-pixel offset: Sample from pixel centers (+0.5/-0.5) to prevent
            //    bilinear filtering from missing edge pixels
            // 2. Clamp sampling: Texture uses UClamp/VClamp flags to prevent wraparound
            // 3. Linear filtering: Uses default bilinear filtering for smooth antialiased text
            const atlas_w = @as(f32, @floatFromInt(self.font_atlas.width));
            const atlas_h = @as(f32, @floatFromInt(self.font_atlas.height));

            const uv_x0 = (@as(f32, @floatFromInt(char_info.x0)) + 0.5) / atlas_w;
            const uv_y0 = (@as(f32, @floatFromInt(char_info.y0)) + 0.5) / atlas_h;
            const uv_x1 = (@as(f32, @floatFromInt(char_info.x1)) - 0.5) / atlas_w;
            const uv_y1 = (@as(f32, @floatFromInt(char_info.y1)) - 0.5) / atlas_h;

            // Add textured quad to batch
            const w = x1 - x0;
            const h = y1 - y0;
            self.texture_batch.addQuad(x0, y0, w, h, uv_x0, uv_y0, uv_x1, uv_y1, color) catch |err| {
                log.renderer.warn("Failed to add text glyph to batch, remaining text will not render: {}", .{err});
                return;
            };

            // Advance cursor
            cursor_x += char_info.xadvance * scale;
        }
    }

    /// Measure text size
    pub fn measureText(self: *Renderer2DProper, text: []const u8, font_size: f32) Vec2 {
        const scale = font_size / self.font_atlas.font_size;
        var width: f32 = 0;

        for (text) |char| {
            if (char < 32 or char >= 128) continue; // Skip non-ASCII

            const char_index: usize = char - 32;
            const char_info = &self.font_atlas.char_data[char_index];

            // Accumulate width
            width += char_info.xadvance * scale;
        }

        // Return actual measured dimensions
        // Height is ascent - descent (since descent is negative)
        const scale_metrics = font_size / self.font_atlas.font_size;
        const total_height = self.font_atlas.ascent - self.font_atlas.descent;
        return Vec2.init(width, total_height * scale_metrics);
    }

    /// Get baseline offset for vertically centering text
    /// When you want to center text in a box, use: baseline_y = box_center_y + getBaselineOffset(font_size)
    pub fn getBaselineOffset(self: *Renderer2DProper, font_size: f32) f32 {
        const scale = font_size / self.font_atlas.font_size;
        // For vertical centering, the baseline should be offset by half the cap height
        // Cap height is approximately ascent * 0.7 for most fonts, but we'll use ascent/2 as a simple approximation
        // A better approach: offset from center by (ascent - descent) / 2 - ascent
        const total_height = self.font_atlas.ascent - self.font_atlas.descent;
        return (total_height * 0.5 - self.font_atlas.ascent) * scale;
    }

    /// Begin scissor
    pub fn beginScissor(self: *Renderer2DProper, rect: Rect) void {
        // Flush current batches before changing scissor
        self.flushColorBatch();
        self.flushTextureBatch();

        // Store the scissor rectangle
        self.scissor_rect = rect;
        self.scissor_enabled = true;
    }

    /// End scissor - resets to full window bounds
    pub fn endScissor(self: *Renderer2DProper) void {
        // CRITICAL: Do NOT flush here - just change the scissor state
        // The caller should flush before calling endScissor if needed
        // This allows the next draw operations to use the full window scissor

        // Reset scissor to full window bounds
        self.scissor_rect = Rect{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(self.window_width),
            .height = @floatFromInt(self.window_height),
        };

        // Keep scissor enabled but with full window bounds
        self.scissor_enabled = true;
    }

    /// Flush all pending draw batches
    pub fn flushBatches(self: *Renderer2DProper) void {
        self.flushColorBatch();
        self.flushTextureBatch();
    }

    /// Switch to overlay view (for dropdowns, tooltips, modals)
    pub fn pushOverlayView(self: *Renderer2DProper) void {
        self.view_id = self.overlay_view_id;
    }

    /// Switch back to default view
    pub fn popOverlayView(self: *Renderer2DProper) void {
        self.view_id = self.default_view_id;
    }

    pub fn isNull(self: *Renderer2DProper) bool {
        _ = self;
        return false;
    }
};

/// Create orthographic projection matrix
fn orthoProjection(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) [16]f32 {
    var result: [16]f32 = [_]f32{0} ** 16;

    result[0] = 2.0 / (right - left);
    result[5] = 2.0 / (top - bottom);
    result[10] = -2.0 / (far - near);
    result[12] = -(right + left) / (right - left);
    result[13] = -(top + bottom) / (top - bottom);
    result[14] = -(far + near) / (far - near);
    result[15] = 1.0;

    return result;
}

/// Convert Color to bgfx attribute (fallback for debug text)
fn colorToBgfxAttr(color: Color) u8 {
    const high = color.r > 128 or color.g > 128 or color.b > 128;
    if (color.r > color.g and color.r > color.b) {
        return if (high) 0x0C else 0x04;
    } else if (color.g > color.r and color.g > color.b) {
        return if (high) 0x0A else 0x02;
    } else if (color.b > color.r and color.b > color.g) {
        return if (high) 0x09 else 0x01;
    } else if (color.r > 200 and color.g > 200 and color.b > 200) {
        return 0x0F;
    } else if (color.r < 50 and color.g < 50 and color.b < 50) {
        return 0x00;
    } else {
        return 0x07;
    }
}

// ============================================================================
// Tests
// ============================================================================

test "renderer - colorToABGR conversion" {
    const red = Color{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const green = Color{ .r = 0, .g = 255, .b = 0, .a = 255 };
    const blue = Color{ .r = 0, .g = 0, .b = 255, .a = 255 };
    const white = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    const transparent = Color{ .r = 128, .g = 128, .b = 128, .a = 0 };

    // Test ABGR format (alpha in high byte, red in low byte)
    try std.testing.expectEqual(@as(u32, 0xFF0000FF), colorToABGR(red));
    try std.testing.expectEqual(@as(u32, 0xFF00FF00), colorToABGR(green));
    try std.testing.expectEqual(@as(u32, 0xFFFF0000), colorToABGR(blue));
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), colorToABGR(white));
    try std.testing.expectEqual(@as(u32, 0x00808080), colorToABGR(transparent));
}

test "renderer - ColorVertex initialization" {
    const color = Color{ .r = 100, .g = 150, .b = 200, .a = 255 };
    const vertex = ColorVertex.init(10.5, 20.75, color);

    try std.testing.expectEqual(@as(f32, 10.5), vertex.x);
    try std.testing.expectEqual(@as(f32, 20.75), vertex.y);
    try std.testing.expectEqual(colorToABGR(color), vertex.abgr);
}

test "renderer - TextureVertex initialization" {
    const color = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    const vertex = TextureVertex.init(5.0, 10.0, 0.25, 0.75, color);

    try std.testing.expectEqual(@as(f32, 5.0), vertex.x);
    try std.testing.expectEqual(@as(f32, 10.0), vertex.y);
    try std.testing.expectEqual(@as(f32, 0.25), vertex.u);
    try std.testing.expectEqual(@as(f32, 0.75), vertex.v);
    try std.testing.expectEqual(colorToABGR(color), vertex.abgr);
}

test "renderer - DrawBatch initialization and cleanup" {
    var batch = DrawBatch.init(std.testing.allocator);
    defer batch.deinit();

    try std.testing.expectEqual(@as(usize, 0), batch.vertices.items.len);
    try std.testing.expectEqual(@as(usize, 0), batch.indices.items.len);
}

test "renderer - DrawBatch addQuad" {
    var batch = DrawBatch.init(std.testing.allocator);
    defer batch.deinit();

    const color = Color{ .r = 255, .g = 0, .b = 0, .a = 255 };
    try batch.addQuad(10.0, 20.0, 100.0, 50.0, color);

    // Should add 4 vertices
    try std.testing.expectEqual(@as(usize, 4), batch.vertices.items.len);
    // Should add 6 indices (2 triangles)
    try std.testing.expectEqual(@as(usize, 6), batch.indices.items.len);

    // Verify vertex positions
    try std.testing.expectEqual(@as(f32, 10.0), batch.vertices.items[0].x);
    try std.testing.expectEqual(@as(f32, 20.0), batch.vertices.items[0].y);

    try std.testing.expectEqual(@as(f32, 110.0), batch.vertices.items[1].x);
    try std.testing.expectEqual(@as(f32, 20.0), batch.vertices.items[1].y);

    try std.testing.expectEqual(@as(f32, 110.0), batch.vertices.items[2].x);
    try std.testing.expectEqual(@as(f32, 70.0), batch.vertices.items[2].y);

    try std.testing.expectEqual(@as(f32, 10.0), batch.vertices.items[3].x);
    try std.testing.expectEqual(@as(f32, 70.0), batch.vertices.items[3].y);

    // Verify indices form two triangles
    try std.testing.expectEqual(@as(u16, 0), batch.indices.items[0]);
    try std.testing.expectEqual(@as(u16, 1), batch.indices.items[1]);
    try std.testing.expectEqual(@as(u16, 2), batch.indices.items[2]);

    try std.testing.expectEqual(@as(u16, 0), batch.indices.items[3]);
    try std.testing.expectEqual(@as(u16, 2), batch.indices.items[4]);
    try std.testing.expectEqual(@as(u16, 3), batch.indices.items[5]);
}

test "renderer - DrawBatch multiple quads" {
    var batch = DrawBatch.init(std.testing.allocator);
    defer batch.deinit();

    const red = Color{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const green = Color{ .r = 0, .g = 255, .b = 0, .a = 255 };

    try batch.addQuad(0.0, 0.0, 10.0, 10.0, red);
    try batch.addQuad(20.0, 20.0, 10.0, 10.0, green);

    // Should have 8 vertices (4 per quad)
    try std.testing.expectEqual(@as(usize, 8), batch.vertices.items.len);
    // Should have 12 indices (6 per quad)
    try std.testing.expectEqual(@as(usize, 12), batch.indices.items.len);

    // Second quad's indices should reference vertices 4-7
    try std.testing.expectEqual(@as(u16, 4), batch.indices.items[6]);
    try std.testing.expectEqual(@as(u16, 5), batch.indices.items[7]);
    try std.testing.expectEqual(@as(u16, 6), batch.indices.items[8]);
}

test "renderer - DrawBatch clear" {
    var batch = DrawBatch.init(std.testing.allocator);
    defer batch.deinit();

    const color = Color{ .r = 255, .g = 0, .b = 0, .a = 255 };
    try batch.addQuad(0.0, 0.0, 10.0, 10.0, color);

    try std.testing.expectEqual(@as(usize, 4), batch.vertices.items.len);
    try std.testing.expectEqual(@as(usize, 6), batch.indices.items.len);

    batch.clear();

    try std.testing.expectEqual(@as(usize, 0), batch.vertices.items.len);
    try std.testing.expectEqual(@as(usize, 0), batch.indices.items.len);
}

test "renderer - TextureBatch initialization and cleanup" {
    var batch = TextureBatch.init(std.testing.allocator);
    defer batch.deinit();

    try std.testing.expectEqual(@as(usize, 0), batch.vertices.items.len);
    try std.testing.expectEqual(@as(usize, 0), batch.indices.items.len);
}

test "renderer - TextureBatch addQuad" {
    var batch = TextureBatch.init(std.testing.allocator);
    defer batch.deinit();

    const color = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    try batch.addQuad(10.0, 20.0, 100.0, 50.0, 0.0, 0.0, 1.0, 1.0, color);

    // Should add 4 vertices
    try std.testing.expectEqual(@as(usize, 4), batch.vertices.items.len);
    // Should add 6 indices (2 triangles)
    try std.testing.expectEqual(@as(usize, 6), batch.indices.items.len);

    // Verify UV coordinates
    try std.testing.expectEqual(@as(f32, 0.0), batch.vertices.items[0].u);
    try std.testing.expectEqual(@as(f32, 0.0), batch.vertices.items[0].v);

    try std.testing.expectEqual(@as(f32, 1.0), batch.vertices.items[1].u);
    try std.testing.expectEqual(@as(f32, 0.0), batch.vertices.items[1].v);

    try std.testing.expectEqual(@as(f32, 1.0), batch.vertices.items[2].u);
    try std.testing.expectEqual(@as(f32, 1.0), batch.vertices.items[2].v);

    try std.testing.expectEqual(@as(f32, 0.0), batch.vertices.items[3].u);
    try std.testing.expectEqual(@as(f32, 1.0), batch.vertices.items[3].v);
}

test "renderer - TextureBatch clear" {
    var batch = TextureBatch.init(std.testing.allocator);
    defer batch.deinit();

    const color = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    try batch.addQuad(0.0, 0.0, 10.0, 10.0, 0.0, 0.0, 1.0, 1.0, color);

    batch.clear();

    try std.testing.expectEqual(@as(usize, 0), batch.vertices.items.len);
    try std.testing.expectEqual(@as(usize, 0), batch.indices.items.len);
}

test "renderer - orthoProjection matrix" {
    const proj = orthoProjection(0, 1920, 1080, 0, -1, 1);

    // Test that it's a valid 4x4 matrix
    try std.testing.expectEqual(@as(usize, 16), proj.len);

    // Test key values for orthographic projection
    // Scale X: 2 / (right - left) = 2 / 1920
    try std.testing.expectApproxEqRel(@as(f32, 2.0 / 1920.0), proj[0], 0.0001);

    // Scale Y: 2 / (top - bottom) = 2 / -1080
    try std.testing.expectApproxEqRel(@as(f32, 2.0 / -1080.0), proj[5], 0.0001);

    // Scale Z: -2 / (far - near) = -2 / 2
    try std.testing.expectApproxEqRel(@as(f32, -1.0), proj[10], 0.0001);

    // Translation X: -(right + left) / (right - left) = -1920 / 1920 = -1
    try std.testing.expectApproxEqRel(@as(f32, -1.0), proj[12], 0.0001);

    // Translation Y: -(top + bottom) / (top - bottom) = -1080 / -1080 = 1
    try std.testing.expectApproxEqRel(@as(f32, 1.0), proj[13], 0.0001);

    // W component should be 1
    try std.testing.expectEqual(@as(f32, 1.0), proj[15]);
}

test "renderer - colorToBgfxAttr" {
    const red = Color{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const green = Color{ .r = 0, .g = 255, .b = 0, .a = 255 };
    const blue = Color{ .r = 0, .g = 0, .b = 255, .a = 255 };
    const white = Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
    const black = Color{ .r = 0, .g = 0, .b = 0, .a = 255 };

    // Test color to ANSI attribute conversion
    try std.testing.expectEqual(@as(u8, 0x0C), colorToBgfxAttr(red));    // Bright red
    try std.testing.expectEqual(@as(u8, 0x0A), colorToBgfxAttr(green));  // Bright green
    try std.testing.expectEqual(@as(u8, 0x09), colorToBgfxAttr(blue));   // Bright blue
    try std.testing.expectEqual(@as(u8, 0x0F), colorToBgfxAttr(white));  // Bright white
    try std.testing.expectEqual(@as(u8, 0x00), colorToBgfxAttr(black));  // Black
}

test "font atlas - initialization" {
    // Note: This test requires bgfx to be initialized, so we test the low-level
    // stb_truetype functionality instead of full FontAtlas.init()
    const font_data = @embedFile("../assets/fonts/Roboto-Regular.ttf");

    var font_info: stb.FontInfo = undefined;
    const result = stb.initFont(&font_info, font_data.ptr, 0);

    try std.testing.expect(result != 0); // Should succeed

    // Verify we can get font metrics
    var ascent: c_int = undefined;
    var descent: c_int = undefined;
    var line_gap: c_int = undefined;
    stb.getFontVMetrics(&font_info, &ascent, &descent, &line_gap);

    // Roboto should have reasonable metrics
    try std.testing.expect(ascent > 0);
    try std.testing.expect(descent < 0); // Descent is typically negative
    try std.testing.expect(line_gap >= 0);
}

test "font atlas - scale calculation" {
    const font_data = @embedFile("../assets/fonts/Roboto-Regular.ttf");

    var font_info: stb.FontInfo = undefined;
    _ = stb.initFont(&font_info, font_data.ptr, 0);

    // Test scale for various pixel heights
    const scale_24 = stb.scaleForPixelHeight(&font_info, 24.0);
    const scale_48 = stb.scaleForPixelHeight(&font_info, 48.0);

    // Scale should be positive
    try std.testing.expect(scale_24 > 0);
    try std.testing.expect(scale_48 > 0);

    // 48px should have roughly 2x the scale of 24px
    const ratio = scale_48 / scale_24;
    try std.testing.expectApproxEqRel(@as(f32, 2.0), ratio, 0.01);
}

test "font atlas - glyph metrics" {
    const font_data = @embedFile("../assets/fonts/Roboto-Regular.ttf");

    var font_info: stb.FontInfo = undefined;
    _ = stb.initFont(&font_info, font_data.ptr, 0);

    // Test getting metrics for 'A' character
    const codepoint: c_int = 'A';
    var advance: c_int = undefined;
    var left_bearing: c_int = undefined;
    stb.getCodepointHMetrics(&font_info, codepoint, &advance, &left_bearing);

    // 'A' should have positive advance width
    try std.testing.expect(advance > 0);
}

test "font atlas - character bounding box" {
    const font_data = @embedFile("../assets/fonts/Roboto-Regular.ttf");

    var font_info: stb.FontInfo = undefined;
    _ = stb.initFont(&font_info, font_data.ptr, 0);

    // Test bounding box for 'M' (typically a wide character)
    var x0: c_int = undefined;
    var y0: c_int = undefined;
    var x1: c_int = undefined;
    var y1: c_int = undefined;
    _ = stb.getCodepointBox(&font_info, 'M', &x0, &y0, &x1, &y1);

    // Bounding box should have width and height
    const width = x1 - x0;
    const height = y1 - y0;

    try std.testing.expect(width > 0);
    try std.testing.expect(height > 0);

    // 'M' should be wider than it is tall (typically)
    try std.testing.expect(width > height / 2);
}

test "font atlas - ASCII coverage" {
    const font_data = @embedFile("../assets/fonts/Roboto-Regular.ttf");

    var font_info: stb.FontInfo = undefined;
    _ = stb.initFont(&font_info, font_data.ptr, 0);

    // Test that we can get glyph indices for ASCII printable characters (32-126)
    var char: u8 = 32;
    while (char < 127) : (char += 1) {
        const glyph_index = stb.findGlyphIndex(&font_info, char);
        // Roboto should have all ASCII characters
        try std.testing.expect(glyph_index > 0);
    }
}

test "font atlas - kerning" {
    const font_data = @embedFile("../assets/fonts/Roboto-Regular.ttf");

    var font_info: stb.FontInfo = undefined;
    _ = stb.initFont(&font_info, font_data.ptr, 0);

    // Test kerning between common pairs
    // Note: Not all fonts have kerning data, so we just test that the function works
    const kern_AV = stb.getCodepointKernAdvance(&font_info, 'A', 'V');
    const kern_AA = stb.getCodepointKernAdvance(&font_info, 'A', 'A');

    // These are valid results (can be 0 if no kerning)
    _ = kern_AV;
    _ = kern_AA;
    // Just verify the calls don't crash
}

test "font atlas - metrics consistency" {
    const font_data = @embedFile("../assets/fonts/Roboto-Regular.ttf");

    var font_info: stb.FontInfo = undefined;
    _ = stb.initFont(&font_info, font_data.ptr, 0);

    // Get vertical metrics
    var ascent: c_int = undefined;
    var descent: c_int = undefined;
    var line_gap: c_int = undefined;
    stb.getFontVMetrics(&font_info, &ascent, &descent, &line_gap);

    // Total line height should be ascent - descent + line_gap
    const total_height = ascent - descent + line_gap;

    // Should be positive and reasonable
    try std.testing.expect(total_height > 0);
    try std.testing.expect(total_height < 10000); // Sanity check
}

test "font atlas - baked char data structure" {
    // Verify the stbtt_bakedchar structure is properly sized
    const char_data_size = @sizeOf(stb.c.stbtt_bakedchar);

    // Should be non-zero and reasonable
    try std.testing.expect(char_data_size > 0);
    try std.testing.expect(char_data_size < 1000); // Sanity check

    // Create an array of baked chars (as used in FontAtlas)
    var char_data: [96]stb.c.stbtt_bakedchar = undefined;
    @memset(std.mem.asBytes(&char_data), 0);

    // Array should have correct size
    try std.testing.expectEqual(@as(usize, 96), char_data.len);
}
