const std = @import("std");
const context_mod = @import("../context.zig");
const types = @import("../types.zig");

pub const Context = context_mod.Context;
pub const widgetId = types.widgetId;
pub const Rect = types.Rect;
pub const Vec2 = types.Vec2;
pub const Color = types.Color;

/// Slider widget - returns updated value
pub fn slider(ctx: *Context, label_text: []const u8, rect: Rect, value: f32, min_val: f32, max_val: f32) f32 {
    const id = widgetId(label_text);
    _ = ctx.registerWidget(id, rect);

    var new_value = value;

    // Handle dragging
    if (ctx.isActive(id) and ctx.input.mouse_down) {
        // Calculate value from mouse position
        const track_x = rect.x + 5;
        const track_width = rect.width - 10;
        const mouse_offset = ctx.input.mouse_pos.x - track_x;
        const normalized = std.math.clamp(mouse_offset / track_width, 0.0, 1.0);
        new_value = min_val + normalized * (max_val - min_val);
    }

    // Draw slider track
    const track_rect = Rect{
        .x = rect.x + 5,
        .y = rect.y + rect.height / 2 - 2,
        .width = rect.width - 10,
        .height = 4,
    };
    ctx.renderer.drawRect(track_rect, Color.rgb(100, 100, 100));

    // Draw slider handle
    const normalized_value = (new_value - min_val) / (max_val - min_val);
    const handle_x = track_rect.x + normalized_value * track_rect.width;
    const handle_size: f32 = 12;
    const handle_rect = Rect{
        .x = handle_x - handle_size / 2,
        .y = rect.y + rect.height / 2 - handle_size / 2,
        .width = handle_size,
        .height = handle_size,
    };

    const handle_color = if (ctx.isActive(id))
        Color.rgb(150, 150, 255)
    else if (ctx.isHot(id))
        Color.rgb(200, 200, 255)
    else
        Color.rgb(180, 180, 180);

    ctx.renderer.drawRect(handle_rect, handle_color);
    ctx.renderer.drawRectOutline(handle_rect, Color.rgb(50, 50, 50), 2.0);

    // Draw label above the slider
    if (label_text.len > 0) {
        const label_size: f32 = 12;
        const label_pos = Vec2{
            .x = rect.x,
            .y = rect.y - 4, // Position 4px above slider
        };
        ctx.renderer.drawText(label_text, label_pos, label_size, Color.white);
    }

    return new_value;
}

/// Auto-layout slider
pub fn sliderAuto(ctx: *Context, label_text: []const u8, width: f32, value: f32, min_val: f32, max_val: f32) f32 {
    const height: f32 = 30;
    const label_height: f32 = if (label_text.len > 0) 16 else 0; // 12px text + 4px spacing

    const rect = Rect{
        .x = ctx.cursor.x,
        .y = ctx.cursor.y + label_height,
        .width = width,
        .height = height,
    };

    const new_value = slider(ctx, label_text, rect, value, min_val, max_val);
    ctx.advanceCursor(height + label_height, 5);

    return new_value;
}

/// Text input widget - mutable buffer for text editing
pub fn textInput(ctx: *Context, label_text: []const u8, rect: Rect, buffer: []u8, buffer_len: *usize) void {
    const id = widgetId(label_text);
    const clicked = ctx.registerWidget(id, rect);

    // Focus on click
    const is_focused = ctx.isFocused(id);
    if (clicked) {
        ctx.setFocus(id);
    }

    // Handle text input when focused
    if (is_focused) {
        // Handle character input
        for (ctx.input.text_input) |char| {
            if (buffer_len.* < buffer.len) {
                buffer[buffer_len.*] = char;
                buffer_len.* += 1;
            }
        }

        // Handle special keys
        if (ctx.input.key_backspace) {
            if (buffer_len.* > 0) {
                buffer_len.* -= 1;
            }
        }

        if (ctx.input.key_delete) {
            if (buffer_len.* > 0) {
                buffer_len.* -= 1;
            }
        }

        // TODO: Implement cursor position for proper left/right/home/end support
        // For now, these keys don't have effect without cursor tracking
    }

    // Draw background
    const bg_color = if (is_focused)
        Color.rgb(255, 255, 255)
    else
        Color.rgb(240, 240, 240);
    ctx.renderer.drawRect(rect, bg_color);

    // Draw border
    const border_color = if (is_focused)
        Color.rgb(100, 150, 255)
    else
        Color.rgb(150, 150, 150);
    ctx.renderer.drawRectOutline(rect, border_color, if (is_focused) 2.0 else 1.0);

    // Draw text content
    const text_size: f32 = 16;
    const baseline_offset = ctx.renderer.getBaselineOffset(text_size);
    const text_pos = Vec2{
        .x = rect.x + 5,
        .y = rect.y + rect.height / 2 - baseline_offset,
    };
    const text_to_display = buffer[0..buffer_len.*];
    ctx.renderer.drawText(text_to_display, text_pos, text_size, Color.black);

    // Draw cursor when focused
    if (is_focused) {
        const text_bounds = ctx.renderer.measureText(text_to_display, text_size);
        const cursor_x = text_pos.x + text_bounds.x + 2;
        // Cursor should span from top of text to baseline (not below baseline)
        // Text baseline is at text_pos.y, and text extends upward by approximately text_size
        const cursor_rect = Rect{
            .x = cursor_x,
            .y = text_pos.y - text_size * 0.75, // Start above baseline
            .width = 2,
            .height = text_size * 0.9, // Height to cover text area
        };
        ctx.renderer.drawRect(cursor_rect, Color.black);
    }

    // Draw label above the input
    if (label_text.len > 0) {
        const label_size: f32 = 12;
        const label_pos = Vec2{
            .x = rect.x,
            .y = rect.y - 4,
        };
        ctx.renderer.drawText(label_text, label_pos, label_size, Color.white);
    }
}

/// Auto-layout text input
pub fn textInputAuto(ctx: *Context, label_text: []const u8, width: f32, buffer: []u8, buffer_len: *usize) void {
    const height: f32 = 30;
    const label_height: f32 = if (label_text.len > 0) 16 else 0; // 12px text + 4px spacing

    const rect = Rect{
        .x = ctx.cursor.x,
        .y = ctx.cursor.y + label_height,
        .width = width,
        .height = height,
    };

    textInput(ctx, label_text, rect, buffer, buffer_len);
    ctx.advanceCursor(height + label_height, 5);
}
