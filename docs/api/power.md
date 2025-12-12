# Power Network System

Grid-based power distribution for factory/strategy games where buildings connect to power networks through poles/substations.

## Features

- Power poles with configurable coverage radius
- Automatic network merging when poles connect (Union-Find algorithm)
- Network splitting when poles are removed
- Production/consumption tracking per network
- Powered/brownout/blackout status
- Cell and entity coverage queries
- Multiple independent networks

## Basic Usage

```zig
const power = @import("AgentiteZ").power;

var network = power.PowerNetwork(u32).init(allocator, .{
    .pole_radius = 5,
    .connection_range = 10,
});
defer network.deinit();

// Add power poles
const pole1 = try network.addPole(10, 10, building_id_1);
const pole2 = try network.addPole(15, 10, building_id_2); // Auto-connects if within range

// Set production/consumption
try network.setProduction(pole1, 100); // Generator
try network.setConsumption(pole2, 60);  // Machine

// Recalculate network stats
network.recalculate();

// Check power status
if (network.isPowered(pole1)) {
    // Building has power
}
```

## Configuration

```zig
const config = power.PowerConfig{
    .pole_radius = 5,           // Coverage radius for buildings
    .connection_range = 10,     // Max distance between poles to connect (default: 2x radius)
    .brownout_threshold = 1.0,  // Ratio below this = brownout
    .max_poles = 4096,          // Maximum poles
};
```

## Network Connectivity

Poles automatically connect when within `connection_range`:

```zig
// These poles will form one network (within range)
const pole1 = try network.addPole(0, 0, 1);
const pole2 = try network.addPole(8, 0, 2);
const pole3 = try network.addPole(16, 0, 3);

// All three are connected through chaining
try std.testing.expect(network.areConnected(pole1, pole3));
```

When a pole is removed, networks may split:

```zig
network.removePole(owner_id);
// If this was a bridge pole, the network splits into two
```

## Power Status

```zig
const status = network.getPowerStatus(pole_index);
// Returns: .disconnected, .unpowered, .brownout, or .powered
```

Network statistics:

```zig
if (network.getNetworkStats(network_id)) |stats| {
    const production = stats.production;
    const consumption = stats.consumption;
    const surplus = stats.getSurplus();
    const ratio = stats.getRatio();
    const is_powered = stats.powered;
}
```

## Cell Coverage

Check if grid positions are powered:

```zig
// Is this cell within any pole's coverage?
if (network.isCellCovered(x, y)) { ... }

// Which network covers this cell?
if (network.getCellNetwork(x, y)) |net_id| { ... }

// Is this cell powered?
if (network.isCellPowered(x, y)) { ... }
```

Get all covered cells (for rendering):

```zig
const cells = try network.getCoveredCells(allocator);
defer allocator.free(cells);

for (cells) |cell| {
    renderPowerOverlay(cell.x, cell.y);
}
```

## By-Owner Operations

Operate on poles by building/entity ID:

```zig
try network.setProductionByOwner(building_id, 100);
try network.setConsumptionByOwner(building_id, 60);

if (network.isPoweredByOwner(building_id)) { ... }
if (network.getNetworkIdByOwner(building_id)) |net_id| { ... }
```

## Utility Functions

```zig
// Count active poles
const pole_count = network.getPoleCount();

// Count distinct networks
const network_count = network.getNetworkCount();

// Total power across all networks
const total_production = network.getTotalProduction();
const total_consumption = network.getTotalConsumption();

// Find nearest powered pole to a position
if (network.findNearestPoweredPole(x, y)) |pole_index| { ... }
```

## Integration Example

```zig
// Each frame/tick:
fn updatePower(network: *PowerNetwork(u32), buildings: []Building) void {
    network.clearPowerData();

    for (buildings) |building| {
        if (network.getPoleIndex(building.id)) |pole_idx| {
            if (building.type == .generator) {
                try network.setProduction(pole_idx, building.power_output);
            } else {
                try network.setConsumption(pole_idx, building.power_draw);
            }
        }
    }

    network.recalculate();

    for (buildings) |*building| {
        building.has_power = network.isPoweredByOwner(building.id);
    }
}
```
