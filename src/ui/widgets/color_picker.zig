const std = @import("std");
const context_mod = @import("../context.zig");
const types = @import("../types.zig");

pub const Context = context_mod.Context;
pub const widgetId = types.widgetId;
pub const Rect = types.Rect;
pub const Vec2 = types.Vec2;
pub const Color = types.Color;

// ============================================================================
// HSV Color Model
// ============================================================================

/// HSV color representation
pub const Hsv = struct {
    /// Hue in degrees [0, 360)
    h: f32,
    /// Saturation [0, 1]
    s: f32,
    /// Value/Brightness [0, 1]
    v: f32,

    pub fn init(h: f32, s: f32, v: f32) Hsv {
        return .{
            .h = std.math.mod(h, 360.0),
            .s = std.math.clamp(s, 0.0, 1.0),
            .v = std.math.clamp(v, 0.0, 1.0),
        };
    }

    /// Convert HSV to RGB color
    pub fn toRgb(self: Hsv) Color {
        return hsvToRgb(self.h, self.s, self.v);
    }

    /// Create HSV from RGB color
    pub fn fromRgb(color: Color) Hsv {
        return rgbToHsv(color);
    }
};

/// Convert HSV to RGB
/// h: 0-360, s: 0-1, v: 0-1
pub fn hsvToRgb(h: f32, s: f32, v: f32) Color {
    if (s == 0.0) {
        // Achromatic (gray)
        const gray: u8 = @intFromFloat(v * 255.0);
        return Color.rgb(gray, gray, gray);
    }

    const hue = std.math.mod(h, 360.0) / 60.0;
    const sector: u32 = @intFromFloat(@floor(hue));
    const f = hue - @as(f32, @floatFromInt(sector));

    const p = v * (1.0 - s);
    const q = v * (1.0 - s * f);
    const t = v * (1.0 - s * (1.0 - f));

    const to_byte = struct {
        fn convert(val: f32) u8 {
            return @intFromFloat(std.math.clamp(val * 255.0, 0.0, 255.0));
        }
    }.convert;

    return switch (sector) {
        0 => Color.rgb(to_byte(v), to_byte(t), to_byte(p)),
        1 => Color.rgb(to_byte(q), to_byte(v), to_byte(p)),
        2 => Color.rgb(to_byte(p), to_byte(v), to_byte(t)),
        3 => Color.rgb(to_byte(p), to_byte(q), to_byte(v)),
        4 => Color.rgb(to_byte(t), to_byte(p), to_byte(v)),
        else => Color.rgb(to_byte(v), to_byte(p), to_byte(q)),
    };
}

/// Convert RGB to HSV
pub fn rgbToHsv(color: Color) Hsv {
    const r: f32 = @as(f32, @floatFromInt(color.r)) / 255.0;
    const g: f32 = @as(f32, @floatFromInt(color.g)) / 255.0;
    const b: f32 = @as(f32, @floatFromInt(color.b)) / 255.0;

    const max_val = @max(r, @max(g, b));
    const min_val = @min(r, @min(g, b));
    const delta = max_val - min_val;

    // Value is max component
    const v = max_val;

    // Saturation
    const s = if (max_val == 0.0) 0.0 else delta / max_val;

    // Hue
    var h: f32 = 0.0;
    if (delta != 0.0) {
        if (max_val == r) {
            h = 60.0 * std.math.mod((g - b) / delta, 6.0);
        } else if (max_val == g) {
            h = 60.0 * ((b - r) / delta + 2.0);
        } else {
            h = 60.0 * ((r - g) / delta + 4.0);
        }
        if (h < 0.0) h += 360.0;
    }

    return Hsv.init(h, s, v);
}

// ============================================================================
// Color Picker State
// ============================================================================

