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
const rich_text_mod = @import("widgets/rich_text.zig");
const table_mod = @import("widgets/table.zig");
const color_picker_mod = @import("widgets/color_picker.zig");
const notification_mod = @import("widgets/notification.zig");

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

// Rich text widgets (formatted text with markup)
pub const TextStyle = rich_text_mod.TextStyle;
pub const TextSpan = rich_text_mod.TextSpan;
pub const RichTextOptions = rich_text_mod.RichTextOptions;
pub const ParsedRichText = rich_text_mod.ParsedRichText;
pub const parseMarkup = rich_text_mod.parseMarkup;
pub const richText = rich_text_mod.richText;
pub const richTextAuto = rich_text_mod.richTextAuto;

// Table widgets (tabular data display)
pub const Alignment = table_mod.Alignment;
pub const TableColumn = table_mod.TableColumn;
pub const TableState = table_mod.TableState;
pub const table = table_mod.table;
pub const tableAuto = table_mod.tableAuto;

// Color picker widgets (HSV/RGB color selection)
pub const Hsv = color_picker_mod.Hsv;
pub const hsvToRgb = color_picker_mod.hsvToRgb;
pub const rgbToHsv = color_picker_mod.rgbToHsv;
pub const parseHex = color_picker_mod.parseHex;
pub const formatHex = color_picker_mod.formatHex;
pub const ColorPickerState = color_picker_mod.ColorPickerState;
pub const ColorPickerOptions = color_picker_mod.ColorPickerOptions;
pub const default_presets = color_picker_mod.default_presets;
pub const colorPicker = color_picker_mod.colorPicker;
pub const colorPickerAuto = color_picker_mod.colorPickerAuto;
pub const CompactColorPickerState = color_picker_mod.CompactColorPickerState;
pub const compactColorPicker = color_picker_mod.compactColorPicker;
pub const compactColorPickerAuto = color_picker_mod.compactColorPickerAuto;

// Notification widgets (toast notifications)
pub const NotificationType = notification_mod.NotificationType;
pub const NotificationPosition = notification_mod.NotificationPosition;
pub const AnimationPhase = notification_mod.AnimationPhase;
pub const Notification = notification_mod.Notification;
pub const NotificationOptions = notification_mod.NotificationOptions;
pub const NotificationDisplayOptions = notification_mod.NotificationDisplayOptions;
pub const NotificationManager = notification_mod.NotificationManager;
pub const renderNotifications = notification_mod.renderNotifications;
pub const MAX_NOTIFICATIONS = notification_mod.MAX_NOTIFICATIONS;
