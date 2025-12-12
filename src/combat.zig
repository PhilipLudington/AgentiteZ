//! Turn-Based Combat System - Initiative-Based Tactical Combat
//!
//! A tactical turn-based combat system with perfect information via telegraphing.
//! Features initiative-based turn order, reaction mechanics, and status effects.
//!
//! Features:
//! - Initiative system (static turn order per encounter)
//! - Telegraphing (enemy intents shown before player commits)
//! - Reaction mechanics (dodge, counter) based on initiative
//! - Action queue with move, attack, defend, use item, abilities
//! - Status effects with duration tracking
//! - Damage calculation with modifiers
//! - Support for unstoppable attacks
//!
//! Usage:
//! ```zig
//! var combat = CombatSystem.init(allocator);
//! defer combat.deinit();
//!
//! // Add combatants
//! const player = try combat.addCombatant(.{
//!     .name = "Scout",
//!     .team = .player,
//!     .max_hp = 4,
//!     .initiative = 8,
//!     .movement = 4,
//! });
//!
//! // Start combat
//! try combat.startCombat();
//!
//! // Get enemy telegraphs
//! const telegraphs = combat.getTelegraphs();
//!
//! // Queue player actions
//! try combat.queueAction(player, .{ .attack = .{ .target = enemy } });
//!
//! // Execute turn
//! const result = try combat.executeTurn();
//! ```

const std = @import("std");

const log = std.log.scoped(.combat);

/// Team allegiance
pub const Team = enum {
    player,
    enemy,
    neutral,
    ally,
};

/// Action types available to combatants
pub const ActionType = enum {
    move,
    attack,
    defend,
    use_item,
    ability,
    wait,
    flee,
};

/// Status effect types
pub const StatusType = enum {
    /// Unit cannot act this turn
    stunned,
    /// Damage over time
    burning,
    /// Damage over time (weaker)
    poisoned,
    /// Damage over time (strong)
    bleeding,
    /// Cannot move
    rooted,
    /// Reduced hit chance
    blinded,
    /// Increased damage taken
    vulnerable,
    /// Reduced damage taken
    fortified,
    /// Increased initiative temporarily
    hasted,
    /// Decreased initiative temporarily
    slowed,
    /// Immune to damage this turn
    invulnerable,
    /// Hidden from targeting
    concealed,
    /// Generic injury (reduces effectiveness)
    injured,
};

/// Position in 2D grid space
pub const Position = struct {
    x: i32,
    y: i32,

    pub fn init(x: i32, y: i32) Position {
        return .{ .x = x, .y = y };
    }

    pub fn distance(self: Position, other: Position) i32 {
        const dx = @abs(self.x - other.x);
        const dy = @abs(self.y - other.y);
        return @intCast(@max(dx, dy));
    }

    pub fn manhattanDistance(self: Position, other: Position) i32 {
        const dx = @abs(self.x - other.x);
        const dy = @abs(self.y - other.y);
        return @intCast(dx + dy);
    }

    pub fn eql(self: Position, other: Position) bool {
        return self.x == other.x and self.y == other.y;
    }
};

/// A status effect applied to a combatant
pub const StatusEffect = struct {
    status_type: StatusType,
    /// Remaining duration (0 = expired, null = permanent)
    duration: ?u32,
    /// Source that applied this effect
    source_id: ?u32 = null,
    /// Effect intensity/stacks
    stacks: u32 = 1,
    /// Damage per tick (for DoT effects)
    damage_per_tick: i32 = 0,

    pub fn isExpired(self: StatusEffect) bool {
        if (self.duration) |d| {
            return d == 0;
        }
        return false;
    }

    pub fn tick(self: *StatusEffect) void {
        if (self.duration) |*d| {
            if (d.* > 0) {
                d.* -= 1;
            }
        }
    }
};

/// Attack properties
pub const AttackProperties = struct {
    /// Base damage
    damage: i32 = 1,
    /// Range in grid units (1 = melee)
    range: i32 = 1,
    /// Hit chance (0.0 to 1.0)
    hit_chance: f32 = 1.0,
    /// Cannot be dodged or reacted to
    unstoppable: bool = false,
    /// Ignores armor
    piercing: bool = false,
    /// Area of effect radius (0 = single target)
    aoe_radius: i32 = 0,
    /// Status effect to apply on hit
    applies_status: ?StatusType = null,
    /// Duration of applied status
    status_duration: u32 = 1,
};

/// Ability definition
pub const Ability = struct {
    /// Unique identifier
    id: []const u8,
    /// Display name
    name: []const u8,
    /// Cooldown in turns
    cooldown: u32 = 0,
    /// Current cooldown remaining
    current_cooldown: u32 = 0,
    /// Uses per encounter (0 = unlimited, excluding cooldown)
    uses_per_encounter: u32 = 0,
    /// Remaining uses
    uses_remaining: u32 = 0,
    /// Attack properties if offensive
    attack: ?AttackProperties = null,
    /// Self-targeting effect
    self_effect: ?StatusType = null,
    /// Self effect duration
    self_effect_duration: u32 = 1,
    /// Requires target
    requires_target: bool = true,
    /// Range
    range: i32 = 1,
};

