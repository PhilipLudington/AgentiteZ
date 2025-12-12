//! Technology Tree System - Research and Tech Unlocks
//!
//! A flexible technology tree system for strategy games with prerequisites,
//! research progress tracking, and unlock management.
//!
//! Features:
//! - Tech node definitions with costs and prerequisites
//! - AND/OR prerequisite logic
//! - Research progress tracking
//! - Tech unlocks (units, buildings, abilities, bonuses)
//! - Tech branches and categories
//! - Research queue management
//! - Era/age progression
//!
//! Usage:
//! ```zig
//! var tree = TechTree.init(allocator);
//! defer tree.deinit();
//!
//! try tree.addTech(.{ .id = "mining", .cost = 100 });
//! try tree.addTech(.{ .id = "fusion", .cost = 500, .prerequisites = &.{"mining"} });
//!
//! try tree.startResearch("mining");
//! tree.addProgress(25);  // Add 25 research points
//! if (tree.isResearched("mining")) { ... }
//! ```

const std = @import("std");

const log = std.log.scoped(.tech);

/// Maximum number of prerequisites per tech
pub const MAX_PREREQUISITES = 8;

/// Maximum number of unlocks per tech
pub const MAX_UNLOCKS = 16;

/// Prerequisite requirement type
pub const PrerequisiteMode = enum {
    /// All prerequisites must be researched (AND)
    all,
    /// Any one prerequisite is sufficient (OR)
    any,
};

/// Type of unlock granted by a technology
pub const UnlockType = enum {
    unit,
    building,
    ability,
    upgrade,
    bonus,
    feature,
    resource,
};

/// An unlock granted by researching a technology
pub const TechUnlock = struct {
    unlock_type: UnlockType,
    id: []const u8,
    /// Optional description for UI
    description: ?[]const u8 = null,
};

/// Research state of a technology
pub const TechState = enum {
    /// Not yet available (prerequisites not met)
    locked,
    /// Available for research
    available,
    /// Currently being researched
    in_progress,
    /// Research complete
    researched,
};

/// Technology definition
pub const TechDefinition = struct {
    /// Unique identifier
    id: []const u8,
    /// Display name (optional, defaults to id)
    name: ?[]const u8 = null,
    /// Description for UI
    description: ?[]const u8 = null,
    /// Research cost (in research points)
    cost: u32 = 100,
    /// Category/branch (e.g., "military", "economy", "science")
    category: ?[]const u8 = null,
    /// Era/age level (higher = later game)
    era: u8 = 1,
    /// Prerequisites (tech IDs that must be researched first)
    prerequisites: []const []const u8 = &.{},
    /// How prerequisites are evaluated
    prerequisite_mode: PrerequisiteMode = .all,
    /// What this tech unlocks
    unlocks: []const TechUnlock = &.{},
    /// Icon path for UI (optional)
    icon: ?[]const u8 = null,
};

/// Internal tech node with runtime state
const TechNode = struct {
    // Definition (copied for ownership)
    id: []u8,
    name: ?[]u8,
    description: ?[]u8,
    cost: u32,
    category: ?[]u8,
    era: u8,
    prerequisites: std.ArrayList([]u8),
    prerequisite_mode: PrerequisiteMode,
    unlocks: std.ArrayList(OwnedUnlock),
    icon: ?[]u8,

    // Runtime state
    state: TechState,
    progress: u32,

    const OwnedUnlock = struct {
        unlock_type: UnlockType,
        id: []u8,
        description: ?[]u8,
    };

    fn deinit(self: *TechNode, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        if (self.name) |n| allocator.free(n);
        if (self.description) |d| allocator.free(d);
        if (self.category) |c| allocator.free(c);
        if (self.icon) |i| allocator.free(i);

        for (self.prerequisites.items) |p| {
            allocator.free(p);
        }
        self.prerequisites.deinit();

        for (self.unlocks.items) |u| {
            allocator.free(u.id);
            if (u.description) |d| allocator.free(d);
        }
        self.unlocks.deinit();
    }
};

