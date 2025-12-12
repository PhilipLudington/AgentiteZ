const std = @import("std");
const Allocator = std.mem.Allocator;

/// AI Personality System - Trait-weighted decision scoring for AI agents
///
/// Provides personality-driven decision making:
/// - 8 built-in personality templates (Balanced, Aggressive, Defensive, etc.)
/// - Trait-weighted action scoring
/// - Threat management and assessment
/// - Goal tracking and prioritization
/// - Action cooldowns
/// - Situation-based modifiers
///
/// Example usage:
/// ```zig
/// var ai = AISystem.init(allocator);
/// defer ai.deinit();
///
/// var state = AIState.init(.aggressive);
/// state.setRatios(0.8, 1.2, 0.9); // resources, military, tech
/// state.setMorale(0.85);
///
/// try state.addThreat(enemy_id, 0.7, base_id, 50.0);
///
/// // Score an action
/// const score = state.scoreAction(.attack, 100.0);
///
/// // Or use the full decision system
/// var decision = ai.processTurn(&state);
/// const best = decision.getBestAction();
/// ```

/// Personality types (8 built-in + custom starting at 16)
pub const PersonalityType = enum(u8) {
    balanced = 0,
    aggressive = 1,
    defensive = 2,
    economic = 3,
    expansionist = 4,
    technologist = 5,
    diplomatic = 6,
    opportunist = 7,

    // Custom personalities start here
    custom_0 = 16,
    custom_1 = 17,
    custom_2 = 18,
    custom_3 = 19,

    pub fn name(self: PersonalityType) []const u8 {
        return switch (self) {
            .balanced => "Balanced",
            .aggressive => "Aggressive",
            .defensive => "Defensive",
            .economic => "Economic",
            .expansionist => "Expansionist",
            .technologist => "Technologist",
            .diplomatic => "Diplomatic",
            .opportunist => "Opportunist",
            .custom_0, .custom_1, .custom_2, .custom_3 => "Custom",
        };
    }
};

/// Personality trait weights (0.0 to 1.0)
pub const Weights = struct {
    aggression: f32 = 0.5,
    defense: f32 = 0.5,
    expansion: f32 = 0.5,
    economy: f32 = 0.5,
    technology: f32 = 0.5,
    diplomacy: f32 = 0.5,
    caution: f32 = 0.5,
    opportunism: f32 = 0.5,

    /// Get weight by action type
    pub fn getForAction(self: *const Weights, action_type: ActionType) f32 {
        return switch (action_type) {
            .attack => self.aggression,
            .defend, .retreat => self.defense,
            .expand, .scout => self.expansion,
            .build, .trade => self.economy,
            .research, .upgrade => self.technology,
            .diplomacy_action => self.diplomacy,
            .recruit => (self.aggression + self.economy) / 2.0,
            .special => self.opportunism,
            .none => 0.5,
        };
    }

    /// Multiply weights by modifiers
    pub fn multiply(self: *Weights, modifiers: *const Weights) void {
        self.aggression *= modifiers.aggression;
        self.defense *= modifiers.defense;
        self.expansion *= modifiers.expansion;
        self.economy *= modifiers.economy;
        self.technology *= modifiers.technology;
        self.diplomacy *= modifiers.diplomacy;
        self.caution *= modifiers.caution;
        self.opportunism *= modifiers.opportunism;
    }

    /// Clamp all weights to [0, 1]
    pub fn clamp(self: *Weights) void {
        self.aggression = std.math.clamp(self.aggression, 0.0, 1.0);
        self.defense = std.math.clamp(self.defense, 0.0, 1.0);
        self.expansion = std.math.clamp(self.expansion, 0.0, 1.0);
        self.economy = std.math.clamp(self.economy, 0.0, 1.0);
        self.technology = std.math.clamp(self.technology, 0.0, 1.0);
        self.diplomacy = std.math.clamp(self.diplomacy, 0.0, 1.0);
        self.caution = std.math.clamp(self.caution, 0.0, 1.0);
        self.opportunism = std.math.clamp(self.opportunism, 0.0, 1.0);
    }
};

