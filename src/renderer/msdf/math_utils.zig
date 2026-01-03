//! MSDF Math Utilities
//!
//! Provides vector math, signed distance calculations, and polynomial solvers
//! for the MSDF (Multi-channel Signed Distance Field) text rendering system.

const std = @import("std");

/// 2D vector with double precision for accurate distance calculations
pub const Vec2 = struct {
    x: f64,
    y: f64,

    pub const zero = Vec2{ .x = 0, .y = 0 };

    pub fn init(x: f64, y: f64) Vec2 {
        return .{ .x = x, .y = y };
    }

    pub fn add(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }

    pub fn sub(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x - b.x, .y = a.y - b.y };
    }

    pub fn scale(v: Vec2, s: f64) Vec2 {
        return .{ .x = v.x * s, .y = v.y * s };
    }

    pub fn negate(v: Vec2) Vec2 {
        return .{ .x = -v.x, .y = -v.y };
    }

    pub fn dot(a: Vec2, b: Vec2) f64 {
        return a.x * b.x + a.y * b.y;
    }

    /// 2D cross product (returns scalar z-component of 3D cross)
    pub fn cross(a: Vec2, b: Vec2) f64 {
        return a.x * b.y - a.y * b.x;
    }

    pub fn lengthSquared(v: Vec2) f64 {
        return v.x * v.x + v.y * v.y;
    }

    pub fn length(v: Vec2) f64 {
        return @sqrt(v.lengthSquared());
    }

    pub fn normalize(v: Vec2) Vec2 {
        const len = v.length();
        if (len == 0) return Vec2.zero;
        return v.scale(1.0 / len);
    }

    pub fn distance(a: Vec2, b: Vec2) f64 {
        return a.sub(b).length();
    }

    pub fn distanceSquared(a: Vec2, b: Vec2) f64 {
        return a.sub(b).lengthSquared();
    }

    /// Perpendicular vector (90 degrees counter-clockwise)
    pub fn perpendicular(v: Vec2) Vec2 {
        return .{ .x = -v.y, .y = v.x };
    }

    /// Linear interpolation between two vectors
    pub fn lerp(a: Vec2, b: Vec2, t: f64) Vec2 {
        return .{
            .x = a.x + (b.x - a.x) * t,
            .y = a.y + (b.y - a.y) * t,
        };
    }
};

/// Signed distance result with orthogonality for tie-breaking
/// When two points are equidistant, the one with higher orthogonality wins
pub const SignedDistance = struct {
    /// Signed distance (negative = inside, positive = outside)
    distance: f64,
    /// Dot product used for tie-breaking (higher = more orthogonal approach)
    dot: f64,

    pub const infinite = SignedDistance{
        .distance = std.math.inf(f64),
        .dot = 1,
    };

    pub fn init(distance: f64, dot: f64) SignedDistance {
        return .{ .distance = distance, .dot = dot };
    }

    /// Returns true if `a` is closer (or equal distance but more orthogonal)
    pub fn isCloser(a: SignedDistance, b: SignedDistance) bool {
        const abs_a = @abs(a.distance);
        const abs_b = @abs(b.distance);
        if (abs_a < abs_b) return true;
        if (abs_a > abs_b) return false;
        // Equal distance: prefer higher orthogonality
        return a.dot > b.dot;
    }
};

// ============================================================================
// Utility Functions
// ============================================================================

pub fn clamp(value: f64, min_val: f64, max_val: f64) f64 {
    return @max(min_val, @min(max_val, value));
}

pub fn sign(value: f64) f64 {
    if (value > 0) return 1;
    if (value < 0) return -1;
    return 0;
}

pub fn lerpf(a: f64, b: f64, t: f64) f64 {
    return a + (b - a) * t;
}

/// Non-zero sign that returns 1 for zero (useful for winding calculations)
pub fn nonZeroSign(value: f64) f64 {
    return if (value >= 0) 1 else -1;
}

// ============================================================================
// Polynomial Solvers
// ============================================================================

/// Solve quadratic equation: a*x^2 + b*x + c = 0
/// Returns number of real roots and fills `roots` array
pub fn solveQuadratic(roots: *[2]f64, a: f64, b: f64, c: f64) u8 {
    // Handle degenerate cases
    if (@abs(a) < 1e-14) {
        // Linear equation: b*x + c = 0
        if (@abs(b) < 1e-14) {
            return 0; // No solution or infinite solutions
        }
        roots[0] = -c / b;
        return 1;
    }

    const discriminant = b * b - 4 * a * c;

    if (discriminant > 0) {
        const sqrt_d = @sqrt(discriminant);
        roots[0] = (-b - sqrt_d) / (2 * a);
        roots[1] = (-b + sqrt_d) / (2 * a);
        return 2;
    } else if (discriminant == 0) {
        roots[0] = -b / (2 * a);
        return 1;
    }

    return 0; // No real roots
}

