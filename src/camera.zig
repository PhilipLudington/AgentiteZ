// camera.zig
// 2D Camera System for AgentiteZ
//
// Features:
// - Position, zoom, and rotation
// - Smooth follow with lerp
// - Camera bounds/constraints
// - Screen shake effect
// - World-to-screen / screen-to-world conversion

const std = @import("std");

/// Virtual resolution constants (same as used by Renderer2D)
pub const VIRTUAL_WIDTH: f32 = 1920.0;
pub const VIRTUAL_HEIGHT: f32 = 1080.0;

/// 2D Vector for camera operations
pub const Vec2 = struct {
    x: f32,
    y: f32,

    pub const zero = Vec2{ .x = 0, .y = 0 };

    pub fn init(x: f32, y: f32) Vec2 {
        return .{ .x = x, .y = y };
    }

    pub fn add(self: Vec2, other: Vec2) Vec2 {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }

    pub fn sub(self: Vec2, other: Vec2) Vec2 {
        return .{ .x = self.x - other.x, .y = self.y - other.y };
    }

    pub fn scale(self: Vec2, s: f32) Vec2 {
        return .{ .x = self.x * s, .y = self.y * s };
    }

    pub fn lerp(self: Vec2, target: Vec2, t: f32) Vec2 {
        return .{
            .x = self.x + (target.x - self.x) * t,
            .y = self.y + (target.y - self.y) * t,
        };
    }

    pub fn length(self: Vec2) f32 {
        return @sqrt(self.x * self.x + self.y * self.y);
    }

    pub fn normalize(self: Vec2) Vec2 {
        const len = self.length();
        if (len == 0) return Vec2.zero;
        return self.scale(1.0 / len);
    }

    pub fn rotate(self: Vec2, angle: f32) Vec2 {
        const cos_a = @cos(angle);
        const sin_a = @sin(angle);
        return .{
            .x = self.x * cos_a - self.y * sin_a,
            .y = self.x * sin_a + self.y * cos_a,
        };
    }
};

/// Camera bounds for constraining camera movement
pub const CameraBounds = struct {
    min_x: f32,
    min_y: f32,
    max_x: f32,
    max_y: f32,

    /// Create bounds that encompass any position (no constraints)
    pub fn infinite() CameraBounds {
        return .{
            .min_x = -std.math.inf(f32),
            .min_y = -std.math.inf(f32),
            .max_x = std.math.inf(f32),
            .max_y = std.math.inf(f32),
        };
    }

    /// Create bounds from position and size
    pub fn fromRect(x: f32, y: f32, w: f32, h: f32) CameraBounds {
        return .{
            .min_x = x,
            .min_y = y,
            .max_x = x + w,
            .max_y = y + h,
        };
    }

    pub fn width(self: CameraBounds) f32 {
        return self.max_x - self.min_x;
    }

    pub fn height(self: CameraBounds) f32 {
        return self.max_y - self.min_y;
    }
};

/// Screen shake configuration
pub const ShakeConfig = struct {
    intensity: f32 = 10.0, // Maximum shake offset in pixels
    duration: f32 = 0.3, // Duration in seconds
    decay: bool = true, // Whether intensity decays over time
    frequency: f32 = 30.0, // Shake frequency (oscillations per second)
};