/// Get default weights for a personality type
pub fn getDefaultWeights(personality: PersonalityType) Weights {
    return switch (personality) {
        .balanced => .{
            .aggression = 0.5,
            .defense = 0.5,
            .expansion = 0.5,
            .economy = 0.5,
            .technology = 0.5,
            .diplomacy = 0.5,
            .caution = 0.5,
            .opportunism = 0.5,
        },
        .aggressive => .{
            .aggression = 0.9,
            .defense = 0.3,
            .expansion = 0.7,
            .economy = 0.4,
            .technology = 0.4,
            .diplomacy = 0.2,
            .caution = 0.2,
            .opportunism = 0.6,
        },
        .defensive => .{
            .aggression = 0.2,
            .defense = 0.9,
            .expansion = 0.3,
            .economy = 0.6,
            .technology = 0.5,
            .diplomacy = 0.5,
            .caution = 0.8,
            .opportunism = 0.3,
        },
        .economic => .{
            .aggression = 0.3,
            .defense = 0.5,
            .expansion = 0.6,
            .economy = 0.9,
            .technology = 0.6,
            .diplomacy = 0.7,
            .caution = 0.6,
            .opportunism = 0.5,
        },
        .expansionist => .{
            .aggression = 0.6,
            .defense = 0.4,
            .expansion = 0.9,
            .economy = 0.5,
            .technology = 0.4,
            .diplomacy = 0.3,
            .caution = 0.3,
            .opportunism = 0.7,
        },
        .technologist => .{
            .aggression = 0.3,
            .defense = 0.5,
            .expansion = 0.4,
            .economy = 0.6,
            .technology = 0.9,
            .diplomacy = 0.5,
            .caution = 0.6,
            .opportunism = 0.4,
        },
        .diplomatic => .{
            .aggression = 0.2,
            .defense = 0.5,
            .expansion = 0.4,
            .economy = 0.6,
            .technology = 0.5,
            .diplomacy = 0.9,
            .caution = 0.7,
            .opportunism = 0.4,
        },
        .opportunist => .{
            .aggression = 0.6,
            .defense = 0.4,
            .expansion = 0.6,
            .economy = 0.5,
            .technology = 0.4,
            .diplomacy = 0.4,
            .caution = 0.4,
            .opportunism = 0.9,
        },
        .custom_0, .custom_1, .custom_2, .custom_3 => .{},
    };
}

/// Action types for decision making
pub const ActionType = enum(u8) {
    attack = 0,
    defend = 1,
    expand = 2,
    build = 3,
    trade = 4,
    research = 5,
    upgrade = 6,
    diplomacy_action = 7,
    recruit = 8,
    retreat = 9,
    scout = 10,
    special = 11,
    none = 12,

    pub fn name(self: ActionType) []const u8 {
        return switch (self) {
            .attack => "Attack",
            .defend => "Defend",
            .expand => "Expand",
            .build => "Build",
            .trade => "Trade",
            .research => "Research",
            .upgrade => "Upgrade",
            .diplomacy_action => "Diplomacy",
            .recruit => "Recruit",
            .retreat => "Retreat",
            .scout => "Scout",
            .special => "Special",
            .none => "None",
        };
    }
};

/// Maximum number of threats tracked
pub const MAX_THREATS: usize = 12;

/// Maximum number of goals tracked
pub const MAX_GOALS: usize = 16;

/// Maximum number of actions in a decision
pub const MAX_ACTIONS: usize = 32;

/// Maximum number of cooldown slots
pub const MAX_COOLDOWNS: usize = 16;

/// Threat entry
pub const Threat = struct {
    source_id: u32,
    level: f32, // 0.0 to 1.0
    target_id: u32, // What's being threatened
    distance: f32,
    turns_since_update: i32,

    /// Calculate weighted threat level
    pub fn weighted(self: *const Threat) f32 {
        // Distance weighting: closer = more dangerous
        const dist_factor = 1.0 / (1.0 + self.distance * 0.1);
        // Age decay: older = less relevant
        const age_factor = 1.0 / (1.0 + @as(f32, @floatFromInt(self.turns_since_update)) * 0.2);
        return self.level * dist_factor * age_factor;
    }
};

/// Goal entry
pub const Goal = struct {
    goal_type: u32,
    target_id: u32,
    priority: f32,
    progress: f32, // 0.0 to 1.0
    turns_active: i32,
    completed: bool,
};

/// Action entry for decision output
pub const Action = struct {
    action_type: ActionType,
    target_id: u32,
    priority: f32, // Score
    urgency: f32, // How quickly needed

    /// Combined score for sorting
    pub fn score(self: *const Action) f32 {
        return self.priority * (1.0 + self.urgency * 0.5);
    }
};

/// Decision output from AI processing
pub const Decision = struct {
    actions: [MAX_ACTIONS]Action = undefined,
    action_count: usize = 0,
    total_score: f32 = 0.0,

    /// Add an action to the decision
    pub fn addAction(self: *Decision, action: Action) void {
        if (self.action_count >= MAX_ACTIONS) return;
        self.actions[self.action_count] = action;
        self.action_count += 1;
        self.total_score += action.priority;
    }

    /// Get actions slice
    pub fn getActions(self: *const Decision) []const Action {
        return self.actions[0..self.action_count];
    }

    /// Get best action (highest score)
    pub fn getBestAction(self: *const Decision) ?Action {
        if (self.action_count == 0) return null;

        var best: Action = self.actions[0];
        for (self.actions[1..self.action_count]) |action| {
            if (action.score() > best.score()) {
                best = action;
            }
        }
        return best;
    }

    /// Sort actions by score (highest first)
    pub fn sort(self: *Decision) void {
        const slice = self.actions[0..self.action_count];
        std.sort.pdq(Action, slice, {}, struct {
            fn cmp(_: void, a: Action, b: Action) bool {
                return a.score() > b.score();
            }
        }.cmp);
    }

    /// Get top N actions
    pub fn getTopActions(self: *Decision, n: usize) []const Action {
        self.sort();
        return self.actions[0..@min(n, self.action_count)];
    }
};

