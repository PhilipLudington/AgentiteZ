//! Crafting/Recipe System - Production Pipeline Management
//!
//! A crafting system for factory/survival games where machines transform
//! input resources into output resources over time.
//!
//! Features:
//! - Recipe definitions with multiple inputs and outputs
//! - Crafting time with progress tracking
//! - Byproduct handling (secondary outputs)
//! - Recipe unlocking/research integration
//! - Crafting queues per machine
//! - Batch crafting support
//! - Crafting speed modifiers
//! - Resource availability validation
//!
//! Usage:
//! ```zig
//! const Resource = enum { iron_ore, coal, iron_plate, slag };
//!
//! var crafting = CraftingSystem(Resource).init(allocator);
//! defer crafting.deinit();
//!
//! try crafting.addRecipe("smelt_iron", .{
//!     .inputs = &.{ .{ .iron_ore, 2 }, .{ .coal, 1 } },
//!     .outputs = &.{ .{ .iron_plate, 1 } },
//!     .byproducts = &.{ .{ .slag, 1 } },
//!     .craft_time = 3.0,
//! });
//!
//! if (crafting.canCraft("smelt_iron", &inventory)) {
//!     try crafting.startCrafting(machine_id, "smelt_iron", &inventory);
//! }
//!
//! crafting.update(delta_time);
//! ```

const std = @import("std");

/// Crafting status
pub const CraftingStatus = enum {
    /// Not currently crafting
    idle,
    /// Waiting for resources
    waiting,
    /// Currently crafting
    crafting,
    /// Finished, ready to collect
    complete,
    /// Blocked (output full)
    blocked,
    /// Recipe not unlocked
    locked,
};

/// A single resource amount (type + quantity)
pub fn ResourceAmount(comptime ResourceType: type) type {
    return struct {
        resource: ResourceType,
        amount: f64,
    };
}

/// Recipe definition
pub fn Recipe(comptime ResourceType: type) type {
    return struct {
        const Self = @This();

        /// Unique recipe identifier
        id: []const u8,
        /// Display name (optional)
        name: ?[]const u8 = null,
        /// Category for UI grouping
        category: ?[]const u8 = null,

        /// Required inputs
        inputs: []const ResourceAmount(ResourceType),
        /// Primary outputs
        outputs: []const ResourceAmount(ResourceType),
        /// Secondary outputs (always produced)
        byproducts: []const ResourceAmount(ResourceType) = &.{},

        /// Time to craft (seconds)
        craft_time: f64 = 1.0,
        /// Base energy consumption
        energy_cost: f64 = 0,

        /// Whether this recipe is unlocked by default
        unlocked_by_default: bool = true,
        /// Tech ID required to unlock (if any)
        required_tech: ?[]const u8 = null,

        /// Check if recipe produces a specific resource
        pub fn produces(self: *const Self, resource: ResourceType) bool {
            for (self.outputs) |output| {
                if (output.resource == resource) return true;
            }
            for (self.byproducts) |bp| {
                if (bp.resource == resource) return true;
            }
            return false;
        }

        /// Check if recipe consumes a specific resource
        pub fn consumes(self: *const Self, resource: ResourceType) bool {
            for (self.inputs) |input| {
                if (input.resource == resource) return true;
            }
            return false;
        }

        /// Get output amount for a resource (0 if not produced)
        pub fn getOutputAmount(self: *const Self, resource: ResourceType) f64 {
            for (self.outputs) |output| {
                if (output.resource == resource) return output.amount;
            }
            return 0;
        }

        /// Get input amount for a resource (0 if not consumed)
        pub fn getInputAmount(self: *const Self, resource: ResourceType) f64 {
            for (self.inputs) |input| {
                if (input.resource == resource) return input.amount;
            }
            return 0;
        }
    };
}

/// Active crafting job
pub fn CraftingJob(comptime ResourceType: type) type {
    return struct {
        /// Recipe being crafted
        recipe_id: []const u8,
        /// Current progress (0.0 to 1.0)
        progress: f64 = 0,
        /// Number of items to craft
        batch_count: u32 = 1,
        /// Items completed in batch
        completed_count: u32 = 0,
        /// Speed modifier (1.0 = normal)
        speed_modifier: f64 = 1.0,
        /// Status
        status: CraftingStatus = .crafting,
        /// Cached inputs already consumed
        inputs_consumed: bool = false,

        /// Calculate remaining time
        pub fn getRemainingTime(self: *const @This(), recipe: *const Recipe(ResourceType)) f64 {
            const remaining_progress = 1.0 - self.progress;
            const remaining_items = self.batch_count - self.completed_count;
            const adjusted_time = recipe.craft_time / self.speed_modifier;
            return remaining_progress * adjusted_time + @as(f64, @floatFromInt(remaining_items -| 1)) * adjusted_time;
        }
    };
}

