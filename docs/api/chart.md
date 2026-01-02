# Chart Widget

Data visualization widgets for displaying line, bar, and pie charts (`src/ui/widgets/chart.zig`).

## Features

- **Line charts** - Multiple series with markers, configurable line thickness
- **Bar charts** - Grouped bars for multi-series data, adjustable bar width
- **Pie charts** - Circular segments with percentage legend
- **Automatic scaling** - Y-axis range auto-calculated from data
- **Grid lines** - Configurable horizontal grid with axis labels
- **Legends** - Series names and colors displayed below chart
- **Colorblind-friendly** - Default palette designed for accessibility
- **Auto-layout** - Both manual positioning and cursor-based placement

## Usage

### Basic Line Chart

```zig
const ui = @import("AgentiteZ").ui;

// Define data series
const series = [_]ui.Series{
    .{
        .data = &[_]f32{ 10, 25, 15, 30, 22 },
        .color = ui.default_colors[0],
        .name = "Revenue",
    },
    .{
        .data = &[_]f32{ 8, 12, 18, 14, 20 },
        .color = ui.default_colors[1],
        .name = "Expenses",
    },
};

// Render line chart
ui.lineChart(ctx, "revenue_chart", rect, &series, .{
    .title = "Monthly Revenue",
    .show_grid = true,
    .show_markers = true,
});

// Or use auto-layout
ui.lineChartAuto(ctx, "revenue_chart", 400, 200, &series, .{});
```

### Bar Chart

```zig
const categories = [_][]const u8{ "Q1", "Q2", "Q3", "Q4" };

ui.barChart(ctx, "sales_chart", rect, &series, .{
    .title = "Quarterly Sales",
    .x_labels = &categories,
    .bar_width_ratio = 0.8,
});
```

### Pie Chart

```zig
const slices = [_]ui.PieSlice{
    .{ .value = 35, .color = ui.default_colors[0], .label = "Desktop" },
    .{ .value = 45, .color = ui.default_colors[1], .label = "Mobile" },
    .{ .value = 20, .color = ui.default_colors[2], .label = "Tablet" },
};

ui.pieChart(ctx, "market_share", rect, &slices, .{
    .title = "Market Share",
    .show_legend = true,
});
```

## Data Structures

### Series

Data series for line and bar charts:

```zig
pub const Series = struct {
    data: []const f32,        // Y values
    color: Color,             // Series color
    name: ?[]const u8 = null, // Legend label
};
```

### PieSlice

Segment for pie charts:

```zig
pub const PieSlice = struct {
    value: f32,               // Normalized to percentage
    color: Color,             // Slice color
    label: ?[]const u8 = null, // Legend label
};
```

### ChartOptions

Configuration options:

```zig
pub const ChartOptions = struct {
    show_grid: bool = true,           // Horizontal grid lines
    show_labels: bool = true,         // Axis labels
    show_legend: bool = true,         // Legend display
    show_markers: bool = true,        // Line chart data points
    y_min: ?f32 = null,               // Y-axis minimum (auto if null)
    y_max: ?f32 = null,               // Y-axis maximum (auto if null)
    x_labels: ?[]const []const u8,    // X-axis category labels
    title: ?[]const u8 = null,        // Chart title
    grid_lines: u32 = 5,              // Number of grid lines
    bar_width_ratio: f32 = 0.8,       // Bar width (0.0-1.0)
    line_thickness: f32 = 2.0,        // Line chart stroke width
    marker_size: f32 = 4.0,           // Data point marker size
};
```

## Default Colors

Colorblind-friendly palette available via `default_colors`:

| Index | Color | RGB |
|-------|-------|-----|
| 0 | Blue | (66, 133, 244) |
| 1 | Red | (234, 67, 53) |
| 2 | Yellow | (251, 188, 5) |
| 3 | Green | (52, 168, 83) |
| 4 | Purple | (155, 89, 182) |
| 5 | Coral | (255, 127, 80) |
| 6 | Cyan | (0, 188, 212) |
| 7 | Orange | (255, 152, 0) |

## Theme Colors

Chart-specific theme colors (customizable via Theme):

- `chart_bg` - Chart background
- `chart_border` - Chart border
- `chart_grid` - Grid line color
- `chart_axis` - Axis line color
- `chart_line_1` through `chart_line_4` - Default series colors

## Limits

- Maximum 256 data points per series
- Maximum 8 series per chart
- Y-axis values formatted as K (thousands) and M (millions) for large numbers

## API Reference

### Line Charts

```zig
fn lineChart(ctx: *Context, label: []const u8, rect: Rect, series: []const Series, options: ChartOptions) void
fn lineChartAuto(ctx: *Context, label: []const u8, width: f32, height: f32, series: []const Series, options: ChartOptions) void
```

### Bar Charts

```zig
fn barChart(ctx: *Context, label: []const u8, rect: Rect, series: []const Series, options: ChartOptions) void
fn barChartAuto(ctx: *Context, label: []const u8, width: f32, height: f32, series: []const Series, options: ChartOptions) void
```

### Pie Charts

```zig
fn pieChart(ctx: *Context, label: []const u8, rect: Rect, slices: []const PieSlice, options: ChartOptions) void
fn pieChartAuto(ctx: *Context, label: []const u8, width: f32, height: f32, slices: []const PieSlice, options: ChartOptions) void
```

## Tests

5 tests covering Y-range calculation, explicit bounds, max data length, value formatting, and coordinate conversion.