/// Color picker state (needs to be stored by caller)
pub const ColorPickerState = struct {
    /// Current color in HSV space (for smooth editing)
    hsv: Hsv = Hsv.init(0, 1, 1),
    /// Alpha value [0, 255]
    alpha: u8 = 255,

    /// Which component is being dragged
    active_component: ActiveComponent = .none,

    pub const ActiveComponent = enum {
        none,
        sv_picker, // Saturation-Value gradient
        hue_slider, // Hue bar
        alpha_slider, // Alpha bar
    };

    /// Get current color as RGBA
    pub fn getColor(self: ColorPickerState) Color {
        var color = self.hsv.toRgb();
        color.a = self.alpha;
        return color;
    }

    /// Set color from RGBA
    pub fn setColor(self: *ColorPickerState, color: Color) void {
        self.hsv = Hsv.fromRgb(color);
        self.alpha = color.a;
    }

    /// Set color from hex string (with or without #)
    pub fn setFromHex(self: *ColorPickerState, hex: []const u8) bool {
        const color = parseHex(hex) orelse return false;
        self.setColor(color);
        return true;
    }
};

/// Parse hex color string (supports #RGB, #RGBA, #RRGGBB, #RRGGBBAA)
pub fn parseHex(hex: []const u8) ?Color {
    var str = hex;
    if (str.len > 0 and str[0] == '#') {
        str = str[1..];
    }

    if (str.len == 3 or str.len == 4) {
        // Short form: RGB or RGBA
        const r = parseHexDigit(str[0]) orelse return null;
        const g = parseHexDigit(str[1]) orelse return null;
        const b = parseHexDigit(str[2]) orelse return null;
        const a: u8 = if (str.len == 4) (parseHexDigit(str[3]) orelse return null) * 17 else 255;
        return Color.init(r * 17, g * 17, b * 17, a);
    } else if (str.len == 6 or str.len == 8) {
        // Long form: RRGGBB or RRGGBBAA
        const r = parseHexByte(str[0..2]) orelse return null;
        const g = parseHexByte(str[2..4]) orelse return null;
        const b = parseHexByte(str[4..6]) orelse return null;
        const a: u8 = if (str.len == 8) (parseHexByte(str[6..8]) orelse return null) else 255;
        return Color.init(r, g, b, a);
    }
    return null;
}

fn parseHexDigit(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}

fn parseHexByte(str: *const [2]u8) ?u8 {
    const high = parseHexDigit(str[0]) orelse return null;
    const low = parseHexDigit(str[1]) orelse return null;
    return high * 16 + low;
}

/// Format color as hex string
pub fn formatHex(color: Color, include_alpha: bool, buf: []u8) []const u8 {
    if (include_alpha) {
        return std.fmt.bufPrint(buf, "#{X:0>2}{X:0>2}{X:0>2}{X:0>2}", .{ color.r, color.g, color.b, color.a }) catch "#000000FF";
    } else {
        return std.fmt.bufPrint(buf, "#{X:0>2}{X:0>2}{X:0>2}", .{ color.r, color.g, color.b }) catch "#000000";
    }
}

// ============================================================================
// Default Color Presets
// ============================================================================

/// Default color swatches
pub const default_presets = [_]Color{
    // Row 1: Grayscale
    Color.rgb(0, 0, 0), // Black
    Color.rgb(64, 64, 64), // Dark gray
    Color.rgb(128, 128, 128), // Gray
    Color.rgb(192, 192, 192), // Light gray
    Color.rgb(255, 255, 255), // White

    // Row 2: Warm colors
    Color.rgb(255, 0, 0), // Red
    Color.rgb(255, 128, 0), // Orange
    Color.rgb(255, 255, 0), // Yellow
    Color.rgb(255, 192, 203), // Pink
    Color.rgb(139, 69, 19), // Brown

    // Row 3: Cool colors
    Color.rgb(0, 255, 0), // Green
    Color.rgb(0, 128, 0), // Dark green
    Color.rgb(0, 255, 255), // Cyan
    Color.rgb(0, 0, 255), // Blue
    Color.rgb(128, 0, 128), // Purple
};

// ============================================================================
// Color Picker Widget
// ============================================================================

