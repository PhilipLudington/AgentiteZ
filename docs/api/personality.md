# AI Personality System

Trait-weighted decision scoring for AI agents (`src/personality.zig`).

## Features

- **8 personality templates** - Balanced, Aggressive, Defensive, Economic, Expansionist, Technologist, Diplomatic, Opportunist
- **8 trait weights** - aggression, defense, expansion, economy, technology, diplomacy, caution, opportunism
- **Situational modifiers** - Adjust scores based on threat, resources, military, morale
- **Threat management** - Track, age, and prioritize threats
- **Goal tracking** - Add, progress, complete, and cleanup goals
- **Action cooldowns** - Prevent action spam
- **Random number generation** - Seeded PRNG for deterministic AI

## Usage

### Basic Scoring

```zig
const personality = @import("AgentiteZ").personality;

var state = personality.AIState.init(.aggressive);

// Set situational context
state.setRatios(0.8, 1.2, 0.9); // resources, military, tech ratios (own/enemy)
state.setMorale(0.85);

// Score potential actions
const attack_score = state.scoreAction(.attack, 100.0);
const defend_score = state.scoreAction(.defend, 100.0);
const expand_score = state.scoreAction(.expand, 100.0);

// Aggressive personality will favor attack
// Military advantage (1.2) boosts attack further
// High morale (0.85) provides additional attack bonus
```

### Threat Management

```zig
// Add threats (source_id, level, target_id, distance)
state.addThreat(enemy_1, 0.8, my_base, 50.0);
state.addThreat(enemy_2, 0.5, outpost, 100.0);

// Get overall threat level (0-1)
const threat = state.overall_threat;

// Get highest priority threat
if (state.getHighestThreat()) |threat| {
    state.setPrimaryTarget(threat.source_id);
}

// Update threats each turn (ages them, reduces relevance)
state.updateThreats();

// Remove threat when eliminated
_ = state.removeThreat(enemy_1);
```

### Goal Management

```zig
// Add goals (type, target, priority)
const idx = state.addGoal(GOAL_CAPTURE, enemy_base, 0.9).?;

// Update progress
state.updateGoalProgress(idx, 0.5); // 50% complete

// Complete goal
state.completeGoal(idx);

// Get primary goal
if (state.getPrimaryGoal()) |goal| {
    // Focus on highest priority incomplete goal
}

// Cleanup completed and stale goals
state.cleanupGoals(10); // Remove goals older than 10 turns
```

### Cooldowns

```zig
// Set cooldown after action
state.setCooldown(.attack, 3); // Can't attack for 3 turns

// Check before scoring
if (state.isOnCooldown(.attack)) {
    // Skip attack scoring
}

// Automatic cooldown check in scoreAction
const score = state.scoreAction(.attack, 100.0); // Returns 0 if on cooldown

// Update cooldowns each turn
state.updateCooldowns();
```

### AI System with Evaluators

```zig
var system = personality.AISystem.init(allocator);
defer system.deinit();

// Register action evaluators
system.registerEvaluator(.attack, struct {
    fn eval(state: *personality.AIState, game_ctx: ?*anyopaque, out_actions: []personality.Action) usize {
        const game: *Game = @ptrCast(@alignCast(game_ctx.?));

        var count: usize = 0;
        for (game.getEnemies()) |enemy| {
            if (count >= out_actions.len) break;
            out_actions[count] = .{
                .action_type = .attack,
                .target_id = enemy.id,
                .priority = enemy.threat_value,
                .urgency = if (enemy.distance < 50) 0.8 else 0.3,
            };
            count += 1;
        }
        return count;
    }
}.eval);

// Process turn
var state = personality.AIState.init(.aggressive);
const decision = system.processTurn(&state, &game);

// Get best action
if (decision.getBestAction()) |action| {
    executeAction(action.action_type, action.target_id);
}

// Or get top N actions
const top3 = decision.getTopActions(3);
```

### Weight Modification

```zig
var state = personality.AIState.init(.balanced);

// Temporarily boost aggression
const modifiers = personality.Weights{
    .aggression = 1.5, // +50%
    .defense = 0.8,    // -20%
    .expansion = 1.0,
    .economy = 1.0,
    .technology = 1.0,
    .diplomacy = 1.0,
    .caution = 1.0,
    .opportunism = 1.0,
};

state.modifyWeights(&modifiers);

// Later, reset to base
state.resetWeights();
```

## Personality Templates

| Type | Aggression | Defense | Expansion | Economy | Technology | Diplomacy | Caution | Opportunism |
|------|------------|---------|-----------|---------|------------|-----------|---------|-------------|
| Balanced | 0.5 | 0.5 | 0.5 | 0.5 | 0.5 | 0.5 | 0.5 | 0.5 |
| Aggressive | 0.9 | 0.3 | 0.7 | 0.4 | 0.4 | 0.2 | 0.2 | 0.6 |
| Defensive | 0.2 | 0.9 | 0.3 | 0.6 | 0.5 | 0.5 | 0.8 | 0.3 |
| Economic | 0.3 | 0.5 | 0.6 | 0.9 | 0.6 | 0.7 | 0.6 | 0.5 |
| Expansionist | 0.6 | 0.4 | 0.9 | 0.5 | 0.4 | 0.3 | 0.3 | 0.7 |
| Technologist | 0.3 | 0.5 | 0.4 | 0.6 | 0.9 | 0.5 | 0.6 | 0.4 |
| Diplomatic | 0.2 | 0.5 | 0.4 | 0.6 | 0.5 | 0.9 | 0.7 | 0.4 |
| Opportunist | 0.6 | 0.4 | 0.6 | 0.5 | 0.4 | 0.4 | 0.4 | 0.9 |

## Data Structures

- `AISystem` - System with evaluators and callbacks
- `AIState` - Agent state with personality, weights, threats, goals, cooldowns
- `Weights` - 8 personality trait weights
- `PersonalityType` - Enum of personality templates
- `ActionType` - 13 action types (attack, defend, expand, build, trade, research, upgrade, diplomacy_action, recruit, retreat, scout, special, none)
- `Threat` - Threat entry with source, level, target, distance, age
- `Goal` - Goal entry with type, target, priority, progress
- `Action` - Action with type, target, priority, urgency
- `Decision` - Collection of scored actions with sorting

## Constants

- `MAX_THREATS` = 12
- `MAX_GOALS` = 16
- `MAX_ACTIONS` = 32
- `MAX_COOLDOWNS` = 16

## Tests

24 comprehensive tests covering personalities, threat management, goal tracking, cooldowns, action scoring, situational modifiers, and weight modification.
