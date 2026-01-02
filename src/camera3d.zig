// camera3d.zig
// 3D Camera System for AgentiteZ
//
// Features:
// - Orbital camera controls (yaw, pitch, distance)
// - Perspective projection with configurable FOV
// - Frustum culling helpers
// - Smooth interpolation and constraints
// - View/projection matrix generation for bgfx

const std = @import("std");

/// 3D Vector for camera operations
pub const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub const zero = Vec3{ .x = 0, .y = 0, .z = 0 };
    pub const up = Vec3{ .x = 0, .y = 1, .z = 0 };
    pub const forward = Vec3{ .x = 0, .y = 0, .z = -1 };
    pub const right = Vec3{ .x = 1, .y = 0, .z = 0 };

    pub fn init(x: f32, y: f32, z: f32) Vec3 {
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn add(self: Vec3, other: Vec3) Vec3 {
        return .{ .x = self.x + other.x, .y = self.y + other.y, .z = self.z + other.z };
    }

    pub fn sub(self: Vec3, other: Vec3) Vec3 {
        return .{ .x = self.x - other.x, .y = self.y - other.y, .z = self.z - other.z };
    }

    pub fn scale(self: Vec3, s: f32) Vec3 {
        return .{ .x = self.x * s, .y = self.y * s, .z = self.z * s };
    }

    pub fn negate(self: Vec3) Vec3 {
        return .{ .x = -self.x, .y = -self.y, .z = -self.z };
    }

    pub fn dot(self: Vec3, other: Vec3) f32 {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }

    pub fn cross(self: Vec3, other: Vec3) Vec3 {
        return .{
            .x = self.y * other.z - self.z * other.y,
            .y = self.z * other.x - self.x * other.z,
            .z = self.x * other.y - self.y * other.x,
        };
    }

    pub fn length(self: Vec3) f32 {
        return @sqrt(self.dot(self));
    }

    pub fn lengthSquared(self: Vec3) f32 {
        return self.dot(self);
    }

    pub fn normalize(self: Vec3) Vec3 {
        const len = self.length();
        if (len == 0) return Vec3.zero;
        return self.scale(1.0 / len);
    }

    pub fn lerp(self: Vec3, target: Vec3, t: f32) Vec3 {
        return .{
            .x = self.x + (target.x - self.x) * t,
            .y = self.y + (target.y - self.y) * t,
            .z = self.z + (target.z - self.z) * t,
        };
    }

    pub fn distance(self: Vec3, other: Vec3) f32 {
        return self.sub(other).length();
    }

    pub fn distanceSquared(self: Vec3, other: Vec3) f32 {
        return self.sub(other).lengthSquared();
    }
};

