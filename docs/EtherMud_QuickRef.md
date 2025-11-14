# EtherMud - Quick Reference Summary

## What is EtherMud?

A **production-ready game engine framework** (not a game) providing:
- SDL3 window/input management
- BGFX 2D rendering pipeline (Metal/Vulkan/DirectX/OpenGL)
- Complete 10-widget UI system
- Structured logging system
- Font rendering with stb_truetype
- Configuration management

**Current Status:** 7.2/10 QA → 8.5/10 target (40% of improvement plan complete)

---

## Architecture Layers

```
Application Code (Your Game)
    ↓
UI System (10 widgets + context)
    ↓
2D Renderer (Renderer2DProper - 921 lines)
    ↓
BGFX (Cross-platform graphics)
    ↓
SDL3 (Window/input)
```

---

## 10 Widget Types

1. **Button** - Interactive, click-detectable
2. **Checkbox** - Boolean state
3. **Slider** - Range values
4. **Text Input** - Single-line text with focus
5. **Dropdown** - Selection menu with overlay
6. **Scroll List** - Scrollable item list
7. **Progress Bar** - Visual progress with color coding
8. **Tab Bar** - Multi-tab interface
9. **Panel** - Container with decorations
10. **Label** - Non-interactive text

---

## Key Components

### Renderer2DProper (921 lines)
- Batch accumulation (color + texture)
- Scissor clipping
- BGFX view layering (view 0 = main, view 1 = overlays)
- Font atlas rendering
- Window resize handling

### UI Context
- Widget state tracking (hot/active/focused)
- Input distribution
- Layout/cursor management
- Theme management
- Deferred overlay rendering

### Font System
- stb_truetype integration
- 1024x1024 atlas
- ASCII 32-127 support
- Anti-aliased rendering
- 3-layer safeguards (half-pixel offset, clamp sampling, linear filtering)

### Logging System
- 5 levels: err, warn, info, debug, trace
- Compile-time filtering (debug/trace removed in release)
- Color-coded output
- Thread-safe
- Zero overhead in production

---

## File Structure Summary

| Path | Lines | Purpose |
|------|-------|---------|
| `src/main.zig` | 407 | Demo app + event loop |
| `src/ui/widgets.zig` | 1278 | All 10 widget types |
| `src/ui/renderer_2d_proper.zig` | 921 | Production renderer |
| `src/ui/context.zig` | 367 | UI state management |
| `src/ui/types.zig` | 300+ | Core types (Vec2, Rect, Color, etc.) |
| `src/ui/dpi.zig` | 402 | DPI/viewport scaling |
| `src/ui/config.zig` | 91 | Centralized constants |
| `src/log.zig` | 244 | Structured logging |
| `src/ui/integration_tests.zig` | 355 | Widget integration tests |

---

## Dependencies

| Dependency | Type | Location |
|------------|------|----------|
| Zig 0.15.1 | Required | Compiler |
| SDL3 | System lib | `brew install sdl3` (macOS) |
| BGFX | Built-in | `external/bgfx/` (git submodule) |
| BX | Built-in | `external/bx/` (git submodule) |
| BIMG | Built-in | `external/bimg/` (git submodule) |
| stb_truetype | Vendored | `external/stb/` (header-only) |

---

## What EtherMud Does NOT Have

- ❌ ECS system (app-specific)
- ❌ Game logic
- ❌ Game data
- ❌ Game screens
- ❌ 3D rendering
- ❌ Physics
- ❌ Audio
- ❌ Networking
- ❌ Animation system

---

## Comparison: EtherMud vs Stellar Throne

| Aspect | EtherMud | Stellar Throne |
|--------|----------|-----------------|
| **Type** | Engine framework | 4X strategy game |
| **ECS** | NO | YES |
| **Game Logic** | NO | YES |
| **UI Widgets** | 10 complete | 10 complete |
| **Rendering** | Production-ready | Custom + tested |
| **Logging** | Structured 5-level | Debug prints |
| **Config** | Centralized | Magic numbers |
| **QA Score** | 7.2/10 | Not scored |
| **Target User** | Any game developer | 4X game players |

---

## Quality Improvement Plan (PLAN.md)

**Target:** 7.2 → 8.5/10 (2-3 weeks)

### Completed (40% - 4/10 tasks)
- ✅ Structured logging system
- ✅ Remove debug logging from hot paths
- ✅ Error logging for silent failures
- ✅ Clean up unused renderer files
- ⚠️ Extract magic numbers (infrastructure only)