/// A combatant in the battle
pub const Combatant = struct {
    /// Unique identifier
    id: u32,
    /// Display name
    name: []const u8,
    /// Team allegiance
    team: Team,
    /// Current HP
    current_hp: i32,
    /// Maximum HP
    max_hp: i32,
    /// Temporary HP (absorbed first)
    temp_hp: i32 = 0,
    /// Initiative value (higher = acts first)
    initiative: i32,
    /// Base initiative (before modifiers)
    base_initiative: i32,
    /// Movement range in tiles
    movement: i32,
    /// Current position on grid
    position: Position,
    /// Base dodge chance (0.0 to 1.0)
    dodge_chance: f32 = 0.0,
    /// Base attack properties
    base_attack: AttackProperties = .{},
    /// Active status effects
    status_effects: std.ArrayList(StatusEffect),
    /// Abilities
    abilities: std.ArrayList(Ability),
    /// Whether this combatant has acted this turn
    has_acted: bool = false,
    /// Whether this combatant is alive
    is_alive: bool = true,
    /// Whether this combatant is defending
    is_defending: bool = false,
    /// Damage reduction from defending
    defend_damage_reduction: i32 = 0,
    /// Dodge bonus from defending
    defend_dodge_bonus: f32 = 0.25,
    /// Counter attack damage (0 = no counter)
    counter_damage: i32 = 0,
    /// Armor/damage reduction
    armor: i32 = 0,
    /// Inventory slot count
    inventory_slots: u32 = 3,
    /// Metadata for game-specific data
    metadata: u64 = 0,

    /// Check if combatant can react (hasn't acted yet)
    pub fn canReact(self: *const Combatant) bool {
        return !self.has_acted and self.is_alive and !self.hasStatus(.stunned);
    }

    /// Check if combatant has a specific status
    pub fn hasStatus(self: *const Combatant, status_type: StatusType) bool {
        for (self.status_effects.items) |effect| {
            if (effect.status_type == status_type and !effect.isExpired()) {
                return true;
            }
        }
        return false;
    }

    /// Get effective dodge chance including modifiers
    pub fn getEffectiveDodge(self: *const Combatant) f32 {
        var dodge = self.dodge_chance;

        // Defending bonus
        if (self.is_defending) {
            dodge += self.defend_dodge_bonus;
        }

        // Status modifiers
        if (self.hasStatus(.blinded)) {
            dodge -= 0.30;
        }
        if (self.hasStatus(.concealed)) {
            dodge += 0.25;
        }

        // Clamp to valid range
        return @max(0.0, @min(0.75, dodge));
    }

    /// Get effective initiative including modifiers
    pub fn getEffectiveInitiative(self: *const Combatant) i32 {
        var init = self.base_initiative;

        // Status modifiers
        if (self.hasStatus(.hasted)) {
            init += 3;
        }
        if (self.hasStatus(.slowed)) {
            init -= 3;
        }

        return init;
    }

    /// Take damage, returns actual damage taken
    pub fn takeDamage(self: *Combatant, raw_damage: i32, piercing: bool) i32 {
        if (self.hasStatus(.invulnerable)) {
            return 0;
        }

        var damage = raw_damage;

        // Apply armor if not piercing
        if (!piercing) {
            damage -= self.armor;
            if (self.is_defending) {
                damage -= self.defend_damage_reduction;
            }
        }

        // Vulnerable increases damage
        if (self.hasStatus(.vulnerable)) {
            damage = @intFromFloat(@as(f32, @floatFromInt(damage)) * 1.5);
        }

        // Fortified reduces damage
        if (self.hasStatus(.fortified)) {
            damage = @intFromFloat(@as(f32, @floatFromInt(damage)) * 0.75);
        }

        damage = @max(0, damage);

        // Absorb with temp HP first
        if (self.temp_hp > 0) {
            const absorbed = @min(self.temp_hp, damage);
            self.temp_hp -= absorbed;
            damage -= absorbed;
        }

        // Apply remaining to HP
        self.current_hp -= damage;
        if (self.current_hp <= 0) {
            self.current_hp = 0;
            self.is_alive = false;
        }

        return raw_damage - @max(0, raw_damage - damage);
    }

    /// Heal HP
    pub fn heal(self: *Combatant, amount: i32) i32 {
        const old_hp = self.current_hp;
        self.current_hp = @min(self.max_hp, self.current_hp + amount);
        return self.current_hp - old_hp;
    }

    /// Add temporary HP
    pub fn addTempHp(self: *Combatant, amount: i32) void {
        self.temp_hp += amount;
    }
};

/// Configuration for a new combatant
pub const CombatantConfig = struct {
    name: []const u8,
    team: Team,
    max_hp: i32,
    initiative: i32,
    movement: i32 = 3,
    position: Position = Position.init(0, 0),
    dodge_chance: f32 = 0.0,
    base_attack: AttackProperties = .{},
    armor: i32 = 0,
    counter_damage: i32 = 0,
    inventory_slots: u32 = 3,
    metadata: u64 = 0,
};

/// An action to be executed
pub const Action = struct {
    /// Combatant performing the action
    combatant_id: u32,
    /// Type of action
    action_type: ActionType,
    /// Target combatant (for attacks/abilities)
    target_id: ?u32 = null,
    /// Target position (for movement)
    target_position: ?Position = null,
    /// Ability ID (for ability actions)
    ability_id: ?[]const u8 = null,
    /// Item slot (for use_item actions)
    item_slot: ?u32 = null,
    /// Override attack properties
    attack_override: ?AttackProperties = null,
};

/// A telegraph showing enemy intent
pub const Telegraph = struct {
    /// Source combatant
    source_id: u32,
    /// Action type
    action_type: ActionType,
    /// Target combatant(s)
    target_ids: std.ArrayList(u32),
    /// Target position (for movement)
    target_position: ?Position,
    /// Damage that will be dealt
    damage: i32,
    /// Hit chance
    hit_chance: f32,
    /// Whether attack is unstoppable
    unstoppable: bool,
    /// Status effects that will be applied
    applies_status: ?StatusType,
    /// Ability name if applicable
    ability_name: ?[]const u8,

    pub fn deinit(self: *Telegraph) void {
        self.target_ids.deinit();
    }
};

/// Result of an action execution
pub const ActionResult = struct {
    /// Combatant that acted
    combatant_id: u32,
    /// Action performed
    action_type: ActionType,
    /// Target(s)
    target_id: ?u32 = null,
    /// Whether action succeeded
    success: bool = true,
    /// Damage dealt
    damage_dealt: i32 = 0,
    /// Whether attack was dodged
    was_dodged: bool = false,
    /// Counter damage dealt back
    counter_damage: i32 = 0,
    /// Status applied
    status_applied: ?StatusType = null,
    /// New position after movement
    new_position: ?Position = null,
    /// Error message if failed
    error_message: ?[]const u8 = null,
};

/// Result of executing a full turn
pub const TurnResult = struct {
    /// Turn number
    turn_number: u32,
    /// Actions executed in order
    action_results: std.ArrayList(ActionResult),
    /// Combatants eliminated this turn
    eliminated: std.ArrayList(u32),
    /// Whether combat ended
    combat_ended: bool = false,
    /// Winning team (if combat ended)
    winning_team: ?Team = null,

    pub fn deinit(self: *TurnResult) void {
        self.action_results.deinit();
        self.eliminated.deinit();
    }
};

/// Combat phase
pub const CombatPhase = enum {
    /// Not in combat
    inactive,
    /// Combat starting, setup phase
    setup,
    /// Showing enemy intents
    telegraph,
    /// Player planning actions
    planning,
    /// Executing actions in initiative order
    execution,
    /// Updating status effects, checking victory
    cleanup,
    /// Combat has ended
    ended,
};

/// Combat configuration
pub const CombatConfig = struct {
    /// Maximum combatants
    max_combatants: u32 = 32,
    /// Enable reaction mechanics
    enable_reactions: bool = true,
    /// Default defend damage reduction
    default_defend_reduction: i32 = 1,
    /// Default defend dodge bonus
    default_defend_dodge: f32 = 0.25,
    /// Maximum dodge chance
    max_dodge_chance: f32 = 0.75,
    /// Turn limit (0 = unlimited)
    turn_limit: u32 = 0,
    /// Random seed for reproducibility (0 = random)
    random_seed: u64 = 0,
};

/// Statistics for the combat encounter
pub const CombatStats = struct {
    total_damage_dealt: i32 = 0,
    total_damage_taken: i32 = 0,
    total_healing: i32 = 0,
    attacks_landed: u32 = 0,
    attacks_dodged: u32 = 0,
    abilities_used: u32 = 0,
    items_used: u32 = 0,
    turns_taken: u32 = 0,
    combatants_eliminated: u32 = 0,
};

