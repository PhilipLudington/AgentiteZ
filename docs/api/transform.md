# Transform System

2D transform component system with hierarchical parent-child relationships (`src/transform.zig`).

## Features

- **Position, rotation, scale** - Full 2D transform components
- **Parent-child hierarchy** - Transforms can have parents for hierarchical scene graphs
- **Local vs world transforms** - Automatic world transform calculation from local transforms
- **Dirty flag optimization** - Only recalculates world transforms when necessary
- **Matrix operations** - Full 2D affine transformation matrix support
- **Coordinate conversion** - Local-to-world and world-to-local point transforms

## Usage

### Basic Transform

```zig
const transform = @import("AgentiteZ").transform;

// Create default transform (position 0,0, rotation 0, scale 1,1)
var t = transform.Transform2D.init();

// Create from position
var t = transform.Transform2D.fromPosition(100.0, 200.0);

// Create with position and rotation
var t = transform.Transform2D.fromPositionRotation(100.0, 200.0, std.math.pi / 4.0);

// Create full transform
var t = transform.Transform2D.create(
    transform.Vec2.init(100.0, 200.0), // position
    std.math.pi / 4.0,                  // rotation (radians)
    transform.Vec2.init(2.0, 2.0),      // scale
);
```

### Transform Manipulation

```zig
var t = transform.Transform2D.init();

// Position
t.setPosition(50.0, 100.0);
t.translate(10.0, -20.0);  // Move by delta

// Rotation
t.setRotation(std.math.pi / 2.0);  // Radians
t.setRotationDegrees(90.0);         // Degrees
t.rotate(0.1);                       // Add radians
t.rotateDegrees(5.0);                // Add degrees
const degrees = t.getRotationDegrees();

// Scale
t.setUniformScale(2.0);        // Same scale on both axes
t.setScale(2.0, 3.0);          // Different x and y scale

// Direction vectors
const forward = t.getForward();  // Unit vector in facing direction
const right = t.getRight();      // Unit vector perpendicular

// Look at target
t.lookAt(transform.Vec2.init(target_x, target_y));
```

### Parent-Child Hierarchy

```zig
const ecs = @import("AgentiteZ").ecs;

// Create entities
var world = ecs.World.init(allocator);
const parent = try world.createEntity();
const child = try world.createEntity();

// Set up transforms
var parent_transform = transform.Transform2D.fromPosition(100.0, 100.0);
var child_transform = transform.Transform2D.fromPosition(50.0, 0.0);
child_transform.parent = parent;  // Child is relative to parent

// Child's world position will be (150, 100) when hierarchy is computed
```

### Transform Hierarchy Manager

```zig
// Create hierarchy manager
var hierarchy = transform.TransformHierarchy.init(allocator);
defer hierarchy.deinit();

// Register entities with their transforms
try hierarchy.register(parent_entity, &parent_transform);
try hierarchy.register(child_entity, &child_transform);

// When transforms change, mark as dirty
hierarchy.markDirty(parent_entity);  // Also marks all children dirty

// Update world transforms (call with your component storage)
try hierarchy.updateWorldTransform(parent_entity, &parent_transform, transforms);
try hierarchy.updateWorldTransform(child_entity, &child_transform, transforms);

// Query world transforms
const world_pos = hierarchy.getWorldPosition(child_entity);
const world_rot = hierarchy.getWorldRotation(child_entity);
const world_scale = hierarchy.getWorldScale(child_entity);
const world_matrix = hierarchy.getWorldMatrix(child_entity);

// Coordinate conversion
const world_point = hierarchy.localToWorld(entity, local_point);
const local_point = hierarchy.worldToLocal(entity, world_point);

// Check dirty state
if (hierarchy.hasDirtyTransforms()) {
    // Some transforms need recalculation
}
const dirty_count = hierarchy.dirtyCount();
```

### Matrix Operations

