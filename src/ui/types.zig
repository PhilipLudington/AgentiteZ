const std = @import("std");

/// 2D Vector for positions and sizes
pub const Vec2 = struct {
    x: f32,
    y: f32,

    pub fn init(x: f32, y: f32) Vec2 {
        return .{ .x = x, .y = y };
    }

    pub fn add(self: Vec2, other: Vec2) Vec2 {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }

    pub fn sub(self: Vec2, other: Vec2) Vec2 {
        return .{ .x = self.x - other.x, .y = self.y - other.y };
    }
};

/// Rectangle for UI bounds
pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    pub fn init(x: f32, y: f32, width: f32, height: f32) Rect {
        return .{ .x = x, .y = y, .width = width, .height = height };
    }

    pub fn contains(self: Rect, point: Vec2) bool {
        return point.x >= self.x and
            point.x <= self.x + self.width and
            point.y >= self.y and
            point.y <= self.y + self.height;
    }

    pub fn center(self: Rect) Vec2 {
        return .{
            .x = self.x + self.width / 2,
            .y = self.y + self.height / 2,
        };
    }

    pub fn scale(self: Rect, factor: f32) Rect {
        return .{
            .x = self.x * factor,
            .y = self.y * factor,
            .width = self.width * factor,
            .height = self.height * factor,
        };
    }

    /// Calculate intersection of two rectangles (for scissor clipping)
    pub fn intersect(self: Rect, other: Rect) Rect {
        const x1 = @max(self.x, other.x);
        const y1 = @max(self.y, other.y);
        const x2 = @min(self.x + self.width, other.x + other.width);
        const y2 = @min(self.y + self.height, other.y + other.height);

        return Rect{
            .x = x1,
            .y = y1,
            .width = @max(0, x2 - x1),
            .height = @max(0, y2 - y1),
        };
    }
};

/// RGBA Color (0-255)
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub fn init(r: u8, g: u8, b: u8, a: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn rgb(r: u8, g: u8, b: u8) Color {
        return init(r, g, b, 255);
    }

    // Common colors
    pub const white = Color.rgb(255, 255, 255);
    pub const black = Color.rgb(0, 0, 0);
    pub const gray = Color.rgb(128, 128, 128);
    pub const red = Color.rgb(255, 0, 0);
    pub const green = Color.rgb(0, 255, 0);
    pub const blue = Color.rgb(0, 0, 255);

    // Imperial salvaged tech palette
    pub const imperial_gold = Color.rgb(180, 150, 90); // Tarnished gold/brass
    pub const imperial_dark_gold = Color.rgb(120, 100, 60);
    pub const oxidized_copper = Color.rgb(120, 140, 130); // Aged metal
    pub const faded_purple = Color.rgb(100, 80, 120); // Imperial purple
    pub const deep_space = Color.rgb(15, 18, 25); // Dark background
    pub const warning_amber = Color.rgb(200, 150, 50); // Alert color
    pub const critical_red = Color.rgb(180, 40, 40); // Danger
    pub const worn_white = Color.rgb(220, 220, 200); // Not-quite-white text
    pub const tech_cyan = Color.rgb(80, 180, 200); // Holographic blue
    pub const dim_green = Color.rgb(60, 140, 80); // Status OK
    pub const panel_bg = Color.rgb(25, 28, 35); // Panel background
    pub const panel_border = Color.rgb(90, 110, 100); // Panel outline

    /// Darken a color by a factor (0.0 = black, 1.0 = original)
    pub fn darken(self: Color, factor: f32) Color {
        const f = std.math.clamp(factor, 0.0, 1.0);
        return Color.rgb(
            @intFromFloat(@as(f32, @floatFromInt(self.r)) * f),
            @intFromFloat(@as(f32, @floatFromInt(self.g)) * f),
            @intFromFloat(@as(f32, @floatFromInt(self.b)) * f),
        );
    }

    /// Lighten a color by a factor (0.0 = original, 1.0 = white)
    pub fn lighten(self: Color, factor: f32) Color {
        const f = std.math.clamp(factor, 0.0, 1.0);
        return Color.rgb(
            @intFromFloat(@as(f32, @floatFromInt(self.r)) + (255.0 - @as(f32, @floatFromInt(self.r))) * f),
            @intFromFloat(@as(f32, @floatFromInt(self.g)) + (255.0 - @as(f32, @floatFromInt(self.g))) * f),
            @intFromFloat(@as(f32, @floatFromInt(self.b)) + (255.0 - @as(f32, @floatFromInt(self.b))) * f),
        );
    }
};

