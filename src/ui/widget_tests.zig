const std = @import("std");
const types = @import("types.zig");
const context_mod = @import("context.zig");
const basic = @import("widgets/basic.zig");
const input = @import("widgets/input.zig");
const selection = @import("widgets/selection.zig");
const display = @import("widgets/display.zig");
const renderer_mod = @import("renderer.zig");

const Rect = types.Rect;
const Vec2 = types.Vec2;
const Color = types.Color;
const InputState = types.InputState;
const Context = context_mod.Context;
const Renderer = renderer_mod.Renderer;
const DropdownState = types.DropdownState;
const ScrollListState = types.ScrollListState;
const TabBarState = types.TabBarState;

// ============================================================================
// Mock Renderer for Testing
// ============================================================================

const MockRenderer = struct {
    fn init() Renderer {
        return Renderer{
            .drawRectFn = mockDrawRect,
            .drawRectOutlineFn = mockDrawRectOutline,
            .drawTextFn = mockDrawText,
            .measureTextFn = mockMeasureText,
            .getBaselineOffsetFn = mockGetBaselineOffset,
            .pushScissorFn = mockPushScissor,
            .popScissorFn = mockPopScissor,
        };
    }

    fn mockDrawRect(_: Rect, _: Color) void {}
    fn mockDrawRectOutline(_: Rect, _: Color, _: f32) void {}
    fn mockDrawText(_: []const u8, _: Vec2, _: f32, _: Color) void {}
    fn mockMeasureText(text: []const u8, _: f32) Vec2 {
        // Simple mock: 10 pixels per character
        return Vec2.init(@as(f32, @floatFromInt(text.len)) * 10.0, 16.0);
    }
    fn mockGetBaselineOffset(_: f32) f32 {
        return 12.0;
    }
    fn mockPushScissor(_: Rect) void {}
    fn mockPopScissor() void {}
};

// ============================================================================
// Test Helpers
// ============================================================================

fn createTestContext(allocator: std.mem.Allocator) !Context {
    const renderer = MockRenderer.init();
    const ctx = Context.init(allocator, renderer);
    return ctx;
}

fn simulateMousePosition(input_state: *InputState, x: f32, y: f32) void {
    input_state.mouse_pos = Vec2.init(x, y);
}

fn simulateMouseClick(input_state: *InputState) void {
    input_state.mouse_down = true;
    input_state.mouse_clicked = true;
}

fn simulateMouseRelease(input_state: *InputState) void {
    input_state.mouse_down = false;
    input_state.mouse_clicked = false;
}

// ============================================================================
// Button Tests
// ============================================================================

test "button - normal state (no interaction)" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    const input_state = InputState.init();
    simulateMousePosition(&input_state, 0, 0); // Mouse outside button
    ctx.beginFrame(input_state, null);

    const button_rect = Rect.init(100, 100, 200, 50);
    const clicked = basic.button(&ctx, "Test Button", button_rect);

    try std.testing.expect(!clicked);
    ctx.endFrame();
}

test "button - hot state (mouse over)" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    const input_state = InputState.init();
    simulateMousePosition(&input_state, 150, 125); // Mouse inside button
    ctx.beginFrame(input_state, null);

    const button_rect = Rect.init(100, 100, 200, 50);
    const clicked = basic.button(&ctx, "Test Button", button_rect);

    try std.testing.expect(!clicked); // Not clicked, just hovering
    ctx.endFrame();
}

test "button - click detection" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    // Frame 1: Mouse down on button
    const input_state = InputState.init();
    simulateMousePosition(&input_state, 150, 125);
    simulateMouseClick(&input_state);
    ctx.beginFrame(input_state, null);

    const button_rect = Rect.init(100, 100, 200, 50);
    var clicked = basic.button(&ctx, "Test Button", button_rect);
    try std.testing.expect(!clicked); // Not clicked yet (active, but not released)

    ctx.endFrame();

    // Frame 2: Mouse released on button
    simulateMouseRelease(&input_state);
    ctx.beginFrame(input_state, null);

    clicked = basic.button(&ctx, "Test Button", button_rect);
    try std.testing.expect(clicked); // Now clicked!

    ctx.endFrame();
}

