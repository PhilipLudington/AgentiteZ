const std = @import("std");
const context_mod = @import("../context.zig");
const types = @import("../types.zig");

pub const Context = context_mod.Context;
pub const widgetId = types.widgetId;
pub const Rect = types.Rect;
pub const Vec2 = types.Vec2;
pub const Color = types.Color;

/// Maximum number of data points per series
pub const max_data_points = 256;

/// Maximum number of series per chart
pub const max_series = 8;

/// Data series for line and bar charts
pub const Series = struct {
    /// Data points (y values)
    data: []const f32,
    /// Series color
    color: Color,
    /// Optional series name for legend
    name: ?[]const u8 = null,
};

/// Slice of a pie chart
pub const PieSlice = struct {
    /// Value (will be normalized to percentage)
    value: f32,
    /// Slice color
    color: Color,
    /// Optional label
    label: ?[]const u8 = null,
};

/// Chart configuration options
pub const ChartOptions = struct {
    /// Show horizontal grid lines
    show_grid: bool = true,
    /// Show axis labels
    show_labels: bool = true,
    /// Show legend
    show_legend: bool = true,
    /// Show data point markers (for line charts)
    show_markers: bool = true,
    /// Y-axis minimum (null for auto)
    y_min: ?f32 = null,
    /// Y-axis maximum (null for auto)
    y_max: ?f32 = null,
    /// X-axis labels (optional)
    x_labels: ?[]const []const u8 = null,
    /// Title (optional)
    title: ?[]const u8 = null,
    /// Number of grid lines
    grid_lines: u32 = 5,
    /// Bar width ratio (0.0-1.0)
    bar_width_ratio: f32 = 0.8,
    /// Line thickness
    line_thickness: f32 = 2.0,
    /// Marker size
    marker_size: f32 = 4.0,
};

/// Default chart colors (colorblind-friendly palette)
pub const default_colors = [_]Color{
    Color.rgb(66, 133, 244), // Blue
    Color.rgb(234, 67, 53), // Red
    Color.rgb(251, 188, 5), // Yellow
    Color.rgb(52, 168, 83), // Green
    Color.rgb(155, 89, 182), // Purple
    Color.rgb(255, 127, 80), // Coral
    Color.rgb(0, 188, 212), // Cyan
    Color.rgb(255, 152, 0), // Orange
};

// ============================================================================
// Line Chart
// ============================================================================

/// Render a line chart with multiple series
pub fn lineChart(
    ctx: *Context,
    label_text: []const u8,
    rect: Rect,
    series: []const Series,
    options: ChartOptions,
) void {
    const id = widgetId(label_text);
    _ = ctx.registerWidget(id, rect);

    // Calculate chart area (leaving room for labels and legend)
    const chart_area = calculateChartArea(ctx, rect, options);

    // Draw background and border
    ctx.renderer.drawRect(rect, ctx.theme.panel_bg);
    ctx.renderer.drawRectOutline(rect, ctx.theme.panel_border, 1.0);

    // Draw title
    if (options.title) |title| {
        const title_size = ctx.theme.font_size_normal;
        const title_bounds = ctx.renderer.measureText(title, title_size);
        const title_pos = Vec2{
            .x = rect.x + (rect.width - title_bounds.x) / 2,
            .y = rect.y + 4,
        };
        ctx.renderer.drawText(title, title_pos, title_size, ctx.theme.text_primary);
    }

    // Calculate y-axis range
    const y_range = calculateYRange(series, options);

    // Draw grid
    if (options.show_grid) {
        drawGrid(ctx, chart_area, options.grid_lines, y_range, options);
    }

    // Draw each series
    for (series) |s| {
        drawLineSeries(ctx, chart_area, s, y_range, options);
    }

    // Draw legend
    if (options.show_legend and series.len > 0) {
        drawLegend(ctx, rect, series);
    }
}

