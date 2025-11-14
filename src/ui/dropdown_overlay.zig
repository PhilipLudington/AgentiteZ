const Context = @import("context.zig").Context;
const DropdownState = @import("widgets.zig").DropdownState;
const Color = @import("types.zig").Color;
const Vec2 = @import("types.zig").Vec2;
const Rect = @import("types.zig").Rect;
const widgetId = @import("types.zig").widgetId;

/// Render a deferred dropdown list overlay (called by Context.endFrame)
pub fn renderDropdownList(ctx: *Context, overlay: anytype) void {
    // Cast state_ptr back to DropdownState
    const state: *DropdownState = @ptrCast(@alignCast(overlay.state_ptr));

    // CRITICAL: Flush any pending geometry BEFORE switching to overlay view
    // This ensures previous content is rendered with the correct scissor/view
    ctx.renderer.flushBatches();

    // Switch to overlay view - this ensures dropdown renders AFTER main UI
    // bgfx processes views in order, so view 1 will always render after view 0
    ctx.renderer.pushOverlayView();

    // Reset scissor to full window for overlay rendering
    // This ensures the dropdown renders on top without being clipped by parent widgets
    ctx.renderer.endScissor();

    // Draw list background
    ctx.renderer.drawRect(overlay.list_rect, Color.rgb(255, 255, 255)); // White background
    ctx.renderer.drawRectOutline(overlay.list_rect, Color.rgb(150, 150, 150), 1.0); // Gray border

    // Draw each option
    for (overlay.options, 0..) |option, i| {
        const item_id = widgetId(option);
        const item_rect = Rect{
            .x = overlay.list_rect.x,
            .y = overlay.list_rect.y + @as(f32, @floatFromInt(i)) * overlay.item_height,
            .width = overlay.list_rect.width,
            .height = overlay.item_height,
        };

        const item_clicked = ctx.registerWidget(item_id, item_rect);

        // Select item on click
        if (item_clicked) {
            state.selected_index = i;
            state.is_open = false;
        }

        // Draw item background
        const item_bg = if (ctx.isHot(item_id))
            Color.rgb(220, 220, 255)
        else if (i == overlay.selected_index)
            Color.rgb(240, 240, 240)
        else
            Color.rgb(255, 255, 255);
        ctx.renderer.drawRect(item_rect, item_bg);

        // Draw item text
        const item_baseline_offset = ctx.renderer.getBaselineOffset(overlay.text_size);
        const item_text_pos = Vec2{
            .x = item_rect.x + 5,
            .y = item_rect.y + overlay.item_height / 2 - item_baseline_offset,
        };
        ctx.renderer.drawText(option, item_text_pos, overlay.text_size, ctx.theme.dropdown_text);
    }

    // CRITICAL: Flush dropdown geometry immediately
    // This ensures the dropdown is rendered with the overlay view
    ctx.renderer.flushBatches();

    // Switch back to default view for subsequent rendering
    ctx.renderer.popOverlayView();
}