/// 4x4 Matrix in row-major order (matches bgfx convention)
/// Layout:
/// [ m[0]  m[1]  m[2]  m[3]  ]   (row 0)
/// [ m[4]  m[5]  m[6]  m[7]  ]   (row 1)
/// [ m[8]  m[9]  m[10] m[11] ]   (row 2)
/// [ m[12] m[13] m[14] m[15] ]   (row 3 - translation)
pub const Mat4 = struct {
    m: [16]f32,

    pub const identity = Mat4{
        .m = .{
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        },
    };

    /// Create perspective projection matrix (right-handed, depth [0, 1])
    /// Matches bgfx's default coordinate system
    pub fn perspective(fov_y: f32, aspect: f32, near: f32, far: f32) Mat4 {
        const tan_half_fov = @tan(fov_y * 0.5);
        const range = far - near;

        return .{
            .m = .{
                1.0 / (aspect * tan_half_fov), 0,                     0,                           0,
                0,                             1.0 / tan_half_fov,    0,                           0,
                0,                             0,                     -(far + near) / range,       -1,
                0,                             0,                     -(2.0 * far * near) / range, 0,
            },
        };
    }

    /// Create look-at view matrix (right-handed)
    pub fn lookAt(eye: Vec3, target: Vec3, world_up: Vec3) Mat4 {
        const f = target.sub(eye).normalize(); // Forward
        const s = f.cross(world_up).normalize(); // Side (right)
        const u = s.cross(f); // Up

        return .{
            .m = .{
                s.x,           u.x,           -f.x,          0,
                s.y,           u.y,           -f.y,          0,
                s.z,           u.z,           -f.z,          0,
                -s.dot(eye),   -u.dot(eye),   f.dot(eye),    1,
            },
        };
    }

    /// Create translation matrix
    pub fn translation(x: f32, y: f32, z: f32) Mat4 {
        return .{
            .m = .{
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                x, y, z, 1,
            },
        };
    }

    /// Create rotation matrix around X axis
    pub fn rotationX(angle: f32) Mat4 {
        const c = @cos(angle);
        const s = @sin(angle);
        return .{
            .m = .{
                1, 0, 0,  0,
                0, c, s,  0,
                0, -s, c, 0,
                0, 0, 0,  1,
            },
        };
    }

    /// Create rotation matrix around Y axis
    pub fn rotationY(angle: f32) Mat4 {
        const c = @cos(angle);
        const s = @sin(angle);
        return .{
            .m = .{
                c,  0, s, 0,
                0,  1, 0, 0,
                -s, 0, c, 0,
                0,  0, 0, 1,
            },
        };
    }

    /// Create rotation matrix around Z axis
    pub fn rotationZ(angle: f32) Mat4 {
        const c = @cos(angle);
        const s = @sin(angle);
        return .{
            .m = .{
                c,  s, 0, 0,
                -s, c, 0, 0,
                0,  0, 1, 0,
                0,  0, 0, 1,
            },
        };
    }

    /// Create scale matrix
    pub fn scaling(sx: f32, sy: f32, sz: f32) Mat4 {
        return .{
            .m = .{
                sx, 0,  0,  0,
                0,  sy, 0,  0,
                0,  0,  sz, 0,
                0,  0,  0,  1,
            },
        };
    }

    /// Matrix multiplication: self * other
    pub fn mul(self: Mat4, other: Mat4) Mat4 {
        var result: Mat4 = undefined;
        inline for (0..4) |row| {
            inline for (0..4) |col| {
                var sum: f32 = 0;
                inline for (0..4) |k| {
                    sum += self.m[row * 4 + k] * other.m[k * 4 + col];
                }
                result.m[row * 4 + col] = sum;
            }
        }
        return result;
    }

    /// Transform a point (w=1) by this matrix
    pub fn transformPoint(self: Mat4, p: Vec3) Vec3 {
        const x = self.m[0] * p.x + self.m[4] * p.y + self.m[8] * p.z + self.m[12];
        const y = self.m[1] * p.x + self.m[5] * p.y + self.m[9] * p.z + self.m[13];
        const z = self.m[2] * p.x + self.m[6] * p.y + self.m[10] * p.z + self.m[14];
        const w = self.m[3] * p.x + self.m[7] * p.y + self.m[11] * p.z + self.m[15];
        if (w != 0 and w != 1) {
            return Vec3.init(x / w, y / w, z / w);
        }
        return Vec3.init(x, y, z);
    }

    /// Transform a direction (w=0) by this matrix
    pub fn transformDirection(self: Mat4, d: Vec3) Vec3 {
        return Vec3.init(
            self.m[0] * d.x + self.m[4] * d.y + self.m[8] * d.z,
            self.m[1] * d.x + self.m[5] * d.y + self.m[9] * d.z,
            self.m[2] * d.x + self.m[6] * d.y + self.m[10] * d.z,
        );
    }

    /// Get raw array pointer for bgfx
    pub fn ptr(self: *const Mat4) *const [16]f32 {
        return &self.m;
    }
};

/// Frustum plane representation (ax + by + cz + d = 0)
pub const Plane = struct {
    normal: Vec3,
    d: f32,

    /// Create plane from normal and point on plane
    pub fn fromNormalAndPoint(normal: Vec3, point: Vec3) Plane {
        const n = normal.normalize();
        return .{
            .normal = n,
            .d = -n.dot(point),
        };
    }

    /// Distance from point to plane (positive = in front, negative = behind)
    pub fn distanceToPoint(self: Plane, point: Vec3) f32 {
        return self.normal.dot(point) + self.d;
    }

    /// Normalize the plane equation
    pub fn normalize(self: Plane) Plane {
        const len = self.normal.length();
        if (len == 0) return self;
        return .{
            .normal = self.normal.scale(1.0 / len),
            .d = self.d / len,
        };
    }
};

