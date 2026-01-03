# AgentiteZ Feature Porting Plan

Features identified from Agentite (C/C++) engine to port to AgentiteZ (Zig).

## Phase 1: Core Infrastructure Systems

### Scene & Prefab Systems
- [x] **Prefab System** - Entity templates with component data for spawning
  - Prefab definition format (TOML-based to match existing config system)
  - Prefab registry for caching loaded prefabs
  - Spawning with component overrides
  - Hierarchical prefabs (parent-child relationships)

- [x] **Scene System** - Level/scene loading and management
  - Scene file format with entity definitions
  - Scene manager for loading/unloading scenes
  - Scene state machine (loading, active, unloading)
  - Asset reference tracking per scene
  - Entity lifetime tied to scene

- [x] **Transform Component** - Entity positioning with hierarchy
  - Position, rotation, scale components
  - Parent-child transform hierarchy
  - Local vs world coordinate transforms
  - Transform dirty flag optimization

### Asset Management
- [x] **Asset System** - Unified resource management
  - Asset registry with reference counting
  - Asset handles (type-safe references)
  - Asset loading abstraction layer
  - Asset unloading with dependency tracking
  - Support for: textures, sounds, fonts, scenes, prefabs

- [x] **Async Loading System** - Background resource loading
  - Thread pool for I/O operations
  - Load priority system (critical, high, normal, low)
  - Progress callbacks and completion events
  - Cancellation support
  - Main thread finalization for GPU resources

## Phase 2: Graphics Enhancements

### Rendering Systems
- [x] **Virtual Resolution System** - Resolution-independent rendering
  - Fixed coordinate space (1920x1080 default)
  - Automatic letterboxing/pillarboxing
  - Mouse coordinate transformation
  - Configurable scaling modes (fit, fill, stretch)
  Implemented in `src/renderer/viewport.zig` with VirtualResolution manager

- [x] **3D Camera** - Orbital/perspective camera
  - Orbital camera controls (yaw, pitch, distance)
  - Perspective projection
  - Frustum culling helpers
  - Smooth interpolation and constraints
  Implemented in `src/camera3d.zig` with 25 tests

- [x] **Gizmo System** - Debug drawing and transform handles
  - Line/circle/rectangle primitives
  - Transform handles (translate, rotate, scale)
  - Grid overlay rendering
  - Screen-space vs world-space modes
  Implemented in `src/gizmo.zig` with 21 tests

- [x] **MSDF Text Rendering** - High-quality scalable text
  - Multi-channel signed distance field fonts
  - Runtime MSDF atlas generation in pure Zig
  - Smooth text at any scale with sharp corner preservation
  - Edge coloring algorithm for corner detection
  Implemented in `src/renderer/msdf/` with 25+ tests:
  - `math_utils.zig` - Vec2, SignedDistance, polynomial solvers
  - `edge.zig` - Linear, Quadratic, Cubic Bezier segments
  - `contour.zig` - Shape/Contour from stb_truetype vertices
  - `edge_coloring.zig` - Corner detection and color assignment
  - `msdf_generator.zig` - Core MSDF generation algorithm
  FontAtlas.initMSDF() in `src/renderer/font_atlas.zig`
  MSDF shader in `src/ui/shaders_source/fs_msdf_text.sc`

### Debug Visualization
- [x] **Line Renderer** - Debug line drawing
  - Batched line rendering
  - Colors and line widths
  - Screen-space and world-space lines
  - Common shapes (boxes, circles, arrows)
  Covered by Gizmo System in `src/gizmo.zig`

## Phase 3: UI System Enhancements

### New Widgets
- [x] **Chart Widget** - Data visualization
  - Line charts with multiple series
  - Bar charts (vertical, grouped for multi-series)
  - Pie charts with percentage legends
  - Axis labels and legends
  - Configurable colors and colorblind-friendly default palette
  Implemented in `src/ui/widgets/chart.zig` with 5 tests

- [x] **RichText Widget** - Formatted text display
  - Inline bold, italic, underline via BBCode-style markup
  - Text colors ([c=#RRGGBB]) and backgrounds ([bg=#RRGGBB])
  - Links with click handling and hover effects
  - Word wrapping with configurable max width
  - Nested tag support
  Implemented in `src/ui/widgets/rich_text.zig` with 9 tests

- [x] **Table Widget** - Tabular data display
  - Column headers with sorting
  - Row selection (single/multi)
  - Cell customization
  - Scrolling for large datasets
  - Column resizing
  Implemented in `src/ui/widgets/table.zig` with 6 tests

- [x] **Color Picker Widget** - Color selection
  - HSV/RGB color models with Hsv struct and conversion functions
  - Saturation-Value gradient picker with hue slider
  - Alpha channel support with transparency visualization
  - Color presets/swatches (15 default colors)
  - Hex color parsing and formatting
  - Compact color picker variant (button + popup)
  Implemented in `src/ui/widgets/color_picker.zig` with 9 tests

- [x] **Notification System** - Toast notifications
  - Position options (9 positions: corners, edges, center)
  - Auto-dismiss with configurable duration per notification type
  - Notification types (info, success, warning, error) with distinct colors
  - Queue management for up to 8 simultaneous notifications
  - Fade-in/fade-out animations with configurable durations
  - Optional close button and click-to-dismiss
  Implemented in `src/ui/widgets/notification.zig` with 11 tests

### UI Features
- [x] **Tween System** - UI animation
  - Easing functions (30+ including ease-in, ease-out, bounce, elastic, back)
  - Property animation (position, size, color, alpha)
  - Sequence and parallel composition
  - Callbacks on completion (on_start, on_update, on_complete)
  - Yoyo mode and repeat support
  Implemented in `src/tween.zig` with 25 tests

- [x] **View Model Pattern** - MVVM data binding
  - Observable properties with change notifications
  - Computed properties for derived values with dependency tracking
  - Two-way binding for sliders, checkboxes, text inputs
  - ViewModel base type with lifecycle management
  - Batching support for coalescing multiple changes
  Implemented in `src/viewmodel/` with 25+ tests:
  - `observable.zig` - Observable(T) generic wrapper with subscriptions
  - `computed.zig` - Computed(T) derived values with auto-recompute
  - `binding.zig` - Widget binding helpers for two-way binding
  - `viewmodel.zig` - ViewModel base with binding cleanup

## Phase 4: ECS Enhancements

### Development Tools
- [x] **ECS Reflection System** - Runtime component introspection
  - Component type registry with metadata capture at comptime
  - Field metadata (name, type, offset, size, default value)
  - FieldKind classification for serialization/UI
  - Runtime field get/set via ComponentAccessor
  - TOML serialization support
  - Integration with PrefabRegistry (registerComponentTypeWithReflection)
  Implemented in `src/ecs/reflection.zig`, `src/ecs/component_accessor.zig`,
  `src/ecs/serialization.zig` with 25+ tests

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