/// Crafting queue entry
pub fn QueueEntry(comptime ResourceType: type) type {
    _ = ResourceType;
    return struct {
        recipe_id: []const u8,
        batch_count: u32 = 1,
    };
}

/// Generic inventory interface for resource checking
pub fn InventoryInterface(comptime ResourceType: type) type {
    return struct {
        ptr: *anyopaque,
        has_fn: *const fn (*anyopaque, ResourceType, f64) bool,
        remove_fn: *const fn (*anyopaque, ResourceType, f64) bool,
        add_fn: *const fn (*anyopaque, ResourceType, f64) bool,
        can_accept_fn: ?*const fn (*anyopaque, ResourceType, f64) bool,

        const Self = @This();

        pub fn has(self: Self, resource: ResourceType, amount: f64) bool {
            return self.has_fn(self.ptr, resource, amount);
        }

        pub fn remove(self: Self, resource: ResourceType, amount: f64) bool {
            return self.remove_fn(self.ptr, resource, amount);
        }

        pub fn add(self: Self, resource: ResourceType, amount: f64) bool {
            return self.add_fn(self.ptr, resource, amount);
        }

        pub fn canAccept(self: Self, resource: ResourceType, amount: f64) bool {
            if (self.can_accept_fn) |func| {
                return func(self.ptr, resource, amount);
            }
            return true; // Assume infinite capacity if not specified
        }
    };
}