/// Frustum for culling (6 planes: left, right, bottom, top, near, far)
pub const Frustum = struct {
    planes: [6]Plane,

    pub const PlaneIndex = enum(usize) {
        left = 0,
        right = 1,
        bottom = 2,
        top = 3,
        near = 4,
        far = 5,
    };

    /// Extract frustum planes from view-projection matrix
    /// Uses the Gribb/Hartmann method
    pub fn fromViewProjection(vp: Mat4) Frustum {
        var frustum: Frustum = undefined;

        // Left plane: row3 + row0
        frustum.planes[0] = (Plane{
            .normal = Vec3.init(
                vp.m[3] + vp.m[0],
                vp.m[7] + vp.m[4],
                vp.m[11] + vp.m[8],
            ),
            .d = vp.m[15] + vp.m[12],
        }).normalize();

        // Right plane: row3 - row0
        frustum.planes[1] = (Plane{
            .normal = Vec3.init(
                vp.m[3] - vp.m[0],
                vp.m[7] - vp.m[4],
                vp.m[11] - vp.m[8],
            ),
            .d = vp.m[15] - vp.m[12],
        }).normalize();

        // Bottom plane: row3 + row1
        frustum.planes[2] = (Plane{
            .normal = Vec3.init(
                vp.m[3] + vp.m[1],
                vp.m[7] + vp.m[5],
                vp.m[11] + vp.m[9],
            ),
            .d = vp.m[15] + vp.m[13],
        }).normalize();

        // Top plane: row3 - row1
        frustum.planes[3] = (Plane{
            .normal = Vec3.init(
                vp.m[3] - vp.m[1],
                vp.m[7] - vp.m[5],
                vp.m[11] - vp.m[9],
            ),
            .d = vp.m[15] - vp.m[13],
        }).normalize();

        // Near plane: row3 + row2
        frustum.planes[4] = (Plane{
            .normal = Vec3.init(
                vp.m[3] + vp.m[2],
                vp.m[7] + vp.m[6],
                vp.m[11] + vp.m[10],
            ),
            .d = vp.m[15] + vp.m[14],
        }).normalize();

        // Far plane: row3 - row2
        frustum.planes[5] = (Plane{
            .normal = Vec3.init(
                vp.m[3] - vp.m[2],
                vp.m[7] - vp.m[6],
                vp.m[11] - vp.m[10],
            ),
            .d = vp.m[15] - vp.m[14],
        }).normalize();

        return frustum;
    }

    /// Test if a point is inside the frustum
    pub fn containsPoint(self: Frustum, point: Vec3) bool {
        for (self.planes) |plane| {
            if (plane.distanceToPoint(point) < 0) {
                return false;
            }
        }
        return true;
    }

    /// Test if a sphere intersects the frustum
    pub fn intersectsSphere(self: Frustum, center: Vec3, radius: f32) bool {
        for (self.planes) |plane| {
            if (plane.distanceToPoint(center) < -radius) {
                return false;
            }
        }
        return true;
    }

    /// Test if an axis-aligned bounding box intersects the frustum
    pub fn intersectsAABB(self: Frustum, min: Vec3, max: Vec3) bool {
        for (self.planes) |plane| {
            // Find the positive vertex (furthest along plane normal)
            const p = Vec3.init(
                if (plane.normal.x >= 0) max.x else min.x,
                if (plane.normal.y >= 0) max.y else min.y,
                if (plane.normal.z >= 0) max.z else min.z,
            );

            // If positive vertex is behind plane, AABB is outside
            if (plane.distanceToPoint(p) < 0) {
                return false;
            }
        }
        return true;
    }
};

/// Orbital camera constraints
pub const OrbitalConstraints = struct {
    /// Minimum pitch angle in radians (default: -89 degrees, almost straight down)
    min_pitch: f32 = -std.math.pi / 2.0 + 0.02,
    /// Maximum pitch angle in radians (default: 89 degrees, almost straight up)
    max_pitch: f32 = std.math.pi / 2.0 - 0.02,
    /// Minimum distance from target
    min_distance: f32 = 0.1,
    /// Maximum distance from target
    max_distance: f32 = 1000.0,
    /// Minimum yaw angle (null = unconstrained)
    min_yaw: ?f32 = null,
    /// Maximum yaw angle (null = unconstrained)
    max_yaw: ?f32 = null,
};

/// Smooth interpolation settings
pub const SmoothingConfig = struct {
    /// Smoothing factor for position (0 = instant, higher = slower)
    position_smoothing: f32 = 0.1,
    /// Smoothing factor for rotation (0 = instant, higher = slower)
    rotation_smoothing: f32 = 0.1,
    /// Smoothing factor for zoom/distance (0 = instant, higher = slower)
    zoom_smoothing: f32 = 0.1,
};

