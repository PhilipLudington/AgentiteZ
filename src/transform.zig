// transform.zig
// Transform Component System for AgentiteZ
//
// Features:
// - Position, rotation, scale components
// - Parent-child transform hierarchy
// - Local vs world coordinate transforms
// - Transform dirty flag optimization
// - Automatic world transform propagation

const std = @import("std");
const ecs = @import("ecs.zig");
const Entity = ecs.Entity;

// ============================================================================
// Math Types
// ============================================================================

/// 2D Vector for transform operations
pub const Vec2 = struct {
    x: f32,
    y: f32,

    pub const zero = Vec2{ .x = 0, .y = 0 };
    pub const one = Vec2{ .x = 1, .y = 1 };

    pub fn init(x: f32, y: f32) Vec2 {
        return .{ .x = x, .y = y };
    }

    pub fn add(self: Vec2, other: Vec2) Vec2 {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }

    pub fn sub(self: Vec2, other: Vec2) Vec2 {
        return .{ .x = self.x - other.x, .y = self.y - other.y };
    }

    pub fn mul(self: Vec2, other: Vec2) Vec2 {
        return .{ .x = self.x * other.x, .y = self.y * other.y };
    }

    pub fn scale(self: Vec2, s: f32) Vec2 {
        return .{ .x = self.x * s, .y = self.y * s };
    }

    pub fn length(self: Vec2) f32 {
        return @sqrt(self.x * self.x + self.y * self.y);
    }

    pub fn lengthSquared(self: Vec2) f32 {
        return self.x * self.x + self.y * self.y;
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

    pub fn lerp(self: Vec2, target: Vec2, t: f32) Vec2 {
        return .{
            .x = self.x + (target.x - self.x) * t,
            .y = self.y + (target.y - self.y) * t,
        };
    }

    pub fn dot(self: Vec2, other: Vec2) f32 {
        return self.x * other.x + self.y * other.y;
    }

    pub fn cross(self: Vec2, other: Vec2) f32 {
        return self.x * other.y - self.y * other.x;
    }

    pub fn distance(self: Vec2, other: Vec2) f32 {
        return self.sub(other).length();
    }

    pub fn eql(self: Vec2, other: Vec2) bool {
        return self.x == other.x and self.y == other.y;
    }

    pub fn approxEql(self: Vec2, other: Vec2, tolerance: f32) bool {
        return @abs(self.x - other.x) <= tolerance and
            @abs(self.y - other.y) <= tolerance;
    }
};

/// 2D transformation matrix (3x3 stored as 6 values for 2D affine transforms)
/// | a  b  tx |
/// | c  d  ty |
/// | 0  0  1  |
pub const Matrix2D = struct {
    a: f32 = 1, // scale x, rotation
    b: f32 = 0, // rotation, skew
    c: f32 = 0, // rotation, skew
    d: f32 = 1, // scale y, rotation
    tx: f32 = 0, // translation x
    ty: f32 = 0, // translation y

    pub const identity = Matrix2D{};

    /// Create a translation matrix
    pub fn translation(x: f32, y: f32) Matrix2D {
        return .{ .tx = x, .ty = y };
    }

    /// Create a rotation matrix (angle in radians)
    pub fn rotation(angle: f32) Matrix2D {
        const cos_a = @cos(angle);
        const sin_a = @sin(angle);
        return .{
            .a = cos_a,
            .b = -sin_a,
            .c = sin_a,
            .d = cos_a,
        };
    }

    /// Create a scale matrix
    pub fn scaling(sx: f32, sy: f32) Matrix2D {
        return .{ .a = sx, .d = sy };
    }

    /// Create a transform matrix from position, rotation, and scale
    pub fn fromTransform(pos: Vec2, rot: f32, scl: Vec2) Matrix2D {
        const cos_a = @cos(rot);
        const sin_a = @sin(rot);
        return .{
            .a = cos_a * scl.x,
            .b = -sin_a * scl.y,
            .c = sin_a * scl.x,
            .d = cos_a * scl.y,
            .tx = pos.x,
            .ty = pos.y,
        };
    }

    /// Multiply two matrices (self * other)
    pub fn multiply(self: Matrix2D, other: Matrix2D) Matrix2D {
        return .{
            .a = self.a * other.a + self.b * other.c,
            .b = self.a * other.b + self.b * other.d,
            .c = self.c * other.a + self.d * other.c,
            .d = self.c * other.b + self.d * other.d,
            .tx = self.a * other.tx + self.b * other.ty + self.tx,
            .ty = self.c * other.tx + self.d * other.ty + self.ty,
        };
    }

    /// Transform a point by this matrix
    pub fn transformPoint(self: Matrix2D, point: Vec2) Vec2 {
        return .{
            .x = self.a * point.x + self.b * point.y + self.tx,
            .y = self.c * point.x + self.d * point.y + self.ty,
        };
    }

    /// Transform a vector (direction) by this matrix (ignores translation)
    pub fn transformVector(self: Matrix2D, vec: Vec2) Vec2 {
        return .{
            .x = self.a * vec.x + self.b * vec.y,
            .y = self.c * vec.x + self.d * vec.y,
        };
    }

    /// Calculate the inverse of this matrix
    pub fn inverse(self: Matrix2D) Matrix2D {
        const det = self.a * self.d - self.b * self.c;
        if (@abs(det) < 0.0001) {
            return Matrix2D.identity; // Singular matrix
        }
        const inv_det = 1.0 / det;
        return .{
            .a = self.d * inv_det,
            .b = -self.b * inv_det,
            .c = -self.c * inv_det,
            .d = self.a * inv_det,
            .tx = (self.c * self.ty - self.d * self.tx) * inv_det,
            .ty = (self.b * self.tx - self.a * self.ty) * inv_det,
        };
    }

    /// Get the determinant
    pub fn determinant(self: Matrix2D) f32 {
        return self.a * self.d - self.b * self.c;
    }

    /// Extract the scale from this matrix
    pub fn getScale(self: Matrix2D) Vec2 {
        return .{
            .x = @sqrt(self.a * self.a + self.c * self.c),
            .y = @sqrt(self.b * self.b + self.d * self.d),
        };
    }

    /// Extract the rotation from this matrix (in radians)
    pub fn getRotation(self: Matrix2D) f32 {
        return std.math.atan2(self.c, self.a);
    }

    /// Extract the translation from this matrix
    pub fn getTranslation(self: Matrix2D) Vec2 {
        return .{ .x = self.tx, .y = self.ty };
    }
};

// ============================================================================
// Transform Component
// ============================================================================

/// 2D Transform component for entities
pub const Transform2D = struct {
    /// Local position relative to parent (or world if no parent)
    position: Vec2 = Vec2.zero,
    /// Local rotation in radians
    rotation: f32 = 0,
    /// Local scale
    scale: Vec2 = Vec2.one,
    /// Parent entity (null if root)
    parent: ?Entity = null,
    /// Z-index for rendering order (higher = in front)
    z_index: i32 = 0,

    /// Create a transform with default values
    pub fn init() Transform2D {
        return .{};
    }

    /// Create a transform with position only
    pub fn fromPosition(x: f32, y: f32) Transform2D {
        return .{ .position = Vec2.init(x, y) };
    }

    /// Create a transform with position and rotation
    pub fn fromPositionRotation(x: f32, y: f32, rot: f32) Transform2D {
        return .{
            .position = Vec2.init(x, y),
            .rotation = rot,
        };
    }

    /// Create a full transform
    pub fn create(pos: Vec2, rot: f32, scl: Vec2) Transform2D {
        return .{
            .position = pos,
            .rotation = rot,
            .scale = scl,
        };
    }

    /// Get the local transformation matrix
    pub fn getLocalMatrix(self: *const Transform2D) Matrix2D {
        return Matrix2D.fromTransform(self.position, self.rotation, self.scale);
    }

    /// Set position
    pub fn setPosition(self: *Transform2D, x: f32, y: f32) void {
        self.position = Vec2.init(x, y);
    }

    /// Translate by delta
    pub fn translate(self: *Transform2D, dx: f32, dy: f32) void {
        self.position.x += dx;
        self.position.y += dy;
    }

    /// Set rotation in radians
    pub fn setRotation(self: *Transform2D, radians: f32) void {
        self.rotation = radians;
    }

    /// Set rotation in degrees
    pub fn setRotationDegrees(self: *Transform2D, degrees: f32) void {
        self.rotation = degrees * std.math.pi / 180.0;
    }

    /// Get rotation in degrees
    pub fn getRotationDegrees(self: *const Transform2D) f32 {
        return self.rotation * 180.0 / std.math.pi;
    }

    /// Rotate by delta (radians)
    pub fn rotate(self: *Transform2D, delta: f32) void {
        self.rotation += delta;
    }

    /// Rotate by delta (degrees)
    pub fn rotateDegrees(self: *Transform2D, degrees: f32) void {
        self.rotation += degrees * std.math.pi / 180.0;
    }

    /// Set uniform scale
    pub fn setUniformScale(self: *Transform2D, s: f32) void {
        self.scale = Vec2.init(s, s);
    }

    /// Set non-uniform scale
    pub fn setScale(self: *Transform2D, sx: f32, sy: f32) void {
        self.scale = Vec2.init(sx, sy);
    }

    /// Get the forward direction vector (pointing right by default, rotated)
    pub fn getForward(self: *const Transform2D) Vec2 {
        return Vec2.init(@cos(self.rotation), @sin(self.rotation));
    }

    /// Get the right direction vector
    pub fn getRight(self: *const Transform2D) Vec2 {
        return Vec2.init(-@sin(self.rotation), @cos(self.rotation));
    }

    /// Look at a target position
    pub fn lookAt(self: *Transform2D, target: Vec2) void {
        const dir = target.sub(self.position);
        self.rotation = std.math.atan2(dir.y, dir.x);
    }
};

// ============================================================================
// Transform Hierarchy
// ============================================================================

/// Cached world transform data with dirty flag optimization
const WorldTransformData = struct {
    world_matrix: Matrix2D = Matrix2D.identity,
    world_position: Vec2 = Vec2.zero,
    world_rotation: f32 = 0,
    world_scale: Vec2 = Vec2.one,
    dirty: bool = true,
};

/// Manages transform hierarchy and world transform calculations
pub const TransformHierarchy = struct {
    allocator: std.mem.Allocator,
    /// Cached world transforms indexed by entity ID
    world_transforms: std.AutoHashMap(u32, WorldTransformData),
    /// Children list for each entity (for propagating dirty flags)
    children: std.AutoHashMap(u32, std.ArrayList(Entity)),
    /// Tracks which entities are dirty (need world transform recalculation)
    dirty_entities: std.AutoHashMap(u32, void),

    pub fn init(allocator: std.mem.Allocator) TransformHierarchy {
        return .{
            .allocator = allocator,
            .world_transforms = std.AutoHashMap(u32, WorldTransformData).init(allocator),
            .children = std.AutoHashMap(u32, std.ArrayList(Entity)).init(allocator),
            .dirty_entities = std.AutoHashMap(u32, void).init(allocator),
        };
    }

    pub fn deinit(self: *TransformHierarchy) void {
        self.world_transforms.deinit();
        var children_iter = self.children.valueIterator();
        while (children_iter.next()) |list| {
            list.deinit(self.allocator);
        }
        self.children.deinit();
        self.dirty_entities.deinit();
    }

    /// Register an entity's transform with the hierarchy
    pub fn register(self: *TransformHierarchy, entity: Entity, transform: *const Transform2D) !void {
        try self.world_transforms.put(entity.id, .{ .dirty = true });
        try self.dirty_entities.put(entity.id, {});

        // If this entity has a parent, add it to the parent's children list
        if (transform.parent) |parent| {
            try self.addChild(parent, entity);
        }
    }

    /// Unregister an entity from the hierarchy
    pub fn unregister(self: *TransformHierarchy, entity: Entity) void {
        _ = self.world_transforms.remove(entity.id);
        _ = self.dirty_entities.remove(entity.id);

        // Remove from children list
        if (self.children.getPtr(entity.id)) |children_list| {
            children_list.deinit(self.allocator);
            _ = self.children.remove(entity.id);
        }
    }

    /// Add a child entity to a parent
    fn addChild(self: *TransformHierarchy, parent: Entity, child: Entity) !void {
        const result = try self.children.getOrPut(parent.id);
        if (!result.found_existing) {
            result.value_ptr.* = std.ArrayList(Entity){};
        }
        try result.value_ptr.append(self.allocator, child);
    }

    /// Remove a child entity from a parent
    pub fn removeChild(self: *TransformHierarchy, parent: Entity, child: Entity) void {
        if (self.children.getPtr(parent.id)) |children_list| {
            for (children_list.items, 0..) |c, i| {
                if (c.eql(child)) {
                    _ = children_list.swapRemove(i);
                    break;
                }
            }
        }
    }

    /// Set a parent for an entity (call when Transform2D.parent changes)
    pub fn setParent(self: *TransformHierarchy, entity: Entity, old_parent: ?Entity, new_parent: ?Entity) !void {
        // Remove from old parent's children
        if (old_parent) |old| {
            self.removeChild(old, entity);
        }

        // Add to new parent's children
        if (new_parent) |new| {
            try self.addChild(new, entity);
        }

        // Mark entity and all descendants as dirty
        self.markDirty(entity);
    }

    /// Mark an entity's world transform as dirty (needs recalculation)
    pub fn markDirty(self: *TransformHierarchy, entity: Entity) void {
        if (self.world_transforms.getPtr(entity.id)) |data| {
            if (!data.dirty) {
                data.dirty = true;
                self.dirty_entities.put(entity.id, {}) catch {};
            }
        }

        // Recursively mark all children as dirty
        if (self.children.get(entity.id)) |children_list| {
            for (children_list.items) |child| {
                self.markDirty(child);
            }
        }
    }

    /// Update world transform for an entity (call after local transform changes)
    pub fn updateWorldTransform(
        self: *TransformHierarchy,
        entity: Entity,
        local_transform: *const Transform2D,
        transforms: anytype,
    ) !void {
        const data = self.world_transforms.getPtr(entity.id) orelse return;

        if (!data.dirty) return;

        // Calculate parent's world matrix
        var parent_matrix = Matrix2D.identity;
        if (local_transform.parent) |parent| {
            if (transforms.get(parent)) |parent_transform| {
                // Ensure parent is updated first
                try self.updateWorldTransform(parent, parent_transform, transforms);
                if (self.world_transforms.get(parent.id)) |parent_data| {
                    parent_matrix = parent_data.world_matrix;
                }
            } else |_| {
                // Parent doesn't have a transform, use identity
            }
        }

        // Calculate local matrix and combine with parent
        const local_matrix = local_transform.getLocalMatrix();
        data.world_matrix = parent_matrix.multiply(local_matrix);

        // Cache decomposed values
        data.world_position = data.world_matrix.getTranslation();
        data.world_rotation = data.world_matrix.getRotation();
        data.world_scale = data.world_matrix.getScale();
        data.dirty = false;

        _ = self.dirty_entities.remove(entity.id);
    }

    /// Get the cached world transform for an entity
    pub fn getWorldTransform(self: *const TransformHierarchy, entity: Entity) ?*const WorldTransformData {
        return self.world_transforms.getPtr(entity.id);
    }

    /// Get world position for an entity
    pub fn getWorldPosition(self: *const TransformHierarchy, entity: Entity) ?Vec2 {
        if (self.world_transforms.get(entity.id)) |data| {
            return data.world_position;
        }
        return null;
    }

    /// Get world rotation for an entity
    pub fn getWorldRotation(self: *const TransformHierarchy, entity: Entity) ?f32 {
        if (self.world_transforms.get(entity.id)) |data| {
            return data.world_rotation;
        }
        return null;
    }

    /// Get world scale for an entity
    pub fn getWorldScale(self: *const TransformHierarchy, entity: Entity) ?Vec2 {
        if (self.world_transforms.get(entity.id)) |data| {
            return data.world_scale;
        }
        return null;
    }

    /// Get world matrix for an entity
    pub fn getWorldMatrix(self: *const TransformHierarchy, entity: Entity) ?Matrix2D {
        if (self.world_transforms.get(entity.id)) |data| {
            return data.world_matrix;
        }
        return null;
    }

    /// Transform a local point to world coordinates
    pub fn localToWorld(self: *const TransformHierarchy, entity: Entity, local_point: Vec2) ?Vec2 {
        if (self.world_transforms.get(entity.id)) |data| {
            return data.world_matrix.transformPoint(local_point);
        }
        return null;
    }

    /// Transform a world point to local coordinates
    pub fn worldToLocal(self: *const TransformHierarchy, entity: Entity, world_point: Vec2) ?Vec2 {
        if (self.world_transforms.get(entity.id)) |data| {
            return data.world_matrix.inverse().transformPoint(world_point);
        }
        return null;
    }

    /// Check if any transforms are dirty
    pub fn hasDirtyTransforms(self: *const TransformHierarchy) bool {
        return self.dirty_entities.count() > 0;
    }

    /// Get the number of dirty transforms
    pub fn dirtyCount(self: *const TransformHierarchy) usize {
        return self.dirty_entities.count();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Vec2 - basic operations" {
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

    // Dot product
    try std.testing.expectApproxEqRel(@as(f32, 11.0), a.dot(b), 0.0001);
}

test "Vec2 - rotation" {
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

test "Matrix2D - identity" {
    const identity = Matrix2D.identity;
    const point = Vec2.init(5.0, 10.0);

    const transformed = identity.transformPoint(point);
    try std.testing.expectApproxEqRel(point.x, transformed.x, 0.0001);
    try std.testing.expectApproxEqRel(point.y, transformed.y, 0.0001);
}

test "Matrix2D - translation" {
    const m = Matrix2D.translation(10.0, 20.0);
    const point = Vec2.init(5.0, 5.0);

    const transformed = m.transformPoint(point);
    try std.testing.expectApproxEqRel(@as(f32, 15.0), transformed.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 25.0), transformed.y, 0.0001);
}

test "Matrix2D - rotation" {
    const m = Matrix2D.rotation(std.math.pi / 2.0);
    const point = Vec2.init(1.0, 0.0);

    const transformed = m.transformPoint(point);
    try std.testing.expectApproxEqRel(@as(f32, 0.0), transformed.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 1.0), transformed.y, 0.0001);
}

test "Matrix2D - scale" {
    const m = Matrix2D.scaling(2.0, 3.0);
    const point = Vec2.init(5.0, 10.0);

    const transformed = m.transformPoint(point);
    try std.testing.expectApproxEqRel(@as(f32, 10.0), transformed.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 30.0), transformed.y, 0.0001);
}

