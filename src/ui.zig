// UI module for AgentiteZ
// Immediate-mode UI system adapted from StellarThroneZig

pub const types = @import("ui/types.zig");
pub const renderer = @import("ui/renderer.zig");
pub const context = @import("ui/context.zig");
pub const widgets = @import("ui/widgets.zig");
pub const dpi = @import("ui/dpi.zig");
pub const layout = @import("ui/layout.zig");
pub const renderer_2d = @import("ui/renderer_2d.zig");
pub const config = @import("ui/config.zig");

// Re-export commonly used types
pub const Vec2 = types.Vec2;
pub const Rect = types.Rect;
pub const Color = types.Color;
pub const Theme = types.Theme;
pub const InputState = types.InputState;
pub const MouseButton = types.MouseButton;
pub const Key = types.Key;

// Re-export DPI types
pub const WindowInfo = dpi.WindowInfo;
pub const DpiConfig = dpi.DpiConfig;
pub const RenderScale = dpi.RenderScale;

// Re-export Layout types
pub const Layout = layout.Layout;
pub const LayoutDirection = layout.LayoutDirection;
pub const LayoutAlign = layout.LayoutAlign;

// Re-export UI components
pub const Context = context.Context;
pub const Renderer = renderer.Renderer;
pub const Renderer2D = renderer_2d.Renderer2D;

// Re-export widget functions
pub const button = widgets.button;
pub const buttonAuto = widgets.buttonAuto;
pub const label = widgets.label;
pub const slider = widgets.slider;
pub const sliderAuto = widgets.sliderAuto;
pub const checkbox = widgets.checkbox;
pub const checkboxAuto = widgets.checkboxAuto;
pub const textInput = widgets.textInput;
pub const textInputAuto = widgets.textInputAuto;
pub const dropdown = widgets.dropdown;
pub const dropdownAuto = widgets.dropdownAuto;
pub const scrollList = widgets.scrollList;
pub const scrollListAuto = widgets.scrollListAuto;
pub const progressBar = widgets.progressBar;
pub const progressBarAuto = widgets.progressBarAuto;
pub const tabBar = widgets.tabBar;
pub const tabBarAuto = widgets.tabBarAuto;
pub const beginPanel = widgets.beginPanel;
pub const endPanel = widgets.endPanel;

// Re-export widget state types
pub const DropdownState = widgets.DropdownState;
pub const ScrollListState = widgets.ScrollListState;
pub const TabBarState = widgets.TabBarState;

// Test modules (compiled only during `zig build test`)
test {
    _ = @import("ui/integration_tests.zig");
    _ = @import("ui/resize_test.zig");
    _ = @import("ui/visual_regression_test.zig");
    _ = @import("ui/widget_tests.zig");
}
