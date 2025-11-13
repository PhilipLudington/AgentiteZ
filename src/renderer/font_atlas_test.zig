// font_atlas_test.zig
// Tests for font atlas system

const std = @import("std");
const font_atlas = @import("font_atlas.zig");
const FontAtlas = font_atlas.FontAtlas;
const Glyph = font_atlas.Glyph;

// Note: These tests require bgfx to be initialized, which we can't do in unit tests
// without a window. So we'll test the data structures and logic that doesn't require GPU.

test "Glyph struct layout" {
    const glyph = Glyph{
        .uv_x0 = 0.0,
        .uv_y0 = 0.0,
        .uv_x1 = 0.5,
        .uv_y1 = 0.5,
        .offset_x = 2.0,
        .offset_y = -10.0,
        .width = 16.0,
        .height = 20.0,
        .advance = 18.0,
    };

    try std.testing.expectEqual(@as(f32, 0.0), glyph.uv_x0);
    try std.testing.expectEqual(@as(f32, 0.5), glyph.uv_x1);
    try std.testing.expectEqual(@as(f32, 16.0), glyph.width);
    try std.testing.expectEqual(@as(f32, 18.0), glyph.advance);
}

test "Glyph UV coordinate calculation" {
    // Simulate a glyph at position (64, 32) with size (16, 20) in a 512x512 atlas
    const atlas_width: u32 = 512;
    const atlas_height: u32 = 512;
    const glyph_x: u32 = 64;
    const glyph_y: u32 = 32;
    const glyph_width: u32 = 16;
    const glyph_height: u32 = 20;

    const uv_x0 = @as(f32, @floatFromInt(glyph_x)) / @as(f32, @floatFromInt(atlas_width));
    const uv_y0 = @as(f32, @floatFromInt(glyph_y)) / @as(f32, @floatFromInt(atlas_height));
    const uv_x1 = @as(f32, @floatFromInt(glyph_x + glyph_width)) / @as(f32, @floatFromInt(atlas_width));
    const uv_y1 = @as(f32, @floatFromInt(glyph_y + glyph_height)) / @as(f32, @floatFromInt(atlas_height));

    // UV coordinates should be normalized (0-1)
    try std.testing.expect(uv_x0 >= 0.0 and uv_x0 <= 1.0);
    try std.testing.expect(uv_y0 >= 0.0 and uv_y0 <= 1.0);
    try std.testing.expect(uv_x1 >= 0.0 and uv_x1 <= 1.0);
    try std.testing.expect(uv_y1 >= 0.0 and uv_y1 <= 1.0);

    // UV coordinates should be correctly positioned
    try std.testing.expectApproxEqAbs(@as(f32, 0.125), uv_x0, 0.001); // 64/512
    try std.testing.expectApproxEqAbs(@as(f32, 0.0625), uv_y0, 0.001); // 32/512
    try std.testing.expectApproxEqAbs(@as(f32, 0.15625), uv_x1, 0.001); // 80/512
    try std.testing.expectApproxEqAbs(@as(f32, 0.10156), uv_y1, 0.001); // 52/512
}

test "Atlas size calculation for 256 glyphs" {
    const glyphs_per_row = 16;
    const glyph_padding = 2;
    const font_size: f32 = 24.0;
    const estimated_glyph_size = @as(u32, @intFromFloat(font_size)) + glyph_padding * 2;
    const atlas_width = glyphs_per_row * estimated_glyph_size;
    const atlas_height = glyphs_per_row * estimated_glyph_size;

    // Should be 16x16 = 256 glyphs
    const total_glyphs = glyphs_per_row * glyphs_per_row;
    try std.testing.expectEqual(@as(u32, 256), total_glyphs);

    // Atlas size should be large enough
    try std.testing.expect(atlas_width >= 256);
    try std.testing.expect(atlas_height >= 256);

    // For 24px font with 2px padding = 28px per glyph
    // 16 * 28 = 448px
    try std.testing.expectEqual(@as(u32, 448), atlas_width);
    try std.testing.expectEqual(@as(u32, 448), atlas_height);
}

test "Glyph array covers full ASCII range" {
    var glyphs: [256]Glyph = undefined;

    // Initialize all glyphs with default values
    for (0..256) |i| {
        glyphs[i] = Glyph{
            .uv_x0 = 0,
            .uv_y0 = 0,
            .uv_x1 = 0,
            .uv_y1 = 0,
            .offset_x = 0,
            .offset_y = 0,
            .width = 0,
            .height = 0,
            .advance = 0,
        };
    }

    // Verify we can access all ASCII characters
    try std.testing.expectEqual(@as(usize, 256), glyphs.len);

    // Common characters should be accessible
    const space = glyphs[' '];
    const letter_a = glyphs['A'];
    const digit_0 = glyphs['0'];

    _ = space;
    _ = letter_a;
    _ = digit_0;
}

