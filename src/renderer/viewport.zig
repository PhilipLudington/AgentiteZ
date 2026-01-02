const std = @import("std");

/// Scaling mode for virtual resolution rendering
pub const ScaleMode = enum {
    /// Fit - Maintain aspect ratio, letterbox/pillarbox as needed (default)
    /// Content is fully visible, black bars may appear
    fit,

    /// Fill - Maintain aspect ratio, crop to fill window
    /// Content fills the window but may be cropped
    fill,

    /// Stretch - Stretch to fill window, ignore aspect ratio
    /// Content fills window but may be distorted
    stretch,
};

/// Viewport information including position, size, and scaling factor
pub const ViewportInfo = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,
    scale: f32, // viewport_height / virtual_height

    pub fn format(self: ViewportInfo, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("ViewportInfo{{ x={}, y={}, w={}, h={}, scale={d:.3} }}", .{
            self.x,
            self.y,
            self.width,
            self.height,
            self.scale,
        });
    }
};

/// Virtual Resolution Manager
///
/// Provides a fixed coordinate space (default 1920x1080) that automatically
/// scales to any physical window size. This enables resolution-independent
/// rendering where game logic always uses the same coordinate system.
///
/// Features:
/// - Fixed virtual coordinate space
/// - Three scaling modes: fit (letterbox), fill (crop), stretch
/// - Mouse coordinate transformation (screen ↔ virtual)
/// - Automatic viewport calculation
///
/// Example:
/// ```zig
/// var vr = VirtualResolution.init(1920, 1080);
/// vr.setPhysicalSize(2560, 1440);
///
/// // Transform mouse input
/// const virtual_mouse = vr.screenToVirtual(mouse_x, mouse_y);
///
/// // Get viewport for bgfx
/// const viewport = vr.getViewport();
/// bgfx.setViewRect(0, viewport.x, viewport.y, viewport.width, viewport.height);
/// ```
pub const VirtualResolution = struct {
    /// Virtual resolution width (game coordinate space)
    virtual_width: u32,
    /// Virtual resolution height (game coordinate space)
    virtual_height: u32,
    /// Physical window width in pixels
    physical_width: u32,
    /// Physical window height in pixels
    physical_height: u32,
    /// Current scaling mode
    scale_mode: ScaleMode,

    // Cached viewport info (recalculated on size/mode change)
    cached_viewport: ViewportInfo,
    cache_valid: bool,

    /// Default virtual resolution (1920x1080)
    pub const DEFAULT_WIDTH: u32 = 1920;
    pub const DEFAULT_HEIGHT: u32 = 1080;

    /// Initialize with default 1920x1080 virtual resolution
    pub fn initDefault() VirtualResolution {
        return init(DEFAULT_WIDTH, DEFAULT_HEIGHT);
    }

    /// Initialize with custom virtual resolution
    pub fn init(virtual_width: u32, virtual_height: u32) VirtualResolution {
        return .{
            .virtual_width = virtual_width,
            .virtual_height = virtual_height,
            .physical_width = virtual_width, // Start with 1:1
            .physical_height = virtual_height,
            .scale_mode = .fit,
            .cached_viewport = undefined,
            .cache_valid = false,
        };
    }

    /// Update physical window size (call on window resize)
    pub fn setPhysicalSize(self: *VirtualResolution, width: u32, height: u32) void {
        if (self.physical_width != width or self.physical_height != height) {
            self.physical_width = width;
            self.physical_height = height;
            self.cache_valid = false;
        }
    }

    /// Change scaling mode
    pub fn setScaleMode(self: *VirtualResolution, mode: ScaleMode) void {
        if (self.scale_mode != mode) {
            self.scale_mode = mode;
            self.cache_valid = false;
        }
    }

    /// Get current viewport information
    pub fn getViewport(self: *VirtualResolution) ViewportInfo {
        if (!self.cache_valid) {
            self.recalculateViewport();
        }
        return self.cached_viewport;
    }

    /// Get the scale factor (viewport pixels per virtual pixel)
    pub fn getScale(self: *VirtualResolution) f32 {
        return self.getViewport().scale;
    }

    /// Transform screen coordinates to virtual coordinates
    ///
    /// Takes physical screen position (e.g., from mouse input) and returns
    /// the corresponding position in virtual coordinate space.
    ///
    /// Returns null if the position is outside the viewport (in letterbox area)
    /// for fit mode, or if coordinates are invalid.
    pub fn screenToVirtual(self: *VirtualResolution, screen_x: i32, screen_y: i32) ?struct { x: f32, y: f32 } {
        const viewport = self.getViewport();

        // Calculate position relative to viewport
        const rel_x = screen_x - @as(i32, viewport.x);
        const rel_y = screen_y - @as(i32, viewport.y);

        // For fit mode, check if outside viewport (in letterbox area)
        if (self.scale_mode == .fit) {
            if (rel_x < 0 or rel_x >= viewport.width or
                rel_y < 0 or rel_y >= viewport.height)
            {
                return null;
            }
        }

        // Convert to virtual coordinates
        const virtual_x = @as(f32, @floatFromInt(rel_x)) / viewport.scale;
        const virtual_y = @as(f32, @floatFromInt(rel_y)) / viewport.scale;

        return .{ .x = virtual_x, .y = virtual_y };
    }

    /// Transform screen coordinates to virtual, clamping to valid range
    ///
    /// Unlike screenToVirtual, this always returns a valid position by clamping
    /// coordinates to the virtual resolution bounds. Useful when you always want
    /// a valid position even if the mouse is in the letterbox area.
    pub fn screenToVirtualClamped(self: *VirtualResolution, screen_x: i32, screen_y: i32) struct { x: f32, y: f32 } {
        const viewport = self.getViewport();

        // Calculate position relative to viewport
        const rel_x = screen_x - @as(i32, viewport.x);
        const rel_y = screen_y - @as(i32, viewport.y);

        // Convert to virtual coordinates
        var virtual_x = @as(f32, @floatFromInt(rel_x)) / viewport.scale;
        var virtual_y = @as(f32, @floatFromInt(rel_y)) / viewport.scale;

        // Clamp to virtual resolution bounds
        virtual_x = std.math.clamp(virtual_x, 0, @as(f32, @floatFromInt(self.virtual_width)));
        virtual_y = std.math.clamp(virtual_y, 0, @as(f32, @floatFromInt(self.virtual_height)));

        return .{ .x = virtual_x, .y = virtual_y };
    }

    /// Transform virtual coordinates to screen coordinates
    ///
    /// Takes a position in virtual coordinate space and returns the
    /// corresponding physical screen position.
    pub fn virtualToScreen(self: *VirtualResolution, virtual_x: f32, virtual_y: f32) struct { x: i32, y: i32 } {
        const viewport = self.getViewport();

        // Scale and offset to screen coordinates
        const screen_x = @as(i32, @intFromFloat(virtual_x * viewport.scale)) + @as(i32, viewport.x);
        const screen_y = @as(i32, @intFromFloat(virtual_y * viewport.scale)) + @as(i32, viewport.y);

        return .{ .x = screen_x, .y = screen_y };
    }

    /// Check if a screen position is within the active viewport
    ///
    /// Returns false if the position is in the letterbox/pillarbox area
    pub fn isInsideViewport(self: *VirtualResolution, screen_x: i32, screen_y: i32) bool {
        const viewport = self.getViewport();

        const rel_x = screen_x - @as(i32, viewport.x);
        const rel_y = screen_y - @as(i32, viewport.y);

        return rel_x >= 0 and rel_x < viewport.width and
            rel_y >= 0 and rel_y < viewport.height;
    }

    /// Get the virtual resolution aspect ratio
    pub fn getVirtualAspectRatio(self: *const VirtualResolution) f32 {
        return @as(f32, @floatFromInt(self.virtual_width)) / @as(f32, @floatFromInt(self.virtual_height));
    }

    /// Get the physical window aspect ratio
    pub fn getPhysicalAspectRatio(self: *const VirtualResolution) f32 {
        return @as(f32, @floatFromInt(self.physical_width)) / @as(f32, @floatFromInt(self.physical_height));
    }

    // Internal: recalculate viewport based on current settings
    fn recalculateViewport(self: *VirtualResolution) void {
        self.cached_viewport = switch (self.scale_mode) {
            .fit => calculateFitViewport(
                self.physical_width,
                self.physical_height,
                self.virtual_width,
                self.virtual_height,
            ),
            .fill => calculateFillViewport(
                self.physical_width,
                self.physical_height,
                self.virtual_width,
                self.virtual_height,
            ),
            .stretch => calculateStretchViewport(
                self.physical_width,
                self.physical_height,
                self.virtual_width,
                self.virtual_height,
            ),
        };
        self.cache_valid = true;
    }
};