/// Auto-layout line chart
pub fn lineChartAuto(
    ctx: *Context,
    label_text: []const u8,
    width: f32,
    height: f32,
    series: []const Series,
    options: ChartOptions,
) void {
    const rect = Rect{
        .x = ctx.cursor.x,
        .y = ctx.cursor.y,
        .width = width,
        .height = height,
    };

    lineChart(ctx, label_text, rect, series, options);
    ctx.advanceCursor(height, 5);
}

fn drawLineSeries(ctx: *Context, chart_area: Rect, series: Series, y_range: YRange, options: ChartOptions) void {
    if (series.data.len < 2) return;

    const x_step = chart_area.width / @as(f32, @floatFromInt(series.data.len - 1));

    var prev_x: f32 = chart_area.x;
    var prev_y: f32 = valueToY(series.data[0], chart_area, y_range);

    // Draw line segments
    for (series.data[1..], 1..) |value, i| {
        const curr_x = chart_area.x + x_step * @as(f32, @floatFromInt(i));
        const curr_y = valueToY(value, chart_area, y_range);

        // Draw line segment as thin rectangles (simple approximation)
        drawLine(ctx, prev_x, prev_y, curr_x, curr_y, series.color, options.line_thickness);

        prev_x = curr_x;
        prev_y = curr_y;
    }

    // Draw markers
    if (options.show_markers) {
        for (series.data, 0..) |value, i| {
            const x = chart_area.x + x_step * @as(f32, @floatFromInt(i));
            const y = valueToY(value, chart_area, y_range);
            drawMarker(ctx, x, y, options.marker_size, series.color);
        }
    }
}

// ============================================================================
// Bar Chart
// ============================================================================

/// Render a bar chart with multiple series
pub fn barChart(
    ctx: *Context,
    label_text: []const u8,
    rect: Rect,
    series: []const Series,
    options: ChartOptions,
) void {
    const id = widgetId(label_text);
    _ = ctx.registerWidget(id, rect);

    // Calculate chart area
    const chart_area = calculateChartArea(ctx, rect, options);

    // Draw background and border
    ctx.renderer.drawRect(rect, ctx.theme.panel_bg);
    ctx.renderer.drawRectOutline(rect, ctx.theme.panel_border, 1.0);

    // Draw title
    if (options.title) |title| {
        const title_size = ctx.theme.font_size_normal;
        const title_bounds = ctx.renderer.measureText(title, title_size);
        const title_pos = Vec2{
            .x = rect.x + (rect.width - title_bounds.x) / 2,
            .y = rect.y + 4,
        };
        ctx.renderer.drawText(title, title_pos, title_size, ctx.theme.text_primary);
    }

    // Calculate y-axis range
    const y_range = calculateYRange(series, options);

    // Draw grid
    if (options.show_grid) {
        drawGrid(ctx, chart_area, options.grid_lines, y_range, options);
    }

    // Calculate bar dimensions
    if (series.len == 0) return;
    const max_data_len = maxDataLen(series);
    if (max_data_len == 0) return;

    const group_width = chart_area.width / @as(f32, @floatFromInt(max_data_len));
    const bar_width = (group_width * options.bar_width_ratio) / @as(f32, @floatFromInt(series.len));
    const group_padding = (group_width - bar_width * @as(f32, @floatFromInt(series.len))) / 2;

    // Draw bars
    for (series, 0..) |s, series_idx| {
        for (s.data, 0..) |value, data_idx| {
            const x = chart_area.x + group_width * @as(f32, @floatFromInt(data_idx)) + group_padding + bar_width * @as(f32, @floatFromInt(series_idx));
            const bar_height = (value - y_range.min) / (y_range.max - y_range.min) * chart_area.height;
            const y = chart_area.y + chart_area.height - bar_height;

            const bar_rect = Rect{
                .x = x,
                .y = y,
                .width = bar_width - 1, // Small gap between bars
                .height = bar_height,
            };

            ctx.renderer.drawRect(bar_rect, s.color);
        }
    }

    // Draw x-axis labels
    if (options.show_labels) {
        if (options.x_labels) |labels| {
            const label_size = ctx.theme.font_size_small;
            for (labels, 0..) |label_str, i| {
                if (i >= max_data_len) break;
                const x = chart_area.x + group_width * @as(f32, @floatFromInt(i)) + group_width / 2;
                const label_bounds = ctx.renderer.measureText(label_str, label_size);
                const label_pos = Vec2{
                    .x = x - label_bounds.x / 2,
                    .y = chart_area.y + chart_area.height + 4,
                };
                ctx.renderer.drawText(label_str, label_pos, label_size, ctx.theme.text_secondary);
            }
        }
    }

    // Draw legend
    if (options.show_legend and series.len > 1) {
        drawLegend(ctx, rect, series);
    }
}

