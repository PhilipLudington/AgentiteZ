# Turn-Based Combat System

**File:** `src/combat.zig`

A tactical turn-based combat system with perfect information via telegraphing. Features initiative-based turn order, reaction mechanics, and status effects.

## Features

- **Initiative System** - Static turn order per encounter, higher initiative acts first
- **Telegraphing** - Enemy intents shown before player commits actions
- **Reaction Mechanics** - Dodge and counter based on initiative (can only react before acting)
- **Status Effects** - 14 status types with duration tracking and DoT support
- **Damage Calculation** - Armor, piercing, temp HP, and modifier-based damage
- **Unstoppable Attacks** - Attacks that cannot be dodged or reacted to
- **Team System** - Player, enemy, ally, and neutral teams
- **Action Queue** - Queue actions during planning phase, execute in initiative order

## Quick Start

```zig
const combat = @import("AgentiteZ").combat;

// Create combat system
var battle = combat.CombatSystem.init(allocator);
defer battle.deinit();

// Add player combatant
const player = try battle.addCombatant(.{
    .name = "Scout",
    .team = .player,
    .max_hp = 4,
    .initiative = 8,
    .movement = 4,
    .dodge_chance = 0.10,
    .base_attack = .{ .damage = 2, .range = 4 },
});

// Add enemy combatant
const enemy = try battle.addCombatant(.{
    .name = "Raider",
    .team = .enemy,
    .max_hp = 4,
    .initiative = 6,
    .movement = 3,
    .base_attack = .{ .damage = 2, .range = 1 },
});

// Start combat
try battle.startCombat();

// Begin turn (generates enemy telegraphs)
try battle.beginTurn();

// View enemy intents
const telegraphs = battle.getTelegraphs();
for (telegraphs) |telegraph| {
    std.debug.print("Enemy will deal {} damage\n", .{telegraph.damage});
}

// Enter planning phase
battle.enterPlanningPhase();

// Queue player action
try battle.queueAction(player, .{
    .combatant_id = player,
    .action_type = .attack,
    .target_id = enemy,
});

// Execute turn
var result = try battle.executeTurn();
defer result.deinit();

if (result.combat_ended) {
    std.debug.print("Victory: {}\n", .{result.winning_team});
}
```

## Core Types

### Team

```zig
pub const Team = enum {
    player,   // Player-controlled units
    enemy,    // AI-controlled enemies
    neutral,  // Non-combatants
    ally,     // AI-controlled friendlies
};
```

### ActionType

```zig
pub const ActionType = enum {
    move,      // Move to a position
    attack,    // Attack a target
    defend,    // Increase dodge and reduce damage
    use_item,  // Use an inventory item
    ability,   // Use a special ability
    wait,      // Skip turn
    flee,      // Attempt to flee combat
};
```

### StatusType

```zig
pub const StatusType = enum {
    stunned,      // Cannot act
    burning,      // Damage over time
    poisoned,     // Damage over time (weaker)
    bleeding,     // Damage over time (strong)
    rooted,       // Cannot move
    blinded,      // Reduced hit chance
    vulnerable,   // Increased damage taken (+50%)
    fortified,    // Reduced damage taken (-25%)
    hasted,       // Increased initiative (+3)
    slowed,       // Decreased initiative (-3)
    invulnerable, // Immune to damage
    concealed,    // Hidden from targeting (+25% dodge)
    injured,      // Generic injury debuff
};
```

### Position

```zig
pub const Position = struct {
    x: i32,
    y: i32,

    pub fn init(x: i32, y: i32) Position;
    pub fn distance(self: Position, other: Position) i32;      // Chebyshev distance
    pub fn manhattanDistance(self: Position, other: Position) i32;
    pub fn eql(self: Position, other: Position) bool;
};
```

### AttackProperties

```zig
pub const AttackProperties = struct {
    damage: i32 = 1,           // Base damage
    range: i32 = 1,            // Range in grid units (1 = melee)
    hit_chance: f32 = 1.0,     // Hit chance (0.0 to 1.0)
    unstoppable: bool = false, // Cannot be dodged
    piercing: bool = false,    // Ignores armor
    aoe_radius: i32 = 0,       // Area of effect (0 = single target)
    applies_status: ?StatusType = null, // Status to apply on hit
    status_duration: u32 = 1,  // Duration of applied status
};
```