/// Full color picker with SV gradient, hue slider, alpha slider, and presets
pub fn colorPicker(
    ctx: *Context,
    label_text: []const u8,
    rect: Rect,
    state: *ColorPickerState,
    options: ColorPickerOptions,
) void {
    const id = widgetId(label_text);
    _ = ctx.registerWidget(id, rect);

    // Draw background
    ctx.renderer.drawRect(rect, ctx.theme.panel_bg);
    ctx.renderer.drawRectOutline(rect, ctx.theme.panel_border, 1.0);

    // Layout calculations
    const padding: f32 = 8;
    const hue_width: f32 = 20;
    const alpha_width: f32 = if (options.show_alpha) 20 else 0;
    const slider_gap: f32 = 6;
    const preview_height: f32 = 30;
    const preset_height: f32 = if (options.show_presets) 40 else 0;
    const info_height: f32 = if (options.show_hex or options.show_rgb) 20 else 0;

    // Calculate SV picker area
    const sv_width = rect.width - padding * 2 - hue_width - alpha_width - slider_gap * 2;
    const sv_height = rect.height - padding * 2 - preview_height - preset_height - info_height - slider_gap * 3;

    const sv_rect = Rect{
        .x = rect.x + padding,
        .y = rect.y + padding,
        .width = sv_width,
        .height = sv_height,
    };

    const hue_rect = Rect{
        .x = sv_rect.x + sv_width + slider_gap,
        .y = rect.y + padding,
        .width = hue_width,
        .height = sv_height,
    };

    const alpha_rect = if (options.show_alpha) Rect{
        .x = hue_rect.x + hue_width + slider_gap,
        .y = rect.y + padding,
        .width = alpha_width,
        .height = sv_height,
    } else Rect{ .x = 0, .y = 0, .width = 0, .height = 0 };

    // Handle mouse interaction
    if (ctx.input.mouse_down) {
        if (state.active_component == .none and ctx.input.mouse_clicked) {
            // Check which component was clicked
            if (sv_rect.contains(ctx.input.mouse_pos)) {
                state.active_component = .sv_picker;
            } else if (hue_rect.contains(ctx.input.mouse_pos)) {
                state.active_component = .hue_slider;
            } else if (options.show_alpha and alpha_rect.contains(ctx.input.mouse_pos)) {
                state.active_component = .alpha_slider;
            }
        }

        // Update based on active component
        switch (state.active_component) {
            .sv_picker => {
                const s = std.math.clamp((ctx.input.mouse_pos.x - sv_rect.x) / sv_rect.width, 0.0, 1.0);
                const v = std.math.clamp(1.0 - (ctx.input.mouse_pos.y - sv_rect.y) / sv_rect.height, 0.0, 1.0);
                state.hsv.s = s;
                state.hsv.v = v;
            },
            .hue_slider => {
                const h = std.math.clamp((ctx.input.mouse_pos.y - hue_rect.y) / hue_rect.height, 0.0, 1.0) * 360.0;
                state.hsv.h = h;
            },
            .alpha_slider => {
                const a = std.math.clamp(1.0 - (ctx.input.mouse_pos.y - alpha_rect.y) / alpha_rect.height, 0.0, 1.0);
                state.alpha = @intFromFloat(a * 255.0);
            },
            .none => {},
        }
    } else {
        state.active_component = .none;
    }

    // Draw SV picker gradient
    drawSvGradient(ctx, sv_rect, state.hsv.h);

    // Draw SV picker cursor
    const sv_cursor_x = sv_rect.x + state.hsv.s * sv_rect.width;
    const sv_cursor_y = sv_rect.y + (1.0 - state.hsv.v) * sv_rect.height;
    drawCursor(ctx, sv_cursor_x, sv_cursor_y, 6);

    // Draw hue slider
    drawHueSlider(ctx, hue_rect);

    // Draw hue cursor
    const hue_cursor_y = hue_rect.y + (state.hsv.h / 360.0) * hue_rect.height;
    drawHorizontalCursor(ctx, hue_rect.x, hue_cursor_y, hue_rect.width, 4);

    // Draw alpha slider
    if (options.show_alpha) {
        drawAlphaSlider(ctx, alpha_rect, state.hsv.toRgb());

        // Draw alpha cursor
        const alpha_cursor_y = alpha_rect.y + (1.0 - @as(f32, @floatFromInt(state.alpha)) / 255.0) * alpha_rect.height;
        drawHorizontalCursor(ctx, alpha_rect.x, alpha_cursor_y, alpha_rect.width, 4);
    }

    // Draw color preview
    const preview_rect = Rect{
        .x = rect.x + padding,
        .y = sv_rect.y + sv_height + slider_gap,
        .width = rect.width - padding * 2,
        .height = preview_height,
    };
    drawColorPreview(ctx, preview_rect, state.getColor());

    // Draw presets
    if (options.show_presets) {
        const presets_rect = Rect{
            .x = rect.x + padding,
            .y = preview_rect.y + preview_height + slider_gap,
            .width = rect.width - padding * 2,
            .height = preset_height - slider_gap,
        };
        const presets = if (options.presets) |p| p else &default_presets;
        drawPresets(ctx, label_text, presets_rect, presets, state);
    }

    // Draw hex/RGB info
    if (options.show_hex or options.show_rgb) {
        const info_y = if (options.show_presets)
            preview_rect.y + preview_height + preset_height + slider_gap
        else
            preview_rect.y + preview_height + slider_gap;

        const info_rect = Rect{
            .x = rect.x + padding,
            .y = info_y,
            .width = rect.width - padding * 2,
            .height = info_height,
        };
        drawColorInfo(ctx, info_rect, state.getColor(), options);
    }

    // Draw label above
    if (label_text.len > 0) {
        const label_size = ctx.theme.font_size_small;
        const label_pos = Vec2{
            .x = rect.x,
            .y = rect.y - 4,
        };
        ctx.renderer.drawText(label_text, label_pos, label_size, ctx.theme.label_color);
    }
}

