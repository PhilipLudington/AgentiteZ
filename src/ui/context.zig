const std = @import("std");
const types = @import("types.zig");
const renderer_mod = @import("renderer.zig");
const dpi_mod = @import("dpi.zig");

pub const WidgetId = types.WidgetId;
pub const widgetId = types.widgetId;
pub const Rect = types.Rect;
pub const Vec2 = types.Vec2;
pub const Color = types.Color;
pub const InputState = types.InputState;
pub const Theme = types.Theme;
pub const Renderer = renderer_mod.Renderer;
pub const DpiConfig = dpi_mod.DpiConfig;

/// Widget state tracked between frames
const WidgetState = struct {
    hot: bool = false, // Mouse is over widget
    active: bool = false, // Widget is being interacted with
    rect: Rect = undefined,
};

/// Overlay rendering callback - stores a function to call at end of frame
const OverlayCallback = struct {
    render_fn: *const fn (ctx: *Context, data: *anyopaque) void,
    data: *anyopaque,
};

/// Dropdown overlay data for deferred rendering (to avoid heap allocation per frame)
pub const DropdownOverlay = struct {
    list_rect: Rect,
    options: []const []const u8,
    selected_index: usize,
    text_size: f32,
    item_height: f32,
    state_ptr: *anyopaque,  // Pointer to DropdownState
};

/// UI Context - manages state for hybrid immediate mode UI
pub const Context = struct {
    allocator: std.mem.Allocator,
    renderer: Renderer,
    input: InputState,

    /// Widget states (persistent between frames)
    widget_states: std.AutoHashMap(WidgetId, WidgetState),

    /// Current hot widget (mouse over)
    hot_widget: ?WidgetId = null,
    /// Current active widget (being clicked)
    active_widget: ?WidgetId = null,
    /// Previous frame's active widget (for click detection)
    prev_active_widget: ?WidgetId = null,
    /// Currently focused widget (for text input)
    focused_widget: ?WidgetId = null,

    /// Tooltip state
    tooltip_text: ?[]const u8 = null,
    tooltip_rect: Rect = undefined,
    tooltip_hover_frames: u32 = 0,

    /// Current layout cursor (for automatic positioning)
    cursor: Vec2,
    /// Layout stack for nested containers
    layout_stack: std.ArrayList(Rect),

    /// DPI configuration for automatic scaling
    dpi_config: DpiConfig,

    /// UI Theme
    theme: Theme,

    /// Deferred overlay rendering callbacks (rendered at end of frame for proper z-ordering)
    overlay_callbacks: std.ArrayList(OverlayCallback),

    /// Deferred dropdown overlays (rendered at end of frame on top of everything)
    dropdown_overlays: std.ArrayList(DropdownOverlay),

    pub fn init(allocator: std.mem.Allocator, renderer: Renderer) Context {
        // Use mock DPI config - TODO: pass window info when available
        const dpi_config = DpiConfig.initMock();

        return .{
            .allocator = allocator,
            .renderer = renderer,
            .input = InputState.init(),
            .widget_states = std.AutoHashMap(WidgetId, WidgetState).init(allocator),
            .cursor = Vec2.init(0, 0),
            .layout_stack = .{},
            .dpi_config = dpi_config,
            .theme = Theme.imperial(), // Default to Imperial salvaged tech theme
            .overlay_callbacks = .{},
            .dropdown_overlays = .{},
        };
    }

    pub fn deinit(self: *Context) void {
        self.widget_states.deinit();
        self.layout_stack.deinit(self.allocator);
        self.overlay_callbacks.deinit(self.allocator);
        self.dropdown_overlays.deinit(self.allocator);
    }

    /// Begin a new frame
    pub fn beginFrame(self: *Context, input: InputState) void {
        // Update DPI config if monitor changed or window resized
        // TODO: Pass WindowInfo from caller to update DPI config
        // _ = self.dpi_config.updateIfNeeded(window_info);

        // Apply automatic mouse coordinate scaling if needed
        var scaled_input = input;
        if (self.dpi_config.auto_scale_mouse) {
            scaled_input.mouse_pos = self.dpi_config.toLogical(input.mouse_pos);
        }

        self.input = scaled_input;
        self.cursor = Vec2.init(0, 0);

        // Save previous active widget for click detection
        self.prev_active_widget = self.active_widget;

        // Reset hot widget (will be set by widgets this frame)
        self.hot_widget = null;

        // Clear active widget if mouse released
        if (self.input.mouse_released) {
            self.active_widget = null;
        }

        // Reset tooltip for this frame
        self.tooltip_text = null;

        // Clear overlay callbacks from previous frame
        self.overlay_callbacks.clearRetainingCapacity();
        self.dropdown_overlays.clearRetainingCapacity();
    }

    /// End the frame - renders deferred overlays
    pub fn endFrame(self: *Context) void {
        // Render all deferred overlays (dropdowns, tooltips, modals, etc.)
        for (self.overlay_callbacks.items) |callback| {
            callback.render_fn(self, callback.data);
        }

        // ALWAYS flush existing batches before rendering dropdown overlays
        // This ensures overlays are drawn on top in a separate draw call
        std.debug.print("endFrame: Flushing main widgets... ({d} dropdowns pending)\n", .{self.dropdown_overlays.items.len});
        self.renderer.flushBatches();

        // Render all deferred dropdown overlays
        for (self.dropdown_overlays.items) |overlay| {
            renderDropdownOverlay(self, overlay);
        }

        // CRITICAL: Flush overlay batches immediately so they don't get cleared by next beginFrame
        if (self.dropdown_overlays.items.len > 0) {
            std.debug.print("endFrame: Flushing dropdown overlays...\n", .{});
            self.renderer.flushBatches();
        }

        // Clean up old widget states that weren't used this frame
        // (In a full implementation, you'd mark widgets as "alive" and prune dead ones)
    }

    /// Render a single dropdown overlay
    fn renderDropdownOverlay(ctx: *Context, overlay: DropdownOverlay) void {
        const dropdown_overlay = @import("dropdown_overlay.zig");
        dropdown_overlay.renderDropdownList(ctx, overlay);
    }

    /// Check if widget is hot (mouse over)
    pub fn isHot(self: *Context, id: WidgetId) bool {
        return self.hot_widget == id;
    }

    /// Check if widget is active (being clicked)
    pub fn isActive(self: *Context, id: WidgetId) bool {
        return self.active_widget == id;
    }

    /// Check if widget is focused (for text input)
    pub fn isFocused(self: *Context, id: WidgetId) bool {
        return self.focused_widget == id;
    }

    /// Set focus to a widget
    pub fn setFocus(self: *Context, id: WidgetId) void {
        self.focused_widget = id;
    }

    /// Clear focus
    pub fn clearFocus(self: *Context) void {
        self.focused_widget = null;
    }

    /// Register widget interaction
    pub fn registerWidget(self: *Context, id: WidgetId, rect: Rect) bool {
        const mouse_over = rect.contains(self.input.mouse_pos);

        // Check for click (widget was active last frame and released this frame)
        const was_clicked = self.prev_active_widget == id and self.input.mouse_released and mouse_over;

        // Update hot widget - allow updating even if another widget is active,
        // but give priority to mouse position (widgets drawn last have priority)
        if (mouse_over) {
            self.hot_widget = id;
        }

        // Update active widget
        // FIX: Use mouse_over directly instead of isHot(id) because hot_widget
        // can be overwritten by subsequent widgets in the same frame
        if (mouse_over and self.input.mouse_clicked) {
            self.active_widget = id;
        }

        // Update widget state
        var state = self.widget_states.get(id) orelse WidgetState{};
        state.hot = self.isHot(id);
        state.active = self.isActive(id);
        state.rect = rect;
        self.widget_states.put(id, state) catch {};

        return was_clicked;
    }

    /// Push a layout container
    pub fn pushLayout(self: *Context, rect: Rect) !void {
        try self.layout_stack.append(self.allocator, rect);
        self.cursor = Vec2.init(rect.x, rect.y);
    }

    /// Pop a layout container
    pub fn popLayout(self: *Context) void {
        if (self.layout_stack.items.len > 0) {
            _ = self.layout_stack.pop();

            // Restore cursor to parent layout
            if (self.layout_stack.items.len > 0) {
                const parent = self.layout_stack.items[self.layout_stack.items.len - 1];
                self.cursor = Vec2.init(parent.x, parent.y);
            } else {
                self.cursor = Vec2.init(0, 0);
            }
        }
    }

    /// Queue an overlay to be rendered at the end of the frame (for proper z-ordering)
    pub fn deferOverlay(self: *Context, render_fn: *const fn (ctx: *Context, data: *anyopaque) void, data: *anyopaque) void {
        self.overlay_callbacks.append(self.allocator, .{
            .render_fn = render_fn,
            .data = data,
        }) catch {
            // If we can't append, just render immediately as fallback
            render_fn(self, data);
        };
    }

    /// Advance layout cursor
    pub fn advanceCursor(self: *Context, height: f32, spacing: f32) void {
        self.cursor.y += height + spacing;
    }

    /// Set tooltip for current hot widget
    pub fn setTooltip(self: *Context, text: []const u8, widget_rect: Rect) void {
        if (self.hot_widget != null) {
            self.tooltip_text = text;
            self.tooltip_rect = widget_rect;
        }
    }
};