### Combatant

```zig
pub const Combatant = struct {
    id: u32,
    name: []const u8,
    team: Team,
    current_hp: i32,
    max_hp: i32,
    temp_hp: i32,              // Absorbed first before HP
    initiative: i32,
    base_initiative: i32,
    movement: i32,
    position: Position,
    dodge_chance: f32,
    base_attack: AttackProperties,
    armor: i32,
    counter_damage: i32,       // Damage dealt on counter (0 = no counter)
    is_defending: bool,
    has_acted: bool,
    is_alive: bool,

    // Methods
    pub fn canReact(self: *const Combatant) bool;
    pub fn hasStatus(self: *const Combatant, status_type: StatusType) bool;
    pub fn getEffectiveDodge(self: *const Combatant) f32;
    pub fn getEffectiveInitiative(self: *const Combatant) i32;
    pub fn takeDamage(self: *Combatant, raw_damage: i32, piercing: bool) i32;
    pub fn heal(self: *Combatant, amount: i32) i32;
    pub fn addTempHp(self: *Combatant, amount: i32) void;
};
```

### Telegraph

```zig
pub const Telegraph = struct {
    source_id: u32,              // Combatant performing action
    action_type: ActionType,
    target_ids: std.ArrayList(u32),
    target_position: ?Position,
    damage: i32,                 // Damage that will be dealt
    hit_chance: f32,
    unstoppable: bool,
    applies_status: ?StatusType,
    ability_name: ?[]const u8,
};
```

## CombatSystem API

### Initialization

```zig
// Default initialization
var combat = CombatSystem.init(allocator);
defer combat.deinit();

// With custom configuration
var combat = CombatSystem.initWithConfig(allocator, .{
    .max_combatants = 32,
    .enable_reactions = true,
    .default_defend_reduction = 1,
    .default_defend_dodge = 0.25,
    .max_dodge_chance = 0.75,
    .turn_limit = 0,       // 0 = unlimited
    .random_seed = 12345,  // 0 = random
});
```

### Combatant Management

```zig
// Add a combatant
const id = try combat.addCombatant(.{
    .name = "Scout",
    .team = .player,
    .max_hp = 4,
    .initiative = 8,
    .movement = 4,
    .position = Position.init(0, 0),
    .dodge_chance = 0.10,
    .base_attack = .{ .damage = 2, .range = 4 },
    .armor = 0,
    .counter_damage = 0,
    .inventory_slots = 3,
});

// Get combatant
if (combat.getCombatant(id)) |combatant| {
    std.debug.print("HP: {}/{}\n", .{combatant.current_hp, combatant.max_hp});
}

// Add ability to combatant
try combat.addAbility(id, .{
    .id = "quick_strike",
    .name = "Quick Strike",
    .cooldown = 2,
    .attack = .{ .damage = 3, .range = 1 },
});

// Get combatants by team
var buffer: [10]u32 = undefined;
const count = combat.getCombatantsByTeam(.player, &buffer);

// Get all living combatants
const living = combat.getLivingCombatants(&buffer);
```

### Combat Flow

```zig
// 1. Start combat (calculates turn order)
try combat.startCombat();

// Combat loop
while (combat.isActive()) {
    // 2. Begin turn (generates telegraphs, resets combatant state)
    try combat.beginTurn();

    // 3. View enemy intents
    const telegraphs = combat.getTelegraphs();
    // ... display to player ...

    // 4. Enter planning phase
    combat.enterPlanningPhase();

    // 5. Queue player actions
    try combat.queueAction(player_id, .{
        .combatant_id = player_id,
        .action_type = .attack,
        .target_id = enemy_id,
    });

    // 6. Execute turn (resolves in initiative order)
    var result = try combat.executeTurn();
    defer result.deinit();

    // 7. Check results
    if (result.combat_ended) {
        break;
    }
}
```

### Actions

