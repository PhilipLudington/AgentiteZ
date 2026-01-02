/// Notification System - Toast notifications with position options, auto-dismiss, and queue management
///
/// Usage:
/// ```zig
/// // In game state
/// notification_manager: ui.NotificationManager,
///
/// // Init
/// self.notification_manager = ui.NotificationManager.init();
///
/// // Update (each frame)
/// self.notification_manager.update(delta_time);
///
/// // Show notifications
/// self.notification_manager.success("Item collected!");
/// self.notification_manager.show("Connection lost", .error_, .{ .title = "Network Error" });
///
/// // Render (after other UI)
/// ui.renderNotifications(ctx, &self.notification_manager, .{ .position = .top_right });
/// ```
const std = @import("std");
const context_mod = @import("../context.zig");
const types = @import("../types.zig");

pub const Context = context_mod.Context;
pub const widgetId = types.widgetId;
pub const Rect = types.Rect;
pub const Vec2 = types.Vec2;
pub const Color = types.Color;
pub const Theme = types.Theme;

/// Maximum number of visible notifications
pub const MAX_NOTIFICATIONS: usize = 8;

/// Virtual resolution constants (matches viewport.zig)
const VIRTUAL_WIDTH: f32 = 1920.0;
const VIRTUAL_HEIGHT: f32 = 1080.0;

/// Notification type determines color and default duration
pub const NotificationType = enum {
    info, // Blue/cyan - informational messages
    success, // Green - operation completed successfully
    warning, // Amber/yellow - warning, user should take note
    error_, // Red - error condition, may need action

    /// Get the accent color for this notification type
    pub fn getColor(self: NotificationType) Color {
        return switch (self) {
            .info => Color.tech_cyan,
            .success => Color.dim_green,
            .warning => Color.warning_amber,
            .error_ => Color.critical_red,
        };
    }

    /// Get default duration in seconds for this type
    pub fn getDefaultDuration(self: NotificationType) f32 {
        return switch (self) {
            .info => 3.0,
            .success => 3.0,
            .warning => 5.0,
            .error_ => 0.0, // 0 = no auto-dismiss, requires manual close
        };
    }
};

/// Screen position for notification stack
pub const NotificationPosition = enum {
    top_left,
    top_center,
    top_right,
    center_left,
    center,
    center_right,
    bottom_left,
    bottom_center,
    bottom_right,

    /// Check if notifications should stack downward from this position
    pub fn stacksDownward(self: NotificationPosition) bool {
        return switch (self) {
            .top_left, .top_center, .top_right => true,
            else => false,
        };
    }

    /// Get base screen position (top-left corner of first notification)
    pub fn getBasePosition(self: NotificationPosition, width: f32, height: f32, margin: f32) Vec2 {
        const x: f32 = switch (self) {
            .top_left, .center_left, .bottom_left => margin,
            .top_center, .center, .bottom_center => (VIRTUAL_WIDTH - width) / 2.0,
            .top_right, .center_right, .bottom_right => VIRTUAL_WIDTH - width - margin,
        };

        const y: f32 = switch (self) {
            .top_left, .top_center, .top_right => margin,
            .center_left, .center, .center_right => (VIRTUAL_HEIGHT - height) / 2.0,
            .bottom_left, .bottom_center, .bottom_right => VIRTUAL_HEIGHT - height - margin,
        };

        return Vec2.init(x, y);
    }
};

/// Animation phase for notification lifecycle
pub const AnimationPhase = enum {
    fade_in,
    display,
    fade_out,
    done,
};

/// Individual notification state
pub const Notification = struct {
    /// Notification content
    message: [256]u8 = [_]u8{0} ** 256,
    message_len: usize = 0,

    /// Optional title (empty = no title)
    title: [64]u8 = [_]u8{0} ** 64,
    title_len: usize = 0,

    /// Notification type
    notification_type: NotificationType = .info,

    /// Time tracking
    elapsed: f32 = 0.0,
    duration: f32 = 3.0, // Total display time (0 = infinite until dismissed)
    fade_in_duration: f32 = 0.2,
    fade_out_duration: f32 = 0.3,

    /// Current animation phase
    phase: AnimationPhase = .fade_in,

    /// Whether this slot is active
    active: bool = false,

    /// Unique ID for this notification (for widget interaction)
    id: u64 = 0,

    /// Get current opacity based on animation phase
    pub fn getOpacity(self: *const Notification) f32 {
        return switch (self.phase) {
            .fade_in => std.math.clamp(self.elapsed / self.fade_in_duration, 0.0, 1.0),
            .display => 1.0,
            .fade_out => {
                const fade_start = self.fade_in_duration + self.duration;
                const fade_progress = (self.elapsed - fade_start) / self.fade_out_duration;
                return std.math.clamp(1.0 - fade_progress, 0.0, 1.0);
            },
            .done => 0.0,
        };
    }

    /// Get message as slice
    pub fn getMessage(self: *const Notification) []const u8 {
        return self.message[0..self.message_len];
    }

    /// Get title as slice (empty if no title)
    pub fn getTitle(self: *const Notification) []const u8 {
        return self.title[0..self.title_len];
    }
};