/// Research result
pub const ResearchResult = enum {
    success,
    already_researched,
    already_in_progress,
    prerequisites_not_met,
    not_found,
    queue_full,
};

/// Technology Tree manager
pub const TechTree = struct {
    allocator: std.mem.Allocator,
    techs: std.StringHashMap(TechNode),
    /// Currently researching tech ID (null if none)
    current_research: ?[]const u8,
    /// Research queue (tech IDs)
    research_queue: std.ArrayList([]u8),
    /// Maximum queue size (0 = unlimited)
    max_queue_size: usize,
    /// Callback when research completes
    on_research_complete: ?*const fn (tech_id: []const u8, ctx: ?*anyopaque) void,
    on_research_complete_ctx: ?*anyopaque,

    /// Initialize the tech tree
    pub fn init(allocator: std.mem.Allocator) TechTree {
        return TechTree{
            .allocator = allocator,
            .techs = std.StringHashMap(TechNode).init(allocator),
            .current_research = null,
            .research_queue = std.ArrayList([]u8).init(allocator),
            .max_queue_size = 0,
            .on_research_complete = null,
            .on_research_complete_ctx = null,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *TechTree) void {
        var iter = self.techs.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.techs.deinit();

        for (self.research_queue.items) |id| {
            self.allocator.free(id);
        }
        self.research_queue.deinit();
    }

    /// Add a technology to the tree
    pub fn addTech(self: *TechTree, definition: TechDefinition) !void {
        // Copy strings for ownership
        const id_copy = try self.allocator.dupe(u8, definition.id);
        errdefer self.allocator.free(id_copy);

        var node = TechNode{
            .id = id_copy,
            .name = null,
            .description = null,
            .cost = definition.cost,
            .category = null,
            .era = definition.era,
            .prerequisites = std.ArrayList([]u8).init(self.allocator),
            .prerequisite_mode = definition.prerequisite_mode,
            .unlocks = std.ArrayList(TechNode.OwnedUnlock).init(self.allocator),
            .icon = null,
            .state = .locked,
            .progress = 0,
        };

        // Copy optional strings
        if (definition.name) |n| {
            node.name = try self.allocator.dupe(u8, n);
        }
        if (definition.description) |d| {
            node.description = try self.allocator.dupe(u8, d);
        }
        if (definition.category) |c| {
            node.category = try self.allocator.dupe(u8, c);
        }
        if (definition.icon) |i| {
            node.icon = try self.allocator.dupe(u8, i);
        }

        // Copy prerequisites
        for (definition.prerequisites) |prereq| {
            const prereq_copy = try self.allocator.dupe(u8, prereq);
            try node.prerequisites.append(prereq_copy);
        }

        // Copy unlocks
        for (definition.unlocks) |unlock| {
            const unlock_id = try self.allocator.dupe(u8, unlock.id);
            var unlock_desc: ?[]u8 = null;
            if (unlock.description) |d| {
                unlock_desc = try self.allocator.dupe(u8, d);
            }
            try node.unlocks.append(.{
                .unlock_type = unlock.unlock_type,
                .id = unlock_id,
                .description = unlock_desc,
            });
        }

        try self.techs.put(id_copy, node);

        // Update availability
        self.updateAvailability();
    }

    /// Remove a technology from the tree
    pub fn removeTech(self: *TechTree, id: []const u8) bool {
        if (self.techs.fetchRemove(id)) |kv| {
            var node = kv.value;
            node.deinit(self.allocator);
            return true;
        }
        return false;
    }

    /// Get technology state
    pub fn getState(self: *const TechTree, id: []const u8) ?TechState {
        if (self.techs.get(id)) |node| {
            return node.state;
        }
        return null;
    }

    /// Check if a technology is researched
    pub fn isResearched(self: *const TechTree, id: []const u8) bool {
        if (self.techs.get(id)) |node| {
            return node.state == .researched;
        }
        return false;
    }

    /// Check if a technology is available for research
    pub fn isAvailable(self: *const TechTree, id: []const u8) bool {
        if (self.techs.get(id)) |node| {
            return node.state == .available;
        }
        return false;
    }

    /// Check if prerequisites are met for a technology
    pub fn prerequisitesMet(self: *const TechTree, id: []const u8) bool {
        const node = self.techs.get(id) orelse return false;

        if (node.prerequisites.items.len == 0) {
            return true;
        }

        return switch (node.prerequisite_mode) {
            .all => blk: {
                for (node.prerequisites.items) |prereq| {
                    if (!self.isResearched(prereq)) {
                        break :blk false;
                    }
                }
                break :blk true;
            },
            .any => blk: {
                for (node.prerequisites.items) |prereq| {
                    if (self.isResearched(prereq)) {
                        break :blk true;
                    }
                }
                break :blk false;
            },
        };
    }

    /// Start researching a technology
    pub fn startResearch(self: *TechTree, id: []const u8) ResearchResult {
        const node = self.techs.getPtr(id) orelse return .not_found;

        if (node.state == .researched) {
            return .already_researched;
        }

        if (node.state == .in_progress) {
            return .already_in_progress;
        }

        if (!self.prerequisitesMet(id)) {
            return .prerequisites_not_met;
        }

        // If something is already being researched, queue this one
        if (self.current_research != null) {
            return self.queueResearch(id);
        }

        node.state = .in_progress;
        self.current_research = node.id;
        return .success;
    }

    /// Queue a technology for research
    pub fn queueResearch(self: *TechTree, id: []const u8) ResearchResult {
        const node = self.techs.get(id) orelse return .not_found;

        if (node.state == .researched) {
            return .already_researched;
        }

        // Check if already in queue
        for (self.research_queue.items) |queued_id| {
            if (std.mem.eql(u8, queued_id, id)) {
                return .already_in_progress;
            }
        }

        // Check queue limit
        if (self.max_queue_size > 0 and self.research_queue.items.len >= self.max_queue_size) {
            return .queue_full;
        }

        const id_copy = self.allocator.dupe(u8, id) catch return .not_found;
        self.research_queue.append(id_copy) catch {
            self.allocator.free(id_copy);
            return .not_found;
        };

        return .success;
    }

    /// Cancel current research
    pub fn cancelResearch(self: *TechTree) void {
        if (self.current_research) |id| {
            if (self.techs.getPtr(id)) |node| {
                node.state = .available;
                node.progress = 0;
            }
            self.current_research = null;
            self.startNextInQueue();
        }
    }

    /// Cancel a queued research
    pub fn cancelQueued(self: *TechTree, id: []const u8) bool {
        var i: usize = 0;
        while (i < self.research_queue.items.len) {
            if (std.mem.eql(u8, self.research_queue.items[i], id)) {
                self.allocator.free(self.research_queue.items[i]);
                _ = self.research_queue.orderedRemove(i);
                return true;
            }
            i += 1;
        }
        return false;
    }

    /// Clear the research queue
    pub fn clearQueue(self: *TechTree) void {
        for (self.research_queue.items) |id| {
            self.allocator.free(id);
        }
        self.research_queue.clearRetainingCapacity();
    }

    /// Add research points to current research
    pub fn addProgress(self: *TechTree, points: u32) bool {
        const id = self.current_research orelse return false;
        const node = self.techs.getPtr(id) orelse return false;

        node.progress += points;

        if (node.progress >= node.cost) {
            self.completeResearch(id);
            return true;
        }

        return false;
    }

    /// Get current research progress (0.0 to 1.0)
    pub fn getProgress(self: *const TechTree) f32 {
        const id = self.current_research orelse return 0;
        const node = self.techs.get(id) orelse return 0;

        if (node.cost == 0) return 1.0;
        return @as(f32, @floatFromInt(node.progress)) / @as(f32, @floatFromInt(node.cost));
    }

    /// Get progress for a specific tech
    pub fn getTechProgress(self: *const TechTree, id: []const u8) ?struct { current: u32, total: u32, ratio: f32 } {
        const node = self.techs.get(id) orelse return null;
        const ratio: f32 = if (node.cost == 0) 1.0 else @as(f32, @floatFromInt(node.progress)) / @as(f32, @floatFromInt(node.cost));
        return .{
            .current = node.progress,
            .total = node.cost,
            .ratio = ratio,
        };
    }

    /// Get currently researching tech ID
    pub fn getCurrentResearch(self: *const TechTree) ?[]const u8 {
        return self.current_research;
    }

    /// Get research queue
    pub fn getQueue(self: *const TechTree) []const []const u8 {
        // Return slice of []u8 as []const u8
        const items = self.research_queue.items;
        return @as([*]const []const u8, @ptrCast(items.ptr))[0..items.len];
    }

    /// Complete current research
    fn completeResearch(self: *TechTree, id: []const u8) void {
        const node = self.techs.getPtr(id) orelse return;

        node.state = .researched;
        node.progress = node.cost;
        self.current_research = null;

        // Callback
        if (self.on_research_complete) |callback| {
            callback(id, self.on_research_complete_ctx);
        }

        // Update availability of dependent techs
        self.updateAvailability();

        // Start next in queue
        self.startNextInQueue();
    }

    /// Force-complete a technology (cheat/debug)
    pub fn forceComplete(self: *TechTree, id: []const u8) bool {
        const node = self.techs.getPtr(id) orelse return false;

        if (node.state == .researched) return false;

        // If this is current research, complete it properly
        if (self.current_research) |current_id| {
            if (std.mem.eql(u8, current_id, id)) {
                self.completeResearch(id);
                return true;
            }
        }

        // Otherwise just mark as researched
        node.state = .researched;
        node.progress = node.cost;
        self.updateAvailability();
        return true;
    }

    /// Reset a technology (un-research it)
    pub fn resetTech(self: *TechTree, id: []const u8) bool {
        const node = self.techs.getPtr(id) orelse return false;

        node.state = .locked;
        node.progress = 0;
        self.updateAvailability();
        return true;
    }

    /// Reset all research
    pub fn resetAll(self: *TechTree) void {
        var iter = self.techs.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.state = .locked;
            entry.value_ptr.progress = 0;
        }
        self.current_research = null;
        self.clearQueue();
        self.updateAvailability();
    }

    /// Start next research from queue
    fn startNextInQueue(self: *TechTree) void {
        while (self.research_queue.items.len > 0) {
            const id = self.research_queue.orderedRemove(0);
            defer self.allocator.free(id);

            if (self.prerequisitesMet(id)) {
                if (self.techs.getPtr(id)) |node| {
                    if (node.state != .researched) {
                        node.state = .in_progress;
                        self.current_research = node.id;
                        return;
                    }
                }
            }
        }
    }

    /// Update availability of all techs based on prerequisites
    fn updateAvailability(self: *TechTree) void {
        var iter = self.techs.iterator();
        while (iter.next()) |entry| {
            const node = entry.value_ptr;
            if (node.state == .locked) {
                if (self.prerequisitesMet(entry.key_ptr.*)) {
                    node.state = .available;
                }
            } else if (node.state == .available) {
                // Re-check in case something was reset
                if (!self.prerequisitesMet(entry.key_ptr.*)) {
                    node.state = .locked;
                }
            }
        }
    }

    /// Set callback for research completion
    pub fn setOnComplete(self: *TechTree, callback: ?*const fn ([]const u8, ?*anyopaque) void, ctx: ?*anyopaque) void {
        self.on_research_complete = callback;
        self.on_research_complete_ctx = ctx;
    }

    /// Set maximum queue size
    pub fn setMaxQueueSize(self: *TechTree, size: usize) void {
        self.max_queue_size = size;
    }

    // ====== Query Methods ======

    /// Get all techs in a category
    pub fn getTechsByCategory(self: *const TechTree, category: []const u8, allocator: std.mem.Allocator) ![][]const u8 {
        var list = std.ArrayList([]const u8).init(allocator);
        var iter = self.techs.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.category) |cat| {
                if (std.mem.eql(u8, cat, category)) {
                    try list.append(entry.key_ptr.*);
                }
            }
        }
        return list.toOwnedSlice();
    }

    /// Get all techs in an era
    pub fn getTechsByEra(self: *const TechTree, era: u8, allocator: std.mem.Allocator) ![][]const u8 {
        var list = std.ArrayList([]const u8).init(allocator);
        var iter = self.techs.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.era == era) {
                try list.append(entry.key_ptr.*);
            }
        }
        return list.toOwnedSlice();
    }

    /// Get all available techs
    pub fn getAvailableTechs(self: *const TechTree, allocator: std.mem.Allocator) ![][]const u8 {
        var list = std.ArrayList([]const u8).init(allocator);
        var iter = self.techs.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.state == .available) {
                try list.append(entry.key_ptr.*);
            }
        }
        return list.toOwnedSlice();
    }

    /// Get all researched techs
    pub fn getResearchedTechs(self: *const TechTree, allocator: std.mem.Allocator) ![][]const u8 {
        var list = std.ArrayList([]const u8).init(allocator);
        var iter = self.techs.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.state == .researched) {
                try list.append(entry.key_ptr.*);
            }
        }
        return list.toOwnedSlice();
    }

    /// Get unlocks for a tech
    pub fn getUnlocks(self: *const TechTree, id: []const u8, allocator: std.mem.Allocator) ![]TechUnlock {
        const node = self.techs.get(id) orelse return &[_]TechUnlock{};
        var list = std.ArrayList(TechUnlock).init(allocator);
        for (node.unlocks.items) |unlock| {
            try list.append(.{
                .unlock_type = unlock.unlock_type,
                .id = unlock.id,
                .description = unlock.description,
            });
        }
        return list.toOwnedSlice();
    }

    /// Check if an unlock is available (its tech is researched)
    pub fn isUnlocked(self: *const TechTree, unlock_id: []const u8) bool {
        var iter = self.techs.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.state == .researched) {
                for (entry.value_ptr.unlocks.items) |unlock| {
                    if (std.mem.eql(u8, unlock.id, unlock_id)) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    /// Get all unlocked items of a type
    pub fn getUnlockedByType(self: *const TechTree, unlock_type: UnlockType, allocator: std.mem.Allocator) ![][]const u8 {
        var list = std.ArrayList([]const u8).init(allocator);
        var iter = self.techs.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.state == .researched) {
                for (entry.value_ptr.unlocks.items) |unlock| {
                    if (unlock.unlock_type == unlock_type) {
                        try list.append(unlock.id);
                    }
                }
            }
        }
        return list.toOwnedSlice();
    }

    /// Get tech info for UI
    pub fn getTechInfo(self: *const TechTree, id: []const u8) ?struct {
        id: []const u8,
        name: []const u8,
        description: ?[]const u8,
        cost: u32,
        category: ?[]const u8,
        era: u8,
        state: TechState,
        progress: u32,
    } {
        const node = self.techs.get(id) orelse return null;
        return .{
            .id = node.id,
            .name = node.name orelse node.id,
            .description = node.description,
            .cost = node.cost,
            .category = node.category,
            .era = node.era,
            .state = node.state,
            .progress = node.progress,
        };
    }

    /// Get tech count
    pub fn getTechCount(self: *const TechTree) usize {
        return self.techs.count();
    }

    /// Get researched tech count
    pub fn getResearchedCount(self: *const TechTree) usize {
        var count: usize = 0;
        var iter = self.techs.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.state == .researched) {
                count += 1;
            }
        }
        return count;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "TechTree - add and get tech" {
    var tree = TechTree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.addTech(.{ .id = "mining", .cost = 100 });

    try std.testing.expect(tree.getState("mining") != null);
    try std.testing.expectEqual(TechState.available, tree.getState("mining").?);
    try std.testing.expect(!tree.isResearched("mining"));
}

