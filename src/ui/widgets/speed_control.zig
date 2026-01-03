//! Speed Control Widget - UI for game speed management
//!
//! Provides pause/play button, speed preset buttons, and current speed display.
//!
//! Usage:
//! ```zig
//! const engine = @import("AgentiteZ");
//! const ui = engine.ui;
//! const GameSpeed = engine.game_speed.GameSpeed;
//!
//! var game_speed = GameSpeed.init(.{});
//!
//! // Full widget with all presets
//! ui.speedControl(ctx, &game_speed, rect, .{});
//!
//! // Auto-layout version
//! ui.speedControlAuto(ctx, &game_speed, .{});
//!
//! // Compact version (just pause + speed indicator)
//! ui.speedControlCompact(ctx, &game_speed, rect);
//! ```

const std = @import("std");
const context_mod = @import("../context.zig");
const types = @import("../types.zig");
const game_speed_mod = @import("../../game_speed.zig");

pub const Context = context_mod.Context;
pub const widgetId = types.widgetId;
pub const Rect = types.Rect;
pub const Vec2 = types.Vec2;
pub const Color = types.Color;
pub const GameSpeed = game_speed_mod.GameSpeed;
pub const SpeedPreset = game_speed_mod.SpeedPreset;

/// Options for the speed control widget
pub const SpeedControlOptions = struct {
    /// Show keyboard shortcut hints below the control
    show_shortcuts: bool = false,
    /// Show current multiplier value as text
    show_multiplier: bool = true,
};

/// Speed control result indicating what changed
pub const SpeedControlResult = struct {
    /// Speed was changed (preset or custom)
    speed_changed: bool = false,
    /// Pause state was toggled
    pause_toggled: bool = false,
};

/// Full speed control widget with pause button and speed presets
///
/// Layout:
/// ```
/// +--------------------------------------------+
/// | [||]  [0.5x] [1x] [2x] [4x]   Speed: 2x    |
/// +--------------------------------------------+
/// ```
pub fn speedControl(
    ctx: *Context,
    game_speed: *GameSpeed,
    rect: Rect,
    options: SpeedControlOptions,
) SpeedControlResult {
    var result = SpeedControlResult{};

    const padding: f32 = 8;
    const button_width: f32 = 50;
    const button_height: f32 = rect.height - padding * 2;
    const button_spacing: f32 = 4;

    var x = rect.x + padding;
    const y = rect.y + padding;

    // Draw background panel
    ctx.renderer.drawRect(rect, ctx.theme.panel_bg);
    ctx.renderer.drawRectOutline(rect, ctx.theme.panel_border, ctx.theme.border_thickness);

    // Pause/Play button
    const pause_rect = Rect{
        .x = x,
        .y = y,
        .width = button_width,
        .height = button_height,
    };

    const pause_id = widgetId("speed_pause");
    const pause_clicked = ctx.registerWidget(pause_id, pause_rect);

    if (pause_clicked) {
        game_speed.togglePause();
        result.pause_toggled = true;
    }

    // Pause button appearance
    const pause_bg = if (ctx.isActive(pause_id))
        ctx.theme.button_pressed
    else if (ctx.isHot(pause_id))
        ctx.theme.button_hover
    else if (game_speed.isPaused())
        Color.warning_amber // Highlight when paused
    else
        ctx.theme.button_normal;

    ctx.renderer.drawRect(pause_rect, pause_bg);
    ctx.renderer.drawRectOutline(pause_rect, ctx.theme.button_border, ctx.theme.border_thickness);

    // Pause/Play icon (text based)
    const pause_text = if (game_speed.isPaused()) ">" else "||";
    const pause_text_size = ctx.theme.font_size_normal;
    const pause_bounds = ctx.renderer.measureText(pause_text, pause_text_size);
    const pause_baseline = ctx.renderer.getBaselineOffset(pause_text_size);
    ctx.renderer.drawText(pause_text, .{
        .x = pause_rect.x + (pause_rect.width - pause_bounds.x) / 2,
        .y = pause_rect.y + pause_rect.height / 2 - pause_baseline,
    }, pause_text_size, ctx.theme.button_text);

    x += button_width + button_spacing * 2;

    // Speed preset buttons
    const current_preset = game_speed.getCurrentPreset();
    for (SpeedPreset.playable) |preset| {
        const preset_rect = Rect{
            .x = x,
            .y = y,
            .width = button_width,
            .height = button_height,
        };

        // Use preset name for unique ID
        const preset_id = widgetId(preset.getShortName());
        const preset_clicked = ctx.registerWidget(preset_id, preset_rect);

        if (preset_clicked) {
            game_speed.setPreset(preset);
            result.speed_changed = true;
        }

        // Highlight selected preset
        const is_selected = if (current_preset) |cp| cp == preset else false;
        const preset_bg = if (ctx.isActive(preset_id))
            ctx.theme.button_pressed
        else if (ctx.isHot(preset_id))
            ctx.theme.button_hover
        else if (is_selected and !game_speed.isPaused())
            Color.imperial_gold
        else
            ctx.theme.button_normal;

        ctx.renderer.drawRect(preset_rect, preset_bg);
        ctx.renderer.drawRectOutline(preset_rect, ctx.theme.button_border, ctx.theme.border_thickness);

        // Preset label
        const preset_label = preset.getShortName();
        const label_size = ctx.theme.font_size_small;
        const label_bounds = ctx.renderer.measureText(preset_label, label_size);
        const label_baseline = ctx.renderer.getBaselineOffset(label_size);
        const label_color = if (is_selected and !game_speed.isPaused())
            Color.init(0, 0, 0, 255) // Dark text on gold
        else
            ctx.theme.button_text;
        ctx.renderer.drawText(preset_label, .{
            .x = preset_rect.x + (preset_rect.width - label_bounds.x) / 2,
            .y = preset_rect.y + preset_rect.height / 2 - label_baseline,
        }, label_size, label_color);

        x += button_width + button_spacing;
    }

    // Current speed display
    if (options.show_multiplier) {
        var speed_buf: [16]u8 = undefined;
        const speed_str = game_speed.getSpeedString(&speed_buf);
        const speed_label = std.fmt.bufPrint(&speed_buf, "Speed: {s}", .{speed_str}) catch "Speed: ?";

        const display_size = ctx.theme.font_size_normal;
        const display_bounds = ctx.renderer.measureText(speed_label, display_size);
        const display_baseline = ctx.renderer.getBaselineOffset(display_size);
        const display_x = rect.x + rect.width - padding - display_bounds.x;
        const display_y = rect.y + rect.height / 2 - display_baseline;

        const display_color = if (game_speed.isPaused())
            Color.warning_amber
        else
            ctx.theme.text_primary;

        ctx.renderer.drawText(speed_label, .{ .x = display_x, .y = display_y }, display_size, display_color);
    }

    // Keyboard shortcut hints
    if (options.show_shortcuts) {
        const hint_text = "Space: Pause  +/-: Speed";
        const hint_size = ctx.theme.font_size_small;
        const hint_bounds = ctx.renderer.measureText(hint_text, hint_size);
        ctx.renderer.drawText(hint_text, .{
            .x = rect.x + (rect.width - hint_bounds.x) / 2,
            .y = rect.y + rect.height + 4,
        }, hint_size, ctx.theme.text_secondary);
    }

    return result;
}

