const std = @import("std");
const types = @import("types.zig");
const Rect = types.Rect;
const Vec2 = types.Vec2;
const Color = types.Color;
const InputState = types.InputState;
const widgetId = types.widgetId;

// ============================================================================
// Integration Tests - Testing UI components working together
// ============================================================================

test "integration - Rect intersection for scissor clipping" {
    // Test that scissor rectangles intersect correctly
    const viewport = Rect.init(0, 0, 1920, 1080);
    const panel = Rect.init(100, 100, 400, 300);

    const clipped = viewport.intersect(panel);

    try std.testing.expectEqual(@as(f32, 100), clipped.x);
    try std.testing.expectEqual(@as(f32, 100), clipped.y);
    try std.testing.expectEqual(@as(f32, 400), clipped.width);
    try std.testing.expectEqual(@as(f32, 300), clipped.height);
}

test "integration - Rect intersection with partial overlap" {
    const rect1 = Rect.init(0, 0, 100, 100);
    const rect2 = Rect.init(50, 50, 100, 100);

    const intersection = rect1.intersect(rect2);

    try std.testing.expectEqual(@as(f32, 50), intersection.x);
    try std.testing.expectEqual(@as(f32, 50), intersection.y);
    try std.testing.expectEqual(@as(f32, 50), intersection.width);
    try std.testing.expectEqual(@as(f32, 50), intersection.height);
}

test "integration - Rect intersection with no overlap" {
    const rect1 = Rect.init(0, 0, 100, 100);
    const rect2 = Rect.init(200, 200, 100, 100);

    const intersection = rect1.intersect(rect2);

    // Should have zero area
    try std.testing.expectEqual(@as(f32, 0), intersection.width);
    try std.testing.expectEqual(@as(f32, 0), intersection.height);
}

test "integration - Rect scaling for DPI" {
    const rect = Rect.init(10, 20, 100, 50);
    const scaled = rect.scale(2.0);

    try std.testing.expectEqual(@as(f32, 20), scaled.x);
    try std.testing.expectEqual(@as(f32, 40), scaled.y);
    try std.testing.expectEqual(@as(f32, 200), scaled.width);
    try std.testing.expectEqual(@as(f32, 100), scaled.height);
}

test "integration - Color manipulation for hover effects" {
    const base_color = Color.imperial_gold;

    // Test darkening for button press
    const darkened = base_color.darken(0.7);
    try std.testing.expect(darkened.r < base_color.r);
    try std.testing.expect(darkened.g < base_color.g);
    try std.testing.expect(darkened.b < base_color.b);

    // Test lightening for hover
    const lightened = base_color.lighten(0.3);
    try std.testing.expect(lightened.r > base_color.r);
    try std.testing.expect(lightened.g > base_color.g);
    try std.testing.expect(lightened.b > base_color.b);
}

test "integration - Color clamping in extreme cases" {
    const white = Color.white;
    const black = Color.black;

    // Lighten white should stay white
    const lightened_white = white.lighten(1.0);
    try std.testing.expectEqual(@as(u8, 255), lightened_white.r);
    try std.testing.expectEqual(@as(u8, 255), lightened_white.g);
    try std.testing.expectEqual(@as(u8, 255), lightened_white.b);

    // Darken black should stay black
    const darkened_black = black.darken(0.0);
    try std.testing.expectEqual(@as(u8, 0), darkened_black.r);
    try std.testing.expectEqual(@as(u8, 0), darkened_black.g);
    try std.testing.expectEqual(@as(u8, 0), darkened_black.b);
}

test "integration - Vec2 operations for layout" {
    const pos1 = Vec2.init(100, 50);
    const offset = Vec2.init(20, 10);

    // Test adding for positioning child widgets
    const child_pos = pos1.add(offset);
    try std.testing.expectEqual(@as(f32, 120), child_pos.x);
    try std.testing.expectEqual(@as(f32, 60), child_pos.y);

    // Test subtracting for relative positions
    const relative = child_pos.sub(pos1);
    try std.testing.expectEqual(@as(f32, 20), relative.x);
    try std.testing.expectEqual(@as(f32, 10), relative.y);
}

test "integration - WidgetId collision detection" {
    // Test that different widget labels produce different IDs
    const button1_id = widgetId("button_1");
    const button2_id = widgetId("button_2");
    const slider_id = widgetId("slider");

    try std.testing.expect(button1_id != button2_id);
    try std.testing.expect(button1_id != slider_id);
    try std.testing.expect(button2_id != slider_id);
}

test "integration - WidgetId consistency across frames" {
    // Same label should produce same ID every time
    const id1 = widgetId("persistent_button");
    const id2 = widgetId("persistent_button");
    const id3 = widgetId("persistent_button");

    try std.testing.expectEqual(id1, id2);
    try std.testing.expectEqual(id2, id3);
}

test "integration - Mouse hit testing workflow" {
    const button_rect = Rect.init(100, 100, 200, 50);
    const input = InputState.init();

    // Test various mouse positions
    const inside_pos = Vec2.init(150, 125);
    const outside_pos = Vec2.init(50, 50);

    try std.testing.expect(button_rect.contains(inside_pos));
    try std.testing.expect(!button_rect.contains(outside_pos));
}