test "TechTree - basic research" {
    var tree = TechTree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.addTech(.{ .id = "mining", .cost = 100 });

    try std.testing.expectEqual(ResearchResult.success, tree.startResearch("mining"));
    try std.testing.expectEqual(TechState.in_progress, tree.getState("mining").?);

    _ = tree.addProgress(50);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), tree.getProgress(), 0.01);

    _ = tree.addProgress(50);
    try std.testing.expect(tree.isResearched("mining"));
}

test "TechTree - prerequisites (AND)" {
    var tree = TechTree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.addTech(.{ .id = "mining", .cost = 100 });
    try tree.addTech(.{ .id = "smelting", .cost = 100 });
    try tree.addTech(.{
        .id = "steel",
        .cost = 200,
        .prerequisites = &.{ "mining", "smelting" },
        .prerequisite_mode = .all,
    });

    // Steel should be locked
    try std.testing.expectEqual(TechState.locked, tree.getState("steel").?);
    try std.testing.expectEqual(ResearchResult.prerequisites_not_met, tree.startResearch("steel"));

    // Research mining
    _ = tree.startResearch("mining");
    _ = tree.addProgress(100);

    // Steel still locked (need smelting too)
    try std.testing.expectEqual(TechState.locked, tree.getState("steel").?);

    // Research smelting
    _ = tree.startResearch("smelting");
    _ = tree.addProgress(100);

    // Steel now available
    try std.testing.expectEqual(TechState.available, tree.getState("steel").?);
    try std.testing.expectEqual(ResearchResult.success, tree.startResearch("steel"));
}