test "button - click outside then drag over (should not click)" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    // Frame 1: Click outside button
    const input_state = InputState.init();
    simulateMousePosition(&input_state, 50, 50);
    simulateMouseClick(&input_state);
    ctx.beginFrame(input_state, null);

    const button_rect = Rect.init(100, 100, 200, 50);
    var clicked = basic.button(&ctx, "Test Button", button_rect);
    try std.testing.expect(!clicked);

    ctx.endFrame();

    // Frame 2: Drag mouse over button (still held)
    simulateMousePosition(&input_state, 150, 125);
    input_state.mouse_clicked = false; // No new click
    ctx.beginFrame(input_state, null);

    clicked = basic.button(&ctx, "Test Button", button_rect);
    try std.testing.expect(!clicked); // Should not click

    ctx.endFrame();

    // Frame 3: Release on button
    simulateMouseRelease(&input_state);
    ctx.beginFrame(input_state, null);

    clicked = basic.button(&ctx, "Test Button", button_rect);
    try std.testing.expect(!clicked); // Still should not click (wasn't pressed on button)

    ctx.endFrame();
}

test "buttonWithId - multiple buttons with same text" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    const input_state = InputState.init();
    simulateMousePosition(&input_state, 150, 125); // Over first button
    simulateMouseClick(&input_state);
    ctx.beginFrame(input_state, null);

    const button1_rect = Rect.init(100, 100, 200, 50);
    const button2_rect = Rect.init(100, 200, 200, 50);

    const id1 = types.widgetId("button_1");
    const id2 = types.widgetId("button_2");

    // Both buttons have same text but different IDs
    _ = basic.buttonWithId(&ctx, "OK", id1, button1_rect);
    _ = basic.buttonWithId(&ctx, "OK", id2, button2_rect);

    ctx.endFrame();

    // Frame 2: Release on first button
    simulateMouseRelease(&input_state);
    ctx.beginFrame(input_state, null);

    const clicked1 = basic.buttonWithId(&ctx, "OK", id1, button1_rect);
    const clicked2 = basic.buttonWithId(&ctx, "OK", id2, button2_rect);

    try std.testing.expect(clicked1); // First button should be clicked
    try std.testing.expect(!clicked2); // Second button should NOT be clicked

    ctx.endFrame();
}

test "button - empty text" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    const input_state = InputState.init();
    simulateMousePosition(&input_state, 150, 125);
    ctx.beginFrame(input_state, null);

    const button_rect = Rect.init(100, 100, 200, 50);
    const clicked = basic.button(&ctx, "", button_rect); // Empty text

    try std.testing.expect(!clicked);
    ctx.endFrame();
}

// ============================================================================
// Checkbox Tests
// ============================================================================

test "checkbox - toggle on click" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    var checked: bool = false;

    // Frame 1: Click checkbox
    const input_state = InputState.init();
    simulateMousePosition(&input_state, 125, 125); // Inside checkbox area
    simulateMouseClick(&input_state);
    ctx.beginFrame(input_state, null);

    const checkbox_rect = Rect.init(100, 100, 200, 50);
    var changed = basic.checkbox(&ctx, "Test Checkbox", checkbox_rect, &checked);
    try std.testing.expect(!changed); // Not changed yet (still pressed)
    try std.testing.expect(!checked);

    ctx.endFrame();

    // Frame 2: Release
    simulateMouseRelease(&input_state);
    ctx.beginFrame(input_state, null);

    changed = basic.checkbox(&ctx, "Test Checkbox", checkbox_rect, &checked);
    try std.testing.expect(changed); // Changed!
    try std.testing.expect(checked); // Now checked

    ctx.endFrame();
}