/// 3D Camera with orbital controls and perspective projection
pub const Camera3D = struct {
    // Orbital camera state
    /// Target point the camera orbits around
    target: Vec3,
    /// Yaw angle (horizontal rotation around Y axis) in radians
    yaw: f32,
    /// Pitch angle (vertical rotation) in radians
    pitch: f32,
    /// Distance from target
    distance: f32,

    // Target values for smooth interpolation
    target_yaw: f32,
    target_pitch: f32,
    target_distance: f32,
    target_target: Vec3,

    // Perspective projection settings
    /// Field of view (vertical) in radians
    fov: f32,
    /// Aspect ratio (width / height)
    aspect: f32,
    /// Near clipping plane distance
    near: f32,
    /// Far clipping plane distance
    far: f32,

    // Constraints
    constraints: OrbitalConstraints,

    // Smoothing
    smoothing: SmoothingConfig,

    // Cached matrices (recalculated when needed)
    cached_view: Mat4,
    cached_projection: Mat4,
    cached_view_projection: Mat4,
    cache_dirty: bool,

    /// Create a new orbital camera
    pub fn init(config: struct {
        target: Vec3 = Vec3.zero,
        yaw: f32 = 0,
        pitch: f32 = 0,
        distance: f32 = 10.0,
        fov: f32 = std.math.pi / 4.0, // 45 degrees
        aspect: f32 = 16.0 / 9.0,
        near: f32 = 0.1,
        far: f32 = 1000.0,
    }) Camera3D {
        return .{
            .target = config.target,
            .yaw = config.yaw,
            .pitch = config.pitch,
            .distance = config.distance,
            .target_yaw = config.yaw,
            .target_pitch = config.pitch,
            .target_distance = config.distance,
            .target_target = config.target,
            .fov = config.fov,
            .aspect = config.aspect,
            .near = config.near,
            .far = config.far,
            .constraints = .{},
            .smoothing = .{},
            .cached_view = Mat4.identity,
            .cached_projection = Mat4.identity,
            .cached_view_projection = Mat4.identity,
            .cache_dirty = true,
        };
    }

    /// Calculate camera position from orbital parameters
    pub fn getPosition(self: *const Camera3D) Vec3 {
        const cos_pitch = @cos(self.pitch);
        return Vec3.init(
            self.target.x + self.distance * cos_pitch * @sin(self.yaw),
            self.target.y + self.distance * @sin(self.pitch),
            self.target.z + self.distance * cos_pitch * @cos(self.yaw),
        );
    }

    /// Get the forward direction the camera is looking
    pub fn getForward(self: *const Camera3D) Vec3 {
        return self.target.sub(self.getPosition()).normalize();
    }

    /// Get the right direction relative to camera
    pub fn getRight(self: *const Camera3D) Vec3 {
        return self.getForward().cross(Vec3.up).normalize();
    }

    /// Get the up direction relative to camera
    pub fn getUp(self: *const Camera3D) Vec3 {
        return self.getRight().cross(self.getForward()).normalize();
    }

    /// Set orbital target with smooth interpolation
    pub fn setTarget(self: *Camera3D, new_target: Vec3) void {
        self.target_target = new_target;
        self.cache_dirty = true;
    }

    /// Set orbital target immediately (no interpolation)
    pub fn setTargetImmediate(self: *Camera3D, new_target: Vec3) void {
        self.target = new_target;
        self.target_target = new_target;
        self.cache_dirty = true;
    }

    /// Set yaw angle (horizontal rotation) with smooth interpolation
    pub fn setYaw(self: *Camera3D, new_yaw: f32) void {
        self.target_yaw = self.applyYawConstraints(new_yaw);
        self.cache_dirty = true;
    }

    /// Set yaw immediately (no interpolation)
    pub fn setYawImmediate(self: *Camera3D, new_yaw: f32) void {
        const constrained = self.applyYawConstraints(new_yaw);
        self.yaw = constrained;
        self.target_yaw = constrained;
        self.cache_dirty = true;
    }

    /// Adjust yaw by delta with smooth interpolation
    pub fn rotateYaw(self: *Camera3D, delta: f32) void {
        self.setYaw(self.target_yaw + delta);
    }

    /// Set pitch angle (vertical rotation) with smooth interpolation
    pub fn setPitch(self: *Camera3D, new_pitch: f32) void {
        self.target_pitch = std.math.clamp(new_pitch, self.constraints.min_pitch, self.constraints.max_pitch);
        self.cache_dirty = true;
    }

    /// Set pitch immediately (no interpolation)
    pub fn setPitchImmediate(self: *Camera3D, new_pitch: f32) void {
        const constrained = std.math.clamp(new_pitch, self.constraints.min_pitch, self.constraints.max_pitch);
        self.pitch = constrained;
        self.target_pitch = constrained;
        self.cache_dirty = true;
    }

    /// Adjust pitch by delta with smooth interpolation
    pub fn rotatePitch(self: *Camera3D, delta: f32) void {
        self.setPitch(self.target_pitch + delta);
    }

    /// Set distance from target with smooth interpolation
    pub fn setDistance(self: *Camera3D, new_distance: f32) void {
        self.target_distance = std.math.clamp(new_distance, self.constraints.min_distance, self.constraints.max_distance);
        self.cache_dirty = true;
    }

    /// Set distance immediately (no interpolation)
    pub fn setDistanceImmediate(self: *Camera3D, new_distance: f32) void {
        const constrained = std.math.clamp(new_distance, self.constraints.min_distance, self.constraints.max_distance);
        self.distance = constrained;
        self.target_distance = constrained;
        self.cache_dirty = true;
    }

    /// Adjust distance by delta (positive = zoom out, negative = zoom in)
    pub fn zoom(self: *Camera3D, delta: f32) void {
        self.setDistance(self.target_distance + delta);
    }

    /// Multiply distance by factor (useful for scroll wheel zoom)
    pub fn zoomMultiply(self: *Camera3D, factor: f32) void {
        self.setDistance(self.target_distance * factor);
    }

    /// Set field of view in radians
    pub fn setFOV(self: *Camera3D, new_fov: f32) void {
        self.fov = std.math.clamp(new_fov, 0.1, std.math.pi - 0.1);
        self.cache_dirty = true;
    }

    /// Set field of view in degrees
    pub fn setFOVDegrees(self: *Camera3D, degrees: f32) void {
        self.setFOV(degrees * std.math.pi / 180.0);
    }

    /// Set aspect ratio
    pub fn setAspect(self: *Camera3D, new_aspect: f32) void {
        self.aspect = new_aspect;
        self.cache_dirty = true;
    }

    /// Set near/far clipping planes
    pub fn setClipPlanes(self: *Camera3D, near: f32, far: f32) void {
        self.near = near;
        self.far = far;
        self.cache_dirty = true;
    }

    /// Set orbital constraints
    pub fn setConstraints(self: *Camera3D, constraints: OrbitalConstraints) void {
        self.constraints = constraints;
        // Apply constraints to current values
        self.target_pitch = std.math.clamp(self.target_pitch, constraints.min_pitch, constraints.max_pitch);
        self.target_distance = std.math.clamp(self.target_distance, constraints.min_distance, constraints.max_distance);
        self.target_yaw = self.applyYawConstraints(self.target_yaw);
        self.cache_dirty = true;
    }

    /// Set smoothing configuration
    pub fn setSmoothing(self: *Camera3D, smoothing: SmoothingConfig) void {
        self.smoothing = smoothing;
    }

    /// Disable smoothing (instant camera response)
    pub fn disableSmoothing(self: *Camera3D) void {
        self.smoothing = .{
            .position_smoothing = 0,
            .rotation_smoothing = 0,
            .zoom_smoothing = 0,
        };
    }

    /// Update camera (call once per frame)
    pub fn update(self: *Camera3D, delta_time: f32) void {
        const needs_update = self.yaw != self.target_yaw or
            self.pitch != self.target_pitch or
            self.distance != self.target_distance or
            self.target.x != self.target_target.x or
            self.target.y != self.target_target.y or
            self.target.z != self.target_target.z;

        if (!needs_update) return;

        // Frame-rate independent interpolation
        const rot_t = if (self.smoothing.rotation_smoothing > 0)
            1.0 - std.math.pow(f32, 1.0 - self.smoothing.rotation_smoothing, delta_time * 60.0)
        else
            1.0;

        const zoom_t = if (self.smoothing.zoom_smoothing > 0)
            1.0 - std.math.pow(f32, 1.0 - self.smoothing.zoom_smoothing, delta_time * 60.0)
        else
            1.0;

        const pos_t = if (self.smoothing.position_smoothing > 0)
            1.0 - std.math.pow(f32, 1.0 - self.smoothing.position_smoothing, delta_time * 60.0)
        else
            1.0;

        // Interpolate angles (handle wrapping for yaw)
        self.yaw = lerpAngle(self.yaw, self.target_yaw, rot_t);
        self.pitch = self.pitch + (self.target_pitch - self.pitch) * rot_t;
        self.distance = self.distance + (self.target_distance - self.distance) * zoom_t;
        self.target = self.target.lerp(self.target_target, pos_t);

        // Snap to target if very close
        if (@abs(self.yaw - self.target_yaw) < 0.0001) self.yaw = self.target_yaw;
        if (@abs(self.pitch - self.target_pitch) < 0.0001) self.pitch = self.target_pitch;
        if (@abs(self.distance - self.target_distance) < 0.0001) self.distance = self.target_distance;
        if (self.target.distance(self.target_target) < 0.0001) self.target = self.target_target;

        self.cache_dirty = true;
    }

    /// Get the view matrix
    pub fn getViewMatrix(self: *Camera3D) Mat4 {
        if (self.cache_dirty) {
            self.recalculateMatrices();
        }
        return self.cached_view;
    }

    /// Get the projection matrix
    pub fn getProjectionMatrix(self: *Camera3D) Mat4 {
        if (self.cache_dirty) {
            self.recalculateMatrices();
        }
        return self.cached_projection;
    }

    /// Get the combined view-projection matrix
    pub fn getViewProjectionMatrix(self: *Camera3D) Mat4 {
        if (self.cache_dirty) {
            self.recalculateMatrices();
        }
        return self.cached_view_projection;
    }

    /// Get frustum for culling
    pub fn getFrustum(self: *Camera3D) Frustum {
        return Frustum.fromViewProjection(self.getViewProjectionMatrix());
    }

    /// Test if a point is visible
    pub fn isPointVisible(self: *Camera3D, point: Vec3) bool {
        return self.getFrustum().containsPoint(point);
    }

    /// Test if a sphere is visible
    pub fn isSphereVisible(self: *Camera3D, center: Vec3, radius: f32) bool {
        return self.getFrustum().intersectsSphere(center, radius);
    }

    /// Test if an AABB is visible
    pub fn isAABBVisible(self: *Camera3D, min: Vec3, max: Vec3) bool {
        return self.getFrustum().intersectsAABB(min, max);
    }

    /// Convert world position to screen position (normalized device coordinates)
    /// Returns (x, y, depth) where x,y are in [-1, 1] and depth is [0, 1]
    /// Returns null if the point is behind the camera
    pub fn worldToScreen(self: *Camera3D, world_pos: Vec3) ?struct { x: f32, y: f32, depth: f32 } {
        const vp = self.getViewProjectionMatrix();
        const clip = vp.transformPoint(world_pos);

        // Check if behind camera (in clip space, w < 0 means behind)
        const w = vp.m[3] * world_pos.x + vp.m[7] * world_pos.y + vp.m[11] * world_pos.z + vp.m[15];
        if (w <= 0) return null;

        return .{
            .x = clip.x,
            .y = clip.y,
            .depth = (clip.z + 1.0) * 0.5, // Convert from [-1,1] to [0,1]
        };
    }

    /// Convert screen position to world ray
    /// screen_x, screen_y are normalized device coordinates in [-1, 1]
    /// Returns origin and direction of the ray
    pub fn screenToWorldRay(self: *Camera3D, screen_x: f32, screen_y: f32) struct { origin: Vec3, direction: Vec3 } {
        const pos = self.getPosition();
        const fwd = self.getForward();
        const rgt = self.getRight();
        const up_vec = self.getUp();

        // Calculate the half-dimensions of the near plane
        const half_height = @tan(self.fov * 0.5) * self.near;
        const half_width = half_height * self.aspect;

        // Calculate direction to the point on near plane
        const direction = fwd.scale(self.near)
            .add(rgt.scale(screen_x * half_width))
            .add(up_vec.scale(screen_y * half_height))
            .normalize();

        return .{
            .origin = pos,
            .direction = direction,
        };
    }

    // Internal helpers

    fn applyYawConstraints(self: *const Camera3D, yaw: f32) f32 {
        if (self.constraints.min_yaw) |min| {
            if (self.constraints.max_yaw) |max| {
                return std.math.clamp(yaw, min, max);
            }
        }
        return yaw;
    }

    fn recalculateMatrices(self: *Camera3D) void {
        const eye = self.getPosition();
        self.cached_view = Mat4.lookAt(eye, self.target, Vec3.up);
        self.cached_projection = Mat4.perspective(self.fov, self.aspect, self.near, self.far);
        self.cached_view_projection = self.cached_view.mul(self.cached_projection);
        self.cache_dirty = false;
    }
};

