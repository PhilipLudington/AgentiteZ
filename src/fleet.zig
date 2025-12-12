//! Fleet/Unit Combat System - Auto-Resolve Strategic Combat
//!
//! A strategic combat system for fleet battles with rock-paper-scissors counters,
//! commander bonuses, and statistical auto-resolve with preview.
//!
//! Features:
//! - Unit types with rock-paper-scissors counters (fighters beat bombers, bombers beat capitals, etc.)
//! - Fleet composition with unit counts and health
//! - Commander/Admiral system with stat bonuses
//! - Auto-resolve combat with statistical damage calculation
//! - Battle preview showing expected casualties
//! - Morale system with retreat mechanics
//! - Support for both space fleets and ground armies
//!
//! Usage:
//! ```zig
//! var system = FleetCombatSystem.init(allocator);
//! defer system.deinit();
//!
//! // Create fleets
//! const attacker = try system.createFleet(.{
//!     .name = "Alpha Fleet",
//!     .owner_id = 0,
//! });
//!
//! try system.addUnits(attacker, .fighter, 100);
//! try system.addUnits(attacker, .capital, 5);
//! try system.assignCommander(attacker, .{ .name = "Admiral Chen", .attack_bonus = 0.15 });
//!
//! // Preview battle
//! const preview = try system.previewBattle(attacker, defender);
//! // preview.attacker_losses, preview.defender_losses, preview.win_probability
//!
//! // Execute battle
//! var result = try system.resolveBattle(attacker, defender);
//! defer result.deinit();
//! ```

const std = @import("std");

const log = std.log.scoped(.fleet);

/// Unit class determining combat role and counters
pub const UnitClass = enum {
    /// Fast, anti-fighter/bomber units. Counters: bomber, interceptor
    fighter,
    /// Heavy strike craft, anti-capital. Counters: capital, station
    bomber,
    /// Defensive fighters. Counters: fighter, bomber
    interceptor,
    /// Medium warships, balanced. Counters: fighter, corvette
    frigate,
    /// Fast attack ships. Counters: frigate, support
    corvette,
    /// Heavy warships. Counters: frigate, corvette, cruiser
    capital,
    /// Largest warships. Counters: capital, station
    dreadnought,
    /// Carrier vessels, deploys fighters. Counters: none directly
    carrier,
    /// Support/logistics vessels. Buffs allies, weak in combat
    support,
    /// Defensive structures. High HP, immobile
    station,

    // Ground unit types
    /// Light infantry. Counters: militia, recon
    infantry,
    /// Militia/garrison. Weak but cheap
    militia,
    /// Armored vehicles. Counters: infantry, fortification
    armor,
    /// Anti-armor infantry. Counters: armor, mech
    anti_armor,
    /// Artillery units. Counters: infantry, fortification
    artillery,
    /// Scout/recon units. Fast, reveals enemies
    recon,
    /// Heavy mechs. Counters: armor, infantry, fortification
    mech,
    /// Defensive structures. High defense
    fortification,
};

/// Counter effectiveness values
pub const CounterEffectiveness = struct {
    /// Strong counter (deals 50% more damage)
    pub const strong: f32 = 1.5;
    /// Weak counter (deals 25% more damage)
    pub const weak: f32 = 1.25;
    /// Neutral (normal damage)
    pub const neutral: f32 = 1.0;
    /// Countered (deals 25% less damage)
    pub const countered: f32 = 0.75;
    /// Hard countered (deals 50% less damage)
    pub const hard_countered: f32 = 0.5;
};

/// Base stats for each unit class
pub const UnitStats = struct {
    /// Attack power per unit
    attack: f32,
    /// Defense/HP per unit
    defense: f32,
    /// Movement speed (for ground combat)
    speed: f32,
    /// Range of attack
    range: f32,
    /// Cost to produce
    cost: u32,
    /// Supply/upkeep cost
    supply: u32,
    /// Can this unit retreat?
    can_retreat: bool,
    /// Is this unit a structure (immobile)?
    is_structure: bool,

    pub fn getDefault(class: UnitClass) UnitStats {
        return switch (class) {
            // Space units
            .fighter => .{ .attack = 5, .defense = 3, .speed = 10, .range = 1, .cost = 10, .supply = 1, .can_retreat = true, .is_structure = false },
            .bomber => .{ .attack = 15, .defense = 5, .speed = 6, .range = 2, .cost = 25, .supply = 2, .can_retreat = true, .is_structure = false },
            .interceptor => .{ .attack = 8, .defense = 4, .speed = 12, .range = 1, .cost = 15, .supply = 1, .can_retreat = true, .is_structure = false },
            .frigate => .{ .attack = 20, .defense = 25, .speed = 5, .range = 3, .cost = 50, .supply = 3, .can_retreat = true, .is_structure = false },
            .corvette => .{ .attack = 12, .defense = 15, .speed = 8, .range = 2, .cost = 30, .supply = 2, .can_retreat = true, .is_structure = false },
            .capital => .{ .attack = 50, .defense = 80, .speed = 3, .range = 5, .cost = 200, .supply = 10, .can_retreat = true, .is_structure = false },
            .dreadnought => .{ .attack = 100, .defense = 150, .speed = 2, .range = 6, .cost = 500, .supply = 25, .can_retreat = true, .is_structure = false },
            .carrier => .{ .attack = 10, .defense = 60, .speed = 3, .range = 8, .cost = 300, .supply = 15, .can_retreat = true, .is_structure = false },
            .support => .{ .attack = 5, .defense = 20, .speed = 4, .range = 4, .cost = 75, .supply = 5, .can_retreat = true, .is_structure = false },
            .station => .{ .attack = 80, .defense = 200, .speed = 0, .range = 6, .cost = 400, .supply = 0, .can_retreat = false, .is_structure = true },
            // Ground units
            .infantry => .{ .attack = 8, .defense = 6, .speed = 3, .range = 1, .cost = 15, .supply = 1, .can_retreat = true, .is_structure = false },
            .militia => .{ .attack = 4, .defense = 4, .speed = 2, .range = 1, .cost = 5, .supply = 1, .can_retreat = true, .is_structure = false },
            .armor => .{ .attack = 25, .defense = 40, .speed = 5, .range = 3, .cost = 80, .supply = 4, .can_retreat = true, .is_structure = false },
            .anti_armor => .{ .attack = 20, .defense = 8, .speed = 2, .range = 2, .cost = 25, .supply = 2, .can_retreat = true, .is_structure = false },
            .artillery => .{ .attack = 35, .defense = 10, .speed = 2, .range = 6, .cost = 60, .supply = 3, .can_retreat = true, .is_structure = false },
            .recon => .{ .attack = 5, .defense = 4, .speed = 8, .range = 1, .cost = 20, .supply = 1, .can_retreat = true, .is_structure = false },
            .mech => .{ .attack = 45, .defense = 60, .speed = 4, .range = 3, .cost = 150, .supply = 8, .can_retreat = true, .is_structure = false },
            .fortification => .{ .attack = 30, .defense = 100, .speed = 0, .range = 4, .cost = 100, .supply = 0, .can_retreat = false, .is_structure = true },
        };
    }
};

