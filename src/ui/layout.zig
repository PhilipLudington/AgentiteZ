const std = @import("std");
const Vec2 = @import("types.zig").Vec2;
const Rect = @import("types.zig").Rect;

/// Layout direction - how widgets are arranged
pub const LayoutDirection = enum {
    vertical, // Stack top to bottom
    horizontal, // Stack left to right
};

/// Layout alignment within the container
pub const LayoutAlign = enum {
    start, // Top/Left
    center, // Middle
    end, // Bottom/Right
};

/// Layout container configuration
pub const Layout = struct {
    /// Bounding rectangle for this layout
    rect: Rect,

    /// Direction to stack widgets
    direction: LayoutDirection,

    /// Alignment within the container
    alignment: LayoutAlign,

    /// Spacing between widgets (pixels)
    spacing: f32,

    /// Padding around the container (pixels)
    padding: f32,

    /// Current cursor position for next widget
    cursor: Vec2,

    /// Track used space in the primary direction
    used_space: f32,

    pub fn init(rect: Rect, direction: LayoutDirection, alignment: LayoutAlign) Layout {
        return .{
            .rect = rect,
            .direction = direction,
            .alignment = alignment,
            .spacing = 0,
            .padding = 0,
            .cursor = Vec2.init(rect.x, rect.y),
            .used_space = 0,
        };
    }

    /// Create a vertical layout (top to bottom)
    pub fn vertical(rect: Rect, alignment: LayoutAlign) Layout {
        var layout = init(rect, .vertical, alignment);
        layout.cursor.y = rect.y + layout.padding;
        return layout;
    }

    /// Create a horizontal layout (left to right)
    pub fn horizontal(rect: Rect, alignment: LayoutAlign) Layout {
        var layout = init(rect, .horizontal, alignment);
        layout.cursor.x = rect.x + layout.padding;
        return layout;
    }

    /// Set spacing between widgets
    pub fn withSpacing(self: Layout, spacing: f32) Layout {
        var result = self;
        result.spacing = spacing;
        return result;
    }

    /// Set padding around the container
    pub fn withPadding(self: Layout, padding: f32) Layout {
        var result = self;
        result.padding = padding;
        // Update cursor to account for padding
        if (result.direction == .vertical) {
            result.cursor.y = result.rect.y + padding;
            result.cursor.x = result.rect.x + padding;
        } else {
            result.cursor.x = result.rect.x + padding;
            result.cursor.y = result.rect.y + padding;
        }
        return result;
    }

    /// Get position for next widget of given size
    pub fn nextPosition(self: *Layout, width: f32, height: f32) Vec2 {
        var pos = self.cursor;

        // Apply alignment
        if (self.direction == .vertical) {
            // Vertical layout - align horizontally
            switch (self.alignment) {
                .start => pos.x = self.rect.x + self.padding,
                .center => pos.x = self.rect.x + (self.rect.width - width) / 2.0,
                .end => pos.x = self.rect.x + self.rect.width - width - self.padding,
            }
        } else {
            // Horizontal layout - align vertically
            switch (self.alignment) {
                .start => pos.y = self.rect.y + self.padding,
                .center => pos.y = self.rect.y + (self.rect.height - height) / 2.0,
                .end => pos.y = self.rect.y + self.rect.height - height - self.padding,
            }
        }

        return pos;
    }

    /// Advance cursor after placing a widget
    pub fn advance(self: *Layout, width: f32, height: f32) void {
        if (self.direction == .vertical) {
            self.cursor.y += height + self.spacing;
            self.used_space += height + self.spacing;
        } else {
            self.cursor.x += width + self.spacing;
            self.used_space += width + self.spacing;
        }
    }

    /// Get rect for next widget and advance cursor
    pub fn nextRect(self: *Layout, width: f32, height: f32) Rect {
        const pos = self.nextPosition(width, height);
        self.advance(width, height);
        return Rect.init(pos.x, pos.y, width, height);
    }

    /// Helper to center a single element in the layout
    pub fn centerElement(self: Layout, width: f32, height: f32) Vec2 {
        return Vec2.init(
            self.rect.x + (self.rect.width - width) / 2.0,
            self.rect.y + (self.rect.height - height) / 2.0,
        );
    }
};

test "Layout - vertical layout with start alignment" {
    const rect = Rect.init(0, 0, 100, 200);
    var layout = Layout.vertical(rect, .start);

    const pos1 = layout.nextPosition(50, 20);
    try std.testing.expectEqual(@as(f32, 0), pos1.x);
    try std.testing.expectEqual(@as(f32, 0), pos1.y);

    layout.advance(50, 20);
    const pos2 = layout.nextPosition(50, 20);
    try std.testing.expectEqual(@as(f32, 0), pos2.x);
    try std.testing.expectEqual(@as(f32, 20), pos2.y);
}

test "Layout - vertical layout with center alignment" {
    const rect = Rect.init(0, 0, 100, 200);
    var layout = Layout.vertical(rect, .center);

    const pos = layout.nextPosition(50, 20);
    try std.testing.expectEqual(@as(f32, 25), pos.x); // (100 - 50) / 2
    try std.testing.expectEqual(@as(f32, 0), pos.y);
}

test "Layout - horizontal layout with spacing" {
    const rect = Rect.init(0, 0, 200, 100);
    var layout = Layout.horizontal(rect, .start).withSpacing(10);

    const pos1 = layout.nextPosition(50, 20);
    try std.testing.expectEqual(@as(f32, 0), pos1.x);

    layout.advance(50, 20);
    const pos2 = layout.nextPosition(50, 20);
    try std.testing.expectEqual(@as(f32, 60), pos2.x); // 50 + 10 spacing
}

test "Layout - padding" {
    const rect = Rect.init(0, 0, 100, 100);
    var layout = Layout.vertical(rect, .start).withPadding(10);

    const pos = layout.nextPosition(50, 20);
    try std.testing.expectEqual(@as(f32, 10), pos.x);
    try std.testing.expectEqual(@as(f32, 10), pos.y);
}

test "Layout - center element" {
    const rect = Rect.init(0, 0, 100, 100);
    const layout = Layout.vertical(rect, .center);

    const pos = layout.centerElement(50, 20);
    try std.testing.expectEqual(@as(f32, 25), pos.x); // (100 - 50) / 2
    try std.testing.expectEqual(@as(f32, 40), pos.y); // (100 - 20) / 2
}

test "Layout - nextRect convenience" {
    const rect = Rect.init(10, 20, 100, 200);
    var layout = Layout.vertical(rect, .start);

    const widget_rect = layout.nextRect(50, 30);
    try std.testing.expectEqual(@as(f32, 10), widget_rect.x);
    try std.testing.expectEqual(@as(f32, 20), widget_rect.y);
    try std.testing.expectEqual(@as(f32, 50), widget_rect.width);
    try std.testing.expectEqual(@as(f32, 30), widget_rect.height);

    // Second widget should be positioned below first
    const widget_rect2 = layout.nextRect(60, 40);
    try std.testing.expectEqual(@as(f32, 50), widget_rect2.y); // 20 + 30
}
