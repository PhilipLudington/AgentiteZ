const std = @import("std");
const context_mod = @import("../context.zig");
const types = @import("../types.zig");

pub const Context = context_mod.Context;
pub const widgetId = types.widgetId;
pub const Rect = types.Rect;
pub const Vec2 = types.Vec2;
pub const Color = types.Color;

/// Column alignment options
pub const Alignment = enum {
    left,
    center,
    right,
};

/// Table column definition
pub const TableColumn = struct {
    header: []const u8,
    width: f32 = 100, // Default width
    min_width: f32 = 50, // Minimum width when resizing
    alignment: Alignment = .left,
};

/// Table state (needs to be stored by caller)
pub const TableState = struct {
    scroll_offset: f32 = 0,
    selected_row: ?usize = null,

    // Internal state for scrollbar dragging
    drag_start_offset: ?f32 = null,

    // Internal state for column resizing
    resize_column: ?usize = null,
    resize_start_width: ?f32 = null,
    resize_start_x: ?f32 = null,
};

/// Table widget with headers, scrolling, row selection, and column resizing.
/// Returns the index of a clicked row, or null if no row was clicked.
pub fn table(
    ctx: *Context,
    label_text: []const u8,
    rect: Rect,
    columns: []const TableColumn,
    rows: []const []const []const u8,
    state: *TableState,
    column_widths: []f32, // Mutable widths for resizing
) ?usize {
    const id = widgetId(label_text);
    _ = ctx.registerWidget(id, rect);

    // Constants
    const header_height: f32 = 28;
    const row_height: f32 = 25;
    const padding = ctx.theme.widget_padding;
    const scrollbar_width: f32 = 8;

    // Calculate total content width from columns
    var total_column_width: f32 = 0;
    for (column_widths) |w| {
        total_column_width += w;
    }

    // Calculate content area dimensions
    const content_height = rect.height - header_height;
    const total_rows_height = @as(f32, @floatFromInt(rows.len)) * row_height;
    const needs_scrollbar = total_rows_height > content_height;
    const content_width = if (needs_scrollbar) rect.width - scrollbar_width - 4 else rect.width;

    // Draw table background
    ctx.renderer.drawRect(rect, ctx.theme.list_bg);
    ctx.renderer.drawRectOutline(rect, ctx.theme.list_border, 1.0);

    // ========================================================================
    // Header Row (outside scissor, always visible)
    // ========================================================================
    const header_rect = Rect{
        .x = rect.x,
        .y = rect.y,
        .width = content_width,
        .height = header_height,
    };
    ctx.renderer.drawRect(header_rect, ctx.theme.list_item_selected);

    // Draw header border
    ctx.renderer.drawRectOutline(header_rect, ctx.theme.list_border, 1.0);

    // Draw column headers and resize handles
    var header_x: f32 = rect.x;
    for (columns, 0..) |col, col_idx| {
        const col_width = column_widths[col_idx];

        // Draw header text
        const text_size = ctx.theme.font_size_small;
        const text_bounds = ctx.renderer.measureText(col.header, text_size);
        const baseline_offset = ctx.renderer.getBaselineOffset(text_size);

        const text_x = switch (col.alignment) {
            .left => header_x + padding,
            .center => header_x + (col_width - text_bounds.x) / 2,
            .right => header_x + col_width - text_bounds.x - padding,
        };
        const text_y = rect.y + header_height / 2 - baseline_offset;

        ctx.renderer.drawText(col.header, Vec2.init(text_x, text_y), text_size, ctx.theme.list_text);

        // Draw column separator (except for last column)
        if (col_idx < columns.len - 1) {
            const separator_x = header_x + col_width;
            ctx.renderer.drawRect(Rect{
                .x = separator_x - 0.5,
                .y = rect.y + 2,
                .width = 1,
                .height = header_height - 4,
            }, ctx.theme.list_border);

            // Resize handle (invisible hit area)
            const handle_width: f32 = 8;
            const handle_rect = Rect{
                .x = separator_x - handle_width / 2,
                .y = rect.y,
                .width = handle_width,
                .height = header_height,
            };

            var handle_id_buf: [128]u8 = undefined;
            const handle_id_str = std.fmt.bufPrint(&handle_id_buf, "{s}_resize_{d}", .{ label_text, col_idx }) catch "resize";
            const handle_id = widgetId(handle_id_str);
            _ = ctx.registerWidget(handle_id, handle_rect);

            // Handle column resizing
            if (ctx.isActive(handle_id)) {
                if (ctx.input.mouse_clicked) {
                    state.resize_column = col_idx;
                    state.resize_start_width = col_width;
                    state.resize_start_x = ctx.input.mouse_pos.x;
                }

                if (ctx.input.mouse_down and state.resize_start_x != null) {
                    const delta = ctx.input.mouse_pos.x - state.resize_start_x.?;
                    const new_width = @max(columns[col_idx].min_width, state.resize_start_width.? + delta);
                    column_widths[col_idx] = new_width;
                }
            } else if (state.resize_column == col_idx) {
                // Clear resize state when no longer active
                state.resize_column = null;
                state.resize_start_width = null;
                state.resize_start_x = null;
            }
        }

        header_x += col_width;
    }

    // ========================================================================
    // Handle mouse wheel scrolling
    // ========================================================================
    const content_rect = Rect{
        .x = rect.x,
        .y = rect.y + header_height,
        .width = content_width,
        .height = content_height,
    };
    const mouse_over_content = content_rect.contains(ctx.input.mouse_pos);

    if (mouse_over_content and ctx.input.mouse_wheel != 0) {
        const scroll_speed: f32 = 30;
        state.scroll_offset -= ctx.input.mouse_wheel * scroll_speed;

        const max_scroll = @max(0, total_rows_height - content_height);
        state.scroll_offset = std.math.clamp(state.scroll_offset, 0, max_scroll);
    }

    // ========================================================================
    // Content Area (inside scissor, scrollable)
    // ========================================================================
    const content_area = Rect{
        .x = rect.x + 1,
        .y = rect.y + header_height,
        .width = content_width - 2,
        .height = content_height - 1,
    };

    // Calculate visible rows (virtualization)
    const start_index = @as(usize, @intFromFloat(@max(0, state.scroll_offset / row_height)));
    const max_visible = @as(usize, @intFromFloat(@ceil(content_height / row_height))) + 2;
    const end_index = @min(rows.len, start_index + max_visible);

    ctx.renderer.beginScissor(content_area);

    var clicked_row: ?usize = null;

    for (start_index..end_index) |row_idx| {
        const row_y = rect.y + header_height + @as(f32, @floatFromInt(row_idx)) * row_height - state.scroll_offset;

        const row_rect = Rect{
            .x = rect.x + 1,
            .y = row_y,
            .width = content_width - 2,
            .height = row_height,
        };

        // Create unique row ID
        var row_id_buf: [128]u8 = undefined;
        const row_id_str = std.fmt.bufPrint(&row_id_buf, "{s}_row_{d}", .{ label_text, row_idx }) catch "row";
        const row_id = widgetId(row_id_str);
        const row_clicked = ctx.registerWidget(row_id, row_rect);

        if (row_clicked) {
            state.selected_row = row_idx;
            clicked_row = row_idx;
        }

        // Draw row background
        const is_selected = state.selected_row == row_idx;
        const is_hovered = ctx.isHot(row_id);
        const row_bg = if (is_selected)
            ctx.theme.list_item_selected
        else if (is_hovered)
            ctx.theme.list_item_hover
        else if (row_idx % 2 == 1)
            ctx.theme.list_bg.darken(0.95) // Alternating row color
        else
            ctx.theme.list_bg;

        ctx.renderer.drawRect(row_rect, row_bg);

        // Draw cells
        const row_data = rows[row_idx];
        var cell_x: f32 = rect.x + 1;

        for (columns, 0..) |col, col_idx| {
            const col_width = column_widths[col_idx];
            const cell_text = if (col_idx < row_data.len) row_data[col_idx] else "";

            const text_size = ctx.theme.font_size_small;
            const text_bounds = ctx.renderer.measureText(cell_text, text_size);
            const baseline_offset = ctx.renderer.getBaselineOffset(text_size);

            const text_x = switch (col.alignment) {
                .left => cell_x + padding,
                .center => cell_x + (col_width - text_bounds.x) / 2,
                .right => cell_x + col_width - text_bounds.x - padding,
            };
            const text_y = row_y + row_height / 2 - baseline_offset;

            ctx.renderer.drawText(cell_text, Vec2.init(text_x, text_y), text_size, ctx.theme.list_text);

            cell_x += col_width;
        }
    }

    ctx.renderer.flushBatches();
    ctx.renderer.endScissor();

    // ========================================================================
    // Scrollbar (outside scissor)
    // ========================================================================
    if (needs_scrollbar) {
        const scrollbar_x = rect.x + rect.width - scrollbar_width - 2;

        // Track
        const track_rect = Rect{
            .x = scrollbar_x,
            .y = rect.y + header_height + 2,
            .width = scrollbar_width,
            .height = content_height - 4,
        };

        // Thumb
        const thumb_height = (content_height / total_rows_height) * track_rect.height;
        const thumb_y = track_rect.y + (state.scroll_offset / total_rows_height) * track_rect.height;
        const thumb_rect = Rect{
            .x = scrollbar_x,
            .y = thumb_y,
            .width = scrollbar_width,
            .height = @max(20, thumb_height), // Minimum thumb size
        };

        // Track interaction (page up/down)
        var track_id_buf: [128]u8 = undefined;
        const track_id_str = std.fmt.bufPrint(&track_id_buf, "{s}_scrollbar_track", .{label_text}) catch "track";
        const track_id = widgetId(track_id_str);
        const track_clicked = ctx.registerWidget(track_id, track_rect);

        if (track_clicked) {
            const max_scroll = @max(0, total_rows_height - content_height);
            if (ctx.input.mouse_pos.y < thumb_y) {
                state.scroll_offset -= content_height * 0.9;
            } else if (ctx.input.mouse_pos.y > thumb_y + thumb_rect.height) {
                state.scroll_offset += content_height * 0.9;
            }
            state.scroll_offset = std.math.clamp(state.scroll_offset, 0, max_scroll);
        }

        // Draw track
        ctx.renderer.drawRect(track_rect, ctx.theme.scrollbar_track);

        // Thumb interaction (dragging)
        var thumb_id_buf: [128]u8 = undefined;
        const thumb_id_str = std.fmt.bufPrint(&thumb_id_buf, "{s}_scrollbar", .{label_text}) catch "thumb";
        const thumb_id = widgetId(thumb_id_str);
        _ = ctx.registerWidget(thumb_id, thumb_rect);

        if (ctx.isActive(thumb_id)) {
            if (ctx.input.mouse_clicked) {
                state.drag_start_offset = ctx.input.mouse_pos.y - thumb_y;
            }

            if (ctx.input.mouse_down and state.drag_start_offset != null) {
                const drag_offset = state.drag_start_offset.?;
                const desired_thumb_y = ctx.input.mouse_pos.y - drag_offset;
                const thumb_offset_in_track = desired_thumb_y - track_rect.y;
                const normalized = std.math.clamp(thumb_offset_in_track / track_rect.height, 0.0, 1.0);
                state.scroll_offset = normalized * total_rows_height;

                const max_scroll = @max(0, total_rows_height - content_height);
                state.scroll_offset = std.math.clamp(state.scroll_offset, 0, max_scroll);
            }
        } else {
            state.drag_start_offset = null;
        }

        // Draw thumb with states
        const thumb_color = if (ctx.isActive(thumb_id))
            ctx.theme.scrollbar_thumb_active
        else if (ctx.isHot(thumb_id))
            ctx.theme.scrollbar_thumb_hover
        else
            ctx.theme.scrollbar_thumb;
        ctx.renderer.drawRect(thumb_rect, thumb_color);
    }

    // Draw label above the table
    if (label_text.len > 0) {
        const label_size = ctx.theme.font_size_small;
        const label_pos = Vec2{
            .x = rect.x,
            .y = rect.y - 4,
        };
        ctx.renderer.drawText(label_text, label_pos, label_size, ctx.theme.label_color);
    }

    return clicked_row;
}