/// UI element identifier (hash of label/id)
pub const WidgetId = u64;

/// Generate widget ID from string label
pub fn widgetId(label: []const u8) WidgetId {
    return std.hash.Wyhash.hash(0, label);
}

/// Mouse button states
pub const MouseButton = enum {
    left,
    right,
    middle,
};

/// Keyboard key codes
pub const Key = enum {
    backspace,
    delete,
    left,
    right,
    home,
    end,
    enter,
    escape,
    tab,
    unknown,
};

/// Imperial UI Theme - for salvaged post-collapse aesthetic
pub const Theme = struct {
    // Button colors
    button_normal: Color,
    button_hover: Color,
    button_pressed: Color,
    button_border: Color,
    button_text: Color,

    // Panel colors
    panel_bg: Color,
    panel_border: Color,
    panel_title: Color,

    // Slider/Progress bar colors
    slider_track: Color,
    slider_fill: Color,
    slider_handle: Color,
    slider_handle_hover: Color,
    slider_handle_active: Color,

    // Text input colors
    input_bg: Color,
    input_bg_focused: Color,
    input_border: Color,
    input_border_focused: Color,
    input_text: Color,
    input_cursor: Color,

    // Checkbox colors
    checkbox_bg_normal: Color,
    checkbox_bg_hover: Color,
    checkbox_bg_pressed: Color,
    checkbox_border: Color,
    checkbox_check: Color,

    // General
    text_primary: Color,
    text_secondary: Color,
    border_thickness: f32,
    corner_size: f32, // For asymmetric/beveled corners

    // Font sizes
    font_size_normal: f32,    // Standard UI text (buttons, checkboxes, text input)
    font_size_small: f32,     // Small text (dropdown items, tooltips, labels)
    font_size_large: f32,     // Large text (titles, headers)

    // Widget dimensions
    checkbox_size: f32,       // Size of checkbox box
    widget_spacing: f32,      // Default spacing between widgets
    widget_padding: f32,      // Padding inside widgets (checkboxes, panels)

    // Dropdown specific
    dropdown_item_height: f32,  // Height of each dropdown item
    dropdown_max_visible: i32,  // Maximum visible items before scrolling
    dropdown_bg: Color,         // Dropdown header background
    dropdown_hover: Color,      // Dropdown header hover
    dropdown_border: Color,     // Dropdown border
    dropdown_text: Color,       // Dropdown text color
    dropdown_item_hover: Color, // Dropdown item hover
    dropdown_item_selected: Color, // Dropdown item selected

    // Progress bar colors
    progress_bg: Color,          // Progress bar background
    progress_border: Color,      // Progress bar border
    progress_fill_low: Color,    // Progress fill (0-33%)
    progress_fill_med: Color,    // Progress fill (33-66%)
    progress_fill_high: Color,   // Progress fill (66-100%)

    // Tooltip colors
    tooltip_bg: Color,           // Tooltip background
    tooltip_border: Color,       // Tooltip border
    tooltip_shadow: Color,       // Tooltip shadow
    tooltip_text: Color,         // Tooltip text

    // List/Scrollbar colors
    list_bg: Color,              // List background
    list_border: Color,          // List border
    list_item_hover: Color,      // List item hover
    list_item_selected: Color,   // List item selected
    list_text: Color,            // List text color
    scrollbar_track: Color,      // Scrollbar track
    scrollbar_thumb: Color,      // Scrollbar thumb
    scrollbar_thumb_hover: Color, // Scrollbar thumb hover
    scrollbar_thumb_active: Color, // Scrollbar thumb active

    // Tab bar colors
    tab_active: Color,           // Active tab
    tab_inactive: Color,         // Inactive tab
    tab_hover: Color,            // Tab hover
    tab_border_active: Color,    // Active tab border
    tab_border_inactive: Color,  // Inactive tab border
    tab_text_active: Color,      // Active tab text
    tab_text_inactive: Color,    // Inactive tab text

    // Label colors
    label_color: Color,          // Generic label text

    // Chart colors
    chart_bg: Color,             // Chart background
    chart_border: Color,         // Chart border
    chart_grid: Color,           // Grid lines
    chart_axis: Color,           // Axis lines
    chart_line_1: Color,         // Series 1 color
    chart_line_2: Color,         // Series 2 color
    chart_line_3: Color,         // Series 3 color
    chart_line_4: Color,         // Series 4 color

    // Notification colors
    notification_bg: Color,           // Notification background
    notification_border: Color,       // Notification border
    notification_text: Color,         // Notification message text
    notification_title: Color,        // Notification title text
    notification_close: Color,        // Close button color
    notification_close_hover: Color,  // Close button hover color

    /// Create default Imperial salvaged tech theme
    pub fn imperial() Theme {
        return .{
            .button_normal = Color.imperial_gold.darken(0.6),
            .button_hover = Color.imperial_gold.darken(0.7),
            .button_pressed = Color.imperial_dark_gold,
            .button_border = Color.imperial_gold,
            .button_text = Color.worn_white,

            .panel_bg = Color.panel_bg,
            .panel_border = Color.panel_border,
            .panel_title = Color.imperial_gold,

            .slider_track = Color.oxidized_copper.darken(0.5),
            .slider_fill = Color.tech_cyan,
            .slider_handle = Color.rgb(180, 180, 180),
            .slider_handle_hover = Color.rgb(200, 200, 255),
            .slider_handle_active = Color.rgb(150, 150, 255),

            .input_bg = Color.rgb(240, 240, 240),
            .input_bg_focused = Color.white,
            .input_border = Color.rgb(150, 150, 150),
            .input_border_focused = Color.rgb(100, 150, 255),
            .input_text = Color.worn_white,
            .input_cursor = Color.black,

            .checkbox_bg_normal = Color.rgb(240, 240, 240),
            .checkbox_bg_hover = Color.rgb(220, 220, 220),
            .checkbox_bg_pressed = Color.rgb(160, 160, 160),
            .checkbox_border = Color.rgb(100, 100, 100),
            .checkbox_check = Color.rgb(50, 150, 50),

            .text_primary = Color.worn_white,
            .text_secondary = Color.oxidized_copper,
            .border_thickness = 2.0,
            .corner_size = 4.0,

            .font_size_normal = 16.0,
            .font_size_small = 14.0,
            .font_size_large = 20.0,

            .checkbox_size = 20.0,
            .widget_spacing = 5.0,
            .widget_padding = 4.0,

            .dropdown_item_height = 25.0,
            .dropdown_max_visible = 5,
            .dropdown_bg = Color.rgb(240, 240, 240),
            .dropdown_hover = Color.rgb(230, 230, 230),
            .dropdown_border = Color.rgb(150, 150, 150),
            .dropdown_text = Color.black,
            .dropdown_item_hover = Color.rgb(220, 220, 255),
            .dropdown_item_selected = Color.rgb(200, 200, 255),

            .progress_bg = Color.rgb(200, 200, 200),
            .progress_border = Color.rgb(100, 100, 100),
            .progress_fill_low = Color.rgb(220, 80, 80),
            .progress_fill_med = Color.rgb(220, 180, 60),
            .progress_fill_high = Color.rgb(80, 200, 80),

            .tooltip_bg = Color.rgb(255, 255, 220),
            .tooltip_border = Color.rgb(100, 100, 100),
            .tooltip_shadow = Color.rgb(0, 0, 0),
            .tooltip_text = Color.black,

            .list_bg = Color.white,
            .list_border = Color.rgb(150, 150, 150),
            .list_item_hover = Color.rgb(220, 220, 255),
            .list_item_selected = Color.rgb(200, 200, 255),
            .list_text = Color.rgb(10, 10, 10),
            .scrollbar_track = Color.rgb(230, 230, 230),
            .scrollbar_thumb = Color.rgb(180, 180, 180),
            .scrollbar_thumb_hover = Color.rgb(150, 150, 150),
            .scrollbar_thumb_active = Color.rgb(120, 120, 120),

            .tab_active = Color.rgb(200, 200, 255),
            .tab_inactive = Color.rgb(200, 200, 200),
            .tab_hover = Color.rgb(220, 220, 220),
            .tab_border_active = Color.rgb(100, 100, 200),
            .tab_border_inactive = Color.rgb(150, 150, 150),
            .tab_text_active = Color.black,
            .tab_text_inactive = Color.rgb(80, 80, 80),

            .label_color = Color.white,

            .chart_bg = Color.panel_bg,
            .chart_border = Color.panel_border,
            .chart_grid = Color.rgb(60, 65, 75),
            .chart_axis = Color.rgb(100, 110, 120),
            .chart_line_1 = Color.tech_cyan,
            .chart_line_2 = Color.warning_amber,
            .chart_line_3 = Color.dim_green,
            .chart_line_4 = Color.faded_purple,

            .notification_bg = Color.panel_bg,
            .notification_border = Color.panel_border,
            .notification_text = Color.worn_white,
            .notification_title = Color.imperial_gold,
            .notification_close = Color.oxidized_copper,
            .notification_close_hover = Color.worn_white,
        };
    }
};