/// AI state for a single agent
pub const AIState = struct {
    personality: PersonalityType,
    weights: Weights,
    base_weights: Weights,

    // Situation assessment
    morale: f32,
    resources_ratio: f32, // own/enemy
    military_ratio: f32, // own/enemy
    tech_ratio: f32, // own/enemy

    // Threats
    threats: [MAX_THREATS]Threat = undefined,
    threat_count: usize = 0,
    overall_threat: f32 = 0.0,

    // Goals
    goals: [MAX_GOALS]Goal = undefined,
    goal_count: usize = 0,

    // Memory / targeting
    primary_target: u32 = 0,
    ally_target: u32 = 0,
    last_action_type: ActionType = .none,
    last_target: u32 = 0,
    turns_since_combat: i32 = 0,
    turns_since_expansion: i32 = 0,

    // Cooldowns per action type
    cooldowns: [MAX_COOLDOWNS]i32 = [_]i32{0} ** MAX_COOLDOWNS,

    // PRNG state
    random_state: u32,

    /// Initialize with a personality type
    pub fn init(personality: PersonalityType) AIState {
        const weights = getDefaultWeights(personality);
        return .{
            .personality = personality,
            .weights = weights,
            .base_weights = weights,
            .morale = 1.0,
            .resources_ratio = 1.0,
            .military_ratio = 1.0,
            .tech_ratio = 1.0,
            .random_state = @truncate(@as(u64, @bitCast(std.time.milliTimestamp()))),
        };
    }

    /// Initialize with custom weights
    pub fn initWithWeights(personality: PersonalityType, weights: Weights) AIState {
        return .{
            .personality = personality,
            .weights = weights,
            .base_weights = weights,
            .morale = 1.0,
            .resources_ratio = 1.0,
            .military_ratio = 1.0,
            .tech_ratio = 1.0,
            .random_state = @truncate(@as(u64, @bitCast(std.time.milliTimestamp()))),
        };
    }

    /// Reset to initial state
    pub fn reset(self: *AIState) void {
        self.weights = self.base_weights;
        self.morale = 1.0;
        self.resources_ratio = 1.0;
        self.military_ratio = 1.0;
        self.tech_ratio = 1.0;
        self.threat_count = 0;
        self.overall_threat = 0.0;
        self.goal_count = 0;
        self.primary_target = 0;
        self.ally_target = 0;
        self.last_action_type = .none;
        self.last_target = 0;
        self.turns_since_combat = 0;
        self.turns_since_expansion = 0;
        @memset(&self.cooldowns, 0);
    }

    // ============================================================
    // Weight Management
    // ============================================================

    /// Set weights directly
    pub fn setWeights(self: *AIState, weights: Weights) void {
        self.weights = weights;
    }

    /// Modify weights with multipliers
    pub fn modifyWeights(self: *AIState, modifiers: *const Weights) void {
        self.weights.multiply(modifiers);
        self.weights.clamp();
    }

    /// Reset weights to base
    pub fn resetWeights(self: *AIState) void {
        self.weights = self.base_weights;
    }

    // ============================================================
    // Situation Assessment
    // ============================================================

    /// Set comparison ratios
    pub fn setRatios(self: *AIState, resources: f32, military: f32, tech: f32) void {
        self.resources_ratio = resources;
        self.military_ratio = military;
        self.tech_ratio = tech;
    }

    /// Set morale
    pub fn setMorale(self: *AIState, morale: f32) void {
        self.morale = std.math.clamp(morale, 0.0, 1.0);
    }

    /// Set primary target
    pub fn setPrimaryTarget(self: *AIState, target_id: u32) void {
        self.primary_target = target_id;
    }

    /// Set ally target
    pub fn setAllyTarget(self: *AIState, ally_id: u32) void {
        self.ally_target = ally_id;
    }

    // ============================================================
    // Threat Management
    // ============================================================

    /// Add or update a threat
    pub fn addThreat(self: *AIState, source_id: u32, level: f32, target_id: u32, distance: f32) void {
        // Check for existing threat from this source
        for (self.threats[0..self.threat_count]) |*threat| {
            if (threat.source_id == source_id) {
                threat.level = level;
                threat.target_id = target_id;
                threat.distance = distance;
                threat.turns_since_update = 0;
                self.calculateOverallThreat();
                return;
            }
        }

        // Add new threat
        if (self.threat_count < MAX_THREATS) {
            self.threats[self.threat_count] = .{
                .source_id = source_id,
                .level = level,
                .target_id = target_id,
                .distance = distance,
                .turns_since_update = 0,
            };
            self.threat_count += 1;
            self.calculateOverallThreat();
        }
    }

    /// Remove a threat
    pub fn removeThreat(self: *AIState, source_id: u32) bool {
        for (self.threats[0..self.threat_count], 0..) |*threat, i| {
            if (threat.source_id == source_id) {
                // Swap with last
                if (i < self.threat_count - 1) {
                    self.threats[i] = self.threats[self.threat_count - 1];
                }
                self.threat_count -= 1;
                self.calculateOverallThreat();
                return true;
            }
        }
        return false;
    }

    /// Get highest threat
    pub fn getHighestThreat(self: *const AIState) ?*const Threat {
        if (self.threat_count == 0) return null;

        var highest: *const Threat = &self.threats[0];
        for (self.threats[1..self.threat_count]) |*threat| {
            if (threat.weighted() > highest.weighted()) {
                highest = threat;
            }
        }
        return highest;
    }

    /// Calculate overall threat level (0-1)
    pub fn calculateOverallThreat(self: *AIState) void {
        if (self.threat_count == 0) {
            self.overall_threat = 0.0;
            return;
        }

        var max_threat: f32 = 0.0;
        var sum_threat: f32 = 0.0;

        for (self.threats[0..self.threat_count]) |*threat| {
            const w = threat.weighted();
            max_threat = @max(max_threat, w);
            sum_threat += w;
        }

        const avg_threat = sum_threat / @as(f32, @floatFromInt(self.threat_count));

        // Combined: 70% max + 30% average
        self.overall_threat = std.math.clamp(max_threat * 0.7 + avg_threat * 0.3, 0.0, 1.0);
    }

    /// Update all threats (age them)
    pub fn updateThreats(self: *AIState) void {
        for (self.threats[0..self.threat_count]) |*threat| {
            threat.turns_since_update += 1;
        }
        self.calculateOverallThreat();
    }

    // ============================================================
    // Goal Management
    // ============================================================

    /// Add a goal
    pub fn addGoal(self: *AIState, goal_type: u32, target_id: u32, priority: f32) ?usize {
        if (self.goal_count >= MAX_GOALS) return null;

        self.goals[self.goal_count] = .{
            .goal_type = goal_type,
            .target_id = target_id,
            .priority = priority,
            .progress = 0.0,
            .turns_active = 0,
            .completed = false,
        };
        const idx = self.goal_count;
        self.goal_count += 1;
        return idx;
    }

    /// Update goal progress
    pub fn updateGoalProgress(self: *AIState, index: usize, progress: f32) void {
        if (index >= self.goal_count) return;
        self.goals[index].progress = std.math.clamp(progress, 0.0, 1.0);
    }

    /// Complete a goal
    pub fn completeGoal(self: *AIState, index: usize) void {
        if (index >= self.goal_count) return;
        self.goals[index].completed = true;
        self.goals[index].progress = 1.0;
    }

    /// Remove a goal
    pub fn removeGoal(self: *AIState, index: usize) void {
        if (index >= self.goal_count) return;
        if (index < self.goal_count - 1) {
            self.goals[index] = self.goals[self.goal_count - 1];
        }
        self.goal_count -= 1;
    }

    /// Get primary goal (highest priority, not completed)
    pub fn getPrimaryGoal(self: *const AIState) ?*const Goal {
        var primary: ?*const Goal = null;
        var highest_priority: f32 = -1.0;

        for (self.goals[0..self.goal_count]) |*goal| {
            if (!goal.completed and goal.priority > highest_priority) {
                highest_priority = goal.priority;
                primary = goal;
            }
        }

        return primary;
    }

    /// Cleanup completed/stale goals
    pub fn cleanupGoals(self: *AIState, max_stale_turns: i32) void {
        var i: usize = 0;
        while (i < self.goal_count) {
            const goal = &self.goals[i];
            if (goal.completed or goal.turns_active > max_stale_turns) {
                self.removeGoal(i);
            } else {
                goal.turns_active += 1;
                i += 1;
            }
        }
    }

    // ============================================================
    // Cooldowns
    // ============================================================

    /// Set cooldown for an action type
    pub fn setCooldown(self: *AIState, action_type: ActionType, turns: i32) void {
        const idx = @intFromEnum(action_type);
        if (idx < MAX_COOLDOWNS) {
            self.cooldowns[idx] = turns;
        }
    }

    /// Check if action is on cooldown
    pub fn isOnCooldown(self: *const AIState, action_type: ActionType) bool {
        const idx = @intFromEnum(action_type);
        if (idx >= MAX_COOLDOWNS) return false;
        return self.cooldowns[idx] > 0;
    }

    /// Get remaining cooldown
    pub fn getCooldown(self: *const AIState, action_type: ActionType) i32 {
        const idx = @intFromEnum(action_type);
        if (idx >= MAX_COOLDOWNS) return 0;
        return self.cooldowns[idx];
    }

    /// Update all cooldowns (decrement by 1)
    pub fn updateCooldowns(self: *AIState) void {
        for (&self.cooldowns) |*cd| {
            if (cd.* > 0) cd.* -= 1;
        }
        self.turns_since_combat += 1;
        self.turns_since_expansion += 1;
    }

    // ============================================================
    // Decision Scoring
    // ============================================================

    /// Score an action based on personality and situation
    pub fn scoreAction(self: *const AIState, action_type: ActionType, base_score: f32) f32 {
        // Skip if on cooldown
        if (self.isOnCooldown(action_type)) {
            return 0.0;
        }

        // Base personality weight
        var score = base_score * self.weights.getForAction(action_type);

        // Situational modifiers
        switch (action_type) {
            .attack => {
                // Boost attack if military advantage
                if (self.military_ratio > 1.2) {
                    score *= 1.3;
                }
                // Reduce if high threat (need defense)
                if (self.overall_threat > 0.6) {
                    score *= 0.7;
                }
                // High morale bonus
                if (self.morale > 0.7) {
                    score *= 1.1;
                }
            },
            .defend => {
                // Boost defense if under threat
                if (self.overall_threat > 0.5) {
                    score *= 1.0 + self.overall_threat;
                }
                // Low morale boost (defensive play)
                if (self.morale < 0.4) {
                    score *= 1.2;
                }
            },
            .expand => {
                // Reduce expansion if threatened
                if (self.overall_threat > 0.4) {
                    score *= 0.6;
                }
                // Boost if resource advantage
                if (self.resources_ratio > 1.0) {
                    score *= 1.2;
                }
                // High morale bonus
                if (self.morale > 0.7) {
                    score *= 1.1;
                }
            },
            .build, .trade => {
                // Boost if low on resources
                if (self.resources_ratio < 0.8) {
                    score *= 1.3;
                }
            },
            .research, .upgrade => {
                // Boost if tech disadvantage
                if (self.tech_ratio < 0.9) {
                    score *= 1.2;
                }
            },
            .retreat => {
                // Strong boost if low morale and high threat
                if (self.morale < 0.3 and self.overall_threat > 0.6) {
                    score *= 2.0;
                }
                // Low morale boost
                if (self.morale < 0.4) {
                    score *= 1.2;
                }
            },
            .diplomacy_action => {
                // Boost diplomacy when weak
                if (self.military_ratio < 0.8) {
                    score *= 1.2;
                }
            },
            .recruit => {
                // Boost if military disadvantage
                if (self.military_ratio < 1.0) {
                    score *= 1.3;
                }
            },
            .scout => {
                // Reduce priority if under immediate threat
                if (self.overall_threat > 0.7) {
                    score *= 0.5;
                }
            },
            .special, .none => {},
        }

        return @max(score, 0.0);
    }

    // ============================================================
    // Random Number Generation
    // ============================================================

    /// Generate random float 0.0 to 1.0
    pub fn random(self: *AIState) f32 {
        // xorshift32
        var x = self.random_state;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        self.random_state = x;
        return @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(std.math.maxInt(u32)));
    }

    /// Generate random integer in range [min, max]
    pub fn randomInt(self: *AIState, min: i32, max: i32) i32 {
        if (min >= max) return min;
        const range: u32 = @intCast(max - min + 1);
        return min + @as(i32, @intCast(self.random_state % range));
    }

    /// Seed the random number generator
    pub fn seedRandom(self: *AIState, seed: u32) void {
        self.random_state = if (seed == 0)
            @truncate(@as(u64, @bitCast(std.time.milliTimestamp())))
        else
            seed;
    }
};

