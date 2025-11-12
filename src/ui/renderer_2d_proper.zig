const std = @import("std");
const root = @import("../root.zig");
const bgfx = root.bgfx;
const stb = root.stb_truetype;
const types = @import("types.zig");

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
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator, font_data: []const u8, font_size: f32) !FontAtlas {
        const atlas_width: u32 = 512;
        const atlas_height: u32 = 512;

        // Allocate bitmap for font atlas
        const bitmap = try allocator.alloc(u8, atlas_width * atlas_height);
        defer allocator.free(bitmap);
        @memset(bitmap, 0);

        var char_data: [96]stb.c.stbtt_bakedchar = undefined;

        // Bake font into bitmap
        const result = stb.c.stbtt_BakeFontBitmap(
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

        if (result <= 0) {
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

        // Create bgfx texture
        const texture_mem = bgfx.copy(rgba_bitmap.ptr, @intCast(rgba_bitmap.len));
        const texture = bgfx.createTexture2D(
            @intCast(atlas_width),
            @intCast(atlas_height),
            false,
            1,
            bgfx.TextureFormat.RGBA8,
            0,
            texture_mem,
        );

        return .{
            .texture = texture,
            .width = atlas_width,
            .height = atlas_height,
            .char_data = char_data,
            .allocator = allocator,
        };
    }

    fn deinit(self: *FontAtlas) void {
        bgfx.destroy(self.texture);
    }
};

/// Batch for collecting draw calls
const DrawBatch = struct {
    vertices: std.ArrayList(ColorVertex),
    indices: std.ArrayList(u16),

    fn init(allocator: std.mem.Allocator) DrawBatch {
        return .{
            .vertices = std.ArrayList(ColorVertex).init(allocator),
            .indices = std.ArrayList(u16).init(allocator),
        };
    }

    fn deinit(self: *DrawBatch) void {
        self.vertices.deinit();
        self.indices.deinit();
    }

    fn clear(self: *DrawBatch) void {
        self.vertices.clearRetainingCapacity();
        self.indices.clearRetainingCapacity();
    }

    fn addQuad(self: *DrawBatch, x: f32, y: f32, w: f32, h: f32, color: Color) !void {
        const base_idx: u16 = @intCast(self.vertices.items.len);

        // Add vertices
        try self.vertices.append(ColorVertex.init(x, y, color));
        try self.vertices.append(ColorVertex.init(x + w, y, color));
        try self.vertices.append(ColorVertex.init(x + w, y + h, color));
        try self.vertices.append(ColorVertex.init(x, y + h, color));

        // Add indices (two triangles)
        try self.indices.append(base_idx + 0);
        try self.indices.append(base_idx + 1);
        try self.indices.append(base_idx + 2);

        try self.indices.append(base_idx + 0);
        try self.indices.append(base_idx + 2);
        try self.indices.append(base_idx + 3);
    }
};

/// Proper 2D Renderer with batching
pub const Renderer2DProper = struct {
    allocator: std.mem.Allocator,
    window_width: u32,
    window_height: u32,

    // Vertex layout
    vertex_layout: bgfx.VertexLayout,

    // Draw batch
    batch: DrawBatch,

    // Font atlas (TODO: load actual font)
    font_atlas: ?FontAtlas,

    // View ID for UI rendering
    view_id: bgfx.ViewId,

    pub fn init(allocator: std.mem.Allocator, window_width: u32, window_height: u32) !Renderer2DProper {
        // Create vertex layout for colored vertices
        var vertex_layout: bgfx.VertexLayout = undefined;
        bgfx.vertexLayoutBegin(&vertex_layout, bgfx.RendererType.Noop);
        _ = bgfx.vertexLayoutAdd(
            &vertex_layout,
            bgfx.Attrib.Position,
            2,
            bgfx.AttribType.Float,
            false,
            false,
        );
        _ = bgfx.vertexLayoutAdd(
            &vertex_layout,
            bgfx.Attrib.Color0,
            4,
            bgfx.AttribType.Uint8,
            true,
            false,
        );
        bgfx.vertexLayoutEnd(&vertex_layout);

        return .{
            .allocator = allocator,
            .window_width = window_width,
            .window_height = window_height,
            .vertex_layout = vertex_layout,
            .batch = DrawBatch.init(allocator),
            .font_atlas = null,
            .view_id = 0,
        };
    }

    pub fn deinit(self: *Renderer2DProper) void {
        self.batch.deinit();
        if (self.font_atlas) |*atlas| {
            atlas.deinit();
        }
    }

    pub fn updateWindowSize(self: *Renderer2DProper, width: u32, height: u32) void {
        self.window_width = width;
        self.window_height = height;
    }

    /// Begin frame - clear batch
    pub fn beginFrame(self: *Renderer2DProper) void {
        self.batch.clear();
    }

    /// End frame - flush batch
    pub fn endFrame(self: *Renderer2DProper) void {
        self.flush();
    }

    /// Flush draw batch to GPU
    fn flush(self: *Renderer2DProper) void {
        if (self.batch.vertices.items.len == 0) return;

        // Allocate transient buffers
        var tvb: bgfx.TransientVertexBuffer = undefined;
        var tib: bgfx.TransientIndexBuffer = undefined;

        const num_vertices: u32 = @intCast(self.batch.vertices.items.len);
        const num_indices: u32 = @intCast(self.batch.indices.items.len);

        if (!bgfx.allocTransientBuffers(
            &tvb,
            &self.vertex_layout,
            num_vertices,
            &tib,
            num_indices,
            false,
        )) {
            return; // Not enough space
        }

        // Copy vertex data
        const vertex_size = @sizeOf(ColorVertex);
        const vertices_bytes = self.batch.vertices.items.len * vertex_size;
        @memcpy(
            @as([*]u8, @ptrCast(tvb.data))[0..vertices_bytes],
            std.mem.sliceAsBytes(self.batch.vertices.items),
        );

        // Copy index data
        const indices_bytes = self.batch.indices.items.len * @sizeOf(u16);
        @memcpy(
            @as([*]u8, @ptrCast(tib.data))[0..indices_bytes],
            std.mem.sliceAsBytes(self.batch.indices.items),
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
        bgfx.setVertexBuffer(0, &tvb, 0, num_vertices);
        bgfx.setIndexBuffer(&tib, 0, num_indices);

        // Set render state (alpha blending)
        bgfx.setState(
            bgfx.StateFlags_WriteRgb |
                bgfx.StateFlags_WriteA |
                bgfx.StateFlags_BlendAlpha,
            0,
        );

        // Submit draw call
        _ = bgfx.submit(self.view_id, bgfx.ProgramHandle_Invalid, 0, false);
    }

    /// Draw a filled rectangle
    pub fn drawRect(self: *Renderer2DProper, rect: Rect, color: Color) void {
        self.batch.addQuad(rect.x, rect.y, rect.width, rect.height, color) catch return;
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

    /// Draw text (simplified - falls back to debug text for now)
    pub fn drawText(self: *Renderer2DProper, text: []const u8, pos: Vec2, size: f32, color: Color) void {
        _ = size;
        _ = self;
        // TODO: Implement with font atlas
        // For now, use debug text
        const char_x: u16 = @intFromFloat(pos.x / 8.0);
        const char_y: u16 = @intFromFloat(pos.y / 16.0);
        const attr: u8 = colorToBgfxAttr(color);

        var text_buffer: std.ArrayList(u8) = .{};
        defer text_buffer.deinit(self.allocator);

        for (text) |char| {
            text_buffer.append(self.allocator, char) catch return;
            text_buffer.append(self.allocator, attr) catch return;
        }

        if (text_buffer.items.len > 0) {
            bgfx.dbgTextImage(char_x, char_y, @intCast(text.len), 1, text_buffer.items.ptr, @intCast(text.len * 2));
        }
    }

    /// Measure text size
    pub fn measureText(self: *Renderer2DProper, text: []const u8, font_size: f32) Vec2 {
        _ = self;
        _ = font_size;
        return Vec2.init(@as(f32, @floatFromInt(text.len)) * 8.0, 16.0);
    }

    /// Begin scissor
    pub fn beginScissor(self: *Renderer2DProper, rect: Rect) void {
        // Flush current batch before scissor
        self.flush();
        _ = bgfx.setScissor(@intFromFloat(rect.x), @intFromFloat(rect.y), @intFromFloat(rect.width), @intFromFloat(rect.height));
    }

    /// End scissor
    pub fn endScissor(self: *Renderer2DProper) void {
        self.flush();
        _ = bgfx.setScissor(0, 0, @intCast(self.window_width), @intCast(self.window_height));
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
