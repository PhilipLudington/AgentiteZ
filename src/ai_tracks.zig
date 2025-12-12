const std = @import("std");
const Allocator = std.mem.Allocator;
const blackboard = @import("blackboard.zig");

/// AI Tracks System - Parallel decision tracks for AI agents
///
/// Enables AI to have multiple concurrent decision-making tracks that
/// operate independently but coordinate when needed. Each track focuses
/// on a specific domain (combat, economy, diplomacy, etc.) and produces
/// recommendations with urgency scores.
///
/// Key concepts:
/// - **Tracks**: Independent decision domains (combat, economy, diplomacy)
/// - **Track Priority**: Base importance weighting for track decisions
/// - **Urgency**: Dynamic importance based on current situation
/// - **Recommendations**: Suggested actions with scores and metadata
/// - **Coordination**: Cross-track communication and conflict resolution
///
/// Example usage:
/// ```zig
/// var ai = AITrackSystem.init(allocator);
/// defer ai.deinit();
///
/// // Define tracks
/// try ai.addTrack("combat", .{ .priority = 0.8, .update_fn = combatUpdate });
/// try ai.addTrack("economy", .{ .priority = 0.6, .update_fn = economyUpdate });
/// try ai.addTrack("diplomacy", .{ .priority = 0.4, .update_fn = diplomacyUpdate });
///
/// // Update all tracks
/// try ai.update(&game_state);
///
/// // Get best recommendation across all tracks
/// if (ai.getBestRecommendation()) |rec| {
///     executeAction(rec.action, rec.target_id);
/// }
/// ```

/// Maximum length for track/action names
pub const MAX_NAME_LENGTH: usize = 63;

/// Maximum number of tracks
pub const MAX_TRACKS: usize = 16;

/// Maximum recommendations per track
pub const MAX_RECOMMENDATIONS: usize = 32;

/// Maximum tags per recommendation
pub const MAX_TAGS: usize = 8;

/// Action types that tracks can recommend
pub const ActionType = enum(u8) {
    // Combat actions
    attack,
    defend,
    retreat,
    reinforce,
    flank,
    siege,

    // Economy actions
    gather,
    build,
    upgrade,
    trade,
    expand,
    stockpile,

    // Diplomacy actions
    negotiate,
    ally,
    declare_war,
    peace_offer,
    tribute,
    embargo,

    // General actions
    scout,
    research,
    wait,
    custom,
};

/// A recommendation from a track
pub const Recommendation = struct {
    action: ActionType,
    score: f32, // Combined urgency * priority score
    urgency: f32, // How urgent is this action (0.0 - 1.0)
    target_id: ?u32 = null, // Optional target entity
    location_x: ?f32 = null, // Optional target location
    location_y: ?f32 = null,
    track_name: [MAX_NAME_LENGTH + 1]u8,
    track_name_len: u8,
    reason: [255]u8, // Explanation for debugging
    reason_len: u8,
    tags: [MAX_TAGS][MAX_NAME_LENGTH + 1]u8,
    tag_lens: [MAX_TAGS]u8,
    tag_count: u8,

    pub fn getTrackName(self: *const Recommendation) []const u8 {
        return self.track_name[0..self.track_name_len];
    }

    pub fn getReason(self: *const Recommendation) []const u8 {
        return self.reason[0..self.reason_len];
    }

    pub fn getTag(self: *const Recommendation, index: usize) []const u8 {
        if (index >= self.tag_count) return "";
        return self.tags[index][0..self.tag_lens[index]];
    }

    pub fn hasTag(self: *const Recommendation, tag: []const u8) bool {
        for (0..self.tag_count) |i| {
            if (std.mem.eql(u8, self.getTag(i), tag)) return true;
        }
        return false;
    }
};

/// Track update function signature
pub const TrackUpdateFn = *const fn (
    track: *Track,
    context: ?*anyopaque,
    bb: *blackboard.Blackboard,
) void;

/// Track configuration
pub const TrackConfig = struct {
    priority: f32 = 1.0, // Base priority weight (0.0 - 1.0)
    update_fn: ?TrackUpdateFn = null,
    enabled: bool = true,
    cooldown: f32 = 0.0, // Minimum time between updates
    userdata: ?*anyopaque = null,
};