/// Interpolate between two angles, taking the shortest path
fn lerpAngle(from: f32, to: f32, t: f32) f32 {
    var diff = to - from;

    // Wrap difference to [-π, π]
    while (diff > std.math.pi) diff -= 2.0 * std.math.pi;
    while (diff < -std.math.pi) diff += 2.0 * std.math.pi;

    return from + diff * t;
}

// ============================================================================
// Tests
// ============================================================================

test "Vec3 - basic operations" {
    const a = Vec3.init(1.0, 2.0, 3.0);
    const b = Vec3.init(4.0, 5.0, 6.0);

    // Add
    const sum = a.add(b);
    try std.testing.expectApproxEqRel(@as(f32, 5.0), sum.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 7.0), sum.y, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 9.0), sum.z, 0.0001);

    // Sub
    const diff = b.sub(a);
    try std.testing.expectApproxEqRel(@as(f32, 3.0), diff.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 3.0), diff.y, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 3.0), diff.z, 0.0001);

    // Scale
    const scaled = a.scale(2.0);
    try std.testing.expectApproxEqRel(@as(f32, 2.0), scaled.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 4.0), scaled.y, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 6.0), scaled.z, 0.0001);
}

test "Vec3 - dot and cross product" {
    const a = Vec3.init(1.0, 0.0, 0.0);
    const b = Vec3.init(0.0, 1.0, 0.0);

    // Dot product
    try std.testing.expectApproxEqRel(@as(f32, 0.0), a.dot(b), 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 1.0), a.dot(a), 0.0001);

    // Cross product (x cross y = z)
    const c = a.cross(b);
    try std.testing.expectApproxEqRel(@as(f32, 0.0), c.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 0.0), c.y, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 1.0), c.z, 0.0001);
}