test "Matrix2D - combined transform" {
    // Position (10, 20), rotation 90 degrees, scale (2, 2)
    const m = Matrix2D.fromTransform(
        Vec2.init(10.0, 20.0),
        std.math.pi / 2.0,
        Vec2.init(2.0, 2.0),
    );

    // Point (1, 0) should become: scaled to (2, 0), rotated to (0, 2), translated to (10, 22)
    const point = Vec2.init(1.0, 0.0);
    const transformed = m.transformPoint(point);
    try std.testing.expectApproxEqRel(@as(f32, 10.0), transformed.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 22.0), transformed.y, 0.0001);
}

test "Matrix2D - multiply" {
    const t = Matrix2D.translation(10.0, 0.0);
    const r = Matrix2D.rotation(std.math.pi / 2.0);

    // Translate then rotate: point at (0, 0) -> (10, 0) -> (0, 10)
    const tr = t.multiply(r);
    const point = Vec2.zero;
    const result_tr = tr.transformPoint(point);
    try std.testing.expectApproxEqRel(@as(f32, 0.0), result_tr.x, 0.001);
    try std.testing.expectApproxEqRel(@as(f32, 10.0), result_tr.y, 0.001);

    // Rotate then translate: point at (0, 0) -> (0, 0) -> (10, 0)
    const rt = r.multiply(t);
    const result_rt = rt.transformPoint(point);
    try std.testing.expectApproxEqRel(@as(f32, 10.0), result_rt.x, 0.001);
    try std.testing.expectApproxEqRel(@as(f32, 0.0), result_rt.y, 0.001);
}

