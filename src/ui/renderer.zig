const std = @import("std");
const types = @import("types.zig");

pub const Rect = types.Rect;
pub const Color = types.Color;
pub const Vec2 = types.Vec2;

/// Text alignment
pub const TextAlign = enum {
    left,
    center,
    right,
};

/// Renderer interface - backends implement this
pub const Renderer = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Draw a filled rectangle
        drawRect: *const fn (ptr: *anyopaque, rect: Rect, color: Color) void,
        /// Draw a rectangle outline
        drawRectOutline: *const fn (ptr: *anyopaque, rect: Rect, color: Color, thickness: f32) void,
        /// Draw text
        drawText: *const fn (ptr: *anyopaque, text: []const u8, pos: Vec2, size: f32, color: Color) void,
        /// Measure text size
        measureText: *const fn (ptr: *anyopaque, text: []const u8, size: f32) Vec2,
        /// Get baseline offset for vertically centering text
        getBaselineOffset: *const fn (ptr: *anyopaque, font_size: f32) f32,
        /// Begin scissor clipping (restrict rendering to rect)
        beginScissor: *const fn (ptr: *anyopaque, rect: Rect) void,
        /// End scissor clipping (restore normal rendering)
        endScissor: *const fn (ptr: *anyopaque) void,
        /// Flush pending draw batches to GPU
        flushBatches: *const fn (ptr: *anyopaque) void,
        /// Check if this is a null/test renderer
        isNull: *const fn (ptr: *anyopaque) bool,
    };

    pub fn drawRect(self: Renderer, rect: Rect, color: Color) void {
        self.vtable.drawRect(self.ptr, rect, color);
    }

    pub fn drawRectOutline(self: Renderer, rect: Rect, color: Color, thickness: f32) void {
        self.vtable.drawRectOutline(self.ptr, rect, color, thickness);
    }

    pub fn drawText(self: Renderer, text: []const u8, pos: Vec2, size: f32, color: Color) void {
        self.vtable.drawText(self.ptr, text, pos, size, color);
    }

    pub fn measureText(self: Renderer, text: []const u8, size: f32) Vec2 {
        return self.vtable.measureText(self.ptr, text, size);
    }

    pub fn getBaselineOffset(self: Renderer, font_size: f32) f32 {
        return self.vtable.getBaselineOffset(self.ptr, font_size);
    }

    pub fn beginScissor(self: Renderer, rect: Rect) void {
        self.vtable.beginScissor(self.ptr, rect);
    }

    pub fn endScissor(self: Renderer) void {
        self.vtable.endScissor(self.ptr);
    }

    pub fn flushBatches(self: Renderer) void {
        self.vtable.flushBatches(self.ptr);
    }

    pub fn isNull(self: Renderer) bool {
        return self.vtable.isNull(self.ptr);
    }

    /// Helper to create a Renderer from any type that implements the interface
    pub fn init(pointer: anytype) Renderer {
        const T = @TypeOf(pointer.*);
        const ptr = @as(*anyopaque, @ptrCast(pointer));

        const gen = struct {
            fn drawRectImpl(p: *anyopaque, rect: Rect, color: Color) void {
                const self: *T = @ptrCast(@alignCast(p));
                self.drawRect(rect, color);
            }

            fn drawRectOutlineImpl(p: *anyopaque, rect: Rect, color: Color, thickness: f32) void {
                const self: *T = @ptrCast(@alignCast(p));
                self.drawRectOutline(rect, color, thickness);
            }

            fn drawTextImpl(p: *anyopaque, text: []const u8, pos: Vec2, size: f32, color: Color) void {
                const self: *T = @ptrCast(@alignCast(p));
                self.drawText(text, pos, size, color);
            }

            fn measureTextImpl(p: *anyopaque, text: []const u8, size: f32) Vec2 {
                const self: *T = @ptrCast(@alignCast(p));
                return self.measureText(text, size);
            }

            fn getBaselineOffsetImpl(p: *anyopaque, font_size: f32) f32 {
                const self: *T = @ptrCast(@alignCast(p));
                return self.getBaselineOffset(font_size);
            }

            fn beginScissorImpl(p: *anyopaque, rect: Rect) void {
                const self: *T = @ptrCast(@alignCast(p));
                self.beginScissor(rect);
            }

            fn endScissorImpl(p: *anyopaque) void {
                const self: *T = @ptrCast(@alignCast(p));
                self.endScissor();
            }

            fn flushBatchesImpl(p: *anyopaque) void {
                const self: *T = @ptrCast(@alignCast(p));
                self.flushBatches();
            }

            fn isNullImpl(p: *anyopaque) bool {
                const self: *T = @ptrCast(@alignCast(p));
                return self.isNull();
            }

            const vtable = VTable{
                .drawRect = drawRectImpl,
                .drawRectOutline = drawRectOutlineImpl,
                .drawText = drawTextImpl,
                .measureText = measureTextImpl,
                .getBaselineOffset = getBaselineOffsetImpl,
                .beginScissor = beginScissorImpl,
                .endScissor = endScissorImpl,
                .flushBatches = flushBatchesImpl,
                .isNull = isNullImpl,
            };
        };

        return .{
            .ptr = ptr,
            .vtable = &gen.vtable,
        };
    }
};

/// Null renderer for testing (does nothing)
pub const NullRenderer = struct {
    pub fn drawRect(self: *NullRenderer, rect: Rect, color: Color) void {
        _ = self;
        _ = rect;
        _ = color;
    }

    pub fn drawRectOutline(self: *NullRenderer, rect: Rect, color: Color, thickness: f32) void {
        _ = self;
        _ = rect;
        _ = color;
        _ = thickness;
    }

    pub fn drawText(self: *NullRenderer, text: []const u8, pos: Vec2, size: f32, color: Color) void {
        _ = self;
        _ = text;
        _ = pos;
        _ = size;
        _ = color;
    }

    pub fn measureText(self: *NullRenderer, text: []const u8, font_size: f32) Vec2 {
        _ = self;
        // Simple estimation: ~10 pixels per character
        return Vec2.init(@as(f32, @floatFromInt(text.len)) * 10.0, font_size);
    }

    pub fn getBaselineOffset(self: *NullRenderer, font_size: f32) f32 {
        _ = self;
        // Simple approximation for null renderer
        return font_size * 0.2;
    }

    pub fn beginScissor(self: *NullRenderer, rect: Rect) void {
        _ = self;
        _ = rect;
    }

    pub fn endScissor(self: *NullRenderer) void {
        _ = self;
    }

    pub fn flushBatches(self: *NullRenderer) void {
        _ = self;
    }

    pub fn isNull(self: *NullRenderer) bool {
        _ = self;
        return true;
    }
};

test "Renderer - null renderer" {
    var null_renderer = NullRenderer{};
    const renderer = Renderer.init(&null_renderer);

    // Should not crash
    renderer.drawRect(Rect.init(0, 0, 100, 50), Color.white);
    renderer.drawRectOutline(Rect.init(0, 0, 100, 50), Color.black, 2.0);
    renderer.drawText("Test", Vec2.init(10, 10), 16, Color.black);

    const size = renderer.measureText("Hello", 16);
    try std.testing.expectEqual(@as(f32, 50), size.x); // 5 chars * 10 pixels
}
