// gizmo.zig
// Debug Drawing and Transform Handles for AgentiteZ
//
// Features:
// - Line/circle/rectangle/box primitives
// - Transform handles (translate, rotate, scale)
// - Grid overlay rendering
// - Screen-space and world-space modes
// - Batched rendering for efficiency

const std = @import("std");
const camera3d = @import("camera3d.zig");
const Vec3 = camera3d.Vec3;
const Mat4 = camera3d.Mat4;

/// Color for gizmo rendering (RGBA, 0-255)
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub const white = Color{ .r = 255, .g = 255, .b = 255 };
    pub const black = Color{ .r = 0, .g = 0, .b = 0 };
    pub const red = Color{ .r = 255, .g = 0, .b = 0 };
    pub const green = Color{ .r = 0, .g = 255, .b = 0 };
    pub const blue = Color{ .r = 0, .g = 0, .b = 255 };
    pub const yellow = Color{ .r = 255, .g = 255, .b = 0 };
    pub const cyan = Color{ .r = 0, .g = 255, .b = 255 };
    pub const magenta = Color{ .r = 255, .g = 0, .b = 255 };
    pub const orange = Color{ .r = 255, .g = 165, .b = 0 };
    pub const gray = Color{ .r = 128, .g = 128, .b = 128 };

    pub fn init(r: u8, g: u8, b: u8, a: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn withAlpha(self: Color, a: u8) Color {
        return .{ .r = self.r, .g = self.g, .b = self.b, .a = a };
    }

    /// Convert to packed ABGR format
    pub fn toABGR(self: Color) u32 {
        return (@as(u32, self.a) << 24) |
            (@as(u32, self.b) << 16) |
            (@as(u32, self.g) << 8) |
            (@as(u32, self.r));
    }

    /// Lerp between two colors
    pub fn lerp(self: Color, other: Color, t: f32) Color {
        const ti = std.math.clamp(t, 0.0, 1.0);
        return .{
            .r = @intFromFloat(@as(f32, @floatFromInt(self.r)) + (@as(f32, @floatFromInt(other.r)) - @as(f32, @floatFromInt(self.r))) * ti),
            .g = @intFromFloat(@as(f32, @floatFromInt(self.g)) + (@as(f32, @floatFromInt(other.g)) - @as(f32, @floatFromInt(self.g))) * ti),
            .b = @intFromFloat(@as(f32, @floatFromInt(self.b)) + (@as(f32, @floatFromInt(other.b)) - @as(f32, @floatFromInt(self.b))) * ti),
            .a = @intFromFloat(@as(f32, @floatFromInt(self.a)) + (@as(f32, @floatFromInt(other.a)) - @as(f32, @floatFromInt(self.a))) * ti),
        };
    }
};

/// A line segment in 3D space
pub const Line = struct {
    start: Vec3,
    end: Vec3,
    color: Color,
    thickness: f32 = 1.0,
};

/// Coordinate space for rendering
pub const Space = enum {
    /// World space - transformed by view-projection matrix
    world,
    /// Screen space - rendered directly in normalized device coordinates
    /// x, y in [-1, 1], origin at center
    screen,
};

/// Vertex for line rendering
pub const LineVertex = struct {
    x: f32,
    y: f32,
    z: f32,
    abgr: u32,

    pub fn init(pos: Vec3, color: Color) LineVertex {
        return .{
            .x = pos.x,
            .y = pos.y,
            .z = pos.z,
            .abgr = color.toABGR(),
        };
    }
};

/// Grid configuration
pub const GridConfig = struct {
    /// Size of the grid (extends from -size to +size)
    size: f32 = 100.0,
    /// Spacing between grid lines
    spacing: f32 = 1.0,
    /// Major line interval (every N lines)
    major_interval: u32 = 10,
    /// Color for minor grid lines
    minor_color: Color = Color.gray.withAlpha(64),
    /// Color for major grid lines
    major_color: Color = Color.gray.withAlpha(128),
    /// Color for X axis
    x_axis_color: Color = Color.red,
    /// Color for Z axis (Y is up)
    z_axis_color: Color = Color.blue,
    /// Whether to draw axis lines
    draw_axes: bool = true,
};

/// Transform handle axis
pub const HandleAxis = enum {
    x,
    y,
    z,
    /// XY plane (for 2D operations)
    xy,
    /// XZ plane (horizontal plane)
    xz,
    /// YZ plane
    yz,
    /// All axes (uniform scale)
    all,
    none,
};