test "TechTree - prerequisites (OR)" {
    var tree = TechTree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.addTech(.{ .id = "coal_power", .cost = 100 });
    try tree.addTech(.{ .id = "solar_power", .cost = 100 });
    try tree.addTech(.{
        .id = "electric_grid",
        .cost = 150,
        .prerequisites = &.{ "coal_power", "solar_power" },
        .prerequisite_mode = .any,
    });

    // Grid locked initially
    try std.testing.expectEqual(TechState.locked, tree.getState("electric_grid").?);

    // Research just coal
    _ = tree.startResearch("coal_power");
    _ = tree.addProgress(100);

    // Grid now available (only need one)
    try std.testing.expectEqual(TechState.available, tree.getState("electric_grid").?);
}

test "TechTree - research queue" {
    var tree = TechTree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.addTech(.{ .id = "tech1", .cost = 100 });
    try tree.addTech(.{ .id = "tech2", .cost = 100 });
    try tree.addTech(.{ .id = "tech3", .cost = 100 });

    // Start tech1, queue tech2 and tech3
    _ = tree.startResearch("tech1");
    _ = tree.queueResearch("tech2");
    _ = tree.queueResearch("tech3");

    try std.testing.expectEqual(@as(usize, 2), tree.getQueue().len);

    // Complete tech1
    _ = tree.addProgress(100);
    try std.testing.expect(tree.isResearched("tech1"));

    // tech2 should auto-start
    try std.testing.expectEqualStrings("tech2", tree.getCurrentResearch().?);
    try std.testing.expectEqual(@as(usize, 1), tree.getQueue().len);
}