```zig
// Move action
try combat.queueAction(id, .{
    .combatant_id = id,
    .action_type = .move,
    .target_position = Position.init(5, 3),
});

// Attack action
try combat.queueAction(id, .{
    .combatant_id = id,
    .action_type = .attack,
    .target_id = enemy_id,
});

// Attack with custom properties
try combat.queueAction(id, .{
    .combatant_id = id,
    .action_type = .attack,
    .target_id = enemy_id,
    .attack_override = .{
        .damage = 5,
        .range = 1,
        .unstoppable = true,
    },
});

// Defend action
try combat.queueAction(id, .{
    .combatant_id = id,
    .action_type = .defend,
});

// Use ability
try combat.queueAction(id, .{
    .combatant_id = id,
    .action_type = .ability,
    .ability_id = "quick_strike",
    .target_id = enemy_id,
});
```

### Status Effects

```zig
// Apply status effect
try combat.applyStatus(target_id, .stunned, 2, source_id);

// Check if combatant has status
const combatant = combat.getCombatant(id).?;
if (combatant.hasStatus(.poisoned)) {
    // Handle poisoned state
}
```

### Queries

```zig
// Get current phase
const phase = combat.getPhase();

// Get current turn
const turn = combat.getCurrentTurn();

// Get turn order (sorted by initiative)
const order = combat.getTurnOrder();

// Check if combat is active
if (combat.isActive()) {
    // Still fighting
}

// Get combat statistics
const stats = combat.getStats();
std.debug.print("Total damage: {}\n", .{stats.total_damage_dealt});
```

## Combat Phases

```zig
pub const CombatPhase = enum {
    inactive,   // Not in combat
    setup,      // Combat starting
    telegraph,  // Showing enemy intents
    planning,   // Player queuing actions
    execution,  // Executing actions in order
    cleanup,    // Processing status effects
    ended,      // Combat finished
};
```

## Initiative and Reactions

The initiative system determines turn order and reaction availability:

1. **Turn Order**: Combatants act in descending initiative order
2. **Tie Breaking**: Player team acts first on initiative ties
3. **Reactions**: A combatant can only dodge/counter attacks from combatants who act AFTER them

```
Turn Order:
[10] Ambusher (enemy)    <- Acts first, cannot react to anyone
[ 8] Scout (player)      <- Can react to Raider, Brawler
[ 6] Raider (enemy)      <- Can react to Brawler only
[ 4] Brawler (player)    <- Can react to all (acts last)
```

### Reaction Mechanics

```zig
// Combatant can react if:
// 1. They haven't acted yet this turn
// 2. They are alive
// 3. They are not stunned
pub fn canReact(self: *const Combatant) bool {
    return !self.has_acted and self.is_alive and !self.hasStatus(.stunned);
}
```

### Effective Dodge Calculation

```zig
pub fn getEffectiveDodge(self: *const Combatant) f32 {
    var dodge = self.dodge_chance;

    // Defending bonus (+25% by default)
    if (self.is_defending) {
        dodge += self.defend_dodge_bonus;
    }

    // Status effects
    if (self.hasStatus(.blinded)) dodge -= 0.30;
    if (self.hasStatus(.concealed)) dodge += 0.25;

    // Capped at 75% maximum
    return @max(0.0, @min(0.75, dodge));
}
```

## Damage Calculation

Damage is calculated as follows:

1. Start with raw damage
2. Subtract armor (unless piercing)
3. Subtract defend bonus (if defending and not piercing)
4. Apply vulnerable modifier (+50%)
5. Apply fortified modifier (-25%)
6. Minimum 0 damage after modifiers
7. Absorb with temp HP first
8. Apply remaining to current HP

```zig
pub fn takeDamage(self: *Combatant, raw_damage: i32, piercing: bool) i32 {
    if (self.hasStatus(.invulnerable)) return 0;

    var damage = raw_damage;

    // Armor (if not piercing)
    if (!piercing) {
        damage -= self.armor;
        if (self.is_defending) {
            damage -= self.defend_damage_reduction;
        }
    }

    // Status modifiers
    if (self.hasStatus(.vulnerable)) {
        damage = @intFromFloat(@floatFromInt(damage) * 1.5);
    }
    if (self.hasStatus(.fortified)) {
        damage = @intFromFloat(@floatFromInt(damage) * 0.75);
    }

    damage = @max(0, damage);

    // Temp HP first
    if (self.temp_hp > 0) {
        const absorbed = @min(self.temp_hp, damage);
        self.temp_hp -= absorbed;
        damage -= absorbed;
    }

    // Apply to HP
    self.current_hp -= damage;
    // ...
}
```

