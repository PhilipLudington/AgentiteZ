# EtherMud - Quality Improvement Plan

**Created:** 2025-11-13
**Status:** 🚧 In Progress
**Based on:** QA Review (Score: 7.2/10)

This document outlines the action items to improve code quality, maintainability, and robustness before expanding to game development features.

---

## Overview

Following the comprehensive QA review, we've identified 7 high-priority improvements to address before building game-specific features. These improvements focus on code quality, testing, and maintainability.

**Target Completion:** 2-3 weeks
**Target Score Increase:** 7.2 → 8.5/10

---

## Priority 1: Testing Infrastructure (Critical)

### Task 1.1: Add Renderer Tests ✅
**Status:** 🔴 Not Started
**Priority:** Critical
**Estimated Time:** 4-6 hours
**Owner:** Unassigned

**Description:**
Add comprehensive unit tests for `renderer_2d_proper.zig` (currently 0 tests for 727 lines of critical rendering code).

**Acceptance Criteria:**
- [ ] Test batch accumulation (color and texture)
- [ ] Test batch flushing behavior
- [ ] Test scissor rectangle storage and application
- [ ] Test view switching (pushOverlayView/popOverlayView)
- [ ] Test window resize handling
- [ ] Test orthographic projection matrix generation
- [ ] Achieve >70% code coverage for renderer_2d_proper.zig

**Test Cases to Implement:**
```zig
test "Renderer2DProper - batch accumulation"
test "Renderer2DProper - flush clears batches"
test "Renderer2DProper - scissor rect storage"
test "Renderer2DProper - view switching"
test "Renderer2DProper - window resize updates"
test "Renderer2DProper - ortho projection matrix"
```

**Files to Create:**
- `src/ui/renderer_2d_proper_test.zig` (new test file)

**Dependencies:** None

---

### Task 1.2: Add Font Atlas Tests ✅
**Status:** 🔴 Not Started
**Priority:** High
**Estimated Time:** 2-3 hours
**Owner:** Unassigned

**Description:**
Add tests for font atlas generation and UV coordinate calculation to prevent regressions in text rendering.

**Acceptance Criteria:**
- [ ] Test font atlas initialization
- [ ] Test UV coordinate calculation with half-pixel offset
- [ ] Test text measurement accuracy
- [ ] Test baseline offset calculation
- [ ] Test character advance calculation

**Test Cases to Implement:**
```zig
test "FontAtlas - initialization"
test "FontAtlas - UV coordinates with half-pixel offset"
test "FontAtlas - text measurement"
test "FontAtlas - baseline offset"
```

**Files to Modify:**
- `src/ui/renderer_2d_proper.zig` (add tests at end of file)

**Dependencies:** None

---

### Task 1.3: Add Integration Tests ✅
**Status:** 🔴 Not Started
**Priority:** Medium
**Estimated Time:** 3-4 hours
**Owner:** Unassigned

**Description:**
Add integration tests for complete UI workflows (widget interaction, overlay rendering, etc.).

**Acceptance Criteria:**
- [ ] Test complete button click flow (hover → press → release)
- [ ] Test dropdown open → select → close flow
- [ ] Test scroll list with mouse wheel
- [ ] Test text input with focus management
- [ ] Test overlay rendering order (main UI → dropdowns)

**Test Cases to Implement:**
```zig
test "Integration - button click flow"
test "Integration - dropdown selection flow"
test "Integration - scroll list interaction"
test "Integration - text input with focus"
test "Integration - overlay z-ordering"
```

**Files to Create:**
- `src/ui/integration_test.zig` (new test file)

**Dependencies:** Task 1.1 (renderer tests)

---

## Priority 2: Logging System (High)

### Task 2.1: Implement Structured Logging ✅
**Status:** 🔴 Not Started
**Priority:** High
**Estimated Time:** 4-5 hours
**Owner:** Unassigned

**Description:**
Replace all `std.debug.print` calls with a structured logging system that supports log levels and compile-time filtering.