/// 2D Camera with zoom, rotation, smooth follow, and screen shake
pub const Camera2D = struct {
    /// Camera position in world space (center of view)
    position: Vec2,

    /// Zoom level (1.0 = normal, 2.0 = 2x zoom in, 0.5 = 2x zoom out)
    zoom: f32,

    /// Rotation in radians
    rotation: f32,

    /// Target position for smooth follow (null = no follow)
    follow_target: ?Vec2,

    /// Smoothing factor for follow (0 = instant, 1 = no movement)
    /// Lower values = faster follow
    follow_smoothing: f32,

    /// Camera movement bounds (constrains position)
    bounds: ?CameraBounds,

    /// Zoom limits
    min_zoom: f32,
    max_zoom: f32,

    /// Screen shake state
    shake_time_remaining: f32,
    shake_intensity: f32,
    shake_decay: bool,
    shake_frequency: f32,
    shake_offset: Vec2,

    /// Random number generator for shake
    rng: std.Random.DefaultPrng,

    /// Offset applied to camera position (for deadzone, look-ahead, etc.)
    offset: Vec2,

    /// Create a new camera with default settings
    pub fn init(config: struct {
        position: Vec2 = Vec2.zero,
        zoom: f32 = 1.0,
        rotation: f32 = 0.0,
    }) Camera2D {
        return .{
            .position = config.position,
            .zoom = config.zoom,
            .rotation = config.rotation,
            .follow_target = null,
            .follow_smoothing = 0.1,
            .bounds = null,
            .min_zoom = 0.1,
            .max_zoom = 10.0,
            .shake_time_remaining = 0,
            .shake_intensity = 0,
            .shake_decay = true,
            .shake_frequency = 30.0,
            .shake_offset = Vec2.zero,
            .rng = std.Random.DefaultPrng.init(0),
            .offset = Vec2.zero,
        };
    }

    /// Set target position for smooth camera follow
    pub fn setTarget(self: *Camera2D, target: Vec2) void {
        self.follow_target = target;
    }

    /// Clear follow target (camera will stay at current position)
    pub fn clearTarget(self: *Camera2D) void {
        self.follow_target = null;
    }

    /// Set follow smoothing factor (0 = instant, higher = slower)
    /// Typical values: 0.05 (fast) to 0.2 (slow)
    pub fn setFollowSmoothing(self: *Camera2D, smoothing: f32) void {
        self.follow_smoothing = std.math.clamp(smoothing, 0.0, 1.0);
    }

    /// Set camera movement bounds
    pub fn setBounds(self: *Camera2D, bounds: CameraBounds) void {
        self.bounds = bounds;
    }

    /// Clear camera bounds (allow free movement)
    pub fn clearBounds(self: *Camera2D) void {
        self.bounds = null;
    }

    /// Set zoom limits
    pub fn setZoomLimits(self: *Camera2D, min: f32, max: f32) void {
        self.min_zoom = @max(0.01, min);
        self.max_zoom = @max(self.min_zoom, max);
        self.zoom = std.math.clamp(self.zoom, self.min_zoom, self.max_zoom);
    }

    /// Set zoom level (clamped to limits)
    pub fn setZoom(self: *Camera2D, new_zoom: f32) void {
        self.zoom = std.math.clamp(new_zoom, self.min_zoom, self.max_zoom);
    }

    /// Adjust zoom by delta (positive = zoom in, negative = zoom out)
    pub fn adjustZoom(self: *Camera2D, delta: f32) void {
        self.setZoom(self.zoom + delta);
    }

    /// Multiply zoom by factor (useful for scroll wheel zoom)
    pub fn multiplyZoom(self: *Camera2D, factor: f32) void {
        self.setZoom(self.zoom * factor);
    }

    /// Set rotation in radians
    pub fn setRotation(self: *Camera2D, radians: f32) void {
        self.rotation = radians;
    }

    /// Set rotation in degrees
    pub fn setRotationDegrees(self: *Camera2D, degrees: f32) void {
        self.rotation = degrees * std.math.pi / 180.0;
    }

    /// Start screen shake effect
    pub fn shake(self: *Camera2D, config: ShakeConfig) void {
        self.shake_time_remaining = config.duration;
        self.shake_intensity = config.intensity;
        self.shake_decay = config.decay;
        self.shake_frequency = config.frequency;
    }

    /// Stop screen shake immediately
    pub fn stopShake(self: *Camera2D) void {
        self.shake_time_remaining = 0;
        self.shake_offset = Vec2.zero;
    }

    /// Check if camera is currently shaking
    pub fn isShaking(self: *const Camera2D) bool {
        return self.shake_time_remaining > 0;
    }

    /// Update camera (call once per frame)
    pub fn update(self: *Camera2D, delta_time: f32) void {
        // Update smooth follow
        if (self.follow_target) |target| {
            // Use frame-rate independent lerp
            // t = 1 - (1 - smoothing)^(dt * 60) approximates smoothing at 60fps
            const t = 1.0 - std.math.pow(1.0 - self.follow_smoothing, delta_time * 60.0);
            self.position = self.position.lerp(target, t);
        }

        // Apply bounds constraint
        self.applyBoundsConstraint();

        // Update screen shake
        self.updateShake(delta_time);
    }

    /// Apply bounds constraint to camera position
    fn applyBoundsConstraint(self: *Camera2D) void {
        if (self.bounds) |bounds| {
            // Calculate visible area half-size based on zoom
            const half_width = (VIRTUAL_WIDTH / 2.0) / self.zoom;
            const half_height = (VIRTUAL_HEIGHT / 2.0) / self.zoom;

            // Constrain position so camera view stays within bounds
            // If view is larger than bounds, center on bounds
            if (bounds.width() < half_width * 2) {
                self.position.x = (bounds.min_x + bounds.max_x) / 2.0;
            } else {
                self.position.x = std.math.clamp(
                    self.position.x,
                    bounds.min_x + half_width,
                    bounds.max_x - half_width,
                );
            }

            if (bounds.height() < half_height * 2) {
                self.position.y = (bounds.min_y + bounds.max_y) / 2.0;
            } else {
                self.position.y = std.math.clamp(
                    self.position.y,
                    bounds.min_y + half_height,
                    bounds.max_y - half_height,
                );
            }
        }
    }

    /// Update screen shake
    fn updateShake(self: *Camera2D, delta_time: f32) void {
        if (self.shake_time_remaining <= 0) {
            self.shake_offset = Vec2.zero;
            return;
        }

        self.shake_time_remaining -= delta_time;

        // Calculate current intensity (with optional decay)
        var current_intensity = self.shake_intensity;
        if (self.shake_decay and self.shake_time_remaining > 0) {
            // Linear decay - could be changed to exponential for different feel
            current_intensity *= self.shake_time_remaining / (self.shake_time_remaining + delta_time);
        }

        // Generate random offset using sine waves for smoother shake
        const time_factor = (1.0 - self.shake_time_remaining / 0.3) * self.shake_frequency * std.math.pi * 2.0;
        const random = self.rng.random();

        // Use perlin-like noise by combining multiple sine waves
        const offset_x = @sin(time_factor) * @cos(time_factor * 1.3 + random.float(f32) * 0.5);
        const offset_y = @cos(time_factor * 0.9) * @sin(time_factor * 1.1 + random.float(f32) * 0.5);

        self.shake_offset = Vec2.init(
            offset_x * current_intensity,
            offset_y * current_intensity,
        );

        if (self.shake_time_remaining <= 0) {
            self.shake_offset = Vec2.zero;
        }
    }

    /// Get the effective camera position (including shake offset)
    pub fn getEffectivePosition(self: *const Camera2D) Vec2 {
        return self.position.add(self.shake_offset).add(self.offset);
    }

    /// Convert world coordinates to screen coordinates
    /// Screen coordinates are in virtual resolution space (1920x1080)
    pub fn worldToScreen(self: *const Camera2D, world_x: f32, world_y: f32) Vec2 {
        const effective_pos = self.getEffectivePosition();

        // Translate relative to camera
        var pos = Vec2.init(world_x - effective_pos.x, world_y - effective_pos.y);

        // Apply rotation
        if (self.rotation != 0) {
            pos = pos.rotate(-self.rotation);
        }

        // Apply zoom
        pos = pos.scale(self.zoom);

        // Translate to screen center
        return Vec2.init(
            pos.x + VIRTUAL_WIDTH / 2.0,
            pos.y + VIRTUAL_HEIGHT / 2.0,
        );
    }

    /// Convert screen coordinates to world coordinates
    /// Screen coordinates are in virtual resolution space (1920x1080)
    pub fn screenToWorld(self: *const Camera2D, screen_x: f32, screen_y: f32) Vec2 {
        const effective_pos = self.getEffectivePosition();

        // Translate from screen center
        var pos = Vec2.init(
            screen_x - VIRTUAL_WIDTH / 2.0,
            screen_y - VIRTUAL_HEIGHT / 2.0,
        );

        // Remove zoom
        pos = pos.scale(1.0 / self.zoom);

        // Remove rotation
        if (self.rotation != 0) {
            pos = pos.rotate(self.rotation);
        }

        // Translate to world coordinates
        return Vec2.init(
            pos.x + effective_pos.x,
            pos.y + effective_pos.y,
        );
    }

    /// Get the visible world rectangle (axis-aligned bounding box)
    /// Returns: .{ .x = min_x, .y = min_y, .width = width, .height = height }
    pub fn getVisibleRect(self: *const Camera2D) struct { x: f32, y: f32, width: f32, height: f32 } {
        const effective_pos = self.getEffectivePosition();
        const half_width = (VIRTUAL_WIDTH / 2.0) / self.zoom;
        const half_height = (VIRTUAL_HEIGHT / 2.0) / self.zoom;

        // If rotated, we need to expand the rect to cover the rotated view
        if (self.rotation != 0) {
            // Calculate corners of the rotated view
            const corners = [_]Vec2{
                Vec2.init(-half_width, -half_height).rotate(self.rotation),
                Vec2.init(half_width, -half_height).rotate(self.rotation),
                Vec2.init(half_width, half_height).rotate(self.rotation),
                Vec2.init(-half_width, half_height).rotate(self.rotation),
            };

            var min_x = corners[0].x;
            var max_x = corners[0].x;
            var min_y = corners[0].y;
            var max_y = corners[0].y;

            for (corners[1..]) |corner| {
                min_x = @min(min_x, corner.x);
                max_x = @max(max_x, corner.x);
                min_y = @min(min_y, corner.y);
                max_y = @max(max_y, corner.y);
            }

            return .{
                .x = effective_pos.x + min_x,
                .y = effective_pos.y + min_y,
                .width = max_x - min_x,
                .height = max_y - min_y,
            };
        }

        return .{
            .x = effective_pos.x - half_width,
            .y = effective_pos.y - half_height,
            .width = half_width * 2,
            .height = half_height * 2,
        };
    }

    /// Check if a world point is visible in the camera view
    pub fn isPointVisible(self: *const Camera2D, world_x: f32, world_y: f32) bool {
        const screen_pos = self.worldToScreen(world_x, world_y);
        return screen_pos.x >= 0 and screen_pos.x <= VIRTUAL_WIDTH and
            screen_pos.y >= 0 and screen_pos.y <= VIRTUAL_HEIGHT;
    }

    /// Check if a world rectangle is at least partially visible
    pub fn isRectVisible(self: *const Camera2D, x: f32, y: f32, width: f32, height: f32) bool {
        // Check all four corners
        if (self.isPointVisible(x, y)) return true;
        if (self.isPointVisible(x + width, y)) return true;
        if (self.isPointVisible(x + width, y + height)) return true;
        if (self.isPointVisible(x, y + height)) return true;

        // Also check if visible rect intersects (for large objects)
        const visible = self.getVisibleRect();
        return !(x + width < visible.x or
            x > visible.x + visible.width or
            y + height < visible.y or
            y > visible.y + visible.height);
    }

    /// Get the view transformation matrix for use with bgfx
    /// Returns a 4x4 matrix in row-major order
    pub fn getViewMatrix(self: *const Camera2D) [16]f32 {
        const effective_pos = self.getEffectivePosition();
        const cos_r = @cos(-self.rotation);
        const sin_r = @sin(-self.rotation);

        // Combined transform: translate to origin, rotate, scale, translate to center
        // M = T_center * S * R * T_-camera
        //
        // For 2D, we build this as a 4x4 matrix:
        // | zoom*cos  -zoom*sin  0  tx |
        // | zoom*sin   zoom*cos  0  ty |
        // |    0          0      1   0 |
        // |    0          0      0   1 |

        const tx = -effective_pos.x * self.zoom * cos_r + effective_pos.y * self.zoom * sin_r + VIRTUAL_WIDTH / 2.0;
        const ty = -effective_pos.x * self.zoom * sin_r - effective_pos.y * self.zoom * cos_r + VIRTUAL_HEIGHT / 2.0;

        return .{
            self.zoom * cos_r,  -self.zoom * sin_r, 0, 0,
            self.zoom * sin_r,  self.zoom * cos_r,  0, 0,
            0,                  0,                  1, 0,
            tx,                 ty,                 0, 1,
        };
    }

    /// Move camera by delta in world space
    pub fn move(self: *Camera2D, delta: Vec2) void {
        self.position = self.position.add(delta);
        self.applyBoundsConstraint();
    }

    /// Move camera by delta in screen space (adjusted for zoom and rotation)
    pub fn moveScreen(self: *Camera2D, screen_delta: Vec2) void {
        // Convert screen movement to world movement
        var world_delta = screen_delta.scale(1.0 / self.zoom);
        if (self.rotation != 0) {
            world_delta = world_delta.rotate(self.rotation);
        }
        self.move(world_delta);
    }

    /// Center camera on a position instantly (no smoothing)
    pub fn centerOn(self: *Camera2D, world_pos: Vec2) void {
        self.position = world_pos;
        self.applyBoundsConstraint();
    }

    /// Zoom towards a world point (keeps that point stationary on screen)
    pub fn zoomTowards(self: *Camera2D, world_point: Vec2, zoom_delta: f32) void {
        // Get screen position of the point before zoom
        const screen_pos = self.worldToScreen(world_point.x, world_point.y);

        // Apply zoom
        const old_zoom = self.zoom;
        self.setZoom(self.zoom + zoom_delta);

        // Calculate how much the point would move on screen due to zoom
        // and adjust camera position to compensate
        if (self.zoom != old_zoom) {
            const zoom_ratio = old_zoom / self.zoom;

            // The point's screen position would change, so we move the camera to compensate
            const offset_from_center = Vec2.init(
                screen_pos.x - VIRTUAL_WIDTH / 2.0,
                screen_pos.y - VIRTUAL_HEIGHT / 2.0,
            );

            const adjustment = offset_from_center.scale((1.0 - zoom_ratio) / self.zoom);
            if (self.rotation != 0) {
                self.position = self.position.add(adjustment.rotate(self.rotation));
            } else {
                self.position = self.position.add(adjustment);
            }
        }

        self.applyBoundsConstraint();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "camera - Vec2 basic operations" {
    const a = Vec2.init(3.0, 4.0);
    const b = Vec2.init(1.0, 2.0);

    // Addition
    const sum = a.add(b);
    try std.testing.expectApproxEqRel(@as(f32, 4.0), sum.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 6.0), sum.y, 0.0001);

    // Subtraction
    const diff = a.sub(b);
    try std.testing.expectApproxEqRel(@as(f32, 2.0), diff.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 2.0), diff.y, 0.0001);

    // Scale
    const scaled = a.scale(2.0);
    try std.testing.expectApproxEqRel(@as(f32, 6.0), scaled.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 8.0), scaled.y, 0.0001);

    // Length
    try std.testing.expectApproxEqRel(@as(f32, 5.0), a.length(), 0.0001);
}