/// A unit group within a fleet
pub const UnitGroup = struct {
    /// Unit class
    class: UnitClass,
    /// Number of units
    count: u32,
    /// Current health per unit (0.0 to 1.0)
    health: f32 = 1.0,
    /// Experience level (affects combat effectiveness)
    experience: f32 = 0.0,
    /// Custom stat overrides (null = use defaults)
    custom_stats: ?UnitStats = null,

    /// Get effective stats for this group
    pub fn getStats(self: *const UnitGroup) UnitStats {
        return self.custom_stats orelse UnitStats.getDefault(self.class);
    }

    /// Get total attack power
    pub fn getTotalAttack(self: *const UnitGroup) f32 {
        const stats = self.getStats();
        const exp_bonus = 1.0 + (self.experience * 0.5); // Up to +50% at max experience
        return stats.attack * @as(f32, @floatFromInt(self.count)) * self.health * exp_bonus;
    }

    /// Get total defense
    pub fn getTotalDefense(self: *const UnitGroup) f32 {
        const stats = self.getStats();
        const exp_bonus = 1.0 + (self.experience * 0.25); // Up to +25% at max experience
        return stats.defense * @as(f32, @floatFromInt(self.count)) * self.health * exp_bonus;
    }

    /// Get total supply cost
    pub fn getTotalSupply(self: *const UnitGroup) u32 {
        const stats = self.getStats();
        return stats.supply * self.count;
    }

    /// Check if group is eliminated
    pub fn isEliminated(self: *const UnitGroup) bool {
        return self.count == 0;
    }
};

/// Commander/Admiral that leads a fleet
pub const Commander = struct {
    /// Commander name
    name: []const u8,
    /// Attack bonus (0.15 = +15%)
    attack_bonus: f32 = 0.0,
    /// Defense bonus
    defense_bonus: f32 = 0.0,
    /// Morale bonus
    morale_bonus: f32 = 0.0,
    /// Speed bonus
    speed_bonus: f32 = 0.0,
    /// Experience (affects all bonuses)
    experience: f32 = 0.0,
    /// Special ability (optional)
    ability: ?CommanderAbility = null,
    /// Unique identifier
    id: u32 = 0,

    /// Get total attack modifier
    pub fn getAttackModifier(self: *const Commander) f32 {
        return 1.0 + self.attack_bonus + (self.experience * 0.1);
    }

    /// Get total defense modifier
    pub fn getDefenseModifier(self: *const Commander) f32 {
        return 1.0 + self.defense_bonus + (self.experience * 0.05);
    }

    /// Get morale modifier
    pub fn getMoraleModifier(self: *const Commander) f32 {
        return 1.0 + self.morale_bonus + (self.experience * 0.1);
    }
};

/// Special abilities commanders can have
pub const CommanderAbility = enum {
    /// +25% damage on first combat round
    first_strike,
    /// +15% defense when outnumbered
    last_stand,
    /// +20% damage to capitals/dreadnoughts
    capital_hunter,
    /// +30% fighter effectiveness
    ace_pilot,
    /// Reduces retreat losses by 50%
    tactical_retreat,
    /// +10% to all stats
    inspiring_leader,
    /// Reveals enemy fleet composition
    intelligence,
    /// Repairs 10% HP per round
    field_repair,
};

/// A fleet (group of unit groups with optional commander)
pub const Fleet = struct {
    /// Unique identifier
    id: u32,
    /// Fleet name
    name: []const u8,
    /// Owner player ID
    owner_id: u32,
    /// Unit groups in this fleet
    units: std.ArrayList(UnitGroup),
    /// Assigned commander (optional)
    commander: ?Commander = null,
    /// Current morale (0.0 to 1.0, below 0.3 may retreat)
    morale: f32 = 1.0,
    /// Position X
    position_x: f32 = 0,
    /// Position Y
    position_y: f32 = 0,
    /// Is this fleet in combat?
    in_combat: bool = false,
    /// Fleet metadata
    metadata: u64 = 0,

    /// Get total unit count
    pub fn getTotalUnits(self: *const Fleet) u32 {
        var total: u32 = 0;
        for (self.units.items) |group| {
            total += group.count;
        }
        return total;
    }

    /// Get total attack power
    pub fn getTotalAttack(self: *const Fleet) f32 {
        var total: f32 = 0;
        for (self.units.items) |group| {
            total += group.getTotalAttack();
        }
        // Apply commander bonus
        if (self.commander) |cmd| {
            total *= cmd.getAttackModifier();
        }
        return total;
    }

    /// Get total defense
    pub fn getTotalDefense(self: *const Fleet) f32 {
        var total: f32 = 0;
        for (self.units.items) |group| {
            total += group.getTotalDefense();
        }
        // Apply commander bonus
        if (self.commander) |cmd| {
            total *= cmd.getDefenseModifier();
        }
        return total;
    }

    /// Get total supply cost
    pub fn getTotalSupply(self: *const Fleet) u32 {
        var total: u32 = 0;
        for (self.units.items) |group| {
            total += group.getTotalSupply();
        }
        return total;
    }

    /// Get a unit group by class
    pub fn getUnitGroup(self: *Fleet, class: UnitClass) ?*UnitGroup {
        for (self.units.items) |*group| {
            if (group.class == class) {
                return group;
            }
        }
        return null;
    }

    /// Get a unit group by class (const)
    pub fn getUnitGroupConst(self: *const Fleet, class: UnitClass) ?*const UnitGroup {
        for (self.units.items) |*group| {
            if (group.class == class) {
                return group;
            }
        }
        return null;
    }

    /// Check if fleet is destroyed
    pub fn isDestroyed(self: *const Fleet) bool {
        return self.getTotalUnits() == 0;
    }

    /// Check if fleet should retreat (low morale)
    pub fn shouldRetreat(self: *const Fleet) bool {
        const threshold: f32 = 0.3;
        var effective_morale = self.morale;
        if (self.commander) |cmd| {
            effective_morale *= cmd.getMoraleModifier();
        }
        return effective_morale < threshold;
    }
};

/// Configuration for creating a fleet
pub const FleetConfig = struct {
    name: []const u8,
    owner_id: u32,
    position_x: f32 = 0,
    position_y: f32 = 0,
    metadata: u64 = 0,
};

/// Result of a single combat round
pub const RoundResult = struct {
    /// Round number
    round: u32,
    /// Attacker damage dealt
    attacker_damage: f32,
    /// Defender damage dealt
    defender_damage: f32,
    /// Attacker units lost this round
    attacker_losses: u32,
    /// Defender units lost this round
    defender_losses: u32,
    /// Did attacker retreat?
    attacker_retreated: bool,
    /// Did defender retreat?
    defender_retreated: bool,
};