test "integration - Layout calculation sequence" {
    // Simulate laying out a vertical list of widgets
    const container = Rect.init(10, 10, 300, 500);
    const padding: f32 = 5;
    const widget_height: f32 = 40;

    // First widget
    const widget1 = Rect.init(
        container.x + padding,
        container.y + padding,
        container.width - padding * 2,
        widget_height,
    );

    // Second widget (below first)
    const widget2 = Rect.init(
        container.x + padding,
        widget1.y + widget1.height + padding,
        container.width - padding * 2,
        widget_height,
    );

    // Verify layout
    try std.testing.expectEqual(@as(f32, 15), widget1.x);
    try std.testing.expectEqual(@as(f32, 15), widget1.y);
    try std.testing.expectEqual(@as(f32, 290), widget1.width);

    try std.testing.expectEqual(@as(f32, 15), widget2.x);
    try std.testing.expectEqual(@as(f32, 60), widget2.y); // 15 + 40 + 5
    try std.testing.expectEqual(@as(f32, 290), widget2.width);

    // Both widgets should be inside container
    const widget1_center = widget1.center();
    const widget2_center = widget2.center();

    try std.testing.expect(container.contains(widget1_center));
    try std.testing.expect(container.contains(widget2_center));
}

test "integration - Nested scissor rectangle clipping" {
    // Outer panel
    const outer_panel = Rect.init(0, 0, 400, 400);

    // Inner scroll region
    const scroll_region = Rect.init(10, 10, 380, 200);

    // Nested panel inside scroll region
    const nested_panel = Rect.init(20, 20, 300, 150);

    // Apply scissor clipping chain
    const clip1 = outer_panel.intersect(scroll_region);
    const clip2 = clip1.intersect(nested_panel);

    // Final clip should be the nested panel
    try std.testing.expectEqual(@as(f32, 20), clip2.x);
    try std.testing.expectEqual(@as(f32, 20), clip2.y);
    try std.testing.expectEqual(@as(f32, 300), clip2.width);
    try std.testing.expectEqual(@as(f32, 150), clip2.height);
}

test "integration - Scroll region with content overflow" {
    // Scroll container
    const scroll_view = Rect.init(0, 0, 200, 100);

    // Content that's larger than container
    const content_height: f32 = 300;
    const scroll_offset: f32 = -50; // Scrolled down 50 pixels

    // Visible content area (top of content + scroll offset)
    const content_y = scroll_offset;
    const visible_content = Rect.init(0, content_y, 200, content_height);

    // Clip to scroll view
    const clipped = scroll_view.intersect(visible_content);

    // Should show from y=0 to y=100 in screen space
    try std.testing.expectEqual(@as(f32, 0), clipped.x);
    try std.testing.expectEqual(@as(f32, 0), clipped.y);
    try std.testing.expectEqual(@as(f32, 100), clipped.height);
}

test "integration - Theme color consistency" {
    const theme = types.Theme.imperial();

    // Button colors should be progressively darker: normal -> hover -> pressed
    // This is a visual consistency check

    // Verify theme has valid colors (not completely black or white unless intended)
    try std.testing.expect(theme.button_normal.r > 0 or theme.button_normal.g > 0 or theme.button_normal.b > 0);
    try std.testing.expect(theme.panel_bg.r > 0 or theme.panel_bg.g > 0 or theme.panel_bg.b > 0);

    // Border thickness should be positive
    try std.testing.expect(theme.border_thickness > 0);
    try std.testing.expect(theme.corner_size > 0);
}

test "integration - Input state frame lifecycle" {
    var input = InputState.init();

    // Simulate mouse click
    input.mouse_pos = Vec2.init(100, 50);
    input.mouse_down = true;
    input.mouse_clicked = true;

    const button_rect = Rect.init(50, 25, 100, 50);

    // Check if click is inside button
    const is_hit = button_rect.contains(input.mouse_pos);
    const is_clicked = is_hit and input.mouse_clicked;

    try std.testing.expect(is_clicked);

    // Next frame: mouse still down but not clicked
    input.mouse_clicked = false;
    const is_still_down = is_hit and input.mouse_down;
    const is_clicked_again = is_hit and input.mouse_clicked;

    try std.testing.expect(is_still_down);
    try std.testing.expect(!is_clicked_again);
}

test "integration - Multi-widget ID generation" {
    // Simulate generating IDs for multiple instances of the same widget type
    const allocator = std.testing.allocator;
    var buffer: [100]u8 = undefined;

    // Generate IDs for a list of buttons
    var ids: [5]u64 = undefined;
    for (0..5) |i| {
        const label = try std.fmt.bufPrint(&buffer, "button_{}", .{i});
        ids[i] = widgetId(label);
    }

    // All IDs should be unique
    for (0..5) |i| {
        for (i + 1..5) |j| {
            try std.testing.expect(ids[i] != ids[j]);
        }
    }

    _ = allocator;
}

test "integration - Rect center calculation for text alignment" {
    const button = Rect.init(100, 50, 200, 40);
    const center = button.center();

    try std.testing.expectEqual(@as(f32, 200), center.x); // 100 + 200/2
    try std.testing.expectEqual(@as(f32, 70), center.y);  // 50 + 40/2

    // Verify center is actually inside the rect
    try std.testing.expect(button.contains(center));
}

test "integration - DPI scaling consistency" {
    const base_rect = Rect.init(10, 20, 100, 50);
    const base_font_size: f32 = 16.0;

    // Scale for 2x DPI
    const dpi_scale: f32 = 2.0;
    const scaled_rect = base_rect.scale(dpi_scale);
    const scaled_font_size = base_font_size * dpi_scale;

    // Verify proportions are maintained
    const base_aspect = base_rect.width / base_rect.height;
    const scaled_aspect = scaled_rect.width / scaled_rect.height;

    try std.testing.expectApproxEqRel(base_aspect, scaled_aspect, 0.0001);
    try std.testing.expectEqual(@as(f32, 32.0), scaled_font_size);
}