/// Auto-layout speed control (uses cursor position)
pub fn speedControlAuto(
    ctx: *Context,
    game_speed: *GameSpeed,
    options: SpeedControlOptions,
) SpeedControlResult {
    const width: f32 = 400;
    const height: f32 = 44;

    const rect = Rect{
        .x = ctx.cursor.x,
        .y = ctx.cursor.y,
        .width = width,
        .height = height,
    };

    const result = speedControl(ctx, game_speed, rect, options);

    // Advance cursor
    var total_height = height;
    if (options.show_shortcuts) {
        total_height += ctx.theme.font_size_small + 8;
    }
    ctx.advanceCursor(total_height, ctx.theme.widget_spacing);

    return result;
}

/// Compact speed control (pause button + speed indicator only)
///
/// Layout:
/// ```
/// +-------------+
/// | [>]  2x     |
/// +-------------+
/// ```
pub fn speedControlCompact(
    ctx: *Context,
    game_speed: *GameSpeed,
    rect: Rect,
) SpeedControlResult {
    var result = SpeedControlResult{};

    const padding: f32 = 4;
    const button_size: f32 = rect.height - padding * 2;

    // Draw background
    ctx.renderer.drawRect(rect, ctx.theme.panel_bg);
    ctx.renderer.drawRectOutline(rect, ctx.theme.panel_border, ctx.theme.border_thickness);

    // Pause/Play button
    const pause_rect = Rect{
        .x = rect.x + padding,
        .y = rect.y + padding,
        .width = button_size,
        .height = button_size,
    };

    const pause_id = widgetId("speed_compact_pause");
    const pause_clicked = ctx.registerWidget(pause_id, pause_rect);

    if (pause_clicked) {
        game_speed.togglePause();
        result.pause_toggled = true;
    }

    const pause_bg = if (ctx.isActive(pause_id))
        ctx.theme.button_pressed
    else if (ctx.isHot(pause_id))
        ctx.theme.button_hover
    else if (game_speed.isPaused())
        Color.warning_amber
    else
        ctx.theme.button_normal;

    ctx.renderer.drawRect(pause_rect, pause_bg);
    ctx.renderer.drawRectOutline(pause_rect, ctx.theme.button_border, ctx.theme.border_thickness);

    const pause_text = if (game_speed.isPaused()) ">" else "||";
    const pause_text_size = ctx.theme.font_size_small;
    const pause_bounds = ctx.renderer.measureText(pause_text, pause_text_size);
    const pause_baseline = ctx.renderer.getBaselineOffset(pause_text_size);
    ctx.renderer.drawText(pause_text, .{
        .x = pause_rect.x + (pause_rect.width - pause_bounds.x) / 2,
        .y = pause_rect.y + pause_rect.height / 2 - pause_baseline,
    }, pause_text_size, ctx.theme.button_text);

    // Speed display
    var speed_buf: [16]u8 = undefined;
    const speed_str = game_speed.getSpeedString(&speed_buf);

    const display_size = ctx.theme.font_size_normal;
    const display_bounds = ctx.renderer.measureText(speed_str, display_size);
    const display_baseline = ctx.renderer.getBaselineOffset(display_size);
    const display_x = pause_rect.x + pause_rect.width + padding * 2;
    const display_y = rect.y + rect.height / 2 - display_baseline;

    const display_color = if (game_speed.isPaused())
        Color.warning_amber
    else
        ctx.theme.text_primary;

    ctx.renderer.drawText(speed_str, .{ .x = display_x, .y = display_y }, display_size, display_color);

    // Click on speed text to cycle
    const speed_text_rect = Rect{
        .x = display_x,
        .y = rect.y + padding,
        .width = display_bounds.x + padding * 2,
        .height = rect.height - padding * 2,
    };
    const speed_id = widgetId("speed_compact_cycle");
    const speed_clicked = ctx.registerWidget(speed_id, speed_text_rect);

    if (speed_clicked and !game_speed.isPaused()) {
        game_speed.cycleSpeed();
        result.speed_changed = true;
    }

    return result;
}