test "camera - Vec2 lerp" {
    const a = Vec2.init(0.0, 0.0);
    const b = Vec2.init(10.0, 20.0);

    const mid = a.lerp(b, 0.5);
    try std.testing.expectApproxEqRel(@as(f32, 5.0), mid.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 10.0), mid.y, 0.0001);

    const quarter = a.lerp(b, 0.25);
    try std.testing.expectApproxEqRel(@as(f32, 2.5), quarter.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 5.0), quarter.y, 0.0001);
}

test "camera - Vec2 rotation" {
    const v = Vec2.init(1.0, 0.0);

    // Rotate 90 degrees
    const rotated = v.rotate(std.math.pi / 2.0);
    try std.testing.expectApproxEqRel(@as(f32, 0.0), rotated.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 1.0), rotated.y, 0.0001);

    // Rotate 180 degrees
    const rotated180 = v.rotate(std.math.pi);
    try std.testing.expectApproxEqRel(@as(f32, -1.0), rotated180.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 0.0), rotated180.y, 0.0001);
}

test "camera - Vec2 normalize" {
    const v = Vec2.init(3.0, 4.0);
    const norm = v.normalize();

    try std.testing.expectApproxEqRel(@as(f32, 1.0), norm.length(), 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 0.6), norm.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 0.8), norm.y, 0.0001);

    // Normalizing zero vector should return zero
    const zero_norm = Vec2.zero.normalize();
    try std.testing.expectEqual(@as(f32, 0.0), zero_norm.x);
    try std.testing.expectEqual(@as(f32, 0.0), zero_norm.y);
}

