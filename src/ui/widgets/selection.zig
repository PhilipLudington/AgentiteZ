const std = @import("std");
const context_mod = @import("../context.zig");
const types = @import("../types.zig");
const log = @import("../../log.zig");

pub const Context = context_mod.Context;
pub const widgetId = types.widgetId;
pub const Rect = types.Rect;
pub const Vec2 = types.Vec2;
pub const Color = types.Color;

/// Dropdown state (needs to be stored by caller)
pub const DropdownState = struct {
    is_open: bool = false,
    selected_index: usize = 0,
};

/// Dropdown widget
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
        ctx.theme.dropdown_hover
    else
        ctx.theme.dropdown_bg;
    ctx.renderer.drawRect(rect, bg_color);
    ctx.renderer.drawRectOutline(rect, ctx.theme.dropdown_border, 1.0);

    // Draw selected option text
    const text_size = ctx.theme.font_size_normal;
    const baseline_offset = ctx.renderer.getBaselineOffset(text_size);
    const text_pos = Vec2{
        .x = rect.x + 5,
        .y = rect.y + rect.height / 2 - baseline_offset,
    };
    if (state.selected_index < options.len) {
        ctx.renderer.drawText(options[state.selected_index], text_pos, text_size, ctx.theme.dropdown_text);
    }

    // Draw arrow indicator
    const arrow_size: f32 = 8;
    const arrow_x = rect.x + rect.width - arrow_size - 10;
    const arrow_y = rect.y + rect.height / 2;
    const arrow_text = if (state.is_open) "▲" else "▼";
    ctx.renderer.drawText(arrow_text, .{ .x = arrow_x, .y = arrow_y - arrow_size / 2 }, arrow_size, ctx.theme.dropdown_text);

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
        }) catch |err| {
            log.ui.err("Failed to queue dropdown overlay, dropdown will not render: {}", .{err});
        };
    }

    // Draw label above the dropdown
    if (label_text.len > 0) {
        const label_size = ctx.theme.font_size_small;
        const label_pos = Vec2{
            .x = rect.x,
            .y = rect.y - 4,
        };
        ctx.renderer.drawText(label_text, label_pos, label_size, ctx.theme.label_color);
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
    ctx.renderer.drawRect(rect, ctx.theme.list_bg);
    ctx.renderer.drawRectOutline(rect, ctx.theme.list_border, 1.0);

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

    const padding = ctx.theme.widget_padding; // Padding from edges

    // Calculate which items could be visible (for performance optimization)
    const start_index = @as(usize, @intFromFloat(@max(0, state.scroll_offset / item_height)));
    const max_visible = @as(usize, @intFromFloat(@ceil(visible_height / item_height))) + 2; // +2 for partial items
    const end_index = @min(items.len, start_index + max_visible);

    // Enable GPU scissor for proper clipping
    // Extend scissor left to accommodate glyphs with negative x-bearing
    const scissor_left_extension: f32 = 5; // Allow for negative glyph bearings
    const content_area = Rect{
        .x = rect.x + padding - scissor_left_extension,
        .y = rect.y + padding,
        .width = rect.width - (padding * 2) + scissor_left_extension, // Correctly sized width
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
            ctx.theme.list_item_hover
        else if (state.selected_index == i)
            ctx.theme.list_item_selected
        else
            ctx.theme.list_bg;
        ctx.renderer.drawRect(item_rect, item_bg);

        // Draw item text (GPU scissor will clip it)
        const text_size = ctx.theme.font_size_small;
        const baseline_offset = ctx.renderer.getBaselineOffset(text_size);
        const text_x = item_rect.x + 5; // Small padding from left edge
        const text_y = item_rect.y + item_height / 2 - baseline_offset;
        ctx.renderer.drawText(items[i], Vec2.init(text_x, text_y), text_size, ctx.theme.list_text);
    }

    // Draw scrollbar if needed (BEFORE ending scissor so it gets clipped too)
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
        ctx.renderer.drawRect(track_rect, ctx.theme.scrollbar_track);

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
            ctx.theme.scrollbar_thumb_active
        else if (ctx.isHot(thumb_id))
            ctx.theme.scrollbar_thumb_hover
        else
            ctx.theme.scrollbar_thumb;
        ctx.renderer.drawRect(thumb_rect, thumb_color);
    }

    // Flush the batch before ending scissor to ensure scrollbar is clipped
    ctx.renderer.flushBatches();

    // End scissor for scroll list content
    ctx.renderer.endScissor();

    // Draw label above the list
    if (label_text.len > 0) {
        const label_size = ctx.theme.font_size_small;
        const label_pos = Vec2{
            .x = rect.x,
            .y = rect.y - 4,
        };
        ctx.renderer.drawText(label_text, label_pos, label_size, ctx.theme.label_color);
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
            ctx.theme.tab_active
        else if (ctx.isHot(tab_id))
            ctx.theme.tab_hover
        else
            ctx.theme.tab_inactive;

        ctx.renderer.drawRect(tab_rect, bg_color);

        // Draw tab border
        const border_thickness: f32 = if (is_active) ctx.theme.border_thickness else 1.0;
        const border_color = if (is_active)
            ctx.theme.tab_border_active
        else
            ctx.theme.tab_border_inactive;
        ctx.renderer.drawRectOutline(tab_rect, border_color, border_thickness);

        // Draw tab label (centered)
        const text_size = ctx.theme.font_size_small;
        const text_bounds = ctx.renderer.measureText(tab_label, text_size);
        const baseline_offset = ctx.renderer.getBaselineOffset(text_size);
        const text_pos = Vec2{
            .x = tab_x + (tab_width - text_bounds.x) / 2,
            .y = rect.y + tab_height / 2 - baseline_offset,
        };
        const text_color = if (is_active) ctx.theme.tab_text_active else ctx.theme.tab_text_inactive;
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