/// Auto-layout bar chart
pub fn barChartAuto(
    ctx: *Context,
    label_text: []const u8,
    width: f32,
    height: f32,
    series: []const Series,
    options: ChartOptions,
) void {
    const rect = Rect{
        .x = ctx.cursor.x,
        .y = ctx.cursor.y,
        .width = width,
        .height = height,
    };

    barChart(ctx, label_text, rect, series, options);
    ctx.advanceCursor(height, 5);
}

// ============================================================================
// Pie Chart
// ============================================================================

/// Render a pie chart
pub fn pieChart(
    ctx: *Context,
    label_text: []const u8,
    rect: Rect,
    slices: []const PieSlice,
    options: ChartOptions,
) void {
    const id = widgetId(label_text);
    _ = ctx.registerWidget(id, rect);

    // Draw background and border
    ctx.renderer.drawRect(rect, ctx.theme.panel_bg);
    ctx.renderer.drawRectOutline(rect, ctx.theme.panel_border, 1.0);

    // Draw title
    var title_height: f32 = 0;
    if (options.title) |title| {
        const title_size = ctx.theme.font_size_normal;
        const title_bounds = ctx.renderer.measureText(title, title_size);
        const title_pos = Vec2{
            .x = rect.x + (rect.width - title_bounds.x) / 2,
            .y = rect.y + 4,
        };
        ctx.renderer.drawText(title, title_pos, title_size, ctx.theme.text_primary);
        title_height = title_bounds.y + 8;
    }

    // Calculate pie center and radius
    const legend_width: f32 = if (options.show_legend) 100 else 0;
    const pie_area = Rect{
        .x = rect.x,
        .y = rect.y + title_height,
        .width = rect.width - legend_width,
        .height = rect.height - title_height,
    };

    const center = Vec2{
        .x = pie_area.x + pie_area.width / 2,
        .y = pie_area.y + pie_area.height / 2,
    };
    const radius = @min(pie_area.width, pie_area.height) / 2 - 10;

    // Calculate total value
    var total: f32 = 0;
    for (slices) |slice| {
        total += slice.value;
    }
    if (total == 0) return;

    // Draw pie slices using filled segments
    var start_angle: f32 = -std.math.pi / 2; // Start from top
    for (slices) |slice| {
        const sweep_angle = (slice.value / total) * 2 * std.math.pi;
        drawPieSlice(ctx, center, radius, start_angle, sweep_angle, slice.color);
        start_angle += sweep_angle;
    }

    // Draw legend
    if (options.show_legend) {
        drawPieLegend(ctx, rect, slices, total, legend_width);
    }
}

/// Auto-layout pie chart
pub fn pieChartAuto(
    ctx: *Context,
    label_text: []const u8,
    width: f32,
    height: f32,
    slices: []const PieSlice,
    options: ChartOptions,
) void {
    const rect = Rect{
        .x = ctx.cursor.x,
        .y = ctx.cursor.y,
        .width = width,
        .height = height,
    };

    pieChart(ctx, label_text, rect, slices, options);
    ctx.advanceCursor(height, 5);
}

// ============================================================================
// Helper Functions
// ============================================================================

const YRange = struct {
    min: f32,
    max: f32,
};