**Acceptance Criteria:**
- [ ] Create logging module with levels (ERROR, WARN, INFO, DEBUG, TRACE)
- [ ] Support compile-time log level filtering
- [ ] Support runtime log level configuration
- [ ] Add category/module tagging
- [ ] Replace all `std.debug.print` calls in production code paths
- [ ] Keep debug logging available via DEBUG level

**Log Levels:**
```zig
pub const LogLevel = enum {
    err,    // Critical errors
    warn,   // Warnings
    info,   // Informational messages
    debug,  // Debug information (compiled out in release)
    trace,  // Verbose tracing (compiled out in release)
};
```

**API Design:**
```zig
const log = @import("log.zig");

// Usage:
log.err("Renderer", "Failed to allocate buffers: {}", .{error});
log.info("UI", "Window resized to {}x{}", .{width, height});
log.debug("Renderer", "Flushing batch with {} vertices", .{count});
```

**Files to Create:**
- `src/log.zig` (new logging module)

**Files to Modify:**
- `src/main.zig` - Remove debug prints
- `src/ui/context.zig` - Replace debug prints with log calls
- `src/ui/renderer_2d_proper.zig` - Replace debug prints with log calls
- `src/ui/widgets.zig` - Replace debug prints with log calls

**Dependencies:** None

---

### Task 2.2: Remove Debug Logging from Hot Paths ✅
**Status:** 🔴 Not Started
**Priority:** High
**Estimated Time:** 1-2 hours
**Owner:** Unassigned

**Description:**
Remove or convert debug logging statements in performance-critical code paths (batch flushing, frame rendering).

**Acceptance Criteria:**
- [ ] Remove all logging from `flushColorBatch()` and `flushTextureBatch()`
- [ ] Remove all logging from `beginFrame()` and `endFrame()`
- [ ] Convert remaining necessary logs to TRACE level (compiled out in release)
- [ ] Verify no performance impact in release builds

**Files to Modify:**
- `src/ui/renderer_2d_proper.zig:366` - beginFrame logging
- `src/ui/renderer_2d_proper.zig:382` - flushColorBatch logging
- `src/ui/renderer_2d_proper.zig:461` - batch clearing logging
- `src/ui/renderer_2d_proper.zig:640` - beginScissor logging
- `src/ui/renderer_2d_proper.zig:653` - endScissor logging
- `src/ui/renderer_2d_proper.zig:679` - pushOverlayView logging
- `src/ui/renderer_2d_proper.zig:685` - popOverlayView logging
- `src/ui/context.zig:147` - endFrame logging

**Debug Prints to Remove/Convert:**
```
main.zig:210 - "Button clicked!"
widgets.zig:367 - "DROPDOWN: Toggled to {}"
widgets.zig:406 - "DROPDOWN: Queueing dropdown overlay..."
context.zig:147 - "endFrame: Flushing main widgets..."
context.zig:157 - "endFrame: Flushing dropdown overlays..."
```

**Dependencies:** Task 2.1 (logging system)

---

## Priority 3: Code Cleanup (Medium)

### Task 3.1: Remove Unused Renderer Implementations ✅
**Status:** 🔴 Not Started
**Priority:** High
**Estimated Time:** 1 hour
**Owner:** Unassigned

**Description:**
Remove or clearly mark unused renderer implementations to reduce code confusion.

**Acceptance Criteria:**
- [ ] Identify which renderer is the canonical implementation
- [ ] Remove unused renderers OR add deprecation warnings
- [ ] Update documentation to clarify renderer architecture
- [ ] Remove imports of unused renderers

**Analysis:**
- `renderer_2d.zig` (230 lines) - Legacy?
- `renderer_2d_proper.zig` (727 lines) - **ACTIVE (confirmed by usage)**
- `renderer_improved.zig` (133 lines) - Unused?
- `bgfx_renderer.zig` (232 lines) - Purpose unclear

**Decision Needed:**
1. Keep only `renderer_2d_proper.zig`?
2. Or keep legacy renderers but add `@deprecated` annotations?

**Files to Modify:**
- `src/ui/renderer_2d.zig` - Remove or deprecate
- `src/ui/renderer_improved.zig` - Remove or deprecate
- `src/ui/bgfx_renderer.zig` - Clarify purpose or remove
- `src/ui.zig` - Update exports