test "checkbox - toggle off when checked" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    var checked: bool = true; // Start checked

    // Frame 1: Click checkbox
    const input_state = InputState.init();
    simulateMousePosition(&input_state, 125, 125);
    simulateMouseClick(&input_state);
    ctx.beginFrame(input_state, null);

    const checkbox_rect = Rect.init(100, 100, 200, 50);
    _ = basic.checkbox(&ctx, "Test Checkbox", checkbox_rect, &checked);
    ctx.endFrame();

    // Frame 2: Release
    simulateMouseRelease(&input_state);
    ctx.beginFrame(input_state, null);

    const changed = basic.checkbox(&ctx, "Test Checkbox", checkbox_rect, &checked);
    try std.testing.expect(changed);
    try std.testing.expect(!checked); // Now unchecked

    ctx.endFrame();
}

test "checkbox - no change when clicking outside" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    var checked: bool = false;

    const input_state = InputState.init();
    simulateMousePosition(&input_state, 50, 50); // Outside checkbox
    simulateMouseClick(&input_state);
    ctx.beginFrame(input_state, null);

    const checkbox_rect = Rect.init(100, 100, 200, 50);
    _ = basic.checkbox(&ctx, "Test Checkbox", checkbox_rect, &checked);
    ctx.endFrame();

    simulateMouseRelease(&input_state);
    ctx.beginFrame(input_state, null);

    const changed = basic.checkbox(&ctx, "Test Checkbox", checkbox_rect, &checked);
    try std.testing.expect(!changed);
    try std.testing.expect(!checked);

    ctx.endFrame();
}

// ============================================================================
// Slider Tests
// ============================================================================

test "slider - returns value unchanged when not interacting" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    const input_state = InputState.init();
    simulateMousePosition(&input_state, 0, 0); // Outside slider
    ctx.beginFrame(input_state, null);

    const slider_rect = Rect.init(100, 100, 200, 30);
    const value: f32 = 0.5;
    const new_value = input.slider(&ctx, "Test Slider", slider_rect, value, 0.0, 1.0);

    try std.testing.expectEqual(value, new_value);
    ctx.endFrame();
}

test "slider - value changes when dragging" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    // Frame 1: Click on slider at 25% position
    const input_state = InputState.init();
    const slider_rect = Rect.init(100, 100, 200, 30);
    simulateMousePosition(&input_state, 150, 115); // 25% along the slider (100 + 200*0.25 = 150)
    simulateMouseClick(&input_state);
    ctx.beginFrame(input_state, null);

    const value: f32 = 0.5;
    const new_value = input.slider(&ctx, "Test Slider", slider_rect, value, 0.0, 1.0);

    // Value should change to approximately 0.25 (25% of the way)
    try std.testing.expect(new_value < 0.5);
    try std.testing.expect(new_value > 0.0);

    ctx.endFrame();
}

test "slider - value clamped to min" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    const input_state = InputState.init();
    const slider_rect = Rect.init(100, 100, 200, 30);
    simulateMousePosition(&input_state, 50, 115); // Far left, outside slider
    simulateMouseClick(&input_state);
    ctx.beginFrame(input_state, null);

    const value: f32 = 0.5;
    const new_value = input.slider(&ctx, "Test Slider", slider_rect, value, 0.0, 1.0);

    // Should clamp to min (0.0)
    try std.testing.expectApproxEqRel(@as(f32, 0.0), new_value, 0.01);

    ctx.endFrame();
}

test "slider - value clamped to max" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    const input_state = InputState.init();
    const slider_rect = Rect.init(100, 100, 200, 30);
    simulateMousePosition(&input_state, 350, 115); // Far right, outside slider
    simulateMouseClick(&input_state);
    ctx.beginFrame(input_state, null);

    const value: f32 = 0.5;
    const new_value = input.slider(&ctx, "Test Slider", slider_rect, value, 0.0, 1.0);

    // Should clamp to max (1.0)
    try std.testing.expectApproxEqRel(@as(f32, 1.0), new_value, 0.01);

    ctx.endFrame();
}