/// Options for showing a notification
pub const NotificationOptions = struct {
    /// Override auto-dismiss duration (null = use type default)
    duration: ?f32 = null,
    /// Fade in duration in seconds
    fade_in: f32 = 0.2,
    /// Fade out duration in seconds
    fade_out: f32 = 0.3,
    /// Optional title text
    title: ?[]const u8 = null,
};

/// Display options for the notification manager
pub const NotificationDisplayOptions = struct {
    /// Screen position for notification stack
    position: NotificationPosition = .top_right,
    /// Width of each notification
    width: f32 = 350.0,
    /// Height of each notification (excluding title)
    base_height: f32 = 60.0,
    /// Additional height when title is present
    title_height: f32 = 24.0,
    /// Margin from screen edge
    margin: f32 = 20.0,
    /// Gap between stacked notifications
    spacing: f32 = 10.0,
    /// Show close button (X)
    show_close_button: bool = true,
    /// Allow click anywhere to dismiss
    click_to_dismiss: bool = true,
    /// Width of the colored type indicator bar
    type_bar_width: f32 = 6.0,
};

/// Notification manager state (caller-managed)
pub const NotificationManager = struct {
    /// Fixed array of notification slots
    notifications: [MAX_NOTIFICATIONS]Notification = [_]Notification{.{}} ** MAX_NOTIFICATIONS,

    /// Counter for generating unique IDs
    next_id: u64 = 1,

    /// Initialize a new notification manager
    pub fn init() NotificationManager {
        return .{};
    }

    /// Show a new notification
    pub fn show(
        self: *NotificationManager,
        message: []const u8,
        notification_type: NotificationType,
        options: NotificationOptions,
    ) void {
        // Find first inactive slot
        for (&self.notifications) |*notif| {
            if (!notif.active) {
                // Initialize notification
                notif.* = .{
                    .active = true,
                    .notification_type = notification_type,
                    .elapsed = 0.0,
                    .phase = .fade_in,
                    .fade_in_duration = options.fade_in,
                    .fade_out_duration = options.fade_out,
                    .duration = options.duration orelse notification_type.getDefaultDuration(),
                    .id = self.next_id,
                };
                self.next_id +%= 1;

                // Copy message
                const copy_len = @min(message.len, notif.message.len);
                @memcpy(notif.message[0..copy_len], message[0..copy_len]);
                notif.message_len = copy_len;

                // Copy title if provided
                if (options.title) |title_text| {
                    const title_len = @min(title_text.len, notif.title.len);
                    @memcpy(notif.title[0..title_len], title_text[0..title_len]);
                    notif.title_len = title_len;
                }

                return;
            }
        }
        // Queue is full - notification is dropped (could implement priority queue if needed)
    }

    /// Convenience method for info notification
    pub fn info(self: *NotificationManager, message: []const u8) void {
        self.show(message, .info, .{});
    }

    /// Convenience method for success notification
    pub fn success(self: *NotificationManager, message: []const u8) void {
        self.show(message, .success, .{});
    }

    /// Convenience method for warning notification
    pub fn warning(self: *NotificationManager, message: []const u8) void {
        self.show(message, .warning, .{});
    }

    /// Convenience method for error notification
    pub fn err(self: *NotificationManager, message: []const u8) void {
        self.show(message, .error_, .{});
    }

    /// Dismiss a specific notification by index
    pub fn dismiss(self: *NotificationManager, index: usize) void {
        if (index < MAX_NOTIFICATIONS and self.notifications[index].active) {
            const notif = &self.notifications[index];
            if (notif.phase != .fade_out and notif.phase != .done) {
                notif.phase = .fade_out;
                // Adjust elapsed to start fade-out from current position
                notif.elapsed = notif.fade_in_duration + notif.duration;
            }
        }
    }

    /// Dismiss all notifications
    pub fn dismissAll(self: *NotificationManager) void {
        for (&self.notifications, 0..) |*notif, i| {
            if (notif.active and notif.phase != .fade_out and notif.phase != .done) {
                self.dismiss(i);
            }
        }
    }

    /// Update all notifications (call once per frame with delta_time)
    pub fn update(self: *NotificationManager, delta_time: f32) void {
        for (&self.notifications) |*notif| {
            if (!notif.active) continue;

            notif.elapsed += delta_time;

            // Update phase based on elapsed time
            switch (notif.phase) {
                .fade_in => {
                    if (notif.elapsed >= notif.fade_in_duration) {
                        notif.phase = .display;
                    }
                },
                .display => {
                    // Check for auto-dismiss (duration > 0)
                    if (notif.duration > 0) {
                        const display_end = notif.fade_in_duration + notif.duration;
                        if (notif.elapsed >= display_end) {
                            notif.phase = .fade_out;
                        }
                    }
                },
                .fade_out => {
                    const total_time = notif.fade_in_duration + notif.duration + notif.fade_out_duration;
                    if (notif.elapsed >= total_time) {
                        notif.phase = .done;
                        notif.active = false;
                    }
                },
                .done => {
                    notif.active = false;
                },
            }
        }
    }

    /// Get count of active notifications
    pub fn activeCount(self: *const NotificationManager) usize {
        var count: usize = 0;
        for (self.notifications) |notif| {
            if (notif.active) count += 1;
        }
        return count;
    }
};