**Dependencies:** None

---

### Task 3.2: Extract Magic Numbers to Configuration ✅
**Status:** 🔴 Not Started
**Priority:** Medium
**Estimated Time:** 3-4 hours
**Owner:** Unassigned

**Description:**
Extract hardcoded magic numbers to named constants in a configuration module for better maintainability.

**Acceptance Criteria:**
- [ ] Create UI configuration module
- [ ] Extract all spacing/padding constants
- [ ] Extract all size constants (corner size, border thickness, etc.)
- [ ] Extract all timing constants
- [ ] Update all code to use named constants
- [ ] Document each constant with purpose

**Magic Numbers Found:**
```zig
// widgets.zig
const grid_spacing: f32 = 20;          // Panel grid
const corner_size: f32 = 8;            // Panel corners
const padding: f32 = 3;                // Scroll list padding
const scrollbar_width: f32 = 8;        // Scrollbar width
const item_height: f32 = 25;           // List item height
const scroll_speed: f32 = 30;          // Wheel scroll speed
const delay_frames: u32 = 30;          // Tooltip delay

// renderer_2d_proper.zig
const atlas_width: u32 = 1024;         // Font atlas size
const atlas_height: u32 = 1024;
const font_size: f32 = 24.0;           // Default font size
```

**Proposed Structure:**
```zig
// src/ui/config.zig
pub const UIConfig = struct {
    // Spacing
    pub const widget_spacing: f32 = 5;
    pub const panel_padding: f32 = 10;
    pub const scroll_list_padding: f32 = 3;

    // Sizes
    pub const corner_bolt_size: f32 = 8;
    pub const scrollbar_width: f32 = 8;
    pub const border_thickness: f32 = 2;

    // Layout
    pub const item_height: f32 = 25;
    pub const panel_grid_spacing: f32 = 20;

    // Interaction
    pub const scroll_speed: f32 = 30;
    pub const tooltip_delay_frames: u32 = 30;

    // Font
    pub const font_atlas_size: u32 = 1024;
    pub const default_font_size: f32 = 24.0;
};
```

**Files to Create:**
- `src/ui/config.zig` (new configuration module)

**Files to Modify:**
- `src/ui/widgets.zig` - Replace magic numbers
- `src/ui/renderer_2d_proper.zig` - Replace magic numbers
- `src/ui/context.zig` - Replace magic numbers
- `src/ui.zig` - Export UIConfig

**Dependencies:** None

---

### Task 3.3: Split Large Widget File ✅
**Status:** 🔴 Not Started
**Priority:** Medium
**Estimated Time:** 4-5 hours
**Owner:** Unassigned

**Description:**
Split `widgets.zig` (1,283 lines) into separate modules for better organization and maintainability.

**Acceptance Criteria:**
- [ ] Create separate file for each widget type
- [ ] Maintain backward compatibility via re-exports
- [ ] Update imports throughout codebase
- [ ] Add module-level documentation
- [ ] Verify all tests still pass

**Proposed Structure:**
```
src/ui/widgets/
├── button.zig        (~100 lines)
├── checkbox.zig      (~100 lines)
├── slider.zig        (~120 lines)
├── text_input.zig    (~120 lines)
├── dropdown.zig      (~150 lines)
├── scroll_list.zig   (~250 lines)
├── progress_bar.zig  (~80 lines)
├── tab_bar.zig       (~120 lines)
├── panel.zig         (~80 lines)
└── label.zig         (~30 lines)
```

**Migration Strategy:**
1. Create `src/ui/widgets/` directory
2. Extract each widget to its own file
3. Update `src/ui/widgets.zig` to re-export all widgets
4. Keep tests in original widget files
5. Run full test suite to verify

**Files to Create:**
- `src/ui/widgets/button.zig`
- `src/ui/widgets/checkbox.zig`
- `src/ui/widgets/slider.zig`
- `src/ui/widgets/text_input.zig`
- `src/ui/widgets/dropdown.zig`
- `src/ui/widgets/scroll_list.zig`
- `src/ui/widgets/progress_bar.zig`
- `src/ui/widgets/tab_bar.zig`
- `src/ui/widgets/panel.zig`
- `src/ui/widgets/label.zig`