/// Crafting system
pub fn CraftingSystem(comptime ResourceType: type) type {
    return struct {
        const Self = @This();
        const RecipeType = Recipe(ResourceType);
        const JobType = CraftingJob(ResourceType);
        const QueueType = QueueEntry(ResourceType);

        allocator: std.mem.Allocator,

        /// All registered recipes
        recipes: std.StringHashMap(RecipeType),

        /// Unlocked recipes (by ID)
        unlocked: std.StringHashMap(void),

        /// Active crafting jobs per machine (by entity ID)
        active_jobs: std.AutoHashMap(u32, JobType),

        /// Crafting queues per machine
        queues: std.AutoHashMap(u32, std.ArrayList(QueueType)),

        /// Completion callback (entity_id, recipe_id)
        on_complete: ?*const fn (u32, []const u8) void = null,

        /// Initialize the crafting system
        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .recipes = std.StringHashMap(RecipeType).init(allocator),
                .unlocked = std.StringHashMap(void).init(allocator),
                .active_jobs = std.AutoHashMap(u32, JobType).init(allocator),
                .queues = std.AutoHashMap(u32, std.ArrayList(QueueType)).init(allocator),
            };
        }

        /// Clean up resources
        pub fn deinit(self: *Self) void {
            self.recipes.deinit();
            self.unlocked.deinit();
            self.active_jobs.deinit();

            var queue_iter = self.queues.valueIterator();
            while (queue_iter.next()) |queue| {
                queue.deinit();
            }
            self.queues.deinit();
        }

        // ====== Recipe Management ======

        /// Add a recipe to the system
        pub fn addRecipe(self: *Self, id: []const u8, recipe: RecipeType) !void {
            var r = recipe;
            r.id = id;
            try self.recipes.put(id, r);

            // Auto-unlock if default
            if (recipe.unlocked_by_default) {
                try self.unlocked.put(id, {});
            }
        }

        /// Get a recipe by ID
        pub fn getRecipe(self: *const Self, id: []const u8) ?*const RecipeType {
            if (self.recipes.getPtr(id)) |ptr| {
                return ptr;
            }
            return null;
        }

        /// Check if a recipe is unlocked
        pub fn isUnlocked(self: *const Self, recipe_id: []const u8) bool {
            return self.unlocked.contains(recipe_id);
        }

        /// Unlock a recipe
        pub fn unlock(self: *Self, recipe_id: []const u8) !void {
            if (self.recipes.contains(recipe_id)) {
                try self.unlocked.put(recipe_id, {});
            }
        }

        /// Lock a recipe
        pub fn lock(self: *Self, recipe_id: []const u8) void {
            _ = self.unlocked.remove(recipe_id);
        }

        /// Get all recipes
        pub fn getAllRecipes(self: *const Self, allocator: std.mem.Allocator) ![]const RecipeType {
            var list = std.ArrayList(RecipeType).init(allocator);
            var iter = self.recipes.iterator();
            while (iter.next()) |entry| {
                try list.append(entry.value_ptr.*);
            }
            return list.toOwnedSlice();
        }

        /// Get unlocked recipes
        pub fn getUnlockedRecipes(self: *const Self, allocator: std.mem.Allocator) ![]const RecipeType {
            var list = std.ArrayList(RecipeType).init(allocator);
            var iter = self.unlocked.keyIterator();
            while (iter.next()) |key| {
                if (self.recipes.get(key.*)) |recipe| {
                    try list.append(recipe);
                }
            }
            return list.toOwnedSlice();
        }

        /// Get recipes by category
        pub fn getRecipesByCategory(self: *const Self, category: []const u8, allocator: std.mem.Allocator) ![]const RecipeType {
            var list = std.ArrayList(RecipeType).init(allocator);
            var iter = self.recipes.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.category) |cat| {
                    if (std.mem.eql(u8, cat, category)) {
                        try list.append(entry.value_ptr.*);
                    }
                }
            }
            return list.toOwnedSlice();
        }

        /// Find recipes that produce a specific resource
        pub fn findRecipesProducing(self: *const Self, resource: ResourceType, allocator: std.mem.Allocator) ![]const RecipeType {
            var list = std.ArrayList(RecipeType).init(allocator);
            var iter = self.recipes.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.produces(resource)) {
                    try list.append(entry.value_ptr.*);
                }
            }
            return list.toOwnedSlice();
        }

        /// Find recipes that consume a specific resource
        pub fn findRecipesConsuming(self: *const Self, resource: ResourceType, allocator: std.mem.Allocator) ![]const RecipeType {
            var list = std.ArrayList(RecipeType).init(allocator);
            var iter = self.recipes.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.consumes(resource)) {
                    try list.append(entry.value_ptr.*);
                }
            }
            return list.toOwnedSlice();
        }

        // ====== Crafting Validation ======

        /// Check if a recipe can be crafted with given inventory
        pub fn canCraft(self: *const Self, recipe_id: []const u8, inventory: InventoryInterface(ResourceType)) bool {
            const recipe = self.getRecipe(recipe_id) orelse return false;
            if (!self.isUnlocked(recipe_id)) return false;

            // Check all inputs
            for (recipe.inputs) |input| {
                if (!inventory.has(input.resource, input.amount)) {
                    return false;
                }
            }

            return true;
        }

        /// Check if outputs can be stored
        pub fn canStoreOutputs(self: *const Self, recipe_id: []const u8, inventory: InventoryInterface(ResourceType)) bool {
            const recipe = self.getRecipe(recipe_id) orelse return false;

            // Check all outputs
            for (recipe.outputs) |output| {
                if (!inventory.canAccept(output.resource, output.amount)) {
                    return false;
                }
            }

            // Check byproducts
            for (recipe.byproducts) |bp| {
                if (!inventory.canAccept(bp.resource, bp.amount)) {
                    return false;
                }
            }

            return true;
        }

        /// Count how many times a recipe can be crafted
        pub fn countCraftable(self: *const Self, recipe_id: []const u8, inventory: InventoryInterface(ResourceType), max_check: u32) u32 {
            const recipe = self.getRecipe(recipe_id) orelse return 0;
            if (!self.isUnlocked(recipe_id)) return 0;

            var count: u32 = max_check;
            for (recipe.inputs) |input| {
                // Calculate how many times we can use this input
                // Note: This requires the inventory to report amounts, not just has()
                // For simplicity, we'll iterate down from max_check
                var test_count: u32 = 0;
                while (test_count < count) : (test_count += 1) {
                    const needed = input.amount * @as(f64, @floatFromInt(test_count + 1));
                    if (!inventory.has(input.resource, needed)) {
                        count = test_count;
                        break;
                    }
                }
            }

            return count;
        }

        // ====== Crafting Operations ======

        /// Start crafting a recipe
        pub fn startCrafting(self: *Self, entity_id: u32, recipe_id: []const u8, inventory: InventoryInterface(ResourceType)) !bool {
            return self.startCraftingBatch(entity_id, recipe_id, 1, inventory);
        }

        /// Start crafting a batch
        pub fn startCraftingBatch(self: *Self, entity_id: u32, recipe_id: []const u8, count: u32, inventory: InventoryInterface(ResourceType)) !bool {
            if (count == 0) return false;

            // Check if already crafting
            if (self.active_jobs.contains(entity_id)) {
                return false;
            }

            const recipe = self.getRecipe(recipe_id) orelse return false;
            if (!self.isUnlocked(recipe_id)) return false;

            // Consume inputs for first item
            for (recipe.inputs) |input| {
                if (!inventory.remove(input.resource, input.amount)) {
                    return false;
                }
            }

            // Create job
            try self.active_jobs.put(entity_id, .{
                .recipe_id = recipe_id,
                .batch_count = count,
                .inputs_consumed = true,
            });

            return true;
        }

        /// Cancel crafting (returns resources if not complete)
        pub fn cancelCrafting(self: *Self, entity_id: u32, inventory: ?InventoryInterface(ResourceType)) bool {
            const job = self.active_jobs.get(entity_id) orelse return false;

            // Return resources if inputs were consumed and not complete
            if (inventory) |inv| {
                if (job.inputs_consumed and job.progress < 1.0) {
                    if (self.getRecipe(job.recipe_id)) |recipe| {
                        for (recipe.inputs) |input| {
                            _ = inv.add(input.resource, input.amount);
                        }
                    }
                }
            }

            _ = self.active_jobs.remove(entity_id);
            return true;
        }

        /// Update crafting progress
        pub fn update(self: *Self, delta_time: f64) void {
            var completed = std.ArrayList(u32).init(self.allocator);
            defer completed.deinit();

            var iter = self.active_jobs.iterator();
            while (iter.next()) |entry| {
                const entity_id = entry.key_ptr.*;
                const job = entry.value_ptr;

                if (job.status != .crafting) continue;

                const recipe = self.getRecipe(job.recipe_id) orelse continue;

                // Update progress
                const progress_rate = job.speed_modifier / recipe.craft_time;
                job.progress += progress_rate * delta_time;

                if (job.progress >= 1.0) {
                    job.progress = 1.0;
                    job.status = .complete;
                    completed.append(entity_id) catch {};
                }
            }

            // Notify completions
            if (self.on_complete) |callback| {
                for (completed.items) |entity_id| {
                    if (self.active_jobs.get(entity_id)) |job| {
                        callback(entity_id, job.recipe_id);
                    }
                }
            }
        }

        /// Collect completed crafting outputs
        pub fn collectOutputs(self: *Self, entity_id: u32, inventory: InventoryInterface(ResourceType)) bool {
            const job_ptr = self.active_jobs.getPtr(entity_id) orelse return false;

            if (job_ptr.status != .complete) return false;

            const recipe = self.getRecipe(job_ptr.recipe_id) orelse return false;

            // Check if outputs can be stored
            for (recipe.outputs) |output| {
                if (!inventory.canAccept(output.resource, output.amount)) {
                    job_ptr.status = .blocked;
                    return false;
                }
            }
            for (recipe.byproducts) |bp| {
                if (!inventory.canAccept(bp.resource, bp.amount)) {
                    job_ptr.status = .blocked;
                    return false;
                }
            }

            // Add outputs
            for (recipe.outputs) |output| {
                _ = inventory.add(output.resource, output.amount);
            }
            for (recipe.byproducts) |bp| {
                _ = inventory.add(bp.resource, bp.amount);
            }

            job_ptr.completed_count += 1;

            // Check if batch complete
            if (job_ptr.completed_count >= job_ptr.batch_count) {
                _ = self.active_jobs.remove(entity_id);
            } else {
                // Start next item in batch - would need inventory for inputs
                job_ptr.progress = 0;
                job_ptr.status = .waiting; // Need resources for next item
                job_ptr.inputs_consumed = false;
            }

            return true;
        }

        /// Continue a batch (consume inputs for next item)
        pub fn continueBatch(self: *Self, entity_id: u32, inventory: InventoryInterface(ResourceType)) bool {
            const job_ptr = self.active_jobs.getPtr(entity_id) orelse return false;

            if (job_ptr.status != .waiting) return false;
            if (job_ptr.inputs_consumed) return false;

            const recipe = self.getRecipe(job_ptr.recipe_id) orelse return false;

            // Consume inputs
            for (recipe.inputs) |input| {
                if (!inventory.remove(input.resource, input.amount)) {
                    return false;
                }
            }

            job_ptr.inputs_consumed = true;
            job_ptr.status = .crafting;
            return true;
        }

        // ====== Job Queries ======

        /// Get current crafting job for an entity
        pub fn getJob(self: *const Self, entity_id: u32) ?JobType {
            return self.active_jobs.get(entity_id);
        }

        /// Check if entity is currently crafting
        pub fn isCrafting(self: *const Self, entity_id: u32) bool {
            return self.active_jobs.contains(entity_id);
        }

        /// Get crafting status for an entity
        pub fn getStatus(self: *const Self, entity_id: u32) CraftingStatus {
            if (self.active_jobs.get(entity_id)) |job| {
                return job.status;
            }
            return .idle;
        }

        /// Get crafting progress (0.0 to 1.0)
        pub fn getProgress(self: *const Self, entity_id: u32) f64 {
            if (self.active_jobs.get(entity_id)) |job| {
                return job.progress;
            }
            return 0;
        }

        /// Get recipe being crafted
        pub fn getCurrentRecipe(self: *const Self, entity_id: u32) ?*const RecipeType {
            if (self.active_jobs.get(entity_id)) |job| {
                return self.getRecipe(job.recipe_id);
            }
            return null;
        }

        /// Set speed modifier for a crafting job
        pub fn setSpeedModifier(self: *Self, entity_id: u32, modifier: f64) bool {
            if (self.active_jobs.getPtr(entity_id)) |job| {
                job.speed_modifier = @max(0.01, modifier);
                return true;
            }
            return false;
        }

        // ====== Queue Operations ======

        /// Add recipe to crafting queue
        pub fn queueRecipe(self: *Self, entity_id: u32, recipe_id: []const u8, count: u32) !void {
            if (!self.recipes.contains(recipe_id)) return error.RecipeNotFound;

            const result = try self.queues.getOrPut(entity_id);
            if (!result.found_existing) {
                result.value_ptr.* = std.ArrayList(QueueType).init(self.allocator);
            }

            try result.value_ptr.append(.{
                .recipe_id = recipe_id,
                .batch_count = count,
            });
        }

        /// Get queue for an entity
        pub fn getQueue(self: *const Self, entity_id: u32) ?[]const QueueType {
            if (self.queues.get(entity_id)) |queue| {
                return queue.items;
            }
            return null;
        }

        /// Clear queue for an entity
        pub fn clearQueue(self: *Self, entity_id: u32) void {
            if (self.queues.getPtr(entity_id)) |queue| {
                queue.clearRetainingCapacity();
            }
        }

        /// Process queue - start next recipe if idle
        pub fn processQueue(self: *Self, entity_id: u32, inventory: InventoryInterface(ResourceType)) bool {
            // Only process if not currently crafting
            if (self.isCrafting(entity_id)) return false;

            const queue = self.queues.getPtr(entity_id) orelse return false;
            if (queue.items.len == 0) return false;

            const next = queue.items[0];

            // Try to start crafting
            if (self.startCraftingBatch(entity_id, next.recipe_id, next.batch_count, inventory) catch false) {
                _ = queue.orderedRemove(0);
                return true;
            }

            return false;
        }

        // ====== Statistics ======

        /// Count active crafting jobs
        pub fn getActiveJobCount(self: *const Self) usize {
            return self.active_jobs.count();
        }

        /// Count registered recipes
        pub fn getRecipeCount(self: *const Self) usize {
            return self.recipes.count();
        }

        /// Count unlocked recipes
        pub fn getUnlockedCount(self: *const Self) usize {
            return self.unlocked.count();
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

const TestResource = enum { iron_ore, coal, iron_plate, steel, slag, copper_ore, copper_plate, wire };

// Simple test inventory
const TestInventory = struct {
    amounts: std.AutoHashMap(TestResource, f64),
    capacity: f64 = 1000,

    fn init(allocator: std.mem.Allocator) TestInventory {
        return .{ .amounts = std.AutoHashMap(TestResource, f64).init(allocator) };
    }

    fn deinit(self: *TestInventory) void {
        self.amounts.deinit();
    }

    fn set(self: *TestInventory, resource: TestResource, amount: f64) void {
        self.amounts.put(resource, amount) catch {};
    }

    fn get(self: *const TestInventory, resource: TestResource) f64 {
        return self.amounts.get(resource) orelse 0;
    }

    fn interface(self: *TestInventory) InventoryInterface(TestResource) {
        return .{
            .ptr = self,
            .has_fn = &hasImpl,
            .remove_fn = &removeImpl,
            .add_fn = &addImpl,
            .can_accept_fn = &canAcceptImpl,
        };
    }

    fn hasImpl(ptr: *anyopaque, resource: TestResource, amount: f64) bool {
        const self: *TestInventory = @ptrCast(@alignCast(ptr));
        return self.get(resource) >= amount;
    }

    fn removeImpl(ptr: *anyopaque, resource: TestResource, amount: f64) bool {
        const self: *TestInventory = @ptrCast(@alignCast(ptr));
        const current = self.get(resource);
        if (current < amount) return false;
        self.set(resource, current - amount);
        return true;
    }

    fn addImpl(ptr: *anyopaque, resource: TestResource, amount: f64) bool {
        const self: *TestInventory = @ptrCast(@alignCast(ptr));
        const current = self.get(resource);
        self.set(resource, current + amount);
        return true;
    }

    fn canAcceptImpl(ptr: *anyopaque, resource: TestResource, amount: f64) bool {
        const self: *TestInventory = @ptrCast(@alignCast(ptr));
        return self.get(resource) + amount <= self.capacity;
    }
};

test "CraftingSystem - init and deinit" {
    var crafting = CraftingSystem(TestResource).init(std.testing.allocator);
    defer crafting.deinit();

    try std.testing.expectEqual(@as(usize, 0), crafting.getRecipeCount());
}

test "CraftingSystem - add recipe" {
    var crafting = CraftingSystem(TestResource).init(std.testing.allocator);
    defer crafting.deinit();

    try crafting.addRecipe("smelt_iron", .{
        .id = undefined,
        .inputs = &.{.{ .resource = .iron_ore, .amount = 2 }},
        .outputs = &.{.{ .resource = .iron_plate, .amount = 1 }},
        .craft_time = 3.0,
    });

    try std.testing.expectEqual(@as(usize, 1), crafting.getRecipeCount());
    try std.testing.expect(crafting.getRecipe("smelt_iron") != null);
    try std.testing.expect(crafting.isUnlocked("smelt_iron"));
}

test "CraftingSystem - recipe locked by default" {
    var crafting = CraftingSystem(TestResource).init(std.testing.allocator);
    defer crafting.deinit();

    try crafting.addRecipe("advanced", .{
        .id = undefined,
        .inputs = &.{},
        .outputs = &.{},
        .unlocked_by_default = false,
    });

    try std.testing.expect(!crafting.isUnlocked("advanced"));

    try crafting.unlock("advanced");
    try std.testing.expect(crafting.isUnlocked("advanced"));
}

test "CraftingSystem - can craft check" {
    var crafting = CraftingSystem(TestResource).init(std.testing.allocator);
    defer crafting.deinit();

    var inv = TestInventory.init(std.testing.allocator);
    defer inv.deinit();

    try crafting.addRecipe("smelt_iron", .{
        .id = undefined,
        .inputs = &.{.{ .resource = .iron_ore, .amount = 2 }},
        .outputs = &.{.{ .resource = .iron_plate, .amount = 1 }},
    });

    // No resources
    try std.testing.expect(!crafting.canCraft("smelt_iron", inv.interface()));

    // Add resources
    inv.set(.iron_ore, 5);
    try std.testing.expect(crafting.canCraft("smelt_iron", inv.interface()));
}

test "CraftingSystem - start and complete crafting" {
    var crafting = CraftingSystem(TestResource).init(std.testing.allocator);
    defer crafting.deinit();

    var inv = TestInventory.init(std.testing.allocator);
    defer inv.deinit();

    try crafting.addRecipe("smelt_iron", .{
        .id = undefined,
        .inputs = &.{.{ .resource = .iron_ore, .amount = 2 }},
        .outputs = &.{.{ .resource = .iron_plate, .amount = 1 }},
        .craft_time = 1.0,
    });

    inv.set(.iron_ore, 10);

    // Start crafting
    try std.testing.expect(try crafting.startCrafting(1, "smelt_iron", inv.interface()));
    try std.testing.expectEqual(@as(f64, 8), inv.get(.iron_ore)); // Consumed 2

    // Check status
    try std.testing.expect(crafting.isCrafting(1));
    try std.testing.expectEqual(CraftingStatus.crafting, crafting.getStatus(1));

    // Update to completion
    crafting.update(1.0);
    try std.testing.expectEqual(CraftingStatus.complete, crafting.getStatus(1));

    // Collect outputs
    try std.testing.expect(crafting.collectOutputs(1, inv.interface()));
    try std.testing.expectEqual(@as(f64, 1), inv.get(.iron_plate));
    try std.testing.expect(!crafting.isCrafting(1));
}

test "CraftingSystem - progress tracking" {
    var crafting = CraftingSystem(TestResource).init(std.testing.allocator);
    defer crafting.deinit();

    var inv = TestInventory.init(std.testing.allocator);
    defer inv.deinit();

    try crafting.addRecipe("slow", .{
        .id = undefined,
        .inputs = &.{},
        .outputs = &.{},
        .craft_time = 10.0,
    });

    _ = try crafting.startCrafting(1, "slow", inv.interface());

    crafting.update(2.5);
    try std.testing.expectApproxEqAbs(@as(f64, 0.25), crafting.getProgress(1), 0.01);

    crafting.update(2.5);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), crafting.getProgress(1), 0.01);
}

