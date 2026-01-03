//! MSDF Edge Segments
//!
//! Defines edge segment types (linear, quadratic Bezier, cubic Bezier) and their
//! signed distance calculations for MSDF text rendering.

const std = @import("std");
const math = @import("math_utils.zig");
const Vec2 = math.Vec2;
const SignedDistance = math.SignedDistance;

/// Edge color for MSDF channel assignment
/// Each edge is assigned a color that determines which RGB channels it affects
pub const EdgeColor = enum(u3) {
    black = 0, // No channel (invalid/unassigned)
    red = 1, // R channel only
    green = 2, // G channel only
    yellow = 3, // R + G channels
    blue = 4, // B channel only
    magenta = 5, // R + B channels
    cyan = 6, // G + B channels
    white = 7, // All channels (R + G + B)

    /// Check if this color contributes to the red channel
    pub fn hasRed(self: EdgeColor) bool {
        return (@intFromEnum(self) & 1) != 0;
    }

    /// Check if this color contributes to the green channel
    pub fn hasGreen(self: EdgeColor) bool {
        return (@intFromEnum(self) & 2) != 0;
    }

    /// Check if this color contributes to the blue channel
    pub fn hasBlue(self: EdgeColor) bool {
        return (@intFromEnum(self) & 4) != 0;
    }
};

/// Linear edge segment (straight line)
pub const LinearSegment = struct {
    p0: Vec2, // Start point
    p1: Vec2, // End point
    color: EdgeColor = .white,

    /// Calculate signed distance from a point to this line segment
    pub fn signedDistance(self: LinearSegment, origin: Vec2) SignedDistance {
        const edge_dir = self.p1.sub(self.p0);
        const to_origin = origin.sub(self.p0);

        // Project origin onto line
        const edge_len_sq = edge_dir.lengthSquared();
        if (edge_len_sq == 0) {
            // Degenerate segment (point)
            return SignedDistance.init(to_origin.length(), 0);
        }

        var t = edge_dir.dot(to_origin) / edge_len_sq;

        // Clamp to segment
        t = math.clamp(t, 0, 1);

        // Vector from closest point to origin
        const closest = self.p0.add(edge_dir.scale(t));
        const diff = origin.sub(closest);
        const dist = diff.length();

        // Determine sign using cross product (left = inside = negative)
        const cross = edge_dir.cross(to_origin);
        const signed_dist = if (cross < 0) -dist else dist;

        // Calculate orthogonality (how perpendicular the approach is)
        // 0 at endpoints, 1 when perpendicular to edge
        const orthogonality = if (dist == 0) 0 else @abs(edge_dir.cross(diff)) / (edge_dir.length() * dist);

        return SignedDistance.init(signed_dist, orthogonality);
    }

    /// Get point on segment at parameter t (0 = p0, 1 = p1)
    pub fn point(self: LinearSegment, t: f64) Vec2 {
        return Vec2.lerp(self.p0, self.p1, t);
    }

    /// Get tangent direction at parameter t
    pub fn direction(self: LinearSegment, t: f64) Vec2 {
        _ = t;
        return self.p1.sub(self.p0).normalize();
    }
};