/// Auto-layout table widget
pub fn tableAuto(
    ctx: *Context,
    label_text: []const u8,
    width: f32,
    height: f32,
    columns: []const TableColumn,
    rows: []const []const []const u8,
    state: *TableState,
    column_widths: []f32,
) ?usize {
    const label_height: f32 = if (label_text.len > 0) 16 else 0;

    const rect = Rect{
        .x = ctx.cursor.x,
        .y = ctx.cursor.y + label_height,
        .width = width,
        .height = height,
    };

    const result = table(ctx, label_text, rect, columns, rows, state, column_widths);
    ctx.advanceCursor(height + label_height, ctx.theme.widget_spacing);

    return result;
}

// ============================================================================
// Tests
// ============================================================================

test "TableState - default initialization" {
    const state = TableState{};
    try std.testing.expectEqual(@as(f32, 0), state.scroll_offset);
    try std.testing.expectEqual(@as(?usize, null), state.selected_row);
    try std.testing.expectEqual(@as(?f32, null), state.drag_start_offset);
    try std.testing.expectEqual(@as(?usize, null), state.resize_column);
}

test "TableColumn - default values" {
    const col = TableColumn{ .header = "Name" };
    try std.testing.expectEqual(@as(f32, 100), col.width);
    try std.testing.expectEqual(@as(f32, 50), col.min_width);
    try std.testing.expectEqual(Alignment.left, col.alignment);
}