/// The main combat system
pub const CombatSystem = struct {
    allocator: std.mem.Allocator,
    config: CombatConfig,

    // Combatants
    combatants: std.AutoHashMap(u32, *Combatant),
    next_combatant_id: u32,

    // Turn order (sorted by initiative)
    turn_order: std.ArrayList(u32),

    // Queued actions for this turn
    queued_actions: std.AutoHashMap(u32, Action),

    // Telegraphs (enemy intents)
    telegraphs: std.ArrayList(Telegraph),

    // Combat state
    phase: CombatPhase,
    current_turn: u32,
    current_actor_index: usize,

    // Random number generator
    rng: std.Random,

    // Statistics
    stats: CombatStats,

    // String storage for names
    name_storage: std.ArrayList([]u8),

    /// Initialize the combat system
    pub fn init(allocator: std.mem.Allocator) CombatSystem {
        return initWithConfig(allocator, .{});
    }

    /// Initialize with custom configuration
    pub fn initWithConfig(allocator: std.mem.Allocator, config: CombatConfig) CombatSystem {
        const seed = if (config.random_seed != 0)
            config.random_seed
        else
            @as(u64, @intCast(std.time.milliTimestamp()));

        var prng = std.rand.DefaultPrng.init(seed);

        return CombatSystem{
            .allocator = allocator,
            .config = config,
            .combatants = std.AutoHashMap(u32, *Combatant).init(allocator),
            .next_combatant_id = 1,
            .turn_order = std.ArrayList(u32).init(allocator),
            .queued_actions = std.AutoHashMap(u32, Action).init(allocator),
            .telegraphs = std.ArrayList(Telegraph).init(allocator),
            .phase = .inactive,
            .current_turn = 0,
            .current_actor_index = 0,
            .rng = prng.random(),
            .stats = .{},
            .name_storage = std.ArrayList([]u8).init(allocator),
        };
    }

    /// Clean up resources
    pub fn deinit(self: *CombatSystem) void {
        // Free combatants
        var it = self.combatants.valueIterator();
        while (it.next()) |combatant_ptr| {
            combatant_ptr.*.status_effects.deinit();
            combatant_ptr.*.abilities.deinit();
            self.allocator.destroy(combatant_ptr.*);
        }
        self.combatants.deinit();

        // Free telegraphs
        for (self.telegraphs.items) |*telegraph| {
            telegraph.deinit();
        }
        self.telegraphs.deinit();

        // Free name storage
        for (self.name_storage.items) |name| {
            self.allocator.free(name);
        }
        self.name_storage.deinit();

        self.turn_order.deinit();
        self.queued_actions.deinit();
    }

    /// Add a combatant to the battle
    pub fn addCombatant(self: *CombatSystem, cfg: CombatantConfig) !u32 {
        const id = self.next_combatant_id;
        self.next_combatant_id += 1;

        // Copy name
        const name_copy = try self.allocator.dupe(u8, cfg.name);
        try self.name_storage.append(name_copy);

        // Create combatant
        const combatant = try self.allocator.create(Combatant);
        combatant.* = Combatant{
            .id = id,
            .name = name_copy,
            .team = cfg.team,
            .current_hp = cfg.max_hp,
            .max_hp = cfg.max_hp,
            .initiative = cfg.initiative,
            .base_initiative = cfg.initiative,
            .movement = cfg.movement,
            .position = cfg.position,
            .dodge_chance = cfg.dodge_chance,
            .base_attack = cfg.base_attack,
            .armor = cfg.armor,
            .counter_damage = cfg.counter_damage,
            .inventory_slots = cfg.inventory_slots,
            .metadata = cfg.metadata,
            .status_effects = std.ArrayList(StatusEffect).init(self.allocator),
            .abilities = std.ArrayList(Ability).init(self.allocator),
        };

        try self.combatants.put(id, combatant);
        return id;
    }

    /// Get a combatant by ID
    pub fn getCombatant(self: *CombatSystem, id: u32) ?*Combatant {
        return self.combatants.get(id);
    }

    /// Get a combatant by ID (const)
    pub fn getCombatantConst(self: *const CombatSystem, id: u32) ?*const Combatant {
        if (self.combatants.get(id)) |c| {
            return c;
        }
        return null;
    }

    /// Add an ability to a combatant
    pub fn addAbility(self: *CombatSystem, combatant_id: u32, ability: Ability) !void {
        if (self.getCombatant(combatant_id)) |combatant| {
            var new_ability = ability;
            if (new_ability.uses_per_encounter > 0) {
                new_ability.uses_remaining = new_ability.uses_per_encounter;
            }
            try combatant.abilities.append(new_ability);
        }
    }

    /// Start combat encounter
    pub fn startCombat(self: *CombatSystem) !void {
        if (self.phase != .inactive) {
            return error.CombatAlreadyStarted;
        }

        // Calculate turn order by initiative
        try self.calculateTurnOrder();

        self.phase = .setup;
        self.current_turn = 0;
    }

    /// Calculate/recalculate turn order based on initiative
    fn calculateTurnOrder(self: *CombatSystem) !void {
        self.turn_order.clearRetainingCapacity();

        var it = self.combatants.iterator();
        while (it.next()) |entry| {
            const combatant = entry.value_ptr.*;
            if (combatant.is_alive) {
                try self.turn_order.append(combatant.id);
            }
        }

        // Sort by initiative (highest first), then by team (player first on ties)
        std.mem.sort(u32, self.turn_order.items, self, compareCombatantInitiative);
    }

    fn compareCombatantInitiative(self: *CombatSystem, a: u32, b: u32) bool {
        const combatant_a = self.getCombatant(a) orelse return false;
        const combatant_b = self.getCombatant(b) orelse return true;

        const init_a = combatant_a.getEffectiveInitiative();
        const init_b = combatant_b.getEffectiveInitiative();

        if (init_a != init_b) {
            return init_a > init_b; // Higher initiative first
        }

        // Ties: player team acts first
        const team_priority_a: u8 = switch (combatant_a.team) {
            .player => 0,
            .ally => 1,
            .neutral => 2,
            .enemy => 3,
        };
        const team_priority_b: u8 = switch (combatant_b.team) {
            .player => 0,
            .ally => 1,
            .neutral => 2,
            .enemy => 3,
        };

        return team_priority_a < team_priority_b;
    }

    /// Begin a new turn
    pub fn beginTurn(self: *CombatSystem) !void {
        self.current_turn += 1;
        self.current_actor_index = 0;

        // Reset combatant turn state
        var it = self.combatants.valueIterator();
        while (it.next()) |combatant_ptr| {
            combatant_ptr.*.has_acted = false;
            combatant_ptr.*.is_defending = false;
        }

        // Clear previous actions and telegraphs
        self.queued_actions.clearRetainingCapacity();
        for (self.telegraphs.items) |*telegraph| {
            telegraph.deinit();
        }
        self.telegraphs.clearRetainingCapacity();

        // Recalculate turn order
        try self.calculateTurnOrder();

        // Generate enemy telegraphs
        try self.generateTelegraphs();

        self.phase = .telegraph;
    }

    /// Generate telegraphs for all enemy combatants
    fn generateTelegraphs(self: *CombatSystem) !void {
        for (self.turn_order.items) |combatant_id| {
            const combatant = self.getCombatant(combatant_id) orelse continue;

            // Only generate telegraphs for enemies
            if (combatant.team != .enemy) continue;
            if (!combatant.is_alive) continue;
            if (combatant.hasStatus(.stunned)) continue;

            // Generate AI action (simple: attack nearest player)
            const action = try self.generateEnemyAction(combatant);
            if (action) |act| {
                try self.queued_actions.put(combatant_id, act);

                // Create telegraph
                var telegraph = Telegraph{
                    .source_id = combatant_id,
                    .action_type = act.action_type,
                    .target_ids = std.ArrayList(u32).init(self.allocator),
                    .target_position = act.target_position,
                    .damage = 0,
                    .hit_chance = 1.0,
                    .unstoppable = false,
                    .applies_status = null,
                    .ability_name = null,
                };

                if (act.target_id) |tid| {
                    try telegraph.target_ids.append(tid);
                }

                // Fill in attack details
                if (act.action_type == .attack) {
                    const props = act.attack_override orelse combatant.base_attack;
                    telegraph.damage = props.damage;
                    telegraph.hit_chance = props.hit_chance;
                    telegraph.unstoppable = props.unstoppable;
                    telegraph.applies_status = props.applies_status;
                }

                try self.telegraphs.append(telegraph);
            }
        }
    }

    /// Generate an action for an enemy combatant (simple AI)
    fn generateEnemyAction(self: *CombatSystem, combatant: *Combatant) !?Action {
        // Find nearest player
        var nearest_player: ?u32 = null;
        var nearest_distance: i32 = std.math.maxInt(i32);

        var it = self.combatants.valueIterator();
        while (it.next()) |other_ptr| {
            const other = other_ptr.*;
            if (other.team == .player and other.is_alive) {
                const dist = combatant.position.distance(other.position);
                if (dist < nearest_distance) {
                    nearest_distance = dist;
                    nearest_player = other.id;
                }
            }
        }

        if (nearest_player) |target_id| {
            const target = self.getCombatant(target_id) orelse return null;

            // Check if in attack range
            if (nearest_distance <= combatant.base_attack.range) {
                return Action{
                    .combatant_id = combatant.id,
                    .action_type = .attack,
                    .target_id = target_id,
                };
            } else {
                // Move towards target
                const dx: i32 = if (target.position.x > combatant.position.x)
                    @min(combatant.movement, target.position.x - combatant.position.x)
                else if (target.position.x < combatant.position.x)
                    -@min(combatant.movement, combatant.position.x - target.position.x)
                else
                    0;

                const dy: i32 = if (target.position.y > combatant.position.y)
                    @min(combatant.movement, target.position.y - combatant.position.y)
                else if (target.position.y < combatant.position.y)
                    -@min(combatant.movement, combatant.position.y - target.position.y)
                else
                    0;

                return Action{
                    .combatant_id = combatant.id,
                    .action_type = .move,
                    .target_position = Position.init(combatant.position.x + dx, combatant.position.y + dy),
                };
            }
        }

        return null;
    }

    /// Enter planning phase (after viewing telegraphs)
    pub fn enterPlanningPhase(self: *CombatSystem) void {
        self.phase = .planning;
    }

    /// Queue an action for a combatant
    pub fn queueAction(self: *CombatSystem, combatant_id: u32, action: Action) !void {
        const combatant = self.getCombatant(combatant_id) orelse return error.InvalidCombatant;

        // Validate action
        if (!combatant.is_alive) return error.CombatantDead;
        if (combatant.team == .enemy) return error.CannotControlEnemy;

        var full_action = action;
        full_action.combatant_id = combatant_id;

        try self.queued_actions.put(combatant_id, full_action);
    }

    /// Get current telegraphs
    pub fn getTelegraphs(self: *const CombatSystem) []const Telegraph {
        return self.telegraphs.items;
    }

    /// Get current turn order
    pub fn getTurnOrder(self: *const CombatSystem) []const u32 {
        return self.turn_order.items;
    }

    /// Execute the current turn
    pub fn executeTurn(self: *CombatSystem) !TurnResult {
        self.phase = .execution;

        var result = TurnResult{
            .turn_number = self.current_turn,
            .action_results = std.ArrayList(ActionResult).init(self.allocator),
            .eliminated = std.ArrayList(u32).init(self.allocator),
        };
        errdefer result.deinit();

        // Execute actions in initiative order
        for (self.turn_order.items) |combatant_id| {
            const combatant = self.getCombatant(combatant_id) orelse continue;
            if (!combatant.is_alive) continue;
            if (combatant.hasStatus(.stunned)) {
                combatant.has_acted = true;
                continue;
            }

            // Get queued action
            if (self.queued_actions.get(combatant_id)) |action| {
                const action_result = try self.executeAction(action);
                try result.action_results.append(action_result);

                // Check for eliminations
                if (action.target_id) |target_id| {
                    const target = self.getCombatant(target_id) orelse continue;
                    if (!target.is_alive) {
                        try result.eliminated.append(target_id);
                        self.stats.combatants_eliminated += 1;
                    }
                }
            }

            combatant.has_acted = true;
        }

        // Cleanup phase
        self.phase = .cleanup;
        try self.processStatusEffects();
        try self.processAbilityCooldowns();

        // Check victory conditions
        const victory_result = self.checkVictory();
        if (victory_result) |winning_team| {
            result.combat_ended = true;
            result.winning_team = winning_team;
            self.phase = .ended;
        }

        // Check turn limit
        if (self.config.turn_limit > 0 and self.current_turn >= self.config.turn_limit) {
            result.combat_ended = true;
            self.phase = .ended;
        }

        self.stats.turns_taken += 1;
        return result;
    }

    /// Execute a single action
    fn executeAction(self: *CombatSystem, action: Action) !ActionResult {
        const combatant = self.getCombatant(action.combatant_id) orelse {
            return ActionResult{
                .combatant_id = action.combatant_id,
                .action_type = action.action_type,
                .success = false,
                .error_message = "Invalid combatant",
            };
        };

        return switch (action.action_type) {
            .move => self.executeMove(combatant, action),
            .attack => self.executeAttack(combatant, action),
            .defend => self.executeDefend(combatant, action),
            .ability => self.executeAbility(combatant, action),
            .wait => ActionResult{
                .combatant_id = action.combatant_id,
                .action_type = .wait,
                .success = true,
            },
            .flee => ActionResult{
                .combatant_id = action.combatant_id,
                .action_type = .flee,
                .success = true,
            },
            .use_item => ActionResult{
                .combatant_id = action.combatant_id,
                .action_type = .use_item,
                .success = true,
            },
        };
    }

    fn executeMove(self: *CombatSystem, combatant: *Combatant, action: Action) ActionResult {
        _ = self;
        const target_pos = action.target_position orelse {
            return ActionResult{
                .combatant_id = combatant.id,
                .action_type = .move,
                .success = false,
                .error_message = "No target position",
            };
        };

        // Check movement range
        const distance = combatant.position.distance(target_pos);
        if (distance > combatant.movement) {
            return ActionResult{
                .combatant_id = combatant.id,
                .action_type = .move,
                .success = false,
                .error_message = "Out of movement range",
            };
        }

        combatant.position = target_pos;

        return ActionResult{
            .combatant_id = combatant.id,
            .action_type = .move,
            .success = true,
            .new_position = target_pos,
        };
    }

    fn executeAttack(self: *CombatSystem, combatant: *Combatant, action: Action) ActionResult {
        const target_id = action.target_id orelse {
            return ActionResult{
                .combatant_id = combatant.id,
                .action_type = .attack,
                .success = false,
                .error_message = "No target",
            };
        };

        const target = self.getCombatant(target_id) orelse {
            return ActionResult{
                .combatant_id = combatant.id,
                .action_type = .attack,
                .success = false,
                .error_message = "Invalid target",
            };
        };

        if (!target.is_alive) {
            return ActionResult{
                .combatant_id = combatant.id,
                .action_type = .attack,
                .success = false,
                .error_message = "Target already dead",
            };
        }

        const props = action.attack_override orelse combatant.base_attack;

        // Check range
        const distance = combatant.position.distance(target.position);
        if (distance > props.range) {
            return ActionResult{
                .combatant_id = combatant.id,
                .action_type = .attack,
                .success = false,
                .error_message = "Out of range",
            };
        }

        var result = ActionResult{
            .combatant_id = combatant.id,
            .action_type = .attack,
            .target_id = target_id,
            .success = true,
        };

        // Check if attack can be dodged (reaction mechanics)
        var was_dodged = false;
        if (self.config.enable_reactions and !props.unstoppable and target.canReact()) {
            const dodge_chance = target.getEffectiveDodge();
            const roll = self.rng.float(f32);
            if (roll < dodge_chance) {
                was_dodged = true;
                result.was_dodged = true;
                self.stats.attacks_dodged += 1;
            }
        }

        if (!was_dodged) {
            // Apply damage
            const damage = target.takeDamage(props.damage, props.piercing);
            result.damage_dealt = damage;
            self.stats.total_damage_dealt += damage;
            self.stats.attacks_landed += 1;

            // Apply status effect
            if (props.applies_status) |status_type| {
                try target.status_effects.append(.{
                    .status_type = status_type,
                    .duration = props.status_duration,
                    .source_id = combatant.id,
                });
                result.status_applied = status_type;
            }
        }

        // Counter attack (if target can react and has counter damage)
        if (self.config.enable_reactions and target.canReact() and target.counter_damage > 0 and distance <= 1) {
            const counter_damage = combatant.takeDamage(target.counter_damage, false);
            result.counter_damage = counter_damage;
        }

        return result;
    }

    fn executeDefend(self: *CombatSystem, combatant: *Combatant, action: Action) ActionResult {
        _ = action;
        combatant.is_defending = true;
        combatant.defend_damage_reduction = self.config.default_defend_reduction;
        combatant.defend_dodge_bonus = self.config.default_defend_dodge;

        return ActionResult{
            .combatant_id = combatant.id,
            .action_type = .defend,
            .success = true,
        };
    }

    fn executeAbility(self: *CombatSystem, combatant: *Combatant, action: Action) ActionResult {
        const ability_id = action.ability_id orelse {
            return ActionResult{
                .combatant_id = combatant.id,
                .action_type = .ability,
                .success = false,
                .error_message = "No ability specified",
            };
        };

        // Find ability
        var ability: ?*Ability = null;
        for (combatant.abilities.items) |*ab| {
            if (std.mem.eql(u8, ab.id, ability_id)) {
                ability = ab;
                break;
            }
        }

        const ab = ability orelse {
            return ActionResult{
                .combatant_id = combatant.id,
                .action_type = .ability,
                .success = false,
                .error_message = "Ability not found",
            };
        };

        // Check cooldown
        if (ab.current_cooldown > 0) {
            return ActionResult{
                .combatant_id = combatant.id,
                .action_type = .ability,
                .success = false,
                .error_message = "Ability on cooldown",
            };
        }

        // Check uses
        if (ab.uses_per_encounter > 0 and ab.uses_remaining == 0) {
            return ActionResult{
                .combatant_id = combatant.id,
                .action_type = .ability,
                .success = false,
                .error_message = "No uses remaining",
            };
        }

        var result = ActionResult{
            .combatant_id = combatant.id,
            .action_type = .ability,
            .success = true,
        };

        // Apply self effect
        if (ab.self_effect) |status_type| {
            try combatant.status_effects.append(.{
                .status_type = status_type,
                .duration = ab.self_effect_duration,
                .source_id = combatant.id,
            });
        }

        // Execute attack if offensive ability
        if (ab.attack) |props| {
            if (action.target_id) |target_id| {
                const target = self.getCombatant(target_id);
                if (target) |t| {
                    const damage = t.takeDamage(props.damage, props.piercing);
                    result.damage_dealt = damage;
                    result.target_id = target_id;
                    self.stats.total_damage_dealt += damage;

                    if (props.applies_status) |status_type| {
                        try t.status_effects.append(.{
                            .status_type = status_type,
                            .duration = props.status_duration,
                            .source_id = combatant.id,
                        });
                        result.status_applied = status_type;
                    }
                }
            }
        }

        // Consume use and start cooldown
        if (ab.uses_per_encounter > 0) {
            ab.uses_remaining -= 1;
        }
        ab.current_cooldown = ab.cooldown;

        self.stats.abilities_used += 1;
        return result;
    }

    /// Process status effects (tick durations, apply DoT)
    fn processStatusEffects(self: *CombatSystem) !void {
        var it = self.combatants.valueIterator();
        while (it.next()) |combatant_ptr| {
            const combatant = combatant_ptr.*;
            if (!combatant.is_alive) continue;

            // Process each status effect
            var i: usize = 0;
            while (i < combatant.status_effects.items.len) {
                var effect = &combatant.status_effects.items[i];

                // Apply DoT damage
                if (effect.damage_per_tick > 0) {
                    _ = combatant.takeDamage(effect.damage_per_tick, true);
                }

                // Tick duration
                effect.tick();

                // Remove expired effects
                if (effect.isExpired()) {
                    _ = combatant.status_effects.swapRemove(i);
                } else {
                    i += 1;
                }
            }
        }
    }

    /// Process ability cooldowns
    fn processAbilityCooldowns(self: *CombatSystem) !void {
        var it = self.combatants.valueIterator();
        while (it.next()) |combatant_ptr| {
            const combatant = combatant_ptr.*;
            for (combatant.abilities.items) |*ability| {
                if (ability.current_cooldown > 0) {
                    ability.current_cooldown -= 1;
                }
            }
        }
    }

    /// Check victory conditions
    fn checkVictory(self: *CombatSystem) ?Team {
        var player_alive = false;
        var enemy_alive = false;

        var it = self.combatants.valueIterator();
        while (it.next()) |combatant_ptr| {
            const combatant = combatant_ptr.*;
            if (combatant.is_alive) {
                switch (combatant.team) {
                    .player, .ally => player_alive = true,
                    .enemy => enemy_alive = true,
                    .neutral => {},
                }
            }
        }

        if (!enemy_alive) return .player;
        if (!player_alive) return .enemy;
        return null;
    }

    /// Apply a status effect to a combatant
    pub fn applyStatus(self: *CombatSystem, combatant_id: u32, status_type: StatusType, duration: ?u32, source_id: ?u32) !void {
        const combatant = self.getCombatant(combatant_id) orelse return error.InvalidCombatant;
        try combatant.status_effects.append(.{
            .status_type = status_type,
            .duration = duration,
            .source_id = source_id,
        });
    }

    /// Get combat phase
    pub fn getPhase(self: *const CombatSystem) CombatPhase {
        return self.phase;
    }

    /// Get current turn number
    pub fn getCurrentTurn(self: *const CombatSystem) u32 {
        return self.current_turn;
    }

    /// Get combat statistics
    pub fn getStats(self: *const CombatSystem) CombatStats {
        return self.stats;
    }

    /// Get all combatants on a specific team
    pub fn getCombatantsByTeam(self: *CombatSystem, team: Team, out_buffer: []u32) usize {
        var count: usize = 0;
        var it = self.combatants.valueIterator();
        while (it.next()) |combatant_ptr| {
            if (count >= out_buffer.len) break;
            const combatant = combatant_ptr.*;
            if (combatant.team == team and combatant.is_alive) {
                out_buffer[count] = combatant.id;
                count += 1;
            }
        }
        return count;
    }

    /// Get all living combatants
    pub fn getLivingCombatants(self: *CombatSystem, out_buffer: []u32) usize {
        var count: usize = 0;
        var it = self.combatants.valueIterator();
        while (it.next()) |combatant_ptr| {
            if (count >= out_buffer.len) break;
            const combatant = combatant_ptr.*;
            if (combatant.is_alive) {
                out_buffer[count] = combatant.id;
                count += 1;
            }
        }
        return count;
    }

    /// Check if combat is active
    pub fn isActive(self: *const CombatSystem) bool {
        return self.phase != .inactive and self.phase != .ended;
    }

    /// End combat immediately
    pub fn endCombat(self: *CombatSystem) void {
        self.phase = .ended;
    }

    /// Reset combat system for a new encounter
    pub fn reset(self: *CombatSystem) void {
        // Clear combatants
        var it = self.combatants.valueIterator();
        while (it.next()) |combatant_ptr| {
            combatant_ptr.*.status_effects.deinit();
            combatant_ptr.*.abilities.deinit();
            self.allocator.destroy(combatant_ptr.*);
        }
        self.combatants.clearRetainingCapacity();

        // Clear telegraphs
        for (self.telegraphs.items) |*telegraph| {
            telegraph.deinit();
        }
        self.telegraphs.clearRetainingCapacity();

        // Clear other state
        self.turn_order.clearRetainingCapacity();
        self.queued_actions.clearRetainingCapacity();

        // Clear name storage
        for (self.name_storage.items) |name| {
            self.allocator.free(name);
        }
        self.name_storage.clearRetainingCapacity();

        // Reset counters
        self.next_combatant_id = 1;
        self.phase = .inactive;
        self.current_turn = 0;
        self.current_actor_index = 0;
        self.stats = .{};
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Position - basic operations" {
    const p1 = Position.init(0, 0);
    const p2 = Position.init(3, 4);

    try std.testing.expectEqual(@as(i32, 4), p1.distance(p2)); // Chebyshev distance
    try std.testing.expectEqual(@as(i32, 7), p1.manhattanDistance(p2));
    try std.testing.expect(p1.eql(Position.init(0, 0)));
    try std.testing.expect(!p1.eql(p2));
}

test "CombatSystem - init and deinit" {
    var combat = CombatSystem.init(std.testing.allocator);
    defer combat.deinit();

    try std.testing.expectEqual(CombatPhase.inactive, combat.getPhase());
    try std.testing.expectEqual(@as(u32, 0), combat.getCurrentTurn());
}

test "CombatSystem - add combatant" {
    var combat = CombatSystem.init(std.testing.allocator);
    defer combat.deinit();

    const id = try combat.addCombatant(.{
        .name = "Scout",
        .team = .player,
        .max_hp = 4,
        .initiative = 8,
        .movement = 4,
        .position = Position.init(0, 0),
    });

    const combatant = combat.getCombatant(id);
    try std.testing.expect(combatant != null);
    try std.testing.expectEqual(@as(i32, 4), combatant.?.max_hp);
    try std.testing.expectEqual(@as(i32, 8), combatant.?.initiative);
}

test "CombatSystem - start combat" {
    var combat = CombatSystem.init(std.testing.allocator);
    defer combat.deinit();

    _ = try combat.addCombatant(.{
        .name = "Player",
        .team = .player,
        .max_hp = 10,
        .initiative = 5,
    });

    try combat.startCombat();
    try std.testing.expectEqual(CombatPhase.setup, combat.getPhase());
}

test "CombatSystem - turn order by initiative" {
    var combat = CombatSystem.init(std.testing.allocator);
    defer combat.deinit();

    const low = try combat.addCombatant(.{
        .name = "Low Init",
        .team = .player,
        .max_hp = 10,
        .initiative = 3,
    });

    const high = try combat.addCombatant(.{
        .name = "High Init",
        .team = .enemy,
        .max_hp = 10,
        .initiative = 10,
    });

    const mid = try combat.addCombatant(.{
        .name = "Mid Init",
        .team = .player,
        .max_hp = 10,
        .initiative = 5,
    });

    try combat.startCombat();

    const order = combat.getTurnOrder();
    try std.testing.expectEqual(@as(usize, 3), order.len);
    try std.testing.expectEqual(high, order[0]); // Highest initiative first
    try std.testing.expectEqual(mid, order[1]);
    try std.testing.expectEqual(low, order[2]);
}

test "CombatSystem - player acts first on ties" {
    var combat = CombatSystem.init(std.testing.allocator);
    defer combat.deinit();

    const enemy = try combat.addCombatant(.{
        .name = "Enemy",
        .team = .enemy,
        .max_hp = 10,
        .initiative = 5,
    });

    const player = try combat.addCombatant(.{
        .name = "Player",
        .team = .player,
        .max_hp = 10,
        .initiative = 5,
    });

    try combat.startCombat();

    const order = combat.getTurnOrder();
    try std.testing.expectEqual(player, order[0]); // Player first on tie
    try std.testing.expectEqual(enemy, order[1]);
}

test "Combatant - take damage" {
    var combat = CombatSystem.init(std.testing.allocator);
    defer combat.deinit();

    const id = try combat.addCombatant(.{
        .name = "Test",
        .team = .player,
        .max_hp = 10,
        .initiative = 5,
        .armor = 2,
    });

    const combatant = combat.getCombatant(id).?;

    // Normal damage (reduced by armor)
    const damage1 = combatant.takeDamage(5, false);
    try std.testing.expectEqual(@as(i32, 3), damage1); // 5 - 2 armor = 3
    try std.testing.expectEqual(@as(i32, 7), combatant.current_hp);

    // Piercing damage (ignores armor)
    const damage2 = combatant.takeDamage(5, true);
    try std.testing.expectEqual(@as(i32, 5), damage2);
    try std.testing.expectEqual(@as(i32, 2), combatant.current_hp);
}

test "Combatant - temp HP absorbs damage" {
    var combat = CombatSystem.init(std.testing.allocator);
    defer combat.deinit();

    const id = try combat.addCombatant(.{
        .name = "Test",
        .team = .player,
        .max_hp = 10,
        .initiative = 5,
    });

    const combatant = combat.getCombatant(id).?;
    combatant.addTempHp(5);

    try std.testing.expectEqual(@as(i32, 5), combatant.temp_hp);

    _ = combatant.takeDamage(3, true);
    try std.testing.expectEqual(@as(i32, 2), combatant.temp_hp);
    try std.testing.expectEqual(@as(i32, 10), combatant.current_hp); // HP untouched

    _ = combatant.takeDamage(5, true);
    try std.testing.expectEqual(@as(i32, 0), combatant.temp_hp);
    try std.testing.expectEqual(@as(i32, 7), combatant.current_hp); // 3 damage to HP
}

test "Combatant - death" {
    var combat = CombatSystem.init(std.testing.allocator);
    defer combat.deinit();

    const id = try combat.addCombatant(.{
        .name = "Test",
        .team = .player,
        .max_hp = 5,
        .initiative = 5,
    });

    const combatant = combat.getCombatant(id).?;
    try std.testing.expect(combatant.is_alive);

    _ = combatant.takeDamage(10, true);
    try std.testing.expect(!combatant.is_alive);
    try std.testing.expectEqual(@as(i32, 0), combatant.current_hp);
}

test "Combatant - heal" {
    var combat = CombatSystem.init(std.testing.allocator);
    defer combat.deinit();

    const id = try combat.addCombatant(.{
        .name = "Test",
        .team = .player,
        .max_hp = 10,
        .initiative = 5,
    });

    const combatant = combat.getCombatant(id).?;
    _ = combatant.takeDamage(5, true);
    try std.testing.expectEqual(@as(i32, 5), combatant.current_hp);

    const healed = combatant.heal(3);
    try std.testing.expectEqual(@as(i32, 3), healed);
    try std.testing.expectEqual(@as(i32, 8), combatant.current_hp);

    // Cannot exceed max HP
    const healed2 = combatant.heal(10);
    try std.testing.expectEqual(@as(i32, 2), healed2);
    try std.testing.expectEqual(@as(i32, 10), combatant.current_hp);
}

test "Combatant - status effects" {
    var combat = CombatSystem.init(std.testing.allocator);
    defer combat.deinit();

    const id = try combat.addCombatant(.{
        .name = "Test",
        .team = .player,
        .max_hp = 10,
        .initiative = 5,
    });

    const combatant = combat.getCombatant(id).?;
    try std.testing.expect(!combatant.hasStatus(.stunned));

    try combatant.status_effects.append(.{
        .status_type = .stunned,
        .duration = 2,
    });

    try std.testing.expect(combatant.hasStatus(.stunned));
    try std.testing.expect(!combatant.canReact());
}

test "Combatant - effective dodge with defend" {
    var combat = CombatSystem.init(std.testing.allocator);
    defer combat.deinit();

    const id = try combat.addCombatant(.{
        .name = "Test",
        .team = .player,
        .max_hp = 10,
        .initiative = 5,
        .dodge_chance = 0.10,
    });

    const combatant = combat.getCombatant(id).?;

    try std.testing.expectApproxEqAbs(@as(f32, 0.10), combatant.getEffectiveDodge(), 0.001);

    combatant.is_defending = true;
    try std.testing.expectApproxEqAbs(@as(f32, 0.35), combatant.getEffectiveDodge(), 0.001);
}

test "CombatSystem - execute move action" {
    var combat = CombatSystem.init(std.testing.allocator);
    defer combat.deinit();

    const id = try combat.addCombatant(.{
        .name = "Test",
        .team = .player,
        .max_hp = 10,
        .initiative = 5,
        .movement = 3,
        .position = Position.init(0, 0),
    });

    try combat.startCombat();
    try combat.beginTurn();
    combat.enterPlanningPhase();

    try combat.queueAction(id, .{
        .combatant_id = id,
        .action_type = .move,
        .target_position = Position.init(2, 1),
    });

    var result = try combat.executeTurn();
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.action_results.items.len);
    try std.testing.expect(result.action_results.items[0].success);

    const combatant = combat.getCombatant(id).?;
    try std.testing.expectEqual(@as(i32, 2), combatant.position.x);
    try std.testing.expectEqual(@as(i32, 1), combatant.position.y);
}

