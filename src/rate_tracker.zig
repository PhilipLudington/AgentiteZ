//! Rate Tracking System - Production/Consumption Analytics
//!
//! A system for tracking resource production and consumption rates over time,
//! with historical data storage for UI graphs and stability analysis.
//!
//! Features:
//! - Per-resource rate tracking (production/consumption)
//! - Configurable time windows (10s, 30s, 60s)
//! - Historical data with circular buffer
//! - Moving averages and statistics
//! - Stability detection (stable/unstable/analyzing)
//! - Per-minute/per-hour rate conversion
//! - Graph-friendly data ranges
//!
//! Usage:
//! ```zig
//! const Resource = enum { iron, copper, energy };
//!
//! var tracker = RateTracker(Resource).init(allocator, .{ .sample_interval = 1.0 });
//! defer tracker.deinit();
//!
//! // Call every frame with delta time
//! tracker.update(delta_time, getResourceCounts);
//!
//! // Query rates
//! const iron_rate = tracker.getRate(.iron);
//! const iron_per_min = tracker.getRatePerMinute(.iron);
//!
//! // Check stability
//! const stability = tracker.getStability(.iron);
//! ```

const std = @import("std");

/// Time window for analysis
pub const TimeWindow = enum {
    seconds_10,
    seconds_30,
    seconds_60,

    pub fn getSeconds(self: TimeWindow) f32 {
        return switch (self) {
            .seconds_10 => 10.0,
            .seconds_30 => 30.0,
            .seconds_60 => 60.0,
        };
    }

    pub fn getName(self: TimeWindow) []const u8 {
        return switch (self) {
            .seconds_10 => "10s",
            .seconds_30 => "30s",
            .seconds_60 => "60s",
        };
    }

    pub fn cycle(self: TimeWindow) TimeWindow {
        return switch (self) {
            .seconds_10 => .seconds_30,
            .seconds_30 => .seconds_60,
            .seconds_60 => .seconds_10,
        };
    }
};

/// View mode for UI
pub const ViewMode = enum {
    absolute,
    ratio,

    pub fn getName(self: ViewMode) []const u8 {
        return switch (self) {
            .absolute => "Absolute",
            .ratio => "Ratio %",
        };
    }

    pub fn cycle(self: ViewMode) ViewMode {
        return switch (self) {
            .absolute => .ratio,
            .ratio => .absolute,
        };
    }
};

/// Stability status
pub const StabilityStatus = enum {
    /// Production meets or exceeds consumption
    stable,
    /// Production below consumption
    unstable,
    /// Not enough data yet
    analyzing,

    pub fn getName(self: StabilityStatus) []const u8 {
        return switch (self) {
            .stable => "STABLE",
            .unstable => "UNSTABLE",
            .analyzing => "ANALYZING...",
        };
    }
};

/// Configuration for rate tracker
pub const RateTrackerConfig = struct {
    /// How often to take samples (seconds)
    sample_interval: f32 = 1.0,
    /// History buffer size
    history_size: usize = 256,
    /// Stability threshold (ratio tolerance)
    stability_threshold: f32 = 0.1,
    /// Time window for stability analysis
    stability_window: f32 = 5.0,
    /// Default time window for display
    default_time_window: TimeWindow = .seconds_30,
    /// Minimum samples for stability check
    min_stability_samples: usize = 5,
};

/// A single metrics sample
pub fn MetricsSample(comptime ResourceType: type) type {
    const resource_info = @typeInfo(ResourceType);
    const field_count = if (resource_info == .@"enum") resource_info.@"enum".fields.len else 0;

    return struct {
        /// Game timestamp when sample was taken
        timestamp: f64,
        /// Resource rates at this sample
        rates: [field_count]f64 = [_]f64{0} ** field_count,
        /// Resource amounts at this sample
        amounts: [field_count]f64 = [_]f64{0} ** field_count,
    };
}