test "Matrix2D - inverse" {
    const m = Matrix2D.fromTransform(
        Vec2.init(10.0, 20.0),
        std.math.pi / 4.0,
        Vec2.init(2.0, 3.0),
    );

    const inv = m.inverse();
    const identity_ish = m.multiply(inv);

    // Should be close to identity
    try std.testing.expectApproxEqRel(@as(f32, 1.0), identity_ish.a, 0.001);
    try std.testing.expectApproxEqRel(@as(f32, 0.0), identity_ish.b, 0.001);
    try std.testing.expectApproxEqRel(@as(f32, 0.0), identity_ish.c, 0.001);
    try std.testing.expectApproxEqRel(@as(f32, 1.0), identity_ish.d, 0.001);
    try std.testing.expectApproxEqRel(@as(f32, 0.0), identity_ish.tx, 0.001);
    try std.testing.expectApproxEqRel(@as(f32, 0.0), identity_ish.ty, 0.001);
}

test "Transform2D - basic creation" {
    const t = Transform2D.init();
    try std.testing.expect(t.position.eql(Vec2.zero));
    try std.testing.expectEqual(@as(f32, 0.0), t.rotation);
    try std.testing.expect(t.scale.eql(Vec2.one));
    try std.testing.expect(t.parent == null);
}

