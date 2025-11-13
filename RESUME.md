# EtherMud Development - Resume Point

**Date**: 2025-11-13
**Status**: ✅ UI System Complete - Dropdown Z-Ordering Fixed

## Current State

### ✅ Completed Systems

1. **Build System & Dependencies** ✓
   - Zig 0.15.1 build configuration
   - SDL3 for windowing and input
   - bgfx for cross-platform rendering (Metal on macOS)
   - stb_truetype for font rendering
   - Git submodules configured

2. **2D Renderer with View Layering** ✓
   - Batch rendering with transient buffers
   - Orthographic projection
   - Alpha blending and scissor testing
   - **Scissor rectangle caching** (stores rects, not handles)
   - **View-based layering** (view 0: main UI, view 1: overlays)
   - Font metrics and text rendering
   - Manual flush capability
   - **Proper batch clearing** after submit

3. **Font System** ✓
   - 1024x1024 font atlas
   - Roboto-Regular.ttf embedded
   - Proper baseline positioning
   - Antialiased text rendering

4. **Complete Widget Library** ✓
   - Buttons, checkboxes, sliders
   - Text input with SDL3 events
   - **Dropdown menus with proper z-ordering** ✓
   - **Scroll lists with proper clipping** ✓
   - Progress bars, tab bars, panels
   - All widgets functional with proper styling

5. **Input Handling** ✓
   - Mouse tracking and events
   - Mouse wheel scrolling
   - SDL3 text input system
   - Keyboard events

## Recent Session: Dropdown Z-Ordering Fix

### Problem Identified

Dropdown overlays were rendering **partially behind** other widgets:
- Dropdown **text** rendered correctly on top
- Dropdown **background/borders** rendered behind scroll lists and other widgets
- This created a confusing visual where only text was visible

### Root Cause Analysis

The issue was with **batch submission order** in bgfx:

1. Main UI draws widgets including dropdown header and scroll list
2. At `endFrame()`, batches are flushed: color batch submit #1, texture batch submit #2
3. Dropdown overlay draws to the same batches
4. Dropdown geometry is submitted: color batch submit #3, texture batch submit #4

**Problem**: bgfx processes submits in order across ALL batches:
- Submit #1: Main UI colored geometry (includes scroll list backgrounds)
- Submit #2: Main UI textured geometry (includes scroll list text)
- Submit #3: Dropdown colored geometry (dropdown backgrounds) ← Draws BEFORE scroll list text!
- Submit #4: Dropdown textured geometry (dropdown text)

