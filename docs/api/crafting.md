# Crafting System

A recipe-based crafting system for factory/survival games where machines transform input resources into outputs over time.

## Features

- Recipe definitions with multiple inputs and outputs
- Byproduct handling (secondary outputs)
- Crafting time with progress tracking
- Recipe unlocking/research integration
- Crafting queues per machine
- Batch crafting support
- Crafting speed modifiers
- Resource availability validation

## Basic Usage

```zig
const crafting = @import("AgentiteZ").crafting;

const Resource = enum { iron_ore, coal, iron_plate, steel, slag };

var system = crafting.CraftingSystem(Resource).init(allocator);
defer system.deinit();

// Add a recipe
try system.addRecipe("smelt_iron", .{
    .id = undefined,
    .inputs = &.{
        .{ .resource = .iron_ore, .amount = 2 },
        .{ .resource = .coal, .amount = 1 },
    },
    .outputs = &.{
        .{ .resource = .iron_plate, .amount = 1 },
    },
    .byproducts = &.{
        .{ .resource = .slag, .amount = 1 },
    },
    .craft_time = 3.0, // seconds
});

// Start crafting
if (system.canCraft("smelt_iron", inventory_interface)) {
    _ = try system.startCrafting(machine_id, "smelt_iron", inventory_interface);
}

// Update progress each frame
system.update(delta_time);

// Collect outputs when complete
if (system.getStatus(machine_id) == .complete) {
    _ = system.collectOutputs(machine_id, inventory_interface);
}
```

## Recipe Definition

```zig
const recipe = crafting.Recipe(Resource){
    .id = "steel_plate",
    .name = "Steel Plate",           // Display name
    .category = "smelting",          // For UI grouping
    .inputs = &.{
        .{ .resource = .iron_plate, .amount = 2 },
        .{ .resource = .coal, .amount = 1 },
    },
    .outputs = &.{
        .{ .resource = .steel, .amount = 1 },
    },
    .byproducts = &.{},              // Optional
    .craft_time = 5.0,               // Seconds
    .energy_cost = 10,               // Optional energy
    .unlocked_by_default = true,     // Or false for tech-gated
    .required_tech = null,           // Tech ID if locked
};
```

## Inventory Interface

The crafting system uses an interface to interact with inventories:

```zig
const InventoryInterface = crafting.InventoryInterface(Resource);

const inv_iface = InventoryInterface{
    .ptr = &my_inventory,
    .has_fn = &hasResource,
    .remove_fn = &removeResource,
    .add_fn = &addResource,
    .can_accept_fn = &canAcceptResource, // Optional
};
```

## Crafting Status

```zig
const status = system.getStatus(machine_id);
// .idle     - Not crafting
// .waiting  - Waiting for resources (batch mode)
// .crafting - In progress
// .complete - Ready to collect
// .blocked  - Output full
// .locked   - Recipe not unlocked
```

## Progress Tracking

```zig
const progress = system.getProgress(machine_id); // 0.0 to 1.0

if (system.getJob(machine_id)) |job| {
    const remaining = job.getRemainingTime(recipe);
}
```

## Speed Modifiers

```zig
// Set crafting speed (1.0 = normal, 2.0 = 2x speed)
_ = system.setSpeedModifier(machine_id, 2.0);
```

## Batch Crafting

Craft multiple items in sequence:

```zig
_ = try system.startCraftingBatch(machine_id, "smelt_iron", 5, inventory);

// After first item completes:
_ = system.collectOutputs(machine_id, inventory);

// Continue batch (consumes inputs for next item):
if (system.getStatus(machine_id) == .waiting) {
    _ = system.continueBatch(machine_id, inventory);
}
```

## Recipe Queuing

Queue recipes for later execution:

```zig
try system.queueRecipe(machine_id, "smelt_iron", 3);
try system.queueRecipe(machine_id, "smelt_steel", 2);

// Process queue when machine is idle
_ = system.processQueue(machine_id, inventory);

// Clear queue
system.clearQueue(machine_id);
```

## Recipe Management

```zig
// Check if can craft
if (system.canCraft("smelt_iron", inventory)) { ... }

// Count how many times can craft
const count = system.countCraftable("smelt_iron", inventory, 100);

// Recipe locking
try system.unlock("advanced_recipe");
system.lock("temporary_recipe");
if (system.isUnlocked("recipe_id")) { ... }
```

## Recipe Queries

```zig
// Get recipe
if (system.getRecipe("smelt_iron")) |recipe| { ... }

// Get current recipe being crafted
if (system.getCurrentRecipe(machine_id)) |recipe| { ... }

// Find recipes by criteria
const iron_recipes = try system.findRecipesProducing(.iron_plate, allocator);
const ore_consumers = try system.findRecipesConsuming(.iron_ore, allocator);
const smelting = try system.getRecipesByCategory("smelting", allocator);

// Get all recipes
const all = try system.getAllRecipes(allocator);
const unlocked = try system.getUnlockedRecipes(allocator);
```

## Recipe Helpers

```zig
const recipe = system.getRecipe("smelt_iron").?;

// Check what recipe produces/consumes
if (recipe.produces(.iron_plate)) { ... }
if (recipe.consumes(.iron_ore)) { ... }

// Get amounts
const input_amount = recipe.getInputAmount(.iron_ore);
const output_amount = recipe.getOutputAmount(.iron_plate);
```

## Cancel Crafting

```zig
// Cancel and return consumed resources
_ = system.cancelCrafting(machine_id, inventory);

// Cancel without returning resources
_ = system.cancelCrafting(machine_id, null);
```

## Completion Callback

```zig
system.on_complete = &onCraftingComplete;

fn onCraftingComplete(entity_id: u32, recipe_id: []const u8) void {
    std.log.info("Machine {} finished {}", .{entity_id, recipe_id});
}
```

## Statistics

```zig
const active_jobs = system.getActiveJobCount();
const total_recipes = system.getRecipeCount();
const unlocked_recipes = system.getUnlockedCount();
```