/// Render all active notifications
/// Call this after all other UI widgets for proper z-ordering
pub fn renderNotifications(
    ctx: *Context,
    manager: *NotificationManager,
    options: NotificationDisplayOptions,
) void {
    // Calculate positions and render each active notification
    var stack_index: usize = 0;

    for (&manager.notifications, 0..) |*notif, slot_index| {
        if (!notif.active) continue;

        // Calculate height for this notification
        const has_title = notif.title_len > 0;
        const height = options.base_height + if (has_title) options.title_height else 0;

        // Calculate position based on stack index
        const base_pos = options.position.getBasePosition(options.width, height, options.margin);
        const stack_offset = @as(f32, @floatFromInt(stack_index)) * (height + options.spacing);

        const y = if (options.position.stacksDownward())
            base_pos.y + stack_offset
        else
            base_pos.y - stack_offset;

        const rect = Rect.init(base_pos.x, y, options.width, height);

        // Render and check for dismissal
        if (renderNotification(ctx, notif, rect, options)) {
            manager.dismiss(slot_index);
        }

        stack_index += 1;
    }
}

/// Internal: Render a single notification
/// Returns true if the notification should be dismissed
fn renderNotification(
    ctx: *Context,
    notif: *const Notification,
    rect: Rect,
    options: NotificationDisplayOptions,
) bool {
    const opacity = notif.getOpacity();
    if (opacity <= 0.0) return false;

    const theme = &ctx.theme;
    var dismissed = false;

    // Calculate alpha from opacity
    const alpha = @as(u8, @intFromFloat(opacity * 255.0));

    // Background with opacity
    const bg_color = Color.init(
        theme.notification_bg.r,
        theme.notification_bg.g,
        theme.notification_bg.b,
        alpha,
    );
    ctx.renderer.drawRect(rect, bg_color);

    // Border with opacity
    const border_color = Color.init(
        theme.notification_border.r,
        theme.notification_border.g,
        theme.notification_border.b,
        alpha,
    );
    ctx.renderer.drawRectOutline(rect, border_color, 1.0);

    // Type indicator bar on left edge
    const type_color = notif.notification_type.getColor();
    const bar_color = Color.init(type_color.r, type_color.g, type_color.b, alpha);
    const bar_rect = Rect.init(rect.x, rect.y, options.type_bar_width, rect.height);
    ctx.renderer.drawRect(bar_rect, bar_color);

    // Content area (after type bar)
    const content_x = rect.x + options.type_bar_width + 8.0;
    const content_width = rect.width - options.type_bar_width - 16.0;
    var content_y = rect.y + 8.0;

    // Title (if present)
    const has_title = notif.title_len > 0;
    if (has_title) {
        const title_color = Color.init(
            theme.notification_title.r,
            theme.notification_title.g,
            theme.notification_title.b,
            alpha,
        );
        ctx.renderer.drawText(
            notif.getTitle(),
            Vec2.init(content_x, content_y),
            theme.font_size_normal,
            title_color,
        );
        content_y += options.title_height;
    }

    // Message text
    const text_color = Color.init(
        theme.notification_text.r,
        theme.notification_text.g,
        theme.notification_text.b,
        alpha,
    );
    ctx.renderer.drawText(
        notif.getMessage(),
        Vec2.init(content_x, content_y),
        theme.font_size_small,
        text_color,
    );

    // Close button (X) in top-right corner
    if (options.show_close_button) {
        const close_size: f32 = 20.0;
        const close_rect = Rect.init(
            rect.x + rect.width - close_size - 4.0,
            rect.y + 4.0,
            close_size,
            close_size,
        );

        if (renderCloseButton(ctx, notif.id, close_rect, alpha, theme)) {
            dismissed = true;
        }
    }

    // Click-to-dismiss anywhere on notification
    if (options.click_to_dismiss and !dismissed) {
        const notif_id = widgetId("notification") +% notif.id;
        if (ctx.registerWidget(notif_id, rect)) {
            dismissed = true;
        }
    }

    // Adjust content width if close button is shown
    _ = content_width;

    return dismissed;
}