test "Vec3 - length and normalize" {
    const v = Vec3.init(3.0, 4.0, 0.0);

    try std.testing.expectApproxEqRel(@as(f32, 5.0), v.length(), 0.0001);

    const norm = v.normalize();
    try std.testing.expectApproxEqRel(@as(f32, 1.0), norm.length(), 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 0.6), norm.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 0.8), norm.y, 0.0001);

    // Normalizing zero should return zero
    const zero_norm = Vec3.zero.normalize();
    try std.testing.expectEqual(@as(f32, 0.0), zero_norm.x);
    try std.testing.expectEqual(@as(f32, 0.0), zero_norm.y);
    try std.testing.expectEqual(@as(f32, 0.0), zero_norm.z);
}

test "Vec3 - lerp" {
    const a = Vec3.init(0.0, 0.0, 0.0);
    const b = Vec3.init(10.0, 20.0, 30.0);

    const mid = a.lerp(b, 0.5);
    try std.testing.expectApproxEqRel(@as(f32, 5.0), mid.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 10.0), mid.y, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 15.0), mid.z, 0.0001);
}

test "Mat4 - identity" {
    const m = Mat4.identity;
    const v = Vec3.init(1.0, 2.0, 3.0);

    const result = m.transformPoint(v);
    try std.testing.expectApproxEqRel(v.x, result.x, 0.0001);
    try std.testing.expectApproxEqRel(v.y, result.y, 0.0001);
    try std.testing.expectApproxEqRel(v.z, result.z, 0.0001);
}

test "Mat4 - translation" {
    const m = Mat4.translation(10.0, 20.0, 30.0);
    const v = Vec3.init(1.0, 2.0, 3.0);

    const result = m.transformPoint(v);
    try std.testing.expectApproxEqRel(@as(f32, 11.0), result.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 22.0), result.y, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 33.0), result.z, 0.0001);
}