/// Color picker options
pub const ColorPickerOptions = struct {
    /// Show alpha channel slider
    show_alpha: bool = true,
    /// Show color presets/swatches
    show_presets: bool = true,
    /// Show hex color value
    show_hex: bool = true,
    /// Show RGB values
    show_rgb: bool = false,
    /// Custom preset colors (null = use defaults)
    presets: ?[]const Color = null,
};

/// Auto-layout color picker
pub fn colorPickerAuto(
    ctx: *Context,
    label_text: []const u8,
    width: f32,
    height: f32,
    state: *ColorPickerState,
    options: ColorPickerOptions,
) void {
    const label_height: f32 = if (label_text.len > 0) 16 else 0;

    const rect = Rect{
        .x = ctx.cursor.x,
        .y = ctx.cursor.y + label_height,
        .width = width,
        .height = height,
    };

    colorPicker(ctx, label_text, rect, state, options);
    ctx.advanceCursor(height + label_height, 5);
}

// ============================================================================
// Compact Color Picker (Button + Popup style)
// ============================================================================

/// Compact color picker state
pub const CompactColorPickerState = struct {
    /// Full picker state
    picker: ColorPickerState = .{},
    /// Is the picker popup open
    is_open: bool = false,
};

/// Compact color picker - shows a color button that opens a popup
pub fn compactColorPicker(
    ctx: *Context,
    label_text: []const u8,
    rect: Rect,
    state: *CompactColorPickerState,
) void {
    const id = widgetId(label_text);
    const clicked = ctx.registerWidget(id, rect);

    // Toggle popup on click
    if (clicked) {
        state.is_open = !state.is_open;
    }

    // Draw color button
    const color = state.picker.getColor();
    drawColorPreview(ctx, rect, color);

    // Draw border
    const border_color = if (ctx.isHot(id))
        ctx.theme.button_hover
    else
        ctx.theme.panel_border;
    ctx.renderer.drawRectOutline(rect, border_color, if (state.is_open) 2.0 else 1.0);

    // Draw label
    if (label_text.len > 0) {
        const label_size = ctx.theme.font_size_small;
        const label_pos = Vec2{
            .x = rect.x,
            .y = rect.y - 4,
        };
        ctx.renderer.drawText(label_text, label_pos, label_size, ctx.theme.label_color);
    }

    // Draw popup picker if open
    if (state.is_open) {
        const popup_rect = Rect{
            .x = rect.x,
            .y = rect.y + rect.height + 4,
            .width = 220,
            .height = 260,
        };

        // Draw popup background with shadow
        const shadow_rect = Rect{
            .x = popup_rect.x + 2,
            .y = popup_rect.y + 2,
            .width = popup_rect.width,
            .height = popup_rect.height,
        };
        ctx.renderer.drawRect(shadow_rect, Color.init(0, 0, 0, 80));

        // Draw the actual picker
        var popup_label_buf: [64]u8 = undefined;
        const popup_label = std.fmt.bufPrint(&popup_label_buf, "{s}_popup", .{label_text}) catch "picker_popup";
        colorPicker(ctx, popup_label, popup_rect, &state.picker, .{});

        // Close popup if clicking outside
        if (ctx.input.mouse_clicked and !popup_rect.contains(ctx.input.mouse_pos) and !rect.contains(ctx.input.mouse_pos)) {
            state.is_open = false;
        }
    }
}