test "CombatSystem - execute attack action" {
    var combat = CombatSystem.initWithConfig(std.testing.allocator, .{
        .enable_reactions = false, // Disable dodge for deterministic test
    });
    defer combat.deinit();

    const attacker = try combat.addCombatant(.{
        .name = "Attacker",
        .team = .player,
        .max_hp = 10,
        .initiative = 5,
        .base_attack = .{ .damage = 3, .range = 5 },
        .position = Position.init(0, 0),
    });

    const target = try combat.addCombatant(.{
        .name = "Target",
        .team = .enemy,
        .max_hp = 10,
        .initiative = 3,
        .position = Position.init(2, 0),
    });

    try combat.startCombat();
    try combat.beginTurn();
    combat.enterPlanningPhase();

    try combat.queueAction(attacker, .{
        .combatant_id = attacker,
        .action_type = .attack,
        .target_id = target,
    });

    var result = try combat.executeTurn();
    defer result.deinit();

    const target_combatant = combat.getCombatant(target).?;
    try std.testing.expectEqual(@as(i32, 7), target_combatant.current_hp); // 10 - 3 = 7
}

test "CombatSystem - victory condition" {
    var combat = CombatSystem.initWithConfig(std.testing.allocator, .{
        .enable_reactions = false,
    });
    defer combat.deinit();

    const player = try combat.addCombatant(.{
        .name = "Player",
        .team = .player,
        .max_hp = 10,
        .initiative = 10,
        .base_attack = .{ .damage = 100, .range = 10 },
    });

    const enemy = try combat.addCombatant(.{
        .name = "Enemy",
        .team = .enemy,
        .max_hp = 5,
        .initiative = 3,
    });

    try combat.startCombat();
    try combat.beginTurn();
    combat.enterPlanningPhase();

    try combat.queueAction(player, .{
        .combatant_id = player,
        .action_type = .attack,
        .target_id = enemy,
    });

    var result = try combat.executeTurn();
    defer result.deinit();

    try std.testing.expect(result.combat_ended);
    try std.testing.expectEqual(Team.player, result.winning_team.?);
}

