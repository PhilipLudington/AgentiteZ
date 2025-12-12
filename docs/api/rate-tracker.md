# Rate Tracker System

A system for tracking resource production and consumption rates over time, with historical data storage for UI graphs and stability analysis.

## Features

- Per-resource rate tracking (production/consumption)
- Configurable time windows (10s, 30s, 60s)
- Historical data with circular buffer
- Moving averages and statistics
- Stability detection (stable/unstable/analyzing)
- Per-minute/per-hour rate conversion
- Graph-friendly data ranges

## Basic Usage

```zig
const rate_tracker = @import("AgentiteZ").rate_tracker;

const Resource = enum { iron, copper, energy, carbon };

var tracker = try rate_tracker.RateTracker(Resource).init(allocator, .{
    .sample_interval = 1.0, // Sample every second
});
defer tracker.deinit();

// Call every frame with current resource amounts
tracker.updateWithAmounts(delta_time, .{ iron_count, copper_count, energy, carbon });

// Query rates
const iron_rate = tracker.getRate(.iron);           // Units per second
const iron_per_min = tracker.getRatePerMinute(.iron);
const iron_per_hour = tracker.getRatePerHour(.iron);

// Check stability
const stability = tracker.getStability(.iron);
// Returns: .stable, .unstable, or .analyzing
```

## Configuration

```zig
const config = rate_tracker.RateTrackerConfig{
    .sample_interval = 1.0,        // How often to sample (seconds)
    .history_size = 256,           // Circular buffer size
    .stability_threshold = 0.1,    // 10% tolerance for stability
    .stability_window = 5.0,       // Time window for stability analysis
    .default_time_window = .seconds_30,
    .min_stability_samples = 5,    // Min samples before stability check
};
```

## Update Methods

**Using amounts array:**
```zig
const amounts = [_]f64{ iron, copper, energy, carbon };
tracker.updateWithAmounts(delta_time, amounts);
```

**Using callback:**
```zig
fn getResourceAmount(resource: Resource) f64 {
    return inventory.get(resource);
}

tracker.update(delta_time, &getResourceAmount);
```

**Force immediate sample:**
```zig
tracker.forceSample(&getResourceAmount);
```

## Rate Queries

```zig
// Current rate
const rate = tracker.getRate(.iron);  // Per second

// Scaled rates
const per_min = tracker.getRatePerMinute(.iron);
const per_hour = tracker.getRatePerHour(.iron);

// Direction
if (tracker.isProducing(.iron)) { ... }  // Rate > 0
if (tracker.isConsuming(.iron)) { ... }  // Rate < 0

// Format for display
var buf: [32]u8 = undefined;
const rate_str = tracker.formatRate(.iron, &buf);  // "+10/s" or "-5/s"
```

## Time Windows

```zig
// Cycle through 10s -> 30s -> 60s
tracker.cycleTimeWindow();

// Current window
const window = tracker.time_window;
const seconds = window.getSeconds();  // 10.0, 30.0, or 60.0
const name = window.getName();        // "10s", "30s", "60s"
```

## Statistics

```zig
// Average rate over time window
const avg = tracker.getAverageRate(.iron);

// Min/max range (with padding for graphs)
const range = tracker.getRateRange(.iron);
const min_rate = range.min;
const max_rate = range.max;

// Standard deviation
const std_dev = tracker.getRateStdDev(.iron);
```

## Stability Analysis

```zig
const stability = tracker.getStability(.iron);
switch (stability) {
    .stable => // Production >= consumption (90% of samples)
    .unstable => // Production < consumption
    .analyzing => // Not enough samples yet
}

// Check all resources
const overall = tracker.getOverallStability();

// Balance check
if (tracker.isBalanced(.iron, 0.5)) {
    // Rate within +/- 0.5 of zero
}
```

## Deficit Detection

```zig
// Any resource being consumed faster than produced?
if (tracker.hasDeficit()) {
    // Show warning
}

// Which resource has the biggest deficit?
if (tracker.getMostConsumed()) |resource| {
    // resource has most negative rate
}

// Which is being produced fastest?
if (tracker.getMostProduced()) |resource| {
    // resource has most positive rate
}
```

## Graph Data

```zig
// Get data points for graphing
const data = try tracker.getGraphData(.iron, allocator);
defer allocator.free(data);

for (data) |point| {
    plot(point.time, point.value);
}

// Get samples within current window
const samples = try tracker.getWindowSamples(allocator);
defer allocator.free(samples);
```

## View Modes

For UI display:

```zig
// Toggle between absolute values and ratios
tracker.cycleViewMode();

const mode = tracker.view_mode;
const mode_name = mode.getName();  // "Absolute" or "Ratio %"
```

## Utility

```zig
// Clear all history
tracker.clear();

// Sample count
const samples = tracker.getSampleCount();

// Game time
const time = tracker.getGameTime();

// Net rate (sum of all resources)
const total_throughput = tracker.getNetRate();

// All current rates
const rates = tracker.getAllRates();
```

## Integration Example

```zig
// Game loop
fn update(delta_time: f32) void {
    // Update tracker with current inventory
    rate_tracker.updateWithAmounts(delta_time, .{
        inventory.get(.iron),
        inventory.get(.copper),
        inventory.get(.energy),
        inventory.get(.carbon),
    });

    // Update UI
    ui.setRateText(.iron, rate_tracker.formatRate(.iron, &buf));

    // Show warnings
    if (rate_tracker.hasDeficit()) {
        if (rate_tracker.getMostConsumed()) |resource| {
            ui.showWarning("Running low on {}", .{@tagName(resource)});
        }
    }

    // Update stability indicator
    const stability = rate_tracker.getOverallStability();
    ui.setStabilityColor(switch (stability) {
        .stable => .green,
        .unstable => .red,
        .analyzing => .yellow,
    });
}
```

## Sample Data Structure

Each sample contains:

```zig
const sample = tracker.getSampleAt(index);
if (sample) |s| {
    const timestamp = s.timestamp;
    const rates = s.rates;      // Per-resource rates
    const amounts = s.amounts;  // Per-resource amounts
}
```