/// Auto-layout compact color picker
pub fn compactColorPickerAuto(
    ctx: *Context,
    label_text: []const u8,
    width: f32,
    state: *CompactColorPickerState,
) void {
    const height: f32 = 30;
    const label_height: f32 = if (label_text.len > 0) 16 else 0;

    const rect = Rect{
        .x = ctx.cursor.x,
        .y = ctx.cursor.y + label_height,
        .width = width,
        .height = height,
    };

    compactColorPicker(ctx, label_text, rect, state);
    ctx.advanceCursor(height + label_height, 5);
}

// ============================================================================
// Drawing Helpers
// ============================================================================

fn drawSvGradient(ctx: *Context, rect: Rect, hue: f32) void {
    // Draw the SV gradient using horizontal strips
    // Each strip goes from gray (s=0) to full hue color (s=1)
    // Vertical axis controls value (bright at top, dark at bottom)

    const steps: u32 = 16; // Number of vertical strips for value gradient
    const strip_height = rect.height / @as(f32, @floatFromInt(steps));

    for (0..steps) |i| {
        const v = 1.0 - @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps));
        const next_v = 1.0 - @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(steps));
        const y = rect.y + @as(f32, @floatFromInt(i)) * strip_height;

        // Draw horizontal gradient from white (s=0) to hue color (s=1) at this value
        const h_steps: u32 = 16;
        const strip_width = rect.width / @as(f32, @floatFromInt(h_steps));

        for (0..h_steps) |j| {
            const s = @as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(h_steps));
            const mid_v = (v + next_v) / 2;
            const color = hsvToRgb(hue, s, mid_v);

            ctx.renderer.drawRect(Rect{
                .x = rect.x + @as(f32, @floatFromInt(j)) * strip_width,
                .y = y,
                .width = strip_width + 1, // +1 to avoid gaps
                .height = strip_height + 1,
            }, color);
        }
    }

    // Draw border
    ctx.renderer.drawRectOutline(rect, ctx.theme.panel_border, 1.0);
}

fn drawHueSlider(ctx: *Context, rect: Rect) void {
    // Draw vertical hue gradient
    const steps: u32 = 12;
    const step_height = rect.height / @as(f32, @floatFromInt(steps));

    for (0..steps) |i| {
        const h = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps)) * 360.0;
        const color = hsvToRgb(h, 1.0, 1.0);

        ctx.renderer.drawRect(Rect{
            .x = rect.x,
            .y = rect.y + @as(f32, @floatFromInt(i)) * step_height,
            .width = rect.width,
            .height = step_height + 1,
        }, color);
    }

    // Draw border
    ctx.renderer.drawRectOutline(rect, ctx.theme.panel_border, 1.0);
}

fn drawAlphaSlider(ctx: *Context, rect: Rect, base_color: Color) void {
    // Draw checkerboard background (to show transparency)
    const checker_size: f32 = 5;
    const cols: u32 = @intFromFloat(@ceil(rect.width / checker_size));
    const rows: u32 = @intFromFloat(@ceil(rect.height / checker_size));

    for (0..rows) |row| {
        for (0..cols) |col| {
            const is_light = (row + col) % 2 == 0;
            const checker_color = if (is_light) Color.rgb(200, 200, 200) else Color.rgb(150, 150, 150);
            ctx.renderer.drawRect(Rect{
                .x = rect.x + @as(f32, @floatFromInt(col)) * checker_size,
                .y = rect.y + @as(f32, @floatFromInt(row)) * checker_size,
                .width = @min(checker_size, rect.width - @as(f32, @floatFromInt(col)) * checker_size),
                .height = @min(checker_size, rect.height - @as(f32, @floatFromInt(row)) * checker_size),
            }, checker_color);
        }
    }

    // Draw alpha gradient overlay
    const steps: u32 = 16;
    const step_height = rect.height / @as(f32, @floatFromInt(steps));

    for (0..steps) |i| {
        const a = 1.0 - @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps));
        const color = Color.init(base_color.r, base_color.g, base_color.b, @intFromFloat(a * 255.0));

        ctx.renderer.drawRect(Rect{
            .x = rect.x,
            .y = rect.y + @as(f32, @floatFromInt(i)) * step_height,
            .width = rect.width,
            .height = step_height + 1,
        }, color);
    }

    // Draw border
    ctx.renderer.drawRectOutline(rect, ctx.theme.panel_border, 1.0);
}

