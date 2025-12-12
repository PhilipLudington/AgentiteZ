//! Modifier System - Stackable Value Modifiers with Source Tracking
//!
//! A flexible modifier system for games with stat modifications from
//! multiple sources (equipment, buffs, skills, traits, etc.).
//!
//! Features:
//! - Flat and percentage modifiers
//! - Configurable stacking rules (additive, multiplicative, highest-only)
//! - Modifier priorities for ordered application
//! - Source tracking for debugging and UI display
//! - Temporary modifiers with duration
//! - Min/max clamping
//!
//! Usage:
//! ```zig
//! var stack = ModifierStack.init(allocator);
//! defer stack.deinit();
//!
//! try stack.addFlat("sword", 10);           // +10 damage from sword
//! try stack.addPercent("strength", 0.25);   // +25% from strength
//! try stack.addPercent("buff", 0.10);       // +10% from buff
//!
//! const final = stack.apply(100.0);  // 100 + 10 = 110, then * 1.35 = 148.5
//! ```

const std = @import("std");

const log = std.log.scoped(.modifier);

/// Type of modifier
pub const ModifierType = enum {
    /// Added to base value before percentage modifiers
    flat,
    /// Percentage modifier (0.25 = +25%, -0.10 = -10%)
    percent,
    /// Flat value added after percentage modifiers
    flat_final,
    /// Multiplier applied at the end (stacks multiplicatively)
    multiplier,
};

/// How modifiers of the same type stack
pub const StackingRule = enum {
    /// All modifiers are summed (default for flat and percent)
    additive,
    /// Each modifier multiplies the result (for multipliers)
    multiplicative,
    /// Only the highest value is used
    highest_only,
    /// Only the lowest value is used
    lowest_only,
};

/// A single modifier entry
pub const Modifier = struct {
    /// Source identifier (e.g., "sword", "strength_buff", "trait_hardy")
    source: []const u8,
    /// Type of modifier
    mod_type: ModifierType,
    /// Value (flat amount or percentage as decimal)
    value: f64,
    /// Priority (lower = applied first within same type)
    priority: i32 = 0,
    /// Duration in ticks/turns (null = permanent)
    duration: ?u32 = null,
    /// Whether this is a buff (positive) or debuff (negative) for UI
    is_buff: bool = true,
};

/// Configuration for ModifierStack
pub const ModifierStackConfig = struct {
    /// How flat modifiers stack
    flat_stacking: StackingRule = .additive,
    /// How percent modifiers stack
    percent_stacking: StackingRule = .additive,
    /// How multipliers stack
    multiplier_stacking: StackingRule = .multiplicative,
    /// Minimum final value (null = no minimum)
    min_value: ?f64 = null,
    /// Maximum final value (null = no maximum)
    max_value: ?f64 = null,
    /// Base value to use if none provided in apply()
    default_base: f64 = 0,
};