/// Calculate letterbox viewport to maintain aspect ratio (fit mode)
///
/// This function calculates the viewport dimensions and position to maintain
/// the target aspect ratio within the physical window, adding letterbox bars
/// (black bars) on the sides or top/bottom as needed.
///
/// Parameters:
///   - physical_width: Physical window width in pixels
///   - physical_height: Physical window height in pixels
///   - virtual_width: Target virtual/logical width
///   - virtual_height: Target virtual/logical height
///
/// Returns: ViewportInfo with viewport position, size, and scale factor
///
/// Example:
///   const viewport = calculateLetterboxViewport(2560, 1440, 1920, 1080);
///   // viewport.scale will be ~1.333 (1440 / 1080)
///   // viewport will have black bars on left/right
pub fn calculateLetterboxViewport(
    physical_width: u32,
    physical_height: u32,
    virtual_width: u32,
    virtual_height: u32,
) ViewportInfo {
    return calculateFitViewport(physical_width, physical_height, virtual_width, virtual_height);
}

/// Calculate fit viewport (letterbox/pillarbox to maintain aspect ratio)
/// Content is fully visible, black bars may appear on edges.
pub fn calculateFitViewport(
    physical_width: u32,
    physical_height: u32,
    virtual_width: u32,
    virtual_height: u32,
) ViewportInfo {
    // Calculate aspect ratios
    const target_aspect = @as(f32, @floatFromInt(virtual_width)) / @as(f32, @floatFromInt(virtual_height));
    const window_aspect = @as(f32, @floatFromInt(physical_width)) / @as(f32, @floatFromInt(physical_height));

    var viewport: ViewportInfo = undefined;

    if (window_aspect > target_aspect) {
        // Window is wider than target - add black bars on left/right (pillarbox)
        viewport.height = @intCast(physical_height);
        viewport.width = @intFromFloat(@as(f32, @floatFromInt(viewport.height)) * target_aspect);
        viewport.x = @intCast((physical_width - viewport.width) / 2);
        viewport.y = 0;
    } else {
        // Window is taller than target - add black bars on top/bottom (letterbox)
        viewport.width = @intCast(physical_width);
        viewport.height = @intFromFloat(@as(f32, @floatFromInt(viewport.width)) / target_aspect);
        viewport.x = 0;
        viewport.y = @intCast((physical_height - viewport.height) / 2);
    }

    // Calculate scale factor (viewport pixels / virtual pixels)
    viewport.scale = @as(f32, @floatFromInt(viewport.height)) / @as(f32, @floatFromInt(virtual_height));

    return viewport;
}