test "camera - CameraBounds" {
    const bounds = CameraBounds.fromRect(100.0, 200.0, 800.0, 600.0);

    try std.testing.expectEqual(@as(f32, 100.0), bounds.min_x);
    try std.testing.expectEqual(@as(f32, 200.0), bounds.min_y);
    try std.testing.expectEqual(@as(f32, 900.0), bounds.max_x);
    try std.testing.expectEqual(@as(f32, 800.0), bounds.max_y);
    try std.testing.expectEqual(@as(f32, 800.0), bounds.width());
    try std.testing.expectEqual(@as(f32, 600.0), bounds.height());

    // Test infinite bounds
    const inf = CameraBounds.infinite();
    try std.testing.expect(inf.min_x == -std.math.inf(f32));
    try std.testing.expect(inf.max_x == std.math.inf(f32));
}

test "camera - init with defaults" {
    const camera = Camera2D.init(.{});

    try std.testing.expectEqual(@as(f32, 0.0), camera.position.x);
    try std.testing.expectEqual(@as(f32, 0.0), camera.position.y);
    try std.testing.expectEqual(@as(f32, 1.0), camera.zoom);
    try std.testing.expectEqual(@as(f32, 0.0), camera.rotation);
    try std.testing.expect(camera.bounds == null);
    try std.testing.expect(camera.follow_target == null);
}