test "Transform2D - from position" {
    const t = Transform2D.fromPosition(100.0, 200.0);
    try std.testing.expectApproxEqRel(@as(f32, 100.0), t.position.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 200.0), t.position.y, 0.0001);
}

test "Transform2D - setters and getters" {
    var t = Transform2D.init();

    t.setPosition(50.0, 100.0);
    try std.testing.expectApproxEqRel(@as(f32, 50.0), t.position.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 100.0), t.position.y, 0.0001);

    t.translate(10.0, -20.0);
    try std.testing.expectApproxEqRel(@as(f32, 60.0), t.position.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 80.0), t.position.y, 0.0001);

    t.setRotationDegrees(90.0);
    try std.testing.expectApproxEqRel(@as(f32, 90.0), t.getRotationDegrees(), 0.01);

    t.setUniformScale(2.0);
    try std.testing.expectApproxEqRel(@as(f32, 2.0), t.scale.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 2.0), t.scale.y, 0.0001);
}

test "Transform2D - forward and right vectors" {
    var t = Transform2D.init();

    // Default: pointing right
    var forward = t.getForward();
    try std.testing.expectApproxEqRel(@as(f32, 1.0), forward.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 0.0), forward.y, 0.0001);

    // Rotate 90 degrees
    t.setRotationDegrees(90.0);
    forward = t.getForward();
    try std.testing.expectApproxEqRel(@as(f32, 0.0), forward.x, 0.0001);
    try std.testing.expectApproxEqRel(@as(f32, 1.0), forward.y, 0.0001);
}

