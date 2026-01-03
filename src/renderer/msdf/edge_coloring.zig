//! MSDF Edge Coloring
//!
//! Assigns colors (R, G, B) to edges such that corners have edges of different
//! colors meeting. This preserves sharp corners in the MSDF output.
//!
//! The algorithm follows msdfgen's approach:
//! 1. Detect corners (where edge direction changes sharply)
//! 2. Assign colors cyclically (red -> green -> blue)
//! 3. Ensure corners have edges of different colors on each side

const std = @import("std");
const math = @import("math_utils.zig");
const edge_mod = @import("edge.zig");
const contour_mod = @import("contour.zig");
const Vec2 = math.Vec2;
const EdgeSegment = edge_mod.EdgeSegment;
const EdgeColor = edge_mod.EdgeColor;
const Contour = contour_mod.Contour;
const Shape = contour_mod.Shape;

/// Angle threshold for corner detection (in radians)
/// Corners sharper than this threshold will be detected
/// 3.0 radians ≈ 171.9 degrees (almost straight line)
pub const DEFAULT_ANGLE_THRESHOLD: f64 = 3.0;

/// Calculate the angle between two direction vectors
/// Returns angle in radians (0 to pi)
fn angleBetween(dir1: Vec2, dir2: Vec2) f64 {
    const d = dir1.normalize().dot(dir2.normalize());
    // Clamp to handle floating point errors
    const clamped = math.clamp(d, -1.0, 1.0);
    return std.math.acos(clamped);
}

/// Detect if there's a corner between two edges
/// A corner exists when the direction changes sharply (angle < threshold)
fn isCorner(dir1: Vec2, dir2: Vec2, threshold: f64) bool {
    const angle = angleBetween(dir1, dir2);
    // Corner if angle is less than threshold (meaning sharp turn)
    return angle < threshold;
}

/// Cycle to next color in the sequence
fn nextColor(current: EdgeColor) EdgeColor {
    return switch (current) {
        .white, .cyan => .magenta,
        .magenta => .yellow,
        .yellow => .cyan,
        // For single colors, cycle through primary colors
        .red => .green,
        .green => .blue,
        .blue => .red,
        .black => .cyan, // Start with cyan (green + blue)
    };
}

/// Switch to a different color that doesn't conflict
fn switchColor(current: EdgeColor, seed: usize) EdgeColor {
    // Use seed to pick a different color
    const colors = [_]EdgeColor{ .cyan, .magenta, .yellow };
    const idx = (seed + 1) % colors.len;
    const new = colors[idx];
    if (@intFromEnum(new) == @intFromEnum(current)) {
        return colors[(idx + 1) % colors.len];
    }
    return new;
}

/// Color edges of a single contour
fn colorContour(contour: *Contour, threshold: f64) void {
    const edges = contour.edges.items;
    const edge_count = edges.len;

    if (edge_count == 0) return;

    // Special case: single edge gets white (all channels)
    if (edge_count == 1) {
        edges[0].setColor(.white);
        return;
    }

    // Special case: two edges
    if (edge_count == 2) {
        edges[0].setColor(.cyan); // G + B
        edges[1].setColor(.magenta); // R + B
        return;
    }

    // Detect corners (indices where corners occur)
    var corner_count: usize = 0;

    // Count corners first
    for (0..edge_count) |i| {
        const prev_idx = if (i == 0) edge_count - 1 else i - 1;
        const prev_dir = edges[prev_idx].endDirection();
        const curr_dir = edges[i].startDirection();

        if (isCorner(prev_dir, curr_dir, threshold)) {
            corner_count += 1;
        }
    }

    // If no corners detected, use simple coloring
    if (corner_count == 0) {
        // Distribute colors evenly
        for (edges, 0..) |*edge, i| {
            const colors = [_]EdgeColor{ .cyan, .magenta, .yellow };
            edge.setColor(colors[i % colors.len]);
        }
        return;
    }

    // Color edges based on corners
    var current_color = EdgeColor.cyan;

    // Find first corner to start coloring from
    var start_idx: usize = 0;
    for (0..edge_count) |i| {
        const prev_idx = if (i == 0) edge_count - 1 else i - 1;
        const prev_dir = edges[prev_idx].endDirection();
        const curr_dir = edges[i].startDirection();

        if (isCorner(prev_dir, curr_dir, threshold)) {
            start_idx = i;
            break;
        }
    }

    // Color edges starting from first corner
    for (0..edge_count) |offset| {
        const i = (start_idx + offset) % edge_count;
        const next_idx = (i + 1) % edge_count;

        // Check if this edge ends at a corner
        const curr_dir = edges[i].endDirection();
        const next_dir = edges[next_idx].startDirection();
        const ends_at_corner = isCorner(curr_dir, next_dir, threshold);

        // Assign current color
        edges[i].setColor(current_color);

        // If we're at a corner, switch color for next edge
        if (ends_at_corner) {
            current_color = nextColor(current_color);
        }
    }
}

/// Color all edges in a shape
/// Each contour is colored independently
pub fn colorEdges(shape: *Shape, threshold: f64) void {
    for (shape.contours.items) |*contour| {
        colorContour(contour, threshold);
    }
}

/// Color edges using default threshold
pub fn colorEdgesDefault(shape: *Shape) void {
    colorEdges(shape, DEFAULT_ANGLE_THRESHOLD);
}

// ============================================================================
// Tests
// ============================================================================

test "angleBetween - perpendicular" {
    const dir1 = Vec2.init(1, 0);
    const dir2 = Vec2.init(0, 1);

    const angle = angleBetween(dir1, dir2);
    try std.testing.expectApproxEqAbs(std.math.pi / 2.0, angle, 0.001);
}