/// Input state for UI
pub const InputState = struct {
    mouse_pos: Vec2,
    mouse_down: bool,
    mouse_clicked: bool, // true for one frame when clicked
    mouse_released: bool, // true for one frame when released
    mouse_button: MouseButton,

    // Keyboard input - text entry
    text_input: []const u8 = "", // Text entered this frame

    // Keyboard input - special keys (true only on frame of press)
    key_backspace: bool = false,
    key_delete: bool = false,
    key_enter: bool = false,
    key_tab: bool = false,
    key_left: bool = false,
    key_right: bool = false,
    key_home: bool = false,
    key_end: bool = false,
    key_escape: bool = false,

    // Mouse wheel
    mouse_wheel: f32 = 0, // Mouse wheel movement this frame (positive = up, negative = down)

    pub fn init() InputState {
        return .{
            .mouse_pos = .{ .x = 0, .y = 0 },
            .mouse_down = false,
            .mouse_clicked = false,
            .mouse_released = false,
            .mouse_button = .left,
            .text_input = "",
            // All keyboard keys default to false
            .mouse_wheel = 0,
        };
    }
};

test "Rect - contains point" {
    const rect = Rect.init(10, 10, 100, 50);

    try std.testing.expect(rect.contains(.{ .x = 50, .y = 30 })); // inside
    try std.testing.expect(!rect.contains(.{ .x = 5, .y = 30 })); // outside left
    try std.testing.expect(!rect.contains(.{ .x = 150, .y = 30 })); // outside right
}

test "widgetId - consistent hashing" {
    const id1 = widgetId("button_1");
    const id2 = widgetId("button_1");
    const id3 = widgetId("button_2");

    try std.testing.expectEqual(id1, id2);
    try std.testing.expect(id1 != id3);
}