/// Rate tracker for a resource type
pub fn RateTracker(comptime ResourceType: type) type {
    const resource_info = @typeInfo(ResourceType);
    if (resource_info != .@"enum") {
        @compileError("RateTracker requires an enum type, got " ++ @typeName(ResourceType));
    }

    const field_count = resource_info.@"enum".fields.len;
    const SampleType = MetricsSample(ResourceType);

    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        config: RateTrackerConfig,

        // Current state
        time_since_sample: f32 = 0,
        has_previous: bool = false,
        previous_amounts: [field_count]f64 = [_]f64{0} ** field_count,
        current_rates: [field_count]f64 = [_]f64{0} ** field_count,

        // History (circular buffer)
        history: []SampleType,
        history_head: usize = 0,
        history_count: usize = 0,

        // UI state
        time_window: TimeWindow,
        view_mode: ViewMode = .absolute,

        // Game time tracking
        game_time: f64 = 0,

        /// Initialize the rate tracker
        pub fn init(allocator: std.mem.Allocator, config: RateTrackerConfig) !Self {
            const history = try allocator.alloc(SampleType, config.history_size);
            @memset(history, std.mem.zeroes(SampleType));

            return Self{
                .allocator = allocator,
                .config = config,
                .history = history,
                .time_window = config.default_time_window,
            };
        }

        /// Clean up resources
        pub fn deinit(self: *Self) void {
            self.allocator.free(self.history);
        }

        /// Update the tracker (call every frame)
        pub fn update(self: *Self, delta_time: f32, get_amounts: *const fn (ResourceType) f64) void {
            self.game_time += delta_time;
            self.time_since_sample += delta_time;

            if (self.time_since_sample >= self.config.sample_interval) {
                self.takeSample(get_amounts);
                self.time_since_sample = 0;
            }
        }

        /// Update with direct amounts (alternative to callback)
        pub fn updateWithAmounts(self: *Self, delta_time: f32, amounts: [field_count]f64) void {
            self.game_time += delta_time;
            self.time_since_sample += delta_time;

            if (self.time_since_sample >= self.config.sample_interval) {
                self.takeSampleDirect(amounts);
                self.time_since_sample = 0;
            }
        }

        fn takeSample(self: *Self, get_amounts: *const fn (ResourceType) f64) void {
            var amounts: [field_count]f64 = undefined;
            inline for (resource_info.@"enum".fields, 0..) |field, i| {
                amounts[i] = get_amounts(@enumFromInt(field.value));
            }
            self.takeSampleDirect(amounts);
        }

        fn takeSampleDirect(self: *Self, amounts: [field_count]f64) void {
            if (self.has_previous) {
                // Calculate rates
                for (0..field_count) |i| {
                    const delta = amounts[i] - self.previous_amounts[i];
                    self.current_rates[i] = delta / self.config.sample_interval;
                }
            }

            // Store sample
            const sample = SampleType{
                .timestamp = self.game_time,
                .rates = self.current_rates,
                .amounts = amounts,
            };

            if (self.history_count < self.history.len) {
                self.history[self.history_count] = sample;
                self.history_count += 1;
            } else {
                self.history[self.history_head] = sample;
                self.history_head = (self.history_head + 1) % self.history.len;
            }

            // Update previous
            self.previous_amounts = amounts;
            self.has_previous = true;
        }

        /// Force a sample now
        pub fn forceSample(self: *Self, get_amounts: *const fn (ResourceType) f64) void {
            self.takeSample(get_amounts);
            self.time_since_sample = 0;
        }

        /// Clear all history
        pub fn clear(self: *Self) void {
            self.has_previous = false;
            self.history_head = 0;
            self.history_count = 0;
            self.time_since_sample = 0;
            @memset(&self.previous_amounts, 0);
            @memset(&self.current_rates, 0);
        }

        // ====== Rate Queries ======

        /// Get current rate for a resource (units per second)
        pub fn getRate(self: *const Self, resource: ResourceType) f64 {
            return self.current_rates[@intFromEnum(resource)];
        }

        /// Get rate per minute
        pub fn getRatePerMinute(self: *const Self, resource: ResourceType) f64 {
            return self.getRate(resource) * 60.0;
        }

        /// Get rate per hour
        pub fn getRatePerHour(self: *const Self, resource: ResourceType) f64 {
            return self.getRate(resource) * 3600.0;
        }

        /// Format rate as string
        pub fn formatRate(self: *const Self, resource: ResourceType, buf: []u8) []const u8 {
            const rate = self.getRate(resource);
            const rate_int = @as(i64, @intFromFloat(@round(rate)));

            if (rate_int == 0) {
                return std.fmt.bufPrint(buf, "0/s", .{}) catch "?/s";
            } else if (rate_int > 0) {
                return std.fmt.bufPrint(buf, "+{d}/s", .{rate_int}) catch "?/s";
            } else {
                return std.fmt.bufPrint(buf, "{d}/s", .{rate_int}) catch "?/s";
            }
        }

        /// Check if rate is positive (producing)
        pub fn isProducing(self: *const Self, resource: ResourceType) bool {
            return self.getRate(resource) > 0;
        }

        /// Check if rate is negative (consuming)
        pub fn isConsuming(self: *const Self, resource: ResourceType) bool {
            return self.getRate(resource) < 0;
        }

        // ====== Time Window Operations ======

        /// Cycle to next time window
        pub fn cycleTimeWindow(self: *Self) void {
            self.time_window = self.time_window.cycle();
        }

        /// Cycle to next view mode
        pub fn cycleViewMode(self: *Self) void {
            self.view_mode = self.view_mode.cycle();
        }

        /// Get samples within current time window
        pub fn getWindowSamples(self: *const Self, allocator: std.mem.Allocator) ![]const SampleType {
            const window_start = self.game_time - self.time_window.getSeconds();
            var list = std.ArrayList(SampleType).init(allocator);

            for (0..self.history_count) |logical_i| {
                const sample = self.getSampleAt(logical_i) orelse continue;
                if (sample.timestamp >= window_start) {
                    try list.append(sample);
                }
            }

            return list.toOwnedSlice();
        }

        /// Get sample at logical index (0 = oldest in buffer)
        pub fn getSampleAt(self: *const Self, logical_index: usize) ?SampleType {
            if (logical_index >= self.history_count) return null;

            const physical_index = (self.history_head + logical_index) % self.history.len;
            return self.history[physical_index];
        }

        /// Get window range indices
        pub fn getWindowRange(self: *const Self) struct { start: usize, count: usize } {
            const window_start = self.game_time - self.time_window.getSeconds();

            var start_idx: usize = 0;
            for (0..self.history_count) |i| {
                const sample = self.getSampleAt(i) orelse continue;
                if (sample.timestamp >= window_start) {
                    start_idx = i;
                    break;
                }
            }

            return .{
                .start = start_idx,
                .count = self.history_count - start_idx,
            };
        }

        // ====== Statistics ======

        /// Get average rate over time window
        pub fn getAverageRate(self: *const Self, resource: ResourceType) f64 {
            const range = self.getWindowRange();
            if (range.count == 0) return 0;

            const idx = @intFromEnum(resource);
            var sum: f64 = 0;

            for (range.start..range.start + range.count) |i| {
                const sample = self.getSampleAt(i) orelse continue;
                sum += sample.rates[idx];
            }

            return sum / @as(f64, @floatFromInt(range.count));
        }

        /// Get min/max rates over time window
        pub fn getRateRange(self: *const Self, resource: ResourceType) struct { min: f64, max: f64 } {
            const range = self.getWindowRange();
            if (range.count == 0) return .{ .min = 0, .max = 0 };

            const idx = @intFromEnum(resource);
            var min_val: f64 = std.math.inf(f64);
            var max_val: f64 = -std.math.inf(f64);

            for (range.start..range.start + range.count) |i| {
                const sample = self.getSampleAt(i) orelse continue;
                const rate = sample.rates[idx];
                min_val = @min(min_val, rate);
                max_val = @max(max_val, rate);
            }

            // Add padding for graph display
            const padding = (max_val - min_val) * 0.1;
            const min_padding = if (padding < 1) @as(f64, 1) else padding;

            return .{
                .min = min_val - min_padding,
                .max = max_val + min_padding,
            };
        }

        /// Get standard deviation of rate
        pub fn getRateStdDev(self: *const Self, resource: ResourceType) f64 {
            const range = self.getWindowRange();
            if (range.count < 2) return 0;

            const avg = self.getAverageRate(resource);
            const idx = @intFromEnum(resource);
            var sum_sq: f64 = 0;

            for (range.start..range.start + range.count) |i| {
                const sample = self.getSampleAt(i) orelse continue;
                const diff = sample.rates[idx] - avg;
                sum_sq += diff * diff;
            }

            return @sqrt(sum_sq / @as(f64, @floatFromInt(range.count - 1)));
        }

        // ====== Stability Analysis ======

        /// Get stability status for a resource
        pub fn getStability(self: *const Self, resource: ResourceType) StabilityStatus {
            const window_start = self.game_time - self.config.stability_window;
            const idx = @intFromEnum(resource);

            var stable_count: usize = 0;
            var total_count: usize = 0;

            for (0..self.history_count) |i| {
                const sample = self.getSampleAt(i) orelse continue;
                if (sample.timestamp >= window_start) {
                    total_count += 1;
                    if (sample.rates[idx] >= 0) {
                        stable_count += 1;
                    }
                }
            }

            if (total_count < self.config.min_stability_samples) {
                return .analyzing;
            }

            const ratio = @as(f32, @floatFromInt(stable_count)) / @as(f32, @floatFromInt(total_count));
            return if (ratio >= 0.9) .stable else .unstable;
        }

        /// Get overall stability (all resources)
        pub fn getOverallStability(self: *const Self) StabilityStatus {
            var any_unknown = false;
            var all_stable = true;

            inline for (resource_info.@"enum".fields, 0..) |_, i| {
                const resource: ResourceType = @enumFromInt(i);
                const status = self.getStability(resource);
                switch (status) {
                    .analyzing => any_unknown = true,
                    .unstable => all_stable = false,
                    .stable => {},
                }
            }

            if (any_unknown) return .analyzing;
            return if (all_stable) .stable else .unstable;
        }

        /// Check if production ratio is balanced (for graphs)
        pub fn isBalanced(self: *const Self, resource: ResourceType, tolerance: f32) bool {
            const rate = self.getRate(resource);
            const abs_rate = @abs(rate);
            return abs_rate <= tolerance;
        }

        // ====== Graph Data Helpers ======

        /// Get data points for graphing a resource rate
        pub fn getGraphData(self: *const Self, resource: ResourceType, allocator: std.mem.Allocator) ![]const struct { time: f64, value: f64 } {
            const DataPoint = struct { time: f64, value: f64 };
            var list = std.ArrayList(DataPoint).init(allocator);

            const range = self.getWindowRange();
            const idx = @intFromEnum(resource);

            for (range.start..range.start + range.count) |i| {
                const sample = self.getSampleAt(i) orelse continue;
                try list.append(.{
                    .time = sample.timestamp,
                    .value = sample.rates[idx],
                });
            }

            return list.toOwnedSlice();
        }

        /// Get the number of samples in history
        pub fn getSampleCount(self: *const Self) usize {
            return self.history_count;
        }

        /// Get current game time
        pub fn getGameTime(self: *const Self) f64 {
            return self.game_time;
        }

        // ====== Utility ======

        /// Get all current rates
        pub fn getAllRates(self: *const Self) [field_count]f64 {
            return self.current_rates;
        }

        /// Get net rate (sum of all resources, useful for "total throughput")
        pub fn getNetRate(self: *const Self) f64 {
            var sum: f64 = 0;
            for (self.current_rates) |rate| {
                sum += rate;
            }
            return sum;
        }

        /// Check if any resource is being consumed faster than produced
        pub fn hasDeficit(self: *const Self) bool {
            for (self.current_rates) |rate| {
                if (rate < -0.001) return true;
            }
            return false;
        }

        /// Get resource with highest consumption rate
        pub fn getMostConsumed(self: *const Self) ?ResourceType {
            var min_rate: f64 = 0;
            var min_resource: ?ResourceType = null;

            inline for (resource_info.@"enum".fields, 0..) |_, i| {
                const rate = self.current_rates[i];
                if (rate < min_rate) {
                    min_rate = rate;
                    min_resource = @enumFromInt(i);
                }
            }

            return min_resource;
        }

        /// Get resource with highest production rate
        pub fn getMostProduced(self: *const Self) ?ResourceType {
            var max_rate: f64 = 0;
            var max_resource: ?ResourceType = null;

            inline for (resource_info.@"enum".fields, 0..) |_, i| {
                const rate = self.current_rates[i];
                if (rate > max_rate) {
                    max_rate = rate;
                    max_resource = @enumFromInt(i);
                }
            }

            return max_resource;
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

const TestResource = enum { iron, copper, energy, carbon };

fn testGetAmounts(resource: TestResource) f64 {
    _ = resource;
    return 100; // Simple constant for testing
}

test "RateTracker - init and deinit" {
    var tracker = try RateTracker(TestResource).init(std.testing.allocator, .{});
    defer tracker.deinit();

    try std.testing.expectEqual(@as(usize, 0), tracker.getSampleCount());
}

test "RateTracker - basic rate tracking" {
    var tracker = try RateTracker(TestResource).init(std.testing.allocator, .{
        .sample_interval = 1.0,
    });
    defer tracker.deinit();

    // First sample
    tracker.updateWithAmounts(0.5, .{ 100, 50, 200, 10 });
    tracker.updateWithAmounts(0.5, .{ 100, 50, 200, 10 }); // Triggers sample

    // Second sample with changes
    tracker.updateWithAmounts(0.5, .{ 110, 45, 200, 15 });
    tracker.updateWithAmounts(0.5, .{ 110, 45, 200, 15 }); // Triggers sample

    // Iron went from 100 to 110 = +10/s
    try std.testing.expectApproxEqAbs(@as(f64, 10), tracker.getRate(.iron), 0.01);
    // Copper went from 50 to 45 = -5/s
    try std.testing.expectApproxEqAbs(@as(f64, -5), tracker.getRate(.copper), 0.01);
}

test "RateTracker - rate per minute/hour" {
    var tracker = try RateTracker(TestResource).init(std.testing.allocator, .{
        .sample_interval = 1.0,
    });
    defer tracker.deinit();

    tracker.updateWithAmounts(1.0, .{ 0, 0, 0, 0 });
    tracker.updateWithAmounts(1.0, .{ 10, 0, 0, 0 });

    try std.testing.expectApproxEqAbs(@as(f64, 10), tracker.getRate(.iron), 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 600), tracker.getRatePerMinute(.iron), 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 36000), tracker.getRatePerHour(.iron), 0.01);
}