/// Calculate fill viewport (crop to fill, maintain aspect ratio)
/// Content fills the entire window but may be cropped on edges.
pub fn calculateFillViewport(
    physical_width: u32,
    physical_height: u32,
    virtual_width: u32,
    virtual_height: u32,
) ViewportInfo {
    const target_aspect = @as(f32, @floatFromInt(virtual_width)) / @as(f32, @floatFromInt(virtual_height));
    const window_aspect = @as(f32, @floatFromInt(physical_width)) / @as(f32, @floatFromInt(physical_height));

    var viewport: ViewportInfo = undefined;

    if (window_aspect > target_aspect) {
        // Window is wider - use full width, crop height (viewport extends beyond window)
        viewport.width = @intCast(physical_width);
        viewport.height = @intFromFloat(@as(f32, @floatFromInt(viewport.width)) / target_aspect);
        viewport.x = 0;
        // Center vertically (negative offset means content extends above window)
        const overflow = @as(i32, @intCast(viewport.height)) - @as(i32, @intCast(physical_height));
        viewport.y = @intCast(@max(0, -@divTrunc(overflow, 2)));
    } else {
        // Window is taller - use full height, crop width
        viewport.height = @intCast(physical_height);
        viewport.width = @intFromFloat(@as(f32, @floatFromInt(viewport.height)) * target_aspect);
        viewport.y = 0;
        const overflow = @as(i32, @intCast(viewport.width)) - @as(i32, @intCast(physical_width));
        viewport.x = @intCast(@max(0, -@divTrunc(overflow, 2)));
    }

    // Scale based on the larger dimension
    viewport.scale = @as(f32, @floatFromInt(viewport.height)) / @as(f32, @floatFromInt(virtual_height));

    return viewport;
}

