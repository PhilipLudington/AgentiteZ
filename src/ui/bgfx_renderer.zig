const std = @import("std");
const root = @import("../root.zig");
const bgfx = root.bgfx;
const types = @import("types.zig");

pub const Rect = types.Rect;
pub const Color = types.Color;
pub const Vec2 = types.Vec2;

/// bgfx-based renderer for UI
/// Uses bgfx debug text for now (simple implementation)
/// TODO: Implement proper textured quad rendering with stb_truetype
pub const BgfxRenderer = struct {
    allocator: std.mem.Allocator,
    window_width: u32,
    window_height: u32,

    // Scissor stack for clipping
    scissor_stack: std.ArrayList(Rect),

    pub fn init(allocator: std.mem.Allocator, window_width: u32, window_height: u32) BgfxRenderer {
        return .{
            .allocator = allocator,
            .window_width = window_width,
            .window_height = window_height,
            .scissor_stack = .{},
        };
    }

    pub fn deinit(self: *BgfxRenderer) void {
        self.scissor_stack.deinit(self.allocator);
    }

    pub fn updateWindowSize(self: *BgfxRenderer, width: u32, height: u32) void {
        self.window_width = width;
        self.window_height = height;
    }

    /// Draw a filled rectangle using bgfx debug text characters
    /// This uses the █ (block) character to fill rectangles
    pub fn drawRect(self: *BgfxRenderer, rect: Rect, color: Color) void {
        // Convert to character grid coordinates (8x16 pixels per char)
        const char_x: u16 = @intFromFloat(@max(0, rect.x / 8.0));
        const char_y: u16 = @intFromFloat(@max(0, rect.y / 16.0));
        const char_w: u16 = @intFromFloat(@max(1, rect.width / 8.0));
        const char_h: u16 = @intFromFloat(@max(1, rect.height / 16.0));

        // Convert color to bgfx attribute
        const attr: u8 = colorToBgfxAttr(color);

        // Draw filled rectangle using block characters
        var y: u16 = 0;
        while (y < char_h) : (y += 1) {
            var x: u16 = 0;
            while (x < char_w) : (x += 1) {
                var text_buffer: [2]u8 = undefined;
                text_buffer[0] = 0xDB; // Block character █
                text_buffer[1] = attr;

                bgfx.dbgTextImage(
                    char_x + x,
                    char_y + y,
                    1,
                    1,
                    &text_buffer,
                    2,
                );
            }
        }
        _ = self;
    }

    /// Draw a rectangle outline
    pub fn drawRectOutline(self: *BgfxRenderer, rect: Rect, color: Color, thickness: f32) void {
        // Draw four rectangles for the outline
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
    pub fn drawText(self: *BgfxRenderer, text: []const u8, pos: Vec2, size: f32, color: Color) void {
        _ = size; // TODO: Use size to select font/scale

        // Convert screen coordinates to character grid coordinates
        // bgfx debug text uses 8x16 pixel characters
        const char_x: u16 = @intFromFloat(pos.x / 8.0);
        const char_y: u16 = @intFromFloat(pos.y / 16.0);

        // Convert Color to bgfx attribute (4-bit color)
        const attr: u8 = colorToBgfxAttr(color);

        // Create text buffer
        var text_buffer: std.ArrayList(u8) = .{};
        defer text_buffer.deinit(self.allocator);

        // Fill buffer with text and attributes
        for (text) |char| {
            text_buffer.append(self.allocator, char) catch return;
            text_buffer.append(self.allocator, attr) catch return;
        }

        // Render using bgfx debug text
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

    /// Measure text size (rough estimation based on fixed-width font)
    pub fn measureText(self: *BgfxRenderer, text: []const u8, font_size: f32) Vec2 {
        _ = self;
        _ = font_size;

        // bgfx debug text uses 8x16 pixel characters
        const char_width: f32 = 8.0;
        const char_height: f32 = 16.0;

        return Vec2.init(
            @as(f32, @floatFromInt(text.len)) * char_width,
            char_height,
        );
    }

    /// Begin scissor clipping
    pub fn beginScissor(self: *BgfxRenderer, rect: Rect) void {
        self.scissor_stack.append(self.allocator, rect) catch return;

        // Convert to bgfx scissor coordinates
        const x: u16 = @intFromFloat(rect.x);
        const y: u16 = @intFromFloat(rect.y);
        const width: u16 = @intFromFloat(rect.width);
        const height: u16 = @intFromFloat(rect.height);

        _ = bgfx.setScissor(x, y, width, height);
    }

    /// End scissor clipping
    pub fn endScissor(self: *BgfxRenderer) void {
        _ = self.scissor_stack.pop();

        // Restore previous scissor or disable
        if (self.scissor_stack.items.len > 0) {
            const rect = self.scissor_stack.items[self.scissor_stack.items.len - 1];
            const x: u16 = @intFromFloat(rect.x);
            const y: u16 = @intFromFloat(rect.y);
            const width: u16 = @intFromFloat(rect.width);
            const height: u16 = @intFromFloat(rect.height);
            _ = bgfx.setScissor(x, y, width, height);
        } else {
            // Disable scissor (use full screen)
            _ = bgfx.setScissor(0, 0, @intCast(self.window_width), @intCast(self.window_height));
        }
    }

    pub fn isNull(self: *BgfxRenderer) bool {
        _ = self;
        return false;
    }
};

/// Convert RGBA color to bgfx 4-bit color attribute
/// Format: 0xFB where F=foreground, B=background
fn colorToBgfxAttr(color: Color) u8 {
    // Simple color mapping to 16-color palette
    // High intensity if any channel > 128
    const high = color.r > 128 or color.g > 128 or color.b > 128;

    var attr: u8 = 0;

    // Determine color based on dominant channel
    if (color.r > color.g and color.r > color.b) {
        attr = if (high) 0x0C else 0x04; // Red (bright/dark)
    } else if (color.g > color.r and color.g > color.b) {
        attr = if (high) 0x0A else 0x02; // Green (bright/dark)
    } else if (color.b > color.r and color.b > color.g) {
        attr = if (high) 0x09 else 0x01; // Blue (bright/dark)
    } else if (color.r > 200 and color.g > 200 and color.b > 200) {
        attr = 0x0F; // White
    } else if (color.r < 50 and color.g < 50 and color.b < 50) {
        attr = 0x00; // Black
    } else {
        attr = 0x07; // Gray
    }

    return attr;
}

test "BgfxRenderer - basic" {
    const allocator = std.testing.allocator;
    var renderer = BgfxRenderer.init(allocator, 1920, 1080);
    defer renderer.deinit();

    // Should not crash
    renderer.drawRect(Rect.init(0, 0, 100, 50), Color.white);
    const size = renderer.measureText("Hello", 16);
    try std.testing.expectEqual(@as(f32, 40), size.x); // 5 chars * 8 pixels
}