/// An AI decision track
pub const Track = struct {
    name: [MAX_NAME_LENGTH + 1]u8,
    name_len: u8,
    priority: f32,
    urgency: f32, // Current urgency level (0.0 - 1.0)
    enabled: bool,
    update_fn: ?TrackUpdateFn,
    userdata: ?*anyopaque,
    cooldown: f32,
    cooldown_remaining: f32,

    // Recommendations from this track
    recommendations: std.ArrayList(Recommendation),

    // Track-specific state (shared blackboard)
    state: blackboard.Blackboard,

    // Statistics
    updates: usize,
    recommendations_made: usize,

    pub fn getName(self: *const Track) []const u8 {
        return self.name[0..self.name_len];
    }

    /// Initialize track
    pub fn init(allocator: Allocator, name: []const u8, config: TrackConfig) !Track {
        if (name.len > MAX_NAME_LENGTH) return error.NameTooLong;

        var track: Track = undefined;
        @memcpy(track.name[0..name.len], name);
        track.name_len = @intCast(name.len);
        track.priority = config.priority;
        track.urgency = 0.0;
        track.enabled = config.enabled;
        track.update_fn = config.update_fn;
        track.userdata = config.userdata;
        track.cooldown = config.cooldown;
        track.cooldown_remaining = 0.0;
        track.recommendations = std.ArrayList(Recommendation).init(allocator);
        track.state = blackboard.Blackboard.init(allocator);
        track.updates = 0;
        track.recommendations_made = 0;

        return track;
    }

    /// Deinitialize track
    pub fn deinit(self: *Track) void {
        self.recommendations.deinit();
        self.state.deinit();
    }

    /// Clear recommendations
    pub fn clearRecommendations(self: *Track) void {
        self.recommendations.clearRetainingCapacity();
    }

    /// Add a recommendation
    pub fn recommend(self: *Track, action: ActionType, urgency: f32, reason: []const u8) !void {
        try self.recommendEx(action, urgency, reason, .{});
    }

    /// Add a recommendation with extended options
    pub fn recommendEx(self: *Track, action: ActionType, urgency: f32, reason: []const u8, options: struct {
        target_id: ?u32 = null,
        location_x: ?f32 = null,
        location_y: ?f32 = null,
        tags: []const []const u8 = &.{},
    }) !void {
        if (self.recommendations.items.len >= MAX_RECOMMENDATIONS) {
            // Remove lowest scored recommendation
            var min_idx: usize = 0;
            var min_score: f32 = std.math.inf(f32);
            for (self.recommendations.items, 0..) |*rec, i| {
                if (rec.score < min_score) {
                    min_score = rec.score;
                    min_idx = i;
                }
            }
            _ = self.recommendations.swapRemove(min_idx);
        }

        var rec: Recommendation = undefined;
        rec.action = action;
        rec.urgency = std.math.clamp(urgency, 0.0, 1.0);
        rec.score = rec.urgency * self.priority;
        rec.target_id = options.target_id;
        rec.location_x = options.location_x;
        rec.location_y = options.location_y;

        // Copy track name
        @memcpy(rec.track_name[0..self.name_len], self.name[0..self.name_len]);
        rec.track_name_len = self.name_len;

        // Copy reason
        const reason_len = @min(reason.len, rec.reason.len);
        @memcpy(rec.reason[0..reason_len], reason[0..reason_len]);
        rec.reason_len = @intCast(reason_len);

        // Copy tags
        rec.tag_count = @intCast(@min(options.tags.len, MAX_TAGS));
        for (0..rec.tag_count) |i| {
            const tag = options.tags[i];
            const tag_len = @min(tag.len, MAX_NAME_LENGTH);
            @memcpy(rec.tags[i][0..tag_len], tag[0..tag_len]);
            rec.tag_lens[i] = @intCast(tag_len);
        }

        try self.recommendations.append(rec);
        self.recommendations_made += 1;
    }

    /// Set track urgency
    pub fn setUrgency(self: *Track, urgency: f32) void {
        self.urgency = std.math.clamp(urgency, 0.0, 1.0);

        // Update all recommendation scores
        for (self.recommendations.items) |*rec| {
            rec.score = rec.urgency * self.priority * (0.5 + 0.5 * self.urgency);
        }
    }

    /// Get top recommendation from this track
    pub fn getTopRecommendation(self: *const Track) ?*const Recommendation {
        if (self.recommendations.items.len == 0) return null;

        var best: ?*const Recommendation = null;
        var best_score: f32 = -std.math.inf(f32);

        for (self.recommendations.items) |*rec| {
            if (rec.score > best_score) {
                best_score = rec.score;
                best = rec;
            }
        }

        return best;
    }
};

/// AI Track System statistics
pub const AITrackStats = struct {
    track_count: usize,
    total_recommendations: usize,
    total_updates: usize,
    enabled_tracks: usize,
};

