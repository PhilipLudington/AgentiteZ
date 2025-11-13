const std = @import("std");
const context_mod = @import("../context.zig");
const types = @import("../types.zig");

pub const Context = context_mod.Context;
pub const widgetId = types.widgetId;
pub const Rect = types.Rect;
pub const Vec2 = types.Vec2;
pub const Color = types.Color;

/// Panel widget with Imperial salvaged tech decorations
pub fn beginPanel(ctx: *Context, panel_label: []const u8, rect: Rect, bg_color: Color) !void {
    const id = widgetId(panel_label);
    _ = ctx.registerWidget(id, rect);

    // Draw panel background
    ctx.renderer.drawRect(rect, bg_color);

    // Draw subtle grid pattern overlay for tech aesthetic
    drawPanelGrid(ctx, rect);

    // Draw panel border with Imperial styling
    ctx.renderer.drawRectOutline(rect, ctx.theme.panel_border, ctx.theme.border_thickness);

    // Draw corner reinforcements/bolts (like jury-rigged panels)
    const corner_size: f32 = 8;
    const corners = [_]Rect{
        // Top-left
        Rect{ .x = rect.x + 2, .y = rect.y + 2, .width = corner_size, .height = corner_size },
        // Top-right
        Rect{ .x = rect.x + rect.width - corner_size - 2, .y = rect.y + 2, .width = corner_size, .height = corner_size },
        // Bottom-left
        Rect{ .x = rect.x + 2, .y = rect.y + rect.height - corner_size - 2, .width = corner_size, .height = corner_size },
        // Bottom-right
        Rect{ .x = rect.x + rect.width - corner_size - 2, .y = rect.y + rect.height - corner_size - 2, .width = corner_size, .height = corner_size },
    };

    for (corners) |corner_rect| {
        // Draw corner bolt/reinforcement
        ctx.renderer.drawRectOutline(corner_rect, Color.imperial_gold, 1.0);
        // Inner detail
        const inner = Rect{
            .x = corner_rect.x + 2,
            .y = corner_rect.y + 2,
            .width = corner_rect.width - 4,
            .height = corner_rect.height - 4,
        };
        ctx.renderer.drawRect(inner, Color.imperial_dark_gold);
    }

    // Push layout for children
    try ctx.pushLayout(Rect{
        .x = rect.x + 10, // 10px padding
        .y = rect.y + 10,
        .width = rect.width - 20,
        .height = rect.height - 20,
    });
}

/// Draw subtle grid pattern for tech aesthetic
fn drawPanelGrid(ctx: *Context, rect: Rect) void {
    const grid_color = Color.oxidized_copper.darken(0.3);
    const grid_spacing: f32 = 20;

    // Vertical lines
    var x = rect.x + grid_spacing;
    while (x < rect.x + rect.width) : (x += grid_spacing) {
        const line_rect = Rect{
            .x = x,
            .y = rect.y,
            .width = 1,
            .height = rect.height,
        };
        ctx.renderer.drawRect(line_rect, grid_color);
    }

    // Horizontal lines
    var y = rect.y + grid_spacing;
    while (y < rect.y + rect.height) : (y += grid_spacing) {
        const line_rect = Rect{
            .x = rect.x,
            .y = y,
            .width = rect.width,
            .height = 1,
        };
        ctx.renderer.drawRect(line_rect, grid_color);
    }
}

/// End panel
pub fn endPanel(ctx: *Context) void {
    ctx.popLayout();
}