test "CombatSystem - telegraph generation" {
    var combat = CombatSystem.init(std.testing.allocator);
    defer combat.deinit();

    _ = try combat.addCombatant(.{
        .name = "Player",
        .team = .player,
        .max_hp = 10,
        .initiative = 5,
        .position = Position.init(0, 0),
    });

    _ = try combat.addCombatant(.{
        .name = "Enemy",
        .team = .enemy,
        .max_hp = 10,
        .initiative = 8,
        .base_attack = .{ .damage = 2, .range = 1 },
        .position = Position.init(1, 0),
    });

    try combat.startCombat();
    try combat.beginTurn();

    const telegraphs = combat.getTelegraphs();
    try std.testing.expectEqual(@as(usize, 1), telegraphs.len);
    try std.testing.expectEqual(ActionType.attack, telegraphs[0].action_type);
    try std.testing.expectEqual(@as(i32, 2), telegraphs[0].damage);
}

test "StatusEffect - tick and expiry" {
    var effect = StatusEffect{
        .status_type = .stunned,
        .duration = 2,
    };

    try std.testing.expect(!effect.isExpired());

    effect.tick();
    try std.testing.expectEqual(@as(u32, 1), effect.duration.?);
    try std.testing.expect(!effect.isExpired());

    effect.tick();
    try std.testing.expectEqual(@as(u32, 0), effect.duration.?);
    try std.testing.expect(effect.isExpired());
}