/// Auto-layout compact speed control
pub fn speedControlCompactAuto(
    ctx: *Context,
    game_speed: *GameSpeed,
) SpeedControlResult {
    const width: f32 = 100;
    const height: f32 = 32;

    const rect = Rect{
        .x = ctx.cursor.x,
        .y = ctx.cursor.y,
        .width = width,
        .height = height,
    };

    const result = speedControlCompact(ctx, game_speed, rect);
    ctx.advanceCursor(height, ctx.theme.widget_spacing);

    return result;
}

// ============================================================================
// Tests
// ============================================================================

test "SpeedControlOptions defaults" {
    const opts = SpeedControlOptions{};
    try std.testing.expectEqual(false, opts.show_shortcuts);
    try std.testing.expectEqual(true, opts.show_multiplier);
}

test "SpeedControlResult defaults" {
    const result = SpeedControlResult{};
    try std.testing.expectEqual(false, result.speed_changed);
    try std.testing.expectEqual(false, result.pause_toggled);
}

test "GameSpeed integration - preset selection" {
    var game_speed = GameSpeed.init(.{});
    try std.testing.expectEqual(SpeedPreset.normal, game_speed.getCurrentPreset().?);

    game_speed.setPreset(.fast);
    try std.testing.expectEqual(SpeedPreset.fast, game_speed.getCurrentPreset().?);
    try std.testing.expectEqual(@as(f32, 2.0), game_speed.getSpeedMultiplier());
}

test "GameSpeed integration - pause toggle" {
    var game_speed = GameSpeed.init(.{});
    try std.testing.expectEqual(false, game_speed.isPaused());

    game_speed.togglePause();
    try std.testing.expectEqual(true, game_speed.isPaused());
    try std.testing.expectEqual(SpeedPreset.pause, game_speed.getCurrentPreset().?);

    game_speed.togglePause();
    try std.testing.expectEqual(false, game_speed.isPaused());
}

test "GameSpeed integration - cycle speed" {
    var game_speed = GameSpeed.init(.{});
    try std.testing.expectEqual(SpeedPreset.normal, game_speed.getCurrentPreset().?);

    game_speed.cycleSpeed();
    try std.testing.expectEqual(SpeedPreset.fast, game_speed.getCurrentPreset().?);

    game_speed.cycleSpeed();
    try std.testing.expectEqual(SpeedPreset.very_fast, game_speed.getCurrentPreset().?);
}