fn drawCursor(ctx: *Context, x: f32, y: f32, size: f32) void {
    // Draw circular cursor with white/black outline for visibility
    const outer_rect = Rect{
        .x = x - size / 2 - 1,
        .y = y - size / 2 - 1,
        .width = size + 2,
        .height = size + 2,
    };
    ctx.renderer.drawRectOutline(outer_rect, Color.black, 1.0);

    const inner_rect = Rect{
        .x = x - size / 2,
        .y = y - size / 2,
        .width = size,
        .height = size,
    };
    ctx.renderer.drawRectOutline(inner_rect, Color.white, 1.0);
}

fn drawHorizontalCursor(ctx: *Context, x: f32, y: f32, width: f32, height: f32) void {
    // Draw horizontal bar cursor
    const outer_rect = Rect{
        .x = x - 1,
        .y = y - height / 2 - 1,
        .width = width + 2,
        .height = height + 2,
    };
    ctx.renderer.drawRectOutline(outer_rect, Color.black, 1.0);

    const inner_rect = Rect{
        .x = x,
        .y = y - height / 2,
        .width = width,
        .height = height,
    };
    ctx.renderer.drawRect(inner_rect, Color.white);
}

fn drawColorPreview(ctx: *Context, rect: Rect, color: Color) void {
    // Draw checkerboard background for alpha visualization
    if (color.a < 255) {
        const checker_size: f32 = 8;
        const cols: u32 = @intFromFloat(@ceil(rect.width / checker_size));
        const rows: u32 = @intFromFloat(@ceil(rect.height / checker_size));

        for (0..rows) |row| {
            for (0..cols) |col| {
                const is_light = (row + col) % 2 == 0;
                const checker_color = if (is_light) Color.rgb(200, 200, 200) else Color.rgb(150, 150, 150);
                ctx.renderer.drawRect(Rect{
                    .x = rect.x + @as(f32, @floatFromInt(col)) * checker_size,
                    .y = rect.y + @as(f32, @floatFromInt(row)) * checker_size,
                    .width = @min(checker_size, rect.width - @as(f32, @floatFromInt(col)) * checker_size),
                    .height = @min(checker_size, rect.height - @as(f32, @floatFromInt(row)) * checker_size),
                }, checker_color);
            }
        }
    }

    // Draw the actual color
    ctx.renderer.drawRect(rect, color);

    // Draw border
    ctx.renderer.drawRectOutline(rect, ctx.theme.panel_border, 1.0);
}

fn drawPresets(ctx: *Context, base_label: []const u8, rect: Rect, presets: []const Color, state: *ColorPickerState) void {
    const swatch_size: f32 = 20;
    const swatch_gap: f32 = 4;
    const swatches_per_row: u32 = @intFromFloat(@floor((rect.width + swatch_gap) / (swatch_size + swatch_gap)));

    for (presets, 0..) |preset, i| {
        const row: u32 = @intCast(i / swatches_per_row);
        const col: u32 = @intCast(i % swatches_per_row);

        const swatch_rect = Rect{
            .x = rect.x + @as(f32, @floatFromInt(col)) * (swatch_size + swatch_gap),
            .y = rect.y + @as(f32, @floatFromInt(row)) * (swatch_size + swatch_gap),
            .width = swatch_size,
            .height = swatch_size,
        };

        // Create unique ID for this swatch
        var swatch_id_buf: [64]u8 = undefined;
        const swatch_id_str = std.fmt.bufPrint(&swatch_id_buf, "{s}_preset_{d}", .{ base_label, i }) catch "preset";
        const swatch_id = widgetId(swatch_id_str);
        const clicked = ctx.registerWidget(swatch_id, swatch_rect);

        // Select preset on click
        if (clicked) {
            state.setColor(preset);
        }

        // Draw swatch
        ctx.renderer.drawRect(swatch_rect, preset);

        // Draw hover effect
        if (ctx.isHot(swatch_id)) {
            ctx.renderer.drawRectOutline(swatch_rect, Color.white, 2.0);
        } else {
            ctx.renderer.drawRectOutline(swatch_rect, ctx.theme.panel_border.darken(0.5), 1.0);
        }
    }
}