fn calculateYRange(series: []const Series, options: ChartOptions) YRange {
    var min_val: f32 = if (options.y_min) |y_min| y_min else std.math.floatMax(f32);
    var max_val: f32 = if (options.y_max) |y_max| y_max else -std.math.floatMax(f32);

    if (options.y_min == null or options.y_max == null) {
        for (series) |s| {
            for (s.data) |value| {
                if (options.y_min == null) min_val = @min(min_val, value);
                if (options.y_max == null) max_val = @max(max_val, value);
            }
        }
    }

    // Add some padding
    if (options.y_min == null and options.y_max == null) {
        const range = max_val - min_val;
        if (range > 0) {
            min_val -= range * 0.05;
            max_val += range * 0.05;
        } else {
            min_val -= 1;
            max_val += 1;
        }
    }

    // Ensure min < max
    if (min_val >= max_val) {
        min_val = 0;
        max_val = 1;
    }

    return .{ .min = min_val, .max = max_val };
}

fn calculateChartArea(ctx: *Context, rect: Rect, options: ChartOptions) Rect {
    var left_margin: f32 = 10;
    const right_margin: f32 = 10;
    var top_margin: f32 = 10;
    var bottom_margin: f32 = 10;

    // Title space
    if (options.title != null) {
        top_margin += ctx.theme.font_size_normal + 4;
    }

    // Y-axis labels
    if (options.show_labels) {
        left_margin += 40; // Space for y-axis labels
        bottom_margin += ctx.theme.font_size_small + 4; // Space for x-axis labels
    }

    // Legend space
    if (options.show_legend) {
        bottom_margin += 20;
    }

    return Rect{
        .x = rect.x + left_margin,
        .y = rect.y + top_margin,
        .width = @max(1, rect.width - left_margin - right_margin),
        .height = @max(1, rect.height - top_margin - bottom_margin),
    };
}

fn valueToY(value: f32, chart_area: Rect, y_range: YRange) f32 {
    const normalized = (value - y_range.min) / (y_range.max - y_range.min);
    return chart_area.y + chart_area.height * (1 - normalized);
}

fn drawGrid(ctx: *Context, chart_area: Rect, grid_lines: u32, y_range: YRange, options: ChartOptions) void {
    const grid_color = ctx.theme.panel_border.lighten(0.3);
    const lines = if (grid_lines == 0) 5 else grid_lines;
    const step = chart_area.height / @as(f32, @floatFromInt(lines));
    const value_step = (y_range.max - y_range.min) / @as(f32, @floatFromInt(lines));

    for (0..lines + 1) |i| {
        const y = chart_area.y + step * @as(f32, @floatFromInt(i));

        // Draw horizontal grid line
        ctx.renderer.drawRect(Rect{
            .x = chart_area.x,
            .y = y,
            .width = chart_area.width,
            .height = 1,
        }, grid_color);

        // Draw y-axis label
        if (options.show_labels) {
            const value = y_range.max - value_step * @as(f32, @floatFromInt(i));
            var buf: [16]u8 = undefined;
            const label_str = formatValue(value, &buf);
            const label_size = ctx.theme.font_size_small;
            const label_bounds = ctx.renderer.measureText(label_str, label_size);
            const label_pos = Vec2{
                .x = chart_area.x - label_bounds.x - 4,
                .y = y - label_bounds.y / 2,
            };
            ctx.renderer.drawText(label_str, label_pos, label_size, ctx.theme.text_secondary);
        }
    }
}

fn drawLegend(ctx: *Context, rect: Rect, series: []const Series) void {
    const legend_y = rect.y + rect.height - 16;
    var legend_x = rect.x + 10;
    const box_size: f32 = 10;
    const label_size = ctx.theme.font_size_small;

    for (series) |s| {
        // Draw color box
        ctx.renderer.drawRect(Rect{
            .x = legend_x,
            .y = legend_y,
            .width = box_size,
            .height = box_size,
        }, s.color);

        legend_x += box_size + 4;

        // Draw label
        if (s.name) |name| {
            ctx.renderer.drawText(name, Vec2{ .x = legend_x, .y = legend_y - 2 }, label_size, ctx.theme.text_secondary);
            const name_bounds = ctx.renderer.measureText(name, label_size);
            legend_x += name_bounds.x + 15;
        }
    }
}

