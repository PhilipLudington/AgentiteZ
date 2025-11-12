const std = @import("std");
const root = @import("../root.zig");
const bgfx = root.bgfx;
// const stb = root.stb_truetype; // TODO: Fix stb_truetype cImport issues
const types = @import("types.zig");
const shaders = @import("shaders.zig");

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

// TODO: Re-enable FontAtlas when stb_truetype cImport issues are resolved
// /// Font atlas for text rendering
// const FontAtlas = struct {
//     texture: bgfx.TextureHandle,
//     width: u32,
//     height: u32,
//     char_data: [96]stb.c.stbtt_bakedchar, // ASCII 32-127
//     font_size: f32,
//
//     fn init(allocator: std.mem.Allocator, font_data: []const u8, font_size: f32) !FontAtlas {
//         ...
//     }
//
//     fn deinit(self: *FontAtlas) void {
//         bgfx.destroyTexture(self.texture);
//     }
// };

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

    // Font atlas for text rendering (TODO: Re-enable when stb_truetype works)
    // font_atlas: ?FontAtlas,

    // View ID for UI rendering
    view_id: bgfx.ViewId,

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

        // TODO: Load font atlas when stb_truetype cImport works

        return .{
            .allocator = allocator,
            .window_width = window_width,
            .window_height = window_height,
            .shader_programs = shader_programs,
            .color_vertex_layout = color_vertex_layout,
            .texture_vertex_layout = texture_vertex_layout,
            .color_batch = DrawBatch.init(allocator),
            .texture_batch = TextureBatch.init(allocator),
            // .font_atlas = null,
            .view_id = 0,
        };
    }

    pub fn deinit(self: *Renderer2DProper) void {
        self.shader_programs.deinit();
        self.color_batch.deinit();
        self.texture_batch.deinit();
        // if (self.font_atlas) |*atlas| {
        //     atlas.deinit();
        // }
    }

    pub fn updateWindowSize(self: *Renderer2DProper, width: u32, height: u32) void {
        self.window_width = width;
        self.window_height = height;
    }

    /// Begin frame - clear batches
    pub fn beginFrame(self: *Renderer2DProper) void {
        self.color_batch.clear();
        self.texture_batch.clear();
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

        // Set render state (alpha blending: src_alpha, inv_src_alpha)
        bgfx.setState(
            bgfx.StateFlags_WriteRgb |
                bgfx.StateFlags_WriteA |
                bgfx.StateFlags_BlendSrcAlpha |
                ((bgfx.StateFlags_BlendInvSrcAlpha) << 4),
            0,
        );

        // Submit draw call with color shader program
        _ = bgfx.submit(self.view_id, self.shader_programs.color_program, 0, 0);
    }

    /// Flush textured draw batch to GPU - TODO: Re-enable when font atlas works
    fn flushTextureBatch(self: *Renderer2DProper) void {
        _ = self;
        // TODO: Implement texture batch flushing when font atlas is working
    }

    /// Draw a filled rectangle
    pub fn drawRect(self: *Renderer2DProper, rect: Rect, color: Color) void {
        self.color_batch.addQuad(rect.x, rect.y, rect.width, rect.height, color) catch return;
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

    /// Draw text - TODO: Implement when font atlas works
    pub fn drawText(self: *Renderer2DProper, text: []const u8, pos: Vec2, size: f32, color: Color) void {
        _ = self;
        _ = text;
        _ = pos;
        _ = size;
        _ = color;
        // TODO: Re-enable font atlas rendering when stb_truetype cImport works
    }

    /// Measure text size
    pub fn measureText(self: *Renderer2DProper, text: []const u8, font_size: f32) Vec2 {
        _ = self;
        _ = font_size;
        return Vec2.init(@as(f32, @floatFromInt(text.len)) * 8.0, 16.0);
    }

    /// Begin scissor
    pub fn beginScissor(self: *Renderer2DProper, rect: Rect) void {
        // Flush current batches before scissor
        self.flushColorBatch();
        self.flushTextureBatch();
        _ = bgfx.setScissor(@intFromFloat(rect.x), @intFromFloat(rect.y), @intFromFloat(rect.width), @intFromFloat(rect.height));
    }

    /// End scissor
    pub fn endScissor(self: *Renderer2DProper) void {
        self.flushColorBatch();
        self.flushTextureBatch();
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