test "TechTree - cancel research" {
    var tree = TechTree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.addTech(.{ .id = "mining", .cost = 100 });

    _ = tree.startResearch("mining");
    _ = tree.addProgress(50);

    tree.cancelResearch();

    try std.testing.expectEqual(TechState.available, tree.getState("mining").?);
    try std.testing.expect(tree.getCurrentResearch() == null);

    // Progress should be reset
    const progress = tree.getTechProgress("mining").?;
    try std.testing.expectEqual(@as(u32, 0), progress.current);
}

test "TechTree - force complete" {
    var tree = TechTree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.addTech(.{ .id = "mining", .cost = 1000 });
    try tree.addTech(.{
        .id = "advanced_mining",
        .cost = 500,
        .prerequisites = &.{"mining"},
    });

    try std.testing.expect(tree.forceComplete("mining"));
    try std.testing.expect(tree.isResearched("mining"));

    // Advanced mining should now be available
    try std.testing.expectEqual(TechState.available, tree.getState("advanced_mining").?);
}

test "TechTree - unlocks" {
    var tree = TechTree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.addTech(.{
        .id = "barracks",
        .cost = 100,
        .unlocks = &.{
            .{ .unlock_type = .building, .id = "barracks" },
            .{ .unlock_type = .unit, .id = "soldier" },
        },
    });

    try std.testing.expect(!tree.isUnlocked("barracks"));
    try std.testing.expect(!tree.isUnlocked("soldier"));

    _ = tree.startResearch("barracks");
    _ = tree.addProgress(100);

    try std.testing.expect(tree.isUnlocked("barracks"));
    try std.testing.expect(tree.isUnlocked("soldier"));
}