fn drawPieLegend(ctx: *Context, rect: Rect, slices: []const PieSlice, total: f32, legend_width: f32) void {
    const legend_x = rect.x + rect.width - legend_width + 10;
    var legend_y = rect.y + 30;
    const box_size: f32 = 10;
    const label_size = ctx.theme.font_size_small;

    for (slices) |slice| {
        // Draw color box
        ctx.renderer.drawRect(Rect{
            .x = legend_x,
            .y = legend_y,
            .width = box_size,
            .height = box_size,
        }, slice.color);

        // Draw label with percentage
        if (slice.label) |label_str| {
            const percentage = (slice.value / total) * 100;
            var buf: [32]u8 = undefined;
            const text = std.fmt.bufPrint(&buf, "{s} ({d:.0}%)", .{ label_str, percentage }) catch label_str;
            ctx.renderer.drawText(text, Vec2{ .x = legend_x + box_size + 4, .y = legend_y - 2 }, label_size, ctx.theme.text_secondary);
        }

        legend_y += 18;
    }
}

fn drawLine(ctx: *Context, x1: f32, y1: f32, x2: f32, y2: f32, color: Color, thickness: f32) void {
    // Calculate line length and angle
    const dx = x2 - x1;
    const dy = y2 - y1;
    const length = @sqrt(dx * dx + dy * dy);

    if (length < 0.001) return;

    // Normalize direction
    const nx = dx / length;
    const ny = dy / length;

    // Perpendicular for thickness
    const px = -ny * thickness / 2;
    const py = nx * thickness / 2;

    // Draw as series of small rectangles along the line
    const steps: u32 = @intFromFloat(@max(1, length / 2));
    const step_x = dx / @as(f32, @floatFromInt(steps));
    const step_y = dy / @as(f32, @floatFromInt(steps));

    var x = x1;
    var y = y1;
    for (0..steps) |_| {
        ctx.renderer.drawRect(Rect{
            .x = x + px,
            .y = y + py,
            .width = thickness + @abs(step_x),
            .height = thickness + @abs(step_y),
        }, color);
        x += step_x;
        y += step_y;
    }
}

fn drawMarker(ctx: *Context, x: f32, y: f32, size: f32, color: Color) void {
    const half_size = size / 2;
    ctx.renderer.drawRect(Rect{
        .x = x - half_size,
        .y = y - half_size,
        .width = size,
        .height = size,
    }, color);
}

fn drawPieSlice(ctx: *Context, center: Vec2, radius: f32, start_angle: f32, sweep_angle: f32, color: Color) void {
    // Draw pie slice as filled triangles from center
    const segments: u32 = @max(8, @as(u32, @intFromFloat(sweep_angle * 20)));
    const angle_step = sweep_angle / @as(f32, @floatFromInt(segments));

    var angle = start_angle;
    for (0..segments) |_| {
        const next_angle = angle + angle_step;

        // Draw triangle from center to arc
        const x1 = center.x + @cos(angle) * radius;
        const y1 = center.y + @sin(angle) * radius;
        const x2 = center.x + @cos(next_angle) * radius;
        const y2 = center.y + @sin(next_angle) * radius;

        // Approximate triangle as small rect (simplified rendering)
        const min_x = @min(center.x, @min(x1, x2));
        const max_x = @max(center.x, @max(x1, x2));
        const min_y = @min(center.y, @min(y1, y2));
        const max_y = @max(center.y, @max(y1, y2));

        // Draw filled segment using radial lines
        drawLine(ctx, center.x, center.y, x1, y1, color, 2);
        drawLine(ctx, center.x, center.y, x2, y2, color, 2);
        drawLine(ctx, x1, y1, x2, y2, color, 2);

        // Fill center area
        ctx.renderer.drawRect(Rect{
            .x = min_x,
            .y = min_y,
            .width = @max(1, max_x - min_x),
            .height = @max(1, max_y - min_y),
        }, color);

        angle = next_angle;
    }
}