/// Internal: Render close button and handle interaction
/// Returns true if clicked
fn renderCloseButton(
    ctx: *Context,
    notif_id: u64,
    rect: Rect,
    alpha: u8,
    theme: *const Theme,
) bool {
    const close_id = widgetId("notification_close") +% notif_id;
    const clicked = ctx.registerWidget(close_id, rect);
    const is_hot = ctx.isHot(close_id);

    // Choose color based on hover state
    const base_color = if (is_hot) theme.notification_close_hover else theme.notification_close;
    const color = Color.init(base_color.r, base_color.g, base_color.b, alpha);

    // Draw X shape using two lines
    const padding: f32 = 5.0;
    const x1 = rect.x + padding;
    const y1 = rect.y + padding;
    const x2 = rect.x + rect.width - padding;
    const y2 = rect.y + rect.height - padding;

    // Draw X as text (simpler than drawing lines)
    const center = rect.center();
    ctx.renderer.drawText("X", Vec2.init(center.x - 4.0, center.y - 6.0), 14.0, color);

    // Unused but kept for potential future line-based rendering
    _ = x1;
    _ = y1;
    _ = x2;
    _ = y2;

    return clicked;
}

// ============================================================================
// Tests
// ============================================================================

test "NotificationManager - init and show" {
    var manager = NotificationManager.init();

    manager.info("Test message");
    try std.testing.expectEqual(@as(usize, 1), manager.activeCount());

    // Check message was stored correctly
    const notif = &manager.notifications[0];
    try std.testing.expect(notif.active);
    try std.testing.expectEqualStrings("Test message", notif.getMessage());
    try std.testing.expectEqual(NotificationType.info, notif.notification_type);
}

test "NotificationManager - update phases" {
    var manager = NotificationManager.init();

    manager.show("Test", .info, .{
        .duration = 1.0,
        .fade_in = 0.2,
        .fade_out = 0.3,
    });

    // Initially in fade_in phase
    try std.testing.expectEqual(AnimationPhase.fade_in, manager.notifications[0].phase);

    // After fade_in duration, should be in display phase
    manager.update(0.25);
    try std.testing.expectEqual(AnimationPhase.display, manager.notifications[0].phase);

    // After display duration, should be in fade_out phase
    manager.update(1.0);
    try std.testing.expectEqual(AnimationPhase.fade_out, manager.notifications[0].phase);

    // After fade_out, should be done and inactive
    manager.update(0.35);
    try std.testing.expectEqual(AnimationPhase.done, manager.notifications[0].phase);
    try std.testing.expect(!manager.notifications[0].active);
}

test "NotificationManager - manual dismiss" {
    var manager = NotificationManager.init();

    manager.show("Test", .error_, .{}); // error has duration=0 (no auto-dismiss)
    try std.testing.expectEqual(AnimationPhase.fade_in, manager.notifications[0].phase);

    manager.update(0.3); // past fade_in
    try std.testing.expectEqual(AnimationPhase.display, manager.notifications[0].phase);

    manager.update(10.0); // wait a long time - should still be in display
    try std.testing.expectEqual(AnimationPhase.display, manager.notifications[0].phase);

    // Manual dismiss
    manager.dismiss(0);
    try std.testing.expectEqual(AnimationPhase.fade_out, manager.notifications[0].phase);
}

test "NotificationManager - queue full behavior" {
    var manager = NotificationManager.init();

    // Fill all slots
    for (0..MAX_NOTIFICATIONS) |i| {
        var buf: [32]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "Message {d}", .{i}) catch "msg";
        manager.info(msg);
    }

    try std.testing.expectEqual(MAX_NOTIFICATIONS, manager.activeCount());

    // Additional notification should be dropped silently
    manager.info("Overflow message");
    try std.testing.expectEqual(MAX_NOTIFICATIONS, manager.activeCount());
}