test "RateTracker - producing/consuming" {
    var tracker = try RateTracker(TestResource).init(std.testing.allocator, .{
        .sample_interval = 1.0,
    });
    defer tracker.deinit();

    tracker.updateWithAmounts(1.0, .{ 0, 100, 0, 0 });
    tracker.updateWithAmounts(1.0, .{ 10, 90, 0, 0 });

    try std.testing.expect(tracker.isProducing(.iron));
    try std.testing.expect(!tracker.isConsuming(.iron));

    try std.testing.expect(!tracker.isProducing(.copper));
    try std.testing.expect(tracker.isConsuming(.copper));
}

test "RateTracker - time window cycling" {
    var tracker = try RateTracker(TestResource).init(std.testing.allocator, .{});
    defer tracker.deinit();

    try std.testing.expectEqual(TimeWindow.seconds_30, tracker.time_window);

    tracker.cycleTimeWindow();
    try std.testing.expectEqual(TimeWindow.seconds_60, tracker.time_window);

    tracker.cycleTimeWindow();
    try std.testing.expectEqual(TimeWindow.seconds_10, tracker.time_window);
}

test "RateTracker - view mode cycling" {
    var tracker = try RateTracker(TestResource).init(std.testing.allocator, .{});
    defer tracker.deinit();

    try std.testing.expectEqual(ViewMode.absolute, tracker.view_mode);

    tracker.cycleViewMode();
    try std.testing.expectEqual(ViewMode.ratio, tracker.view_mode);
}