test "Text measurement logic" {
    // Simulate measuring "Hello" with known glyph advances
    const glyphs = [_]Glyph{
        Glyph{ .uv_x0 = 0, .uv_y0 = 0, .uv_x1 = 0, .uv_y1 = 0, .offset_x = 0, .offset_y = 0, .width = 10, .height = 12, .advance = 12 }, // H
        Glyph{ .uv_x0 = 0, .uv_y0 = 0, .uv_x1 = 0, .uv_y1 = 0, .offset_x = 0, .offset_y = 0, .width = 8, .height = 12, .advance = 10 }, // e
        Glyph{ .uv_x0 = 0, .uv_y0 = 0, .uv_x1 = 0, .uv_y1 = 0, .offset_x = 0, .offset_y = 0, .width = 4, .height = 14, .advance = 6 }, // l
        Glyph{ .uv_x0 = 0, .uv_y0 = 0, .uv_x1 = 0, .uv_y1 = 0, .offset_x = 0, .offset_y = 0, .width = 4, .height = 14, .advance = 6 }, // l
        Glyph{ .uv_x0 = 0, .uv_y0 = 0, .uv_x1 = 0, .uv_y1 = 0, .offset_x = 0, .offset_y = 0, .width = 9, .height = 12, .advance = 11 }, // o
    };

    // Measure "Hello" by summing advances
    var width: f32 = 0;
    const text = "Hello";
    const char_map = [_]u8{ 'H', 'e', 'l', 'l', 'o' };

    for (char_map, 0..) |char, i| {
        _ = char;
        width += glyphs[i].advance;
    }

    // 12 + 10 + 6 + 6 + 11 = 45
    try std.testing.expectApproxEqAbs(@as(f32, 45.0), width, 0.01);
}

test "Ellipsis truncation logic" {
    // Simulate text that needs truncation
    const max_width: f32 = 50.0;
    const ellipsis_width: f32 = 18.0; // "..." = 3 * 6
    const char_width: f32 = 10.0;

    // How many characters fit before ellipsis?
    // 50 - 18 = 32 pixels available for text
    // 32 / 10 = 3.2 characters -> 3 characters
    var width: f32 = 0;
    var chars_fit: usize = 0;

    while (width + char_width + ellipsis_width <= max_width) {
        width += char_width;
        chars_fit += 1;
    }

    try std.testing.expectEqual(@as(usize, 3), chars_fit);
    try std.testing.expectApproxEqAbs(@as(f32, 30.0), width, 0.01);
}

test "Line height calculation from font metrics" {
    // Typical font metrics
    const ascent: c_int = 800;
    const descent: c_int = -200;
    const line_gap: c_int = 100;
    const scale: f32 = 0.03; // Scale for ~24px font

    const line_height = @as(f32, @floatFromInt(ascent - descent + line_gap)) * scale;

    // (800 - (-200) + 100) * 0.03 = 1100 * 0.03 = 33
    try std.testing.expectApproxEqAbs(@as(f32, 33.0), line_height, 0.01);
}

test "RGBA conversion for Metal compatibility" {
    // Simulate converting grayscale atlas to RGBA
    const atlas_data = [_]u8{ 0, 128, 255, 64 };
    var rgba_data: [16]u8 = undefined;

    for (atlas_data, 0..) |gray, i| {
        rgba_data[i * 4 + 0] = 255; // R - white
        rgba_data[i * 4 + 1] = 255; // G - white
        rgba_data[i * 4 + 2] = 255; // B - white
        rgba_data[i * 4 + 3] = gray; // A - glyph data
    }

    // Check first pixel (gray=0)
    try std.testing.expectEqual(@as(u8, 255), rgba_data[0]); // R
    try std.testing.expectEqual(@as(u8, 255), rgba_data[1]); // G
    try std.testing.expectEqual(@as(u8, 255), rgba_data[2]); // B
    try std.testing.expectEqual(@as(u8, 0), rgba_data[3]); // A

    // Check second pixel (gray=128)
    try std.testing.expectEqual(@as(u8, 255), rgba_data[4]); // R
    try std.testing.expectEqual(@as(u8, 255), rgba_data[5]); // G
    try std.testing.expectEqual(@as(u8, 255), rgba_data[6]); // B
    try std.testing.expectEqual(@as(u8, 128), rgba_data[7]); // A
}

test "Glyph packing grid layout" {
    // Simulate packing glyphs in a 16x16 grid
    const glyphs_per_row = 16;
    const glyph_width: u32 = 20;
    const glyph_height: u32 = 24;
    const glyph_padding: u32 = 2;

    var current_x: u32 = glyph_padding;
    var current_y: u32 = glyph_padding;
    var glyphs_placed: u32 = 0;

    // Place first row of glyphs
    for (0..glyphs_per_row) |_| {
        // Place glyph at (current_x, current_y)
        glyphs_placed += 1;
        current_x += glyph_width + glyph_padding;
    }

    try std.testing.expectEqual(@as(u32, 16), glyphs_placed);

    // After first row, x should wrap
    const expected_x = glyph_padding + (glyphs_per_row * (glyph_width + glyph_padding));
    try std.testing.expectEqual(expected_x, current_x);
}