test "Notification - opacity calculation" {
    var notif = Notification{
        .active = true,
        .phase = .fade_in,
        .fade_in_duration = 0.2,
        .duration = 1.0,
        .fade_out_duration = 0.3,
        .elapsed = 0.0,
    };

    // Start of fade_in
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), notif.getOpacity(), 0.01);

    // Middle of fade_in
    notif.elapsed = 0.1;
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), notif.getOpacity(), 0.01);

    // End of fade_in / start of display
    notif.elapsed = 0.2;
    notif.phase = .display;
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), notif.getOpacity(), 0.01);

    // During fade_out
    notif.elapsed = 1.35; // 0.2 + 1.0 + 0.15 = 1.35 (halfway through fade_out)
    notif.phase = .fade_out;
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), notif.getOpacity(), 0.01);
}

test "NotificationType - default durations" {
    try std.testing.expectEqual(@as(f32, 3.0), NotificationType.info.getDefaultDuration());
    try std.testing.expectEqual(@as(f32, 3.0), NotificationType.success.getDefaultDuration());
    try std.testing.expectEqual(@as(f32, 5.0), NotificationType.warning.getDefaultDuration());
    try std.testing.expectEqual(@as(f32, 0.0), NotificationType.error_.getDefaultDuration());
}

test "NotificationPosition - base positions" {
    const width: f32 = 350.0;
    const height: f32 = 60.0;
    const margin: f32 = 20.0;

    // Top-right should be near top-right corner
    const top_right = NotificationPosition.top_right.getBasePosition(width, height, margin);
    try std.testing.expectApproxEqAbs(@as(f32, VIRTUAL_WIDTH - 350.0 - 20.0), top_right.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 20.0), top_right.y, 0.01);

    // Center should be centered
    const center_pos = NotificationPosition.center.getBasePosition(width, height, margin);
    try std.testing.expectApproxEqAbs(@as(f32, (VIRTUAL_WIDTH - 350.0) / 2.0), center_pos.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, (VIRTUAL_HEIGHT - 60.0) / 2.0), center_pos.y, 0.01);

    // Bottom-left should be near bottom-left corner
    const bottom_left = NotificationPosition.bottom_left.getBasePosition(width, height, margin);
    try std.testing.expectApproxEqAbs(@as(f32, 20.0), bottom_left.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, VIRTUAL_HEIGHT - 60.0 - 20.0), bottom_left.y, 0.01);
}

test "NotificationPosition - stacking direction" {
    // Top positions stack downward
    try std.testing.expect(NotificationPosition.top_left.stacksDownward());
    try std.testing.expect(NotificationPosition.top_center.stacksDownward());
    try std.testing.expect(NotificationPosition.top_right.stacksDownward());

    // Other positions stack upward
    try std.testing.expect(!NotificationPosition.center.stacksDownward());
    try std.testing.expect(!NotificationPosition.bottom_right.stacksDownward());
}

test "NotificationManager - convenience methods" {
    var manager = NotificationManager.init();

    manager.info("Info message");
    try std.testing.expectEqual(NotificationType.info, manager.notifications[0].notification_type);

    manager.success("Success message");
    try std.testing.expectEqual(NotificationType.success, manager.notifications[1].notification_type);

    manager.warning("Warning message");
    try std.testing.expectEqual(NotificationType.warning, manager.notifications[2].notification_type);

    manager.err("Error message");
    try std.testing.expectEqual(NotificationType.error_, manager.notifications[3].notification_type);

    try std.testing.expectEqual(@as(usize, 4), manager.activeCount());
}

test "NotificationManager - dismissAll" {
    var manager = NotificationManager.init();

    manager.info("Message 1");
    manager.success("Message 2");
    manager.warning("Message 3");

    manager.update(0.3); // Past fade_in

    // All should be in display phase
    try std.testing.expectEqual(AnimationPhase.display, manager.notifications[0].phase);
    try std.testing.expectEqual(AnimationPhase.display, manager.notifications[1].phase);
    try std.testing.expectEqual(AnimationPhase.display, manager.notifications[2].phase);

    manager.dismissAll();

    // All should now be in fade_out phase
    try std.testing.expectEqual(AnimationPhase.fade_out, manager.notifications[0].phase);
    try std.testing.expectEqual(AnimationPhase.fade_out, manager.notifications[1].phase);
    try std.testing.expectEqual(AnimationPhase.fade_out, manager.notifications[2].phase);
}

test "Notification - title storage" {
    var manager = NotificationManager.init();

    manager.show("Message body", .info, .{ .title = "Test Title" });

    const notif = &manager.notifications[0];
    try std.testing.expectEqualStrings("Test Title", notif.getTitle());
    try std.testing.expectEqualStrings("Message body", notif.getMessage());
}