/// Transform handle mode
pub const HandleMode = enum {
    translate,
    rotate,
    scale,
};

/// Transform handle configuration
pub const HandleConfig = struct {
    /// Size of the handle in world units
    size: f32 = 1.0,
    /// Thickness of handle lines
    thickness: f32 = 2.0,
    /// Color for X axis handle
    x_color: Color = Color.red,
    /// Color for Y axis handle
    y_color: Color = Color.green,
    /// Color for Z axis handle
    z_color: Color = Color.blue,
    /// Color when hovered
    hover_color: Color = Color.yellow,
    /// Alpha for plane handles
    plane_alpha: u8 = 64,
};

/// Gizmo renderer for debug drawing
pub const Gizmo = struct {
    allocator: std.mem.Allocator,

    /// Batched lines for world-space rendering
    world_lines: std.ArrayList(Line),
    /// Batched lines for screen-space rendering
    screen_lines: std.ArrayList(Line),

    /// Default handle configuration
    handle_config: HandleConfig,

    /// Initialize gizmo renderer
    pub fn init(allocator: std.mem.Allocator) Gizmo {
        return .{
            .allocator = allocator,
            .world_lines = .{},
            .screen_lines = .{},
            .handle_config = .{},
        };
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Gizmo) void {
        self.world_lines.deinit(self.allocator);
        self.screen_lines.deinit(self.allocator);
    }

    /// Clear all batched primitives
    pub fn clear(self: *Gizmo) void {
        self.world_lines.clearRetainingCapacity();
        self.screen_lines.clearRetainingCapacity();
    }

    // ========================================================================
    // Line Primitives
    // ========================================================================

    /// Draw a line
    pub fn drawLine(self: *Gizmo, start: Vec3, end: Vec3, color: Color, space: Space) !void {
        const line = Line{ .start = start, .end = end, .color = color };
        switch (space) {
            .world => try self.world_lines.append(self.allocator, line),
            .screen => try self.screen_lines.append(self.allocator, line),
        }
    }

    /// Draw a line with thickness
    pub fn drawLineThick(self: *Gizmo, start: Vec3, end: Vec3, color: Color, thickness: f32, space: Space) !void {
        const line = Line{ .start = start, .end = end, .color = color, .thickness = thickness };
        switch (space) {
            .world => try self.world_lines.append(self.allocator, line),
            .screen => try self.screen_lines.append(self.allocator, line),
        }
    }

    /// Draw a ray (line from origin in direction)
    pub fn drawRay(self: *Gizmo, origin: Vec3, direction: Vec3, length: f32, color: Color, space: Space) !void {
        try self.drawLine(origin, origin.add(direction.normalize().scale(length)), color, space);
    }

    /// Draw an arrow
    pub fn drawArrow(self: *Gizmo, start: Vec3, end: Vec3, color: Color, head_size: f32, space: Space) !void {
        try self.drawLine(start, end, color, space);

        // Calculate arrow head
        const dir = end.sub(start).normalize();
        const up = if (@abs(dir.y) < 0.99) Vec3.up else Vec3.right;
        const right = dir.cross(up).normalize();
        const arrow_up = right.cross(dir).normalize();

        const head_base = end.sub(dir.scale(head_size));
        const head_offset = head_size * 0.4;

        // Four arrow head lines
        try self.drawLine(end, head_base.add(right.scale(head_offset)), color, space);
        try self.drawLine(end, head_base.sub(right.scale(head_offset)), color, space);
        try self.drawLine(end, head_base.add(arrow_up.scale(head_offset)), color, space);
        try self.drawLine(end, head_base.sub(arrow_up.scale(head_offset)), color, space);
    }

    // ========================================================================
    // Shape Primitives
    // ========================================================================

    /// Draw a circle in the XZ plane (Y up)
    pub fn drawCircleXZ(self: *Gizmo, center: Vec3, radius: f32, color: Color, segments: u32, space: Space) !void {
        const seg = if (segments < 3) 16 else segments;
        const angle_step = 2.0 * std.math.pi / @as(f32, @floatFromInt(seg));

        var prev = Vec3.init(
            center.x + radius,
            center.y,
            center.z,
        );

        for (1..seg + 1) |i| {
            const angle = @as(f32, @floatFromInt(i)) * angle_step;
            const curr = Vec3.init(
                center.x + radius * @cos(angle),
                center.y,
                center.z + radius * @sin(angle),
            );
            try self.drawLine(prev, curr, color, space);
            prev = curr;
        }
    }

    /// Draw a circle in the XY plane (Z forward)
    pub fn drawCircleXY(self: *Gizmo, center: Vec3, radius: f32, color: Color, segments: u32, space: Space) !void {
        const seg = if (segments < 3) 16 else segments;
        const angle_step = 2.0 * std.math.pi / @as(f32, @floatFromInt(seg));

        var prev = Vec3.init(
            center.x + radius,
            center.y,
            center.z,
        );

        for (1..seg + 1) |i| {
            const angle = @as(f32, @floatFromInt(i)) * angle_step;
            const curr = Vec3.init(
                center.x + radius * @cos(angle),
                center.y + radius * @sin(angle),
                center.z,
            );
            try self.drawLine(prev, curr, color, space);
            prev = curr;
        }
    }

    /// Draw a circle in the YZ plane (X right)
    pub fn drawCircleYZ(self: *Gizmo, center: Vec3, radius: f32, color: Color, segments: u32, space: Space) !void {
        const seg = if (segments < 3) 16 else segments;
        const angle_step = 2.0 * std.math.pi / @as(f32, @floatFromInt(seg));

        var prev = Vec3.init(
            center.x,
            center.y + radius,
            center.z,
        );

        for (1..seg + 1) |i| {
            const angle = @as(f32, @floatFromInt(i)) * angle_step;
            const curr = Vec3.init(
                center.x,
                center.y + radius * @cos(angle),
                center.z + radius * @sin(angle),
            );
            try self.drawLine(prev, curr, color, space);
            prev = curr;
        }
    }

    /// Draw a sphere wireframe
    pub fn drawSphere(self: *Gizmo, center: Vec3, radius: f32, color: Color, segments: u32, space: Space) !void {
        try self.drawCircleXZ(center, radius, color, segments, space);
        try self.drawCircleXY(center, radius, color, segments, space);
        try self.drawCircleYZ(center, radius, color, segments, space);
    }

    /// Draw an axis-aligned bounding box
    pub fn drawAABB(self: *Gizmo, min: Vec3, max: Vec3, color: Color, space: Space) !void {
        // Bottom face
        try self.drawLine(Vec3.init(min.x, min.y, min.z), Vec3.init(max.x, min.y, min.z), color, space);
        try self.drawLine(Vec3.init(max.x, min.y, min.z), Vec3.init(max.x, min.y, max.z), color, space);
        try self.drawLine(Vec3.init(max.x, min.y, max.z), Vec3.init(min.x, min.y, max.z), color, space);
        try self.drawLine(Vec3.init(min.x, min.y, max.z), Vec3.init(min.x, min.y, min.z), color, space);

        // Top face
        try self.drawLine(Vec3.init(min.x, max.y, min.z), Vec3.init(max.x, max.y, min.z), color, space);
        try self.drawLine(Vec3.init(max.x, max.y, min.z), Vec3.init(max.x, max.y, max.z), color, space);
        try self.drawLine(Vec3.init(max.x, max.y, max.z), Vec3.init(min.x, max.y, max.z), color, space);
        try self.drawLine(Vec3.init(min.x, max.y, max.z), Vec3.init(min.x, max.y, min.z), color, space);

        // Vertical edges
        try self.drawLine(Vec3.init(min.x, min.y, min.z), Vec3.init(min.x, max.y, min.z), color, space);
        try self.drawLine(Vec3.init(max.x, min.y, min.z), Vec3.init(max.x, max.y, min.z), color, space);
        try self.drawLine(Vec3.init(max.x, min.y, max.z), Vec3.init(max.x, max.y, max.z), color, space);
        try self.drawLine(Vec3.init(min.x, min.y, max.z), Vec3.init(min.x, max.y, max.z), color, space);
    }

    /// Draw a box centered at position with given size
    pub fn drawBox(self: *Gizmo, center: Vec3, size: Vec3, color: Color, space: Space) !void {
        const half = size.scale(0.5);
        const min = center.sub(half);
        const max = center.add(half);
        try self.drawAABB(min, max, color, space);
    }

    /// Draw a 2D rectangle (in XY plane at z=0)
    pub fn drawRect(self: *Gizmo, x: f32, y: f32, width: f32, height: f32, color: Color, space: Space) !void {
        const min = Vec3.init(x, y, 0);
        const max = Vec3.init(x + width, y + height, 0);
        try self.drawLine(Vec3.init(min.x, min.y, 0), Vec3.init(max.x, min.y, 0), color, space);
        try self.drawLine(Vec3.init(max.x, min.y, 0), Vec3.init(max.x, max.y, 0), color, space);
        try self.drawLine(Vec3.init(max.x, max.y, 0), Vec3.init(min.x, max.y, 0), color, space);
        try self.drawLine(Vec3.init(min.x, max.y, 0), Vec3.init(min.x, min.y, 0), color, space);
    }

    // ========================================================================
    // Grid Overlay
    // ========================================================================

    /// Draw a grid in the XZ plane
    pub fn drawGrid(self: *Gizmo, config: GridConfig) !void {
        const half_size = config.size;
        const spacing = config.spacing;
        const major = config.major_interval;

        // Calculate number of lines
        const lines_half = @as(u32, @intFromFloat(half_size / spacing));

        // Draw grid lines parallel to X axis (varying Z)
        var i: u32 = 0;
        while (i <= lines_half * 2) : (i += 1) {
            const z = -half_size + @as(f32, @floatFromInt(i)) * spacing;
            const is_major = (i % major) == 0;
            const is_center = @abs(z) < spacing * 0.01;

            if (is_center and config.draw_axes) {
                // X axis
                try self.drawLine(
                    Vec3.init(-half_size, 0, z),
                    Vec3.init(half_size, 0, z),
                    config.x_axis_color,
                    .world,
                );
            } else {
                const color = if (is_major) config.major_color else config.minor_color;
                try self.drawLine(
                    Vec3.init(-half_size, 0, z),
                    Vec3.init(half_size, 0, z),
                    color,
                    .world,
                );
            }
        }

        // Draw grid lines parallel to Z axis (varying X)
        i = 0;
        while (i <= lines_half * 2) : (i += 1) {
            const x = -half_size + @as(f32, @floatFromInt(i)) * spacing;
            const is_major = (i % major) == 0;
            const is_center = @abs(x) < spacing * 0.01;

            if (is_center and config.draw_axes) {
                // Z axis
                try self.drawLine(
                    Vec3.init(x, 0, -half_size),
                    Vec3.init(x, 0, half_size),
                    config.z_axis_color,
                    .world,
                );
            } else {
                const color = if (is_major) config.major_color else config.minor_color;
                try self.drawLine(
                    Vec3.init(x, 0, -half_size),
                    Vec3.init(x, 0, half_size),
                    color,
                    .world,
                );
            }
        }

        // Draw Y axis if enabled
        if (config.draw_axes) {
            try self.drawLine(
                Vec3.init(0, -half_size, 0),
                Vec3.init(0, half_size, 0),
                Color.green,
                .world,
            );
        }
    }

    // ========================================================================
    // Transform Handles
    // ========================================================================

    /// Draw a translation handle (3 arrows)
    pub fn drawTranslateHandle(self: *Gizmo, position: Vec3, hovered: HandleAxis) !void {
        const cfg = self.handle_config;
        const size = cfg.size;

        // X axis arrow
        const x_color = if (hovered == .x or hovered == .xy or hovered == .xz) cfg.hover_color else cfg.x_color;
        try self.drawArrow(position, position.add(Vec3.init(size, 0, 0)), x_color, size * 0.15, .world);

        // Y axis arrow
        const y_color = if (hovered == .y or hovered == .xy or hovered == .yz) cfg.hover_color else cfg.y_color;
        try self.drawArrow(position, position.add(Vec3.init(0, size, 0)), y_color, size * 0.15, .world);

        // Z axis arrow
        const z_color = if (hovered == .z or hovered == .xz or hovered == .yz) cfg.hover_color else cfg.z_color;
        try self.drawArrow(position, position.add(Vec3.init(0, 0, size)), z_color, size * 0.15, .world);

        // XY plane handle
        const xy_offset = size * 0.3;
        const xy_color = if (hovered == .xy) cfg.hover_color.withAlpha(cfg.plane_alpha) else cfg.z_color.withAlpha(cfg.plane_alpha);
        try self.drawLine(position.add(Vec3.init(xy_offset, 0, 0)), position.add(Vec3.init(xy_offset, xy_offset, 0)), xy_color, .world);
        try self.drawLine(position.add(Vec3.init(xy_offset, xy_offset, 0)), position.add(Vec3.init(0, xy_offset, 0)), xy_color, .world);

        // XZ plane handle
        const xz_color = if (hovered == .xz) cfg.hover_color.withAlpha(cfg.plane_alpha) else cfg.y_color.withAlpha(cfg.plane_alpha);
        try self.drawLine(position.add(Vec3.init(xy_offset, 0, 0)), position.add(Vec3.init(xy_offset, 0, xy_offset)), xz_color, .world);
        try self.drawLine(position.add(Vec3.init(xy_offset, 0, xy_offset)), position.add(Vec3.init(0, 0, xy_offset)), xz_color, .world);

        // YZ plane handle
        const yz_color = if (hovered == .yz) cfg.hover_color.withAlpha(cfg.plane_alpha) else cfg.x_color.withAlpha(cfg.plane_alpha);
        try self.drawLine(position.add(Vec3.init(0, xy_offset, 0)), position.add(Vec3.init(0, xy_offset, xy_offset)), yz_color, .world);
        try self.drawLine(position.add(Vec3.init(0, xy_offset, xy_offset)), position.add(Vec3.init(0, 0, xy_offset)), yz_color, .world);
    }

    /// Draw a rotation handle (3 circles)
    pub fn drawRotateHandle(self: *Gizmo, position: Vec3, hovered: HandleAxis) !void {
        const cfg = self.handle_config;
        const size = cfg.size;
        const segments: u32 = 32;

        // X rotation (YZ plane)
        const x_color = if (hovered == .x) cfg.hover_color else cfg.x_color;
        try self.drawCircleYZ(position, size, x_color, segments, .world);

        // Y rotation (XZ plane)
        const y_color = if (hovered == .y) cfg.hover_color else cfg.y_color;
        try self.drawCircleXZ(position, size, y_color, segments, .world);

        // Z rotation (XY plane)
        const z_color = if (hovered == .z) cfg.hover_color else cfg.z_color;
        try self.drawCircleXY(position, size, z_color, segments, .world);
    }

    /// Draw a scale handle (3 lines with boxes)
    pub fn drawScaleHandle(self: *Gizmo, position: Vec3, hovered: HandleAxis) !void {
        const cfg = self.handle_config;
        const size = cfg.size;
        const box_size = size * 0.1;

        // X axis
        const x_end = position.add(Vec3.init(size, 0, 0));
        const x_color = if (hovered == .x or hovered == .all) cfg.hover_color else cfg.x_color;
        try self.drawLine(position, x_end, x_color, .world);
        try self.drawBox(x_end, Vec3.init(box_size, box_size, box_size), x_color, .world);

        // Y axis
        const y_end = position.add(Vec3.init(0, size, 0));
        const y_color = if (hovered == .y or hovered == .all) cfg.hover_color else cfg.y_color;
        try self.drawLine(position, y_end, y_color, .world);
        try self.drawBox(y_end, Vec3.init(box_size, box_size, box_size), y_color, .world);

        // Z axis
        const z_end = position.add(Vec3.init(0, 0, size));
        const z_color = if (hovered == .z or hovered == .all) cfg.hover_color else cfg.z_color;
        try self.drawLine(position, z_end, z_color, .world);
        try self.drawBox(z_end, Vec3.init(box_size, box_size, box_size), z_color, .world);

        // Center box for uniform scale
        const center_color = if (hovered == .all) cfg.hover_color else Color.white;
        try self.drawBox(position, Vec3.init(box_size * 1.5, box_size * 1.5, box_size * 1.5), center_color, .world);
    }

    /// Draw a transform handle based on mode
    pub fn drawTransformHandle(self: *Gizmo, position: Vec3, mode: HandleMode, hovered: HandleAxis) !void {
        switch (mode) {
            .translate => try self.drawTranslateHandle(position, hovered),
            .rotate => try self.drawRotateHandle(position, hovered),
            .scale => try self.drawScaleHandle(position, hovered),
        }
    }

    // ========================================================================
    // Debug Helpers
    // ========================================================================

    /// Draw coordinate axes at origin
    pub fn drawAxes(self: *Gizmo, origin: Vec3, size: f32, space: Space) !void {
        try self.drawArrow(origin, origin.add(Vec3.init(size, 0, 0)), Color.red, size * 0.1, space);
        try self.drawArrow(origin, origin.add(Vec3.init(0, size, 0)), Color.green, size * 0.1, space);
        try self.drawArrow(origin, origin.add(Vec3.init(0, 0, size)), Color.blue, size * 0.1, space);
    }

    /// Draw a frustum (for camera visualization)
    pub fn drawFrustum(self: *Gizmo, eye: Vec3, forward: Vec3, up: Vec3, fov: f32, aspect: f32, near: f32, far: f32, color: Color) !void {
        const right = forward.cross(up).normalize();
        const cam_up = right.cross(forward).normalize();

        // Calculate frustum corners
        const near_height = 2.0 * @tan(fov * 0.5) * near;
        const near_width = near_height * aspect;
        const far_height = 2.0 * @tan(fov * 0.5) * far;
        const far_width = far_height * aspect;

        const near_center = eye.add(forward.scale(near));
        const far_center = eye.add(forward.scale(far));

        // Near plane corners
        const ntl = near_center.add(cam_up.scale(near_height * 0.5)).sub(right.scale(near_width * 0.5));
        const ntr = near_center.add(cam_up.scale(near_height * 0.5)).add(right.scale(near_width * 0.5));
        const nbl = near_center.sub(cam_up.scale(near_height * 0.5)).sub(right.scale(near_width * 0.5));
        const nbr = near_center.sub(cam_up.scale(near_height * 0.5)).add(right.scale(near_width * 0.5));

        // Far plane corners
        const ftl = far_center.add(cam_up.scale(far_height * 0.5)).sub(right.scale(far_width * 0.5));
        const ftr = far_center.add(cam_up.scale(far_height * 0.5)).add(right.scale(far_width * 0.5));
        const fbl = far_center.sub(cam_up.scale(far_height * 0.5)).sub(right.scale(far_width * 0.5));
        const fbr = far_center.sub(cam_up.scale(far_height * 0.5)).add(right.scale(far_width * 0.5));

        // Near plane
        try self.drawLine(ntl, ntr, color, .world);
        try self.drawLine(ntr, nbr, color, .world);
        try self.drawLine(nbr, nbl, color, .world);
        try self.drawLine(nbl, ntl, color, .world);

        // Far plane
        try self.drawLine(ftl, ftr, color, .world);
        try self.drawLine(ftr, fbr, color, .world);
        try self.drawLine(fbr, fbl, color, .world);
        try self.drawLine(fbl, ftl, color, .world);

        // Connecting edges
        try self.drawLine(ntl, ftl, color, .world);
        try self.drawLine(ntr, ftr, color, .world);
        try self.drawLine(nbl, fbl, color, .world);
        try self.drawLine(nbr, fbr, color, .world);
    }

    /// Draw a point as a small cross
    pub fn drawPoint(self: *Gizmo, pos: Vec3, color: Color, size: f32, space: Space) !void {
        const half = size * 0.5;
        try self.drawLine(pos.sub(Vec3.init(half, 0, 0)), pos.add(Vec3.init(half, 0, 0)), color, space);
        try self.drawLine(pos.sub(Vec3.init(0, half, 0)), pos.add(Vec3.init(0, half, 0)), color, space);
        try self.drawLine(pos.sub(Vec3.init(0, 0, half)), pos.add(Vec3.init(0, 0, half)), color, space);
    }

    // ========================================================================
    // Rendering
    // ========================================================================

    /// Get all world-space lines for rendering
    pub fn getWorldLines(self: *const Gizmo) []const Line {
        return self.world_lines.items;
    }

    /// Get all screen-space lines for rendering
    pub fn getScreenLines(self: *const Gizmo) []const Line {
        return self.screen_lines.items;
    }

    /// Get total line count
    pub fn getLineCount(self: *const Gizmo) usize {
        return self.world_lines.items.len + self.screen_lines.items.len;
    }

    /// Generate vertices for rendering (transforms world lines by view-projection matrix)
    pub fn generateVertices(self: *const Gizmo, vp: Mat4, allocator: std.mem.Allocator) ![]LineVertex {
        const total_lines = self.getLineCount();
        var vertices = try allocator.alloc(LineVertex, total_lines * 2);
        var idx: usize = 0;

        // Transform world-space lines
        for (self.world_lines.items) |line| {
            const start = vp.transformPoint(line.start);
            const end = vp.transformPoint(line.end);
            vertices[idx] = LineVertex.init(start, line.color);
            vertices[idx + 1] = LineVertex.init(end, line.color);
            idx += 2;
        }

        // Screen-space lines (no transformation)
        for (self.screen_lines.items) |line| {
            vertices[idx] = LineVertex.init(line.start, line.color);
            vertices[idx + 1] = LineVertex.init(line.end, line.color);
            idx += 2;
        }

        return vertices;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Color - basic operations" {
    const c = Color.init(255, 128, 64, 200);
    try std.testing.expectEqual(@as(u8, 255), c.r);
    try std.testing.expectEqual(@as(u8, 128), c.g);
    try std.testing.expectEqual(@as(u8, 64), c.b);
    try std.testing.expectEqual(@as(u8, 200), c.a);
}

test "Color - toABGR" {
    const c = Color.init(0x12, 0x34, 0x56, 0x78);
    const abgr = c.toABGR();
    // ABGR format: A=0x78, B=0x56, G=0x34, R=0x12
    try std.testing.expectEqual(@as(u32, 0x78563412), abgr);
}

test "Color - withAlpha" {
    const c = Color.red.withAlpha(128);
    try std.testing.expectEqual(@as(u8, 255), c.r);
    try std.testing.expectEqual(@as(u8, 0), c.g);
    try std.testing.expectEqual(@as(u8, 0), c.b);
    try std.testing.expectEqual(@as(u8, 128), c.a);
}

test "Color - lerp" {
    const a = Color.init(0, 0, 0, 255);
    const b = Color.init(100, 200, 50, 255);

    const mid = a.lerp(b, 0.5);
    try std.testing.expectEqual(@as(u8, 50), mid.r);
    try std.testing.expectEqual(@as(u8, 100), mid.g);
    try std.testing.expectEqual(@as(u8, 25), mid.b);
}

test "Gizmo - init and deinit" {
    var gizmo = Gizmo.init(std.testing.allocator);
    defer gizmo.deinit();

    try std.testing.expectEqual(@as(usize, 0), gizmo.getLineCount());
}

test "Gizmo - drawLine world space" {
    var gizmo = Gizmo.init(std.testing.allocator);
    defer gizmo.deinit();

    try gizmo.drawLine(Vec3.zero, Vec3.init(1, 0, 0), Color.red, .world);

    try std.testing.expectEqual(@as(usize, 1), gizmo.world_lines.items.len);
    try std.testing.expectEqual(@as(usize, 0), gizmo.screen_lines.items.len);
}

test "Gizmo - drawLine screen space" {
    var gizmo = Gizmo.init(std.testing.allocator);
    defer gizmo.deinit();

    try gizmo.drawLine(Vec3.zero, Vec3.init(1, 0, 0), Color.red, .screen);

    try std.testing.expectEqual(@as(usize, 0), gizmo.world_lines.items.len);
    try std.testing.expectEqual(@as(usize, 1), gizmo.screen_lines.items.len);
}

test "Gizmo - clear" {
    var gizmo = Gizmo.init(std.testing.allocator);
    defer gizmo.deinit();

    try gizmo.drawLine(Vec3.zero, Vec3.init(1, 0, 0), Color.red, .world);
    try gizmo.drawLine(Vec3.zero, Vec3.init(0, 1, 0), Color.green, .screen);

    try std.testing.expectEqual(@as(usize, 2), gizmo.getLineCount());

    gizmo.clear();
    try std.testing.expectEqual(@as(usize, 0), gizmo.getLineCount());
}

test "Gizmo - drawArrow" {
    var gizmo = Gizmo.init(std.testing.allocator);
    defer gizmo.deinit();

    try gizmo.drawArrow(Vec3.zero, Vec3.init(1, 0, 0), Color.red, 0.1, .world);

    // Arrow = 1 line + 4 head lines = 5 lines
    try std.testing.expectEqual(@as(usize, 5), gizmo.world_lines.items.len);
}

test "Gizmo - drawBox" {
    var gizmo = Gizmo.init(std.testing.allocator);
    defer gizmo.deinit();

    try gizmo.drawBox(Vec3.zero, Vec3.init(1, 1, 1), Color.white, .world);

    // Box has 12 edges
    try std.testing.expectEqual(@as(usize, 12), gizmo.world_lines.items.len);
}

test "Gizmo - drawCircleXZ" {
    var gizmo = Gizmo.init(std.testing.allocator);
    defer gizmo.deinit();

    try gizmo.drawCircleXZ(Vec3.zero, 1.0, Color.white, 16, .world);

    // 16 segments = 16 lines
    try std.testing.expectEqual(@as(usize, 16), gizmo.world_lines.items.len);
}

test "Gizmo - drawSphere" {
    var gizmo = Gizmo.init(std.testing.allocator);
    defer gizmo.deinit();

    try gizmo.drawSphere(Vec3.zero, 1.0, Color.white, 16, .world);

    // 3 circles * 16 segments = 48 lines
    try std.testing.expectEqual(@as(usize, 48), gizmo.world_lines.items.len);
}

test "Gizmo - drawAxes" {
    var gizmo = Gizmo.init(std.testing.allocator);
    defer gizmo.deinit();

    try gizmo.drawAxes(Vec3.zero, 1.0, .world);

    // 3 arrows * 5 lines each = 15 lines
    try std.testing.expectEqual(@as(usize, 15), gizmo.world_lines.items.len);
}

test "Gizmo - drawTranslateHandle" {
    var gizmo = Gizmo.init(std.testing.allocator);
    defer gizmo.deinit();

    try gizmo.drawTranslateHandle(Vec3.zero, .none);

    // Should create arrows and plane handles
    try std.testing.expect(gizmo.world_lines.items.len > 0);
}

test "Gizmo - drawRotateHandle" {
    var gizmo = Gizmo.init(std.testing.allocator);
    defer gizmo.deinit();

    try gizmo.drawRotateHandle(Vec3.zero, .none);

    // Should create 3 circles
    try std.testing.expect(gizmo.world_lines.items.len > 0);
}

test "Gizmo - drawScaleHandle" {
    var gizmo = Gizmo.init(std.testing.allocator);
    defer gizmo.deinit();

    try gizmo.drawScaleHandle(Vec3.zero, .none);

    // Should create lines and boxes
    try std.testing.expect(gizmo.world_lines.items.len > 0);
}

test "Gizmo - generateVertices" {
    var gizmo = Gizmo.init(std.testing.allocator);
    defer gizmo.deinit();

    try gizmo.drawLine(Vec3.zero, Vec3.init(1, 0, 0), Color.red, .world);
    try gizmo.drawLine(Vec3.zero, Vec3.init(0, 1, 0), Color.green, .screen);

    const vp = Mat4.identity;
    const vertices = try gizmo.generateVertices(vp, std.testing.allocator);
    defer std.testing.allocator.free(vertices);

    // 2 lines * 2 vertices = 4 vertices
    try std.testing.expectEqual(@as(usize, 4), vertices.len);
}

test "Gizmo - drawGrid" {
    var gizmo = Gizmo.init(std.testing.allocator);
    defer gizmo.deinit();

    try gizmo.drawGrid(.{
        .size = 10.0,
        .spacing = 1.0,
        .major_interval = 5,
    });

    // Grid should create many lines
    try std.testing.expect(gizmo.world_lines.items.len > 0);
}

test "LineVertex - init" {
    const vertex = LineVertex.init(Vec3.init(1, 2, 3), Color.red);

    try std.testing.expectApproxEqAbs(@as(f32, 1.0), vertex.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), vertex.y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), vertex.z, 0.0001);
    try std.testing.expectEqual(Color.red.toABGR(), vertex.abgr);
}

test "Gizmo - drawPoint" {
    var gizmo = Gizmo.init(std.testing.allocator);
    defer gizmo.deinit();

    try gizmo.drawPoint(Vec3.zero, Color.white, 1.0, .world);

    // Point = 3 lines (cross)
    try std.testing.expectEqual(@as(usize, 3), gizmo.world_lines.items.len);
}

test "Gizmo - drawRect" {
    var gizmo = Gizmo.init(std.testing.allocator);
    defer gizmo.deinit();

    try gizmo.drawRect(0, 0, 100, 50, Color.white, .world);

    // Rectangle = 4 lines
    try std.testing.expectEqual(@as(usize, 4), gizmo.world_lines.items.len);
}