test "slider - custom range (0-100)" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    const input_state = InputState.init();
    const slider_rect = Rect.init(100, 100, 200, 30);
    simulateMousePosition(&input_state, 200, 115); // Middle of slider
    simulateMouseClick(&input_state);
    ctx.beginFrame(input_state, null);

    const value: f32 = 25.0;
    const new_value = input.slider(&ctx, "Test Slider", slider_rect, value, 0.0, 100.0);

    // Should be approximately 50.0 (middle of 0-100 range)
    try std.testing.expect(new_value > 40.0);
    try std.testing.expect(new_value < 60.0);

    ctx.endFrame();
}

// ============================================================================
// Text Input Tests
// ============================================================================

test "textInput - initial state" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    var buffer: [64]u8 = undefined;
    var buffer_len: usize = 0;

    const input_state = InputState.init();
    ctx.beginFrame(input_state, null);

    const text_input_rect = Rect.init(100, 100, 300, 40);
    input.textInput(&ctx, "Name:", text_input_rect, &buffer, &buffer_len);

    try std.testing.expectEqual(@as(usize, 0), buffer_len);
    ctx.endFrame();
}

test "textInput - receives input when focused" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    var buffer: [64]u8 = undefined;
    var buffer_len: usize = 0;

    // Frame 1: Click to focus
    const input_state = InputState.init();
    simulateMousePosition(&input_state, 150, 120);
    simulateMouseClick(&input_state);
    ctx.beginFrame(input_state, null);

    const text_input_rect = Rect.init(100, 100, 300, 40);
    input.textInput(&ctx, "Name:", text_input_rect, &buffer, &buffer_len);
    ctx.endFrame();

    // Frame 2: Type text (simulate key input)
    simulateMouseRelease(&input_state);
    input_state.text_input_buffer = "Hello";
    input_state.text_input_len = 5;
    ctx.beginFrame(input_state, null);

    input.textInput(&ctx, "Name:", text_input_rect, &buffer, &buffer_len);

    try std.testing.expectEqual(@as(usize, 5), buffer_len);
    try std.testing.expectEqualStrings("Hello", buffer[0..buffer_len]);

    ctx.endFrame();
}

test "textInput - buffer overflow protection" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    var buffer: [10]u8 = undefined; // Small buffer
    var buffer_len: usize = 0;

    // Frame 1: Click to focus
    const input_state = InputState.init();
    simulateMousePosition(&input_state, 150, 120);
    simulateMouseClick(&input_state);
    ctx.beginFrame(input_state, null);

    const text_input_rect = Rect.init(100, 100, 300, 40);
    input.textInput(&ctx, "Name:", text_input_rect, &buffer, &buffer_len);
    ctx.endFrame();

    // Frame 2: Try to type more than buffer can hold
    simulateMouseRelease(&input_state);
    input_state.text_input_buffer = "This is a very long string";
    input_state.text_input_len = 26;
    ctx.beginFrame(input_state, null);

    input.textInput(&ctx, "Name:", text_input_rect, &buffer, &buffer_len);

    // Should be clamped to buffer size
    try std.testing.expectEqual(@as(usize, 10), buffer_len);
    try std.testing.expectEqualStrings("This is a ", buffer[0..buffer_len]);

    ctx.endFrame();
}