test "Transform2D - lookAt" {
    var t = Transform2D.fromPosition(0.0, 0.0);

    t.lookAt(Vec2.init(10.0, 0.0)); // Look right
    try std.testing.expectApproxEqRel(@as(f32, 0.0), t.rotation, 0.0001);

    t.lookAt(Vec2.init(0.0, 10.0)); // Look up
    try std.testing.expectApproxEqRel(std.math.pi / 2.0, t.rotation, 0.0001);

    t.lookAt(Vec2.init(-10.0, 0.0)); // Look left
    try std.testing.expectApproxEqRel(std.math.pi, @abs(t.rotation), 0.0001);
}

test "TransformHierarchy - basic registration" {
    var hierarchy = TransformHierarchy.init(std.testing.allocator);
    defer hierarchy.deinit();

    const entity = Entity.init(0, 0);
    const transform = Transform2D.init();

    try hierarchy.register(entity, &transform);
    try std.testing.expect(hierarchy.hasDirtyTransforms());
}

test "TransformHierarchy - world transform without parent" {
    var hierarchy = TransformHierarchy.init(std.testing.allocator);
    defer hierarchy.deinit();

    // Simple mock transform storage
    const MockTransforms = struct {
        pub fn get(_: @This(), _: Entity) error{ComponentNotFound}!*const Transform2D {
            return error.ComponentNotFound;
        }
    };
    const mock = MockTransforms{};

    const entity = Entity.init(0, 0);
    var transform = Transform2D.fromPosition(100.0, 200.0);
    transform.rotation = std.math.pi / 4.0;
    transform.scale = Vec2.init(2.0, 2.0);

    try hierarchy.register(entity, &transform);
    try hierarchy.updateWorldTransform(entity, &transform, mock);

    const world_pos = hierarchy.getWorldPosition(entity);
    try std.testing.expect(world_pos != null);
    try std.testing.expectApproxEqRel(@as(f32, 100.0), world_pos.?.x, 0.001);
    try std.testing.expectApproxEqRel(@as(f32, 200.0), world_pos.?.y, 0.001);
}