test "TechTree - get unlocked by type" {
    var tree = TechTree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.addTech(.{
        .id = "military1",
        .cost = 100,
        .unlocks = &.{
            .{ .unlock_type = .unit, .id = "soldier" },
            .{ .unlock_type = .building, .id = "barracks" },
        },
    });
    try tree.addTech(.{
        .id = "military2",
        .cost = 100,
        .unlocks = &.{
            .{ .unlock_type = .unit, .id = "tank" },
        },
    });

    _ = tree.forceComplete("military1");
    _ = tree.forceComplete("military2");

    const units = try tree.getUnlockedByType(.unit, std.testing.allocator);
    defer std.testing.allocator.free(units);

    try std.testing.expectEqual(@as(usize, 2), units.len);
}

test "TechTree - categories and eras" {
    var tree = TechTree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.addTech(.{ .id = "mining", .cost = 100, .category = "economy", .era = 1 });
    try tree.addTech(.{ .id = "barracks", .cost = 100, .category = "military", .era = 1 });
    try tree.addTech(.{ .id = "tanks", .cost = 200, .category = "military", .era = 2 });

    const military = try tree.getTechsByCategory("military", std.testing.allocator);
    defer std.testing.allocator.free(military);
    try std.testing.expectEqual(@as(usize, 2), military.len);

    const era1 = try tree.getTechsByEra(1, std.testing.allocator);
    defer std.testing.allocator.free(era1);
    try std.testing.expectEqual(@as(usize, 2), era1.len);
}

