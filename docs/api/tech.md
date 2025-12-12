# Tech Tree System

Technology research system with prerequisites, progress tracking, and unlock management.

## Overview

The Tech Tree system provides:
- Technology node definitions with costs
- AND/OR prerequisite logic
- Research progress tracking
- Research queue management
- Technology unlocks (units, buildings, abilities)
- Categories and eras for organization
- Completion callbacks

## Quick Start

```zig
const tech = @import("AgentiteZ").tech;

var tree = tech.TechTree.init(allocator);
defer tree.deinit();

// Add technologies
try tree.addTech(.{ .id = "mining", .cost = 100 });
try tree.addTech(.{
    .id = "advanced_mining",
    .cost = 200,
    .prerequisites = &.{"mining"},
});

// Start research
_ = tree.startResearch("mining");

// Add research points (e.g., from buildings)
if (tree.addProgress(50)) {
    // Research complete!
}

// Check progress
const progress = tree.getProgress(); // 0.0 to 1.0
```

## API Reference

### TechTree

Main manager for the technology tree.

#### Initialization

```zig
pub fn init(allocator: std.mem.Allocator) TechTree
pub fn deinit(self: *TechTree) void
```

#### Adding Technologies

```zig
pub fn addTech(self: *TechTree, definition: TechDefinition) !void
pub fn removeTech(self: *TechTree, id: []const u8) bool
```

#### Research Operations

```zig
pub fn startResearch(self: *TechTree, id: []const u8) ResearchResult
pub fn queueResearch(self: *TechTree, id: []const u8) ResearchResult
pub fn cancelResearch(self: *TechTree) void
pub fn cancelQueued(self: *TechTree, id: []const u8) bool
pub fn clearQueue(self: *TechTree) void
pub fn addProgress(self: *TechTree, points: u32) bool
```

#### Query Methods

```zig
pub fn getState(self: *const TechTree, id: []const u8) ?TechState
pub fn isResearched(self: *const TechTree, id: []const u8) bool
pub fn isAvailable(self: *const TechTree, id: []const u8) bool
pub fn prerequisitesMet(self: *const TechTree, id: []const u8) bool
pub fn getProgress(self: *const TechTree) f32
pub fn getTechProgress(self: *const TechTree, id: []const u8) ?struct { current: u32, total: u32, ratio: f32 }
pub fn getCurrentResearch(self: *const TechTree) ?[]const u8
pub fn getQueue(self: *const TechTree) []const []const u8
```

#### Category and Era Queries

```zig
pub fn getTechsByCategory(self: *const TechTree, category: []const u8, allocator: std.mem.Allocator) ![][]const u8
pub fn getTechsByEra(self: *const TechTree, era: u8, allocator: std.mem.Allocator) ![][]const u8
pub fn getAvailableTechs(self: *const TechTree, allocator: std.mem.Allocator) ![][]const u8
pub fn getResearchedTechs(self: *const TechTree, allocator: std.mem.Allocator) ![][]const u8
```

#### Unlock System

```zig
pub fn getUnlocks(self: *const TechTree, id: []const u8, allocator: std.mem.Allocator) ![]TechUnlock
pub fn isUnlocked(self: *const TechTree, unlock_id: []const u8) bool
pub fn getUnlockedByType(self: *const TechTree, unlock_type: UnlockType, allocator: std.mem.Allocator) ![][]const u8
```

#### Debug/Cheat

```zig
pub fn forceComplete(self: *TechTree, id: []const u8) bool
pub fn resetTech(self: *TechTree, id: []const u8) bool
pub fn resetAll(self: *TechTree) void
```

### TechDefinition

Definition for a technology node.

```zig
pub const TechDefinition = struct {
    id: []const u8,                              // Unique identifier
    name: ?[]const u8 = null,                    // Display name
    description: ?[]const u8 = null,             // Description for UI
    cost: u32 = 100,                             // Research cost
    category: ?[]const u8 = null,                // Category/branch
    era: u8 = 1,                                 // Era/age level
    prerequisites: []const []const u8 = &.{},   // Required techs
    prerequisite_mode: PrerequisiteMode = .all, // AND or OR
    unlocks: []const TechUnlock = &.{},         // What this unlocks
    icon: ?[]const u8 = null,                   // Icon path
};
```

### PrerequisiteMode

```zig
pub const PrerequisiteMode = enum {
    all,  // All prerequisites must be researched (AND)
    any,  // Any one prerequisite is sufficient (OR)
};
```

### TechState

```zig
pub const TechState = enum {
    locked,       // Prerequisites not met
    available,    // Can research
    in_progress,  // Currently researching
    researched,   // Complete
};
```

### TechUnlock

```zig
pub const TechUnlock = struct {
    unlock_type: UnlockType,
    id: []const u8,
    description: ?[]const u8 = null,
};

pub const UnlockType = enum {
    unit,
    building,
    ability,
    upgrade,
    bonus,
    feature,
    resource,
};
```

## Examples

### Technology with Unlocks

```zig
try tree.addTech(.{
    .id = "barracks",
    .name = "Barracks Technology",
    .cost = 150,
    .category = "military",
    .era = 1,
    .unlocks = &.{
        .{ .unlock_type = .building, .id = "barracks" },
        .{ .unlock_type = .unit, .id = "soldier" },
        .{ .unlock_type = .unit, .id = "archer" },
    },
});

// Later, check if units are available
if (tree.isUnlocked("soldier")) {
    // Can now train soldiers
}
```

### OR Prerequisites

```zig
// Grid requires either coal OR solar power
try tree.addTech(.{
    .id = "electric_grid",
    .cost = 200,
    .prerequisites = &.{ "coal_power", "solar_power" },
    .prerequisite_mode = .any,
});
```

### Research Queue

```zig
tree.setMaxQueueSize(3);

_ = tree.startResearch("tech1");
_ = tree.queueResearch("tech2");
_ = tree.queueResearch("tech3");

// When tech1 completes, tech2 starts automatically
```

### Completion Callback

```zig
tree.setOnComplete(struct {
    fn callback(tech_id: []const u8, ctx: ?*anyopaque) void {
        const game: *Game = @ptrCast(@alignCast(ctx));
        game.onTechResearched(tech_id);
    }
}.callback, game);
```

## Test Coverage

20 tests covering:
- Basic tech addition and research
- AND/OR prerequisites
- Research queuing
- Cancel and reset
- Force complete
- Unlocks
- Categories and eras
- Callbacks
