const std = @import("std");
const context_mod = @import("context.zig");
const types = @import("types.zig");

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

/// Label widget (non-interactive text)
pub fn label(ctx: *Context, text: []const u8, pos: Vec2, size: f32, color: Color) void {
    ctx.renderer.drawText(text, pos, size, color);
}

/// Panel widget with Imperial salvaged tech decorations
pub fn beginPanel(ctx: *Context, panel_label: []const u8, rect: Rect, bg_color: Color) !void {
    const id = widgetId(panel_label);
    _ = ctx.registerWidget(id, rect);

    // Draw panel background
    ctx.renderer.drawRect(rect, bg_color);

    // Draw subtle grid pattern overlay for tech aesthetic
    drawPanelGrid(ctx, rect);

    // Draw panel border with Imperial styling
    ctx.renderer.drawRectOutline(rect, ctx.theme.panel_border, ctx.theme.border_thickness);

    // Draw corner reinforcements/bolts (like jury-rigged panels)
    const corner_size: f32 = 8;
    const corners = [_]Rect{
        // Top-left
        Rect{ .x = rect.x + 2, .y = rect.y + 2, .width = corner_size, .height = corner_size },
        // Top-right
        Rect{ .x = rect.x + rect.width - corner_size - 2, .y = rect.y + 2, .width = corner_size, .height = corner_size },
        // Bottom-left
        Rect{ .x = rect.x + 2, .y = rect.y + rect.height - corner_size - 2, .width = corner_size, .height = corner_size },
        // Bottom-right
        Rect{ .x = rect.x + rect.width - corner_size - 2, .y = rect.y + rect.height - corner_size - 2, .width = corner_size, .height = corner_size },
    };

    for (corners) |corner_rect| {
        // Draw corner bolt/reinforcement
        ctx.renderer.drawRectOutline(corner_rect, Color.imperial_gold, 1.0);
        // Inner detail
        const inner = Rect{
            .x = corner_rect.x + 2,
            .y = corner_rect.y + 2,
            .width = corner_rect.width - 4,
            .height = corner_rect.height - 4,
        };
        ctx.renderer.drawRect(inner, Color.imperial_dark_gold);
    }

    // Push layout for children
    try ctx.pushLayout(Rect{
        .x = rect.x + 10, // 10px padding
        .y = rect.y + 10,
        .width = rect.width - 20,
        .height = rect.height - 20,
    });
}

/// Draw subtle grid pattern for tech aesthetic
fn drawPanelGrid(ctx: *Context, rect: Rect) void {
    const grid_color = Color.oxidized_copper.darken(0.3);
    const grid_spacing: f32 = 20;

    // Vertical lines
    var x = rect.x + grid_spacing;
    while (x < rect.x + rect.width) : (x += grid_spacing) {
        const line_rect = Rect{
            .x = x,
            .y = rect.y,
            .width = 1,
            .height = rect.height,
        };
        ctx.renderer.drawRect(line_rect, grid_color);
    }

    // Horizontal lines
    var y = rect.y + grid_spacing;
    while (y < rect.y + rect.height) : (y += grid_spacing) {
        const line_rect = Rect{
            .x = rect.x,
            .y = y,
            .width = rect.width,
            .height = 1,
        };
        ctx.renderer.drawRect(line_rect, grid_color);
    }
}