test "angleBetween - parallel" {
    const dir1 = Vec2.init(1, 0);
    const dir2 = Vec2.init(1, 0);

    const angle = angleBetween(dir1, dir2);
    try std.testing.expectApproxEqAbs(0.0, angle, 0.001);
}

test "angleBetween - opposite" {
    const dir1 = Vec2.init(1, 0);
    const dir2 = Vec2.init(-1, 0);

    const angle = angleBetween(dir1, dir2);
    try std.testing.expectApproxEqAbs(std.math.pi, angle, 0.001);
}

test "isCorner - sharp corner" {
    const dir1 = Vec2.init(1, 0); // Going right
    const dir2 = Vec2.init(0, 1); // Then going up

    // 90 degree turn should be detected as corner
    try std.testing.expect(isCorner(dir1, dir2, DEFAULT_ANGLE_THRESHOLD));
}

test "isCorner - slight bend" {
    const dir1 = Vec2.init(1, 0); // Going right
    const dir2 = Vec2.init(1, 0.1); // Slight upward bend

    // Almost straight should NOT be a corner
    try std.testing.expect(!isCorner(dir1, dir2, DEFAULT_ANGLE_THRESHOLD));
}

test "colorContour - single edge" {
    const allocator = std.testing.allocator;

    var contour = Contour.init(allocator);
    defer contour.deinit();

    try contour.addEdge(.{ .linear = edge_mod.LinearSegment{
        .p0 = Vec2.init(0, 0),
        .p1 = Vec2.init(10, 0),
    } });

    colorContour(&contour, DEFAULT_ANGLE_THRESHOLD);

    // Single edge should be white (all channels)
    try std.testing.expect(contour.edges.items[0].color() == .white);
}

test "colorContour - two edges" {
    const allocator = std.testing.allocator;

    var contour = Contour.init(allocator);
    defer contour.deinit();

    try contour.addEdge(.{ .linear = edge_mod.LinearSegment{
        .p0 = Vec2.init(0, 0),
        .p1 = Vec2.init(10, 0),
    } });
    try contour.addEdge(.{ .linear = edge_mod.LinearSegment{
        .p0 = Vec2.init(10, 0),
        .p1 = Vec2.init(0, 0),
    } });

    colorContour(&contour, DEFAULT_ANGLE_THRESHOLD);

    // Two edges should have different colors
    const c1 = contour.edges.items[0].color();
    const c2 = contour.edges.items[1].color();
    try std.testing.expect(@intFromEnum(c1) != @intFromEnum(c2));
}

test "colorContour - square" {
    const allocator = std.testing.allocator;

    var contour = Contour.init(allocator);
    defer contour.deinit();

    // Create a square (4 edges with 90-degree corners)
    try contour.addEdge(.{ .linear = edge_mod.LinearSegment{ .p0 = Vec2.init(0, 0), .p1 = Vec2.init(10, 0) } });
    try contour.addEdge(.{ .linear = edge_mod.LinearSegment{ .p0 = Vec2.init(10, 0), .p1 = Vec2.init(10, 10) } });
    try contour.addEdge(.{ .linear = edge_mod.LinearSegment{ .p0 = Vec2.init(10, 10), .p1 = Vec2.init(0, 10) } });
    try contour.addEdge(.{ .linear = edge_mod.LinearSegment{ .p0 = Vec2.init(0, 10), .p1 = Vec2.init(0, 0) } });

    colorContour(&contour, DEFAULT_ANGLE_THRESHOLD);

    // All edges should have a color assigned
    for (contour.edges.items) |edge| {
        try std.testing.expect(edge.color() != .black);
    }
}

test "colorEdges - shape with multiple contours" {
    const allocator = std.testing.allocator;

    var shape = Shape.init(allocator);
    defer shape.deinit();

    // Add outer contour
    const outer = try shape.addContour();
    try outer.addEdge(.{ .linear = edge_mod.LinearSegment{ .p0 = Vec2.init(0, 0), .p1 = Vec2.init(20, 0) } });
    try outer.addEdge(.{ .linear = edge_mod.LinearSegment{ .p0 = Vec2.init(20, 0), .p1 = Vec2.init(20, 20) } });
    try outer.addEdge(.{ .linear = edge_mod.LinearSegment{ .p0 = Vec2.init(20, 20), .p1 = Vec2.init(0, 20) } });
    try outer.addEdge(.{ .linear = edge_mod.LinearSegment{ .p0 = Vec2.init(0, 20), .p1 = Vec2.init(0, 0) } });

    // Add inner contour (hole)
    const inner = try shape.addContour();
    try inner.addEdge(.{ .linear = edge_mod.LinearSegment{ .p0 = Vec2.init(5, 5), .p1 = Vec2.init(15, 5) } });
    try inner.addEdge(.{ .linear = edge_mod.LinearSegment{ .p0 = Vec2.init(15, 5), .p1 = Vec2.init(15, 15) } });
    try inner.addEdge(.{ .linear = edge_mod.LinearSegment{ .p0 = Vec2.init(15, 15), .p1 = Vec2.init(5, 15) } });
    try inner.addEdge(.{ .linear = edge_mod.LinearSegment{ .p0 = Vec2.init(5, 15), .p1 = Vec2.init(5, 5) } });

    colorEdges(&shape, DEFAULT_ANGLE_THRESHOLD);

    // All edges in both contours should have colors
    for (shape.contours.items) |contour| {
        for (contour.edges.items) |edge| {
            try std.testing.expect(edge.color() != .black);
        }
    }
}