/// Quadratic Bezier edge segment
pub const QuadraticSegment = struct {
    p0: Vec2, // Start point
    p1: Vec2, // Control point
    p2: Vec2, // End point
    color: EdgeColor = .white,

    /// Calculate signed distance from a point to this quadratic Bezier
    pub fn signedDistance(self: QuadraticSegment, origin: Vec2) SignedDistance {
        // Quadratic Bezier: B(t) = (1-t)^2*P0 + 2(1-t)t*P1 + t^2*P2
        // Distance minimization requires solving a cubic equation

        const qa = self.p0.sub(origin);
        const ab = self.p1.sub(self.p0).scale(2);
        const br = self.p0.add(self.p2).sub(self.p1.scale(2));

        // Coefficients for the cubic derivative equation
        const a = br.dot(br);
        const b = 3 * ab.dot(br);
        const c = 2 * ab.dot(ab) + qa.dot(br).scale(2);
        const d = qa.dot(ab);

        // Solve cubic
        var roots: [3]f64 = undefined;
        const n_roots = math.solveCubic(&roots, a, b, c, d);

        // Check all roots plus endpoints
        var min_dist = SignedDistance.infinite;

        // Check endpoints
        min_dist = self.checkDistance(min_dist, origin, 0);
        min_dist = self.checkDistance(min_dist, origin, 1);

        // Check interior roots
        for (0..n_roots) |i| {
            const t = roots[i];
            if (t > 0 and t < 1) {
                min_dist = self.checkDistance(min_dist, origin, t);
            }
        }

        return min_dist;
    }

    fn checkDistance(self: QuadraticSegment, current: SignedDistance, origin: Vec2, t: f64) SignedDistance {
        const p = self.point(t);
        const diff = origin.sub(p);
        const dist = diff.length();

        // Get direction at t for sign determination
        const dir = self.direction(t);
        const cross = dir.cross(diff);
        const signed_dist = if (cross < 0) -dist else dist;

        // Orthogonality
        const orthogonality = if (dist == 0) 0 else @abs(dir.cross(diff.normalize()));

        const new_dist = SignedDistance.init(signed_dist, orthogonality);
        return if (new_dist.isCloser(current)) new_dist else current;
    }

    /// Get point on curve at parameter t
    pub fn point(self: QuadraticSegment, t: f64) Vec2 {
        const t1 = 1 - t;
        return .{
            .x = t1 * t1 * self.p0.x + 2 * t1 * t * self.p1.x + t * t * self.p2.x,
            .y = t1 * t1 * self.p0.y + 2 * t1 * t * self.p1.y + t * t * self.p2.y,
        };
    }

    /// Get tangent direction at parameter t
    pub fn direction(self: QuadraticSegment, t: f64) Vec2 {
        // Derivative: B'(t) = 2(1-t)(P1-P0) + 2t(P2-P1)
        const t1 = 1 - t;
        const tangent = Vec2{
            .x = 2 * t1 * (self.p1.x - self.p0.x) + 2 * t * (self.p2.x - self.p1.x),
            .y = 2 * t1 * (self.p1.y - self.p0.y) + 2 * t * (self.p2.y - self.p1.y),
        };
        return tangent.normalize();
    }
};