fn drawColorInfo(ctx: *Context, rect: Rect, color: Color, options: ColorPickerOptions) void {
    const text_size = ctx.theme.font_size_small;
    var buf: [32]u8 = undefined;
    var x = rect.x;

    if (options.show_hex) {
        const hex_str = formatHex(color, options.show_alpha, &buf);
        ctx.renderer.drawText(hex_str, Vec2{ .x = x, .y = rect.y }, text_size, ctx.theme.text_primary);
        x += 80;
    }

    if (options.show_rgb) {
        const rgb_str = std.fmt.bufPrint(&buf, "R:{d} G:{d} B:{d}", .{ color.r, color.g, color.b }) catch "RGB:?";
        ctx.renderer.drawText(rgb_str, Vec2{ .x = x, .y = rect.y }, text_size, ctx.theme.text_primary);
    }
}

// ============================================================================
// Tests
// ============================================================================

test "HSV to RGB conversion" {
    // Red (H=0)
    const red = hsvToRgb(0, 1, 1);
    try std.testing.expectEqual(@as(u8, 255), red.r);
    try std.testing.expectEqual(@as(u8, 0), red.g);
    try std.testing.expectEqual(@as(u8, 0), red.b);

    // Green (H=120)
    const green = hsvToRgb(120, 1, 1);
    try std.testing.expectEqual(@as(u8, 0), green.r);
    try std.testing.expectEqual(@as(u8, 255), green.g);
    try std.testing.expectEqual(@as(u8, 0), green.b);

    // Blue (H=240)
    const blue = hsvToRgb(240, 1, 1);
    try std.testing.expectEqual(@as(u8, 0), blue.r);
    try std.testing.expectEqual(@as(u8, 0), blue.g);
    try std.testing.expectEqual(@as(u8, 255), blue.b);

    // White (S=0, V=1)
    const white = hsvToRgb(0, 0, 1);
    try std.testing.expectEqual(@as(u8, 255), white.r);
    try std.testing.expectEqual(@as(u8, 255), white.g);
    try std.testing.expectEqual(@as(u8, 255), white.b);

    // Black (V=0)
    const black = hsvToRgb(0, 1, 0);
    try std.testing.expectEqual(@as(u8, 0), black.r);
    try std.testing.expectEqual(@as(u8, 0), black.g);
    try std.testing.expectEqual(@as(u8, 0), black.b);
}

test "RGB to HSV conversion" {
    // Red
    const red_hsv = rgbToHsv(Color.rgb(255, 0, 0));
    try std.testing.expectApproxEqAbs(@as(f32, 0), red_hsv.h, 0.1);
    try std.testing.expectApproxEqAbs(@as(f32, 1), red_hsv.s, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 1), red_hsv.v, 0.01);

    // Green
    const green_hsv = rgbToHsv(Color.rgb(0, 255, 0));
    try std.testing.expectApproxEqAbs(@as(f32, 120), green_hsv.h, 0.1);
    try std.testing.expectApproxEqAbs(@as(f32, 1), green_hsv.s, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 1), green_hsv.v, 0.01);

    // Blue
    const blue_hsv = rgbToHsv(Color.rgb(0, 0, 255));
    try std.testing.expectApproxEqAbs(@as(f32, 240), blue_hsv.h, 0.1);
    try std.testing.expectApproxEqAbs(@as(f32, 1), blue_hsv.s, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 1), blue_hsv.v, 0.01);

    // Gray (no saturation)
    const gray_hsv = rgbToHsv(Color.rgb(128, 128, 128));
    try std.testing.expectApproxEqAbs(@as(f32, 0), gray_hsv.s, 0.01);
}