test "RateTracker - stability analysis" {
    var tracker = try RateTracker(TestResource).init(std.testing.allocator, .{
        .sample_interval = 0.5,
        .stability_window = 3.0,
        .min_stability_samples = 3,
    });
    defer tracker.deinit();

    // Not enough samples yet
    tracker.updateWithAmounts(0.5, .{ 100, 0, 0, 0 });
    try std.testing.expectEqual(StabilityStatus.analyzing, tracker.getStability(.iron));

    // Add stable samples (rate >= 0)
    tracker.updateWithAmounts(0.5, .{ 110, 0, 0, 0 });
    tracker.updateWithAmounts(0.5, .{ 120, 0, 0, 0 });
    tracker.updateWithAmounts(0.5, .{ 130, 0, 0, 0 });
    tracker.updateWithAmounts(0.5, .{ 140, 0, 0, 0 });

    try std.testing.expectEqual(StabilityStatus.stable, tracker.getStability(.iron));
}

test "RateTracker - clear" {
    var tracker = try RateTracker(TestResource).init(std.testing.allocator, .{
        .sample_interval = 1.0,
    });
    defer tracker.deinit();

    tracker.updateWithAmounts(1.0, .{ 100, 0, 0, 0 });
    tracker.updateWithAmounts(1.0, .{ 200, 0, 0, 0 });

    try std.testing.expect(tracker.getSampleCount() > 0);

    tracker.clear();

    try std.testing.expectEqual(@as(usize, 0), tracker.getSampleCount());
    try std.testing.expectApproxEqAbs(@as(f64, 0), tracker.getRate(.iron), 0.01);
}

