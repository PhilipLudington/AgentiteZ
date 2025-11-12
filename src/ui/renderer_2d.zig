const std = @import("std");
const root = @import("../root.zig");
const bgfx = root.bgfx;
const stb = root.stb_truetype;
const types = @import("types.zig");

pub const Rect = types.Rect;
pub const Color = types.Color;
pub const Vec2 = types.Vec2;

/// Vertex structure for 2D rendering
const PosColorVertex = extern struct {
    x: f32,
    y: f32,
    z: f32,
    abgr: u32,

    fn init(x: f32, y: f32, color: Color) PosColorVertex {
        return .{
            .x = x,
            .y = y,
            .z = 0.0,
            .abgr = colorToABGR(color),
        };
    }
};

/// Convert Color to ABGR u32 format
fn colorToABGR(color: Color) u32 {
    return (@as(u32, color.a) << 24) |
        (@as(u32, color.b) << 16) |
        (@as(u32, color.g) << 8) |
        (@as(u32, color.r) << 0);
}

/// Improved 2D Renderer using bgfx primitives
/// This is still a simplified implementation but better than character-based
pub const Renderer2D = struct {
    allocator: std.mem.Allocator,
    window_width: u32,
    window_height: u32,

    // Vertex layout for colored vertices
    vertex_layout: bgfx.VertexLayout,

    pub fn init(allocator: std.mem.Allocator, window_width: u32, window_height: u32) !Renderer2D {
        var vertex_layout: bgfx.VertexLayout = undefined;
        bgfx.vertexLayoutBegin(&vertex_layout, bgfx.RendererType.Noop);
        _ = bgfx.vertexLayoutAdd(
            &vertex_layout,
            bgfx.Attrib.Position,
            3,
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
        };
    }

    pub fn deinit(self: *Renderer2D) void {
        _ = self;
    }

    pub fn updateWindowSize(self: *Renderer2D, width: u32, height: u32) void {
        self.window_width = width;
        self.window_height = height;
    }

    /// Draw a filled rectangle
    /// For now, falls back to debug text rendering
    /// TODO: Implement with transient vertex buffers
    pub fn drawRect(self: *Renderer2D, rect: Rect, color: Color) void {
        // For now, use debug text as fallback
        // This will be replaced with proper vertex buffer rendering
        const char_x: u16 = @intFromFloat(@max(0, rect.x / 8.0));
        const char_y: u16 = @intFromFloat(@max(0, rect.y / 16.0));
        const char_w: u16 = @intFromFloat(@max(1, rect.width / 8.0));
        const char_h: u16 = @intFromFloat(@max(1, rect.height / 16.0));

        const attr: u8 = colorToBgfxAttr(color);

        var y: u16 = 0;
        while (y < char_h) : (y += 1) {
            var x: u16 = 0;
            while (x < char_w) : (x += 1) {
                var text_buffer: [2]u8 = undefined;
                text_buffer[0] = 0xDB; // Block character
                text_buffer[1] = attr;

                bgfx.dbgTextImage(char_x + x, char_y + y, 1, 1, &text_buffer, 2);
            }
        }
        _ = self;
    }

    /// Draw a rectangle outline
    pub fn drawRectOutline(self: *Renderer2D, rect: Rect, color: Color, thickness: f32) void {
        // Top
        self.drawRect(.{
            .x = rect.x,
            .y = rect.y,
            .width = rect.width,
            .height = thickness,
        }, color);

        // Bottom
        self.drawRect(.{
            .x = rect.x,
            .y = rect.y + rect.height - thickness,
            .width = rect.width,
            .height = thickness,
        }, color);

        // Left
        self.drawRect(.{
            .x = rect.x,
            .y = rect.y + thickness,
            .width = thickness,
            .height = rect.height - (thickness * 2),
        }, color);

        // Right
        self.drawRect(.{
            .x = rect.x + rect.width - thickness,
            .y = rect.y + thickness,
            .width = thickness,
            .height = rect.height - (thickness * 2),
        }, color);
    }

    /// Draw text using bgfx debug text
    pub fn drawText(self: *Renderer2D, text: []const u8, pos: Vec2, size: f32, color: Color) void {
        _ = size;

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
            bgfx.dbgTextImage(
                char_x,
                char_y,
                @intCast(text.len),
                1,
                text_buffer.items.ptr,
                @intCast(text.len * 2),
            );
        }
    }

    /// Measure text size
    pub fn measureText(self: *Renderer2D, text: []const u8, font_size: f32) Vec2 {
        _ = self;
        _ = font_size;

        const char_width: f32 = 8.0;
        const char_height: f32 = 16.0;

        return Vec2.init(
            @as(f32, @floatFromInt(text.len)) * char_width,
            char_height,
        );
    }

    /// Begin scissor clipping
    pub fn beginScissor(self: *Renderer2D, rect: Rect) void {
        const x: u16 = @intFromFloat(rect.x);
        const y: u16 = @intFromFloat(rect.y);
        const width: u16 = @intFromFloat(rect.width);
        const height: u16 = @intFromFloat(rect.height);
        _ = bgfx.setScissor(x, y, width, height);
        _ = self;
    }

    /// End scissor clipping
    pub fn endScissor(self: *Renderer2D) void {
        _ = bgfx.setScissor(0, 0, @intCast(self.window_width), @intCast(self.window_height));
    }

    pub fn isNull(self: *Renderer2D) bool {
        _ = self;
        return false;
    }
};

/// Convert Color to bgfx 4-bit color attribute
fn colorToBgfxAttr(color: Color) u8 {
    const high = color.r > 128 or color.g > 128 or color.b > 128;

    var attr: u8 = 0;

    if (color.r > color.g and color.r > color.b) {
        attr = if (high) 0x0C else 0x04;
    } else if (color.g > color.r and color.g > color.b) {
        attr = if (high) 0x0A else 0x02;
    } else if (color.b > color.r and color.b > color.g) {
        attr = if (high) 0x09 else 0x01;
    } else if (color.r > 200 and color.g > 200 and color.b > 200) {
        attr = 0x0F;
    } else if (color.r < 50 and color.g < 50 and color.b < 50) {
        attr = 0x00;
    } else {
        attr = 0x07;
    }

    return attr;
}