/// Calculate stretch viewport (fill window, ignore aspect ratio)
/// Content fills entire window but may be distorted.
pub fn calculateStretchViewport(
    physical_width: u32,
    physical_height: u32,
    virtual_width: u32,
    virtual_height: u32,
) ViewportInfo {
    _ = virtual_width;
    return ViewportInfo{
        .x = 0,
        .y = 0,
        .width = @intCast(physical_width),
        .height = @intCast(physical_height),
        .scale = @as(f32, @floatFromInt(physical_height)) / @as(f32, @floatFromInt(virtual_height)),
    };
}

// ============================================================================
// Tests
// ============================================================================

test "calculateLetterboxViewport - ultra-wide display" {
    // Ultra-wide 21:9 display (2560x1080) with 16:9 target (1920x1080)
    const viewport = calculateLetterboxViewport(2560, 1080, 1920, 1080);

    try std.testing.expectEqual(@as(u16, 0), viewport.y); // No top/bottom bars
    try std.testing.expect(viewport.x > 0); // Has left/right bars
    try std.testing.expectEqual(@as(u16, 1080), viewport.height); // Full height
    try std.testing.expect(viewport.width < 2560); // Narrower than physical
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), viewport.scale, 0.01); // Scale ~1.0
}

test "calculateLetterboxViewport - tall display" {
    // Tall display (1080x2560) with 16:9 target (1920x1080)
    const viewport = calculateLetterboxViewport(1080, 2560, 1920, 1080);

    try std.testing.expectEqual(@as(u16, 0), viewport.x); // No left/right bars
    try std.testing.expect(viewport.y > 0); // Has top/bottom bars
    try std.testing.expectEqual(@as(u16, 1080), viewport.width); // Full width
    try std.testing.expect(viewport.height < 2560); // Shorter than physical
}

test "calculateLetterboxViewport - exact match" {
    // Exact 16:9 display (1920x1080) with 16:9 target (1920x1080)
    const viewport = calculateLetterboxViewport(1920, 1080, 1920, 1080);

    try std.testing.expectEqual(@as(u16, 0), viewport.x);
    try std.testing.expectEqual(@as(u16, 0), viewport.y);
    try std.testing.expectEqual(@as(u16, 1920), viewport.width);
    try std.testing.expectEqual(@as(u16, 1080), viewport.height);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), viewport.scale, 0.01);
}

test "calculateLetterboxViewport - HiDPI Retina" {
    // 2x Retina display (3840x2160) with 16:9 target (1920x1080)
    const viewport = calculateLetterboxViewport(3840, 2160, 1920, 1080);

    try std.testing.expectEqual(@as(u16, 0), viewport.x);
    try std.testing.expectEqual(@as(u16, 0), viewport.y);
    try std.testing.expectEqual(@as(u16, 3840), viewport.width);
    try std.testing.expectEqual(@as(u16, 2160), viewport.height);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), viewport.scale, 0.01); // Scale ~2.0
}

test "ScaleMode - fit vs fill vs stretch" {
    // Window wider than virtual (2560x1080 physical, 1920x1080 virtual)
    const fit = calculateFitViewport(2560, 1080, 1920, 1080);
    const fill = calculateFillViewport(2560, 1080, 1920, 1080);
    const stretch = calculateStretchViewport(2560, 1080, 1920, 1080);

    // Fit: pillarboxed (black bars on sides)
    try std.testing.expect(fit.x > 0);
    try std.testing.expectEqual(@as(u16, 1080), fit.height);

    // Fill: uses full width (may crop top/bottom)
    try std.testing.expectEqual(@as(u16, 0), fill.x);
    try std.testing.expectEqual(@as(u16, 2560), fill.width);

    // Stretch: fills entire window
    try std.testing.expectEqual(@as(u16, 0), stretch.x);
    try std.testing.expectEqual(@as(u16, 0), stretch.y);
    try std.testing.expectEqual(@as(u16, 2560), stretch.width);
    try std.testing.expectEqual(@as(u16, 1080), stretch.height);
}

test "VirtualResolution - basic initialization" {
    const vr = VirtualResolution.initDefault();
    try std.testing.expectEqual(@as(u32, 1920), vr.virtual_width);
    try std.testing.expectEqual(@as(u32, 1080), vr.virtual_height);
    try std.testing.expectEqual(ScaleMode.fit, vr.scale_mode);
}

test "VirtualResolution - screen to virtual transformation" {
    var vr = VirtualResolution.init(1920, 1080);
    vr.setPhysicalSize(1920, 1080);

    // 1:1 mapping at exact resolution
    const result = vr.screenToVirtual(960, 540);
    try std.testing.expect(result != null);
    try std.testing.expectApproxEqAbs(@as(f32, 960.0), result.?.x, 0.1);
    try std.testing.expectApproxEqAbs(@as(f32, 540.0), result.?.y, 0.1);
}