/// Cubic Bezier edge segment
pub const CubicSegment = struct {
    p0: Vec2, // Start point
    p1: Vec2, // Control point 1
    p2: Vec2, // Control point 2
    p3: Vec2, // End point
    color: EdgeColor = .white,

    /// Calculate signed distance from a point to this cubic Bezier
    /// Uses iterative subdivision since cubic distance has no closed-form solution
    pub fn signedDistance(self: CubicSegment, origin: Vec2) SignedDistance {
        // Use iterative refinement with initial sampling
        const num_samples = 16;
        var min_dist = SignedDistance.infinite;
        var best_t: f64 = 0;

        // Initial sampling to find approximate minimum
        for (0..num_samples + 1) |i| {
            const t = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(num_samples));
            const dist = self.checkDistance(min_dist, origin, t);
            if (dist.isCloser(min_dist)) {
                min_dist = dist;
                best_t = t;
            }
        }

        // Refine with Newton-Raphson iterations
        var t = best_t;
        for (0..4) |_| {
            const p = self.point(t);
            const d1 = self.derivative1(t);
            const d2 = self.derivative2(t);

            const diff = p.sub(origin);

            // f(t) = (B(t) - origin) . B'(t) = 0 at minimum
            const f = diff.dot(d1);
            const f_prime = d1.dot(d1) + diff.dot(d2);

            if (@abs(f_prime) < 1e-10) break;

            const new_t = t - f / f_prime;
            t = math.clamp(new_t, 0, 1);
        }

        // Final distance calculation
        min_dist = self.checkDistance(min_dist, origin, t);

        return min_dist;
    }

    fn checkDistance(self: CubicSegment, current: SignedDistance, origin: Vec2, t: f64) SignedDistance {
        const p = self.point(t);
        const diff = origin.sub(p);
        const dist = diff.length();

        // Get direction at t for sign determination
        const dir = self.direction(t);
        const cross = dir.cross(diff);
        const signed_dist = if (cross < 0) -dist else dist;

        // Orthogonality
        const orthogonality = if (dist == 0) 0 else @abs(dir.cross(diff.normalize()));

        const new_dist = SignedDistance.init(signed_dist, orthogonality);
        return if (new_dist.isCloser(current)) new_dist else current;
    }

    /// Get point on curve at parameter t
    pub fn point(self: CubicSegment, t: f64) Vec2 {
        const t1 = 1 - t;
        const t1_2 = t1 * t1;
        const t1_3 = t1_2 * t1;
        const t2 = t * t;
        const t3 = t2 * t;

        return .{
            .x = t1_3 * self.p0.x + 3 * t1_2 * t * self.p1.x + 3 * t1 * t2 * self.p2.x + t3 * self.p3.x,
            .y = t1_3 * self.p0.y + 3 * t1_2 * t * self.p1.y + 3 * t1 * t2 * self.p2.y + t3 * self.p3.y,
        };
    }

    /// Get tangent direction at parameter t (normalized first derivative)
    pub fn direction(self: CubicSegment, t: f64) Vec2 {
        return self.derivative1(t).normalize();
    }

    /// First derivative B'(t)
    fn derivative1(self: CubicSegment, t: f64) Vec2 {
        const t1 = 1 - t;
        const t1_2 = t1 * t1;
        const t2 = t * t;

        return .{
            .x = 3 * t1_2 * (self.p1.x - self.p0.x) + 6 * t1 * t * (self.p2.x - self.p1.x) + 3 * t2 * (self.p3.x - self.p2.x),
            .y = 3 * t1_2 * (self.p1.y - self.p0.y) + 6 * t1 * t * (self.p2.y - self.p1.y) + 3 * t2 * (self.p3.y - self.p2.y),
        };
    }

    /// Second derivative B''(t)
    fn derivative2(self: CubicSegment, t: f64) Vec2 {
        const t1 = 1 - t;
        return .{
            .x = 6 * t1 * (self.p2.x - 2 * self.p1.x + self.p0.x) + 6 * t * (self.p3.x - 2 * self.p2.x + self.p1.x),
            .y = 6 * t1 * (self.p2.y - 2 * self.p1.y + self.p0.y) + 6 * t * (self.p3.y - 2 * self.p2.y + self.p1.y),
        };
    }
};

