# AgentiteZ Feature Porting Plan

Features identified from Agentite (C/C++) engine to port to AgentiteZ (Zig).

## Phase 1: Core Infrastructure Systems

### Scene & Prefab Systems
- [x] **Prefab System** - Entity templates with component data for spawning
  - Prefab definition format (TOML-based to match existing config system)
  - Prefab registry for caching loaded prefabs
  - Spawning with component overrides
  - Hierarchical prefabs (parent-child relationships)

- [ ] **Scene System** - Level/scene loading and management
  - Scene file format with entity definitions
  - Scene manager for loading/unloading scenes
  - Scene state machine (loading, active, unloading)
  - Asset reference tracking per scene
  - Entity lifetime tied to scene

- [ ] **Transform Component** - Entity positioning with hierarchy
  - Position, rotation, scale components
  - Parent-child transform hierarchy
  - Local vs world coordinate transforms
  - Transform dirty flag optimization

### Asset Management
- [ ] **Asset System** - Unified resource management
  - Asset registry with reference counting
  - Asset handles (type-safe references)
  - Asset loading abstraction layer
  - Asset unloading with dependency tracking
  - Support for: textures, sounds, fonts, scenes, prefabs

- [ ] **Async Loading System** - Background resource loading
  - Thread pool for I/O operations
  - Load priority system (critical, high, normal, low)
  - Progress callbacks and completion events
  - Cancellation support
  - Main thread finalization for GPU resources

## Phase 2: Graphics Enhancements

### Rendering Systems
- [ ] **Virtual Resolution System** - Resolution-independent rendering
  - Fixed coordinate space (1920x1080 default)
  - Automatic letterboxing/pillarboxing
  - Mouse coordinate transformation
  - Configurable scaling modes (fit, fill, stretch)
  Partial support exists in viewport.zig, needs enhancement

- [ ] **3D Camera** - Orbital/perspective camera
  - Orbital camera controls (yaw, pitch, distance)
  - Perspective projection
  - Frustum culling helpers
  - Smooth interpolation and constraints

- [ ] **Gizmo System** - Debug drawing and transform handles
  - Line/circle/rectangle primitives
  - Transform handles (translate, rotate, scale)
  - Grid overlay rendering
  - Screen-space vs world-space modes

- [ ] **MSDF Text Rendering** - High-quality scalable text
  - Multi-channel signed distance field fonts
  - MSDF atlas generation (offline or runtime)
  - Smooth text at any scale
  - Outline and shadow effects
  Current font system is bitmap-based

### Debug Visualization
- [ ] **Line Renderer** - Debug line drawing
  - Batched line rendering
  - Colors and line widths
  - Screen-space and world-space lines
  - Common shapes (boxes, circles, arrows)

## Phase 3: UI System Enhancements

### New Widgets
- [ ] **Chart Widget** - Data visualization
  - Line charts with multiple series
  - Bar charts (horizontal/vertical)
  - Pie/donut charts
  - Axis labels and legends
  - Configurable colors and styles

- [ ] **RichText Widget** - Formatted text display
  - Inline bold, italic, underline
  - Text colors and backgrounds
  - Inline images/icons
  - Links with click handling
  - Simple markup parser

- [ ] **Table Widget** - Tabular data display
  - Column headers with sorting
  - Row selection (single/multi)
  - Cell customization
  - Scrolling for large datasets
  - Column resizing

- [ ] **Color Picker Widget** - Color selection
  - HSV/RGB color models
  - Color wheel or gradient picker
  - Alpha channel support
  - Color presets/swatches

- [ ] **Notification System** - Toast notifications
  - Position options (corners, center)
  - Auto-dismiss with configurable duration
  - Notification types (info, success, warning, error)
  - Queue management for multiple notifications

### UI Features
- [ ] **Tween System** - UI animation
  - Easing functions (ease-in, ease-out, bounce, etc.)
  - Property animation (position, size, color, alpha)
  - Sequence and parallel composition
  - Callbacks on completion