/// Result of a complete battle
pub const BattleResult = struct {
    allocator: std.mem.Allocator,
    /// Attacker fleet ID
    attacker_id: u32,
    /// Defender fleet ID
    defender_id: u32,
    /// Winner (null if draw)
    winner_id: ?u32,
    /// Was this a retreat vs destruction?
    ended_by_retreat: bool,
    /// Total rounds fought
    total_rounds: u32,
    /// Attacker starting units
    attacker_start_units: u32,
    /// Defender starting units
    defender_start_units: u32,
    /// Attacker units lost
    attacker_losses: u32,
    /// Defender units lost
    defender_losses: u32,
    /// Attacker final morale
    attacker_final_morale: f32,
    /// Defender final morale
    defender_final_morale: f32,
    /// Round-by-round results
    rounds: std.ArrayList(RoundResult),
    /// Commander killed? (attacker)
    attacker_commander_killed: bool,
    /// Commander killed? (defender)
    defender_commander_killed: bool,

    pub fn deinit(self: *BattleResult) void {
        self.rounds.deinit();
    }
};

/// Preview of expected battle outcome
pub const BattlePreview = struct {
    /// Expected attacker losses (%)
    attacker_loss_percent: f32,
    /// Expected defender losses (%)
    defender_loss_percent: f32,
    /// Probability attacker wins (0.0 to 1.0)
    attacker_win_probability: f32,
    /// Expected rounds
    expected_rounds: u32,
    /// Is attacker favored?
    attacker_favored: bool,
    /// Power ratio (attacker / defender)
    power_ratio: f32,
    /// Expected attacker surviving units
    expected_attacker_survivors: u32,
    /// Expected defender surviving units
    expected_defender_survivors: u32,
};

/// Combat configuration
pub const CombatConfig = struct {
    /// Maximum rounds before draw
    max_rounds: u32 = 20,
    /// Morale loss per round
    morale_loss_per_round: f32 = 0.05,
    /// Morale loss multiplier when taking heavy casualties
    morale_loss_multiplier: f32 = 2.0,
    /// Threshold for "heavy casualties" (% lost in one round)
    heavy_casualty_threshold: f32 = 0.2,
    /// Retreat morale threshold
    retreat_threshold: f32 = 0.3,
    /// Damage variance (0.2 = +/- 20%)
    damage_variance: f32 = 0.2,
    /// Random seed (0 = random)
    random_seed: u64 = 0,
    /// Experience gain per battle
    experience_gain: f32 = 0.1,
    /// Commander death chance when fleet destroyed
    commander_death_chance: f32 = 0.25,
};