test "VirtualResolution - screen to virtual with letterbox" {
    var vr = VirtualResolution.init(1920, 1080);
    vr.setPhysicalSize(2560, 1080); // Ultra-wide, will have pillarbox

    const viewport = vr.getViewport();
    try std.testing.expect(viewport.x > 0); // Has pillarbox

    // Click in letterbox area (left bar) should return null
    const result_letterbox = vr.screenToVirtual(0, 540);
    try std.testing.expect(result_letterbox == null);

    // Click in active area should work
    const center_x: i32 = @intCast(@divFloor(2560, 2));
    const result_active = vr.screenToVirtual(center_x, 540);
    try std.testing.expect(result_active != null);
}

test "VirtualResolution - virtual to screen transformation" {
    var vr = VirtualResolution.init(1920, 1080);
    vr.setPhysicalSize(3840, 2160); // 2x scale

    // Center of virtual space
    const screen = vr.virtualToScreen(960.0, 540.0);

    // At 2x scale, virtual center (960, 540) should be at screen (1920, 1080)
    try std.testing.expectEqual(@as(i32, 1920), screen.x);
    try std.testing.expectEqual(@as(i32, 1080), screen.y);
}

test "VirtualResolution - round trip transformation" {
    var vr = VirtualResolution.init(1920, 1080);
    vr.setPhysicalSize(2560, 1440);

    const original_virtual_x: f32 = 500.0;
    const original_virtual_y: f32 = 300.0;

    // Virtual -> Screen -> Virtual
    const screen = vr.virtualToScreen(original_virtual_x, original_virtual_y);
    const back = vr.screenToVirtual(screen.x, screen.y);

    try std.testing.expect(back != null);
    try std.testing.expectApproxEqAbs(original_virtual_x, back.?.x, 1.0);
    try std.testing.expectApproxEqAbs(original_virtual_y, back.?.y, 1.0);
}

test "VirtualResolution - clamped transformation" {
    var vr = VirtualResolution.init(1920, 1080);
    vr.setPhysicalSize(1920, 1080);

    // Negative coordinates should clamp to 0
    const clamped = vr.screenToVirtualClamped(-100, -50);
    try std.testing.expectEqual(@as(f32, 0.0), clamped.x);
    try std.testing.expectEqual(@as(f32, 0.0), clamped.y);

    // Coordinates beyond viewport should clamp to max
    const clamped2 = vr.screenToVirtualClamped(3000, 2000);
    try std.testing.expectEqual(@as(f32, 1920.0), clamped2.x);
    try std.testing.expectEqual(@as(f32, 1080.0), clamped2.y);
}

test "VirtualResolution - isInsideViewport" {
    var vr = VirtualResolution.init(1920, 1080);
    vr.setPhysicalSize(2560, 1080); // Ultra-wide with pillarbox

    const viewport = vr.getViewport();

    // Inside viewport
    const center_x: i32 = @intCast(@divFloor(2560, 2));
    try std.testing.expect(vr.isInsideViewport(center_x, 540));

    // In left pillarbox
    try std.testing.expect(!vr.isInsideViewport(0, 540));

    // In right pillarbox
    try std.testing.expect(!vr.isInsideViewport(2559, 540));

    // Just inside left edge of viewport
    try std.testing.expect(vr.isInsideViewport(@as(i32, viewport.x), 540));
}

test "VirtualResolution - scale mode changes" {
    var vr = VirtualResolution.init(1920, 1080);
    vr.setPhysicalSize(2560, 1080);

    // Fit mode (default)
    const fit_viewport = vr.getViewport();
    try std.testing.expect(fit_viewport.x > 0);

    // Switch to stretch
    vr.setScaleMode(.stretch);
    const stretch_viewport = vr.getViewport();
    try std.testing.expectEqual(@as(u16, 0), stretch_viewport.x);
    try std.testing.expectEqual(@as(u16, 2560), stretch_viewport.width);
}

test "VirtualResolution - aspect ratio helpers" {
    const vr = VirtualResolution.init(1920, 1080);
    const aspect = vr.getVirtualAspectRatio();

    // 1920/1080 ≈ 1.777... (16:9)
    try std.testing.expectApproxEqAbs(@as(f32, 16.0 / 9.0), aspect, 0.001);
}
