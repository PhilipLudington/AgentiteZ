const std = @import("std");
const context_mod = @import("../context.zig");
const types = @import("../types.zig");

pub const Context = context_mod.Context;
pub const widgetId = types.widgetId;
pub const Rect = types.Rect;
pub const Vec2 = types.Vec2;
pub const Color = types.Color;

/// Button widget with Imperial salvaged tech styling
///
/// IMPORTANT: Widget ID Collision Risk
/// ====================================
/// This function generates widget IDs by hashing the button text. If you have
/// multiple buttons with IDENTICAL text (e.g., multiple "OK" or "Delete" buttons),
/// they will share the same widget state, causing unexpected behavior.
///
/// Safe Usage:
///   - Static UIs with unique button labels
///   - Buttons with distinct text per screen
///
/// Unsafe Usage (ID Collisions):
///   - Dynamic lists with identical button labels
///   - Multiple modals with same button text
///   - Repeated UI patterns (e.g., inventory items with "Use" buttons)
///
/// Solution for Dynamic UIs:
///   Use `buttonWithId()` with explicit IDs instead:
///
///   Example:
///   ```zig
///   for (items, 0..) |item, i| {
///       const id = widgetId(&[_]u8{i}); // Unique ID per item
///       if (buttonWithId(ctx, "Delete", id, rect)) {
///           // Handle delete for item i
///       }
///   }
///   ```
///
/// See also: `buttonWithId()` for explicit ID control
pub fn button(ctx: *Context, text: []const u8, rect: Rect) bool {
    const id = widgetId(text);
    return buttonWithId(ctx, text, id, rect);
}

/// Button widget with explicit ID (for cases where multiple buttons share the same text)
///
/// Use this when you need multiple buttons with identical text. You provide a unique ID
/// to prevent widget state collisions.
///
/// Example - Dynamic item list:
/// ```zig
/// for (inventory_items, 0..) |item, i| {
///     const button_rect = layout.nextRect(120, 40);
///
///     // Generate unique ID combining item index with a namespace
///     const id = std.hash.Wyhash.hash(i, "inventory_delete");
///
///     if (buttonWithId(ctx, "Delete", id, button_rect)) {
///         deleteItem(item);
///     }
/// }
/// ```
///
/// Example - Multiple modals:
/// ```zig
/// // Modal 1
/// if (buttonWithId(ctx, "OK", widgetId("modal1_ok"), rect1)) { }
///
/// // Modal 2 (different ID, same text)
/// if (buttonWithId(ctx, "OK", widgetId("modal2_ok"), rect2)) { }
/// ```
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
    const text_size = ctx.theme.font_size_normal;
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
    ctx.advanceCursor(height, ctx.theme.widget_spacing);

    return clicked;
}

/// Label widget (non-interactive text)
pub fn label(ctx: *Context, text: []const u8, pos: Vec2, size: f32, color: Color) void {
    ctx.renderer.drawText(text, pos, size, color);
}

/// Checkbox widget
///
/// WARNING: Same ID collision risk as button()
/// If you have multiple checkboxes with identical labels, use explicit IDs instead.
///
/// Safe: Each checkbox has unique label text
/// Unsafe: Multiple checkboxes labeled "Enable" in dynamic lists
///
/// For dynamic UIs, generate unique IDs:
/// ```zig
/// const id = std.hash.Wyhash.hash(item_index, "checkbox_namespace");
/// ```
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
    const box_size = ctx.theme.checkbox_size;
    const box_rect = Rect{
        .x = rect.x,
        .y = rect.y + (rect.height - box_size) / 2,
        .width = box_size,
        .height = box_size,
    };

    // Background color based on state using theme
    const bg_color = if (ctx.isActive(id))
        ctx.theme.checkbox_bg_pressed
    else if (ctx.isHot(id))
        ctx.theme.checkbox_bg_hover
    else
        ctx.theme.checkbox_bg_normal;

    ctx.renderer.drawRect(box_rect, bg_color);
    ctx.renderer.drawRectOutline(box_rect, ctx.theme.checkbox_border, ctx.theme.border_thickness);

    // Draw checkmark if checked
    if (checked.*) {
        // Simple checkmark using filled rect
        const padding = ctx.theme.widget_padding;
        const check_rect = Rect{
            .x = box_rect.x + padding,
            .y = box_rect.y + padding,
            .width = box_size - (padding * 2),
            .height = box_size - (padding * 2),
        };
        ctx.renderer.drawRect(check_rect, ctx.theme.checkbox_check);
    }

    // Draw label text
    if (label_text.len > 0) {
        const text_size = ctx.theme.font_size_normal;
        const baseline_offset = ctx.renderer.getBaselineOffset(text_size);
        const text_x = box_rect.x + box_size + 8; // 8px gap
        const text_y = rect.y + rect.height / 2 - baseline_offset;

        ctx.renderer.drawText(label_text, .{ .x = text_x, .y = text_y }, text_size, ctx.theme.text_primary);
    }

    return changed;
}

/// Auto-layout checkbox
pub fn checkboxAuto(ctx: *Context, label_text: []const u8, checked: *bool) bool {
    const text_size = ctx.theme.font_size_normal;
    const box_size = ctx.theme.checkbox_size;
    const text_bounds = ctx.renderer.measureText(label_text, text_size);

    // Width is box + gap + text
    const width = box_size + 8 + text_bounds.x;
    const height = @max(box_size, text_bounds.y);

    const rect = Rect{
        .x = ctx.cursor.x,
        .y = ctx.cursor.y,
        .width = width,
        .height = height + ctx.theme.widget_padding,
    };

    const changed = checkbox(ctx, label_text, rect, checked);
    ctx.advanceCursor(height + ctx.theme.widget_padding, ctx.theme.widget_spacing);

    return changed;
}
