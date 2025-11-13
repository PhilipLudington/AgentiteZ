const std = @import("std");
const context_mod = @import("../context.zig");
const types = @import("../types.zig");

pub const Context = context_mod.Context;
pub const widgetId = types.widgetId;
pub const Rect = types.Rect;
pub const Vec2 = types.Vec2;
pub const Color = types.Color;

/// Progress bar widget
pub fn progressBar(ctx: *Context, label_text: []const u8, rect: Rect, progress: f32, show_percentage: bool) void {
    const id = widgetId(label_text);
    _ = ctx.registerWidget(id, rect);

    // Clamp progress to 0-1 range
    const clamped_progress = std.math.clamp(progress, 0.0, 1.0);

    // Draw background (empty part)
    ctx.renderer.drawRect(rect, Color.rgb(200, 200, 200));
    ctx.renderer.drawRectOutline(rect, Color.rgb(100, 100, 100), 1.0);

    // Draw filled portion (progress)
    if (clamped_progress > 0.0) {
        const fill_width = rect.width * clamped_progress;
        const fill_rect = Rect{
            .x = rect.x,
            .y = rect.y,
            .width = fill_width,
            .height = rect.height,
        };

        // Color gradient based on progress (red -> yellow -> green)
        const fill_color = if (clamped_progress < 0.33)
            Color.rgb(220, 80, 80) // Red for low progress
        else if (clamped_progress < 0.66)
            Color.rgb(220, 180, 60) // Yellow for medium progress
        else
            Color.rgb(80, 200, 80); // Green for high progress

        ctx.renderer.drawRect(fill_rect, fill_color);
    }

    // Draw percentage text if requested
    if (show_percentage) {
        const text_size: f32 = 14;
        var text_buf: [32]u8 = undefined;
        const percentage = @as(i32, @intFromFloat(clamped_progress * 100));
        const text = std.fmt.bufPrint(&text_buf, "{d}%", .{percentage}) catch "??%";

        const text_bounds = ctx.renderer.measureText(text, text_size);
        const baseline_offset = ctx.renderer.getBaselineOffset(text_size);
        const text_pos = Vec2{
            .x = rect.x + (rect.width - text_bounds.x) / 2,
            .y = rect.y + rect.height / 2 - baseline_offset,
        };
        ctx.renderer.drawText(text, text_pos, text_size, Color.black);
    }

    // Draw label above the progress bar
    if (label_text.len > 0) {
        const label_size: f32 = 12;
        const label_pos = Vec2{
            .x = rect.x,
            .y = rect.y - 4,
        };
        ctx.renderer.drawText(label_text, label_pos, label_size, Color.white);
    }
}

/// Auto-layout progress bar
pub fn progressBarAuto(ctx: *Context, label_text: []const u8, width: f32, progress: f32, show_percentage: bool) void {
    const height: f32 = 24;
    const label_height: f32 = if (label_text.len > 0) 16 else 0;

    const rect = Rect{
        .x = ctx.cursor.x,
        .y = ctx.cursor.y + label_height,
        .width = width,
        .height = height,
    };

    progressBar(ctx, label_text, rect, progress, show_percentage);
    ctx.advanceCursor(height + label_height, 5);
}

/// Render tooltip at the end of frame if any widget has set one
/// Call this at the very end, after all widgets
pub fn renderTooltip(ctx: *Context) void {
    if (ctx.tooltip_text) |text| {
        // Only show tooltip after hovering for a bit
        ctx.tooltip_hover_frames += 1;
        const delay_frames: u32 = 30; // ~0.5 seconds at 60fps

        if (ctx.tooltip_hover_frames >= delay_frames) {
            const text_size: f32 = 14;
            const padding: f32 = 8;

            // Measure text to size tooltip
            const text_bounds = ctx.renderer.measureText(text, text_size);
            const tooltip_width = text_bounds.x + (padding * 2);
            const tooltip_height = text_bounds.y + (padding * 2);

            // Position tooltip below widget, centered
            var tooltip_x = ctx.tooltip_rect.x + (ctx.tooltip_rect.width / 2) - (tooltip_width / 2);
            var tooltip_y = ctx.tooltip_rect.y + ctx.tooltip_rect.height + 5;

            // Keep tooltip on screen (simple bounds check)
            if (tooltip_x < 0) tooltip_x = 0;
            if (tooltip_y < 0) tooltip_y = ctx.tooltip_rect.y - tooltip_height - 5; // Show above instead

            const tooltip_rect = Rect{
                .x = tooltip_x,
                .y = tooltip_y,
                .width = tooltip_width,
                .height = tooltip_height,
            };

            // Draw tooltip background with shadow effect
            const shadow_offset: f32 = 2;
            const shadow_rect = Rect{
                .x = tooltip_rect.x + shadow_offset,
                .y = tooltip_rect.y + shadow_offset,
                .width = tooltip_rect.width,
                .height = tooltip_rect.height,
            };
            ctx.renderer.drawRect(shadow_rect, Color.rgb(0, 0, 0)); // Shadow

            ctx.renderer.drawRect(tooltip_rect, Color.rgb(255, 255, 220)); // Light yellow background
            ctx.renderer.drawRectOutline(tooltip_rect, Color.rgb(100, 100, 100), 1.0);

            // Draw tooltip text
            const text_pos = Vec2{
                .x = tooltip_rect.x + padding,
                .y = tooltip_rect.y + padding,
            };
            ctx.renderer.drawText(text, text_pos, text_size, Color.black);
        }
    } else {
        // Reset hover counter when not hovering
        ctx.tooltip_hover_frames = 0;
    }
}