test "CraftingSystem - speed modifier" {
    var crafting = CraftingSystem(TestResource).init(std.testing.allocator);
    defer crafting.deinit();

    var inv = TestInventory.init(std.testing.allocator);
    defer inv.deinit();

    try crafting.addRecipe("fast", .{
        .id = undefined,
        .inputs = &.{},
        .outputs = &.{},
        .craft_time = 10.0,
    });

    _ = try crafting.startCrafting(1, "fast", inv.interface());
    _ = crafting.setSpeedModifier(1, 2.0); // 2x speed

    crafting.update(2.5);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), crafting.getProgress(1), 0.01); // 2x progress
}

test "CraftingSystem - byproducts" {
    var crafting = CraftingSystem(TestResource).init(std.testing.allocator);
    defer crafting.deinit();

    var inv = TestInventory.init(std.testing.allocator);
    defer inv.deinit();

    try crafting.addRecipe("smelt_with_slag", .{
        .id = undefined,
        .inputs = &.{.{ .resource = .iron_ore, .amount = 2 }},
        .outputs = &.{.{ .resource = .iron_plate, .amount = 1 }},
        .byproducts = &.{.{ .resource = .slag, .amount = 1 }},
        .craft_time = 0.1,
    });

    inv.set(.iron_ore, 10);

    _ = try crafting.startCrafting(1, "smelt_with_slag", inv.interface());
    crafting.update(1.0);
    _ = crafting.collectOutputs(1, inv.interface());

    try std.testing.expectEqual(@as(f64, 1), inv.get(.iron_plate));
    try std.testing.expectEqual(@as(f64, 1), inv.get(.slag));
}