test "TechTree - reset tech" {
    var tree = TechTree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.addTech(.{ .id = "mining", .cost = 100 });
    try tree.addTech(.{
        .id = "advanced",
        .cost = 100,
        .prerequisites = &.{"mining"},
    });

    _ = tree.forceComplete("mining");
    try std.testing.expectEqual(TechState.available, tree.getState("advanced").?);

    _ = tree.resetTech("mining");
    try std.testing.expectEqual(TechState.available, tree.getState("mining").?);
    try std.testing.expectEqual(TechState.locked, tree.getState("advanced").?);
}

test "TechTree - reset all" {
    var tree = TechTree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.addTech(.{ .id = "tech1", .cost = 100 });
    try tree.addTech(.{ .id = "tech2", .cost = 100 });

    _ = tree.forceComplete("tech1");
    _ = tree.forceComplete("tech2");

    try std.testing.expectEqual(@as(usize, 2), tree.getResearchedCount());

    tree.resetAll();

    try std.testing.expectEqual(@as(usize, 0), tree.getResearchedCount());
    try std.testing.expectEqual(@as(usize, 2), tree.getTechCount());
}

test "TechTree - callback on complete" {
    var tree = TechTree.init(std.testing.allocator);
    defer tree.deinit();

    var completed_id: ?[]const u8 = null;
    const callback = struct {
        fn cb(id: []const u8, ctx: ?*anyopaque) void {
            const ptr: *?[]const u8 = @ptrCast(@alignCast(ctx));
            ptr.* = id;
        }
    }.cb;

    tree.setOnComplete(callback, &completed_id);

    try tree.addTech(.{ .id = "mining", .cost = 100 });
    _ = tree.startResearch("mining");
    _ = tree.addProgress(100);

    try std.testing.expect(completed_id != null);
    try std.testing.expectEqualStrings("mining", completed_id.?);
}