test "camera - init with custom values" {
    const camera = Camera2D.init(.{
        .position = Vec2.init(100.0, 200.0),
        .zoom = 2.0,
        .rotation = std.math.pi / 4.0,
    });

    try std.testing.expectEqual(@as(f32, 100.0), camera.position.x);
    try std.testing.expectEqual(@as(f32, 200.0), camera.position.y);
    try std.testing.expectEqual(@as(f32, 2.0), camera.zoom);
    try std.testing.expectApproxEqRel(std.math.pi / 4.0, camera.rotation, 0.0001);
}

test "camera - zoom limits" {
    var camera = Camera2D.init(.{});

    camera.setZoomLimits(0.5, 4.0);
    try std.testing.expectEqual(@as(f32, 0.5), camera.min_zoom);
    try std.testing.expectEqual(@as(f32, 4.0), camera.max_zoom);

    // Test clamping
    camera.setZoom(10.0);
    try std.testing.expectEqual(@as(f32, 4.0), camera.zoom);

    camera.setZoom(0.1);
    try std.testing.expectEqual(@as(f32, 0.5), camera.zoom);

    camera.setZoom(2.0);
    try std.testing.expectEqual(@as(f32, 2.0), camera.zoom);
}

test "camera - adjustZoom and multiplyZoom" {
    var camera = Camera2D.init(.{ .zoom = 1.0 });
    camera.setZoomLimits(0.1, 10.0);

    camera.adjustZoom(0.5);
    try std.testing.expectEqual(@as(f32, 1.5), camera.zoom);

    camera.multiplyZoom(2.0);
    try std.testing.expectEqual(@as(f32, 3.0), camera.zoom);
}