/// Action evaluator callback type
pub const ActionEvaluator = *const fn (
    state: *AIState,
    game_ctx: ?*anyopaque,
    out_actions: []Action,
) usize;

/// Threat assessor callback type
pub const ThreatAssessor = *const fn (
    state: *AIState,
    game_ctx: ?*anyopaque,
    out_threats: []Threat,
) usize;

/// Situation analyzer callback type
pub const SituationAnalyzer = *const fn (
    state: *AIState,
    game_ctx: ?*anyopaque,
) void;

/// AI System - manages evaluators and processes decisions
pub const AISystem = struct {
    allocator: Allocator,

    // Registered evaluators per action type
    evaluators: [13]?ActionEvaluator = [_]?ActionEvaluator{null} ** 13,

    // Callbacks
    threat_assessor: ?ThreatAssessor = null,
    situation_analyzer: ?SituationAnalyzer = null,

    /// Initialize AI system
    pub fn init(allocator: Allocator) AISystem {
        return .{
            .allocator = allocator,
        };
    }

    /// Deinitialize
    pub fn deinit(self: *AISystem) void {
        _ = self;
    }

    /// Register an action evaluator
    pub fn registerEvaluator(self: *AISystem, action_type: ActionType, evaluator: ActionEvaluator) void {
        const idx = @intFromEnum(action_type);
        if (idx < 13) {
            self.evaluators[idx] = evaluator;
        }
    }

    /// Set threat assessor
    pub fn setThreatAssessor(self: *AISystem, assessor: ThreatAssessor) void {
        self.threat_assessor = assessor;
    }

    /// Set situation analyzer
    pub fn setSituationAnalyzer(self: *AISystem, analyzer: SituationAnalyzer) void {
        self.situation_analyzer = analyzer;
    }

    /// Update situation using registered analyzer
    pub fn updateSituation(self: *AISystem, state: *AIState, game_ctx: ?*anyopaque) void {
        if (self.situation_analyzer) |analyzer| {
            analyzer(state, game_ctx);
        }
    }

    /// Update threats using registered assessor
    pub fn updateThreats(self: *AISystem, state: *AIState, game_ctx: ?*anyopaque) void {
        if (self.threat_assessor) |assessor| {
            var threat_buffer: [MAX_THREATS]Threat = undefined;
            const count = assessor(state, game_ctx, &threat_buffer);

            // Replace current threats
            state.threat_count = @min(count, MAX_THREATS);
            for (0..state.threat_count) |i| {
                state.threats[i] = threat_buffer[i];
            }
            state.calculateOverallThreat();
        } else {
            // Just age existing threats
            state.updateThreats();
        }
    }

    /// Process a turn and return decision
    pub fn processTurn(self: *AISystem, state: *AIState, game_ctx: ?*anyopaque) Decision {
        var decision = Decision{};

        // Update situation
        self.updateSituation(state, game_ctx);

        // Update threats
        self.updateThreats(state, game_ctx);

        // Collect actions from all evaluators
        var action_buffer: [MAX_ACTIONS]Action = undefined;

        for (self.evaluators, 0..) |maybe_evaluator, action_idx| {
            if (maybe_evaluator) |evaluator| {
                const count = evaluator(state, game_ctx, &action_buffer);

                for (action_buffer[0..count]) |action| {
                    // Score the action
                    const scored_priority = state.scoreAction(action.action_type, action.priority);
                    if (scored_priority > 0.0) {
                        decision.addAction(.{
                            .action_type = action.action_type,
                            .target_id = action.target_id,
                            .priority = scored_priority,
                            .urgency = action.urgency,
                        });
                    }
                }
            }
            _ = action_idx;
        }

        // Sort by score
        decision.sort();

        return decision;
    }

    /// Simple process without evaluators (use scoreAction directly)
    pub fn scoreActions(self: *AISystem, state: *AIState, actions: []const Action) Decision {
        _ = self;
        var decision = Decision{};

        for (actions) |action| {
            const scored_priority = state.scoreAction(action.action_type, action.priority);
            if (scored_priority > 0.0) {
                decision.addAction(.{
                    .action_type = action.action_type,
                    .target_id = action.target_id,
                    .priority = scored_priority,
                    .urgency = action.urgency,
                });
            }
        }

        decision.sort();
        return decision;
    }
};