## Configuration

```zig
pub const CombatConfig = struct {
    max_combatants: u32 = 32,
    enable_reactions: bool = true,         // Enable dodge/counter
    default_defend_reduction: i32 = 1,     // Damage reduction when defending
    default_defend_dodge: f32 = 0.25,      // Dodge bonus when defending
    max_dodge_chance: f32 = 0.75,          // Maximum dodge cap
    turn_limit: u32 = 0,                   // 0 = unlimited
    random_seed: u64 = 0,                  // 0 = random seed
};
```

## Combat Statistics

```zig
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

// Access stats
const stats = combat.getStats();
```

## Example: Full Combat Loop

```zig
const std = @import("std");
const combat = @import("AgentiteZ").combat;

pub fn runCombat(allocator: std.mem.Allocator) !void {
    var battle = combat.CombatSystem.init(allocator);
    defer battle.deinit();

    // Setup combatants
    const scout = try battle.addCombatant(.{
        .name = "Scout",
        .team = .player,
        .max_hp = 4,
        .initiative = 8,
        .movement = 4,
        .position = combat.Position.init(0, 3),
        .dodge_chance = 0.10,
        .base_attack = .{ .damage = 2, .range = 4 },
    });

    const brawler = try battle.addCombatant(.{
        .name = "Brawler",
        .team = .player,
        .max_hp = 6,
        .initiative = 4,
        .movement = 3,
        .position = combat.Position.init(1, 3),
        .counter_damage = 1, // Counter-attacks melee
        .armor = 1,
        .base_attack = .{ .damage = 2, .range = 1 },
    });

    const raider = try battle.addCombatant(.{
        .name = "Raider",
        .team = .enemy,
        .max_hp = 4,
        .initiative = 6,
        .movement = 3,
        .position = combat.Position.init(2, 0),
        .base_attack = .{ .damage = 2, .range = 1 },
    });

    // Start combat
    try battle.startCombat();

    var turn: u32 = 0;
    while (battle.isActive() and turn < 10) {
        turn += 1;
        std.debug.print("\n=== Turn {} ===\n", .{turn});

        // Begin turn
        try battle.beginTurn();

        // Show telegraphs
        const telegraphs = battle.getTelegraphs();
        for (telegraphs) |t| {
            std.debug.print("Enemy will deal {} damage\n", .{t.damage});
        }

        // Planning phase
        battle.enterPlanningPhase();

        // Queue player actions based on situation
        const scout_c = battle.getCombatant(scout).?;
        const raider_c = battle.getCombatant(raider).?;

        if (raider_c.is_alive) {
            // Scout attacks from range
            try battle.queueAction(scout, .{
                .combatant_id = scout,
                .action_type = .attack,
                .target_id = raider,
            });

            // Brawler moves toward enemy or attacks if close
            if (brawler.position.distance(raider_c.position) <= 1) {
                try battle.queueAction(brawler, .{
                    .combatant_id = brawler,
                    .action_type = .attack,
                    .target_id = raider,
                });
            } else {
                try battle.queueAction(brawler, .{
                    .combatant_id = brawler,
                    .action_type = .move,
                    .target_position = raider_c.position,
                });
            }
        }

        // Execute turn
        var result = try battle.executeTurn();
        defer result.deinit();

        // Report results
        for (result.action_results.items) |ar| {
            if (ar.damage_dealt > 0) {
                std.debug.print("Dealt {} damage\n", .{ar.damage_dealt});
            }
            if (ar.was_dodged) {
                std.debug.print("Attack was dodged!\n", .{});
            }
        }

        if (result.combat_ended) {
            std.debug.print("\nCombat ended! Winner: {}\n", .{result.winning_team});
            break;
        }
    }
}
```

## Tests

The combat system includes 20+ comprehensive tests covering:
- Position calculations
- Combatant creation and damage
- HP, temp HP, and healing
- Status effects and reactions
- Initiative ordering
- Turn execution
- Victory conditions
- Telegraph generation
- Defend mechanics
- Statistics tracking