test "RateTracker - average rate" {
    var tracker = try RateTracker(TestResource).init(std.testing.allocator, .{
        .sample_interval = 1.0,
        .default_time_window = .seconds_60,
    });
    defer tracker.deinit();

    // Create samples with varying rates
    tracker.updateWithAmounts(1.0, .{ 0, 0, 0, 0 });
    tracker.updateWithAmounts(1.0, .{ 10, 0, 0, 0 }); // +10
    tracker.updateWithAmounts(1.0, .{ 30, 0, 0, 0 }); // +20
    tracker.updateWithAmounts(1.0, .{ 60, 0, 0, 0 }); // +30

    // Average of 0, 10, 20, 30 = 15 (first sample has no rate)
    const avg = tracker.getAverageRate(.iron);
    try std.testing.expect(avg > 0);
}

test "RateTracker - most produced/consumed" {
    var tracker = try RateTracker(TestResource).init(std.testing.allocator, .{
        .sample_interval = 1.0,
    });
    defer tracker.deinit();

    tracker.updateWithAmounts(1.0, .{ 0, 100, 0, 50 });
    tracker.updateWithAmounts(1.0, .{ 100, 50, 0, 30 }); // iron +100, copper -50, carbon -20

    try std.testing.expectEqual(@as(?TestResource, .iron), tracker.getMostProduced());
    try std.testing.expectEqual(@as(?TestResource, .copper), tracker.getMostConsumed());
}