/// The main fleet combat system
pub const FleetCombatSystem = struct {
    allocator: std.mem.Allocator,
    config: CombatConfig,
    fleets: std.AutoHashMap(u32, *Fleet),
    next_fleet_id: u32,
    next_commander_id: u32,
    rng: std.Random,
    name_storage: std.ArrayList([]u8),

    /// Initialize the fleet combat system
    pub fn init(allocator: std.mem.Allocator) FleetCombatSystem {
        return initWithConfig(allocator, .{});
    }

    /// Initialize with custom configuration
    pub fn initWithConfig(allocator: std.mem.Allocator, config: CombatConfig) FleetCombatSystem {
        const seed = if (config.random_seed != 0)
            config.random_seed
        else
            @as(u64, @intCast(std.time.milliTimestamp()));

        var prng = std.rand.DefaultPrng.init(seed);

        return FleetCombatSystem{
            .allocator = allocator,
            .config = config,
            .fleets = std.AutoHashMap(u32, *Fleet).init(allocator),
            .next_fleet_id = 1,
            .next_commander_id = 1,
            .rng = prng.random(),
            .name_storage = std.ArrayList([]u8).init(allocator),
        };
    }

    /// Clean up resources
    pub fn deinit(self: *FleetCombatSystem) void {
        var it = self.fleets.valueIterator();
        while (it.next()) |fleet_ptr| {
            fleet_ptr.*.units.deinit();
            self.allocator.destroy(fleet_ptr.*);
        }
        self.fleets.deinit();

        for (self.name_storage.items) |name| {
            self.allocator.free(name);
        }
        self.name_storage.deinit();
    }

    /// Create a new fleet
    pub fn createFleet(self: *FleetCombatSystem, cfg: FleetConfig) !u32 {
        const id = self.next_fleet_id;
        self.next_fleet_id += 1;

        // Copy name
        const name_copy = try self.allocator.dupe(u8, cfg.name);
        try self.name_storage.append(name_copy);

        // Create fleet
        const fleet = try self.allocator.create(Fleet);
        fleet.* = Fleet{
            .id = id,
            .name = name_copy,
            .owner_id = cfg.owner_id,
            .units = std.ArrayList(UnitGroup).init(self.allocator),
            .position_x = cfg.position_x,
            .position_y = cfg.position_y,
            .metadata = cfg.metadata,
        };

        try self.fleets.put(id, fleet);
        return id;
    }

    /// Get a fleet by ID
    pub fn getFleet(self: *FleetCombatSystem, id: u32) ?*Fleet {
        return self.fleets.get(id);
    }

    /// Get a fleet by ID (const)
    pub fn getFleetConst(self: *const FleetCombatSystem, id: u32) ?*const Fleet {
        if (self.fleets.get(id)) |f| {
            return f;
        }
        return null;
    }

    /// Add units to a fleet
    pub fn addUnits(self: *FleetCombatSystem, fleet_id: u32, class: UnitClass, count: u32) !void {
        const fleet = self.getFleet(fleet_id) orelse return error.InvalidFleet;

        // Check if we already have this unit type
        for (fleet.units.items) |*group| {
            if (group.class == class) {
                group.count += count;
                return;
            }
        }

        // Add new group
        try fleet.units.append(.{
            .class = class,
            .count = count,
        });
    }

    /// Remove units from a fleet
    pub fn removeUnits(self: *FleetCombatSystem, fleet_id: u32, class: UnitClass, count: u32) !u32 {
        const fleet = self.getFleet(fleet_id) orelse return error.InvalidFleet;

        for (fleet.units.items, 0..) |*group, i| {
            if (group.class == class) {
                const removed = @min(group.count, count);
                group.count -= removed;
                if (group.count == 0) {
                    _ = fleet.units.swapRemove(i);
                }
                return removed;
            }
        }
        return 0;
    }

    /// Assign a commander to a fleet
    pub fn assignCommander(self: *FleetCombatSystem, fleet_id: u32, commander: Commander) !void {
        const fleet = self.getFleet(fleet_id) orelse return error.InvalidFleet;

        var cmd = commander;
        cmd.id = self.next_commander_id;
        self.next_commander_id += 1;

        // Copy commander name
        const name_copy = try self.allocator.dupe(u8, commander.name);
        try self.name_storage.append(name_copy);
        cmd.name = name_copy;

        fleet.commander = cmd;
    }

    /// Remove commander from fleet
    pub fn removeCommander(self: *FleetCombatSystem, fleet_id: u32) !?Commander {
        const fleet = self.getFleet(fleet_id) orelse return error.InvalidFleet;
        const cmd = fleet.commander;
        fleet.commander = null;
        return cmd;
    }

    /// Get counter effectiveness between two unit classes
    pub fn getCounterEffectiveness(attacker: UnitClass, defender: UnitClass) f32 {
        // Define counter relationships
        return switch (attacker) {
            // Space units
            .fighter => switch (defender) {
                .bomber => CounterEffectiveness.strong,
                .interceptor => CounterEffectiveness.countered,
                .support => CounterEffectiveness.strong,
                .capital, .dreadnought => CounterEffectiveness.hard_countered,
                else => CounterEffectiveness.neutral,
            },
            .bomber => switch (defender) {
                .capital => CounterEffectiveness.strong,
                .dreadnought => CounterEffectiveness.strong,
                .station => CounterEffectiveness.strong,
                .fighter, .interceptor => CounterEffectiveness.countered,
                else => CounterEffectiveness.neutral,
            },
            .interceptor => switch (defender) {
                .fighter => CounterEffectiveness.strong,
                .bomber => CounterEffectiveness.strong,
                .capital, .dreadnought => CounterEffectiveness.hard_countered,
                else => CounterEffectiveness.neutral,
            },
            .frigate => switch (defender) {
                .fighter => CounterEffectiveness.strong,
                .corvette => CounterEffectiveness.weak,
                .capital, .dreadnought => CounterEffectiveness.countered,
                else => CounterEffectiveness.neutral,
            },
            .corvette => switch (defender) {
                .frigate => CounterEffectiveness.weak,
                .support => CounterEffectiveness.strong,
                .capital, .dreadnought => CounterEffectiveness.countered,
                else => CounterEffectiveness.neutral,
            },
            .capital => switch (defender) {
                .frigate => CounterEffectiveness.strong,
                .corvette => CounterEffectiveness.strong,
                .bomber => CounterEffectiveness.countered,
                .dreadnought => CounterEffectiveness.countered,
                else => CounterEffectiveness.neutral,
            },
            .dreadnought => switch (defender) {
                .capital => CounterEffectiveness.strong,
                .frigate, .corvette => CounterEffectiveness.strong,
                .bomber => CounterEffectiveness.countered,
                .station => CounterEffectiveness.weak,
                else => CounterEffectiveness.neutral,
            },
            .carrier => switch (defender) {
                .fighter, .bomber, .interceptor => CounterEffectiveness.countered,
                else => CounterEffectiveness.neutral,
            },
            .support => CounterEffectiveness.countered, // Support is weak vs everything
            .station => switch (defender) {
                .fighter, .bomber, .corvette => CounterEffectiveness.strong,
                .dreadnought => CounterEffectiveness.countered,
                else => CounterEffectiveness.neutral,
            },
            // Ground units
            .infantry => switch (defender) {
                .militia => CounterEffectiveness.strong,
                .recon => CounterEffectiveness.weak,
                .armor, .mech => CounterEffectiveness.hard_countered,
                else => CounterEffectiveness.neutral,
            },
            .militia => switch (defender) {
                .recon => CounterEffectiveness.weak,
                else => CounterEffectiveness.countered,
            },
            .armor => switch (defender) {
                .infantry, .militia => CounterEffectiveness.strong,
                .fortification => CounterEffectiveness.weak,
                .anti_armor => CounterEffectiveness.hard_countered,
                else => CounterEffectiveness.neutral,
            },
            .anti_armor => switch (defender) {
                .armor => CounterEffectiveness.strong,
                .mech => CounterEffectiveness.strong,
                .infantry => CounterEffectiveness.countered,
                else => CounterEffectiveness.neutral,
            },
            .artillery => switch (defender) {
                .infantry, .militia => CounterEffectiveness.strong,
                .fortification => CounterEffectiveness.strong,
                .armor, .recon => CounterEffectiveness.countered,
                else => CounterEffectiveness.neutral,
            },
            .recon => switch (defender) {
                .artillery => CounterEffectiveness.strong,
                .armor, .mech => CounterEffectiveness.hard_countered,
                else => CounterEffectiveness.countered,
            },
            .mech => switch (defender) {
                .armor => CounterEffectiveness.weak,
                .infantry, .militia => CounterEffectiveness.strong,
                .fortification => CounterEffectiveness.strong,
                .anti_armor => CounterEffectiveness.countered,
                else => CounterEffectiveness.neutral,
            },
            .fortification => switch (defender) {
                .infantry, .militia => CounterEffectiveness.strong,
                .artillery => CounterEffectiveness.hard_countered,
                .mech => CounterEffectiveness.countered,
                else => CounterEffectiveness.neutral,
            },
        };
    }

    /// Calculate damage from one fleet to another
    fn calculateDamage(self: *FleetCombatSystem, attacker: *const Fleet, defender: *const Fleet) f32 {
        var total_damage: f32 = 0;

        // For each attacking unit group
        for (attacker.units.items) |att_group| {
            if (att_group.count == 0) continue;

            var group_damage = att_group.getTotalAttack();

            // Calculate weighted counter effectiveness against all defender units
            var effectiveness: f32 = 0;
            var total_defender_weight: f32 = 0;

            for (defender.units.items) |def_group| {
                if (def_group.count == 0) continue;
                const weight = def_group.getTotalDefense();
                effectiveness += getCounterEffectiveness(att_group.class, def_group.class) * weight;
                total_defender_weight += weight;
            }

            if (total_defender_weight > 0) {
                effectiveness /= total_defender_weight;
            } else {
                effectiveness = 1.0;
            }

            group_damage *= effectiveness;
            total_damage += group_damage;
        }

        // Apply commander bonus
        if (attacker.commander) |cmd| {
            total_damage *= cmd.getAttackModifier();

            // Apply special abilities
            if (cmd.ability) |ability| {
                switch (ability) {
                    .capital_hunter => {
                        // Check if defender has capitals
                        for (defender.units.items) |group| {
                            if (group.class == .capital or group.class == .dreadnought) {
                                total_damage *= 1.2;
                                break;
                            }
                        }
                    },
                    .ace_pilot => {
                        // Boost if we have fighters
                        for (attacker.units.items) |group| {
                            if (group.class == .fighter or group.class == .interceptor) {
                                total_damage *= 1.1;
                                break;
                            }
                        }
                    },
                    else => {},
                }
            }
        }

        // Apply variance
        const variance = self.config.damage_variance;
        const roll = self.rng.float(f32) * 2.0 - 1.0; // -1 to 1
        total_damage *= (1.0 + roll * variance);

        return @max(0, total_damage);
    }

    /// Apply damage to a fleet, returns units lost
    fn applyDamage(self: *FleetCombatSystem, fleet: *Fleet, damage: f32) u32 {
        _ = self;
        var units_lost: u32 = 0;

        // Distribute damage across unit groups proportionally
        const total_defense = fleet.getTotalDefense();
        if (total_defense <= 0) return 0;

        for (fleet.units.items) |*group| {
            if (group.count == 0) continue;

            const group_defense = group.getTotalDefense();
            const damage_share = (group_defense / total_defense) * damage;

            const stats = group.getStats();
            const hp_per_unit = stats.defense * group.health;

            if (hp_per_unit <= 0) continue;

            // Calculate units destroyed
            const units_destroyed_float = damage_share / hp_per_unit;
            const full_units_destroyed = @min(@as(u32, @intFromFloat(units_destroyed_float)), group.count);

            group.count -= full_units_destroyed;
            units_lost += full_units_destroyed;

            // Remaining damage becomes health damage to surviving units
            if (group.count > 0) {
                const leftover = units_destroyed_float - @as(f32, @floatFromInt(full_units_destroyed));
                group.health -= leftover / @as(f32, @floatFromInt(group.count));
                group.health = @max(0, group.health);

                // If health too low, lose another unit
                if (group.health < 0.1 and group.count > 0) {
                    group.count -= 1;
                    units_lost += 1;
                    group.health = 1.0;
                }
            }
        }

        // Clean up eliminated groups
        var i: usize = 0;
        while (i < fleet.units.items.len) {
            if (fleet.units.items[i].count == 0) {
                _ = fleet.units.swapRemove(i);
            } else {
                i += 1;
            }
        }

        return units_lost;
    }

    /// Preview a battle without executing it
    pub fn previewBattle(self: *FleetCombatSystem, attacker_id: u32, defender_id: u32) !BattlePreview {
        const attacker = self.getFleetConst(attacker_id) orelse return error.InvalidFleet;
        const defender = self.getFleetConst(defender_id) orelse return error.InvalidFleet;

        const att_power = attacker.getTotalAttack();
        const def_power = defender.getTotalAttack();
        const att_defense = attacker.getTotalDefense();
        const def_defense = defender.getTotalDefense();

        const att_units = attacker.getTotalUnits();
        const def_units = defender.getTotalUnits();

        if (att_power == 0 and def_power == 0) {
            return BattlePreview{
                .attacker_loss_percent = 0,
                .defender_loss_percent = 0,
                .attacker_win_probability = 0.5,
                .expected_rounds = 0,
                .attacker_favored = false,
                .power_ratio = 1.0,
                .expected_attacker_survivors = att_units,
                .expected_defender_survivors = def_units,
            };
        }

        // Calculate power ratio
        const att_effective = att_power * att_defense;
        const def_effective = def_power * def_defense;
        const power_ratio = if (def_effective > 0) att_effective / def_effective else 10.0;

        // Estimate win probability using Lanchester's laws
        const att_strength = @sqrt(att_effective);
        const def_strength = @sqrt(def_effective);
        const total_strength = att_strength + def_strength;
        const win_prob = if (total_strength > 0) att_strength / total_strength else 0.5;

        // Estimate casualties using simplified combat model
        var att_loss_percent: f32 = 0;
        var def_loss_percent: f32 = 0;

        if (power_ratio > 3.0) {
            // Overwhelming attacker advantage
            att_loss_percent = 0.1;
            def_loss_percent = 0.9;
        } else if (power_ratio > 1.5) {
            // Attacker advantage
            att_loss_percent = 0.25;
            def_loss_percent = 0.6;
        } else if (power_ratio > 0.67) {
            // Roughly even
            att_loss_percent = 0.4;
            def_loss_percent = 0.4;
        } else if (power_ratio > 0.33) {
            // Defender advantage
            att_loss_percent = 0.6;
            def_loss_percent = 0.25;
        } else {
            // Overwhelming defender advantage
            att_loss_percent = 0.9;
            def_loss_percent = 0.1;
        }

        // Estimate rounds
        const avg_damage_per_round = (att_power + def_power) / 2.0;
        const total_hp = att_defense + def_defense;
        const expected_rounds: u32 = if (avg_damage_per_round > 0)
            @min(self.config.max_rounds, @as(u32, @intFromFloat(total_hp / avg_damage_per_round)))
        else
            1;

        return BattlePreview{
            .attacker_loss_percent = att_loss_percent,
            .defender_loss_percent = def_loss_percent,
            .attacker_win_probability = win_prob,
            .expected_rounds = @max(1, expected_rounds),
            .attacker_favored = power_ratio > 1.0,
            .power_ratio = power_ratio,
            .expected_attacker_survivors = @intFromFloat(@as(f32, @floatFromInt(att_units)) * (1.0 - att_loss_percent)),
            .expected_defender_survivors = @intFromFloat(@as(f32, @floatFromInt(def_units)) * (1.0 - def_loss_percent)),
        };
    }

    /// Execute a battle between two fleets
    pub fn resolveBattle(self: *FleetCombatSystem, attacker_id: u32, defender_id: u32) !BattleResult {
        const attacker = self.getFleet(attacker_id) orelse return error.InvalidFleet;
        const defender = self.getFleet(defender_id) orelse return error.InvalidFleet;

        attacker.in_combat = true;
        defender.in_combat = true;

        var result = BattleResult{
            .allocator = self.allocator,
            .attacker_id = attacker_id,
            .defender_id = defender_id,
            .winner_id = null,
            .ended_by_retreat = false,
            .total_rounds = 0,
            .attacker_start_units = attacker.getTotalUnits(),
            .defender_start_units = defender.getTotalUnits(),
            .attacker_losses = 0,
            .defender_losses = 0,
            .attacker_final_morale = attacker.morale,
            .defender_final_morale = defender.morale,
            .rounds = std.ArrayList(RoundResult).init(self.allocator),
            .attacker_commander_killed = false,
            .defender_commander_killed = false,
        };
        errdefer result.deinit();

        // Apply first strike ability if applicable
        var first_strike_applied = false;
        if (attacker.commander) |cmd| {
            if (cmd.ability == .first_strike) {
                first_strike_applied = true;
            }
        }

        // Combat loop
        var round: u32 = 0;
        while (round < self.config.max_rounds) {
            round += 1;

            const att_units_before = attacker.getTotalUnits();
            const def_units_before = defender.getTotalUnits();

            // Calculate damage
            var att_damage = self.calculateDamage(attacker, defender);
            var def_damage = self.calculateDamage(defender, attacker);

            // First strike bonus on round 1
            if (round == 1 and first_strike_applied) {
                att_damage *= 1.25;
            }

            // Last stand bonus
            if (attacker.commander) |cmd| {
                if (cmd.ability == .last_stand and att_units_before < def_units_before) {
                    def_damage *= 0.85; // Take 15% less damage
                }
            }
            if (defender.commander) |cmd| {
                if (cmd.ability == .last_stand and def_units_before < att_units_before) {
                    att_damage *= 0.85;
                }
            }

            // Apply damage
            const def_lost = self.applyDamage(defender, att_damage);
            const att_lost = self.applyDamage(attacker, def_damage);

            result.attacker_losses += att_lost;
            result.defender_losses += def_lost;

            // Update morale
            const att_casualty_rate = if (att_units_before > 0)
                @as(f32, @floatFromInt(att_lost)) / @as(f32, @floatFromInt(att_units_before))
            else
                0;
            const def_casualty_rate = if (def_units_before > 0)
                @as(f32, @floatFromInt(def_lost)) / @as(f32, @floatFromInt(def_units_before))
            else
                0;

            var att_morale_loss = self.config.morale_loss_per_round;
            var def_morale_loss = self.config.morale_loss_per_round;

            if (att_casualty_rate > self.config.heavy_casualty_threshold) {
                att_morale_loss *= self.config.morale_loss_multiplier;
            }
            if (def_casualty_rate > self.config.heavy_casualty_threshold) {
                def_morale_loss *= self.config.morale_loss_multiplier;
            }

            attacker.morale = @max(0, attacker.morale - att_morale_loss);
            defender.morale = @max(0, defender.morale - def_morale_loss);

            // Field repair ability
            if (attacker.commander) |cmd| {
                if (cmd.ability == .field_repair) {
                    for (attacker.units.items) |*group| {
                        group.health = @min(1.0, group.health + 0.1);
                    }
                }
            }
            if (defender.commander) |cmd| {
                if (cmd.ability == .field_repair) {
                    for (defender.units.items) |*group| {
                        group.health = @min(1.0, group.health + 0.1);
                    }
                }
            }

            // Check for retreat
            const att_retreated = attacker.shouldRetreat() and !attacker.isDestroyed();
            const def_retreated = defender.shouldRetreat() and !defender.isDestroyed();

            // Record round
            try result.rounds.append(.{
                .round = round,
                .attacker_damage = att_damage,
                .defender_damage = def_damage,
                .attacker_losses = att_lost,
                .defender_losses = def_lost,
                .attacker_retreated = att_retreated,
                .defender_retreated = def_retreated,
            });

            // Check end conditions
            if (attacker.isDestroyed()) {
                result.winner_id = defender_id;
                // Check commander death
                if (attacker.commander != null) {
                    if (self.rng.float(f32) < self.config.commander_death_chance) {
                        result.attacker_commander_killed = true;
                        attacker.commander = null;
                    }
                }
                break;
            }

            if (defender.isDestroyed()) {
                result.winner_id = attacker_id;
                // Check commander death
                if (defender.commander != null) {
                    if (self.rng.float(f32) < self.config.commander_death_chance) {
                        result.defender_commander_killed = true;
                        defender.commander = null;
                    }
                }
                break;
            }

            if (att_retreated) {
                result.winner_id = defender_id;
                result.ended_by_retreat = true;

                // Tactical retreat reduces losses
                if (attacker.commander) |cmd| {
                    if (cmd.ability == .tactical_retreat) {
                        // Recover some "lost" units
                        const recovery: u32 = @intFromFloat(@as(f32, @floatFromInt(att_lost)) * 0.5);
                        if (attacker.units.items.len > 0) {
                            attacker.units.items[0].count += recovery;
                            result.attacker_losses -= recovery;
                        }
                    }
                }
                break;
            }

            if (def_retreated) {
                result.winner_id = attacker_id;
                result.ended_by_retreat = true;

                // Tactical retreat reduces losses
                if (defender.commander) |cmd| {
                    if (cmd.ability == .tactical_retreat) {
                        const recovery: u32 = @intFromFloat(@as(f32, @floatFromInt(def_lost)) * 0.5);
                        if (defender.units.items.len > 0) {
                            defender.units.items[0].count += recovery;
                            result.defender_losses -= recovery;
                        }
                    }
                }
                break;
            }
        }

        result.total_rounds = round;
        result.attacker_final_morale = attacker.morale;
        result.defender_final_morale = defender.morale;

        // Award experience to survivors
        for (attacker.units.items) |*group| {
            group.experience = @min(1.0, group.experience + self.config.experience_gain);
        }
        for (defender.units.items) |*group| {
            group.experience = @min(1.0, group.experience + self.config.experience_gain);
        }

        // Award experience to commanders
        if (attacker.commander) |*cmd| {
            cmd.experience = @min(1.0, cmd.experience + self.config.experience_gain);
        }
        if (defender.commander) |*cmd| {
            cmd.experience = @min(1.0, cmd.experience + self.config.experience_gain);
        }

        attacker.in_combat = false;
        defender.in_combat = false;

        return result;
    }

    /// Merge two fleets into one (fleet B merged into fleet A)
    pub fn mergeFleets(self: *FleetCombatSystem, fleet_a_id: u32, fleet_b_id: u32) !void {
        const fleet_a = self.getFleet(fleet_a_id) orelse return error.InvalidFleet;
        const fleet_b = self.getFleet(fleet_b_id) orelse return error.InvalidFleet;

        // Merge units
        for (fleet_b.units.items) |group| {
            if (group.count == 0) continue;

            var found = false;
            for (fleet_a.units.items) |*existing| {
                if (existing.class == group.class) {
                    // Weighted average of experience and health
                    const total_a = existing.count;
                    const total_b = group.count;
                    const total = total_a + total_b;
                    if (total > 0) {
                        existing.experience = (existing.experience * @as(f32, @floatFromInt(total_a)) +
                            group.experience * @as(f32, @floatFromInt(total_b))) / @as(f32, @floatFromInt(total));
                        existing.health = (existing.health * @as(f32, @floatFromInt(total_a)) +
                            group.health * @as(f32, @floatFromInt(total_b))) / @as(f32, @floatFromInt(total));
                    }
                    existing.count += group.count;
                    found = true;
                    break;
                }
            }
            if (!found) {
                try fleet_a.units.append(group);
            }
        }

        // If fleet_a has no commander but fleet_b does, transfer
        if (fleet_a.commander == null and fleet_b.commander != null) {
            fleet_a.commander = fleet_b.commander;
        }

        // Remove fleet B
        try self.destroyFleet(fleet_b_id);
    }

    /// Split units from a fleet into a new fleet
    pub fn splitFleet(self: *FleetCombatSystem, source_id: u32, name: []const u8, units_to_split: []const struct { class: UnitClass, count: u32 }) !u32 {
        const source = self.getFleet(source_id) orelse return error.InvalidFleet;

        // Create new fleet
        const new_id = try self.createFleet(.{
            .name = name,
            .owner_id = source.owner_id,
            .position_x = source.position_x,
            .position_y = source.position_y,
        });

        const new_fleet = self.getFleet(new_id).?;

        // Transfer units
        for (units_to_split) |split_info| {
            for (source.units.items) |*group| {
                if (group.class == split_info.class) {
                    const transfer_count = @min(group.count, split_info.count);
                    if (transfer_count > 0) {
                        try new_fleet.units.append(.{
                            .class = group.class,
                            .count = transfer_count,
                            .health = group.health,
                            .experience = group.experience,
                        });
                        group.count -= transfer_count;
                    }
                    break;
                }
            }
        }

        // Clean up empty groups in source
        var i: usize = 0;
        while (i < source.units.items.len) {
            if (source.units.items[i].count == 0) {
                _ = source.units.swapRemove(i);
            } else {
                i += 1;
            }
        }

        return new_id;
    }

    /// Destroy a fleet (remove from system)
    pub fn destroyFleet(self: *FleetCombatSystem, fleet_id: u32) !void {
        if (self.fleets.fetchRemove(fleet_id)) |entry| {
            entry.value.units.deinit();
            self.allocator.destroy(entry.value);
        }
    }

    /// Get all fleets for a player
    pub fn getPlayerFleets(self: *FleetCombatSystem, player_id: u32, out_buffer: []u32) usize {
        var count: usize = 0;
        var it = self.fleets.valueIterator();
        while (it.next()) |fleet_ptr| {
            if (count >= out_buffer.len) break;
            if (fleet_ptr.*.owner_id == player_id) {
                out_buffer[count] = fleet_ptr.*.id;
                count += 1;
            }
        }
        return count;
    }

    /// Get total fleet count
    pub fn getFleetCount(self: *const FleetCombatSystem) usize {
        return self.fleets.count();
    }

    /// Repair a fleet (restore health)
    pub fn repairFleet(self: *FleetCombatSystem, fleet_id: u32, repair_amount: f32) !void {
        const fleet = self.getFleet(fleet_id) orelse return error.InvalidFleet;
        for (fleet.units.items) |*group| {
            group.health = @min(1.0, group.health + repair_amount);
        }
    }

    /// Restore morale to a fleet
    pub fn restoreMorale(self: *FleetCombatSystem, fleet_id: u32, amount: f32) !void {
        const fleet = self.getFleet(fleet_id) orelse return error.InvalidFleet;
        fleet.morale = @min(1.0, fleet.morale + amount);
    }

    /// Reinforce a fleet (add units, costs resources)
    pub fn reinforceFleet(self: *FleetCombatSystem, fleet_id: u32, class: UnitClass, count: u32) !void {
        try self.addUnits(fleet_id, class, count);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "UnitStats - default stats" {
    const fighter_stats = UnitStats.getDefault(.fighter);
    try std.testing.expectEqual(@as(f32, 5), fighter_stats.attack);
    try std.testing.expectEqual(@as(f32, 3), fighter_stats.defense);
    try std.testing.expect(fighter_stats.can_retreat);

    const station_stats = UnitStats.getDefault(.station);
    try std.testing.expect(station_stats.is_structure);
    try std.testing.expect(!station_stats.can_retreat);
}

test "UnitGroup - basic operations" {
    var group = UnitGroup{
        .class = .fighter,
        .count = 100,
        .health = 1.0,
        .experience = 0.5, // 50% experienced
    };

    const attack = group.getTotalAttack();
    // 5 (base) * 100 (count) * 1.0 (health) * 1.25 (exp bonus) = 625
    try std.testing.expectEqual(@as(f32, 625), attack);

    try std.testing.expect(!group.isEliminated());
    group.count = 0;
    try std.testing.expect(group.isEliminated());
}

test "Commander - modifiers" {
    const cmd = Commander{
        .name = "Admiral Test",
        .attack_bonus = 0.15,
        .defense_bonus = 0.10,
        .experience = 0.5,
    };

    // Attack: 1.0 + 0.15 + (0.5 * 0.1) = 1.2
    try std.testing.expectApproxEqAbs(@as(f32, 1.2), cmd.getAttackModifier(), 0.001);
    // Defense: 1.0 + 0.10 + (0.5 * 0.05) = 1.125
    try std.testing.expectApproxEqAbs(@as(f32, 1.125), cmd.getDefenseModifier(), 0.001);
}

test "FleetCombatSystem - init and deinit" {
    var system = FleetCombatSystem.init(std.testing.allocator);
    defer system.deinit();

    try std.testing.expectEqual(@as(usize, 0), system.getFleetCount());
}

test "FleetCombatSystem - create fleet" {
    var system = FleetCombatSystem.init(std.testing.allocator);
    defer system.deinit();

    const id = try system.createFleet(.{
        .name = "Alpha Fleet",
        .owner_id = 1,
        .position_x = 100,
        .position_y = 200,
    });

    const fleet = system.getFleet(id);
    try std.testing.expect(fleet != null);
    try std.testing.expectEqualStrings("Alpha Fleet", fleet.?.name);
    try std.testing.expectEqual(@as(u32, 1), fleet.?.owner_id);
}

test "FleetCombatSystem - add and remove units" {
    var system = FleetCombatSystem.init(std.testing.allocator);
    defer system.deinit();

    const id = try system.createFleet(.{ .name = "Test", .owner_id = 0 });
    try system.addUnits(id, .fighter, 50);
    try system.addUnits(id, .fighter, 30); // Should merge
    try system.addUnits(id, .bomber, 20);

    const fleet = system.getFleet(id).?;
    try std.testing.expectEqual(@as(u32, 100), fleet.getTotalUnits());

    const removed = try system.removeUnits(id, .fighter, 40);
    try std.testing.expectEqual(@as(u32, 40), removed);
    try std.testing.expectEqual(@as(u32, 60), fleet.getTotalUnits());
}

test "FleetCombatSystem - assign commander" {
    var system = FleetCombatSystem.init(std.testing.allocator);
    defer system.deinit();

    const id = try system.createFleet(.{ .name = "Test", .owner_id = 0 });
    try system.assignCommander(id, .{
        .name = "Admiral Chen",
        .attack_bonus = 0.20,
    });

    const fleet = system.getFleet(id).?;
    try std.testing.expect(fleet.commander != null);
    try std.testing.expectEqualStrings("Admiral Chen", fleet.commander.?.name);
}

test "FleetCombatSystem - counter effectiveness" {
    // Fighters are strong against bombers
    try std.testing.expectEqual(CounterEffectiveness.strong, FleetCombatSystem.getCounterEffectiveness(.fighter, .bomber));

    // Bombers are strong against capitals
    try std.testing.expectEqual(CounterEffectiveness.strong, FleetCombatSystem.getCounterEffectiveness(.bomber, .capital));

    // Fighters are hard countered by capitals
    try std.testing.expectEqual(CounterEffectiveness.hard_countered, FleetCombatSystem.getCounterEffectiveness(.fighter, .capital));

    // Interceptors counter fighters
    try std.testing.expectEqual(CounterEffectiveness.strong, FleetCombatSystem.getCounterEffectiveness(.interceptor, .fighter));
}

test "FleetCombatSystem - preview battle" {
    var system = FleetCombatSystem.init(std.testing.allocator);
    defer system.deinit();

    const attacker = try system.createFleet(.{ .name = "Attacker", .owner_id = 0 });
    try system.addUnits(attacker, .fighter, 100);
    try system.addUnits(attacker, .capital, 5);

    const defender = try system.createFleet(.{ .name = "Defender", .owner_id = 1 });
    try system.addUnits(defender, .fighter, 50);

    const preview = try system.previewBattle(attacker, defender);
    try std.testing.expect(preview.attacker_favored);
    try std.testing.expect(preview.power_ratio > 1.0);
    try std.testing.expect(preview.attacker_win_probability > 0.5);
}

test "FleetCombatSystem - resolve battle" {
    var system = FleetCombatSystem.initWithConfig(std.testing.allocator, .{
        .random_seed = 12345, // Deterministic for testing
        .max_rounds = 10,
    });
    defer system.deinit();

    const attacker = try system.createFleet(.{ .name = "Attacker", .owner_id = 0 });
    try system.addUnits(attacker, .fighter, 100);
    try system.addUnits(attacker, .capital, 10);

    const defender = try system.createFleet(.{ .name = "Defender", .owner_id = 1 });
    try system.addUnits(defender, .fighter, 20);

    var result = try system.resolveBattle(attacker, defender);
    defer result.deinit();

    try std.testing.expect(result.winner_id != null);
    try std.testing.expect(result.total_rounds > 0);
    try std.testing.expect(result.rounds.items.len > 0);
}

test "FleetCombatSystem - merge fleets" {
    var system = FleetCombatSystem.init(std.testing.allocator);
    defer system.deinit();

    const fleet_a = try system.createFleet(.{ .name = "Fleet A", .owner_id = 0 });
    try system.addUnits(fleet_a, .fighter, 50);

    const fleet_b = try system.createFleet(.{ .name = "Fleet B", .owner_id = 0 });
    try system.addUnits(fleet_b, .fighter, 30);
    try system.addUnits(fleet_b, .bomber, 10);

    try std.testing.expectEqual(@as(usize, 2), system.getFleetCount());

    try system.mergeFleets(fleet_a, fleet_b);

    try std.testing.expectEqual(@as(usize, 1), system.getFleetCount());

    const merged = system.getFleet(fleet_a).?;
    try std.testing.expectEqual(@as(u32, 90), merged.getTotalUnits()); // 50 + 30 + 10
}

test "FleetCombatSystem - split fleet" {
    var system = FleetCombatSystem.init(std.testing.allocator);
    defer system.deinit();

    const original = try system.createFleet(.{ .name = "Original", .owner_id = 0 });
    try system.addUnits(original, .fighter, 100);
    try system.addUnits(original, .bomber, 50);

    const split = [_]struct { class: UnitClass, count: u32 }{
        .{ .class = .fighter, .count = 30 },
        .{ .class = .bomber, .count = 20 },
    };

    const new_id = try system.splitFleet(original, "Detachment", &split);

    const orig_fleet = system.getFleet(original).?;
    const new_fleet = system.getFleet(new_id).?;

    try std.testing.expectEqual(@as(u32, 100), orig_fleet.getTotalUnits()); // 70 + 30
    try std.testing.expectEqual(@as(u32, 50), new_fleet.getTotalUnits()); // 30 + 20
}

test "FleetCombatSystem - retreat mechanics" {
    var system = FleetCombatSystem.initWithConfig(std.testing.allocator, .{
        .retreat_threshold = 0.3,
    });
    defer system.deinit();

    const id = try system.createFleet(.{ .name = "Test", .owner_id = 0 });
    try system.addUnits(id, .fighter, 50);

    const fleet = system.getFleet(id).?;
    fleet.morale = 1.0;
    try std.testing.expect(!fleet.shouldRetreat());

    fleet.morale = 0.2;
    try std.testing.expect(fleet.shouldRetreat());
}

test "FleetCombatSystem - commander abilities" {
    var system = FleetCombatSystem.init(std.testing.allocator);
    defer system.deinit();

    const id = try system.createFleet(.{ .name = "Test", .owner_id = 0 });
    try system.assignCommander(id, .{
        .name = "Ace Commander",
        .attack_bonus = 0.1,
        .ability = .ace_pilot,
    });

    const fleet = system.getFleet(id).?;
    try std.testing.expect(fleet.commander.?.ability == .ace_pilot);
}

test "FleetCombatSystem - repair and morale" {
    var system = FleetCombatSystem.init(std.testing.allocator);
    defer system.deinit();

    const id = try system.createFleet(.{ .name = "Test", .owner_id = 0 });
    try system.addUnits(id, .fighter, 50);

    const fleet = system.getFleet(id).?;
    fleet.units.items[0].health = 0.5;
    fleet.morale = 0.4;

    try system.repairFleet(id, 0.3);
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), fleet.units.items[0].health, 0.001);

    try system.restoreMorale(id, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.9), fleet.morale, 0.001);
}