test "TableColumn - custom alignment" {
    const col_left = TableColumn{ .header = "Left", .alignment = .left };
    const col_center = TableColumn{ .header = "Center", .alignment = .center };
    const col_right = TableColumn{ .header = "Right", .alignment = .right };

    try std.testing.expectEqual(Alignment.left, col_left.alignment);
    try std.testing.expectEqual(Alignment.center, col_center.alignment);
    try std.testing.expectEqual(Alignment.right, col_right.alignment);
}

test "widgetId - generates unique IDs for rows" {
    var id_buf1: [128]u8 = undefined;
    var id_buf2: [128]u8 = undefined;

    const id_str1 = std.fmt.bufPrint(&id_buf1, "table_row_{d}", .{0}) catch unreachable;
    const id_str2 = std.fmt.bufPrint(&id_buf2, "table_row_{d}", .{1}) catch unreachable;

    const id1 = widgetId(id_str1);
    const id2 = widgetId(id_str2);

    try std.testing.expect(id1 != id2);
}

test "widgetId - generates unique IDs for resize handles" {
    var id_buf1: [128]u8 = undefined;
    var id_buf2: [128]u8 = undefined;

    const id_str1 = std.fmt.bufPrint(&id_buf1, "table_resize_{d}", .{0}) catch unreachable;
    const id_str2 = std.fmt.bufPrint(&id_buf2, "table_resize_{d}", .{1}) catch unreachable;

    const id1 = widgetId(id_str1);
    const id2 = widgetId(id_str2);

    try std.testing.expect(id1 != id2);
}

test "Alignment - all variants" {
    const alignments = [_]Alignment{ .left, .center, .right };
    try std.testing.expectEqual(@as(usize, 3), alignments.len);
}