/// Solve cubic equation: a*x^3 + b*x^2 + c*x + d = 0
/// Returns number of real roots and fills `roots` array
/// Uses Cardano's formula with trigonometric method for three real roots
pub fn solveCubic(roots: *[3]f64, a: f64, b: f64, c: f64, d: f64) u8 {
    // Handle degenerate case
    if (@abs(a) < 1e-14) {
        var quad_roots: [2]f64 = undefined;
        const n = solveQuadratic(&quad_roots, b, c, d);
        for (0..n) |i| {
            roots[i] = quad_roots[i];
        }
        return n;
    }

    // Normalize: x^3 + p*x^2 + q*x + r = 0
    const p = b / a;
    const q = c / a;
    const r = d / a;

    // Substitute x = t - p/3 to get depressed cubic: t^3 + pt + q = 0
    const p_over_3 = p / 3.0;
    const p2 = p * p;
    const p3 = p2 * p;

    // Coefficients of depressed cubic
    const dp = q - p2 / 3.0;
    const dq = r - p * q / 3.0 + 2.0 * p3 / 27.0;

    // Discriminant
    const dp3 = dp * dp * dp;
    const discriminant = dq * dq / 4.0 + dp3 / 27.0;

    if (discriminant > 1e-14) {
        // One real root
        const sqrt_disc = @sqrt(discriminant);
        const u = cubeRoot(-dq / 2.0 + sqrt_disc);
        const v = cubeRoot(-dq / 2.0 - sqrt_disc);
        roots[0] = u + v - p_over_3;
        return 1;
    } else if (discriminant < -1e-14) {
        // Three real roots (use trigonometric method)
        const m = @sqrt(-dp / 3.0);
        const theta = std.math.acos(3.0 * dq / (2.0 * dp * m)) / 3.0;
        const two_pi_over_3 = 2.0 * std.math.pi / 3.0;

        roots[0] = 2.0 * m * @cos(theta) - p_over_3;
        roots[1] = 2.0 * m * @cos(theta - two_pi_over_3) - p_over_3;
        roots[2] = 2.0 * m * @cos(theta + two_pi_over_3) - p_over_3;
        return 3;
    } else {
        // Discriminant ~ 0: multiple roots
        if (@abs(dq) < 1e-14) {
            // Triple root
            roots[0] = -p_over_3;
            return 1;
        } else {
            // Double root + single root
            const u = cubeRoot(-dq / 2.0);
            roots[0] = 2.0 * u - p_over_3;
            roots[1] = -u - p_over_3;
            return 2;
        }
    }
}

/// Cube root that handles negative numbers correctly
fn cubeRoot(x: f64) f64 {
    if (x >= 0) {
        return std.math.pow(f64, x, 1.0 / 3.0);
    } else {
        return -std.math.pow(f64, -x, 1.0 / 3.0);
    }
}

// ============================================================================
// Tests
// ============================================================================

test "Vec2 - basic operations" {
    const a = Vec2.init(3, 4);
    const b = Vec2.init(1, 2);

    const sum = a.add(b);
    try std.testing.expectApproxEqAbs(4.0, sum.x, 0.001);
    try std.testing.expectApproxEqAbs(6.0, sum.y, 0.001);

    const diff = a.sub(b);
    try std.testing.expectApproxEqAbs(2.0, diff.x, 0.001);
    try std.testing.expectApproxEqAbs(2.0, diff.y, 0.001);

    const scaled = a.scale(2);
    try std.testing.expectApproxEqAbs(6.0, scaled.x, 0.001);
    try std.testing.expectApproxEqAbs(8.0, scaled.y, 0.001);
}

test "Vec2 - length and normalize" {
    const v = Vec2.init(3, 4);

    try std.testing.expectApproxEqAbs(25.0, v.lengthSquared(), 0.001);
    try std.testing.expectApproxEqAbs(5.0, v.length(), 0.001);

    const norm = v.normalize();
    try std.testing.expectApproxEqAbs(0.6, norm.x, 0.001);
    try std.testing.expectApproxEqAbs(0.8, norm.y, 0.001);
    try std.testing.expectApproxEqAbs(1.0, norm.length(), 0.001);
}

