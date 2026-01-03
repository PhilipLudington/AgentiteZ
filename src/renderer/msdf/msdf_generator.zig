//! MSDF Generator
//!
//! Core MSDF (Multi-channel Signed Distance Field) generation algorithm.
//! Generates a 3-channel (RGB) distance field where the median of the
//! three channels reconstructs the true signed distance, while preserving
//! sharp corners.

const std = @import("std");
const math = @import("math_utils.zig");
const edge_mod = @import("edge.zig");
const contour_mod = @import("contour.zig");
const edge_coloring = @import("edge_coloring.zig");
const Vec2 = math.Vec2;
const SignedDistance = math.SignedDistance;
const EdgeSegment = edge_mod.EdgeSegment;
const EdgeColor = edge_mod.EdgeColor;
const Contour = contour_mod.Contour;
const Shape = contour_mod.Shape;

/// Configuration for MSDF generation
pub const MsdfConfig = struct {
    /// Width of output bitmap in pixels
    width: u32 = 48,
    /// Height of output bitmap in pixels
    height: u32 = 48,
    /// Distance field range in shape units (maps to 0.5 in normalized space)
    /// Typical values: 2.0 - 8.0
    range: f64 = 4.0,
    /// Angle threshold for corner detection (radians)
    /// Default is ~172 degrees (almost straight = not a corner)
    angle_threshold: f64 = edge_coloring.DEFAULT_ANGLE_THRESHOLD,
    /// Translation to apply to shape coordinates
    translate: Vec2 = Vec2.zero,
    /// Scale to apply to shape coordinates
    scale: Vec2 = Vec2{ .x = 1.0, .y = 1.0 },
};

/// Result of MSDF generation
pub const MsdfResult = struct {
    /// RGB8 bitmap data (3 bytes per pixel)
    bitmap: []u8,
    /// Bitmap width
    width: u32,
    /// Bitmap height
    height: u32,
    /// Allocator used for bitmap
    allocator: std.mem.Allocator,

    pub fn deinit(self: *MsdfResult) void {
        self.allocator.free(self.bitmap);
    }

    /// Get pixel at (x, y) as RGB tuple
    pub fn getPixel(self: MsdfResult, x: u32, y: u32) struct { r: u8, g: u8, b: u8 } {
        const idx = (y * self.width + x) * 3;
        return .{
            .r = self.bitmap[idx],
            .g = self.bitmap[idx + 1],
            .b = self.bitmap[idx + 2],
        };
    }
};

/// Per-channel distance tracking
const ChannelDistances = struct {
    r: SignedDistance = SignedDistance.infinite,
    g: SignedDistance = SignedDistance.infinite,
    b: SignedDistance = SignedDistance.infinite,
};

/// Calculate point-in-polygon using winding number
fn calculateWinding(point: Vec2, shape: *const Shape) i32 {
    var total: i32 = 0;

    for (shape.contours.items) |contour| {
        if (contour.edges.items.len == 0) continue;

        // Use crossing number algorithm
        var crossings: i32 = 0;

        for (contour.edges.items) |edge| {
            // Sample the edge at several points
            const samples = 8;
            var prev_y: f64 = edge.point(0).y;
            var prev_x: f64 = edge.point(0).x;

            for (1..samples + 1) |i| {
                const t = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(samples));
                const p = edge.point(t);

                // Check for crossing
                if ((prev_y <= point.y and p.y > point.y) or
                    (prev_y > point.y and p.y <= point.y))
                {
                    // Calculate x intersection
                    const t_intersect = (point.y - prev_y) / (p.y - prev_y);
                    const x_intersect = prev_x + t_intersect * (p.x - prev_x);

                    if (point.x < x_intersect) {
                        if (p.y > prev_y) {
                            crossings += 1;
                        } else {
                            crossings -= 1;
                        }
                    }
                }

                prev_y = p.y;
                prev_x = p.x;
            }
        }

        total += crossings;
    }

    return total;
}

/// Convert signed distance to pixel value (0-255)
fn distanceToPixel(distance: f64, range: f64) u8 {
    // Map distance from [-range, +range] to [0, 255]
    // distance = 0 (on edge) maps to 127.5
    // distance = -range (inside) maps to 255
    // distance = +range (outside) maps to 0
    const normalized = 0.5 - distance / (2.0 * range);
    const clamped = math.clamp(normalized, 0.0, 1.0);
    return @intFromFloat(clamped * 255.0);
}