**Files to Modify:**
- `src/ui/widgets.zig` - Convert to re-export module

**Dependencies:** Task 3.2 (config module)

---

## Priority 4: DPI Scaling (Medium)

### Task 4.1: Complete DPI Scaling Implementation ✅
**Status:** 🔴 Not Started
**Priority:** Medium
**Estimated Time:** 6-8 hours
**Owner:** Unassigned

**Description:**
Complete the DPI scaling system or remove it if not needed. Currently uses `initMock()` which indicates incomplete implementation.

**Decision Required:**
- **Option A:** Complete DPI scaling implementation (recommended for multi-platform support)
- **Option B:** Remove DPI scaling system if not needed yet

**If Option A (Complete Implementation):**

**Acceptance Criteria:**
- [ ] Remove `initMock()` function
- [ ] Implement proper DPI detection per platform:
  - macOS: Use `SDL_GetDisplayContentScale()`
  - Linux: Use `SDL_GetDisplayContentScale()` or X11 DPI
  - Windows: Use `SDL_GetDisplayContentScale()` or Windows DPI API
- [ ] Add automatic UI scaling based on DPI
- [ ] Add DPI change detection (monitor switching)
- [ ] Test on high-DPI displays (Retina, 4K, etc.)
- [ ] Document DPI scaling behavior

**Files to Modify:**
- `src/ui/dpi.zig` - Complete implementation
- `src/ui/context.zig` - Remove mock, use real DPI detection
- `src/main.zig` - Pass window info to context

**If Option B (Remove DPI Scaling):**

**Acceptance Criteria:**
- [ ] Remove `src/ui/dpi.zig`
- [ ] Remove DPI scaling from context
- [ ] Remove DPI-related code from renderer
- [ ] Document decision in RESUME.md

**Dependencies:** None

**Recommendation:** Choose Option A to support high-DPI displays properly.

---

## Priority 5: Error Handling (Medium)

### Task 5.1: Add Error Logging for Silent Failures ✅
**Status:** 🔴 Not Started
**Priority:** Medium
**Estimated Time:** 2-3 hours
**Owner:** Unassigned

**Description:**
Add proper error logging for all cases where errors are currently caught and ignored with `catch {}`.

**Acceptance Criteria:**
- [ ] Identify all `catch {}` instances
- [ ] Add error logging for each case
- [ ] Determine appropriate recovery strategy per case
- [ ] Document error handling decisions

**Silent Error Locations:**
```zig
// context.zig:221
self.widget_states.put(id, state) catch {};

// context.zig:252
self.overlay_callbacks.append(self.allocator, callback) catch {
    render_fn(self, data); // Has fallback, but no logging
};

// widgets.zig:414 (dropdown)
ctx.dropdown_overlays.append(ctx.allocator, overlay) catch {};

// renderer_2d_proper.zig:548 (drawRect)
self.color_batch.addQuad(...) catch return;

// renderer_2d_proper.zig:598 (drawText)
self.texture_batch.addQuad(...) catch return;
```

**Error Handling Strategy:**
1. **Widget state updates** - Log warning, continue (non-critical)
2. **Overlay callbacks** - Log warning, use fallback (already implemented)
3. **Dropdown overlays** - Log error, skip dropdown rendering
4. **Batch additions** - Log error, skip geometry (already returns)

**Files to Modify:**
- `src/ui/context.zig:221` - Add error logging
- `src/ui/context.zig:252` - Add error logging
- `src/ui/widgets.zig:414` - Add error logging
- `src/ui/renderer_2d_proper.zig:548` - Add error logging (optional)
- `src/ui/renderer_2d_proper.zig:598` - Add error logging (optional)

**Dependencies:** Task 2.1 (logging system)

---

## Progress Tracking

### Overall Progress: 0/7 Tasks Complete (0%)