/// AI Track System - manages multiple decision tracks
pub const AITrackSystem = struct {
    allocator: Allocator,
    tracks: std.ArrayList(Track),
    shared_state: blackboard.Blackboard, // Cross-track communication
    total_updates: usize,

    /// Configuration
    pub const Config = struct {
        initial_track_capacity: usize = 8,
    };

    /// Initialize system
    pub fn init(allocator: Allocator) AITrackSystem {
        return initWithConfig(allocator, .{});
    }

    /// Initialize with configuration
    pub fn initWithConfig(allocator: Allocator, config: Config) AITrackSystem {
        _ = config;
        return .{
            .allocator = allocator,
            .tracks = std.ArrayList(Track).init(allocator),
            .shared_state = blackboard.Blackboard.init(allocator),
            .total_updates = 0,
        };
    }

    /// Deinitialize
    pub fn deinit(self: *AITrackSystem) void {
        for (self.tracks.items) |*track| {
            track.deinit();
        }
        self.tracks.deinit();
        self.shared_state.deinit();
    }

    /// Add a track
    pub fn addTrack(self: *AITrackSystem, name: []const u8, config: TrackConfig) !void {
        if (self.getTrack(name) != null) return error.DuplicateTrack;
        if (self.tracks.items.len >= MAX_TRACKS) return error.TooManyTracks;

        const track = try Track.init(self.allocator, name, config);
        try self.tracks.append(track);
    }

    /// Remove a track
    pub fn removeTrack(self: *AITrackSystem, name: []const u8) bool {
        for (self.tracks.items, 0..) |*track, i| {
            if (std.mem.eql(u8, track.getName(), name)) {
                track.deinit();
                _ = self.tracks.swapRemove(i);
                return true;
            }
        }
        return false;
    }

    /// Get track by name
    pub fn getTrack(self: *AITrackSystem, name: []const u8) ?*Track {
        for (self.tracks.items) |*track| {
            if (std.mem.eql(u8, track.getName(), name)) {
                return track;
            }
        }
        return null;
    }

    /// Get track by name (const)
    pub fn getTrackConst(self: *const AITrackSystem, name: []const u8) ?*const Track {
        for (self.tracks.items) |*track| {
            if (std.mem.eql(u8, track.getName(), name)) {
                return track;
            }
        }
        return null;
    }

    /// Enable/disable a track
    pub fn setTrackEnabled(self: *AITrackSystem, name: []const u8, enabled: bool) bool {
        if (self.getTrack(name)) |track| {
            track.enabled = enabled;
            return true;
        }
        return false;
    }

    /// Set track priority
    pub fn setTrackPriority(self: *AITrackSystem, name: []const u8, priority: f32) bool {
        if (self.getTrack(name)) |track| {
            track.priority = std.math.clamp(priority, 0.0, 1.0);
            return true;
        }
        return false;
    }

    /// Set track urgency
    pub fn setTrackUrgency(self: *AITrackSystem, name: []const u8, urgency: f32) bool {
        if (self.getTrack(name)) |track| {
            track.setUrgency(urgency);
            return true;
        }
        return false;
    }

    /// Update all tracks
    pub fn update(self: *AITrackSystem, context: ?*anyopaque) void {
        self.updateWithDelta(context, 0.0);
    }

    /// Update all tracks with delta time
    pub fn updateWithDelta(self: *AITrackSystem, context: ?*anyopaque, delta: f32) void {
        for (self.tracks.items) |*track| {
            if (!track.enabled) continue;

            // Handle cooldown
            if (track.cooldown_remaining > 0) {
                track.cooldown_remaining -= delta;
                if (track.cooldown_remaining > 0) continue;
            }

            // Clear previous recommendations
            track.clearRecommendations();

            // Call update function
            if (track.update_fn) |update_fn| {
                update_fn(track, context, &self.shared_state);
            }

            track.updates += 1;
            track.cooldown_remaining = track.cooldown;
        }

        self.total_updates += 1;
    }

    /// Get best recommendation across all tracks
    pub fn getBestRecommendation(self: *const AITrackSystem) ?*const Recommendation {
        var best: ?*const Recommendation = null;
        var best_score: f32 = -std.math.inf(f32);

        for (self.tracks.items) |*track| {
            if (!track.enabled) continue;

            for (track.recommendations.items) |*rec| {
                if (rec.score > best_score) {
                    best_score = rec.score;
                    best = rec;
                }
            }
        }

        return best;
    }

    /// Get top N recommendations across all tracks
    pub fn getTopRecommendations(self: *const AITrackSystem, allocator: Allocator, max_count: usize) ![]const Recommendation {
        // Collect all recommendations
        var all = std.ArrayList(Recommendation).init(allocator);
        defer all.deinit();

        for (self.tracks.items) |*track| {
            if (!track.enabled) continue;
            for (track.recommendations.items) |rec| {
                try all.append(rec);
            }
        }

        // Sort by score (descending)
        std.mem.sort(Recommendation, all.items, {}, struct {
            fn cmp(_: void, a: Recommendation, b: Recommendation) bool {
                return a.score > b.score;
            }
        }.cmp);

        // Return top N
        const result_count = @min(max_count, all.items.len);
        const result = try allocator.alloc(Recommendation, result_count);
        @memcpy(result, all.items[0..result_count]);
        return result;
    }

    /// Get recommendations filtered by action type
    pub fn getRecommendationsByAction(self: *const AITrackSystem, allocator: Allocator, action: ActionType) ![]const Recommendation {
        var filtered = std.ArrayList(Recommendation).init(allocator);
        errdefer filtered.deinit();

        for (self.tracks.items) |*track| {
            if (!track.enabled) continue;
            for (track.recommendations.items) |rec| {
                if (rec.action == action) {
                    try filtered.append(rec);
                }
            }
        }

        return filtered.toOwnedSlice();
    }

    /// Get recommendations filtered by tag
    pub fn getRecommendationsByTag(self: *const AITrackSystem, allocator: Allocator, tag: []const u8) ![]const Recommendation {
        var filtered = std.ArrayList(Recommendation).init(allocator);
        errdefer filtered.deinit();

        for (self.tracks.items) |*track| {
            if (!track.enabled) continue;
            for (track.recommendations.items) |*rec| {
                if (rec.hasTag(tag)) {
                    try filtered.append(rec.*);
                }
            }
        }

        return filtered.toOwnedSlice();
    }

    /// Clear all recommendations
    pub fn clearAllRecommendations(self: *AITrackSystem) void {
        for (self.tracks.items) |*track| {
            track.clearRecommendations();
        }
    }

    /// Get track count
    pub fn getTrackCount(self: *const AITrackSystem) usize {
        return self.tracks.items.len;
    }

    /// Get total recommendation count
    pub fn getTotalRecommendations(self: *const AITrackSystem) usize {
        var total: usize = 0;
        for (self.tracks.items) |*track| {
            total += track.recommendations.items.len;
        }
        return total;
    }

    /// Get statistics
    pub fn getStats(self: *const AITrackSystem) AITrackStats {
        var enabled: usize = 0;
        var recommendations: usize = 0;

        for (self.tracks.items) |*track| {
            if (track.enabled) enabled += 1;
            recommendations += track.recommendations.items.len;
        }

        return .{
            .track_count = self.tracks.items.len,
            .total_recommendations = recommendations,
            .total_updates = self.total_updates,
            .enabled_tracks = enabled,
        };
    }

    /// Get track names
    pub fn getTrackNames(self: *const AITrackSystem, allocator: Allocator) ![][]const u8 {
        var names = try allocator.alloc([]const u8, self.tracks.items.len);
        for (self.tracks.items, 0..) |*track, i| {
            names[i] = track.getName();
        }
        return names;
    }

    /// Post a message to shared state for cross-track communication
    pub fn postMessage(self: *AITrackSystem, key: []const u8, value: blackboard.Value) !void {
        switch (value) {
            .int32 => |v| try self.shared_state.setInt(key, v),
            .int64 => |v| try self.shared_state.setInt64(key, v),
            .float32 => |v| try self.shared_state.setFloat(key, v),
            .float64 => |v| try self.shared_state.setFloat64(key, v),
            .boolean => |v| try self.shared_state.setBool(key, v),
            .string => |v| try self.shared_state.setString(key, v),
            .pointer => |v| try self.shared_state.setPointer(key, v),
            .vec2 => |v| try self.shared_state.setVec2(key, v),
            .vec3 => |v| try self.shared_state.setVec3(key, v),
        }
    }

    /// Get shared state value
    pub fn getMessage(self: *const AITrackSystem, key: []const u8) ?blackboard.Value {
        return self.shared_state.get(key);
    }

    /// Check for conflicting recommendations
    pub fn hasConflict(_: *const AITrackSystem, rec1: *const Recommendation, rec2: *const Recommendation) bool {
        // Same target, conflicting actions
        if (rec1.target_id != null and rec1.target_id == rec2.target_id) {
            // Attack vs Ally is a conflict
            if ((rec1.action == .attack and rec2.action == .ally) or
                (rec1.action == .ally and rec2.action == .attack))
            {
                return true;
            }
            // Attack vs Peace is a conflict
            if ((rec1.action == .attack and rec2.action == .peace_offer) or
                (rec1.action == .peace_offer and rec2.action == .attack))
            {
                return true;
            }
        }
        return false;
    }

    /// Get non-conflicting top recommendations
    pub fn getNonConflictingRecommendations(self: *const AITrackSystem, allocator: Allocator, max_count: usize) ![]const Recommendation {
        const all = try self.getTopRecommendations(allocator, max_count * 2);
        defer allocator.free(all);

        var result = std.ArrayList(Recommendation).init(allocator);
        errdefer result.deinit();

        for (all) |rec| {
            var conflicts = false;
            for (result.items) |*existing| {
                if (self.hasConflict(&rec, existing)) {
                    conflicts = true;
                    break;
                }
            }
            if (!conflicts) {
                try result.append(rec);
                if (result.items.len >= max_count) break;
            }
        }

        return result.toOwnedSlice();
    }
};