test "FleetCombatSystem - get player fleets" {
    var system = FleetCombatSystem.init(std.testing.allocator);
    defer system.deinit();

    _ = try system.createFleet(.{ .name = "P1 Fleet 1", .owner_id = 1 });
    _ = try system.createFleet(.{ .name = "P1 Fleet 2", .owner_id = 1 });
    _ = try system.createFleet(.{ .name = "P2 Fleet 1", .owner_id = 2 });

    var buffer: [10]u32 = undefined;
    const p1_count = system.getPlayerFleets(1, &buffer);
    try std.testing.expectEqual(@as(usize, 2), p1_count);

    const p2_count = system.getPlayerFleets(2, &buffer);
    try std.testing.expectEqual(@as(usize, 1), p2_count);
}

test "FleetCombatSystem - destroy fleet" {
    var system = FleetCombatSystem.init(std.testing.allocator);
    defer system.deinit();

    const id = try system.createFleet(.{ .name = "Test", .owner_id = 0 });
    try std.testing.expectEqual(@as(usize, 1), system.getFleetCount());

    try system.destroyFleet(id);
    try std.testing.expectEqual(@as(usize, 0), system.getFleetCount());
}

test "Fleet - total calculations with commander" {
    var system = FleetCombatSystem.init(std.testing.allocator);
    defer system.deinit();

    const id = try system.createFleet(.{ .name = "Test", .owner_id = 0 });
    try system.addUnits(id, .fighter, 100);
    try system.assignCommander(id, .{
        .name = "Commander",
        .attack_bonus = 0.20, // +20%
    });

    const fleet = system.getFleet(id).?;

    // Base attack: 5 * 100 = 500
    // With commander: 500 * 1.2 = 600
    const total_attack = fleet.getTotalAttack();
    try std.testing.expectApproxEqAbs(@as(f32, 600), total_attack, 0.001);
}