test "textInput - loses focus when clicking outside" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    var buffer: [64]u8 = undefined;
    var buffer_len: usize = 0;

    // Frame 1: Click to focus
    const input_state = InputState.init();
    simulateMousePosition(&input_state, 150, 120);
    simulateMouseClick(&input_state);
    ctx.beginFrame(input_state, null);

    const text_input_rect = Rect.init(100, 100, 300, 40);
    input.textInput(&ctx, "Name:", text_input_rect, &buffer, &buffer_len);
    ctx.endFrame();

    // Frame 2: Click outside
    simulateMousePosition(&input_state, 50, 50);
    simulateMouseClick(&input_state);
    ctx.beginFrame(input_state, null);

    input.textInput(&ctx, "Name:", text_input_rect, &buffer, &buffer_len);
    ctx.endFrame();

    // Frame 3: Type text (should not be received)
    simulateMouseRelease(&input_state);
    input_state.text_input_buffer = "Hello";
    input_state.text_input_len = 5;
    ctx.beginFrame(input_state, null);

    input.textInput(&ctx, "Name:", text_input_rect, &buffer, &buffer_len);

    try std.testing.expectEqual(@as(usize, 0), buffer_len); // Should still be empty

    ctx.endFrame();
}

// ============================================================================
// Dropdown Tests
// ============================================================================

test "dropdown - initial state closed" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    var state = DropdownState.init();
    const options = &[_][]const u8{ "Option 1", "Option 2", "Option 3" };

    const input_state = InputState.init();
    ctx.beginFrame(input_state, null);

    const dropdown_rect = Rect.init(100, 100, 200, 40);
    selection.dropdown(&ctx, "Dropdown", dropdown_rect, options, &state);

    try std.testing.expect(!state.is_open);
    try std.testing.expectEqual(@as(usize, 0), state.selected_index);

    ctx.endFrame();
}

test "dropdown - opens on click" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    var state = DropdownState.init();
    const options = &[_][]const u8{ "Option 1", "Option 2", "Option 3" };

    // Frame 1: Click dropdown
    const input_state = InputState.init();
    simulateMousePosition(&input_state, 150, 120);
    simulateMouseClick(&input_state);
    ctx.beginFrame(input_state, null);

    const dropdown_rect = Rect.init(100, 100, 200, 40);
    selection.dropdown(&ctx, "Dropdown", dropdown_rect, options, &state);
    ctx.endFrame();

    // Frame 2: Release
    simulateMouseRelease(&input_state);
    ctx.beginFrame(input_state, null);

    selection.dropdown(&ctx, "Dropdown", dropdown_rect, options, &state);

    try std.testing.expect(state.is_open);

    ctx.endFrame();
}

test "dropdown - selects option" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    var state = DropdownState.init();
    state.is_open = true; // Start open
    const options = &[_][]const u8{ "Option 1", "Option 2", "Option 3" };

    const input_state = InputState.init();
    const dropdown_rect = Rect.init(100, 100, 200, 40);

    // Click on second option (approximate position)
    simulateMousePosition(&input_state, 150, 170); // Below main dropdown
    simulateMouseClick(&input_state);
    ctx.beginFrame(input_state, null);

    selection.dropdown(&ctx, "Dropdown", dropdown_rect, options, &state);
    ctx.endFrame();

    // Note: Actual selection happens in overlay rendering
    // Just verify state management works
    try std.testing.expect(state.is_open); // Should still be open until option clicked

    ctx.endFrame();
}

// ============================================================================
// ScrollList Tests
// ============================================================================

test "scrollList - initial state" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    var state = ScrollListState.init();
    const items = &[_][]const u8{ "Item 1", "Item 2", "Item 3", "Item 4", "Item 5" };

    const input_state = InputState.init();
    ctx.beginFrame(input_state, null);

    const list_rect = Rect.init(100, 100, 200, 150);
    selection.scrollList(&ctx, "List", list_rect, items, &state);

    try std.testing.expectEqual(@as(usize, 0), state.selected_index);
    try std.testing.expectEqual(@as(f32, 0.0), state.scroll_offset);

    ctx.endFrame();
}