/// A stack of modifiers that can be applied to a base value
pub const ModifierStack = struct {
    allocator: std.mem.Allocator,
    modifiers: std.ArrayList(OwnedModifier),
    config: ModifierStackConfig,

    /// Internal modifier with owned source string
    const OwnedModifier = struct {
        source: []u8,
        mod_type: ModifierType,
        value: f64,
        priority: i32,
        duration: ?u32,
        is_buff: bool,
    };

    /// Initialize a new modifier stack
    pub fn init(allocator: std.mem.Allocator) ModifierStack {
        return initWithConfig(allocator, .{});
    }

    /// Initialize with custom configuration
    pub fn initWithConfig(allocator: std.mem.Allocator, config: ModifierStackConfig) ModifierStack {
        return ModifierStack{
            .allocator = allocator,
            .modifiers = std.ArrayList(OwnedModifier).init(allocator),
            .config = config,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *ModifierStack) void {
        for (self.modifiers.items) |mod| {
            self.allocator.free(mod.source);
        }
        self.modifiers.deinit();
    }

    /// Add a modifier
    pub fn add(self: *ModifierStack, modifier: Modifier) !void {
        const source_copy = try self.allocator.dupe(u8, modifier.source);
        errdefer self.allocator.free(source_copy);

        try self.modifiers.append(.{
            .source = source_copy,
            .mod_type = modifier.mod_type,
            .value = modifier.value,
            .priority = modifier.priority,
            .duration = modifier.duration,
            .is_buff = modifier.is_buff,
        });
    }

    /// Convenience: add a flat modifier
    pub fn addFlat(self: *ModifierStack, source: []const u8, value: f64) !void {
        try self.add(.{
            .source = source,
            .mod_type = .flat,
            .value = value,
            .is_buff = value >= 0,
        });
    }

    /// Convenience: add a percentage modifier
    pub fn addPercent(self: *ModifierStack, source: []const u8, value: f64) !void {
        try self.add(.{
            .source = source,
            .mod_type = .percent,
            .value = value,
            .is_buff = value >= 0,
        });
    }

    /// Convenience: add a multiplier
    pub fn addMultiplier(self: *ModifierStack, source: []const u8, value: f64) !void {
        try self.add(.{
            .source = source,
            .mod_type = .multiplier,
            .value = value,
            .is_buff = value >= 1.0,
        });
    }

    /// Convenience: add a flat final modifier (applied after percentages)
    pub fn addFlatFinal(self: *ModifierStack, source: []const u8, value: f64) !void {
        try self.add(.{
            .source = source,
            .mod_type = .flat_final,
            .value = value,
            .is_buff = value >= 0,
        });
    }

    /// Convenience: add a temporary modifier with duration
    pub fn addTemporary(self: *ModifierStack, source: []const u8, mod_type: ModifierType, value: f64, duration: u32) !void {
        try self.add(.{
            .source = source,
            .mod_type = mod_type,
            .value = value,
            .duration = duration,
            .is_buff = if (mod_type == .multiplier) value >= 1.0 else value >= 0,
        });
    }

    /// Remove all modifiers from a specific source
    pub fn removeSource(self: *ModifierStack, source: []const u8) usize {
        var removed: usize = 0;
        var i: usize = 0;
        while (i < self.modifiers.items.len) {
            if (std.mem.eql(u8, self.modifiers.items[i].source, source)) {
                self.allocator.free(self.modifiers.items[i].source);
                _ = self.modifiers.swapRemove(i);
                removed += 1;
            } else {
                i += 1;
            }
        }
        return removed;
    }

    /// Check if a source has modifiers
    pub fn hasSource(self: *const ModifierStack, source: []const u8) bool {
        for (self.modifiers.items) |mod| {
            if (std.mem.eql(u8, mod.source, source)) {
                return true;
            }
        }
        return false;
    }

    /// Update durations and remove expired modifiers
    /// Call once per tick/turn
    pub fn tick(self: *ModifierStack) usize {
        var removed: usize = 0;
        var i: usize = 0;
        while (i < self.modifiers.items.len) {
            if (self.modifiers.items[i].duration) |*dur| {
                if (dur.* <= 1) {
                    self.allocator.free(self.modifiers.items[i].source);
                    _ = self.modifiers.swapRemove(i);
                    removed += 1;
                    continue;
                }
                dur.* -= 1;
            }
            i += 1;
        }
        return removed;
    }

    /// Apply all modifiers to a base value
    pub fn apply(self: *const ModifierStack, base: f64) f64 {
        var result = base;

        // Step 1: Apply flat modifiers
        const flat_total = self.calculateByType(.flat, self.config.flat_stacking);
        result += flat_total;

        // Step 2: Apply percentage modifiers
        const percent_total = self.calculateByType(.percent, self.config.percent_stacking);
        result *= (1.0 + percent_total);

        // Step 3: Apply flat final modifiers
        const flat_final_total = self.calculateByType(.flat_final, self.config.flat_stacking);
        result += flat_final_total;

        // Step 4: Apply multipliers
        const multiplier_total = self.calculateMultipliers();
        result *= multiplier_total;

        // Step 5: Clamp to min/max
        if (self.config.min_value) |min| {
            result = @max(result, min);
        }
        if (self.config.max_value) |max| {
            result = @min(result, max);
        }

        return result;
    }

    /// Calculate combined value for a modifier type
    fn calculateByType(self: *const ModifierStack, mod_type: ModifierType, rule: StackingRule) f64 {
        var values = std.ArrayList(f64).init(self.allocator);
        defer values.deinit();

        for (self.modifiers.items) |mod| {
            if (mod.mod_type == mod_type) {
                values.append(mod.value) catch continue;
            }
        }

        if (values.items.len == 0) return 0;

        return switch (rule) {
            .additive => blk: {
                var sum: f64 = 0;
                for (values.items) |v| sum += v;
                break :blk sum;
            },
            .multiplicative => blk: {
                var product: f64 = 1;
                for (values.items) |v| product *= v;
                break :blk product;
            },
            .highest_only => blk: {
                var highest = values.items[0];
                for (values.items[1..]) |v| {
                    if (v > highest) highest = v;
                }
                break :blk highest;
            },
            .lowest_only => blk: {
                var lowest = values.items[0];
                for (values.items[1..]) |v| {
                    if (v < lowest) lowest = v;
                }
                break :blk lowest;
            },
        };
    }

    /// Calculate combined multipliers (always multiplicative)
    fn calculateMultipliers(self: *const ModifierStack) f64 {
        var product: f64 = 1.0;
        for (self.modifiers.items) |mod| {
            if (mod.mod_type == .multiplier) {
                switch (self.config.multiplier_stacking) {
                    .multiplicative => product *= mod.value,
                    .additive => product += (mod.value - 1.0), // Convert to additive
                    .highest_only => product = @max(product, mod.value),
                    .lowest_only => product = @min(product, mod.value),
                }
            }
        }
        return product;
    }

    /// Get total flat modifier value
    pub fn getTotalFlat(self: *const ModifierStack) f64 {
        return self.calculateByType(.flat, self.config.flat_stacking);
    }

    /// Get total percentage modifier value
    pub fn getTotalPercent(self: *const ModifierStack) f64 {
        return self.calculateByType(.percent, self.config.percent_stacking);
    }

    /// Get total multiplier value
    pub fn getTotalMultiplier(self: *const ModifierStack) f64 {
        return self.calculateMultipliers();
    }

    /// Get count of modifiers
    pub fn getCount(self: *const ModifierStack) usize {
        return self.modifiers.items.len;
    }

    /// Get count of modifiers by type
    pub fn getCountByType(self: *const ModifierStack, mod_type: ModifierType) usize {
        var count: usize = 0;
        for (self.modifiers.items) |mod| {
            if (mod.mod_type == mod_type) count += 1;
        }
        return count;
    }

    /// Get count of buffs
    pub fn getBuffCount(self: *const ModifierStack) usize {
        var count: usize = 0;
        for (self.modifiers.items) |mod| {
            if (mod.is_buff) count += 1;
        }
        return count;
    }

    /// Get count of debuffs
    pub fn getDebuffCount(self: *const ModifierStack) usize {
        var count: usize = 0;
        for (self.modifiers.items) |mod| {
            if (!mod.is_buff) count += 1;
        }
        return count;
    }

    /// Get all modifier sources
    pub fn getSources(self: *const ModifierStack, allocator: std.mem.Allocator) ![][]const u8 {
        var sources = std.ArrayList([]const u8).init(allocator);
        for (self.modifiers.items) |mod| {
            // Check if already in list
            var found = false;
            for (sources.items) |s| {
                if (std.mem.eql(u8, s, mod.source)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                try sources.append(mod.source);
            }
        }
        return sources.toOwnedSlice();
    }

    /// Clear all modifiers
    pub fn clear(self: *ModifierStack) void {
        for (self.modifiers.items) |mod| {
            self.allocator.free(mod.source);
        }
        self.modifiers.clearRetainingCapacity();
    }

    /// Check if stack is empty
    pub fn isEmpty(self: *const ModifierStack) bool {
        return self.modifiers.items.len == 0;
    }

    /// Get a breakdown of all modifiers for debugging/UI
    pub fn getBreakdown(self: *const ModifierStack, allocator: std.mem.Allocator) ![]ModifierInfo {
        var list = std.ArrayList(ModifierInfo).init(allocator);
        for (self.modifiers.items) |mod| {
            try list.append(.{
                .source = mod.source,
                .mod_type = mod.mod_type,
                .value = mod.value,
                .is_buff = mod.is_buff,
                .remaining_duration = mod.duration,
            });
        }
        return list.toOwnedSlice();
    }

    /// Info about a modifier for UI display
    pub const ModifierInfo = struct {
        source: []const u8,
        mod_type: ModifierType,
        value: f64,
        is_buff: bool,
        remaining_duration: ?u32,
    };
};

// ============================================================================
// Tests
// ============================================================================

test "ModifierStack - basic flat modifier" {
    var stack = ModifierStack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.addFlat("sword", 10);
    const result = stack.apply(100);
    try std.testing.expectEqual(@as(f64, 110), result);
}

test "ModifierStack - multiple flat modifiers" {
    var stack = ModifierStack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.addFlat("sword", 10);
    try stack.addFlat("ring", 5);
    try stack.addFlat("buff", 3);

    const result = stack.apply(100);
    try std.testing.expectEqual(@as(f64, 118), result);
}

test "ModifierStack - percentage modifier" {
    var stack = ModifierStack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.addPercent("strength", 0.25); // +25%
    const result = stack.apply(100);
    try std.testing.expectEqual(@as(f64, 125), result);
}

test "ModifierStack - multiple percentage modifiers (additive)" {
    var stack = ModifierStack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.addPercent("strength", 0.25); // +25%
    try stack.addPercent("buff", 0.10); // +10%

    const result = stack.apply(100);
    try std.testing.expectEqual(@as(f64, 135), result); // 100 * 1.35
}

test "ModifierStack - flat and percent combined" {
    var stack = ModifierStack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.addFlat("sword", 10);
    try stack.addPercent("strength", 0.25);

    const result = stack.apply(100);
    // (100 + 10) * 1.25 = 137.5
    try std.testing.expectEqual(@as(f64, 137.5), result);
}

test "ModifierStack - multiplier" {
    var stack = ModifierStack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.addMultiplier("critical", 2.0);
    const result = stack.apply(100);
    try std.testing.expectEqual(@as(f64, 200), result);
}

test "ModifierStack - multiple multipliers (multiplicative)" {
    var stack = ModifierStack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.addMultiplier("critical", 2.0);
    try stack.addMultiplier("headshot", 1.5);

    const result = stack.apply(100);
    try std.testing.expectEqual(@as(f64, 300), result); // 100 * 2.0 * 1.5
}

test "ModifierStack - flat final modifier" {
    var stack = ModifierStack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.addPercent("strength", 0.50); // +50%
    try stack.addFlatFinal("bonus", 10); // +10 after percent

    const result = stack.apply(100);
    // 100 * 1.5 = 150, then + 10 = 160
    try std.testing.expectEqual(@as(f64, 160), result);
}

test "ModifierStack - all modifier types combined" {
    var stack = ModifierStack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.addFlat("sword", 10);
    try stack.addPercent("strength", 0.25);
    try stack.addFlatFinal("bonus", 5);
    try stack.addMultiplier("critical", 2.0);

    const result = stack.apply(100);
    // (100 + 10) * 1.25 = 137.5
    // 137.5 + 5 = 142.5
    // 142.5 * 2.0 = 285.0
    try std.testing.expectEqual(@as(f64, 285), result);
}

test "ModifierStack - negative modifiers" {
    var stack = ModifierStack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.addFlat("curse", -20);
    try stack.addPercent("weakness", -0.25); // -25%

    const result = stack.apply(100);
    // (100 - 20) * 0.75 = 60
    try std.testing.expectEqual(@as(f64, 60), result);
}

test "ModifierStack - removeSource" {
    var stack = ModifierStack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.addFlat("sword", 10);
    try stack.addPercent("sword", 0.25);
    try stack.addFlat("ring", 5);

    try std.testing.expectEqual(@as(usize, 3), stack.getCount());

    const removed = stack.removeSource("sword");
    try std.testing.expectEqual(@as(usize, 2), removed);
    try std.testing.expectEqual(@as(usize, 1), stack.getCount());

    const result = stack.apply(100);
    try std.testing.expectEqual(@as(f64, 105), result); // Only ring remains
}

test "ModifierStack - hasSource" {
    var stack = ModifierStack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.addFlat("sword", 10);

    try std.testing.expect(stack.hasSource("sword"));
    try std.testing.expect(!stack.hasSource("ring"));
}

test "ModifierStack - temporary modifier tick" {
    var stack = ModifierStack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.addTemporary("buff", .percent, 0.50, 3); // 3 ticks
    try stack.addFlat("sword", 10);

    try std.testing.expectEqual(@as(usize, 2), stack.getCount());

    _ = stack.tick();
    try std.testing.expectEqual(@as(usize, 2), stack.getCount()); // Still there (2 left)

    _ = stack.tick();
    try std.testing.expectEqual(@as(usize, 2), stack.getCount()); // Still there (1 left)

    _ = stack.tick();
    try std.testing.expectEqual(@as(usize, 1), stack.getCount()); // Expired
}

test "ModifierStack - min/max clamping" {
    var stack = ModifierStack.initWithConfig(std.testing.allocator, .{
        .min_value = 10,
        .max_value = 200,
    });
    defer stack.deinit();

    try stack.addFlat("curse", -1000);
    var result = stack.apply(100);
    try std.testing.expectEqual(@as(f64, 10), result); // Clamped to min

    stack.clear();
    try stack.addMultiplier("mega_buff", 10.0);
    result = stack.apply(100);
    try std.testing.expectEqual(@as(f64, 200), result); // Clamped to max
}

test "ModifierStack - highest only stacking" {
    var stack = ModifierStack.initWithConfig(std.testing.allocator, .{
        .percent_stacking = .highest_only,
    });
    defer stack.deinit();

    try stack.addPercent("buff1", 0.20);
    try stack.addPercent("buff2", 0.50);
    try stack.addPercent("buff3", 0.30);

    const result = stack.apply(100);
    try std.testing.expectEqual(@as(f64, 150), result); // Only highest (50%) applies
}

test "ModifierStack - lowest only stacking" {
    var stack = ModifierStack.initWithConfig(std.testing.allocator, .{
        .percent_stacking = .lowest_only,
    });
    defer stack.deinit();

    try stack.addPercent("debuff1", -0.20);
    try stack.addPercent("debuff2", -0.50);
    try stack.addPercent("debuff3", -0.30);

    const result = stack.apply(100);
    try std.testing.expectEqual(@as(f64, 50), result); // Only lowest (-50%) applies
}

test "ModifierStack - getCount methods" {
    var stack = ModifierStack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.addFlat("sword", 10);
    try stack.addFlat("ring", 5);
    try stack.addPercent("strength", 0.25);
    try stack.addMultiplier("critical", 2.0);

    try std.testing.expectEqual(@as(usize, 4), stack.getCount());
    try std.testing.expectEqual(@as(usize, 2), stack.getCountByType(.flat));
    try std.testing.expectEqual(@as(usize, 1), stack.getCountByType(.percent));
    try std.testing.expectEqual(@as(usize, 1), stack.getCountByType(.multiplier));
}

test "ModifierStack - buff/debuff count" {
    var stack = ModifierStack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.addFlat("sword", 10);
    try stack.addFlat("curse", -5);
    try stack.addPercent("strength", 0.25);
    try stack.addPercent("weakness", -0.10);

    try std.testing.expectEqual(@as(usize, 2), stack.getBuffCount());
    try std.testing.expectEqual(@as(usize, 2), stack.getDebuffCount());
}

test "ModifierStack - getTotals" {
    var stack = ModifierStack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.addFlat("sword", 10);
    try stack.addFlat("ring", 5);
    try stack.addPercent("strength", 0.25);
    try stack.addPercent("buff", 0.10);
    try stack.addMultiplier("critical", 2.0);

    try std.testing.expectEqual(@as(f64, 15), stack.getTotalFlat());
    try std.testing.expectEqual(@as(f64, 0.35), stack.getTotalPercent());
    try std.testing.expectEqual(@as(f64, 2.0), stack.getTotalMultiplier());
}

test "ModifierStack - clear" {
    var stack = ModifierStack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.addFlat("sword", 10);
    try stack.addPercent("strength", 0.25);

    try std.testing.expectEqual(@as(usize, 2), stack.getCount());

    stack.clear();

    try std.testing.expectEqual(@as(usize, 0), stack.getCount());
    try std.testing.expect(stack.isEmpty());
}

test "ModifierStack - getSources" {
    var stack = ModifierStack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.addFlat("sword", 10);
    try stack.addPercent("sword", 0.25); // Same source
    try stack.addFlat("ring", 5);
    try stack.addPercent("buff", 0.10);

    const sources = try stack.getSources(std.testing.allocator);
    defer std.testing.allocator.free(sources);

    try std.testing.expectEqual(@as(usize, 3), sources.len);
}

test "ModifierStack - getBreakdown" {
    var stack = ModifierStack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.addFlat("sword", 10);
    try stack.addTemporary("buff", .percent, 0.25, 5);

    const breakdown = try stack.getBreakdown(std.testing.allocator);
    defer std.testing.allocator.free(breakdown);

    try std.testing.expectEqual(@as(usize, 2), breakdown.len);

    // Check sword
    try std.testing.expectEqualStrings("sword", breakdown[0].source);
    try std.testing.expectEqual(ModifierType.flat, breakdown[0].mod_type);
    try std.testing.expectEqual(@as(f64, 10), breakdown[0].value);
    try std.testing.expectEqual(@as(?u32, null), breakdown[0].remaining_duration);

    // Check buff
    try std.testing.expectEqualStrings("buff", breakdown[1].source);
    try std.testing.expectEqual(ModifierType.percent, breakdown[1].mod_type);
    try std.testing.expectEqual(@as(f64, 0.25), breakdown[1].value);
    try std.testing.expectEqual(@as(?u32, 5), breakdown[1].remaining_duration);
}

test "ModifierStack - zero base value" {
    var stack = ModifierStack.init(std.testing.allocator);
    defer stack.deinit();

    try stack.addFlat("bonus", 50);
    try stack.addPercent("strength", 0.25);

    const result = stack.apply(0);
    // (0 + 50) * 1.25 = 62.5
    try std.testing.expectEqual(@as(f64, 62.5), result);
}

test "ModifierStack - empty stack returns base" {
    var stack = ModifierStack.init(std.testing.allocator);
    defer stack.deinit();

    const result = stack.apply(100);
    try std.testing.expectEqual(@as(f64, 100), result);
}