// ============================================================
// Predefined Track Update Functions
// ============================================================

/// Combat track - evaluates threats and recommends military actions
pub fn combatTrackUpdate(track: *Track, context: ?*anyopaque, shared: *blackboard.Blackboard) void {
    _ = context;

    // Read shared state for threat info
    const threat_level = shared.getFloatOr("threat_level", 0.0);
    const enemy_count = shared.getIntOr("enemy_count", 0);
    const military_strength = shared.getFloatOr("military_strength", 1.0);

    track.setUrgency(threat_level);

    // Generate recommendations based on situation
    if (threat_level > 0.7 and military_strength < 0.5) {
        track.recommend(.retreat, 0.9, "High threat, low strength - retreat") catch {};
        track.recommend(.reinforce, 0.7, "Need reinforcements") catch {};
    } else if (threat_level > 0.5) {
        track.recommend(.defend, 0.8, "Moderate threat - defend") catch {};
        if (enemy_count > 0) {
            track.recommend(.attack, 0.6, "Counter-attack opportunity") catch {};
        }
    } else if (enemy_count > 0) {
        track.recommend(.attack, 0.7, "Low threat - attack enemies") catch {};
        track.recommend(.scout, 0.4, "Scout for more targets") catch {};
    } else {
        track.recommend(.scout, 0.5, "No threats - scout") catch {};
    }
}