// ============================================================
// Tests
// ============================================================

test "AIState: initialization" {
    const state = AIState.init(.aggressive);

    try std.testing.expectEqual(PersonalityType.aggressive, state.personality);
    try std.testing.expectApproxEqAbs(@as(f32, 0.9), state.weights.aggression, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.3), state.weights.defense, 0.001);
}

test "AIState: personality weights" {
    const balanced = getDefaultWeights(.balanced);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), balanced.aggression, 0.001);

    const aggressive = getDefaultWeights(.aggressive);
    try std.testing.expectApproxEqAbs(@as(f32, 0.9), aggressive.aggression, 0.001);

    const defensive = getDefaultWeights(.defensive);
    try std.testing.expectApproxEqAbs(@as(f32, 0.9), defensive.defense, 0.001);
}

test "AIState: threat management" {
    var state = AIState.init(.balanced);

    state.addThreat(1, 0.5, 100, 10.0);
    state.addThreat(2, 0.8, 100, 5.0);

    try std.testing.expectEqual(@as(usize, 2), state.threat_count);
    try std.testing.expect(state.overall_threat > 0.0);

    const highest = state.getHighestThreat().?;
    try std.testing.expectEqual(@as(u32, 2), highest.source_id);

    try std.testing.expect(state.removeThreat(1));
    try std.testing.expectEqual(@as(usize, 1), state.threat_count);
}