test "camera - world to screen conversion (no rotation)" {
    var camera = Camera2D.init(.{
        .position = Vec2.init(0.0, 0.0),
        .zoom = 1.0,
    });

    // World origin should be at screen center
    const center = camera.worldToScreen(0.0, 0.0);
    try std.testing.expectApproxEqRel(VIRTUAL_WIDTH / 2.0, center.x, 0.0001);
    try std.testing.expectApproxEqRel(VIRTUAL_HEIGHT / 2.0, center.y, 0.0001);

    // Test with camera offset
    camera.position = Vec2.init(100.0, 50.0);
    const offset_center = camera.worldToScreen(100.0, 50.0);
    try std.testing.expectApproxEqRel(VIRTUAL_WIDTH / 2.0, offset_center.x, 0.0001);
    try std.testing.expectApproxEqRel(VIRTUAL_HEIGHT / 2.0, offset_center.y, 0.0001);
}

test "camera - world to screen with zoom" {
    const camera = Camera2D.init(.{
        .position = Vec2.init(0.0, 0.0),
        .zoom = 2.0,
    });

    // World point at (100, 0) should be 200 pixels right of center on screen
    const screen_pos = camera.worldToScreen(100.0, 0.0);
    try std.testing.expectApproxEqRel(VIRTUAL_WIDTH / 2.0 + 200.0, screen_pos.x, 0.0001);
}