/// Economy track - evaluates resources and recommends economic actions
pub fn economyTrackUpdate(track: *Track, context: ?*anyopaque, shared: *blackboard.Blackboard) void {
    _ = context;

    const resources = shared.getFloatOr("resources", 0.0);
    const production_rate = shared.getFloatOr("production_rate", 0.0);
    const storage_capacity = shared.getFloatOr("storage_capacity", 100.0);

    // Calculate urgency based on resource levels
    const resource_ratio = resources / storage_capacity;
    if (resource_ratio < 0.2) {
        track.setUrgency(0.9);
    } else if (resource_ratio < 0.5) {
        track.setUrgency(0.6);
    } else {
        track.setUrgency(0.3);
    }

    // Generate recommendations
    if (resources < 50) {
        track.recommend(.gather, 0.9, "Critical resource shortage") catch {};
    } else if (resources < storage_capacity * 0.3) {
        track.recommend(.gather, 0.7, "Low resources") catch {};
    }

    if (production_rate < 10) {
        track.recommend(.build, 0.8, "Need production buildings") catch {};
    }

    if (resources > storage_capacity * 0.8) {
        track.recommend(.expand, 0.6, "Resources available for expansion") catch {};
        track.recommend(.trade, 0.5, "Trade excess resources") catch {};
    }
}

/// Diplomacy track - evaluates relationships and recommends diplomatic actions
pub fn diplomacyTrackUpdate(track: *Track, context: ?*anyopaque, shared: *blackboard.Blackboard) void {
    _ = context;

    const relations = shared.getFloatOr("best_relations", 0.0);
    const worst_relations = shared.getFloatOr("worst_relations", 0.0);
    const at_war = shared.getBoolOr("at_war", false);

    // Urgency based on diplomatic situation
    if (at_war and worst_relations < -0.5) {
        track.setUrgency(0.8);
    } else if (worst_relations < -0.3) {
        track.setUrgency(0.6);
    } else {
        track.setUrgency(0.3);
    }

    // Generate recommendations
    if (at_war and relations > 0.3) {
        track.recommend(.peace_offer, 0.7, "Possible peace opportunity") catch {};
    }

    if (relations > 0.5) {
        track.recommend(.ally, 0.6, "Good relations - propose alliance") catch {};
    }

    if (worst_relations < -0.7) {
        track.recommend(.embargo, 0.5, "Economic pressure on enemy") catch {};
    }

    if (!at_war) {
        track.recommend(.negotiate, 0.4, "Maintain diplomatic relations") catch {};
    }
}

// ============================================================
// Tests
// ============================================================