/// Generate MSDF bitmap for a shape
pub fn generateMsdf(
    allocator: std.mem.Allocator,
    shape: *Shape,
    config: MsdfConfig,
) !MsdfResult {
    // Color edges if not already colored
    edge_coloring.colorEdges(shape, config.angle_threshold);

    // Allocate output bitmap (RGB8 = 3 bytes per pixel)
    const pixel_count = config.width * config.height;
    const bitmap = try allocator.alloc(u8, pixel_count * 3);
    errdefer allocator.free(bitmap);

    // Process each pixel
    for (0..config.height) |y| {
        for (0..config.width) |x| {
            // Convert pixel center to shape coordinates
            const px = (@as(f64, @floatFromInt(x)) + 0.5) / config.scale.x - config.translate.x;
            const py = (@as(f64, @floatFromInt(y)) + 0.5) / config.scale.y - config.translate.y;
            const point = Vec2.init(px, py);

            // Find minimum distance for each color channel
            var dists = ChannelDistances{};

            for (shape.contours.items) |contour| {
                for (contour.edges.items) |edge| {
                    const dist = edge.signedDistance(point);
                    const color = edge.color();

                    // Update per-channel distances
                    if (color.hasRed() and dist.isCloser(dists.r)) {
                        dists.r = dist;
                    }
                    if (color.hasGreen() and dist.isCloser(dists.g)) {
                        dists.g = dist;
                    }
                    if (color.hasBlue() and dist.isCloser(dists.b)) {
                        dists.b = dist;
                    }
                }
            }

            // Determine inside/outside using winding number
            const winding = calculateWinding(point, shape);
            const inside = winding != 0;

            // Apply sign based on inside/outside
            var r_dist = dists.r.distance;
            var g_dist = dists.g.distance;
            var b_dist = dists.b.distance;

            // If inside, distances should be negative
            if (inside) {
                r_dist = -@abs(r_dist);
                g_dist = -@abs(g_dist);
                b_dist = -@abs(b_dist);
            } else {
                r_dist = @abs(r_dist);
                g_dist = @abs(g_dist);
                b_dist = @abs(b_dist);
            }

            // Convert to pixel values
            const idx = (y * config.width + x) * 3;
            bitmap[idx + 0] = distanceToPixel(r_dist, config.range);
            bitmap[idx + 1] = distanceToPixel(g_dist, config.range);
            bitmap[idx + 2] = distanceToPixel(b_dist, config.range);
        }
    }

    return MsdfResult{
        .bitmap = bitmap,
        .width = config.width,
        .height = config.height,
        .allocator = allocator,
    };
}

/// Generate MSDF for a glyph with automatic bounds calculation
pub fn generateMsdfForGlyph(
    allocator: std.mem.Allocator,
    shape: *Shape,
    output_size: u32,
    padding: u32,
    range: f64,
) !MsdfResult {
    // Calculate shape bounds
    const b = shape.bounds();

    // Handle empty shape
    if (b.min.x > b.max.x or b.min.y > b.max.y) {
        // Return empty MSDF (all pixels at edge value)
        const pixel_count = output_size * output_size;
        const bitmap = try allocator.alloc(u8, pixel_count * 3);
        @memset(bitmap, 127); // Edge value
        return MsdfResult{
            .bitmap = bitmap,
            .width = output_size,
            .height = output_size,
            .allocator = allocator,
        };
    }

    // Calculate scale to fit glyph in output size with padding
    const glyph_width = b.max.x - b.min.x;
    const glyph_height = b.max.y - b.min.y;

    // Available space after padding
    const available = @as(f64, @floatFromInt(output_size - 2 * padding));

    // Scale to fit (maintain aspect ratio)
    const scale_x = if (glyph_width > 0) available / glyph_width else 1.0;
    const scale_y = if (glyph_height > 0) available / glyph_height else 1.0;
    const scale = @min(scale_x, scale_y);

    // Center the glyph
    const scaled_width = glyph_width * scale;
    const scaled_height = glyph_height * scale;
    const offset_x = (@as(f64, @floatFromInt(output_size)) - scaled_width) / 2.0;
    const offset_y = (@as(f64, @floatFromInt(output_size)) - scaled_height) / 2.0;

    // Translation: map shape coordinates to pixel coordinates
    const translate = Vec2.init(
        b.min.x - offset_x / scale,
        b.min.y - offset_y / scale,
    );

    return generateMsdf(allocator, shape, .{
        .width = output_size,
        .height = output_size,
        .range = range / scale, // Scale range to match
        .translate = translate,
        .scale = Vec2.init(scale, scale),
    });
}

// ============================================================================
// Tests
// ============================================================================

test "distanceToPixel - on edge" {
    const pixel = distanceToPixel(0, 4.0);
    try std.testing.expectEqual(@as(u8, 127), pixel);
}