test "Combatant - effective initiative with status" {
    var combat = CombatSystem.init(std.testing.allocator);
    defer combat.deinit();

    const id = try combat.addCombatant(.{
        .name = "Test",
        .team = .player,
        .max_hp = 10,
        .initiative = 5,
    });

    const combatant = combat.getCombatant(id).?;
    try std.testing.expectEqual(@as(i32, 5), combatant.getEffectiveInitiative());

    try combatant.status_effects.append(.{ .status_type = .hasted, .duration = 1 });
    try std.testing.expectEqual(@as(i32, 8), combatant.getEffectiveInitiative());
}

test "CombatSystem - defend action" {
    var combat = CombatSystem.init(std.testing.allocator);
    defer combat.deinit();

    const id = try combat.addCombatant(.{
        .name = "Test",
        .team = .player,
        .max_hp = 10,
        .initiative = 5,
        .dodge_chance = 0.0,
    });

    try combat.startCombat();
    try combat.beginTurn();
    combat.enterPlanningPhase();

    try combat.queueAction(id, .{
        .combatant_id = id,
        .action_type = .defend,
    });

    var result = try combat.executeTurn();
    defer result.deinit();

    const combatant = combat.getCombatant(id).?;
    try std.testing.expect(combatant.is_defending);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), combatant.getEffectiveDodge(), 0.001);
}