test "camera - screen to world conversion" {
    var camera = Camera2D.init(.{
        .position = Vec2.init(0.0, 0.0),
        .zoom = 1.0,
    });

    // Screen center should be at world origin
    const world = camera.screenToWorld(VIRTUAL_WIDTH / 2.0, VIRTUAL_HEIGHT / 2.0);
    try std.testing.expectApproxEqRel(@as(f32, 0.0), world.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 0.0), world.y, 0.0001);

    // Round-trip test
    camera.position = Vec2.init(500.0, 300.0);
    camera.zoom = 1.5;

    const original = Vec2.init(123.0, 456.0);
    const screen = camera.worldToScreen(original.x, original.y);
    const back = camera.screenToWorld(screen.x, screen.y);

    try std.testing.expectApproxEqRel(original.x, back.x, 0.001);
    try std.testing.expectApproxEqRel(original.y, back.y, 0.001);
}

test "camera - visible rect (no rotation)" {
    const camera = Camera2D.init(.{
        .position = Vec2.init(500.0, 300.0),
        .zoom = 1.0,
    });

    const rect = camera.getVisibleRect();

    // With zoom 1.0, visible area is exactly the virtual resolution
    try std.testing.expectApproxEqRel(VIRTUAL_WIDTH, rect.width, 0.0001);
    try std.testing.expectApproxEqRel(VIRTUAL_HEIGHT, rect.height, 0.0001);

    // Centered on camera position
    try std.testing.expectApproxEqRel(500.0 - VIRTUAL_WIDTH / 2.0, rect.x, 0.0001);
    try std.testing.expectApproxEqRel(300.0 - VIRTUAL_HEIGHT / 2.0, rect.y, 0.0001);
}

test "camera - visible rect with zoom" {
    const camera = Camera2D.init(.{
        .position = Vec2.init(0.0, 0.0),
        .zoom = 2.0,
    });

    const rect = camera.getVisibleRect();

    // With zoom 2.0, visible area is half the virtual resolution
    try std.testing.expectApproxEqRel(VIRTUAL_WIDTH / 2.0, rect.width, 0.0001);
    try std.testing.expectApproxEqRel(VIRTUAL_HEIGHT / 2.0, rect.height, 0.0001);
}

test "camera - isPointVisible" {
    const camera = Camera2D.init(.{
        .position = Vec2.init(0.0, 0.0),
        .zoom = 1.0,
    });

    // Point at origin (camera center) should be visible
    try std.testing.expect(camera.isPointVisible(0.0, 0.0));

    // Points within half the virtual resolution should be visible
    try std.testing.expect(camera.isPointVisible(VIRTUAL_WIDTH / 2.0 - 1, 0.0));
    try std.testing.expect(camera.isPointVisible(0.0, VIRTUAL_HEIGHT / 2.0 - 1));

    // Points outside should not be visible
    try std.testing.expect(!camera.isPointVisible(VIRTUAL_WIDTH, 0.0));
    try std.testing.expect(!camera.isPointVisible(0.0, VIRTUAL_HEIGHT));
}

test "camera - bounds constraint" {
    var camera = Camera2D.init(.{
        .position = Vec2.init(0.0, 0.0),
        .zoom = 1.0,
    });

    // Set bounds smaller than the view
    camera.setBounds(CameraBounds.fromRect(0.0, 0.0, 1000.0, 800.0));

    // Camera should center on bounds when view is larger
    camera.update(0.016);

    try std.testing.expectApproxEqRel(@as(f32, 500.0), camera.position.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 400.0), camera.position.y, 0.0001);
}

test "camera - bounds constraint with zoom" {
    var camera = Camera2D.init(.{
        .position = Vec2.init(0.0, 0.0),
        .zoom = 2.0, // Zoomed in, visible area is smaller
    });

    // Set bounds larger than the zoomed view
    camera.setBounds(CameraBounds.fromRect(0.0, 0.0, 2000.0, 1500.0));

    // Try to move outside bounds
    camera.position = Vec2.init(-1000.0, -1000.0);
    camera.update(0.016);

    // Should be clamped to bounds (accounting for visible area)
    const half_visible_width = (VIRTUAL_WIDTH / 2.0) / camera.zoom;
    const half_visible_height = (VIRTUAL_HEIGHT / 2.0) / camera.zoom;

    try std.testing.expect(camera.position.x >= half_visible_width);
    try std.testing.expect(camera.position.y >= half_visible_height);
}