```zig
const Matrix2D = transform.Matrix2D;

// Create matrices
const identity = Matrix2D.identity;
const t = Matrix2D.translation(10.0, 20.0);
const r = Matrix2D.rotation(std.math.pi / 2.0);
const s = Matrix2D.scaling(2.0, 3.0);

// Combined transform matrix (from position, rotation, scale)
const m = Matrix2D.fromTransform(
    transform.Vec2.init(100.0, 200.0),  // position
    std.math.pi / 4.0,                   // rotation
    transform.Vec2.init(2.0, 2.0),       // scale
);

// Matrix multiplication (self * other)
const combined = t.multiply(r);

// Transform points and vectors
const world_point = m.transformPoint(local_point);
const world_dir = m.transformVector(local_dir);  // Ignores translation

// Inverse matrix
const inv = m.inverse();

// Decompose matrix
const pos = m.getTranslation();
const rot = m.getRotation();
const scl = m.getScale();
```

## Data Structures

### Vec2

```zig
pub const Vec2 = struct {
    x: f32,
    y: f32,

    pub const zero = Vec2{ .x = 0, .y = 0 };
    pub const one = Vec2{ .x = 1, .y = 1 };

    // Operations
    pub fn add(self: Vec2, other: Vec2) Vec2;
    pub fn sub(self: Vec2, other: Vec2) Vec2;
    pub fn mul(self: Vec2, other: Vec2) Vec2;  // Component-wise
    pub fn scale(self: Vec2, s: f32) Vec2;
    pub fn length(self: Vec2) f32;
    pub fn lengthSquared(self: Vec2) f32;
    pub fn normalize(self: Vec2) Vec2;
    pub fn rotate(self: Vec2, angle: f32) Vec2;
    pub fn lerp(self: Vec2, target: Vec2, t: f32) Vec2;
    pub fn dot(self: Vec2, other: Vec2) f32;
    pub fn cross(self: Vec2, other: Vec2) f32;
    pub fn distance(self: Vec2, other: Vec2) f32;
    pub fn eql(self: Vec2, other: Vec2) bool;
    pub fn approxEql(self: Vec2, other: Vec2, tolerance: f32) bool;
};
```

### Matrix2D

2D affine transformation matrix (3x3, stored as 6 values):

```
| a  b  tx |
| c  d  ty |
| 0  0  1  |
```

```zig
pub const Matrix2D = struct {
    a: f32 = 1,   // scale x, rotation
    b: f32 = 0,   // rotation, skew
    c: f32 = 0,   // rotation, skew
    d: f32 = 1,   // scale y, rotation
    tx: f32 = 0,  // translation x
    ty: f32 = 0,  // translation y

    pub const identity = Matrix2D{};

    // Factory methods
    pub fn translation(x: f32, y: f32) Matrix2D;
    pub fn rotation(angle: f32) Matrix2D;
    pub fn scaling(sx: f32, sy: f32) Matrix2D;
    pub fn fromTransform(pos: Vec2, rot: f32, scl: Vec2) Matrix2D;

    // Operations
    pub fn multiply(self: Matrix2D, other: Matrix2D) Matrix2D;
    pub fn transformPoint(self: Matrix2D, point: Vec2) Vec2;
    pub fn transformVector(self: Matrix2D, vec: Vec2) Vec2;
    pub fn inverse(self: Matrix2D) Matrix2D;
    pub fn determinant(self: Matrix2D) f32;

    // Decomposition
    pub fn getScale(self: Matrix2D) Vec2;
    pub fn getRotation(self: Matrix2D) f32;
    pub fn getTranslation(self: Matrix2D) Vec2;
};
```

### Transform2D

```zig
pub const Transform2D = struct {
    position: Vec2 = Vec2.zero,
    rotation: f32 = 0,          // Radians
    scale: Vec2 = Vec2.one,
    parent: ?Entity = null,     // Parent entity for hierarchy
    z_index: i32 = 0,           // Rendering order

    // Factory methods
    pub fn init() Transform2D;
    pub fn fromPosition(x: f32, y: f32) Transform2D;
    pub fn fromPositionRotation(x: f32, y: f32, rot: f32) Transform2D;
    pub fn create(pos: Vec2, rot: f32, scl: Vec2) Transform2D;

    // Methods
    pub fn getLocalMatrix(self: *const Transform2D) Matrix2D;
    pub fn setPosition(self: *Transform2D, x: f32, y: f32) void;
    pub fn translate(self: *Transform2D, dx: f32, dy: f32) void;
    pub fn setRotation(self: *Transform2D, radians: f32) void;
    pub fn setRotationDegrees(self: *Transform2D, degrees: f32) void;
    pub fn getRotationDegrees(self: *const Transform2D) f32;
    pub fn rotate(self: *Transform2D, delta: f32) void;
    pub fn rotateDegrees(self: *Transform2D, degrees: f32) void;
    pub fn setUniformScale(self: *Transform2D, s: f32) void;
    pub fn setScale(self: *Transform2D, sx: f32, sy: f32) void;
    pub fn getForward(self: *const Transform2D) Vec2;
    pub fn getRight(self: *const Transform2D) Vec2;
    pub fn lookAt(self: *Transform2D, target: Vec2) void;
};
```