/// Tagged union for any edge segment type
pub const EdgeSegment = union(enum) {
    linear: LinearSegment,
    quadratic: QuadraticSegment,
    cubic: CubicSegment,

    pub fn signedDistance(self: EdgeSegment, origin: Vec2) SignedDistance {
        return switch (self) {
            .linear => |s| s.signedDistance(origin),
            .quadratic => |s| s.signedDistance(origin),
            .cubic => |s| s.signedDistance(origin),
        };
    }

    pub fn point(self: EdgeSegment, t: f64) Vec2 {
        return switch (self) {
            .linear => |s| s.point(t),
            .quadratic => |s| s.point(t),
            .cubic => |s| s.point(t),
        };
    }

    pub fn direction(self: EdgeSegment, t: f64) Vec2 {
        return switch (self) {
            .linear => |s| s.direction(t),
            .quadratic => |s| s.direction(t),
            .cubic => |s| s.direction(t),
        };
    }

    pub fn startPoint(self: EdgeSegment) Vec2 {
        return switch (self) {
            .linear => |s| s.p0,
            .quadratic => |s| s.p0,
            .cubic => |s| s.p0,
        };
    }

    pub fn endPoint(self: EdgeSegment) Vec2 {
        return switch (self) {
            .linear => |s| s.p1,
            .quadratic => |s| s.p2,
            .cubic => |s| s.p3,
        };
    }

    pub fn color(self: EdgeSegment) EdgeColor {
        return switch (self) {
            .linear => |s| s.color,
            .quadratic => |s| s.color,
            .cubic => |s| s.color,
        };
    }

    pub fn setColor(self: *EdgeSegment, c: EdgeColor) void {
        switch (self.*) {
            .linear => |*s| s.color = c,
            .quadratic => |*s| s.color = c,
            .cubic => |*s| s.color = c,
        }
    }

    /// Get direction at start of segment (t=0)
    pub fn startDirection(self: EdgeSegment) Vec2 {
        return self.direction(0);
    }

    /// Get direction at end of segment (t=1)
    pub fn endDirection(self: EdgeSegment) Vec2 {
        return self.direction(1);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "EdgeColor - channel checks" {
    try std.testing.expect(EdgeColor.red.hasRed());
    try std.testing.expect(!EdgeColor.red.hasGreen());
    try std.testing.expect(!EdgeColor.red.hasBlue());

    try std.testing.expect(EdgeColor.yellow.hasRed());
    try std.testing.expect(EdgeColor.yellow.hasGreen());
    try std.testing.expect(!EdgeColor.yellow.hasBlue());

    try std.testing.expect(EdgeColor.white.hasRed());
    try std.testing.expect(EdgeColor.white.hasGreen());
    try std.testing.expect(EdgeColor.white.hasBlue());
}

test "LinearSegment - signed distance point above" {
    const segment = LinearSegment{
        .p0 = Vec2.init(0, 0),
        .p1 = Vec2.init(10, 0),
    };

    // Point above the line (outside on right side)
    const dist = segment.signedDistance(Vec2.init(5, 3));
    try std.testing.expectApproxEqAbs(3.0, dist.distance, 0.001);
}

test "LinearSegment - signed distance point below" {
    const segment = LinearSegment{
        .p0 = Vec2.init(0, 0),
        .p1 = Vec2.init(10, 0),
    };

    // Point below the line (inside on left side)
    const dist = segment.signedDistance(Vec2.init(5, -3));
    try std.testing.expectApproxEqAbs(-3.0, dist.distance, 0.001);
}

test "LinearSegment - distance to endpoint" {
    const segment = LinearSegment{
        .p0 = Vec2.init(0, 0),
        .p1 = Vec2.init(10, 0),
    };

    // Point beyond end of segment
    const dist = segment.signedDistance(Vec2.init(13, 4));
    try std.testing.expectApproxEqAbs(5.0, @abs(dist.distance), 0.001); // 3-4-5 triangle
}

test "QuadraticSegment - basic curve" {
    const segment = QuadraticSegment{
        .p0 = Vec2.init(0, 0),
        .p1 = Vec2.init(5, 10), // Control point
        .p2 = Vec2.init(10, 0),
    };

    // Point at apex should be close to control point
    const apex = segment.point(0.5);
    try std.testing.expectApproxEqAbs(5.0, apex.x, 0.1);
    try std.testing.expectApproxEqAbs(5.0, apex.y, 0.1); // (0+2*10+0)/4 = 5

    // Distance from control point to curve should be significant
    const dist = segment.signedDistance(Vec2.init(5, 10));
    try std.testing.expect(@abs(dist.distance) < 6.0); // Control point is above curve
}

test "CubicSegment - basic curve" {
    const segment = CubicSegment{
        .p0 = Vec2.init(0, 0),
        .p1 = Vec2.init(3, 10),
        .p2 = Vec2.init(7, 10),
        .p3 = Vec2.init(10, 0),
    };

    // Check endpoints
    const start = segment.point(0);
    try std.testing.expectApproxEqAbs(0.0, start.x, 0.001);
    try std.testing.expectApproxEqAbs(0.0, start.y, 0.001);

    const end = segment.point(1);
    try std.testing.expectApproxEqAbs(10.0, end.x, 0.001);
    try std.testing.expectApproxEqAbs(0.0, end.y, 0.001);

    // Check midpoint is elevated
    const mid = segment.point(0.5);
    try std.testing.expect(mid.y > 0);
}

test "EdgeSegment - tagged union" {
    const linear = EdgeSegment{ .linear = LinearSegment{
        .p0 = Vec2.init(0, 0),
        .p1 = Vec2.init(10, 0),
    } };

    const dist = linear.signedDistance(Vec2.init(5, 5));
    try std.testing.expectApproxEqAbs(5.0, dist.distance, 0.001);

    try std.testing.expect(linear.startPoint().x == 0);
    try std.testing.expect(linear.endPoint().x == 10);
}