test "AIState: threat aging" {
    var state = AIState.init(.balanced);

    state.addThreat(1, 0.8, 100, 10.0);
    const initial_threat = state.overall_threat;

    state.updateThreats();
    state.updateThreats();

    // Threat should decrease as it ages
    try std.testing.expect(state.overall_threat < initial_threat);
}

test "AIState: goal management" {
    var state = AIState.init(.balanced);

    const idx = state.addGoal(1, 100, 0.8).?;
    try std.testing.expectEqual(@as(usize, 1), state.goal_count);

    state.updateGoalProgress(idx, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), state.goals[idx].progress, 0.001);

    const primary = state.getPrimaryGoal().?;
    try std.testing.expectEqual(@as(u32, 1), primary.goal_type);

    state.completeGoal(idx);
    try std.testing.expect(state.goals[idx].completed);
    try std.testing.expect(state.getPrimaryGoal() == null);
}

test "AIState: cooldowns" {
    var state = AIState.init(.balanced);

    state.setCooldown(.attack, 3);
    try std.testing.expect(state.isOnCooldown(.attack));
    try std.testing.expectEqual(@as(i32, 3), state.getCooldown(.attack));

    state.updateCooldowns();
    try std.testing.expectEqual(@as(i32, 2), state.getCooldown(.attack));

    state.updateCooldowns();
    state.updateCooldowns();
    try std.testing.expect(!state.isOnCooldown(.attack));
}