test "Context - widget interaction" {
    const NullRenderer = renderer_mod.NullRenderer;
    var null_renderer = NullRenderer{};
    const renderer = Renderer.init(&null_renderer);

    var ctx = Context.init(std.testing.allocator, renderer);
    defer ctx.deinit();

    const button_id = widgetId("test_button");
    const button_rect = Rect.init(10, 10, 100, 30);

    // Frame 1: Mouse over button
    ctx.beginFrame(.{
        .mouse_pos = .{ .x = 50, .y = 20 }, // inside button
        .mouse_down = false,
        .mouse_clicked = false,
        .mouse_released = false,
        .mouse_button = .left,
    });

    const clicked1 = ctx.registerWidget(button_id, button_rect);
    try std.testing.expect(!clicked1); // Not clicked yet
    try std.testing.expect(ctx.isHot(button_id)); // But is hot
    try std.testing.expect(!ctx.isActive(button_id));

    ctx.endFrame();

    // Frame 2: Click button
    ctx.beginFrame(.{
        .mouse_pos = .{ .x = 50, .y = 20 },
        .mouse_down = true,
        .mouse_clicked = true, // Click started this frame
        .mouse_released = false,
        .mouse_button = .left,
    });

    const clicked2 = ctx.registerWidget(button_id, button_rect);
    try std.testing.expect(!clicked2); // Not clicked until released
    try std.testing.expect(ctx.isActive(button_id)); // Now active

    ctx.endFrame();

    // Frame 3: Release button
    ctx.beginFrame(.{
        .mouse_pos = .{ .x = 50, .y = 20 },
        .mouse_down = false,
        .mouse_clicked = false,
        .mouse_released = true, // Released this frame
        .mouse_button = .left,
    });

    const clicked3 = ctx.registerWidget(button_id, button_rect);
    try std.testing.expect(clicked3); // Now it's clicked!

    ctx.endFrame();
}