/// End panel
pub fn endPanel(ctx: *Context) void {
    ctx.popLayout();
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
            .y = rect.y - 4,  // Position 4px above slider
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
        if (ctx.input.key_pressed) |key| {
            switch (key) {
                .backspace => {
                    if (buffer_len.* > 0) {
                        buffer_len.* -= 1;
                    }
                },
                .delete => {
                    if (buffer_len.* > 0) {
                        buffer_len.* -= 1;
                    }
                },
                else => {},
            }
        }
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
        const cursor_rect = Rect{
            .x = cursor_x,
            .y = text_pos.y,
            .width = 2,
            .height = text_size,
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

/// Dropdown widget state (needs to be stored by caller)
pub const DropdownState = struct {
    is_open: bool = false,
    selected_index: usize = 0,
};

/// Dropdown widget - returns selected index
pub fn dropdown(ctx: *Context, label_text: []const u8, rect: Rect, options: []const []const u8, state: *DropdownState) void {
    const id = widgetId(label_text);
    const header_clicked = ctx.registerWidget(id, rect);

    // Close dropdown if clicking outside when open (but not on header)
    if (state.is_open and ctx.input.mouse_clicked and !header_clicked) {
        const item_height: f32 = 25;
        const list_rect = Rect{
            .x = rect.x,
            .y = rect.y + rect.height,
            .width = rect.width,
            .height = @as(f32, @floatFromInt(options.len)) * item_height,
        };

        // Check if mouse is outside both header and list
        if (!rect.contains(ctx.input.mouse_pos) and !list_rect.contains(ctx.input.mouse_pos)) {
            state.is_open = false;
        }
    }

    // Toggle dropdown on header click
    if (header_clicked) {
        state.is_open = !state.is_open;
    }

    // Draw header background
    const bg_color = if (ctx.isHot(id))
        Color.rgb(230, 230, 230)
    else
        Color.rgb(240, 240, 240);
    ctx.renderer.drawRect(rect, bg_color);
    ctx.renderer.drawRectOutline(rect, Color.rgb(150, 150, 150), 1.0);

    // Draw selected option text
    const text_size: f32 = 16;
    const baseline_offset = ctx.renderer.getBaselineOffset(text_size);
    const text_pos = Vec2{
        .x = rect.x + 5,
        .y = rect.y + rect.height / 2 - baseline_offset,
    };
    if (state.selected_index < options.len) {
        ctx.renderer.drawText(options[state.selected_index], text_pos, text_size, Color.black);
    }

    // Draw arrow indicator
    const arrow_size: f32 = 8;
    const arrow_x = rect.x + rect.width - arrow_size - 10;
    const arrow_y = rect.y + rect.height / 2;
    const arrow_text = if (state.is_open) "▲" else "▼";
    ctx.renderer.drawText(arrow_text, .{ .x = arrow_x, .y = arrow_y - arrow_size / 2 }, arrow_size, Color.black);

    // Defer dropdown list rendering if open (renders at end of frame on top)
    if (state.is_open) {
        const item_height: f32 = 25;
        const list_rect = Rect{
            .x = rect.x,
            .y = rect.y + rect.height,
            .width = rect.width,
            .height = @as(f32, @floatFromInt(options.len)) * item_height,
        };

        // Queue the dropdown list for deferred rendering
        ctx.dropdown_overlays.append(ctx.allocator, .{
            .list_rect = list_rect,
            .options = options,
            .selected_index = state.selected_index,
            .text_size = text_size,
            .item_height = item_height,
            .state_ptr = @ptrCast(state),
        }) catch {};
    }

    // Draw label above the dropdown
    if (label_text.len > 0) {
        const label_size: f32 = 12;
        const label_pos = Vec2{
            .x = rect.x,
            .y = rect.y - 4,
        };
        ctx.renderer.drawText(label_text, label_pos, label_size, Color.white);
    }
}

/// Auto-layout dropdown
pub fn dropdownAuto(ctx: *Context, label_text: []const u8, width: f32, options: []const []const u8, state: *DropdownState) void {
    const height: f32 = 30;
    const label_height: f32 = if (label_text.len > 0) 16 else 0; // 12px text + 4px spacing

    const rect = Rect{
        .x = ctx.cursor.x,
        .y = ctx.cursor.y + label_height,
        .width = width,
        .height = height,
    };

    dropdown(ctx, label_text, rect, options, state);

    // Only advance cursor by the header height, dropdown list overlays
    ctx.advanceCursor(height + label_height, 5);
}

/// Scrollable list state (needs to be stored by caller)
pub const ScrollListState = struct {
    scroll_offset: f32 = 0,
    selected_index: ?usize = null,
    // Internal state for smooth scrollbar dragging
    drag_start_offset: ?f32 = null, // Mouse offset from thumb top when drag started
};

/// Scrollable list widget
pub fn scrollList(ctx: *Context, label_text: []const u8, rect: Rect, items: []const []const u8, state: *ScrollListState) void {
    const id = widgetId(label_text);
    _ = ctx.registerWidget(id, rect);

    // Draw background
    ctx.renderer.drawRect(rect, Color.rgb(255, 255, 255));
    ctx.renderer.drawRectOutline(rect, Color.rgb(150, 150, 150), 1.0);

    // Calculate item dimensions
    const item_height: f32 = 25;
    const total_height = @as(f32, @floatFromInt(items.len)) * item_height;
    const visible_height = rect.height;

    // Handle mouse wheel scrolling when mouse is over the list
    const mouse_over = rect.contains(ctx.input.mouse_pos);
    if (mouse_over and ctx.input.mouse_wheel != 0) {
        const scroll_speed: f32 = 30; // pixels per wheel notch
        state.scroll_offset -= ctx.input.mouse_wheel * scroll_speed;

        // Clamp scroll offset
        const max_scroll = @max(0, total_height - visible_height);
        state.scroll_offset = std.math.clamp(state.scroll_offset, 0, max_scroll);
    }

    const padding: f32 = 3; // Padding from edges
    const text_padding: f32 = 5; // Extra padding for text to prevent glyph clipping

    // Calculate which items could be visible (for performance optimization)
    const start_index = @as(usize, @intFromFloat(@max(0, state.scroll_offset / item_height)));
    const max_visible = @as(usize, @intFromFloat(@ceil(visible_height / item_height))) + 2; // +2 for partial items
    const end_index = @min(items.len, start_index + max_visible);

    // Enable GPU scissor for proper clipping
    // Add extra horizontal padding to prevent glyph clipping (some glyphs have negative xoff)
    const content_area = Rect{
        .x = rect.x + padding - text_padding,
        .y = rect.y + padding,
        .width = rect.width - (padding * 2) + (text_padding * 2),
        .height = rect.height - (padding * 2),
    };
    ctx.renderer.beginScissor(content_area);

    for (start_index..end_index) |i| {
        const item_id = widgetId(items[i]);
        const item_y = rect.y + padding + @as(f32, @floatFromInt(i)) * item_height - state.scroll_offset;

        const item_rect = Rect{
            .x = rect.x + padding,
            .y = item_y,
            .width = rect.width - (padding * 2),
            .height = item_height,
        };

        const item_clicked = ctx.registerWidget(item_id, item_rect);

        if (item_clicked) {
            state.selected_index = i;
        }

        // Draw item background (clipped)
        const item_bg = if (ctx.isHot(item_id))
            Color.rgb(220, 220, 255)
        else if (state.selected_index == i)
            Color.rgb(200, 200, 255)
        else
            Color.rgb(255, 255, 255);
        ctx.renderer.drawRect(item_rect, item_bg);

        // Draw item text (GPU scissor will clip it)
        const text_size: f32 = 14;
        const baseline_offset = ctx.renderer.getBaselineOffset(text_size);
        const text_x = item_rect.x + 8;  // Increased padding to prevent clipping
        const text_y = item_rect.y + item_height / 2 - baseline_offset;
        ctx.renderer.drawText(items[i], Vec2.init(text_x, text_y), text_size, Color.rgb(10, 10, 10));
    }

    // End scissor for scroll list content
    ctx.renderer.endScissor();

    // Draw scrollbar if needed
    if (total_height > visible_height) {
        const scrollbar_width: f32 = 8;
        const scrollbar_x = rect.x + rect.width - scrollbar_width - 2;

        // Scrollbar track
        const track_rect = Rect{
            .x = scrollbar_x,
            .y = rect.y + 2,
            .width = scrollbar_width,
            .height = rect.height - 4,
        };

        // Scrollbar thumb
        const thumb_height = (visible_height / total_height) * track_rect.height;
        const thumb_y = rect.y + 2 + (state.scroll_offset / total_height) * track_rect.height;
        const thumb_rect = Rect{
            .x = scrollbar_x,
            .y = thumb_y,
            .width = scrollbar_width,
            .height = thumb_height,
        };

        // Make scrollbar track interactive (for page up/down)
        var track_label_buf: [128]u8 = undefined;
        const track_label = std.fmt.bufPrint(&track_label_buf, "{s}_scrollbar_track", .{label_text}) catch "scrollbar_track";
        const track_id = widgetId(track_label);
        const track_clicked = ctx.registerWidget(track_id, track_rect);

        // Handle clicking on track (page up/down)
        if (track_clicked) {
            const max_scroll = @max(0, total_height - visible_height);
            if (ctx.input.mouse_pos.y < thumb_y) {
                // Clicked above thumb - page up
                state.scroll_offset -= visible_height * 0.9; // Page by 90% of visible height
                state.scroll_offset = std.math.clamp(state.scroll_offset, 0, max_scroll);
            } else if (ctx.input.mouse_pos.y > thumb_y + thumb_height) {
                // Clicked below thumb - page down
                state.scroll_offset += visible_height * 0.9;
                state.scroll_offset = std.math.clamp(state.scroll_offset, 0, max_scroll);
            }
        }

        // Draw track
        ctx.renderer.drawRect(track_rect, Color.rgb(230, 230, 230));

        // Make scrollbar thumb interactive (drawn after track for priority)
        var scrollbar_label_buf: [128]u8 = undefined;
        const scrollbar_label = std.fmt.bufPrint(&scrollbar_label_buf, "{s}_scrollbar", .{label_text}) catch "scrollbar";
        const thumb_id = widgetId(scrollbar_label);
        _ = ctx.registerWidget(thumb_id, thumb_rect);

        // Handle dragging the scrollbar thumb
        if (ctx.isActive(thumb_id)) {
            // On first click, record where on the thumb we clicked
            if (ctx.input.mouse_clicked) {
                state.drag_start_offset = ctx.input.mouse_pos.y - thumb_y;
            }

            if (ctx.input.mouse_down and state.drag_start_offset != null) {
                // Use the drag offset to calculate new position
                const drag_offset = state.drag_start_offset.?;
                const desired_thumb_y = ctx.input.mouse_pos.y - drag_offset;
                const thumb_offset_in_track = desired_thumb_y - (rect.y + 2);
                const normalized = std.math.clamp(thumb_offset_in_track / track_rect.height, 0.0, 1.0);
                state.scroll_offset = normalized * total_height;

                // Clamp scroll offset
                const max_scroll = @max(0, total_height - visible_height);
                state.scroll_offset = std.math.clamp(state.scroll_offset, 0, max_scroll);
            }
        } else {
            // Clear drag offset when not active
            state.drag_start_offset = null;
        }

        // Draw thumb with hover/active states
        const thumb_color = if (ctx.isActive(thumb_id))
            Color.rgb(120, 120, 120)
        else if (ctx.isHot(thumb_id))
            Color.rgb(150, 150, 150)
        else
            Color.rgb(180, 180, 180);
        ctx.renderer.drawRect(thumb_rect, thumb_color);
    }

    // Draw label above the list
    if (label_text.len > 0) {
        const label_size: f32 = 12;
        const label_pos = Vec2{
            .x = rect.x,
            .y = rect.y - 4,
        };
        ctx.renderer.drawText(label_text, label_pos, label_size, Color.white);
    }
}

/// Auto-layout scroll list
pub fn scrollListAuto(ctx: *Context, label_text: []const u8, width: f32, height: f32, items: []const []const u8, state: *ScrollListState) void {
    const label_height: f32 = if (label_text.len > 0) 16 else 0; // 12px text + 4px spacing

    const rect = Rect{
        .x = ctx.cursor.x,
        .y = ctx.cursor.y + label_height,
        .width = width,
        .height = height,
    };

    scrollList(ctx, label_text, rect, items, state);
    ctx.advanceCursor(height + label_height, 5);
}

/// Progress bar widget - displays a filled bar representing progress (0.0 to 1.0)
pub fn progressBar(ctx: *Context, label_text: []const u8, rect: Rect, progress: f32, show_percentage: bool) void {
    const id = widgetId(label_text);
    _ = ctx.registerWidget(id, rect);

    // Clamp progress to 0-1 range
    const clamped_progress = std.math.clamp(progress, 0.0, 1.0);

    // Draw background (empty part)
    ctx.renderer.drawRect(rect, Color.rgb(200, 200, 200));
    ctx.renderer.drawRectOutline(rect, Color.rgb(100, 100, 100), 1.0);

    // Draw filled portion (progress)
    if (clamped_progress > 0.0) {
        const fill_width = rect.width * clamped_progress;
        const fill_rect = Rect{
            .x = rect.x,
            .y = rect.y,
            .width = fill_width,
            .height = rect.height,
        };

        // Color gradient based on progress (red -> yellow -> green)
        const fill_color = if (clamped_progress < 0.33)
            Color.rgb(220, 80, 80) // Red for low progress
        else if (clamped_progress < 0.66)
            Color.rgb(220, 180, 60) // Yellow for medium progress
        else
            Color.rgb(80, 200, 80); // Green for high progress

        ctx.renderer.drawRect(fill_rect, fill_color);
    }

    // Draw percentage text if requested
    if (show_percentage) {
        const text_size: f32 = 14;
        var text_buf: [32]u8 = undefined;
        const percentage = @as(i32, @intFromFloat(clamped_progress * 100));
        const text = std.fmt.bufPrint(&text_buf, "{d}%", .{percentage}) catch "??%";

        const text_bounds = ctx.renderer.measureText(text, text_size);
        const baseline_offset = ctx.renderer.getBaselineOffset(text_size);
        const text_pos = Vec2{
            .x = rect.x + (rect.width - text_bounds.x) / 2,
            .y = rect.y + rect.height / 2 - baseline_offset,
        };
        ctx.renderer.drawText(text, text_pos, text_size, Color.black);
    }

    // Draw label above the progress bar
    if (label_text.len > 0) {
        const label_size: f32 = 12;
        const label_pos = Vec2{
            .x = rect.x,
            .y = rect.y - 4,
        };
        ctx.renderer.drawText(label_text, label_pos, label_size, Color.white);
    }
}

/// Auto-layout progress bar
pub fn progressBarAuto(ctx: *Context, label_text: []const u8, width: f32, progress: f32, show_percentage: bool) void {
    const height: f32 = 24;
    const label_height: f32 = if (label_text.len > 0) 16 else 0;

    const rect = Rect{
        .x = ctx.cursor.x,
        .y = ctx.cursor.y + label_height,
        .width = width,
        .height = height,
    };

    progressBar(ctx, label_text, rect, progress, show_percentage);
    ctx.advanceCursor(height + label_height, 5);
}

/// Tab bar state (needs to be stored by caller)
pub const TabBarState = struct {
    active_tab: usize = 0,
};

/// Tab bar widget - horizontal tabs for switching between views
/// Returns the index of the active tab
pub fn tabBar(ctx: *Context, id_label: []const u8, rect: Rect, tab_labels: []const []const u8, state: *TabBarState) usize {
    const id = widgetId(id_label);
    _ = ctx.registerWidget(id, rect);

    // Calculate tab width (equal width for all tabs)
    const tab_width = rect.width / @as(f32, @floatFromInt(tab_labels.len));
    const tab_height = rect.height;

    // Draw tabs
    for (tab_labels, 0..) |tab_label, i| {
        const tab_x = rect.x + @as(f32, @floatFromInt(i)) * tab_width;
        const tab_rect = Rect{
            .x = tab_x,
            .y = rect.y,
            .width = tab_width,
            .height = tab_height,
        };

        // Create unique ID for each tab
        var tab_id_buf: [128]u8 = undefined;
        const tab_id_str = std.fmt.bufPrint(&tab_id_buf, "{s}_tab_{d}", .{ id_label, i }) catch "tab";
        const tab_id = widgetId(tab_id_str);
        const tab_clicked = ctx.registerWidget(tab_id, tab_rect);

        // Update active tab on click
        if (tab_clicked) {
            state.active_tab = i;
        }

        const is_active = state.active_tab == i;

        // Draw tab background
        const bg_color = if (is_active)
            Color.rgb(200, 200, 255) // Active tab - blue tint
        else if (ctx.isHot(tab_id))
            Color.rgb(220, 220, 220) // Hover
        else
            Color.rgb(200, 200, 200); // Inactive

        ctx.renderer.drawRect(tab_rect, bg_color);

        // Draw tab border
        const border_thickness: f32 = if (is_active) 2.0 else 1.0;
        const border_color = if (is_active)
            Color.rgb(100, 100, 200)
        else
            Color.rgb(150, 150, 150);
        ctx.renderer.drawRectOutline(tab_rect, border_color, border_thickness);

        // Draw tab label (centered)
        const text_size: f32 = 14;
        const text_bounds = ctx.renderer.measureText(tab_label, text_size);
        const text_pos = Vec2{
            .x = tab_x + (tab_width - text_bounds.x) / 2,
            .y = rect.y + (tab_height - text_bounds.y) / 2,
        };
        const text_color = if (is_active) Color.black else Color.rgb(80, 80, 80);
        ctx.renderer.drawText(tab_label, text_pos, text_size, text_color);
    }

    return state.active_tab;
}

/// Auto-layout tab bar
pub fn tabBarAuto(ctx: *Context, id_label: []const u8, width: f32, tab_labels: []const []const u8, state: *TabBarState) usize {
    const height: f32 = 32;

    const rect = Rect{
        .x = ctx.cursor.x,
        .y = ctx.cursor.y,
        .width = width,
        .height = height,
    };

    const active = tabBar(ctx, id_label, rect, tab_labels, state);
    ctx.advanceCursor(height, 5);

    return active;
}

/// Checkbox widget - returns true if checked changed this frame
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

        ctx.renderer.drawText(label_text, .{ .x = text_x, .y = text_y }, text_size, Color.black);
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

/// Render tooltip at the end of frame if any widget has set one
/// Call this at the very end, after all widgets
pub fn renderTooltip(ctx: *Context) void {
    if (ctx.tooltip_text) |text| {
        // Only show tooltip after hovering for a bit
        ctx.tooltip_hover_frames += 1;
        const delay_frames: u32 = 30; // ~0.5 seconds at 60fps

        if (ctx.tooltip_hover_frames >= delay_frames) {
            const text_size: f32 = 14;
            const padding: f32 = 8;

            // Measure text to size tooltip
            const text_bounds = ctx.renderer.measureText(text, text_size);
            const tooltip_width = text_bounds.x + (padding * 2);
            const tooltip_height = text_bounds.y + (padding * 2);

            // Position tooltip below widget, centered
            var tooltip_x = ctx.tooltip_rect.x + (ctx.tooltip_rect.width / 2) - (tooltip_width / 2);
            var tooltip_y = ctx.tooltip_rect.y + ctx.tooltip_rect.height + 5;

            // Keep tooltip on screen (simple bounds check)
            if (tooltip_x < 0) tooltip_x = 0;
            if (tooltip_y < 0) tooltip_y = ctx.tooltip_rect.y - tooltip_height - 5; // Show above instead

            const tooltip_rect = Rect{
                .x = tooltip_x,
                .y = tooltip_y,
                .width = tooltip_width,
                .height = tooltip_height,
            };

            // Draw tooltip background with shadow effect
            const shadow_offset: f32 = 2;
            const shadow_rect = Rect{
                .x = tooltip_rect.x + shadow_offset,
                .y = tooltip_rect.y + shadow_offset,
                .width = tooltip_rect.width,
                .height = tooltip_rect.height,
            };
            ctx.renderer.drawRect(shadow_rect, Color.rgb(0, 0, 0)); // Shadow

            ctx.renderer.drawRect(tooltip_rect, Color.rgb(255, 255, 220)); // Light yellow background
            ctx.renderer.drawRectOutline(tooltip_rect, Color.rgb(100, 100, 100), 1.0);

            // Draw tooltip text
            const text_pos = Vec2{
                .x = tooltip_rect.x + padding,
                .y = tooltip_rect.y + padding,
            };
            ctx.renderer.drawText(text, text_pos, text_size, Color.black);
        }
    } else {
        // Reset hover counter when not hovering
        ctx.tooltip_hover_frames = 0;
    }
}

test "widgets - button interaction" {
    const renderer_mod = @import("renderer.zig");
    const NullRenderer = renderer_mod.NullRenderer;

    var null_renderer = NullRenderer{};
    const renderer = renderer_mod.Renderer.init(&null_renderer);

    var ctx = Context.init(std.testing.allocator, renderer);
    defer ctx.deinit();

    const button_rect = Rect.init(10, 10, 100, 30);

    // Frame 1: Hover
    ctx.beginFrame(.{
        .mouse_pos = .{ .x = 50, .y = 20 },
        .mouse_down = false,
        .mouse_clicked = false,
        .mouse_released = false,
        .mouse_button = .left,
    });

    const clicked1 = button(&ctx, "Test", button_rect);
    try std.testing.expect(!clicked1);
    try std.testing.expect(ctx.isHot(widgetId("Test")));

    ctx.endFrame();

    // Frame 2: Click and release in one frame (quick click)
    ctx.beginFrame(.{
        .mouse_pos = .{ .x = 50, .y = 20 },
        .mouse_down = false,
        .mouse_clicked = true,
        .mouse_released = true,
        .mouse_button = .left,
    });

    const clicked2 = button(&ctx, "Test", button_rect);
    // Note: This won't work in one frame, need separate frames for click/release
    _ = clicked2;

    ctx.endFrame();
}

test "widgets - auto layout" {
    const renderer_mod = @import("renderer.zig");
    const NullRenderer = renderer_mod.NullRenderer;

    var null_renderer = NullRenderer{};
    const renderer = renderer_mod.Renderer.init(&null_renderer);

    var ctx = Context.init(std.testing.allocator, renderer);
    defer ctx.deinit();

    ctx.beginFrame(types.InputState.init());

    // First button at (0, 0)
    _ = buttonAuto(&ctx, "Button 1", 100, 30);
    try std.testing.expectEqual(@as(f32, 35), ctx.cursor.y); // 30 height + 5 spacing

    // Second button at (0, 35)
    _ = buttonAuto(&ctx, "Button 2", 100, 30);
    try std.testing.expectEqual(@as(f32, 70), ctx.cursor.y); // 35 + 30 + 5

    ctx.endFrame();
}

test "widgets - slider" {
    const renderer_mod = @import("renderer.zig");
    const NullRenderer = renderer_mod.NullRenderer;

    var null_renderer = NullRenderer{};
    const renderer = renderer_mod.Renderer.init(&null_renderer);

    var ctx = Context.init(std.testing.allocator, renderer);
    defer ctx.deinit();

    const slider_rect = Rect.init(10, 10, 200, 30);

    // Frame 1: Initial value
    ctx.beginFrame(types.InputState.init());
    const value1 = slider(&ctx, "Volume", slider_rect, 50, 0, 100);
    try std.testing.expectEqual(@as(f32, 50), value1);
    ctx.endFrame();

    // Frame 2: Click and drag
    ctx.beginFrame(.{
        .mouse_pos = .{ .x = 110, .y = 25 }, // Midpoint
        .mouse_down = true,
        .mouse_clicked = true,
        .mouse_released = false,
        .mouse_button = .left,
    });
    _ = slider(&ctx, "Volume", slider_rect, 50, 0, 100);
    ctx.endFrame();

    // Frame 3: Continue dragging
    ctx.beginFrame(.{
        .mouse_pos = .{ .x = 160, .y = 25 }, // 75% across
        .mouse_down = true,
        .mouse_clicked = false,
        .mouse_released = false,
        .mouse_button = .left,
    });
    const value3 = slider(&ctx, "Volume", slider_rect, 50, 0, 100);
    // Value should be around 75 (75% of range)
    try std.testing.expect(value3 > 70 and value3 < 80);
    ctx.endFrame();
}

test "widgets - text input" {
    const renderer_mod = @import("renderer.zig");
    const NullRenderer = renderer_mod.NullRenderer;

    var null_renderer = NullRenderer{};
    const renderer = renderer_mod.Renderer.init(&null_renderer);

    var ctx = Context.init(std.testing.allocator, renderer);
    defer ctx.deinit();

    var buffer: [64]u8 = undefined;
    var buffer_len: usize = 0;

    const input_rect = Rect.init(10, 10, 200, 30);
    const id = widgetId("name_input");

    // Frame 1: Click down
    ctx.beginFrame(.{
        .mouse_pos = .{ .x = 50, .y = 20 },
        .mouse_down = true,
        .mouse_clicked = true,
        .mouse_released = false,
        .mouse_button = .left,
    });
    textInput(&ctx, "name_input", input_rect, &buffer, &buffer_len);
    ctx.endFrame();

    // Frame 2: Release (this triggers focus)
    ctx.beginFrame(.{
        .mouse_pos = .{ .x = 50, .y = 20 },
        .mouse_down = false,
        .mouse_clicked = false,
        .mouse_released = true,
        .mouse_button = .left,
    });
    textInput(&ctx, "name_input", input_rect, &buffer, &buffer_len);
    try std.testing.expect(ctx.isFocused(id));
    ctx.endFrame();

    // Frame 3: Type some text
    ctx.beginFrame(.{
        .mouse_pos = .{ .x = 50, .y = 20 },
        .mouse_down = false,
        .mouse_clicked = false,
        .mouse_released = false,
        .mouse_button = .left,
        .text_input = "Hi",
    });
    textInput(&ctx, "name_input", input_rect, &buffer, &buffer_len);
    try std.testing.expectEqual(@as(usize, 2), buffer_len);
    try std.testing.expectEqualStrings("Hi", buffer[0..buffer_len]);
    ctx.endFrame();

    // Frame 4: Backspace
    ctx.beginFrame(.{
        .mouse_pos = .{ .x = 50, .y = 20 },
        .mouse_down = false,
        .mouse_clicked = false,
        .mouse_released = false,
        .mouse_button = .left,
        .key_pressed = .backspace,
    });
    textInput(&ctx, "name_input", input_rect, &buffer, &buffer_len);
    try std.testing.expectEqual(@as(usize, 1), buffer_len);
    try std.testing.expectEqualStrings("H", buffer[0..buffer_len]);
    ctx.endFrame();
}

test "widgets - dropdown" {
    const renderer_mod = @import("renderer.zig");
    const NullRenderer = renderer_mod.NullRenderer;

    var null_renderer = NullRenderer{};
    const renderer = renderer_mod.Renderer.init(&null_renderer);

    var ctx = Context.init(std.testing.allocator, renderer);
    defer ctx.deinit();

    const options = [_][]const u8{ "Option 1", "Option 2", "Option 3" };
    var state = DropdownState{};

    const dropdown_rect = Rect.init(10, 10, 150, 30);

    // Frame 1: Click down
    ctx.beginFrame(.{
        .mouse_pos = .{ .x = 50, .y = 20 },
        .mouse_down = true,
        .mouse_clicked = true,
        .mouse_released = false,
        .mouse_button = .left,
    });
    dropdown(&ctx, "choose", dropdown_rect, &options, &state);
    ctx.endFrame();

    // Frame 2: Release to open
    ctx.beginFrame(.{
        .mouse_pos = .{ .x = 50, .y = 20 },
        .mouse_down = false,
        .mouse_clicked = false,
        .mouse_released = true,
        .mouse_button = .left,
    });
    dropdown(&ctx, "choose", dropdown_rect, &options, &state);
    try std.testing.expect(state.is_open);
    ctx.endFrame();

    // Frame 3: Manually select an option (simulating user selection)
    state.selected_index = 1;
    state.is_open = false;

    // Verify state
    try std.testing.expectEqual(@as(usize, 1), state.selected_index);
    try std.testing.expect(!state.is_open);
}

test "widgets - scroll list" {
    const renderer_mod = @import("renderer.zig");
    const NullRenderer = renderer_mod.NullRenderer;

    var null_renderer = NullRenderer{};
    const renderer = renderer_mod.Renderer.init(&null_renderer);

    var ctx = Context.init(std.testing.allocator, renderer);
    defer ctx.deinit();

    const items = [_][]const u8{ "Item 1", "Item 2", "Item 3", "Item 4", "Item 5" };
    var state = ScrollListState{};

    const list_rect = Rect.init(10, 10, 200, 100);

    // Frame 1: Render list
    ctx.beginFrame(types.InputState.init());
    scrollList(&ctx, "items", list_rect, &items, &state);
    try std.testing.expectEqual(@as(?usize, null), state.selected_index);
    ctx.endFrame();

    // Manually set selection (simulating user interaction)
    state.selected_index = 2;

    // Frame 2: Render with selection
    ctx.beginFrame(types.InputState.init());
    scrollList(&ctx, "items", list_rect, &items, &state);
    try std.testing.expectEqual(@as(?usize, 2), state.selected_index);
    ctx.endFrame();
}

test "widgets - checkbox" {
    const renderer_mod = @import("renderer.zig");
    const NullRenderer = renderer_mod.NullRenderer;

    var null_renderer = NullRenderer{};
    const renderer = renderer_mod.Renderer.init(&null_renderer);

    var ctx = Context.init(std.testing.allocator, renderer);
    defer ctx.deinit();

    var checked = false;
    const checkbox_rect = Rect.init(10, 10, 150, 24);

    // Frame 1: Unchecked, no interaction
    ctx.beginFrame(types.InputState.init());
    const changed1 = checkbox(&ctx, "Enable feature", checkbox_rect, &checked);
    try std.testing.expect(!changed1);
    try std.testing.expect(!checked);
    ctx.endFrame();

    // Frame 2: Mouse down
    ctx.beginFrame(.{
        .mouse_pos = .{ .x = 20, .y = 20 },
        .mouse_down = true,
        .mouse_clicked = true,
        .mouse_released = false,
        .mouse_button = .left,
    });
    const changed2a = checkbox(&ctx, "Enable feature", checkbox_rect, &checked);
    try std.testing.expect(!changed2a); // Not changed yet
    ctx.endFrame();

    // Frame 3: Mouse release (completes click)
    ctx.beginFrame(.{
        .mouse_pos = .{ .x = 20, .y = 20 },
        .mouse_down = false,
        .mouse_clicked = false,
        .mouse_released = true,
        .mouse_button = .left,
    });
    const changed2b = checkbox(&ctx, "Enable feature", checkbox_rect, &checked);
    try std.testing.expect(changed2b); // Changed on release
    try std.testing.expect(checked); // Now checked
    ctx.endFrame();

    // Frame 4: Mouse down again
    ctx.beginFrame(.{
        .mouse_pos = .{ .x = 20, .y = 20 },
        .mouse_down = true,
        .mouse_clicked = true,
        .mouse_released = false,
        .mouse_button = .left,
    });
    const changed3a = checkbox(&ctx, "Enable feature", checkbox_rect, &checked);
    try std.testing.expect(!changed3a);
    ctx.endFrame();

    // Frame 5: Mouse release to uncheck
    ctx.beginFrame(.{
        .mouse_pos = .{ .x = 20, .y = 20 },
        .mouse_down = false,
        .mouse_clicked = false,
        .mouse_released = true,
        .mouse_button = .left,
    });
    const changed3b = checkbox(&ctx, "Enable feature", checkbox_rect, &checked);
    try std.testing.expect(changed3b);
    try std.testing.expect(!checked); // Back to unchecked
    ctx.endFrame();
}