test "CombatSystem - reset" {
    var combat = CombatSystem.init(std.testing.allocator);
    defer combat.deinit();

    _ = try combat.addCombatant(.{
        .name = "Test",
        .team = .player,
        .max_hp = 10,
        .initiative = 5,
    });

    try combat.startCombat();
    try std.testing.expectEqual(CombatPhase.setup, combat.getPhase());

    combat.reset();

    try std.testing.expectEqual(CombatPhase.inactive, combat.getPhase());
    try std.testing.expectEqual(@as(u32, 0), combat.getCurrentTurn());
}

test "CombatSystem - add ability" {
    var combat = CombatSystem.init(std.testing.allocator);
    defer combat.deinit();

    const id = try combat.addCombatant(.{
        .name = "Test",
        .team = .player,
        .max_hp = 10,
        .initiative = 5,
    });

    try combat.addAbility(id, .{
        .id = "fireball",
        .name = "Fireball",
        .cooldown = 2,
        .attack = .{ .damage = 5, .range = 3 },
    });

    const combatant = combat.getCombatant(id).?;
    try std.testing.expectEqual(@as(usize, 1), combatant.abilities.items.len);
    try std.testing.expectEqualStrings("fireball", combatant.abilities.items[0].id);
}

test "CombatSystem - get combatants by team" {
    var combat = CombatSystem.init(std.testing.allocator);
    defer combat.deinit();

    _ = try combat.addCombatant(.{ .name = "P1", .team = .player, .max_hp = 10, .initiative = 5 });
    _ = try combat.addCombatant(.{ .name = "P2", .team = .player, .max_hp = 10, .initiative = 5 });
    _ = try combat.addCombatant(.{ .name = "E1", .team = .enemy, .max_hp = 10, .initiative = 5 });

    var buffer: [10]u32 = undefined;
    const player_count = combat.getCombatantsByTeam(.player, &buffer);
    try std.testing.expectEqual(@as(usize, 2), player_count);

    const enemy_count = combat.getCombatantsByTeam(.enemy, &buffer);
    try std.testing.expectEqual(@as(usize, 1), enemy_count);
}

test "CombatSystem - stats tracking" {
    var combat = CombatSystem.initWithConfig(std.testing.allocator, .{
        .enable_reactions = false,
    });
    defer combat.deinit();

    const attacker = try combat.addCombatant(.{
        .name = "Attacker",
        .team = .player,
        .max_hp = 10,
        .initiative = 10,
        .base_attack = .{ .damage = 3, .range = 5 },
    });

    const target = try combat.addCombatant(.{
        .name = "Target",
        .team = .enemy,
        .max_hp = 100,
        .initiative = 3,
    });

    try combat.startCombat();
    try combat.beginTurn();
    combat.enterPlanningPhase();

    try combat.queueAction(attacker, .{
        .combatant_id = attacker,
        .action_type = .attack,
        .target_id = target,
    });

    var result = try combat.executeTurn();
    defer result.deinit();

    const stats = combat.getStats();
    try std.testing.expectEqual(@as(i32, 3), stats.total_damage_dealt);
    try std.testing.expectEqual(@as(u32, 1), stats.attacks_landed);
    try std.testing.expectEqual(@as(u32, 1), stats.turns_taken);
}