test "Mat4 - rotation Y" {
    const m = Mat4.rotationY(std.math.pi / 2.0); // 90 degrees
    const v = Vec3.init(1.0, 0.0, 0.0);

    const result = m.transformPoint(v);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), result.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), result.y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), result.z, 0.0001);
}

test "Mat4 - multiplication" {
    const t = Mat4.translation(5.0, 0.0, 0.0);
    const s = Mat4.scaling(2.0, 2.0, 2.0);

    // Translation then scale
    const ts = t.mul(s);
    const v = Vec3.init(1.0, 0.0, 0.0);

    const result = ts.transformPoint(v);
    // First translate (1+5=6), then scale (6*2=12)
    try std.testing.expectApproxEqRel(@as(f32, 12.0), result.x, 0.0001);
}

test "Mat4 - perspective projection" {
    const proj = Mat4.perspective(std.math.pi / 4.0, 16.0 / 9.0, 0.1, 100.0);

    // A point at the center of near plane should map to center
    const near_center = Vec3.init(0.0, 0.0, -0.1);
    const result = proj.transformPoint(near_center);

    // Should be near 0,0 in x,y (center of screen)
    try std.testing.expectApproxEqRel(@as(f32, 0.0), result.x, 0.01);
    try std.testing.expectApproxEqRel(@as(f32, 0.0), result.y, 0.01);
}

test "Mat4 - lookAt" {
    const view = Mat4.lookAt(
        Vec3.init(0.0, 0.0, 10.0), // eye
        Vec3.zero, // target
        Vec3.up, // up
    );

    // Origin should transform to (0, 0, -10) in view space
    const result = view.transformPoint(Vec3.zero);
    try std.testing.expectApproxEqRel(@as(f32, 0.0), result.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 0.0), result.y, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, -10.0), result.z, 0.0001);
}

test "Plane - distance to point" {
    // XY plane at origin, normal pointing up (+Y)
    const plane = Plane{ .normal = Vec3.up, .d = 0 };

    try std.testing.expectApproxEqRel(@as(f32, 5.0), plane.distanceToPoint(Vec3.init(0, 5, 0)), 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, -3.0), plane.distanceToPoint(Vec3.init(0, -3, 0)), 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 0.0), plane.distanceToPoint(Vec3.init(100, 0, -50)), 0.0001);
}

test "Frustum - point containment" {
    var camera = Camera3D.init(.{
        .distance = 10.0,
        .fov = std.math.pi / 4.0,
        .aspect = 1.0,
        .near = 1.0,
        .far = 100.0,
    });

    const frustum = camera.getFrustum();

    // Point at target (center of frustum) should be visible
    try std.testing.expect(frustum.containsPoint(Vec3.zero));

    // Point far behind camera should not be visible
    try std.testing.expect(!frustum.containsPoint(Vec3.init(0, 0, 50)));

    // Point far to the side should not be visible
    try std.testing.expect(!frustum.containsPoint(Vec3.init(1000, 0, 0)));
}

test "Frustum - sphere intersection" {
    var camera = Camera3D.init(.{
        .distance = 10.0,
        .fov = std.math.pi / 4.0,
        .aspect = 1.0,
        .near = 1.0,
        .far = 100.0,
    });

    const frustum = camera.getFrustum();

    // Large sphere at origin should intersect
    try std.testing.expect(frustum.intersectsSphere(Vec3.zero, 5.0));

    // Small sphere far behind camera should not intersect
    try std.testing.expect(!frustum.intersectsSphere(Vec3.init(0, 0, 100), 1.0));
}

test "Camera3D - initialization" {
    const camera = Camera3D.init(.{
        .target = Vec3.init(1.0, 2.0, 3.0),
        .yaw = std.math.pi / 4.0,
        .pitch = std.math.pi / 6.0,
        .distance = 20.0,
    });

    try std.testing.expectApproxEqRel(@as(f32, 1.0), camera.target.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 2.0), camera.target.y, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 3.0), camera.target.z, 0.0001);
    try std.testing.expectApproxEqRel(std.math.pi / 4.0, camera.yaw, 0.0001);
    try std.testing.expectApproxEqRel(std.math.pi / 6.0, camera.pitch, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 20.0), camera.distance, 0.0001);
}

test "Camera3D - position calculation" {
    // Camera at yaw=0, pitch=0, distance=10 looking at origin
    const camera = Camera3D.init(.{
        .target = Vec3.zero,
        .yaw = 0,
        .pitch = 0,
        .distance = 10.0,
    });

    const pos = camera.getPosition();

    // With yaw=0, pitch=0, camera should be at (0, 0, 10)
    try std.testing.expectApproxEqRel(@as(f32, 0.0), pos.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 0.0), pos.y, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 10.0), pos.z, 0.0001);
}

test "Camera3D - position with yaw" {
    const camera = Camera3D.init(.{
        .target = Vec3.zero,
        .yaw = std.math.pi / 2.0, // 90 degrees
        .pitch = 0,
        .distance = 10.0,
    });

    const pos = camera.getPosition();

    // With yaw=90°, camera should be at (10, 0, 0)
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), pos.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), pos.y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), pos.z, 0.0001);
}

