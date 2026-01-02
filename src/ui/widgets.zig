// Main widgets module - re-exports all widget functions from sub-modules
const std = @import("std");
const context_mod = @import("context.zig");
const types = @import("types.zig");

// Re-export common types
pub const Context = context_mod.Context;
pub const widgetId = types.widgetId;
pub const Rect = types.Rect;
pub const Vec2 = types.Vec2;
pub const Color = types.Color;

// Import all widget modules
const basic = @import("widgets/basic.zig");
const container = @import("widgets/container.zig");
const input = @import("widgets/input.zig");
const selection = @import("widgets/selection.zig");
const display = @import("widgets/display.zig");
const chart_mod = @import("widgets/chart.zig");

// ============================================================================
// Re-export all widget functions
// ============================================================================

// Basic widgets (button, label, checkbox)
pub const button = basic.button;
pub const buttonWithId = basic.buttonWithId;
pub const buttonAuto = basic.buttonAuto;
pub const label = basic.label;
pub const checkbox = basic.checkbox;
pub const checkboxAuto = basic.checkboxAuto;

// Container widgets (panel)
pub const beginPanel = container.beginPanel;
pub const endPanel = container.endPanel;

// Input widgets (slider, text input)
pub const slider = input.slider;
pub const sliderAuto = input.sliderAuto;
pub const textInput = input.textInput;
pub const textInputAuto = input.textInputAuto;

// Selection widgets (dropdown, scroll list, tab bar)
pub const DropdownState = selection.DropdownState;
pub const dropdown = selection.dropdown;
pub const dropdownAuto = selection.dropdownAuto;

pub const ScrollListState = selection.ScrollListState;
pub const scrollList = selection.scrollList;
pub const scrollListAuto = selection.scrollListAuto;

pub const TabBarState = selection.TabBarState;
pub const tabBar = selection.tabBar;
pub const tabBarAuto = selection.tabBarAuto;

// Display widgets (progress bar, tooltip)
pub const progressBar = display.progressBar;
pub const progressBarAuto = display.progressBarAuto;
pub const renderTooltip = display.renderTooltip;

// Chart widgets (line, bar, pie charts)
pub const Series = chart_mod.Series;
pub const PieSlice = chart_mod.PieSlice;
pub const ChartOptions = chart_mod.ChartOptions;
pub const default_colors = chart_mod.default_colors;
pub const lineChart = chart_mod.lineChart;
pub const lineChartAuto = chart_mod.lineChartAuto;
pub const barChart = chart_mod.barChart;
pub const barChartAuto = chart_mod.barChartAuto;
pub const pieChart = chart_mod.pieChart;
pub const pieChartAuto = chart_mod.pieChartAuto;