### Remaining (60% - 6/10 tasks)
- 🔲 Add renderer unit tests
- 🔲 Add font atlas tests
- 🔲 Add integration tests
- 🔲 Split large widget file
- 🔲 Complete DPI scaling

---

## How to Use EtherMud

### Minimal Example
```zig
const EtherMud = @import("EtherMud");
const ui = EtherMud.ui;

// Initialize
var renderer_2d = try ui.Renderer2DProper.init(allocator, width, height);
const renderer = ui.Renderer.init(&renderer_2d);
var ctx = ui.Context.init(allocator, renderer);

// Each frame
renderer_2d.beginFrame();
ctx.beginFrame(input_state);

// Draw widgets
if (ui.button(&ctx, "Click Me", rect)) {
    // Button was clicked
}

ctx.endFrame();
renderer_2d.endFrame();
bgfx.frame(false);
```

---

## Key Design Patterns

### 1. Immediate-Mode UI
- Widgets drawn fresh each frame
- State managed externally (not in widgets)
- Context tracks transient state (hot/active/focused)
- Simple to test with NullRenderer

### 2. Renderer Abstraction (VTable)
- Pluggable renderer implementations
- Enables testing without BGFX
- Easy to add custom renderers

### 3. Batch Rendering
- Accumulates geometry per frame
- Sends in batches to GPU
- Reduces draw call overhead
- Uses transient buffers

### 4. View Layering
- BGFX view 0: main UI
- BGFX view 1: overlays (dropdowns)
- Automatic z-ordering
- Deferred rendering pass

### 5. Structured Logging
- 5 severity levels
- Compile-time filtering
- Compile-out in release mode
- Zero production overhead

---

## Performance Characteristics

- **Target:** 60 FPS sustained
- **Achieved:** Stable 60 FPS with all widgets active
- **Batch overhead:** Minimal (transient buffers reused)
- **Logging overhead:** 0 in release builds
- **Scissor testing:** Hardware-accelerated
- **Font rendering:** Cached atlas (no runtime generation)

---

## Notable Implementation Details

### Font Atlas Safety
Three layers of protection for pixel-perfect text:
1. Half-pixel UV offset (samples from pixel centers)
2. Clamp sampling (prevents texture wraparound)
3. Linear filtering (bilinear for smooth text)

### Error Handling Improvement
Recent refactor added explicit logging instead of silent catch blocks:
```zig
// Before: error silently caught
try operation() catch {};

// After: error logged with context
try operation() catch |err| {
    log.warn("category", "Operation failed: {}", .{err});
};
```

### Configuration Centralization
70+ constants organized by category:
- `config.spacing.*` - Padding, offsets
- `config.sizes.*` - Widget dimensions
- `config.font.*` - Font atlas settings
- `config.borders.*` - Border thicknesses
- `config.timing.*` - Animation durations
- `config.scrolling.*` - Scroll behavior

---

## Code Quality Notes

**Strengths:**
- Well-documented (CLAUDE.md, RESUME.md, PLAN.md)
- Clean git history
- Clear separation of concerns
- Production-ready UI system
- Comprehensive error handling

**Recent Improvements (This Week):**
- Added error logging to 5 critical paths
- Deleted 595 lines of unused code
- Created centralized configuration system
- Improved code clarity overall

**Next Steps (per PLAN.md):**
- Unit tests for renderer (4-6 hours)
- Font atlas tests (2-3 hours)
- Integration tests (3-4 hours)
- Widget file refactoring (4-5 hours)
- DPI scaling completion (6-8 hours)

---

## Related Documentation

- **Full Analysis:** `/Users/mrphil/Fun/EtherMud_Analysis.md` (932 lines)
- **In-Repo Docs:**
  - `CLAUDE.md` - Architecture guide
  - `RESUME.md` - Development history
  - `PLAN.md` - Quality improvement roadmap
  - `README.md` - Quick start guide

---

## Key Learnings

1. **Silent Errors are Dangerous** - Always log failures, even caught ones
2. **Code Cleanup Matters** - Removing 595 lines of unused code improves clarity
3. **Centralize Configuration** - Single source of truth prevents inconsistency
4. **Profile Hot Paths** - Logging in render loop visible in performance
5. **Abstract Early** - VTable pattern enables pluggable implementations
6. **Batch Geometry** - Reduces draw calls, improves performance

---

**TL;DR:** EtherMud is a battle-tested UI/rendering foundation for Zig games. It provides a complete 10-widget UI library, production 2D renderer, structured logging, and professional error handling. It's framework-agnostic (you add the ECS/game logic), making it suitable for any game type. Currently at 7.2/10 quality with documented 3-week improvement plan to 8.5/10.