test "TransformHierarchy - parent-child hierarchy" {
    var hierarchy = TransformHierarchy.init(std.testing.allocator);
    defer hierarchy.deinit();

    const parent_entity = Entity.init(0, 0);
    const child_entity = Entity.init(1, 0);

    var parent_transform = Transform2D.fromPosition(100.0, 100.0);
    var child_transform = Transform2D.fromPosition(50.0, 0.0);
    child_transform.parent = parent_entity;

    try hierarchy.register(parent_entity, &parent_transform);
    try hierarchy.register(child_entity, &child_transform);

    // Mock transform storage that returns our transforms
    const TransformStorage = struct {
        parent: *const Transform2D,
        child: *const Transform2D,
        parent_entity: Entity,
        child_entity: Entity,

        pub fn get(self: @This(), entity: Entity) error{ComponentNotFound}!*const Transform2D {
            if (entity.eql(self.parent_entity)) return self.parent;
            if (entity.eql(self.child_entity)) return self.child;
            return error.ComponentNotFound;
        }
    };
    const storage = TransformStorage{
        .parent = &parent_transform,
        .child = &child_transform,
        .parent_entity = parent_entity,
        .child_entity = child_entity,
    };

    try hierarchy.updateWorldTransform(parent_entity, &parent_transform, storage);
    try hierarchy.updateWorldTransform(child_entity, &child_transform, storage);

    // Child's world position should be parent position + child local position
    const child_world_pos = hierarchy.getWorldPosition(child_entity);
    try std.testing.expect(child_world_pos != null);
    try std.testing.expectApproxEqRel(@as(f32, 150.0), child_world_pos.?.x, 0.001);
    try std.testing.expectApproxEqRel(@as(f32, 100.0), child_world_pos.?.y, 0.001);
}

