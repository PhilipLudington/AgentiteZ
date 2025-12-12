# Resource System

Generic resource storage and management for game economies (`src/resource.zig`).

## Features

- **Generic resource types** - Works with any enum type
- **Per-resource capacity limits** - Optional maximum storage with overflow policies
- **Production/consumption rates** - Track income and expenses per resource
- **Net rate calculation** - Automatic production - consumption tracking
- **Resource transfers** - Move resources between storages
- **Overflow/deficit policies** - Configurable handling (clamp, reject, allow)
- **Atomic cost operations** - All-or-nothing multi-resource deductions

## Usage

### Basic Storage

```zig
const resource = @import("AgentiteZ").resource;

const ResourceType = enum { credits, energy, minerals, food, research };

var storage = resource.ResourceStorage(ResourceType).init(allocator);
defer storage.deinit();

// Define resources with properties
try storage.defineResource(.credits, .{
    .initial_amount = 1000,
    .max_capacity = 10000,
    .overflow_policy = .clamp,
});

try storage.defineResource(.energy, .{
    .initial_amount = 100,
    .max_capacity = 500,
});

// Basic operations
_ = storage.add(.credits, 500);
_ = storage.remove(.credits, 200);
const balance = storage.get(.credits);
const space = storage.getAvailableSpace(.energy);
```

### Rates and Production

```zig
_ = storage.setProductionRate(.energy, 50);   // +50 per tick
_ = storage.setConsumptionRate(.energy, 30);  // -30 per tick

const production = storage.getProductionRate(.energy);
const consumption = storage.getConsumptionRate(.energy);
const net_rate = storage.getNetRate(.energy); // +20 per tick

// Apply rates each game tick
storage.applyRates(1.0);
storage.applyRates(delta_time);

// Reset rates each turn (for recalculation)
storage.resetRates();
```

### Transfers

```zig
var player_storage = resource.ResourceStorage(ResourceType).init(allocator);
var bank_storage = resource.ResourceStorage(ResourceType).init(allocator);

try player_storage.defineResource(.credits, .{ .initial_amount = 1000 });
try bank_storage.defineResource(.credits, .{ .initial_amount = 0, .max_capacity = 5000 });

// Exact transfer (fails if insufficient or no space)
const result = player_storage.transferTo(&bank_storage, .credits, 500);
if (result == .success) {
    // Transfer complete
}

// Transfer as much as possible
const transferred = player_storage.transferToMax(&bank_storage, .credits, 1000);
```

### Cost Operations

```zig
const building_cost = [_]struct { ResourceType, f64 }{
    .{ .credits, 500 },
    .{ .minerals, 200 },
    .{ .energy, 50 },
};

if (storage.canAfford(&building_cost)) {
    // Atomic deduction (all or nothing)
    const result = storage.deductCosts(&building_cost);
    if (result == .success) {
        // Build the building
    }
}

// Add multiple resources at once
storage.addBulk(&[_]struct { ResourceType, f64 }{
    .{ .credits, 100 },
    .{ .minerals, 50 },
});
```

### Overflow and Deficit Policies

```zig
// Clamp to capacity (default)
try storage.defineResource(.energy, .{
    .max_capacity = 100,
    .overflow_policy = .clamp,  // Excess is lost
});

// Reject overflow
try storage.defineResource(.rare_items, .{
    .max_capacity = 10,
    .overflow_policy = .reject, // Returns .overflow if would exceed
});

// Allow debt (negative values)
try storage.defineResource(.reputation, .{
    .initial_amount = 50,
    .deficit_policy = .allow_negative, // Can go negative
});
```

### Status and Summary

```zig
const fill = storage.getFillRatio(.energy); // 0.0 to 1.0

if (storage.getSummary(.energy)) |summary| {
    std.debug.print("Energy: {d}/{d} (+{d}/-{d} = {d}/tick)\n", .{
        summary.amount,
        summary.capacity,
        summary.production,
        summary.consumption,
        summary.net_rate,
    });
}

if (storage.has(.minerals, 100)) { /* Has at least 100 */ }
if (storage.hasSpace(.minerals, 50)) { /* Can accept 50 more */ }
```

## Data Structures

- `ResourceStorage(ResourceType)` - Generic storage parameterized by resource enum
- `ResourceDefinition` - Resource properties (capacity, initial, policies)
- `ResourceResult` - Operation result (success, insufficient, overflow, not_defined)
- `OverflowPolicy` - How to handle additions beyond capacity (clamp, reject, allow)
- `DeficitPolicy` - How to handle removals below zero (clamp, reject, allow_negative)

## Key Methods

- `defineResource(type, definition)` - Define a resource with properties
- `add(type, amount)` / `remove(type, amount)` - Modify amounts
- `get(type)` / `set(type, amount)` - Query/set amounts
- `has(type, amount)` / `hasSpace(type, amount)` - Check availability
- `setProductionRate()` / `setConsumptionRate()` - Set rates
- `getNetRate()` - Get production - consumption
- `applyRates(delta)` - Apply rates over time
- `transferTo()` / `transferToMax()` - Move resources between storages
- `canAfford(costs)` / `deductCosts(costs)` - Multi-resource operations

## Tests

22 comprehensive tests covering add/remove, capacity limits, overflow/deficit policies, rates, transfers, cost operations, and edge cases.