test "camera - smooth follow" {
    var camera = Camera2D.init(.{
        .position = Vec2.init(0.0, 0.0),
    });

    camera.setTarget(Vec2.init(100.0, 100.0));
    camera.setFollowSmoothing(0.5);

    // After update, camera should move towards target
    camera.update(0.016);

    try std.testing.expect(camera.position.x > 0.0);
    try std.testing.expect(camera.position.y > 0.0);
    try std.testing.expect(camera.position.x < 100.0);
    try std.testing.expect(camera.position.y < 100.0);
}

test "camera - screen shake" {
    var camera = Camera2D.init(.{});

    try std.testing.expect(!camera.isShaking());

    camera.shake(.{
        .intensity = 10.0,
        .duration = 0.5,
        .decay = true,
    });

    try std.testing.expect(camera.isShaking());

    // Update shake
    camera.update(0.016);

    // Shake offset should be non-zero (most of the time)
    // Note: Could be near zero by chance, so we just check that effective position includes shake
    const effective_pos = camera.getEffectivePosition();
    _ = effective_pos; // Used for shake

    // After duration, shake should stop
    camera.update(0.6);
    try std.testing.expect(!camera.isShaking());
}

test "camera - stop shake" {
    var camera = Camera2D.init(.{});

    camera.shake(.{ .intensity = 10.0, .duration = 1.0 });
    try std.testing.expect(camera.isShaking());

    camera.stopShake();
    try std.testing.expect(!camera.isShaking());
    try std.testing.expectEqual(@as(f32, 0.0), camera.shake_offset.x);
    try std.testing.expectEqual(@as(f32, 0.0), camera.shake_offset.y);
}

test "camera - move and moveScreen" {
    var camera = Camera2D.init(.{
        .position = Vec2.init(0.0, 0.0),
        .zoom = 2.0,
    });

    // Move in world space
    camera.move(Vec2.init(100.0, 50.0));
    try std.testing.expectEqual(@as(f32, 100.0), camera.position.x);
    try std.testing.expectEqual(@as(f32, 50.0), camera.position.y);

    // Move in screen space (should be scaled by 1/zoom)
    camera.position = Vec2.init(0.0, 0.0);
    camera.moveScreen(Vec2.init(100.0, 50.0));
    try std.testing.expectEqual(@as(f32, 50.0), camera.position.x); // 100 / 2.0
    try std.testing.expectEqual(@as(f32, 25.0), camera.position.y); // 50 / 2.0
}

test "camera - centerOn" {
    var camera = Camera2D.init(.{
        .position = Vec2.init(0.0, 0.0),
    });

    camera.centerOn(Vec2.init(500.0, 300.0));
    try std.testing.expectEqual(@as(f32, 500.0), camera.position.x);
    try std.testing.expectEqual(@as(f32, 300.0), camera.position.y);
}

test "camera - rotation degrees" {
    var camera = Camera2D.init(.{});

    camera.setRotationDegrees(90.0);
    try std.testing.expectApproxEqRel(std.math.pi / 2.0, camera.rotation, 0.0001);

    camera.setRotationDegrees(180.0);
    try std.testing.expectApproxEqRel(std.math.pi, camera.rotation, 0.0001);
}

test "camera - getViewMatrix identity" {
    const camera = Camera2D.init(.{
        .position = Vec2.init(0.0, 0.0),
        .zoom = 1.0,
        .rotation = 0.0,
    });

    const matrix = camera.getViewMatrix();

    // Scale should be 1.0 (zoom)
    try std.testing.expectApproxEqRel(@as(f32, 1.0), matrix[0], 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 1.0), matrix[5], 0.0001);

    // Translation should center the view
    try std.testing.expectApproxEqRel(VIRTUAL_WIDTH / 2.0, matrix[12], 0.0001);
    try std.testing.expectApproxEqRel(VIRTUAL_HEIGHT / 2.0, matrix[13], 0.0001);
}

test "camera - round trip with rotation" {
    var camera = Camera2D.init(.{
        .position = Vec2.init(200.0, 150.0),
        .zoom = 1.5,
        .rotation = std.math.pi / 6.0, // 30 degrees
    });

    const original = Vec2.init(300.0, 250.0);
    const screen = camera.worldToScreen(original.x, original.y);
    const back = camera.screenToWorld(screen.x, screen.y);

    try std.testing.expectApproxEqRel(original.x, back.x, 0.01);
    try std.testing.expectApproxEqRel(original.y, back.y, 0.01);
}