test "CraftingSystem - cancel crafting returns resources" {
    var crafting = CraftingSystem(TestResource).init(std.testing.allocator);
    defer crafting.deinit();

    var inv = TestInventory.init(std.testing.allocator);
    defer inv.deinit();

    try crafting.addRecipe("smelt", .{
        .id = undefined,
        .inputs = &.{.{ .resource = .iron_ore, .amount = 2 }},
        .outputs = &.{.{ .resource = .iron_plate, .amount = 1 }},
        .craft_time = 10.0,
    });

    inv.set(.iron_ore, 10);

    _ = try crafting.startCrafting(1, "smelt", inv.interface());
    try std.testing.expectEqual(@as(f64, 8), inv.get(.iron_ore));

    // Cancel before completion
    _ = crafting.cancelCrafting(1, inv.interface());
    try std.testing.expectEqual(@as(f64, 10), inv.get(.iron_ore)); // Returned
    try std.testing.expect(!crafting.isCrafting(1));
}

test "CraftingSystem - cannot start while crafting" {
    var crafting = CraftingSystem(TestResource).init(std.testing.allocator);
    defer crafting.deinit();

    var inv = TestInventory.init(std.testing.allocator);
    defer inv.deinit();

    try crafting.addRecipe("test", .{
        .id = undefined,
        .inputs = &.{},
        .outputs = &.{},
        .craft_time = 10.0,
    });

    _ = try crafting.startCrafting(1, "test", inv.interface());
    try std.testing.expect(!(try crafting.startCrafting(1, "test", inv.interface())));
}