test "TransformHierarchy - rotated parent affects child" {
    var hierarchy = TransformHierarchy.init(std.testing.allocator);
    defer hierarchy.deinit();

    const parent_entity = Entity.init(0, 0);
    const child_entity = Entity.init(1, 0);

    var parent_transform = Transform2D.fromPosition(0.0, 0.0);
    parent_transform.rotation = std.math.pi / 2.0; // 90 degrees

    var child_transform = Transform2D.fromPosition(10.0, 0.0); // Local: 10 units right
    child_transform.parent = parent_entity;

    try hierarchy.register(parent_entity, &parent_transform);
    try hierarchy.register(child_entity, &child_transform);

    const TransformStorage = struct {
        parent: *const Transform2D,
        child: *const Transform2D,
        parent_entity: Entity,
        child_entity: Entity,

        pub fn get(self: @This(), entity: Entity) error{ComponentNotFound}!*const Transform2D {
            if (entity.eql(self.parent_entity)) return self.parent;
            if (entity.eql(self.child_entity)) return self.child;
            return error.ComponentNotFound;
        }
    };
    const storage = TransformStorage{
        .parent = &parent_transform,
        .child = &child_transform,
        .parent_entity = parent_entity,
        .child_entity = child_entity,
    };

    try hierarchy.updateWorldTransform(parent_entity, &parent_transform, storage);
    try hierarchy.updateWorldTransform(child_entity, &child_transform, storage);

    // With parent rotated 90 degrees, child's local (10, 0) becomes world (0, 10)
    const child_world_pos = hierarchy.getWorldPosition(child_entity);
    try std.testing.expect(child_world_pos != null);
    try std.testing.expectApproxEqRel(@as(f32, 0.0), child_world_pos.?.x, 0.01);
    try std.testing.expectApproxEqRel(@as(f32, 10.0), child_world_pos.?.y, 0.01);
}

