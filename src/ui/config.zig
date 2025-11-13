/// UI Configuration Constants
/// All magic numbers used for spacing, sizing, timing, and styling
/// Centralizes all hardcoded values for easier maintenance and theming

/// Spacing and padding values
pub const spacing = struct {
    pub const widget_default: f32 = 5;
    pub const panel_padding: f32 = 10;
    pub const label_offset_y: f32 = 4;
    pub const input_padding_x: f32 = 5;
    pub const scrolllist_padding: f32 = 3;
    pub const scrolllist_scissor_extension: f32 = 5;
    pub const scrollbar_padding: f32 = 2;
    pub const checkbox_text_gap: f32 = 8;
    pub const tooltip_offset_y: f32 = 5;
    pub const tooltip_shadow_offset: f32 = 2;
    pub const tabbar_spacing: f32 = 5;
};

/// Widget sizes and dimensions
pub const sizes = struct {
    // Text sizes
    pub const text_default: f32 = 16;
    pub const text_small: f32 = 12;
    pub const text_medium: f32 = 14;

    // Widget heights
    pub const widget_height: f32 = 30;
    pub const label_height: f32 = 16;
    pub const progressbar_height: f32 = 24;
    pub const tabbar_height: f32 = 32;

    // Specific widget sizes
    pub const slider_handle: f32 = 12;
    pub const dropdown_item_height: f32 = 25;
    pub const dropdown_arrow: f32 = 8;
    pub const scrolllist_item_height: f32 = 25;
    pub const scrollbar_width: f32 = 8;
    pub const checkbox_box: f32 = 20;
    pub const panel_corner: f32 = 8;
    pub const tooltip_padding: f32 = 8;
};

/// Font and text rendering
pub const font = struct {
    pub const atlas_width: u32 = 1024;
    pub const atlas_height: u32 = 1024;
    pub const default_size: f32 = 24.0;
    pub const bake_first_char: u32 = 32; // ASCII space
    pub const bake_num_chars: u32 = 96;  // ASCII 32-127

    // Cursor rendering
    pub const cursor_height_factor: f32 = 0.75;
    pub const cursor_y_offset_factor: f32 = 0.75;
    pub const cursor_coverage: f32 = 0.9;
};

/// Border and outline thicknesses
pub const borders = struct {
    pub const thin: f32 = 1.0;
    pub const medium: f32 = 2.0;
};

/// Timing values (in frames at 60fps)
pub const timing = struct {
    pub const tooltip_hover_delay: u32 = 30; // ~0.5 seconds
};

/// Scrolling behavior
pub const scrolling = struct {
    pub const wheel_speed: f32 = 30;        // pixels per wheel notch
    pub const page_factor: f32 = 0.9;       // scroll by 90% of visible area
};

/// Progress bar thresholds
pub const progress = struct {
    pub const low_threshold: f32 = 0.33;
    pub const medium_threshold: f32 = 0.66;
};

/// Grid and layout
pub const layout = struct {
    pub const panel_grid_spacing: f32 = 20;
};

/// Null renderer fallback values
pub const null_renderer = struct {
    pub const char_width: f32 = 10.0;
    pub const baseline_factor: f32 = 0.2;
};