test "distanceToPixel - inside" {
    const pixel = distanceToPixel(-4.0, 4.0);
    try std.testing.expectEqual(@as(u8, 255), pixel);
}

test "distanceToPixel - outside" {
    const pixel = distanceToPixel(4.0, 4.0);
    try std.testing.expectEqual(@as(u8, 0), pixel);
}

test "distanceToPixel - halfway inside" {
    const pixel = distanceToPixel(-2.0, 4.0);
    try std.testing.expectEqual(@as(u8, 191), pixel);
}

test "generateMsdf - simple square" {
    const allocator = std.testing.allocator;

    var shape = Shape.init(allocator);
    defer shape.deinit();

    // Create a 10x10 square centered at origin
    const contour = try shape.addContour();
    try contour.addEdge(.{ .linear = edge_mod.LinearSegment{ .p0 = Vec2.init(-5, -5), .p1 = Vec2.init(5, -5) } });
    try contour.addEdge(.{ .linear = edge_mod.LinearSegment{ .p0 = Vec2.init(5, -5), .p1 = Vec2.init(5, 5) } });
    try contour.addEdge(.{ .linear = edge_mod.LinearSegment{ .p0 = Vec2.init(5, 5), .p1 = Vec2.init(-5, 5) } });
    try contour.addEdge(.{ .linear = edge_mod.LinearSegment{ .p0 = Vec2.init(-5, 5), .p1 = Vec2.init(-5, -5) } });

    var result = try generateMsdf(allocator, &shape, .{
        .width = 16,
        .height = 16,
        .range = 4.0,
        .scale = Vec2.init(16.0 / 20.0, 16.0 / 20.0), // Map -10 to 10 to 0 to 16
        .translate = Vec2.init(-10, -10),
    });
    defer result.deinit();

    // Check dimensions
    try std.testing.expectEqual(@as(u32, 16), result.width);
    try std.testing.expectEqual(@as(u32, 16), result.height);
    try std.testing.expectEqual(@as(usize, 16 * 16 * 3), result.bitmap.len);

    // Center pixel should be inside (higher values)
    const center = result.getPixel(8, 8);
    try std.testing.expect(center.r > 127);
    try std.testing.expect(center.g > 127);
    try std.testing.expect(center.b > 127);

    // Corner pixel should be outside (lower values)
    const corner = result.getPixel(0, 0);
    try std.testing.expect(corner.r < 127);
    try std.testing.expect(corner.g < 127);
    try std.testing.expect(corner.b < 127);
}

test "generateMsdfForGlyph - auto bounds" {
    const allocator = std.testing.allocator;

    var shape = Shape.init(allocator);
    defer shape.deinit();

    // Create a simple triangle
    const contour = try shape.addContour();
    try contour.addEdge(.{ .linear = edge_mod.LinearSegment{ .p0 = Vec2.init(0, 0), .p1 = Vec2.init(100, 0) } });
    try contour.addEdge(.{ .linear = edge_mod.LinearSegment{ .p0 = Vec2.init(100, 0), .p1 = Vec2.init(50, 100) } });
    try contour.addEdge(.{ .linear = edge_mod.LinearSegment{ .p0 = Vec2.init(50, 100), .p1 = Vec2.init(0, 0) } });

    var result = try generateMsdfForGlyph(allocator, &shape, 32, 4, 4.0);
    defer result.deinit();

    try std.testing.expectEqual(@as(u32, 32), result.width);
    try std.testing.expectEqual(@as(u32, 32), result.height);
}

test "MsdfResult - getPixel" {
    const allocator = std.testing.allocator;

    var shape = Shape.init(allocator);
    defer shape.deinit();

    const contour = try shape.addContour();
    try contour.addEdge(.{ .linear = edge_mod.LinearSegment{ .p0 = Vec2.init(0, 0), .p1 = Vec2.init(10, 0) } });
    try contour.addEdge(.{ .linear = edge_mod.LinearSegment{ .p0 = Vec2.init(10, 0), .p1 = Vec2.init(10, 10) } });
    try contour.addEdge(.{ .linear = edge_mod.LinearSegment{ .p0 = Vec2.init(10, 10), .p1 = Vec2.init(0, 10) } });
    try contour.addEdge(.{ .linear = edge_mod.LinearSegment{ .p0 = Vec2.init(0, 10), .p1 = Vec2.init(0, 0) } });

    var result = try generateMsdfForGlyph(allocator, &shape, 16, 2, 2.0);
    defer result.deinit();

    // Just verify we can get pixels without crashing
    const p = result.getPixel(8, 8);
    _ = p;
}