- [ ] **View Model Pattern** - MVVM data binding
  - Observable properties
  - Automatic UI updates on data change
  - Two-way binding for inputs

## Phase 4: ECS Enhancements

### Development Tools
- [ ] **ECS Reflection System** - Runtime component introspection
  - Component type registry
  - Field metadata (name, type, offset)
  - Serialization support
  - Integration with config system

- [ ] **ECS Inspector** - Debug UI for entities
  - Entity browser with filtering
  - Component viewer/editor
  - Real-time value modification
  - Archetype statistics

## Phase 5: Additional Strategy Systems

These systems extend the existing strategy game framework.

### Economy & Resources
- [ ] **Finance System** - Economic management
  - Income/expense tracking
  - Budget categories
  - Financial reports per turn
  - Deficit handling

- [ ] **Loan System** - Borrowing mechanics
  - Loan offers with interest rates
  - Repayment schedules
  - Credit rating impact
  - Default consequences

- [ ] **Trade Routes** - Inter-region trade
  - Trade route creation and management
  - Supply/demand pricing
  - Transport costs and time
  - Trade agreements

- [ ] **Demand System** - Market simulation
  - Resource demand calculation
  - Price elasticity
  - Market equilibrium

### World Systems
- [ ] **Biome System** - Terrain classification
  - Biome definitions (forest, desert, ocean, etc.)
  - Biome effects on gameplay (movement, resources)
  - Biome transitions and borders
  - Climate influence

- [ ] **Anomaly System** - Discoverable events
  - Anomaly spawning and discovery
  - Investigation mechanics
  - Rewards and consequences
  - Anomaly types (ruins, resources, events)

- [ ] **Game Event System** - Triggered events
  - Event conditions and triggers
  - Event choices and outcomes
  - Event chains and storylines
  - Integration with dialog system

### Military Systems
- [ ] **Siege System** - City/fort siege mechanics
  - Siege progress tracking
  - Siege equipment and tactics
  - Supply line mechanics
  - Breakthrough conditions

- [ ] **Blueprint/Construction** - Building placement
  - Blueprint ghost rendering
  - Placement validation
  - Construction progress tracking
  - Resource requirements

### Game Flow
- [ ] **Game Speed System** - Timing control
  - Multiple speed settings
  - Pause functionality
  - Per-system speed scaling
  - UI for speed control

- [ ] **History System** - Game history tracking
  - Event logging with timestamps
  - Statistics over time
  - Replay support
  - Achievements based on history

## Phase 6: Utility Systems

- [ ] **Safe Math** - Overflow-safe arithmetic
  - Checked add/sub/mul operations
  - Saturating arithmetic
  - Integer size conversions
  Zig has built-in overflow detection, may just need wrapper utilities

- [ ] **Query System** - Advanced ECS queries
  - Query builder pattern
  - Component filters (with, without, optional)
  - Query caching
  - Iteration optimizations

---

## Implementation Notes

### Priority Order
1. **Phase 1** - Foundation for other systems (prefabs/scenes enable level design)
2. **Phase 3** - UI enhancements have high user visibility
3. **Phase 2** - Graphics improvements for polish
4. **Phase 4** - Development tools accelerate future work
5. **Phase 5-6** - Game-specific features as needed

### Zig-Specific Considerations
- Use comptime where possible for zero-cost abstractions
- Leverage Zig's error handling (error unions) instead of C-style error codes
- Use allocator parameter pattern for memory management
- Consider using tagged unions for variant types
- Existing TOML parser can be extended for new config formats

### Testing Strategy
- Unit tests for each new system (matching existing test coverage pattern)
- Integration tests for system interactions
- Example programs demonstrating usage

### Documentation
- API documentation in `docs/api/` following existing pattern
- Update CLAUDE.md with new system summaries
- Example code in `examples/` directory
