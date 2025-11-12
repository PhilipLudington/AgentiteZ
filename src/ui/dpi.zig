const std = @import("std");
const types = @import("types.zig");

pub const Vec2 = types.Vec2;

// Virtual resolution constants - our game runs at logical 1920x1080
pub const VIRTUAL_WIDTH: f32 = 1920;
pub const VIRTUAL_HEIGHT: f32 = 1080;

/// WindowInfo provides window dimensions for RenderScale initialization
/// This abstraction allows us to work with different window backends (SDL, Raylib, etc.)
pub const WindowInfo = struct {
    width: i32,
    height: i32,
    dpi_scale: f32,
};

/// RenderScale - The heart of DPI magic (based on Grok's advice)
/// Handles DPI-aware virtual resolution rendering
pub const RenderScale = struct {
    /// Physical window dimensions
    window_width: i32,
    window_height: i32,

    /// Scale factor for rendering
    scale: f32,

    /// Offset for letterboxing (centering content)
    offset_x: f32,
    offset_y: f32,

    /// Aspect ratio preservation scale
    viewport_scale: f32,

    /// Actual viewport dimensions (after letterboxing)
    viewport_width: i32,
    viewport_height: i32,

    /// Initialize RenderScale with window information
    pub fn init(window_info: WindowInfo) RenderScale {
        // Note: DPI scale is provided for awareness, but we calculate
        // our scale based on window/virtual ratio for aspect ratio preservation
        _ = window_info.dpi_scale;

        // Get current window dimensions
        const current_width = window_info.width;
        const current_height = window_info.height;

        // Calculate scale to fit virtual resolution in window while preserving aspect ratio
        const scale_x = @as(f32, @floatFromInt(current_width)) / VIRTUAL_WIDTH;
        const scale_y = @as(f32, @floatFromInt(current_height)) / VIRTUAL_HEIGHT;
        const viewport_scale = @min(scale_x, scale_y);

        // Calculate actual viewport size (maintains aspect ratio)
        const viewport_width = @as(i32, @intFromFloat(VIRTUAL_WIDTH * viewport_scale));
        const viewport_height = @as(i32, @intFromFloat(VIRTUAL_HEIGHT * viewport_scale));

        // Calculate centering offset for letterboxing
        const offset_x = @as(f32, @floatFromInt(current_width - viewport_width)) / 2.0;
        const offset_y = @as(f32, @floatFromInt(current_height - viewport_height)) / 2.0;

        return .{
            .window_width = current_width,
            .window_height = current_height,
            .scale = viewport_scale,
            .offset_x = offset_x,
            .offset_y = offset_y,
            .viewport_scale = viewport_scale,
            .viewport_width = viewport_width,
            .viewport_height = viewport_height,
        };
    }

    /// Convert screen coordinates to virtual/logical coordinates
    pub fn screenToVirtual(self: RenderScale, x: f32, y: f32) Vec2 {
        return Vec2.init(
            (x - self.offset_x) / self.scale,
            (y - self.offset_y) / self.scale
        );
    }

    /// Convert virtual/logical coordinates to screen coordinates
    pub fn virtualToScreen(self: RenderScale, pos: Vec2) Vec2 {
        return Vec2.init(
            pos.x * self.scale + self.offset_x,
            pos.y * self.scale + self.offset_y
        );
    }

    /// Convert a virtual rect to screen coordinates (for rendering)
    pub fn toScreen(self: RenderScale, rect: types.Rect) types.Rect {
        return types.Rect{
            .x = rect.x * self.scale + self.offset_x,
            .y = rect.y * self.scale + self.offset_y,
            .width = rect.width * self.scale,
            .height = rect.height * self.scale,
        };
    }

    /// Alias for virtualToScreen for consistency
    pub fn toScreenVec2(self: RenderScale, pos: Vec2) Vec2 {
        return self.virtualToScreen(pos);
    }

    /// Begin virtual resolution rendering with scissor mode for viewport
    /// NOTE: This is now handled by the renderer (BgfxRenderer) directly
    /// Kept for API compatibility but does nothing
    pub fn beginVirtualRender(self: RenderScale) void {
        _ = self;
        // Scissor mode is now managed by BgfxRenderer.setScissor()
        // This function kept for backward compatibility
    }

    /// End virtual resolution rendering
    /// NOTE: This is now handled by the renderer (BgfxRenderer) directly
    /// Kept for API compatibility but does nothing
    pub fn endVirtualRender(self: RenderScale) void {
        _ = self;
        // Scissor mode is now managed by BgfxRenderer.setScissor()
        // This function kept for backward compatibility
    }

    /// Check if render scale needs updating (window resize, etc.)
    /// Call this with current window info to check if recalculation is needed
    pub fn needsUpdate(self: RenderScale, window_info: WindowInfo) bool {
        return (window_info.width != self.window_width or
                window_info.height != self.window_height);
    }

    /// Get debug information
    pub fn getDebugInfo(self: RenderScale, buffer: []u8) ![]u8 {
        return std.fmt.bufPrint(buffer,
            \\RenderScale Config:
            \\  Window: {}x{}
            \\  Viewport: {}x{}
            \\  Scale: {d:.2}x
            \\  Offset: ({d:.1}, {d:.1})
            \\  Virtual: {d:.0}x{d:.0}
        , .{
            self.window_width,
            self.window_height,
            self.viewport_width,
            self.viewport_height,
            self.scale,
            self.offset_x,
            self.offset_y,
            VIRTUAL_WIDTH,
            VIRTUAL_HEIGHT,
        });
    }
};

