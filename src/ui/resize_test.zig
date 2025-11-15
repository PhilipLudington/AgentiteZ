// resize_test.zig
// Integration tests for window resize and DPI handling

const std = @import("std");
const ui = @import("../ui.zig");

test "RenderScale: Standard 16:9 to ultra-wide 21:9" {
    // Resize from standard to ultra-wide display
    const initial_info = ui.WindowInfo{
        .width = 1920,
        .height = 1080,
        .dpi_scale = 1.0,
    };
    const initial_scale = ui.RenderScale.init(initial_info);

    // Initial state - no letterboxing needed
    try std.testing.expectEqual(@as(f32, 1.0), initial_scale.scale);
    try std.testing.expectEqual(@as(u32, 1920), initial_scale.viewport_width);
    try std.testing.expectEqual(@as(u32, 1080), initial_scale.viewport_height);
    try std.testing.expectEqual(@as(f32, 0.0), initial_scale.offset_x);
    try std.testing.expectEqual(@as(f32, 0.0), initial_scale.offset_y);

    // Resize to ultra-wide 21:9
    const wide_info = ui.WindowInfo{
        .width = 2560,
        .height = 1080,
        .dpi_scale = 1.0,
    };
    const wide_scale = ui.RenderScale.init(wide_info);

    // Should have horizontal letterboxing (black bars on sides)
    try std.testing.expectEqual(@as(f32, 1.0), wide_scale.scale);
    try std.testing.expectEqual(@as(u32, 1920), wide_scale.viewport_width);
    try std.testing.expectEqual(@as(u32, 1080), wide_scale.viewport_height);
    try std.testing.expect(wide_scale.offset_x > 0); // Has horizontal offset
    try std.testing.expectEqual(@as(f32, 0.0), wide_scale.offset_y);
}

test "RenderScale: Landscape to portrait orientation" {
    // Resize from landscape to portrait
    const landscape_info = ui.WindowInfo{
        .width = 1920,
        .height = 1080,
        .dpi_scale = 1.0,
    };
    _ = ui.RenderScale.init(landscape_info);

    // Rotate to portrait (swap width/height)
    const portrait_info = ui.WindowInfo{
        .width = 1080,
        .height = 1920,
        .dpi_scale = 1.0,
    };
    const portrait_scale = ui.RenderScale.init(portrait_info);

    // Should have vertical letterboxing (black bars on top/bottom)
    try std.testing.expect(portrait_scale.offset_x == 0 or portrait_scale.offset_x < 1.0); // Minimal or no horizontal offset
    try std.testing.expect(portrait_scale.offset_y > 0); // Has vertical offset
    try std.testing.expectEqual(@as(u32, 1080), portrait_scale.viewport_width); // Full width used
    try std.testing.expect(portrait_scale.viewport_height < 1920); // Height reduced for aspect ratio
}

test "RenderScale: Small window downscaling" {
    // Resize to very small window
    const small_info = ui.WindowInfo{
        .width = 640,
        .height = 480,
        .dpi_scale = 1.0,
    };
    const small_scale = ui.RenderScale.init(small_info);

    // Should scale down while maintaining aspect ratio
    try std.testing.expect(small_scale.scale < 0.5); // Significant downscaling
    try std.testing.expect(small_scale.viewport_width <= 640);
    try std.testing.expect(small_scale.viewport_height <= 480);
}

test "RenderScale: 4K upscaling" {
    // Resize to 4K display
    const uhd_info = ui.WindowInfo{
        .width = 3840,
        .height = 2160,
        .dpi_scale = 1.0,
    };
    const uhd_scale = ui.RenderScale.init(uhd_info);

    // Should scale up 2x while maintaining aspect ratio
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), uhd_scale.scale, 0.01);
    try std.testing.expectEqual(@as(u32, 3840), uhd_scale.viewport_width);
    try std.testing.expectEqual(@as(u32, 2160), uhd_scale.viewport_height);
    try std.testing.expectEqual(@as(f32, 0.0), uhd_scale.offset_x);
    try std.testing.expectEqual(@as(f32, 0.0), uhd_scale.offset_y);
}

test "RenderScale: DPI change during resize (1x to 2x)" {
    // Standard resolution at 1x DPI
    const standard_info = ui.WindowInfo{
        .width = 1920,
        .height = 1080,
        .dpi_scale = 1.0,
    };
    const standard_scale = ui.RenderScale.init(standard_info);

    try std.testing.expectEqual(@as(f32, 1.0), standard_scale.scale);

    // Same physical size but 2x DPI (Retina display)
    const retina_info = ui.WindowInfo{
        .width = 1920,
        .height = 1080,
        .dpi_scale = 2.0,
    };
    const retina_scale = ui.RenderScale.init(retina_info);

    // Scale should account for DPI
    try std.testing.expectEqual(@as(f32, 1.0), retina_scale.scale); // Still 1:1 virtual mapping
    try std.testing.expectEqual(@as(u32, 1920), retina_scale.viewport_width);
    try std.testing.expectEqual(@as(u32, 1080), retina_scale.viewport_height);
}

test "Coordinate conversion after resize" {
    // Test virtual <-> physical coordinate conversion after resize
    const initial_info = ui.WindowInfo{
        .width = 1920,
        .height = 1080,
        .dpi_scale = 1.0,
    };
    const initial_scale = ui.RenderScale.init(initial_info);

    // Center of screen in virtual coordinates
    const virtual_center = ui.Vec2{ .x = 960, .y = 540 };
    const physical_center = initial_scale.virtualToScreen(virtual_center);

    // Should map to center of physical screen
    try std.testing.expectApproxEqAbs(@as(f32, 960.0), physical_center.x, 1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 540.0), physical_center.y, 1.0);

    // Convert back
    const virtual_again = initial_scale.screenToVirtual(physical_center);
    try std.testing.expectApproxEqAbs(virtual_center.x, virtual_again.x, 1.0);
    try std.testing.expectApproxEqAbs(virtual_center.y, virtual_again.y, 1.0);

    // Now resize to 4K
    const uhd_info = ui.WindowInfo{
        .width = 3840,
        .height = 2160,
        .dpi_scale = 1.0,
    };
    const uhd_scale = ui.RenderScale.init(uhd_info);

    // Same virtual center should map to physical center of 4K screen
    const physical_4k = uhd_scale.virtualToScreen(virtual_center);
    try std.testing.expectApproxEqAbs(@as(f32, 1920.0), physical_4k.x, 1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 1080.0), physical_4k.y, 1.0);
}

test "DpiConfig.updateIfNeeded detects changes" {
    const initial_info = ui.WindowInfo{
        .width = 1920,
        .height = 1080,
        .dpi_scale = 1.0,
    };
    var config = ui.DpiConfig.init(initial_info);

    // No change - should return false
    const no_change = config.updateIfNeeded(initial_info);
    try std.testing.expect(!no_change);

    // Window resized - should return true
    const resized_info = ui.WindowInfo{
        .width = 2560,
        .height = 1440,
        .dpi_scale = 1.0,
    };
    const window_changed = config.updateIfNeeded(resized_info);
    try std.testing.expect(window_changed);

    // DPI changed - should return true
    const dpi_changed_info = ui.WindowInfo{
        .width = 2560,
        .height = 1440,
        .dpi_scale = 2.0,
    };
    const dpi_changed = config.updateIfNeeded(dpi_changed_info);
    try std.testing.expect(dpi_changed);

    // No change again - should return false
    const no_change2 = config.updateIfNeeded(dpi_changed_info);
    try std.testing.expect(!no_change2);
}