test "TechTree - queue limit" {
    var tree = TechTree.init(std.testing.allocator);
    defer tree.deinit();

    tree.setMaxQueueSize(2);

    try tree.addTech(.{ .id = "tech1", .cost = 100 });
    try tree.addTech(.{ .id = "tech2", .cost = 100 });
    try tree.addTech(.{ .id = "tech3", .cost = 100 });
    try tree.addTech(.{ .id = "tech4", .cost = 100 });

    _ = tree.startResearch("tech1");
    try std.testing.expectEqual(ResearchResult.success, tree.queueResearch("tech2"));
    try std.testing.expectEqual(ResearchResult.success, tree.queueResearch("tech3"));
    try std.testing.expectEqual(ResearchResult.queue_full, tree.queueResearch("tech4"));
}

test "TechTree - get tech info" {
    var tree = TechTree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.addTech(.{
        .id = "mining",
        .name = "Mining Technology",
        .description = "Allows mining resources",
        .cost = 150,
        .category = "economy",
        .era = 1,
    });

    const info = tree.getTechInfo("mining").?;
    try std.testing.expectEqualStrings("mining", info.id);
    try std.testing.expectEqualStrings("Mining Technology", info.name);
    try std.testing.expectEqual(@as(u32, 150), info.cost);
    try std.testing.expectEqual(@as(u8, 1), info.era);
}

test "TechTree - already researched" {
    var tree = TechTree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.addTech(.{ .id = "mining", .cost = 100 });

    _ = tree.forceComplete("mining");

    try std.testing.expectEqual(ResearchResult.already_researched, tree.startResearch("mining"));
}

test "TechTree - not found" {
    var tree = TechTree.init(std.testing.allocator);
    defer tree.deinit();

    try std.testing.expectEqual(ResearchResult.not_found, tree.startResearch("nonexistent"));
    try std.testing.expect(tree.getState("nonexistent") == null);
}

test "TechTree - no prerequisites means available" {
    var tree = TechTree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.addTech(.{ .id = "basic", .cost = 100 });

    // Should be immediately available
    try std.testing.expectEqual(TechState.available, tree.getState("basic").?);
    try std.testing.expect(tree.prerequisitesMet("basic"));
}

test "TechTree - chain of prerequisites" {
    var tree = TechTree.init(std.testing.allocator);
    defer tree.deinit();

    try tree.addTech(.{ .id = "tier1", .cost = 100 });
    try tree.addTech(.{ .id = "tier2", .cost = 100, .prerequisites = &.{"tier1"} });
    try tree.addTech(.{ .id = "tier3", .cost = 100, .prerequisites = &.{"tier2"} });
    try tree.addTech(.{ .id = "tier4", .cost = 100, .prerequisites = &.{"tier3"} });

    try std.testing.expectEqual(TechState.available, tree.getState("tier1").?);
    try std.testing.expectEqual(TechState.locked, tree.getState("tier2").?);
    try std.testing.expectEqual(TechState.locked, tree.getState("tier3").?);
    try std.testing.expectEqual(TechState.locked, tree.getState("tier4").?);

    // Complete the chain
    _ = tree.forceComplete("tier1");
    try std.testing.expectEqual(TechState.available, tree.getState("tier2").?);

    _ = tree.forceComplete("tier2");
    try std.testing.expectEqual(TechState.available, tree.getState("tier3").?);

    _ = tree.forceComplete("tier3");
    try std.testing.expectEqual(TechState.available, tree.getState("tier4").?);
}