test "Camera3D - position with pitch" {
    const camera = Camera3D.init(.{
        .target = Vec3.zero,
        .yaw = 0,
        .pitch = std.math.pi / 2.0, // 90 degrees (looking down)
        .distance = 10.0,
    });

    const pos = camera.getPosition();

    // With pitch=90°, camera should be at (0, 10, 0)
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), pos.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), pos.y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), pos.z, 0.0001);
}

test "Camera3D - pitch constraints" {
    var camera = Camera3D.init(.{});

    camera.setPitchImmediate(std.math.pi); // Try to set pitch to 180°
    // Should be clamped to max (default ~89°)
    try std.testing.expect(camera.pitch < std.math.pi / 2.0);

    camera.setPitchImmediate(-std.math.pi); // Try to set pitch to -180°
    // Should be clamped to min (default ~-89°)
    try std.testing.expect(camera.pitch > -std.math.pi / 2.0);
}

test "Camera3D - distance constraints" {
    var camera = Camera3D.init(.{ .distance = 10.0 });
    camera.setConstraints(.{
        .min_distance = 5.0,
        .max_distance = 50.0,
        .min_pitch = -std.math.pi / 2.0 + 0.02,
        .max_pitch = std.math.pi / 2.0 - 0.02,
    });

    camera.setDistanceImmediate(1.0); // Below min
    try std.testing.expectApproxEqRel(@as(f32, 5.0), camera.distance, 0.0001);

    camera.setDistanceImmediate(100.0); // Above max
    try std.testing.expectApproxEqRel(@as(f32, 50.0), camera.distance, 0.0001);

    camera.setDistanceImmediate(20.0); // Within range
    try std.testing.expectApproxEqRel(@as(f32, 20.0), camera.distance, 0.0001);
}

test "Camera3D - zoom functions" {
    var camera = Camera3D.init(.{ .distance = 10.0 });
    camera.disableSmoothing();

    camera.zoom(5.0);
    camera.update(0.016);
    try std.testing.expectApproxEqRel(@as(f32, 15.0), camera.distance, 0.0001);

    camera.zoomMultiply(0.5);
    camera.update(0.016);
    try std.testing.expectApproxEqRel(@as(f32, 7.5), camera.distance, 0.0001);
}

test "Camera3D - view matrix generation" {
    var camera = Camera3D.init(.{
        .target = Vec3.zero,
        .yaw = 0,
        .pitch = 0,
        .distance = 10.0,
    });

    const view = camera.getViewMatrix();

    // Transform origin should give us view-space position of origin
    // Origin is at the target, which the camera is looking at from (0,0,10)
    const origin_in_view = view.transformPoint(Vec3.zero);
    try std.testing.expectApproxEqRel(@as(f32, 0.0), origin_in_view.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 0.0), origin_in_view.y, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, -10.0), origin_in_view.z, 0.0001);
}

test "Camera3D - smooth interpolation" {
    var camera = Camera3D.init(.{
        .yaw = 0,
        .pitch = 0,
        .distance = 10.0,
    });
    camera.setSmoothing(.{
        .rotation_smoothing = 0.5,
        .zoom_smoothing = 0.5,
        .position_smoothing = 0.5,
    });

    // Set target values
    camera.setYaw(std.math.pi);
    camera.setDistance(20.0);

    // Update - should move towards target
    camera.update(0.016);

    // Should have moved but not reached target
    try std.testing.expect(camera.yaw > 0);
    try std.testing.expect(camera.yaw < std.math.pi);
    try std.testing.expect(camera.distance > 10.0);
    try std.testing.expect(camera.distance < 20.0);
}

test "Camera3D - FOV setting" {
    var camera = Camera3D.init(.{});

    camera.setFOVDegrees(60.0);
    try std.testing.expectApproxEqRel(60.0 * std.math.pi / 180.0, camera.fov, 0.0001);

    // Test clamping
    camera.setFOV(0.0);
    try std.testing.expect(camera.fov >= 0.1);

    camera.setFOV(std.math.pi);
    try std.testing.expect(camera.fov < std.math.pi);
}

test "lerpAngle - basic interpolation" {
    // Simple case
    const result = lerpAngle(0.0, std.math.pi / 2.0, 0.5);
    try std.testing.expectApproxEqRel(std.math.pi / 4.0, result, 0.0001);
}

test "lerpAngle - wrapping" {
    // From 350° to 10° should go the short way (through 0°)
    const from = 350.0 * std.math.pi / 180.0;
    const to = 10.0 * std.math.pi / 180.0;

    const result = lerpAngle(from, to, 0.5);

    // Should be near 0° (or 360°)
    const result_deg = result * 180.0 / std.math.pi;
    // Normalize to [0, 360)
    var normalized = @mod(result_deg, 360.0);
    if (normalized < 0) normalized += 360.0;

    // Should be either near 0 or near 360
    const near_zero = normalized < 10.0 or normalized > 350.0;
    try std.testing.expect(near_zero);
}