test "CraftingSystem - recipe produces/consumes" {
    var crafting = CraftingSystem(TestResource).init(std.testing.allocator);
    defer crafting.deinit();

    try crafting.addRecipe("smelt", .{
        .id = undefined,
        .inputs = &.{.{ .resource = .iron_ore, .amount = 2 }},
        .outputs = &.{.{ .resource = .iron_plate, .amount = 1 }},
        .byproducts = &.{.{ .resource = .slag, .amount = 1 }},
    });

    const recipe = crafting.getRecipe("smelt").?;

    try std.testing.expect(recipe.produces(.iron_plate));
    try std.testing.expect(recipe.produces(.slag));
    try std.testing.expect(!recipe.produces(.iron_ore));

    try std.testing.expect(recipe.consumes(.iron_ore));
    try std.testing.expect(!recipe.consumes(.iron_plate));
}

test "CraftingSystem - find recipes" {
    var crafting = CraftingSystem(TestResource).init(std.testing.allocator);
    defer crafting.deinit();

    try crafting.addRecipe("iron", .{
        .id = undefined,
        .inputs = &.{.{ .resource = .iron_ore, .amount = 1 }},
        .outputs = &.{.{ .resource = .iron_plate, .amount = 1 }},
    });

    try crafting.addRecipe("copper", .{
        .id = undefined,
        .inputs = &.{.{ .resource = .copper_ore, .amount = 1 }},
        .outputs = &.{.{ .resource = .copper_plate, .amount = 1 }},
    });

    const producing_iron = try crafting.findRecipesProducing(.iron_plate, std.testing.allocator);
    defer std.testing.allocator.free(producing_iron);
    try std.testing.expectEqual(@as(usize, 1), producing_iron.len);

    const consuming_ore = try crafting.findRecipesConsuming(.iron_ore, std.testing.allocator);
    defer std.testing.allocator.free(consuming_ore);
    try std.testing.expectEqual(@as(usize, 1), consuming_ore.len);
}