test "AITrackSystem: add and get track" {
    const allocator = std.testing.allocator;
    var ai = AITrackSystem.init(allocator);
    defer ai.deinit();

    try ai.addTrack("combat", .{ .priority = 0.8 });
    try ai.addTrack("economy", .{ .priority = 0.6 });

    try std.testing.expectEqual(@as(usize, 2), ai.getTrackCount());

    const track = ai.getTrack("combat");
    try std.testing.expect(track != null);
    try std.testing.expectEqualStrings("combat", track.?.getName());
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), track.?.priority, 0.001);
}

test "AITrackSystem: duplicate track error" {
    const allocator = std.testing.allocator;
    var ai = AITrackSystem.init(allocator);
    defer ai.deinit();

    try ai.addTrack("combat", .{});
    try std.testing.expectError(error.DuplicateTrack, ai.addTrack("combat", .{}));
}

test "AITrackSystem: remove track" {
    const allocator = std.testing.allocator;
    var ai = AITrackSystem.init(allocator);
    defer ai.deinit();

    try ai.addTrack("combat", .{});
    try std.testing.expectEqual(@as(usize, 1), ai.getTrackCount());

    try std.testing.expect(ai.removeTrack("combat"));
    try std.testing.expectEqual(@as(usize, 0), ai.getTrackCount());

    try std.testing.expect(!ai.removeTrack("combat")); // Already removed
}

test "AITrackSystem: track recommendations" {
    const allocator = std.testing.allocator;
    var ai = AITrackSystem.init(allocator);
    defer ai.deinit();

    try ai.addTrack("combat", .{ .priority = 0.8 });

    const track = ai.getTrack("combat").?;
    try track.recommend(.attack, 0.9, "Enemy spotted");
    try track.recommend(.defend, 0.5, "Protect base");

    try std.testing.expectEqual(@as(usize, 2), track.recommendations.items.len);

    // Check scores (urgency * priority)
    const rec1 = track.recommendations.items[0];
    try std.testing.expectApproxEqAbs(@as(f32, 0.72), rec1.score, 0.001); // 0.9 * 0.8
}

test "AITrackSystem: best recommendation" {
    const allocator = std.testing.allocator;
    var ai = AITrackSystem.init(allocator);
    defer ai.deinit();

    try ai.addTrack("combat", .{ .priority = 0.8 });
    try ai.addTrack("economy", .{ .priority = 0.6 });

    const combat = ai.getTrack("combat").?;
    const economy = ai.getTrack("economy").?;

    try combat.recommend(.attack, 0.7, "Attack enemy"); // score = 0.56
    try economy.recommend(.gather, 0.9, "Gather resources"); // score = 0.54

    const best = ai.getBestRecommendation();
    try std.testing.expect(best != null);
    try std.testing.expectEqual(ActionType.attack, best.?.action);
}

test "AITrackSystem: update with function" {
    const allocator = std.testing.allocator;
    var ai = AITrackSystem.init(allocator);
    defer ai.deinit();

    const updateFn = struct {
        fn update(track: *Track, _: ?*anyopaque, _: *blackboard.Blackboard) void {
            track.recommend(.scout, 0.5, "Test recommendation") catch {};
        }
    }.update;

    try ai.addTrack("test", .{ .update_fn = updateFn });

    try std.testing.expectEqual(@as(usize, 0), ai.getTotalRecommendations());

    ai.update(null);

    try std.testing.expectEqual(@as(usize, 1), ai.getTotalRecommendations());
}

test "AITrackSystem: enable/disable track" {
    const allocator = std.testing.allocator;
    var ai = AITrackSystem.init(allocator);
    defer ai.deinit();

    const updateFn = struct {
        fn update(track: *Track, _: ?*anyopaque, _: *blackboard.Blackboard) void {
            track.recommend(.scout, 0.5, "Test") catch {};
        }
    }.update;

    try ai.addTrack("test", .{ .update_fn = updateFn });

    ai.update(null);
    try std.testing.expectEqual(@as(usize, 1), ai.getTotalRecommendations());

    _ = ai.setTrackEnabled("test", false);
    ai.update(null);
    try std.testing.expectEqual(@as(usize, 0), ai.getTotalRecommendations()); // Cleared, not updated
}

test "AITrackSystem: urgency affects score" {
    const allocator = std.testing.allocator;
    var ai = AITrackSystem.init(allocator);
    defer ai.deinit();

    try ai.addTrack("combat", .{ .priority = 0.8 });

    const track = ai.getTrack("combat").?;
    try track.recommend(.attack, 0.6, "Attack");

    const initial_score = track.recommendations.items[0].score;

    track.setUrgency(0.9);

    const new_score = track.recommendations.items[0].score;
    try std.testing.expect(new_score > initial_score);
}