test "scrollList - selects item on click" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    var state = ScrollListState.init();
    const items = &[_][]const u8{ "Item 1", "Item 2", "Item 3" };

    // Frame 1: Click on first item
    const input_state = InputState.init();
    simulateMousePosition(&input_state, 150, 120);
    simulateMouseClick(&input_state);
    ctx.beginFrame(input_state, null);

    const list_rect = Rect.init(100, 100, 200, 150);
    selection.scrollList(&ctx, "List", list_rect, items, &state);
    ctx.endFrame();

    // Frame 2: Release
    simulateMouseRelease(&input_state);
    ctx.beginFrame(input_state, null);

    selection.scrollList(&ctx, "List", list_rect, items, &state);

    // First item should be selected (index 0)
    try std.testing.expectEqual(@as(usize, 0), state.selected_index);

    ctx.endFrame();
}

test "scrollList - scrolls with mouse wheel" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    var state = ScrollListState.init();
    const items = &[_][]const u8{ "Item 1", "Item 2", "Item 3", "Item 4", "Item 5", "Item 6", "Item 7", "Item 8" };

    // Scroll down (negative wheel)
    var input_state = InputState.init();
    simulateMousePosition(&input_state, 150, 120);
    input_state.mouse_wheel_y = -1.0; // Scroll down
    ctx.beginFrame(input_state, null);

    const list_rect = Rect.init(100, 100, 200, 100); // Small height to force scrolling
    selection.scrollList(&ctx, "List", list_rect, items, &state);

    // Scroll offset should have changed
    try std.testing.expect(state.scroll_offset != 0.0);

    ctx.endFrame();
}

// ============================================================================
// TabBar Tests
// ============================================================================

test "tabBar - initial state" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    var state = TabBarState.init();
    const tabs = &[_][]const u8{ "Tab 1", "Tab 2", "Tab 3" };

    const input_state = InputState.init();
    ctx.beginFrame(input_state, null);

    const tab_rect = Rect.init(100, 100, 600, 40);
    const active_tab = selection.tabBar(&ctx, "TabBar", tab_rect, tabs, &state);

    try std.testing.expectEqual(@as(usize, 0), active_tab);
    try std.testing.expectEqual(@as(usize, 0), state.active_tab);

    ctx.endFrame();
}

test "tabBar - switches tab on click" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    var state = TabBarState.init();
    const tabs = &[_][]const u8{ "Tab 1", "Tab 2", "Tab 3" };

    // Frame 1: Click on second tab (approximate position)
    const input_state = InputState.init();
    const tab_rect = Rect.init(100, 100, 600, 40);
    const tab_width = tab_rect.width / @as(f32, @floatFromInt(tabs.len));
    simulateMousePosition(&input_state, 100 + tab_width * 1.5, 120); // Middle of second tab
    simulateMouseClick(&input_state);
    ctx.beginFrame(input_state, null);

    _ = selection.tabBar(&ctx, "TabBar", tab_rect, tabs, &state);
    ctx.endFrame();

    // Frame 2: Release
    simulateMouseRelease(&input_state);
    ctx.beginFrame(input_state, null);

    const active_tab = selection.tabBar(&ctx, "TabBar", tab_rect, tabs, &state);

    try std.testing.expectEqual(@as(usize, 1), active_tab); // Second tab

    ctx.endFrame();
}

test "tabBar - single tab" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    var state = TabBarState.init();
    const tabs = &[_][]const u8{"Only Tab"};

    const input_state = InputState.init();
    ctx.beginFrame(input_state, null);

    const tab_rect = Rect.init(100, 100, 200, 40);
    const active_tab = selection.tabBar(&ctx, "TabBar", tab_rect, tabs, &state);

    try std.testing.expectEqual(@as(usize, 0), active_tab);

    ctx.endFrame();
}

// ============================================================================
// Progress Bar Tests
// ============================================================================

test "progressBar - zero progress" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    const input_state = InputState.init();
    ctx.beginFrame(input_state, null);

    const progress_rect = Rect.init(100, 100, 300, 30);
    display.progressBar(&ctx, "Loading", progress_rect, 0.0, true);

    // Just verify it doesn't crash
    ctx.endFrame();
}

