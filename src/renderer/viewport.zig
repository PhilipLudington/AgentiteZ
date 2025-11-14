const std = @import("std");

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

/// Calculate letterbox viewport to maintain aspect ratio
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
    // Calculate aspect ratios
    const target_aspect = @as(f32, @floatFromInt(virtual_width)) / @as(f32, @floatFromInt(virtual_height));
    const window_aspect = @as(f32, @floatFromInt(physical_width)) / @as(f32, @floatFromInt(physical_height));

    var viewport: ViewportInfo = undefined;

    if (window_aspect > target_aspect) {
        // Window is wider than target - add black bars on left/right
        viewport.height = @intCast(physical_height);
        viewport.width = @intFromFloat(@as(f32, @floatFromInt(viewport.height)) * target_aspect);
        viewport.x = @intCast((physical_width - viewport.width) / 2);
        viewport.y = 0;
    } else {
        // Window is taller than target - add black bars on top/bottom
        viewport.width = @intCast(physical_width);
        viewport.height = @intFromFloat(@as(f32, @floatFromInt(viewport.width)) / target_aspect);
        viewport.x = 0;
        viewport.y = @intCast((physical_height - viewport.height) / 2);
    }

    // Calculate scale factor (viewport pixels / virtual pixels)
    viewport.scale = @as(f32, @floatFromInt(viewport.height)) / @as(f32, @floatFromInt(virtual_height));

    return viewport;
}

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
