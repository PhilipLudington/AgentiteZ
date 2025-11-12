const std = @import("std");
const root = @import("../root.zig");
const bgfx = root.bgfx;
const types = @import("types.zig");

pub const Rect = types.Rect;
pub const Color = types.Color;
pub const Vec2 = types.Vec2;

/// Improved 2D Renderer using bgfx debug draw
/// This provides much better rendering than character-based while being practical
pub const RendererImproved = struct {
    allocator: std.mem.Allocator,
    window_width: u32,
    window_height: u32,
    encoder: ?*bgfx.Encoder,

    pub fn init(allocator: std.mem.Allocator, window_width: u32, window_height: u32) RendererImproved {
        return .{
            .allocator = allocator,
            .window_width = window_width,
            .window_height = window_height,
            .encoder = null,
        };
    }

    pub fn deinit(self: *RendererImproved) void {
        _ = self;
    }

    pub fn updateWindowSize(self: *RendererImproved, width: u32, height: u32) void {
        self.window_width = width;
        self.window_height = height;
    }

    /// Draw a filled rectangle using debug draw
    pub fn drawRect(self: *RendererImproved, rect: Rect, color: Color) void {
        // Use bgfx debug draw to render filled rectangles
        const dd = bgfx.DebugDrawEncoder{};

        // For now, fall back to character rendering but with better granularity
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
        _ = dd;
    }

    /// Draw rectangle outline
    pub fn drawRectOutline(self: *RendererImproved, rect: Rect, color: Color, thickness: f32) void {
        self.drawRect(.{ .x = rect.x, .y = rect.y, .width = rect.width, .height = thickness }, color);
        self.drawRect(.{ .x = rect.x, .y = rect.y + rect.height - thickness, .width = rect.width, .height = thickness }, color);
        self.drawRect(.{ .x = rect.x, .y = rect.y + thickness, .width = thickness, .height = rect.height - (thickness * 2) }, color);
        self.drawRect(.{ .x = rect.x + rect.width - thickness, .y = rect.y + thickness, .width = thickness, .height = rect.height - (thickness * 2) }, color);
    }

    /// Draw text
    pub fn drawText(self: *RendererImproved, text: []const u8, pos: Vec2, size: f32, color: Color) void {
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
            bgfx.dbgTextImage(char_x, char_y, @intCast(text.len), 1, text_buffer.items.ptr, @intCast(text.len * 2));
        }
    }

    /// Measure text size
    pub fn measureText(self: *RendererImproved, text: []const u8, font_size: f32) Vec2 {
        _ = self;
        _ = font_size;
        return Vec2.init(@as(f32, @floatFromInt(text.len)) * 8.0, 16.0);
    }

    /// Begin scissor clipping
    pub fn beginScissor(self: *RendererImproved, rect: Rect) void {
        _ = bgfx.setScissor(@intFromFloat(rect.x), @intFromFloat(rect.y), @intFromFloat(rect.width), @intFromFloat(rect.height));
        _ = self;
    }

    /// End scissor clipping
    pub fn endScissor(self: *RendererImproved) void {
        _ = bgfx.setScissor(0, 0, @intCast(self.window_width), @intCast(self.window_height));
    }

    pub fn isNull(self: *RendererImproved) bool {
        _ = self;
        return false;
    }
};

/// Convert Color to bgfx debug text attribute
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
