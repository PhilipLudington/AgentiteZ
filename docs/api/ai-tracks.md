# AI Tracks System

Parallel decision tracks for AI agents (`src/ai_tracks.zig`).

## Features

- **Multiple tracks** - Independent decision domains (combat, economy, diplomacy)
- **Track priorities** - Base importance weighting for each track
- **Urgency scoring** - Dynamic importance based on situation
- **Recommendations** - Suggested actions with scores and metadata
- **Cross-track communication** - Shared blackboard state
- **Conflict detection** - Identify conflicting recommendations
- **Predefined tracks** - Combat, economy, and diplomacy update functions

## Usage

### Basic Setup

```zig
const ai_tracks = @import("AgentiteZ").ai_tracks;

var ai = ai_tracks.AITrackSystem.init(allocator);
defer ai.deinit();

// Define custom tracks
try ai.addTrack("combat", .{ .priority = 0.8 });
try ai.addTrack("economy", .{ .priority = 0.6 });
try ai.addTrack("diplomacy", .{ .priority = 0.4 });
```

### Track Update Functions

```zig
fn myCombatUpdate(track: *ai_tracks.Track, context: ?*anyopaque, shared: *blackboard.Blackboard) void {
    const game: *Game = @ptrCast(@alignCast(context.?));

    // Read shared state
    const threat_level = shared.getFloatOr("threat_level", 0.0);

    // Set track urgency based on situation
    track.setUrgency(threat_level);

    // Generate recommendations
    if (threat_level > 0.7) {
        track.recommend(.defend, 0.9, "High threat - defensive posture") catch {};
    } else {
        track.recommend(.attack, 0.6, "Normal - offensive operations") catch {};
    }
}

try ai.addTrack("combat", .{
    .priority = 0.8,
    .update_fn = myCombatUpdate,
});
```

### Predefined Track Functions

```zig
// Use built-in update functions
try ai.addTrack("combat", .{ .update_fn = ai_tracks.combatTrackUpdate });
try ai.addTrack("economy", .{ .update_fn = ai_tracks.economyTrackUpdate });
try ai.addTrack("diplomacy", .{ .update_fn = ai_tracks.diplomacyTrackUpdate });

// Set shared state that predefined functions expect
try ai.postMessage("threat_level", .{ .float32 = 0.5 });
try ai.postMessage("enemy_count", .{ .int32 = 3 });
try ai.postMessage("military_strength", .{ .float32 = 0.8 });
try ai.postMessage("resources", .{ .float32 = 500.0 });
```

### Updating Tracks

```zig
// Update all enabled tracks
ai.update(&game_state);

// Or with delta time (for cooldowns)
ai.updateWithDelta(&game_state, delta_time);
```

### Getting Recommendations

```zig
// Get best recommendation across all tracks
if (ai.getBestRecommendation()) |rec| {
    std.debug.print("Action: {s} from {s}\n", .{
        @tagName(rec.action),
        rec.getTrackName(),
    });
    std.debug.print("Reason: {s}\n", .{rec.getReason()});

    executeAction(rec.action, rec.target_id);
}

// Get top N recommendations
const top = try ai.getTopRecommendations(allocator, 5);
defer allocator.free(top);

// Filter by action type
const attacks = try ai.getRecommendationsByAction(allocator, .attack);
defer allocator.free(attacks);

// Filter by tag
const urgent = try ai.getRecommendationsByTag(allocator, "urgent");
defer allocator.free(urgent);
```

### Recommendations with Metadata

```zig
const track = ai.getTrack("combat").?;

// Basic recommendation
try track.recommend(.attack, 0.9, "Enemy spotted");

// Extended recommendation with target and tags
try track.recommendEx(.attack, 0.9, "Attack enemy base", .{
    .target_id = enemy_id,
    .location_x = 100.0,
    .location_y = 200.0,
    .tags = &.{ "urgent", "military", "high-value" },
});
```

### Cross-Track Communication

```zig
// Post messages to shared state
try ai.postMessage("threat_level", .{ .float32 = 0.8 });
try ai.postMessage("resources_low", .{ .boolean = true });

// Read from shared state (in update functions or externally)
const threat = ai.getMessage("threat_level");
if (threat) |value| {
    const level = value.toFloat();
}
```

### Conflict Detection

```zig
// Check if recommendations conflict
if (ai.hasConflict(&rec1, &rec2)) {
    // Same target, incompatible actions (attack vs ally)
}

// Get non-conflicting recommendations
const safe = try ai.getNonConflictingRecommendations(allocator, 3);
defer allocator.free(safe);
```

### Track Control

```zig
// Enable/disable tracks
_ = ai.setTrackEnabled("diplomacy", false);

// Adjust priorities dynamically
_ = ai.setTrackPriority("combat", 1.0); // Increase during battle

// Set urgency externally
_ = ai.setTrackUrgency("economy", 0.9); // Resource crisis

// Remove a track
_ = ai.removeTrack("obsolete_track");
```

### Track Cooldowns

```zig
// Track with 1 second cooldown between updates
try ai.addTrack("expensive", .{
    .priority = 0.5,
    .update_fn = expensiveUpdate,
    .cooldown = 1.0,
});

// Must use updateWithDelta for cooldowns to work
ai.updateWithDelta(&game, delta_time);
```

## Data Structures

- `AITrackSystem` - Main system managing all tracks
- `Track` - Individual decision domain with recommendations
- `Recommendation` - Suggested action with score and metadata
- `ActionType` - Enum of available actions (attack, defend, gather, etc.)
- `AITrackStats` - Statistics (track_count, recommendations, updates)

### Action Types

Combat: `attack`, `defend`, `retreat`, `reinforce`, `flank`, `siege`
Economy: `gather`, `build`, `upgrade`, `trade`, `expand`, `stockpile`
Diplomacy: `negotiate`, `ally`, `declare_war`, `peace_offer`, `tribute`, `embargo`
General: `scout`, `research`, `wait`, `custom`

## Constants

- `MAX_NAME_LENGTH` = 63
- `MAX_TRACKS` = 16
- `MAX_RECOMMENDATIONS` = 32
- `MAX_TAGS` = 8

## Predefined Track Functions

### combatTrackUpdate
Evaluates `threat_level`, `enemy_count`, `military_strength` to recommend:
- High threat + low strength: retreat, reinforce
- Moderate threat: defend, counter-attack
- Low threat: attack, scout

### economyTrackUpdate
Evaluates `resources`, `production_rate`, `storage_capacity` to recommend:
- Low resources: gather (high urgency)
- Low production: build
- High resources: expand, trade

### diplomacyTrackUpdate
Evaluates `best_relations`, `worst_relations`, `at_war` to recommend:
- At war with good relations: peace offer
- Good relations: ally proposal
- Bad relations: embargo
- Peace time: negotiate

## Error Handling

- `error.NameTooLong` - Track name exceeds MAX_NAME_LENGTH
- `error.DuplicateTrack` - Track name already exists
- `error.TooManyTracks` - Exceeds MAX_TRACKS

## Tests

24 comprehensive tests covering track management, recommendations, scoring, filtering, conflict detection, predefined tracks, and cooldowns.
