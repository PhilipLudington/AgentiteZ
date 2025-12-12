# Modifier System

Stackable value modifiers with source tracking for game stats (`src/modifier.zig`).

## Features

- **Flat modifiers** - Added to base value before percentages
- **Percentage modifiers** - Applied as multipliers after flat
- **Final flat modifiers** - Added after percentages
- **Multipliers** - Stacked multiplicatively at the end
- **Configurable stacking** - Additive, multiplicative, highest-only, lowest-only
- **Source tracking** - Know which item/buff/skill contributed each modifier
- **Temporary modifiers** - Auto-expire after duration ticks
- **Min/max clamping** - Enforce value bounds

## Usage

### Basic Modifiers

```zig
const modifier = @import("AgentiteZ").modifier;

var stack = modifier.ModifierStack.init(allocator);
defer stack.deinit();

// Add modifiers from various sources
try stack.addFlat("iron_sword", 15);      // +15 damage
try stack.addFlat("ring_of_power", 5);    // +5 damage
try stack.addPercent("strength", 0.25);   // +25% from strength stat
try stack.addPercent("rage_buff", 0.10);  // +10% from buff

// Apply to base damage
const base_damage: f64 = 100;
const final_damage = stack.apply(base_damage);
// (100 + 15 + 5) * 1.35 = 162
```

### Modifier Types

```zig
// Flat: Added first to base
try stack.addFlat("sword", 10);

// Percent: Multiplies (base + flat)
try stack.addPercent("strength", 0.25); // +25%

// Flat Final: Added after percentages
try stack.addFlatFinal("enchantment", 5);

// Multiplier: Multiplies everything at end
try stack.addMultiplier("critical_hit", 2.0);

// Application order:
// result = ((base + flat) * (1 + percent) + flat_final) * multipliers
```

### Temporary Modifiers

```zig
// Add a buff that lasts 5 ticks/turns
try stack.addTemporary("berserk", .percent, 0.50, 5);

// Each game tick, update durations and remove expired
_ = stack.tick();  // Returns count of expired modifiers

// After 5 ticks, the berserk modifier is automatically removed
```

### Source Management

```zig
// Remove all modifiers from a source (e.g., when unequipping)
const removed = stack.removeSource("iron_sword");

// Check if source has any modifiers
if (stack.hasSource("buff_spell")) {
    // Buff is still active
}

// Get all unique sources for UI
const sources = try stack.getSources(allocator);
defer allocator.free(sources);
```

### Stacking Rules

```zig
// Default: percentages are additive
var stack = modifier.ModifierStack.init(allocator);
try stack.addPercent("buff1", 0.20); // +20%
try stack.addPercent("buff2", 0.30); // +30%
// Total: +50%

// Highest-only stacking (for non-stacking buffs)
var stack = modifier.ModifierStack.initWithConfig(allocator, .{
    .percent_stacking = .highest_only,
});
try stack.addPercent("buff1", 0.20);
try stack.addPercent("buff2", 0.30);
// Total: +30% (only highest applies)
```

### Value Clamping

```zig
var stack = modifier.ModifierStack.initWithConfig(allocator, .{
    .min_value = 1,     // Never go below 1
    .max_value = 9999,  // Cap at 9999
});

try stack.addFlat("curse", -1000);
const result = stack.apply(100);  // Returns 1 (clamped to min)
```

### UI Breakdown

```zig
const breakdown = try stack.getBreakdown(allocator);
defer allocator.free(breakdown);

for (breakdown) |info| {
    const sign: []const u8 = if (info.is_buff) "+" else "";
    const type_str = switch (info.mod_type) {
        .flat => "",
        .percent => "%",
        .flat_final => " (final)",
        .multiplier => "x",
    };
    std.debug.print("{s}: {s}{d:.0}{s}", .{
        info.source, sign, info.value * if (info.mod_type == .percent) 100 else 1, type_str,
    });
    if (info.remaining_duration) |dur| {
        std.debug.print(" ({d} turns left)", .{dur});
    }
}
```

## Data Structures

- `ModifierStack` - Collection of modifiers with apply logic
- `Modifier` - Single modifier entry (source, type, value, duration)
- `ModifierType` - flat, percent, flat_final, multiplier
- `StackingRule` - additive, multiplicative, highest_only, lowest_only
- `ModifierStackConfig` - Stacking rules and min/max clamping

## Key Methods

- `addFlat(source, value)` - Add flat modifier
- `addPercent(source, value)` - Add percentage modifier (0.25 = +25%)
- `addMultiplier(source, value)` - Add multiplier (2.0 = double)
- `addTemporary(source, type, value, duration)` - Add expiring modifier
- `apply(base)` - Calculate final value
- `tick()` - Update durations, remove expired
- `removeSource(source)` - Remove all modifiers from source
- `getBreakdown()` - Get all modifiers for UI display
- `getTotalFlat()` / `getTotalPercent()` / `getTotalMultiplier()` - Get totals by type

## Tests

24 comprehensive tests covering all modifier types, stacking rules, source tracking, temporary modifiers, clamping, and edge cases.