test "RateTracker - has deficit" {
    var tracker = try RateTracker(TestResource).init(std.testing.allocator, .{
        .sample_interval = 1.0,
    });
    defer tracker.deinit();

    tracker.updateWithAmounts(1.0, .{ 100, 100, 100, 100 });
    tracker.updateWithAmounts(1.0, .{ 110, 110, 110, 110 }); // All increasing

    try std.testing.expect(!tracker.hasDeficit());

    tracker.updateWithAmounts(1.0, .{ 120, 100, 120, 120 }); // Copper decreasing

    try std.testing.expect(tracker.hasDeficit());
}

test "RateTracker - format rate" {
    var tracker = try RateTracker(TestResource).init(std.testing.allocator, .{
        .sample_interval = 1.0,
    });
    defer tracker.deinit();

    tracker.updateWithAmounts(1.0, .{ 0, 100, 50, 0 });
    tracker.updateWithAmounts(1.0, .{ 10, 90, 50, 0 });

    var buf: [32]u8 = undefined;

    const iron_str = tracker.formatRate(.iron, &buf);
    try std.testing.expect(std.mem.indexOf(u8, iron_str, "+") != null);

    const copper_str = tracker.formatRate(.copper, &buf);
    try std.testing.expect(std.mem.indexOf(u8, copper_str, "-") != null);

    const energy_str = tracker.formatRate(.energy, &buf);
    try std.testing.expectEqualStrings("0/s", energy_str);
}