test "AITrackSystem: shared state communication" {
    const allocator = std.testing.allocator;
    var ai = AITrackSystem.init(allocator);
    defer ai.deinit();

    try ai.postMessage("threat_level", .{ .float32 = 0.75 });
    try ai.postMessage("enemy_count", .{ .int32 = 5 });

    const threat = ai.getMessage("threat_level");
    try std.testing.expect(threat != null);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), threat.?.toFloat(), 0.001);
}

test "AITrackSystem: top N recommendations" {
    const allocator = std.testing.allocator;
    var ai = AITrackSystem.init(allocator);
    defer ai.deinit();

    try ai.addTrack("combat", .{ .priority = 1.0 });

    const track = ai.getTrack("combat").?;
    try track.recommend(.attack, 0.9, "High priority");
    try track.recommend(.defend, 0.5, "Medium priority");
    try track.recommend(.scout, 0.2, "Low priority");

    const top = try ai.getTopRecommendations(allocator, 2);
    defer allocator.free(top);

    try std.testing.expectEqual(@as(usize, 2), top.len);
    try std.testing.expectEqual(ActionType.attack, top[0].action);
    try std.testing.expectEqual(ActionType.defend, top[1].action);
}

test "AITrackSystem: filter by action type" {
    const allocator = std.testing.allocator;
    var ai = AITrackSystem.init(allocator);
    defer ai.deinit();

    try ai.addTrack("test", .{ .priority = 1.0 });

    const track = ai.getTrack("test").?;
    try track.recommend(.attack, 0.9, "Attack 1");
    try track.recommend(.defend, 0.5, "Defend");
    try track.recommend(.attack, 0.7, "Attack 2");

    const attacks = try ai.getRecommendationsByAction(allocator, .attack);
    defer allocator.free(attacks);

    try std.testing.expectEqual(@as(usize, 2), attacks.len);
}

test "AITrackSystem: recommendation tags" {
    const allocator = std.testing.allocator;
    var ai = AITrackSystem.init(allocator);
    defer ai.deinit();

    try ai.addTrack("test", .{ .priority = 1.0 });

    const track = ai.getTrack("test").?;
    try track.recommendEx(.attack, 0.9, "High priority attack", .{
        .tags = &.{ "urgent", "military" },
    });
    try track.recommendEx(.gather, 0.5, "Gather resources", .{
        .tags = &.{"economic"},
    });

    const urgent = try ai.getRecommendationsByTag(allocator, "urgent");
    defer allocator.free(urgent);

    try std.testing.expectEqual(@as(usize, 1), urgent.len);
    try std.testing.expectEqual(ActionType.attack, urgent[0].action);
}

test "AITrackSystem: conflict detection" {
    const allocator = std.testing.allocator;
    var ai = AITrackSystem.init(allocator);
    defer ai.deinit();

    var rec1: Recommendation = undefined;
    rec1.action = .attack;
    rec1.target_id = 42;

    var rec2: Recommendation = undefined;
    rec2.action = .ally;
    rec2.target_id = 42;

    var rec3: Recommendation = undefined;
    rec3.action = .attack;
    rec3.target_id = 99;

    try std.testing.expect(ai.hasConflict(&rec1, &rec2)); // Same target, conflicting actions
    try std.testing.expect(!ai.hasConflict(&rec1, &rec3)); // Different targets
}

test "AITrackSystem: predefined combat track" {
    const allocator = std.testing.allocator;
    var ai = AITrackSystem.init(allocator);
    defer ai.deinit();

    try ai.addTrack("combat", .{ .priority = 0.8, .update_fn = combatTrackUpdate });

    // Set up shared state
    try ai.postMessage("threat_level", .{ .float32 = 0.8 });
    try ai.postMessage("enemy_count", .{ .int32 = 3 });
    try ai.postMessage("military_strength", .{ .float32 = 0.4 });

    ai.update(null);

    // Should recommend retreat due to high threat, low strength
    const best = ai.getBestRecommendation();
    try std.testing.expect(best != null);
    try std.testing.expectEqual(ActionType.retreat, best.?.action);
}

test "AITrackSystem: predefined economy track" {
    const allocator = std.testing.allocator;
    var ai = AITrackSystem.init(allocator);
    defer ai.deinit();

    try ai.addTrack("economy", .{ .priority = 0.6, .update_fn = economyTrackUpdate });

    // Set up shared state - low resources
    try ai.postMessage("resources", .{ .float32 = 30.0 });
    try ai.postMessage("storage_capacity", .{ .float32 = 100.0 });

    ai.update(null);

    // Should recommend gathering due to low resources
    const best = ai.getBestRecommendation();
    try std.testing.expect(best != null);
    try std.testing.expectEqual(ActionType.gather, best.?.action);
}