fn maxDataLen(series: []const Series) usize {
    var max_len: usize = 0;
    for (series) |s| {
        max_len = @max(max_len, s.data.len);
    }
    return max_len;
}

fn formatValue(value: f32, buf: []u8) []const u8 {
    const abs_value = @abs(value);
    if (abs_value >= 1000000) {
        return std.fmt.bufPrint(buf, "{d:.1}M", .{value / 1000000}) catch "?";
    } else if (abs_value >= 1000) {
        return std.fmt.bufPrint(buf, "{d:.1}K", .{value / 1000}) catch "?";
    } else if (abs_value < 0.01 and abs_value > 0) {
        return std.fmt.bufPrint(buf, "{d:.3}", .{value}) catch "?";
    } else if (@floor(value) == value) {
        return std.fmt.bufPrint(buf, "{d:.0}", .{value}) catch "?";
    } else {
        return std.fmt.bufPrint(buf, "{d:.1}", .{value}) catch "?";
    }
}

// ============================================================================
// Tests
// ============================================================================

test "chart - y range calculation" {
    const series = [_]Series{
        .{ .data = &[_]f32{ 1, 5, 3, 8, 2 }, .color = Color.blue },
        .{ .data = &[_]f32{ 2, 4, 6, 4, 3 }, .color = Color.red },
    };

    const y_range = calculateYRange(&series, .{});

    // Should find min ~1 and max ~8 (with padding)
    try std.testing.expect(y_range.min < 1);
    try std.testing.expect(y_range.max > 8);
}

test "chart - y range with explicit bounds" {
    const series = [_]Series{
        .{ .data = &[_]f32{ 1, 5, 3 }, .color = Color.blue },
    };

    const y_range = calculateYRange(&series, .{ .y_min = 0, .y_max = 10 });

    try std.testing.expectEqual(@as(f32, 0), y_range.min);
    try std.testing.expectEqual(@as(f32, 10), y_range.max);
}

test "chart - max data length" {
    const series = [_]Series{
        .{ .data = &[_]f32{ 1, 2, 3 }, .color = Color.blue },
        .{ .data = &[_]f32{ 1, 2, 3, 4, 5 }, .color = Color.red },
        .{ .data = &[_]f32{ 1 }, .color = Color.green },
    };

    const max_len = maxDataLen(&series);
    try std.testing.expectEqual(@as(usize, 5), max_len);
}

test "chart - value formatting" {
    var buf: [16]u8 = undefined;

    try std.testing.expectEqualStrings("1.5M", formatValue(1500000, &buf));
    try std.testing.expectEqualStrings("2.5K", formatValue(2500, &buf));
    try std.testing.expectEqualStrings("42", formatValue(42, &buf));
    try std.testing.expectEqualStrings("3.1", formatValue(3.14, &buf));
    try std.testing.expectEqualStrings("0.005", formatValue(0.005, &buf));
}

test "chart - value to y coordinate" {
    const chart_area = Rect{ .x = 0, .y = 0, .width = 100, .height = 100 };
    const y_range = YRange{ .min = 0, .max = 100 };

    // Value 0 should be at bottom (y = 100)
    const y_at_0 = valueToY(0, chart_area, y_range);
    try std.testing.expectEqual(@as(f32, 100), y_at_0);

    // Value 100 should be at top (y = 0)
    const y_at_100 = valueToY(100, chart_area, y_range);
    try std.testing.expectEqual(@as(f32, 0), y_at_100);

    // Value 50 should be in middle (y = 50)
    const y_at_50 = valueToY(50, chart_area, y_range);
    try std.testing.expectEqual(@as(f32, 50), y_at_50);
}