test "RateTracker - circular buffer" {
    var tracker = try RateTracker(TestResource).init(std.testing.allocator, .{
        .sample_interval = 0.1,
        .history_size = 5,
    });
    defer tracker.deinit();

    // Fill and overflow the buffer
    for (0..10) |i| {
        tracker.updateWithAmounts(0.1, .{ @floatFromInt(i * 10), 0, 0, 0 });
    }

    // Should only have 5 samples
    try std.testing.expectEqual(@as(usize, 5), tracker.getSampleCount());
}

test "RateTracker - TimeWindow helpers" {
    try std.testing.expectEqual(@as(f32, 10.0), TimeWindow.seconds_10.getSeconds());
    try std.testing.expectEqual(@as(f32, 30.0), TimeWindow.seconds_30.getSeconds());
    try std.testing.expectEqual(@as(f32, 60.0), TimeWindow.seconds_60.getSeconds());

    try std.testing.expectEqualStrings("10s", TimeWindow.seconds_10.getName());
}

test "RateTracker - StabilityStatus helpers" {
    try std.testing.expectEqualStrings("STABLE", StabilityStatus.stable.getName());
    try std.testing.expectEqualStrings("UNSTABLE", StabilityStatus.unstable.getName());
    try std.testing.expectEqualStrings("ANALYZING...", StabilityStatus.analyzing.getName());
}

test "RateTracker - ViewMode helpers" {
    try std.testing.expectEqualStrings("Absolute", ViewMode.absolute.getName());
    try std.testing.expectEqualStrings("Ratio %", ViewMode.ratio.getName());
}

test "RateTracker - get graph data" {
    var tracker = try RateTracker(TestResource).init(std.testing.allocator, .{
        .sample_interval = 1.0,
    });
    defer tracker.deinit();

    tracker.updateWithAmounts(1.0, .{ 0, 0, 0, 0 });
    tracker.updateWithAmounts(1.0, .{ 10, 0, 0, 0 });
    tracker.updateWithAmounts(1.0, .{ 20, 0, 0, 0 });

    const data = try tracker.getGraphData(.iron, std.testing.allocator);
    defer std.testing.allocator.free(data);

    try std.testing.expect(data.len > 0);
}

test "RateTracker - rate range" {
    var tracker = try RateTracker(TestResource).init(std.testing.allocator, .{
        .sample_interval = 1.0,
    });
    defer tracker.deinit();

    tracker.updateWithAmounts(1.0, .{ 0, 0, 0, 0 });
    tracker.updateWithAmounts(1.0, .{ 10, 0, 0, 0 }); // +10
    tracker.updateWithAmounts(1.0, .{ 30, 0, 0, 0 }); // +20
    tracker.updateWithAmounts(1.0, .{ 35, 0, 0, 0 }); // +5

    const range = tracker.getRateRange(.iron);
    try std.testing.expect(range.max > range.min);
}

test "RateTracker - net rate" {
    var tracker = try RateTracker(TestResource).init(std.testing.allocator, .{
        .sample_interval = 1.0,
    });
    defer tracker.deinit();

    tracker.updateWithAmounts(1.0, .{ 0, 100, 0, 50 });
    tracker.updateWithAmounts(1.0, .{ 100, 50, 20, 30 }); // +100 -50 +20 -20 = +50

    try std.testing.expectApproxEqAbs(@as(f64, 50), tracker.getNetRate(), 0.01);
}