test "TransformHierarchy - dirty flag propagation" {
    var hierarchy = TransformHierarchy.init(std.testing.allocator);
    defer hierarchy.deinit();

    const parent_entity = Entity.init(0, 0);
    const child_entity = Entity.init(1, 0);

    var parent_transform = Transform2D.fromPosition(0.0, 0.0);
    var child_transform = Transform2D.fromPosition(10.0, 0.0);
    child_transform.parent = parent_entity;

    try hierarchy.register(parent_entity, &parent_transform);
    try hierarchy.register(child_entity, &child_transform);

    const TransformStorage = struct {
        parent: *const Transform2D,
        child: *const Transform2D,
        parent_entity: Entity,
        child_entity: Entity,

        pub fn get(self: @This(), entity: Entity) error{ComponentNotFound}!*const Transform2D {
            if (entity.eql(self.parent_entity)) return self.parent;
            if (entity.eql(self.child_entity)) return self.child;
            return error.ComponentNotFound;
        }
    };
    const storage = TransformStorage{
        .parent = &parent_transform,
        .child = &child_transform,
        .parent_entity = parent_entity,
        .child_entity = child_entity,
    };

    // Update both transforms
    try hierarchy.updateWorldTransform(parent_entity, &parent_transform, storage);
    try hierarchy.updateWorldTransform(child_entity, &child_transform, storage);
    try std.testing.expect(!hierarchy.hasDirtyTransforms());

    // Mark parent as dirty - should propagate to child
    hierarchy.markDirty(parent_entity);
    try std.testing.expect(hierarchy.hasDirtyTransforms());
    try std.testing.expectEqual(@as(usize, 2), hierarchy.dirtyCount());
}

test "TransformHierarchy - local to world and world to local" {
    var hierarchy = TransformHierarchy.init(std.testing.allocator);
    defer hierarchy.deinit();

    const entity = Entity.init(0, 0);
    var transform = Transform2D.fromPosition(100.0, 100.0);
    transform.scale = Vec2.init(2.0, 2.0);

    const MockTransforms = struct {
        pub fn get(_: @This(), _: Entity) error{ComponentNotFound}!*const Transform2D {
            return error.ComponentNotFound;
        }
    };
    const mock = MockTransforms{};

    try hierarchy.register(entity, &transform);
    try hierarchy.updateWorldTransform(entity, &transform, mock);

    // Local point (10, 10) should become world (120, 120) with scale 2
    const local_point = Vec2.init(10.0, 10.0);
    const world_point = hierarchy.localToWorld(entity, local_point);
    try std.testing.expect(world_point != null);
    try std.testing.expectApproxEqRel(@as(f32, 120.0), world_point.?.x, 0.001);
    try std.testing.expectApproxEqRel(@as(f32, 120.0), world_point.?.y, 0.001);

    // Round trip: world -> local -> world
    const back_to_local = hierarchy.worldToLocal(entity, world_point.?);
    try std.testing.expect(back_to_local != null);
    try std.testing.expectApproxEqRel(local_point.x, back_to_local.?.x, 0.001);
    try std.testing.expectApproxEqRel(local_point.y, back_to_local.?.y, 0.001);
}