This caused scroll list text (#2) to render on top of dropdown backgrounds (#3).

### Solution Implemented

Implemented **bgfx view-based layering** to ensure proper z-ordering:

#### 1. Batch Clearing Fix
**File**: `src/ui/renderer_2d_proper.zig`
- Added `clear()` calls after `bgfx.submit()` in `flushColorBatch()` and `flushTextureBatch()`
- Ensures batches don't contain duplicate geometry across flushes
- **Lines**: 455, 536

#### 2. Scissor Management Fix
**File**: `src/ui/renderer_2d_proper.zig`
- Modified `endScissor()` to NOT flush batches, only change scissor state
- Allows explicit control over when geometry is submitted
- **Lines**: 631-648

#### 3. View Layering System
**Files**:
- `src/ui/renderer_2d_proper.zig` (262, 332-333, 668-677)
- `src/ui/renderer.zig` (38-40, 77-83, 135-143, 159-161, 220-226)
- `src/ui/dropdown_overlay.zig` (17-70)
- `src/main.zig` (176-178)

**Architecture**:
- **View 0**: Main UI widgets (default)
- **View 1**: Overlay layer (dropdowns, tooltips, modals)
- bgfx renders views **in order**, guaranteeing view 1 always renders after view 0

**Implementation**:
- Added `overlay_view_id` field to renderer
- Added `pushOverlayView()` and `popOverlayView()` methods
- Updated dropdown rendering to:
  1. Flush main UI batches
  2. Switch to overlay view (view 1)
  3. Reset scissor to full window
  4. Render dropdown geometry
  5. Flush dropdown batches
  6. Switch back to default view (view 0)

### Results

✅ **Dropdown overlays render completely on top** - both background and text visible
✅ **Scroll lists clip correctly** - proper scissor functionality maintained
✅ **All UI widgets fully functional** - complete widget library working as designed
✅ **Layering system ready for future overlays** - tooltips, modals can use same pattern

## Project Structure

```
EtherMud/
├── src/
│   ├── main.zig                    # Main loop with UI demo, view setup
│   ├── ui/
│   │   ├── renderer_2d_proper.zig  # 2D batch renderer (view layering, scissor)
│   │   ├── context.zig             # UI context with overlay system
│   │   ├── dropdown_overlay.zig    # Deferred dropdown renderer (uses view 1)
│   │   ├── renderer.zig            # Renderer interface with push/popOverlayView
│   │   ├── widgets.zig             # Complete widget library
│   │   └── types.zig               # Core UI types
│   └── assets/fonts/
│       └── Roboto-Regular.ttf      # Embedded font
└── external/                        # bgfx, SDL3 dependencies
```

## Technical Implementation Details

### View-Based Layering Architecture

```
Frame Rendering Flow:
1. beginFrame() - view_id = 0, scissor = full window
2. Render main UI widgets (buttons, panels, scroll lists)
   - All geometry batched for view 0
3. ctx.endFrame()
   a. Flush main UI batches → bgfx submits to view 0
   b. For each dropdown overlay:
      - pushOverlayView() → view_id = 1
      - endScissor() → full window (no clipping)
      - Render dropdown geometry
      - Flush dropdown batches → bgfx submits to view 1
      - popOverlayView() → view_id = 0
4. renderer.endFrame() - final cleanup
5. bgfx.frame() - bgfx renders view 0, then view 1
```

**Key Insight**: bgfx processes views in order (0, 1, 2...), guaranteeing overlay rendering on top regardless of batch submission timing.

### Scissor Management

1. **Frame Start** (`beginFrame`)
   - Scissor rect set to full window: `(0, 0, width, height)`
   - All batches cleared

2. **Scissor Region** (`beginScissor`)
   - Flush existing batches (with previous scissor)
   - Store new scissor rectangle
   - Subsequent geometry uses new scissor

3. **Scissor End** (`endScissor`)
   - **Does NOT flush** - only changes scissor state
   - Reset scissor to full window
   - Caller controls when to flush

4. **Batch Flush** (any flush call)
   - Call `bgfx.setScissor()` with current `scissor_rect`
   - Submit geometry with fresh scissor applied
   - **Clear batch** after submit

### Overlay Rendering Pattern

Any future overlay widgets (tooltips, modals, context menus) should follow this pattern:

```zig
// 1. Flush main UI
ctx.renderer.flushBatches();

// 2. Switch to overlay view
ctx.renderer.pushOverlayView();

// 3. Reset scissor (no parent clipping)
ctx.renderer.endScissor();

// 4. Draw overlay content
ctx.renderer.drawRect(overlay_rect, color);
ctx.renderer.drawText(text, pos, size, color);

// 5. Flush overlay geometry
ctx.renderer.flushBatches();

// 6. Restore default view
ctx.renderer.popOverlayView();
```

## Known Issues

**None** - All UI features working as designed.

## Next Steps

### Game Development Ready

The UI system is production-ready with proper layering. Proceed with core game features:

1. **Game World Rendering**
   - Tile map system
   - Sprite rendering
   - Camera/viewport management
   - Layered rendering (ground, objects, characters, effects)

2. **Game Logic**
   - Entity Component System (ECS) or simple entity management
   - Player movement and controls
   - NPC behavior
   - Collision detection

3. **Networking**
   - Client-server architecture
   - Message protocol
   - State synchronization
   - Latency compensation

4. **Content Systems**
   - Map editor/loader
   - Quest system
   - Item database
   - Character progression

### Future UI Enhancements

Low priority improvements for later:

- Tooltip system (hover text) - use view 1 overlay pattern
- Modal dialogs - use view 1 overlay pattern
- Context menus (right-click) - use view 1 overlay pattern
- Drag-and-drop
- Custom themes/styling
- UI animation system

## Time Investment

- Initial renderer & font system: ~5 hours
- Widget library development: ~3 hours
- Scissor clipping fix (previous session): ~4 hours
- **This session**: Dropdown z-ordering fix ~3 hours
  - Investigation and diagnosis: ~1 hour
  - View layering implementation: ~1.5 hours
  - Interface updates and testing: ~0.5 hours
- **Total project time**: ~15 hours

## Performance Notes

- 2D batch rendering minimizes draw calls
- Font atlas enables efficient text rendering
- Scissor testing provides proper clipping with minimal overhead
- View-based layering has no performance cost (bgfx feature)
- Target: 60 FPS maintained with complex UI layouts
- Current demo: Stable 60 FPS with all widgets active

## Key Learnings

### bgfx Submission Order

bgfx processes draw calls in the order they're submitted, **across all batches**. This means:
- Batching colored geometry separately from textured geometry can cause z-order issues
- View-based layering (view 0, view 1, view 2...) is the correct solution for UI layers
- Views are rendered in order regardless of submission timing within a view

### Batch Management

Batches must be **explicitly cleared** after submission:
- bgfx's transient buffers don't automatically clear
- Without clearing, subsequent flushes resubmit old geometry
- Always call `batch.clear()` after `bgfx.submit()`

### Scissor State vs Handles

bgfx's `setScissorCached()` returns handles valid only within a single frame:
- Handles reset between frames
- Storing **rectangles** and calling `setScissor()` fresh each flush is more reliable
- This pattern works consistently across frames

---

**Status**: ✅ UI system complete and fully functional. All widgets working with proper clipping and z-ordering via view layering. Dropdown overlays render correctly on top. Ready for game development.

**Next Session**: Begin game world rendering - tile maps, sprites, and camera system.