test "Vec2 - dot and cross product" {
    const a = Vec2.init(1, 0);
    const b = Vec2.init(0, 1);

    try std.testing.expectApproxEqAbs(0.0, a.dot(b), 0.001);
    try std.testing.expectApproxEqAbs(1.0, a.cross(b), 0.001);
    try std.testing.expectApproxEqAbs(-1.0, b.cross(a), 0.001);

    const c = Vec2.init(3, 4);
    const d = Vec2.init(2, 1);
    try std.testing.expectApproxEqAbs(10.0, c.dot(d), 0.001);
}

test "Vec2 - distance" {
    const a = Vec2.init(0, 0);
    const b = Vec2.init(3, 4);

    try std.testing.expectApproxEqAbs(5.0, a.distance(b), 0.001);
    try std.testing.expectApproxEqAbs(25.0, a.distanceSquared(b), 0.001);
}

test "Vec2 - lerp" {
    const a = Vec2.init(0, 0);
    const b = Vec2.init(10, 20);

    const mid = Vec2.lerp(a, b, 0.5);
    try std.testing.expectApproxEqAbs(5.0, mid.x, 0.001);
    try std.testing.expectApproxEqAbs(10.0, mid.y, 0.001);

    const quarter = Vec2.lerp(a, b, 0.25);
    try std.testing.expectApproxEqAbs(2.5, quarter.x, 0.001);
    try std.testing.expectApproxEqAbs(5.0, quarter.y, 0.001);
}

test "SignedDistance - comparison" {
    const closer = SignedDistance.init(1.0, 0.5);
    const farther = SignedDistance.init(2.0, 0.5);

    try std.testing.expect(closer.isCloser(farther));
    try std.testing.expect(!farther.isCloser(closer));

    // Equal distance: higher orthogonality wins
    const same_dist_low = SignedDistance.init(1.0, 0.3);
    const same_dist_high = SignedDistance.init(1.0, 0.7);

    try std.testing.expect(same_dist_high.isCloser(same_dist_low));
    try std.testing.expect(!same_dist_low.isCloser(same_dist_high));
}

test "solveQuadratic - two roots" {
    var roots: [2]f64 = undefined;
    // x^2 - 5x + 6 = 0 -> (x-2)(x-3) = 0
    const n = solveQuadratic(&roots, 1, -5, 6);
    try std.testing.expectEqual(@as(u8, 2), n);
    try std.testing.expectApproxEqAbs(2.0, roots[0], 0.001);
    try std.testing.expectApproxEqAbs(3.0, roots[1], 0.001);
}

test "solveQuadratic - one root" {
    var roots: [2]f64 = undefined;
    // x^2 - 4x + 4 = 0 -> (x-2)^2 = 0
    const n = solveQuadratic(&roots, 1, -4, 4);
    try std.testing.expectEqual(@as(u8, 1), n);
    try std.testing.expectApproxEqAbs(2.0, roots[0], 0.001);
}

test "solveQuadratic - no roots" {
    var roots: [2]f64 = undefined;
    // x^2 + 1 = 0 -> no real roots
    const n = solveQuadratic(&roots, 1, 0, 1);
    try std.testing.expectEqual(@as(u8, 0), n);
}

test "solveQuadratic - linear" {
    var roots: [2]f64 = undefined;
    // 2x + 4 = 0 -> x = -2
    const n = solveQuadratic(&roots, 0, 2, 4);
    try std.testing.expectEqual(@as(u8, 1), n);
    try std.testing.expectApproxEqAbs(-2.0, roots[0], 0.001);
}

test "solveCubic - one root" {
    var roots: [3]f64 = undefined;
    // x^3 - 1 = 0 -> x = 1
    const n = solveCubic(&roots, 1, 0, 0, -1);
    try std.testing.expectEqual(@as(u8, 1), n);
    try std.testing.expectApproxEqAbs(1.0, roots[0], 0.001);
}

test "solveCubic - three roots" {
    var roots: [3]f64 = undefined;
    // x^3 - 6x^2 + 11x - 6 = 0 -> (x-1)(x-2)(x-3) = 0
    const n = solveCubic(&roots, 1, -6, 11, -6);
    try std.testing.expectEqual(@as(u8, 3), n);

    // Sort roots for comparison
    if (roots[0] > roots[1]) std.mem.swap(f64, &roots[0], &roots[1]);
    if (roots[1] > roots[2]) std.mem.swap(f64, &roots[1], &roots[2]);
    if (roots[0] > roots[1]) std.mem.swap(f64, &roots[0], &roots[1]);

    try std.testing.expectApproxEqAbs(1.0, roots[0], 0.001);
    try std.testing.expectApproxEqAbs(2.0, roots[1], 0.001);
    try std.testing.expectApproxEqAbs(3.0, roots[2], 0.001);
}