/// Get mouse position in virtual coordinates
/// NOTE: This function is deprecated - mouse position should be obtained
/// from InputState and converted using RenderScale.screenToVirtual()
pub fn getMouseVirtual(scale: RenderScale, mouse_x: f32, mouse_y: f32) Vec2 {
    return scale.screenToVirtual(mouse_x, mouse_y);
}

/// Legacy DpiConfig for backward compatibility - wraps RenderScale
pub const DpiConfig = struct {
    render_scale: RenderScale,

    // Compatibility fields
    scale_factor: f32,
    logical_width: f32,
    logical_height: f32,
    physical_width: f32,
    physical_height: f32,
    high_dpi_enabled: bool,
    monitor_index: i32,
    auto_scale_mouse: bool,

    /// Initialize DPI configuration using new RenderScale
    pub fn init(window_info: WindowInfo) DpiConfig {
        const render_scale = RenderScale.init(window_info);
        const actual_dpi_scale = if (window_info.dpi_scale > 0) window_info.dpi_scale else 1.0;

        return .{
            .render_scale = render_scale,
            .scale_factor = render_scale.scale,
            .logical_width = VIRTUAL_WIDTH,
            .logical_height = VIRTUAL_HEIGHT,
            .physical_width = @floatFromInt(render_scale.window_width),
            .physical_height = @floatFromInt(render_scale.window_height),
            .high_dpi_enabled = actual_dpi_scale > 1.1,
            .monitor_index = 0, // Not needed for SDL3 - kept for compatibility
            .auto_scale_mouse = false, // RenderScale handles this automatically
        };
    }

    /// Initialize mock DPI configuration for testing (no Raylib dependency)
    pub fn initMock() DpiConfig {
        const render_scale = RenderScale{
            .window_width = 1920,
            .window_height = 1080,
            .scale = 1.0,
            .offset_x = 0,
            .offset_y = 0,
            .viewport_scale = 1.0,
            .viewport_width = 1920,
            .viewport_height = 1080,
        };

        return .{
            .render_scale = render_scale,
            .scale_factor = 1.0,
            .logical_width = VIRTUAL_WIDTH,
            .logical_height = VIRTUAL_HEIGHT,
            .physical_width = 1920,
            .physical_height = 1080,
            .high_dpi_enabled = false,
            .monitor_index = 0,
            .auto_scale_mouse = false,
        };
    }

    /// Convert physical coordinates to logical coordinates
    pub fn toLogical(self: DpiConfig, physical: Vec2) Vec2 {
        return self.render_scale.screenToVirtual(physical.x, physical.y);
    }

    /// Convert logical coordinates to physical coordinates
    pub fn toPhysical(self: DpiConfig, logical: Vec2) Vec2 {
        return self.render_scale.virtualToScreen(logical);
    }

    /// Scale a logical dimension to physical pixels
    pub fn scaleToPhysical(self: DpiConfig, logical_size: f32) f32 {
        return logical_size * self.render_scale.scale;
    }

    /// Scale a physical dimension to logical units
    pub fn scaleToLogical(self: DpiConfig, physical_size: f32) f32 {
        return physical_size / self.render_scale.scale;
    }

    /// Check if configuration needs updating
    pub fn needsUpdate(self: DpiConfig, window_info: WindowInfo) bool {
        return self.render_scale.needsUpdate(window_info);
    }

    /// Update configuration if needed
    pub fn updateIfNeeded(self: *DpiConfig, window_info: WindowInfo) bool {
        // Skip update for mock configs (used in tests)
        if (self.monitor_index == 0 and self.physical_width == 1920 and self.physical_height == 1080) {
            return false; // This is a mock config, don't update
        }

        if (self.needsUpdate(window_info)) {
            self.* = DpiConfig.init(window_info);
            return true;
        }
        return false;
    }

    /// Get debug information
    pub fn getDebugInfo(self: DpiConfig, buffer: []u8) ![]u8 {
        return self.render_scale.getDebugInfo(buffer);
    }
};