| Task | Priority | Status | Progress | Estimated Hours |
|------|----------|--------|----------|-----------------|
| 1.1 - Renderer Tests | Critical | 🔴 Not Started | 0% | 4-6 hours |
| 1.2 - Font Atlas Tests | High | 🔴 Not Started | 0% | 2-3 hours |
| 1.3 - Integration Tests | Medium | 🔴 Not Started | 0% | 3-4 hours |
| 2.1 - Logging System | High | 🔴 Not Started | 0% | 4-5 hours |
| 2.2 - Remove Debug Logging | High | 🔴 Not Started | 0% | 1-2 hours |
| 3.1 - Clean Up Renderers | High | 🔴 Not Started | 0% | 1 hour |
| 3.2 - Extract Magic Numbers | Medium | 🔴 Not Started | 0% | 3-4 hours |
| 3.3 - Split Widget File | Medium | 🔴 Not Started | 0% | 4-5 hours |
| 4.1 - Complete DPI Scaling | Medium | 🔴 Not Started | 0% | 6-8 hours |
| 5.1 - Error Logging | Medium | 🔴 Not Started | 0% | 2-3 hours |

**Total Estimated Time:** 30-45 hours (~1-2 weeks of dedicated work)

---

## Success Metrics

### Code Quality Targets

| Metric | Current | Target | Status |
|--------|---------|--------|--------|
| Test Coverage | ~15% | 70%+ | 🔴 |
| Lines per File | 1,283 max | <500 | 🔴 |
| Debug Logging in Hot Paths | 8+ instances | 0 | 🔴 |
| Magic Numbers | 20+ instances | 0 | 🔴 |
| Silent Error Handling | 5 instances | 0 | 🔴 |
| Overall QA Score | 7.2/10 | 8.5/10 | 🔴 |

---

## Implementation Order

### Week 1: Testing & Logging
1. **Day 1-2:** Task 2.1 - Implement logging system
2. **Day 2-3:** Task 2.2 - Remove debug logging from hot paths
3. **Day 3-5:** Task 1.1 - Add renderer tests

### Week 2: Code Cleanup
4. **Day 1:** Task 3.1 - Clean up renderer files
5. **Day 1:** Task 5.1 - Add error logging
6. **Day 2-3:** Task 3.2 - Extract magic numbers
7. **Day 3-5:** Task 3.3 - Split widget file

### Week 3: Polish
8. **Day 1-2:** Task 1.2 - Add font atlas tests
9. **Day 2-3:** Task 1.3 - Add integration tests
10. **Day 4-5:** Task 4.1 - Complete DPI scaling (if Option A)

---

## Out of Scope (Future Work)

These items are noted in the QA review but deferred to later:

- ⏸️ CI/CD setup for automated testing
- ⏸️ Cross-platform testing (Linux, Windows)
- ⏸️ Performance profiling infrastructure
- ⏸️ Visual regression testing
- ⏸️ API documentation generation
- ⏸️ Benchmark suite

---

## Notes & Decisions

### Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2025-11-13 | Prioritize testing first | Critical for preventing regressions |
| 2025-11-13 | Implement logging before cleanup | Needed for error handling task |
| TBD | DPI scaling: Complete vs Remove | Pending decision |

### Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking existing code during refactoring | High | Comprehensive test suite first |
| Time overrun on DPI scaling | Medium | Can defer if needed |
| Widget split causes import issues | Low | Keep re-export layer |

---

## Questions & Blockers

### Open Questions
1. **DPI Scaling:** Complete implementation or remove feature?
2. **Renderer Cleanup:** Keep legacy renderers with deprecation or remove entirely?
3. **Test Coverage Target:** Aim for 70% or 80%?

### Blockers
- None currently

---

## Review & Approval

| Reviewer | Status | Date | Comments |
|----------|--------|------|----------|
| TBD | ⏳ Pending | - | - |

---

**Last Updated:** 2025-11-13
**Next Review:** After Week 1 completion

---

## Quick Start

To begin implementation:

```bash
# 1. Start with logging system (foundation for other tasks)
# Create src/log.zig and implement LogLevel enum

# 2. Run existing tests to establish baseline
zig build test

# 3. Begin Task 1.1 (Renderer tests)
# Create test file: src/ui/renderer_2d_proper_test.zig

# 4. Continue with implementation order as outlined above
```

**Remember:** Commit after each completed task to maintain clean history.
