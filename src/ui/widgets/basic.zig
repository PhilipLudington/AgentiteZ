const std = @import("std");
const context_mod = @import("../context.zig");
const types = @import("../types.zig");

pub const Context = context_mod.Context;
pub const widgetId = types.widgetId;
pub const Rect = types.Rect;
pub const Vec2 = types.Vec2;
pub const Color = types.Color;

/// Button widget with Imperial salvaged tech styling
pub fn button(ctx: *Context, text: []const u8, rect: Rect) bool {
    const id = widgetId(text);
    return buttonWithId(ctx, text, id, rect);
}

/// Button widget with explicit ID (for cases where multiple buttons share the same text)
pub fn buttonWithId(ctx: *Context, display_text: []const u8, id: u64, rect: Rect) bool {
    const clicked = ctx.registerWidget(id, rect);

    // Determine button color based on state using theme
    const bg_color = if (ctx.isActive(id))
        ctx.theme.button_pressed
    else if (ctx.isHot(id))
        ctx.theme.button_hover
    else
        ctx.theme.button_normal;

    // Draw button background
    ctx.renderer.drawRect(rect, bg_color);

    // Draw border
    ctx.renderer.drawRectOutline(rect, ctx.theme.button_border, ctx.theme.border_thickness);

    // Draw button text (centered) with theme color
    const text_size: f32 = 16;
    const text_bounds = ctx.renderer.measureText(display_text, text_size);
    const baseline_offset = ctx.renderer.getBaselineOffset(text_size);
    const text_pos = Vec2{
        .x = rect.x + (rect.width - text_bounds.x) / 2,
        .y = rect.y + rect.height / 2 - baseline_offset,
    };
    ctx.renderer.drawText(display_text, text_pos, text_size, ctx.theme.button_text);

    return clicked;
}

/// Auto-layout button (uses cursor position)
pub fn buttonAuto(ctx: *Context, text: []const u8, width: f32, height: f32) bool {
    const rect = Rect{
        .x = ctx.cursor.x,
        .y = ctx.cursor.y,
        .width = width,
        .height = height,
    };

    const clicked = button(ctx, text, rect);

    // Advance cursor for next widget
    ctx.advanceCursor(height, 5); // 5px spacing

    return clicked;
}

/// Label widget (non-interactive text)
pub fn label(ctx: *Context, text: []const u8, pos: Vec2, size: f32, color: Color) void {
    ctx.renderer.drawText(text, pos, size, color);
}

/// Checkbox widget
pub fn checkbox(ctx: *Context, label_text: []const u8, rect: Rect, checked: *bool) bool {
    const id = widgetId(label_text);
    const clicked = ctx.registerWidget(id, rect);

    // Toggle on click
    var changed = false;
    if (clicked) {
        checked.* = !checked.*;
        changed = true;
    }

    // Draw checkbox box
    const box_size: f32 = 20;
    const box_rect = Rect{
        .x = rect.x,
        .y = rect.y + (rect.height - box_size) / 2,
        .width = box_size,
        .height = box_size,
    };

    // Background color based on state
    const bg_color = if (ctx.isActive(id))
        Color.rgb(160, 160, 160) // Pressed
    else if (ctx.isHot(id))
        Color.rgb(220, 220, 220) // Hover
    else
        Color.rgb(240, 240, 240); // Normal

    ctx.renderer.drawRect(box_rect, bg_color);
    ctx.renderer.drawRectOutline(box_rect, Color.rgb(100, 100, 100), 2.0);

    // Draw checkmark if checked
    if (checked.*) {
        // Simple checkmark using filled rect
        const padding: f32 = 4;
        const check_rect = Rect{
            .x = box_rect.x + padding,
            .y = box_rect.y + padding,
            .width = box_size - (padding * 2),
            .height = box_size - (padding * 2),
        };
        ctx.renderer.drawRect(check_rect, Color.rgb(50, 150, 50));
    }

    // Draw label text
    if (label_text.len > 0) {
        const text_size: f32 = 16;
        const text_x = box_rect.x + box_size + 8; // 8px gap
        const baseline_offset = ctx.renderer.getBaselineOffset(text_size);
        const text_y = rect.y + rect.height / 2 - baseline_offset;

        ctx.renderer.drawText(label_text, .{ .x = text_x, .y = text_y }, text_size, Color.white);
    }

    return changed;
}

/// Auto-layout checkbox
pub fn checkboxAuto(ctx: *Context, label_text: []const u8, checked: *bool) bool {
    const text_size: f32 = 16;
    const box_size: f32 = 20;
    const text_bounds = ctx.renderer.measureText(label_text, text_size);

    // Width is box + gap + text
    const width = box_size + 8 + text_bounds.x;
    const height = @max(box_size, text_bounds.y);

    const rect = Rect{
        .x = ctx.cursor.x,
        .y = ctx.cursor.y,
        .width = width,
        .height = height + 4, // Bit of extra vertical space
    };

    const changed = checkbox(ctx, label_text, rect, checked);
    ctx.advanceCursor(height + 4, 5);

    return changed;
}