### TransformHierarchy

```zig
pub const TransformHierarchy = struct {
    pub fn init(allocator: std.mem.Allocator) TransformHierarchy;
    pub fn deinit(self: *TransformHierarchy) void;

    // Registration
    pub fn register(self: *TransformHierarchy, entity: Entity, transform: *const Transform2D) !void;
    pub fn unregister(self: *TransformHierarchy, entity: Entity) void;

    // Hierarchy management
    pub fn setParent(self: *TransformHierarchy, entity: Entity, old_parent: ?Entity, new_parent: ?Entity) !void;

    // Dirty flag management
    pub fn markDirty(self: *TransformHierarchy, entity: Entity) void;
    pub fn hasDirtyTransforms(self: *const TransformHierarchy) bool;
    pub fn dirtyCount(self: *const TransformHierarchy) usize;

    // World transform calculation
    pub fn updateWorldTransform(self: *TransformHierarchy, entity: Entity, local_transform: *const Transform2D, transforms: anytype) !void;

    // World transform queries
    pub fn getWorldTransform(self: *const TransformHierarchy, entity: Entity) ?*const WorldTransformData;
    pub fn getWorldPosition(self: *const TransformHierarchy, entity: Entity) ?Vec2;
    pub fn getWorldRotation(self: *const TransformHierarchy, entity: Entity) ?f32;
    pub fn getWorldScale(self: *const TransformHierarchy, entity: Entity) ?Vec2;
    pub fn getWorldMatrix(self: *const TransformHierarchy, entity: Entity) ?Matrix2D;

    // Coordinate conversion
    pub fn localToWorld(self: *const TransformHierarchy, entity: Entity, local_point: Vec2) ?Vec2;
    pub fn worldToLocal(self: *const TransformHierarchy, entity: Entity, world_point: Vec2) ?Vec2;
};
```

## Integration with ECS

The transform system integrates with the ECS through the `TransformHierarchy` manager:

```zig
const ecs = @import("AgentiteZ").ecs;
const transform = @import("AgentiteZ").transform;

// Game state
var world: ecs.World = undefined;
var transforms: ecs.ComponentArray(transform.Transform2D) = undefined;
var hierarchy: transform.TransformHierarchy = undefined;

pub fn init(allocator: std.mem.Allocator) void {
    world = ecs.World.init(allocator);
    transforms = ecs.ComponentArray(transform.Transform2D).init(allocator);
    hierarchy = transform.TransformHierarchy.init(allocator);
}

pub fn createEntity(pos: transform.Vec2, parent: ?ecs.Entity) !ecs.Entity {
    const entity = try world.createEntity();
    var t = transform.Transform2D.fromPosition(pos.x, pos.y);
    t.parent = parent;
    try transforms.add(entity, t);
    try hierarchy.register(entity, &t);
    return entity;
}

pub fn updateTransforms() !void {
    var iter = transforms.iterator();
    while (iter.next()) |entry| {
        try hierarchy.updateWorldTransform(entry.entity, entry.component, &transforms);
    }
}
```

## Design Notes

- **Local transforms** are stored in `Transform2D` components
- **World transforms** are cached in `TransformHierarchy` with dirty flag optimization
- When a parent transform changes, all descendants are automatically marked dirty
- World transforms are computed lazily when `updateWorldTransform` is called
- The `z_index` field can be used for render ordering independent of hierarchy