test "AIState: action scoring - basic" {
    var state = AIState.init(.aggressive);

    const attack_score = state.scoreAction(.attack, 100.0);
    const defend_score = state.scoreAction(.defend, 100.0);

    // Aggressive personality should favor attack over defense
    try std.testing.expect(attack_score > defend_score);
}

test "AIState: action scoring - situational modifiers" {
    var state = AIState.init(.balanced);

    // Base case
    var attack_score = state.scoreAction(.attack, 100.0);

    // With military advantage
    state.setRatios(1.0, 1.5, 1.0);
    const boosted_attack = state.scoreAction(.attack, 100.0);
    try std.testing.expect(boosted_attack > attack_score);

    // With high threat - should reduce attack
    state.addThreat(1, 0.9, 100, 5.0);
    attack_score = state.scoreAction(.attack, 100.0);
    try std.testing.expect(attack_score < boosted_attack);
}

test "AIState: action scoring - defend under threat" {
    var state = AIState.init(.balanced);

    const base_defend = state.scoreAction(.defend, 100.0);

    state.addThreat(1, 0.8, 100, 5.0);
    const threatened_defend = state.scoreAction(.defend, 100.0);

    // Defense should be boosted when threatened
    try std.testing.expect(threatened_defend > base_defend);
}

test "AIState: action scoring - retreat conditions" {
    var state = AIState.init(.balanced);

    const base_retreat = state.scoreAction(.retreat, 100.0);

    // Low morale + high threat = retreat boost
    state.setMorale(0.2);
    state.addThreat(1, 0.9, 100, 5.0);
    const panic_retreat = state.scoreAction(.retreat, 100.0);

    try std.testing.expect(panic_retreat > base_retreat * 1.5);
}

test "AIState: cooldown blocks action" {
    var state = AIState.init(.aggressive);

    state.setCooldown(.attack, 2);
    const score = state.scoreAction(.attack, 100.0);

    try std.testing.expectEqual(@as(f32, 0.0), score);
}

test "AIState: random number generation" {
    var state = AIState.init(.balanced);
    state.seedRandom(12345);

    const r1 = state.random();
    const r2 = state.random();

    try std.testing.expect(r1 >= 0.0 and r1 <= 1.0);
    try std.testing.expect(r2 >= 0.0 and r2 <= 1.0);
    try std.testing.expect(r1 != r2);
}

test "AIState: weight modification" {
    var state = AIState.init(.balanced);

    const modifiers = Weights{
        .aggression = 1.5,
        .defense = 0.5,
        .expansion = 1.0,
        .economy = 1.0,
        .technology = 1.0,
        .diplomacy = 1.0,
        .caution = 1.0,
        .opportunism = 1.0,
    };

    state.modifyWeights(&modifiers);

    // Aggression boosted (clamped to 1.0)
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), state.weights.aggression, 0.001);
    // Defense reduced
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), state.weights.defense, 0.001);

    state.resetWeights();
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), state.weights.aggression, 0.001);
}

