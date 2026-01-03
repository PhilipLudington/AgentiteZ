//! MSDF Contour Decomposition
//!
//! Converts TrueType glyph outlines from stb_truetype vertex format
//! into edge segments for MSDF generation.

const std = @import("std");
const math = @import("math_utils.zig");
const edge_mod = @import("edge.zig");
const Vec2 = math.Vec2;
const EdgeSegment = edge_mod.EdgeSegment;
const EdgeColor = edge_mod.EdgeColor;
const LinearSegment = edge_mod.LinearSegment;
const QuadraticSegment = edge_mod.QuadraticSegment;
const CubicSegment = edge_mod.CubicSegment;

// stb_truetype vertex types
pub const STBTT_vmove: u8 = 1;
pub const STBTT_vline: u8 = 2;
pub const STBTT_vcurve: u8 = 3;
pub const STBTT_vcubic: u8 = 4;

/// stb_truetype vertex structure (matching C struct layout)
pub const StbttVertex = extern struct {
    x: i16,
    y: i16,
    cx: i16,
    cy: i16,
    cx1: i16,
    cy1: i16,
    vertex_type: u8,
    padding: u8 = 0,
};

/// A single contour (closed loop of edges)
pub const Contour = struct {
    edges: std.ArrayList(EdgeSegment),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Contour {
        return .{
            .edges = std.ArrayList(EdgeSegment).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Contour) void {
        self.edges.deinit();
    }

    pub fn addEdge(self: *Contour, e: EdgeSegment) !void {
        try self.edges.append(e);
    }

    /// Calculate winding number of contour (positive = counter-clockwise)
    pub fn winding(self: Contour) i32 {
        if (self.edges.items.len == 0) return 0;

        var total: f64 = 0;
        for (self.edges.items) |e| {
            // Shoelace formula: sum of (x1 - x0) * (y1 + y0)
            const p0 = e.startPoint();
            const p1 = e.endPoint();
            total += (p1.x - p0.x) * (p1.y + p0.y);
        }

        if (total > 0) return 1;
        if (total < 0) return -1;
        return 0;
    }

    /// Get bounds of this contour
    pub fn bounds(self: Contour) struct { min: Vec2, max: Vec2 } {
        var min_v = Vec2{ .x = std.math.inf(f64), .y = std.math.inf(f64) };
        var max_v = Vec2{ .x = -std.math.inf(f64), .y = -std.math.inf(f64) };

        for (self.edges.items) |e| {
            const start = e.startPoint();
            const end = e.endPoint();

            min_v.x = @min(min_v.x, @min(start.x, end.x));
            min_v.y = @min(min_v.y, @min(start.y, end.y));
            max_v.x = @max(max_v.x, @max(start.x, end.x));
            max_v.y = @max(max_v.y, @max(start.y, end.y));

            // Also check control points for curves
            switch (e) {
                .quadratic => |q| {
                    min_v.x = @min(min_v.x, q.p1.x);
                    min_v.y = @min(min_v.y, q.p1.y);
                    max_v.x = @max(max_v.x, q.p1.x);
                    max_v.y = @max(max_v.y, q.p1.y);
                },
                .cubic => |c| {
                    min_v.x = @min(min_v.x, @min(c.p1.x, c.p2.x));
                    min_v.y = @min(min_v.y, @min(c.p1.y, c.p2.y));
                    max_v.x = @max(max_v.x, @max(c.p1.x, c.p2.x));
                    max_v.y = @max(max_v.y, @max(c.p1.y, c.p2.y));
                },
                .linear => {},
            }
        }

        return .{ .min = min_v, .max = max_v };
    }
};

/// A shape consisting of multiple contours
pub const Shape = struct {
    contours: std.ArrayList(Contour),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Shape {
        return .{
            .contours = std.ArrayList(Contour).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Shape) void {
        for (self.contours.items) |*c| {
            c.deinit();
        }
        self.contours.deinit();
    }

    pub fn addContour(self: *Shape) !*Contour {
        try self.contours.append(Contour.init(self.allocator));
        return &self.contours.items[self.contours.items.len - 1];
    }

    /// Build shape from stb_truetype vertex array
    ///
    /// Parameters:
    /// - vertices: Pointer to stb_truetype vertex array
    /// - num_vertices: Number of vertices in array
    /// - scale: Scale factor for coordinates (typically font_size / units_per_em)
    /// - flip_y: If true, flip Y coordinates (TrueType Y is up, MSDF Y is down)
    pub fn fromVertices(
        allocator: std.mem.Allocator,
        vertices: [*]const StbttVertex,
        num_vertices: usize,
        scale: f64,
        flip_y: bool,
    ) !Shape {
        var shape = Shape.init(allocator);
        errdefer shape.deinit();

        var current_contour: ?*Contour = null;
        var contour_start = Vec2.zero;
        var prev_point = Vec2.zero;

        for (0..num_vertices) |i| {
            const v = vertices[i];
            const y_mult: f64 = if (flip_y) -1.0 else 1.0;

            const px = @as(f64, @floatFromInt(v.x)) * scale;
            const py = @as(f64, @floatFromInt(v.y)) * scale * y_mult;

            switch (v.vertex_type) {
                STBTT_vmove => {
                    // Start new contour
                    current_contour = try shape.addContour();
                    contour_start = Vec2.init(px, py);
                    prev_point = contour_start;
                },
                STBTT_vline => {
                    // Linear edge
                    if (current_contour) |contour| {
                        const current = Vec2.init(px, py);
                        try contour.addEdge(.{ .linear = LinearSegment{
                            .p0 = prev_point,
                            .p1 = current,
                        } });
                        prev_point = current;
                    }
                },
                STBTT_vcurve => {
                    // Quadratic Bezier (cx, cy is control point)
                    if (current_contour) |contour| {
                        const cx = @as(f64, @floatFromInt(v.cx)) * scale;
                        const cy = @as(f64, @floatFromInt(v.cy)) * scale * y_mult;
                        const current = Vec2.init(px, py);

                        try contour.addEdge(.{ .quadratic = QuadraticSegment{
                            .p0 = prev_point,
                            .p1 = Vec2.init(cx, cy),
                            .p2 = current,
                        } });
                        prev_point = current;
                    }
                },
                STBTT_vcubic => {
                    // Cubic Bezier (cx, cy is control point 1, cx1, cy1 is control point 2)
                    if (current_contour) |contour| {
                        const cx = @as(f64, @floatFromInt(v.cx)) * scale;
                        const cy = @as(f64, @floatFromInt(v.cy)) * scale * y_mult;
                        const cx1 = @as(f64, @floatFromInt(v.cx1)) * scale;
                        const cy1 = @as(f64, @floatFromInt(v.cy1)) * scale * y_mult;
                        const current = Vec2.init(px, py);

                        try contour.addEdge(.{ .cubic = CubicSegment{
                            .p0 = prev_point,
                            .p1 = Vec2.init(cx, cy),
                            .p2 = Vec2.init(cx1, cy1),
                            .p3 = current,
                        } });
                        prev_point = current;
                    }
                },
                else => {},
            }
        }

        return shape;
    }

    /// Get bounds of entire shape
    pub fn bounds(self: Shape) struct { min: Vec2, max: Vec2 } {
        var min_v = Vec2{ .x = std.math.inf(f64), .y = std.math.inf(f64) };
        var max_v = Vec2{ .x = -std.math.inf(f64), .y = -std.math.inf(f64) };

        for (self.contours.items) |contour| {
            const b = contour.bounds();
            min_v.x = @min(min_v.x, b.min.x);
            min_v.y = @min(min_v.y, b.min.y);
            max_v.x = @max(max_v.x, b.max.x);
            max_v.y = @max(max_v.y, b.max.y);
        }

        return .{ .min = min_v, .max = max_v };
    }

    /// Validate that the shape has proper closed contours
    pub fn validate(self: Shape) bool {
        for (self.contours.items) |contour| {
            if (contour.edges.items.len == 0) continue;

            // Check that contour is closed
            const first = contour.edges.items[0].startPoint();
            const last = contour.edges.items[contour.edges.items.len - 1].endPoint();
            const dist = first.distance(last);

            if (dist > 0.001) return false;
        }
        return true;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Contour - basic operations" {
    const allocator = std.testing.allocator;

    var contour = Contour.init(allocator);
    defer contour.deinit();

    // Create a square contour
    try contour.addEdge(.{ .linear = LinearSegment{ .p0 = Vec2.init(0, 0), .p1 = Vec2.init(10, 0) } });
    try contour.addEdge(.{ .linear = LinearSegment{ .p0 = Vec2.init(10, 0), .p1 = Vec2.init(10, 10) } });
    try contour.addEdge(.{ .linear = LinearSegment{ .p0 = Vec2.init(10, 10), .p1 = Vec2.init(0, 10) } });
    try contour.addEdge(.{ .linear = LinearSegment{ .p0 = Vec2.init(0, 10), .p1 = Vec2.init(0, 0) } });

    try std.testing.expectEqual(@as(usize, 4), contour.edges.items.len);
}

test "Contour - winding" {
    const allocator = std.testing.allocator;

    var contour = Contour.init(allocator);
    defer contour.deinit();

    // Counter-clockwise square
    try contour.addEdge(.{ .linear = LinearSegment{ .p0 = Vec2.init(0, 0), .p1 = Vec2.init(10, 0) } });
    try contour.addEdge(.{ .linear = LinearSegment{ .p0 = Vec2.init(10, 0), .p1 = Vec2.init(10, 10) } });
    try contour.addEdge(.{ .linear = LinearSegment{ .p0 = Vec2.init(10, 10), .p1 = Vec2.init(0, 10) } });
    try contour.addEdge(.{ .linear = LinearSegment{ .p0 = Vec2.init(0, 10), .p1 = Vec2.init(0, 0) } });

    const w = contour.winding();
    try std.testing.expect(w != 0);
}

test "Shape - basic operations" {
    const allocator = std.testing.allocator;

    var shape = Shape.init(allocator);
    defer shape.deinit();

    const contour1 = try shape.addContour();
    try contour1.addEdge(.{ .linear = LinearSegment{ .p0 = Vec2.init(0, 0), .p1 = Vec2.init(10, 0) } });

    const contour2 = try shape.addContour();
    try contour2.addEdge(.{ .linear = LinearSegment{ .p0 = Vec2.init(20, 0), .p1 = Vec2.init(30, 0) } });

    try std.testing.expectEqual(@as(usize, 2), shape.contours.items.len);
}

test "Shape - fromVertices with simple line" {
    const allocator = std.testing.allocator;

    // Create a simple triangle using stb_truetype vertex format
    const vertices = [_]StbttVertex{
        .{ .x = 0, .y = 0, .cx = 0, .cy = 0, .cx1 = 0, .cy1 = 0, .vertex_type = STBTT_vmove },
        .{ .x = 100, .y = 0, .cx = 0, .cy = 0, .cx1 = 0, .cy1 = 0, .vertex_type = STBTT_vline },
        .{ .x = 50, .y = 100, .cx = 0, .cy = 0, .cx1 = 0, .cy1 = 0, .vertex_type = STBTT_vline },
        .{ .x = 0, .y = 0, .cx = 0, .cy = 0, .cx1 = 0, .cy1 = 0, .vertex_type = STBTT_vline },
    };

    var shape = try Shape.fromVertices(allocator, &vertices, vertices.len, 1.0, false);
    defer shape.deinit();

    try std.testing.expectEqual(@as(usize, 1), shape.contours.items.len);
    try std.testing.expectEqual(@as(usize, 3), shape.contours.items[0].edges.items.len);
}

test "Shape - fromVertices with quadratic curve" {
    const allocator = std.testing.allocator;

    // Create a simple curved shape
    const vertices = [_]StbttVertex{
        .{ .x = 0, .y = 0, .cx = 0, .cy = 0, .cx1 = 0, .cy1 = 0, .vertex_type = STBTT_vmove },
        .{ .x = 100, .y = 0, .cx = 50, .cy = 50, .cx1 = 0, .cy1 = 0, .vertex_type = STBTT_vcurve },
        .{ .x = 0, .y = 0, .cx = 0, .cy = 0, .cx1 = 0, .cy1 = 0, .vertex_type = STBTT_vline },
    };

    var shape = try Shape.fromVertices(allocator, &vertices, vertices.len, 1.0, false);
    defer shape.deinit();

    try std.testing.expectEqual(@as(usize, 1), shape.contours.items.len);
    try std.testing.expectEqual(@as(usize, 2), shape.contours.items[0].edges.items.len);

    // First edge should be quadratic
    const first_edge = shape.contours.items[0].edges.items[0];
    try std.testing.expect(first_edge == .quadratic);
}

test "Shape - bounds" {
    const allocator = std.testing.allocator;

    var shape = Shape.init(allocator);
    defer shape.deinit();

    const contour = try shape.addContour();
    try contour.addEdge(.{ .linear = LinearSegment{ .p0 = Vec2.init(10, 20), .p1 = Vec2.init(100, 20) } });
    try contour.addEdge(.{ .linear = LinearSegment{ .p0 = Vec2.init(100, 20), .p1 = Vec2.init(100, 80) } });
    try contour.addEdge(.{ .linear = LinearSegment{ .p0 = Vec2.init(100, 80), .p1 = Vec2.init(10, 80) } });
    try contour.addEdge(.{ .linear = LinearSegment{ .p0 = Vec2.init(10, 80), .p1 = Vec2.init(10, 20) } });

    const b = shape.bounds();
    try std.testing.expectApproxEqAbs(10.0, b.min.x, 0.001);
    try std.testing.expectApproxEqAbs(20.0, b.min.y, 0.001);
    try std.testing.expectApproxEqAbs(100.0, b.max.x, 0.001);
    try std.testing.expectApproxEqAbs(80.0, b.max.y, 0.001);
}