test "HSV round-trip" {
    // Test that RGB -> HSV -> RGB preserves color
    const colors = [_]Color{
        Color.rgb(255, 128, 64),
        Color.rgb(64, 128, 255),
        Color.rgb(100, 200, 50),
        Color.rgb(200, 100, 150),
    };

    for (colors) |original| {
        const hsv = rgbToHsv(original);
        const back = hsv.toRgb();

        // Allow small rounding errors
        try std.testing.expect(@abs(@as(i16, @intCast(original.r)) - @as(i16, @intCast(back.r))) <= 1);
        try std.testing.expect(@abs(@as(i16, @intCast(original.g)) - @as(i16, @intCast(back.g))) <= 1);
        try std.testing.expect(@abs(@as(i16, @intCast(original.b)) - @as(i16, @intCast(back.b))) <= 1);
    }
}

test "hex parsing - short form" {
    const rgb = parseHex("#F80") orelse unreachable;
    try std.testing.expectEqual(@as(u8, 255), rgb.r);
    try std.testing.expectEqual(@as(u8, 136), rgb.g);
    try std.testing.expectEqual(@as(u8, 0), rgb.b);
    try std.testing.expectEqual(@as(u8, 255), rgb.a);

    const rgba = parseHex("F80A") orelse unreachable;
    try std.testing.expectEqual(@as(u8, 170), rgba.a);
}

test "hex parsing - long form" {
    const rgb = parseHex("#FF8800") orelse unreachable;
    try std.testing.expectEqual(@as(u8, 255), rgb.r);
    try std.testing.expectEqual(@as(u8, 136), rgb.g);
    try std.testing.expectEqual(@as(u8, 0), rgb.b);
    try std.testing.expectEqual(@as(u8, 255), rgb.a);

    const rgba = parseHex("FF8800AA") orelse unreachable;
    try std.testing.expectEqual(@as(u8, 170), rgba.a);
}

test "hex parsing - invalid" {
    try std.testing.expect(parseHex("invalid") == null);
    try std.testing.expect(parseHex("#GGG") == null);
    try std.testing.expect(parseHex("#12") == null);
}

test "hex formatting" {
    var buf: [16]u8 = undefined;

    const hex_no_alpha = formatHex(Color.rgb(255, 128, 0), false, &buf);
    try std.testing.expectEqualStrings("#FF8000", hex_no_alpha);

    const hex_with_alpha = formatHex(Color.init(255, 128, 0, 170), true, &buf);
    try std.testing.expectEqualStrings("#FF8000AA", hex_with_alpha);
}

test "ColorPickerState - get and set color" {
    var state = ColorPickerState{};

    // Set a color
    state.setColor(Color.init(255, 128, 64, 200));

    // Get it back
    const color = state.getColor();
    try std.testing.expectEqual(@as(u8, 200), color.a);

    // RGB values should be close (may have small rounding errors from HSV conversion)
    try std.testing.expect(@abs(@as(i16, 255) - @as(i16, @intCast(color.r))) <= 1);
    try std.testing.expect(@abs(@as(i16, 128) - @as(i16, @intCast(color.g))) <= 1);
    try std.testing.expect(@abs(@as(i16, 64) - @as(i16, @intCast(color.b))) <= 1);
}

test "ColorPickerState - set from hex" {
    var state = ColorPickerState{};

    try std.testing.expect(state.setFromHex("#FF8040"));

    const color = state.getColor();
    try std.testing.expect(@abs(@as(i16, 255) - @as(i16, @intCast(color.r))) <= 1);
    try std.testing.expect(@abs(@as(i16, 128) - @as(i16, @intCast(color.g))) <= 1);
    try std.testing.expect(@abs(@as(i16, 64) - @as(i16, @intCast(color.b))) <= 1);

    // Invalid hex should return false and not change color
    const prev_color = state.getColor();
    try std.testing.expect(!state.setFromHex("invalid"));
    const new_color = state.getColor();
    try std.testing.expectEqual(prev_color.r, new_color.r);
}