test "Decision: action management" {
    var decision = Decision{};

    decision.addAction(.{ .action_type = .attack, .target_id = 1, .priority = 50.0, .urgency = 0.5 });
    decision.addAction(.{ .action_type = .defend, .target_id = 0, .priority = 80.0, .urgency = 0.8 });
    decision.addAction(.{ .action_type = .build, .target_id = 2, .priority = 30.0, .urgency = 0.2 });

    try std.testing.expectEqual(@as(usize, 3), decision.action_count);

    const best = decision.getBestAction().?;
    try std.testing.expectEqual(ActionType.defend, best.action_type);

    const top = decision.getTopActions(2);
    try std.testing.expectEqual(@as(usize, 2), top.len);
    try std.testing.expectEqual(ActionType.defend, top[0].action_type);
}

test "AISystem: basic processing" {
    const allocator = std.testing.allocator;
    var system = AISystem.init(allocator);
    defer system.deinit();

    var state = AIState.init(.aggressive);

    const actions = [_]Action{
        .{ .action_type = .attack, .target_id = 1, .priority = 100.0, .urgency = 0.5 },
        .{ .action_type = .defend, .target_id = 0, .priority = 100.0, .urgency = 0.5 },
    };

    const decision = system.scoreActions(&state, &actions);

    try std.testing.expectEqual(@as(usize, 2), decision.action_count);

    // Aggressive should favor attack
    const best = decision.getBestAction().?;
    try std.testing.expectEqual(ActionType.attack, best.action_type);
}

test "AISystem: with evaluators" {
    const allocator = std.testing.allocator;
    var system = AISystem.init(allocator);
    defer system.deinit();

    // Register a simple attack evaluator
    system.registerEvaluator(.attack, struct {
        fn eval(_: *AIState, _: ?*anyopaque, out_actions: []Action) usize {
            out_actions[0] = .{
                .action_type = .attack,
                .target_id = 42,
                .priority = 100.0,
                .urgency = 0.5,
            };
            return 1;
        }
    }.eval);

    var state = AIState.init(.aggressive);
    const decision = system.processTurn(&state, null);

    try std.testing.expect(decision.action_count > 0);
}

test "Personality names" {
    try std.testing.expectEqualStrings("Aggressive", PersonalityType.aggressive.name());
    try std.testing.expectEqualStrings("Defensive", PersonalityType.defensive.name());
    try std.testing.expectEqualStrings("Economic", PersonalityType.economic.name());
}

test "Action names" {
    try std.testing.expectEqualStrings("Attack", ActionType.attack.name());
    try std.testing.expectEqualStrings("Defend", ActionType.defend.name());
    try std.testing.expectEqualStrings("Research", ActionType.research.name());
}

test "AIState: reset" {
    var state = AIState.init(.aggressive);

    state.setMorale(0.5);
    state.addThreat(1, 0.8, 100, 10.0);
    _ = state.addGoal(1, 100, 0.8);
    state.setCooldown(.attack, 5);

    state.reset();

    try std.testing.expectApproxEqAbs(@as(f32, 1.0), state.morale, 0.001);
    try std.testing.expectEqual(@as(usize, 0), state.threat_count);
    try std.testing.expectEqual(@as(usize, 0), state.goal_count);
    try std.testing.expect(!state.isOnCooldown(.attack));
}

test "AIState: goal cleanup" {
    var state = AIState.init(.balanced);

    _ = state.addGoal(1, 100, 0.8);
    _ = state.addGoal(2, 101, 0.6);

    // Complete first goal
    state.completeGoal(0);

    // Age goals and cleanup
    for (0..10) |_| {
        state.cleanupGoals(5);
    }

    // Completed goal should be removed
    // Old goal should be removed
    try std.testing.expectEqual(@as(usize, 0), state.goal_count);
}

test "Weights: getForAction" {
    const weights = getDefaultWeights(.aggressive);

    try std.testing.expectApproxEqAbs(@as(f32, 0.9), weights.getForAction(.attack), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.3), weights.getForAction(.defend), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.7), weights.getForAction(.expand), 0.001);
}

test "Threat: weighted calculation" {
    const threat = Threat{
        .source_id = 1,
        .level = 0.8,
        .target_id = 100,
        .distance = 10.0,
        .turns_since_update = 0,
    };

    const w = threat.weighted();
    // Should be reduced by distance but not by age
    try std.testing.expect(w < 0.8);
    try std.testing.expect(w > 0.3);
}

test "Action: score calculation" {
    const action = Action{
        .action_type = .attack,
        .target_id = 1,
        .priority = 100.0,
        .urgency = 0.5,
    };

    const score = action.score();
    // priority * (1 + urgency * 0.5) = 100 * 1.25 = 125
    try std.testing.expectApproxEqAbs(@as(f32, 125.0), score, 0.001);
}