test "CraftingSystem - queue operations" {
    var crafting = CraftingSystem(TestResource).init(std.testing.allocator);
    defer crafting.deinit();

    try crafting.addRecipe("test", .{
        .id = undefined,
        .inputs = &.{},
        .outputs = &.{},
    });

    try crafting.queueRecipe(1, "test", 3);
    try crafting.queueRecipe(1, "test", 5);

    const queue = crafting.getQueue(1).?;
    try std.testing.expectEqual(@as(usize, 2), queue.len);
    try std.testing.expectEqual(@as(u32, 3), queue[0].batch_count);
}

test "CraftingSystem - count craftable" {
    var crafting = CraftingSystem(TestResource).init(std.testing.allocator);
    defer crafting.deinit();

    var inv = TestInventory.init(std.testing.allocator);
    defer inv.deinit();

    try crafting.addRecipe("smelt", .{
        .id = undefined,
        .inputs = &.{.{ .resource = .iron_ore, .amount = 2 }},
        .outputs = &.{.{ .resource = .iron_plate, .amount = 1 }},
    });

    inv.set(.iron_ore, 7);

    const count = crafting.countCraftable("smelt", inv.interface(), 100);
    try std.testing.expectEqual(@as(u32, 3), count); // 7 / 2 = 3 times
}