test "BattleResult - round tracking" {
    var system = FleetCombatSystem.initWithConfig(std.testing.allocator, .{
        .random_seed = 42,
        .max_rounds = 5,
    });
    defer system.deinit();

    const attacker = try system.createFleet(.{ .name = "Attacker", .owner_id = 0 });
    try system.addUnits(attacker, .capital, 10);

    const defender = try system.createFleet(.{ .name = "Defender", .owner_id = 1 });
    try system.addUnits(defender, .capital, 10);

    var result = try system.resolveBattle(attacker, defender);
    defer result.deinit();

    // Should have at least one round
    try std.testing.expect(result.rounds.items.len > 0);

    // Each round should have damage recorded
    for (result.rounds.items) |round| {
        try std.testing.expect(round.attacker_damage >= 0);
        try std.testing.expect(round.defender_damage >= 0);
    }
}

test "UnitGroup - supply calculation" {
    const group = UnitGroup{
        .class = .capital, // Supply: 10 per unit
        .count = 5,
    };

    try std.testing.expectEqual(@as(u32, 50), group.getTotalSupply());
}

test "Fleet - supply total" {
    var system = FleetCombatSystem.init(std.testing.allocator);
    defer system.deinit();

    const id = try system.createFleet(.{ .name = "Test", .owner_id = 0 });
    try system.addUnits(id, .fighter, 10); // 1 supply each = 10
    try system.addUnits(id, .capital, 2); // 10 supply each = 20

    const fleet = system.getFleet(id).?;
    try std.testing.expectEqual(@as(u32, 30), fleet.getTotalSupply());
}