test "AITrackSystem: statistics" {
    const allocator = std.testing.allocator;
    var ai = AITrackSystem.init(allocator);
    defer ai.deinit();

    try ai.addTrack("combat", .{ .priority = 0.8 });
    try ai.addTrack("economy", .{ .priority = 0.6, .enabled = false });

    const track = ai.getTrack("combat").?;
    try track.recommend(.attack, 0.9, "Test");

    const stats = ai.getStats();
    try std.testing.expectEqual(@as(usize, 2), stats.track_count);
    try std.testing.expectEqual(@as(usize, 1), stats.enabled_tracks);
    try std.testing.expectEqual(@as(usize, 1), stats.total_recommendations);
}

test "AITrackSystem: track cooldown" {
    const allocator = std.testing.allocator;
    var ai = AITrackSystem.init(allocator);
    defer ai.deinit();

    var update_count: usize = 0;
    const updateFn = struct {
        fn update(track: *Track, ctx: ?*anyopaque, _: *blackboard.Blackboard) void {
            _ = track;
            const count: *usize = @ptrCast(@alignCast(ctx.?));
            count.* += 1;
        }
    }.update;

    try ai.addTrack("test", .{ .update_fn = updateFn, .cooldown = 1.0 });

    ai.updateWithDelta(&update_count, 0.0);
    try std.testing.expectEqual(@as(usize, 1), update_count);

    ai.updateWithDelta(&update_count, 0.5); // Not enough time passed
    try std.testing.expectEqual(@as(usize, 1), update_count);

    ai.updateWithDelta(&update_count, 0.6); // Cooldown expired
    try std.testing.expectEqual(@as(usize, 2), update_count);
}

test "AITrackSystem: clear all recommendations" {
    const allocator = std.testing.allocator;
    var ai = AITrackSystem.init(allocator);
    defer ai.deinit();

    try ai.addTrack("combat", .{});
    try ai.addTrack("economy", .{});

    const combat = ai.getTrack("combat").?;
    const economy = ai.getTrack("economy").?;

    try combat.recommend(.attack, 0.9, "Attack");
    try economy.recommend(.gather, 0.8, "Gather");

    try std.testing.expectEqual(@as(usize, 2), ai.getTotalRecommendations());

    ai.clearAllRecommendations();

    try std.testing.expectEqual(@as(usize, 0), ai.getTotalRecommendations());
}

test "AITrackSystem: recommendation location" {
    const allocator = std.testing.allocator;
    var ai = AITrackSystem.init(allocator);
    defer ai.deinit();

    try ai.addTrack("test", .{});

    const track = ai.getTrack("test").?;
    try track.recommendEx(.attack, 0.9, "Attack at location", .{
        .target_id = 42,
        .location_x = 100.0,
        .location_y = 200.0,
    });

    const rec = track.recommendations.items[0];
    try std.testing.expectEqual(@as(?u32, 42), rec.target_id);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), rec.location_x.?, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 200.0), rec.location_y.?, 0.001);
}

test "Track: top recommendation" {
    const allocator = std.testing.allocator;
    var track = try Track.init(allocator, "test", .{ .priority = 1.0 });
    defer track.deinit();

    try track.recommend(.attack, 0.9, "High");
    try track.recommend(.defend, 0.5, "Low");

    const top = track.getTopRecommendation();
    try std.testing.expect(top != null);
    try std.testing.expectEqual(ActionType.attack, top.?.action);
}

test "AITrackSystem: non-conflicting recommendations" {
    const allocator = std.testing.allocator;
    var ai = AITrackSystem.init(allocator);
    defer ai.deinit();

    try ai.addTrack("combat", .{ .priority = 1.0 });
    try ai.addTrack("diplomacy", .{ .priority = 0.9 });

    const combat = ai.getTrack("combat").?;
    const diplomacy = ai.getTrack("diplomacy").?;

    // Conflicting recommendations for same target
    try combat.recommendEx(.attack, 0.9, "Attack enemy", .{ .target_id = 42 });
    try diplomacy.recommendEx(.ally, 0.8, "Ally with enemy", .{ .target_id = 42 });
    // Non-conflicting
    try combat.recommendEx(.attack, 0.7, "Attack other", .{ .target_id = 99 });

    const filtered = try ai.getNonConflictingRecommendations(allocator, 2);
    defer allocator.free(filtered);

    try std.testing.expectEqual(@as(usize, 2), filtered.len);
    // Should have attack on 42 and attack on 99 (ally excluded due to conflict)
}