test "CraftingSystem - batch crafting" {
    var crafting = CraftingSystem(TestResource).init(std.testing.allocator);
    defer crafting.deinit();

    var inv = TestInventory.init(std.testing.allocator);
    defer inv.deinit();

    try crafting.addRecipe("fast", .{
        .id = undefined,
        .inputs = &.{.{ .resource = .iron_ore, .amount = 1 }},
        .outputs = &.{.{ .resource = .iron_plate, .amount = 1 }},
        .craft_time = 0.1,
    });

    inv.set(.iron_ore, 10);

    // Start batch of 3
    _ = try crafting.startCraftingBatch(1, "fast", 3, inv.interface());
    try std.testing.expectEqual(@as(f64, 9), inv.get(.iron_ore)); // First item consumed

    // Complete first
    crafting.update(1.0);
    _ = crafting.collectOutputs(1, inv.interface());
    try std.testing.expectEqual(@as(f64, 1), inv.get(.iron_plate));

    // Should be waiting for next item
    try std.testing.expectEqual(CraftingStatus.waiting, crafting.getStatus(1));

    // Continue batch
    try std.testing.expect(crafting.continueBatch(1, inv.interface()));
    try std.testing.expectEqual(@as(f64, 8), inv.get(.iron_ore));
    try std.testing.expectEqual(CraftingStatus.crafting, crafting.getStatus(1));
}

test "CraftingSystem - lock and unlock" {
    var crafting = CraftingSystem(TestResource).init(std.testing.allocator);
    defer crafting.deinit();

    try crafting.addRecipe("test", .{
        .id = undefined,
        .inputs = &.{},
        .outputs = &.{},
        .unlocked_by_default = true,
    });

    try std.testing.expect(crafting.isUnlocked("test"));

    crafting.lock("test");
    try std.testing.expect(!crafting.isUnlocked("test"));

    try crafting.unlock("test");
    try std.testing.expect(crafting.isUnlocked("test"));
}

test "CraftingSystem - get all recipes" {
    var crafting = CraftingSystem(TestResource).init(std.testing.allocator);
    defer crafting.deinit();

    try crafting.addRecipe("a", .{ .id = undefined, .inputs = &.{}, .outputs = &.{} });
    try crafting.addRecipe("b", .{ .id = undefined, .inputs = &.{}, .outputs = &.{} });
    try crafting.addRecipe("c", .{ .id = undefined, .inputs = &.{}, .outputs = &.{}, .unlocked_by_default = false });

    const all = try crafting.getAllRecipes(std.testing.allocator);
    defer std.testing.allocator.free(all);
    try std.testing.expectEqual(@as(usize, 3), all.len);

    const unlocked = try crafting.getUnlockedRecipes(std.testing.allocator);
    defer std.testing.allocator.free(unlocked);
    try std.testing.expectEqual(@as(usize, 2), unlocked.len);
}

test "CraftingSystem - category filtering" {
    var crafting = CraftingSystem(TestResource).init(std.testing.allocator);
    defer crafting.deinit();

    try crafting.addRecipe("iron", .{
        .id = undefined,
        .inputs = &.{},
        .outputs = &.{},
        .category = "smelting",
    });
    try crafting.addRecipe("copper", .{
        .id = undefined,
        .inputs = &.{},
        .outputs = &.{},
        .category = "smelting",
    });
    try crafting.addRecipe("wire", .{
        .id = undefined,
        .inputs = &.{},
        .outputs = &.{},
        .category = "assembly",
    });

    const smelting = try crafting.getRecipesByCategory("smelting", std.testing.allocator);
    defer std.testing.allocator.free(smelting);
    try std.testing.expectEqual(@as(usize, 2), smelting.len);

    const assembly = try crafting.getRecipesByCategory("assembly", std.testing.allocator);
    defer std.testing.allocator.free(assembly);
    try std.testing.expectEqual(@as(usize, 1), assembly.len);
}