/// Runtime DPI detection test
pub const DpiDetector = struct {
    test_complete: bool = false,
    mouse_needs_scaling: bool = false,

    /// Run a quick test to detect mouse coordinate behavior
    pub fn detectMouseBehavior() bool {
        // With RenderScale, this is handled automatically
        return false;
    }
};

// Tests
test "RenderScale coordinate conversion" {
    const scale = RenderScale{
        .window_width = 3840,
        .window_height = 2160,
        .scale = 2.0,
        .offset_x = 0,
        .offset_y = 0,
        .viewport_scale = 2.0,
        .viewport_width = 3840,
        .viewport_height = 2160,
    };

    // Test screen to virtual conversion
    const screen_pos = Vec2.init(400, 300);
    const virtual_pos = scale.screenToVirtual(screen_pos.x, screen_pos.y);

    try std.testing.expectApproxEqAbs(@as(f32, 200), virtual_pos.x, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 150), virtual_pos.y, 0.01);

    // Test reverse conversion
    const back_to_screen = scale.virtualToScreen(virtual_pos);
    try std.testing.expectApproxEqAbs(screen_pos.x, back_to_screen.x, 0.01);
    try std.testing.expectApproxEqAbs(screen_pos.y, back_to_screen.y, 0.01);
}

test "RenderScale with letterboxing" {
    // 2560x1440 window with 1920x1080 virtual resolution (letterboxed horizontally)
    // scale = min(2560/1920, 1440/1080) = min(1.333, 1.333) = 1.333
    // viewport = 1920*1.333 x 1080*1.333 = 2560x1440 (fills entire window, no letterboxing needed)
    // Actually, let's use a case where letterboxing IS needed:
    // Window: 2560x1200 (wider aspect ratio than 16:9)
    // scale = min(2560/1920, 1200/1080) = min(1.333, 1.111) = 1.111
    // viewport = 1920*1.111 x 1080*1.111 = 2133x1200
    // offset_x = (2560 - 2133) / 2 = 213.5
    const scale = RenderScale{
        .window_width = 2560,
        .window_height = 1200,
        .scale = 1.111,
        .offset_x = 213.5, // Centered horizontally
        .offset_y = 0,
        .viewport_scale = 1.111,
        .viewport_width = 2133,
        .viewport_height = 1200,
    };

    // Test that mouse in letterbox area maps to negative virtual coords
    const letterbox_pos = scale.screenToVirtual(100, 100);
    try std.testing.expect(letterbox_pos.x < 0);

    // Test that centered content maps correctly
    const center_screen = Vec2.init(1280, 600);
    const center_virtual = scale.screenToVirtual(center_screen.x, center_screen.y);
    // center_virtual.x = (1280 - 213.5) / 1.111 = 1066.5 / 1.111 = 960
    // center_virtual.y = (600 - 0) / 1.111 = 540
    try std.testing.expectApproxEqAbs(@as(f32, 960), center_virtual.x, 1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 540), center_virtual.y, 1.0);
}