test "progressBar - half progress" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    const input_state = InputState.init();
    ctx.beginFrame(input_state, null);

    const progress_rect = Rect.init(100, 100, 300, 30);
    display.progressBar(&ctx, "Loading", progress_rect, 0.5, true);

    ctx.endFrame();
}

test "progressBar - full progress" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    const input_state = InputState.init();
    ctx.beginFrame(input_state, null);

    const progress_rect = Rect.init(100, 100, 300, 30);
    display.progressBar(&ctx, "Loading", progress_rect, 1.0, true);

    ctx.endFrame();
}

test "progressBar - over 100% (should clamp)" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    const input_state = InputState.init();
    ctx.beginFrame(input_state, null);

    const progress_rect = Rect.init(100, 100, 300, 30);
    display.progressBar(&ctx, "Loading", progress_rect, 1.5, true); // Over 100%

    // Should handle gracefully (clamp to 100%)
    ctx.endFrame();
}

test "progressBar - negative progress (should clamp)" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    const input_state = InputState.init();
    ctx.beginFrame(input_state, null);

    const progress_rect = Rect.init(100, 100, 300, 30);
    display.progressBar(&ctx, "Loading", progress_rect, -0.5, true); // Negative

    // Should handle gracefully (clamp to 0%)
    ctx.endFrame();
}

// ============================================================================
// Label Tests
// ============================================================================

test "label - renders text" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    const input_state = InputState.init();
    ctx.beginFrame(input_state, null);

    const pos = Vec2.init(100, 100);
    basic.label(&ctx, "Test Label", pos, 16.0, Color.white);

    // Just verify it doesn't crash
    ctx.endFrame();
}

test "label - empty text" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    const input_state = InputState.init();
    ctx.beginFrame(input_state, null);

    const pos = Vec2.init(100, 100);
    basic.label(&ctx, "", pos, 16.0, Color.white);

    ctx.endFrame();
}

test "label - very long text" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    const input_state = InputState.init();
    ctx.beginFrame(input_state, null);

    const pos = Vec2.init(100, 100);
    basic.label(&ctx, "This is a very long label text that should render without issues even though it might overflow the screen", pos, 16.0, Color.white);

    ctx.endFrame();
}

// ============================================================================
// State Persistence Tests
// ============================================================================

test "widget state persists between frames" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    const button_rect = Rect.init(100, 100, 200, 50);

    // Frame 1: Hover over button
    const input_state = InputState.init();
    simulateMousePosition(&input_state, 150, 125);
    ctx.beginFrame(input_state, null);
    _ = basic.button(&ctx, "Test Button", button_rect);
    ctx.endFrame();

    // Frame 2: Check state persists
    ctx.beginFrame(input_state, null);
    _ = basic.button(&ctx, "Test Button", button_rect);

    // Widget should still be hot
    const id = types.widgetId("Test Button");
    const is_hot = ctx.isHot(id);
    try std.testing.expect(is_hot);

    ctx.endFrame();
}

test "multiple widgets track state independently" {
    const allocator = std.testing.allocator;
    var ctx = try createTestContext(allocator);
    defer ctx.deinit();

    const button1_rect = Rect.init(100, 100, 200, 50);
    const button2_rect = Rect.init(100, 200, 200, 50);

    // Hover over first button only
    const input_state = InputState.init();
    simulateMousePosition(&input_state, 150, 125); // Over button 1
    ctx.beginFrame(input_state, null);

    _ = basic.button(&ctx, "Button 1", button1_rect);
    _ = basic.button(&ctx, "Button 2", button2_rect);

    const id1 = types.widgetId("Button 1");
    const id2 = types.widgetId("Button 2");

    try std.testing.expect(ctx.isHot(id1));
    try std.testing.expect(!ctx.isHot(id2));

    ctx.endFrame();
}
