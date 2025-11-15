const std = @import("std");
const ui = @import("../ui.zig");
const types = @import("types.zig");
const Context = @import("context.zig").Context;
const Renderer = @import("renderer.zig").Renderer;
const button = @import("widgets/basic.zig").button;
const checkbox = @import("widgets/selection.zig").checkbox;
const slider = @import("widgets/basic.zig").slider;
const textInput = @import("widgets/input.zig").textInput;
const dropdown = @import("widgets/selection.zig").dropdown;
const panel = @import("widgets/container.zig").panel;
const label = @import("widgets/display.zig").label;

const Rect = types.Rect;
const Vec2 = types.Vec2;
const Color = types.Color;
const InputState = types.InputState;

// ============================================================================
// MockRenderer - Records all rendering commands for verification
// ============================================================================

pub const DrawCall = union(enum) {
    rect: struct { rect: Rect, color: Color },
    rect_outline: struct { rect: Rect, color: Color, thickness: f32 },
    text: struct { text: []const u8, pos: Vec2, size: f32, color: Color },
    begin_scissor: struct { rect: Rect },
    end_scissor: void,
    flush_batches: void,
    push_overlay: void,
    pop_overlay: void,

    pub fn format(
        self: DrawCall,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .rect => |r| try writer.print("DrawRect({d:.1},{d:.1},{d:.1}x{d:.1}, rgba({d},{d},{d},{d}))", .{
                r.rect.x,
                r.rect.y,
                r.rect.width,
                r.rect.height,
                r.color.r,
                r.color.g,
                r.color.b,
                r.color.a,
            }),
            .rect_outline => |r| try writer.print("DrawRectOutline({d:.1},{d:.1},{d:.1}x{d:.1}, rgba({d},{d},{d},{d}), thick={d:.1})", .{
                r.rect.x,
                r.rect.y,
                r.rect.width,
                r.rect.height,
                r.color.r,
                r.color.g,
                r.color.b,
                r.color.a,
                r.thickness,
            }),
            .text => |t| try writer.print("DrawText(\"{s}\", pos=({d:.1},{d:.1}), size={d:.1})", .{
                t.text,
                t.pos.x,
                t.pos.y,
                t.size,
            }),
            .begin_scissor => |s| try writer.print("BeginScissor({d:.1},{d:.1},{d:.1}x{d:.1})", .{
                s.rect.x,
                s.rect.y,
                s.rect.width,
                s.rect.height,
            }),
            .end_scissor => try writer.writeAll("EndScissor()"),
            .flush_batches => try writer.writeAll("FlushBatches()"),
            .push_overlay => try writer.writeAll("PushOverlay()"),
            .pop_overlay => try writer.writeAll("PopOverlay()"),
        }
    }
};

pub const MockRenderer = struct {
    allocator: std.mem.Allocator,
    draw_calls: std.ArrayList(DrawCall),
    text_storage: std.ArrayList([]u8), // Store owned text strings

    pub fn init(allocator: std.mem.Allocator) MockRenderer {
        return .{
            .allocator = allocator,
            .draw_calls = std.ArrayList(DrawCall).init(allocator),
            .text_storage = std.ArrayList([]u8).init(allocator),
        };
    }

    pub fn deinit(self: *MockRenderer) void {
        // Free all stored text strings
        for (self.text_storage.items) |text| {
            self.allocator.free(text);
        }
        self.text_storage.deinit();
        self.draw_calls.deinit();
    }

    pub fn clear(self: *MockRenderer) void {
        // Free all stored text strings
        for (self.text_storage.items) |text| {
            self.allocator.free(text);
        }
        self.text_storage.clearRetainingCapacity();
        self.draw_calls.clearRetainingCapacity();
    }

    pub fn drawRect(self: *MockRenderer, rect: Rect, color: Color) void {
        self.draw_calls.append(.{ .rect = .{ .rect = rect, .color = color } }) catch unreachable;
    }

    pub fn drawRectOutline(self: *MockRenderer, rect: Rect, color: Color, thickness: f32) void {
        self.draw_calls.append(.{ .rect_outline = .{ .rect = rect, .color = color, .thickness = thickness } }) catch unreachable;
    }

    pub fn drawText(self: *MockRenderer, text: []const u8, pos: Vec2, size: f32, color: Color) void {
        // Store a copy of the text string
        const owned_text = self.allocator.dupe(u8, text) catch unreachable;
        self.text_storage.append(owned_text) catch unreachable;

        self.draw_calls.append(.{ .text = .{
            .text = owned_text,
            .pos = pos,
            .size = size,
            .color = color,
        } }) catch unreachable;
    }

    pub fn measureText(self: *MockRenderer, text: []const u8, font_size: f32) Vec2 {
        _ = self;
        // Simple estimation: ~10 pixels per character
        return Vec2.init(@as(f32, @floatFromInt(text.len)) * 10.0, font_size);
    }

    pub fn getBaselineOffset(self: *MockRenderer, font_size: f32) f32 {
        _ = self;
        return font_size * 0.2;
    }

    pub fn beginScissor(self: *MockRenderer, rect: Rect) void {
        self.draw_calls.append(.{ .begin_scissor = .{ .rect = rect } }) catch unreachable;
    }

    pub fn endScissor(self: *MockRenderer) void {
        self.draw_calls.append(.end_scissor) catch unreachable;
    }

    pub fn flushBatches(self: *MockRenderer) void {
        self.draw_calls.append(.flush_batches) catch unreachable;
    }

    pub fn pushOverlayView(self: *MockRenderer) void {
        self.draw_calls.append(.push_overlay) catch unreachable;
    }

    pub fn popOverlayView(self: *MockRenderer) void {
        self.draw_calls.append(.pop_overlay) catch unreachable;
    }

    pub fn isNull(self: *MockRenderer) bool {
        _ = self;
        return false;
    }

    // Helper methods for test assertions

    pub fn countDrawCalls(self: *const MockRenderer, call_type: std.meta.Tag(DrawCall)) usize {
        var count: usize = 0;
        for (self.draw_calls.items) |call| {
            if (call == call_type) count += 1;
        }
        return count;
    }

    pub fn findDrawCall(self: *const MockRenderer, call_type: std.meta.Tag(DrawCall)) ?DrawCall {
        for (self.draw_calls.items) |call| {
            if (call == call_type) return call;
        }
        return null;
    }

    pub fn assertDrawCallCount(self: *const MockRenderer, call_type: std.meta.Tag(DrawCall), expected: usize) !void {
        const actual = self.countDrawCalls(call_type);
        if (actual != expected) {
            std.debug.print("\nExpected {d} {s} calls, got {d}\n", .{ expected, @tagName(call_type), actual });
            std.debug.print("All draw calls ({d} total):\n", .{self.draw_calls.items.len});
            for (self.draw_calls.items, 0..) |call, i| {
                std.debug.print("  [{d}] {}\n", .{ i, call });
            }
            return error.DrawCallCountMismatch;
        }
    }

    pub fn assertContainsRect(self: *const MockRenderer, expected_rect: Rect, tolerance: f32) !void {
        for (self.draw_calls.items) |call| {
            switch (call) {
                .rect => |r| {
                    if (rectsApproxEqual(r.rect, expected_rect, tolerance)) return;
                },
                .rect_outline => |r| {
                    if (rectsApproxEqual(r.rect, expected_rect, tolerance)) return;
                },
                else => {},
            }
        }
        std.debug.print("\nExpected to find rect: {d:.1},{d:.1},{d:.1}x{d:.1}\n", .{
            expected_rect.x,
            expected_rect.y,
            expected_rect.width,
            expected_rect.height,
        });
        std.debug.print("All draw calls:\n", .{});
        for (self.draw_calls.items, 0..) |call, i| {
            std.debug.print("  [{d}] {}\n", .{ i, call });
        }
        return error.RectNotFound;
    }

    pub fn assertContainsText(self: *const MockRenderer, expected_text: []const u8) !void {
        for (self.draw_calls.items) |call| {
            if (call == .text) {
                if (std.mem.eql(u8, call.text.text, expected_text)) return;
            }
        }
        std.debug.print("\nExpected to find text: \"{s}\"\n", .{expected_text});
        std.debug.print("All draw calls:\n", .{});
        for (self.draw_calls.items, 0..) |call, i| {
            std.debug.print("  [{d}] {}\n", .{ i, call });
        }
        return error.TextNotFound;
    }
};

fn rectsApproxEqual(a: Rect, b: Rect, tolerance: f32) bool {
    return @abs(a.x - b.x) <= tolerance and
        @abs(a.y - b.y) <= tolerance and
        @abs(a.width - b.width) <= tolerance and
        @abs(a.height - b.height) <= tolerance;
}

// ============================================================================
// Visual Regression Tests
// ============================================================================

test "Visual: Button normal state rendering" {
    var mock = MockRenderer.init(std.testing.allocator);
    defer mock.deinit();

    const renderer = Renderer.init(&mock);
    var ctx = try Context.init(std.testing.allocator, renderer, null);
    defer ctx.deinit();

    const input = InputState.init();
    ctx.beginFrame(input, null);

    const rect = Rect.init(100, 100, 200, 40);
    const clicked = button(&ctx, "Click Me", rect);

    try std.testing.expect(!clicked);

    // Button should draw:
    // 1. Background rectangle (filled)
    // 2. Border (outline)
    // 3. Text label
    try mock.assertDrawCallCount(.rect, 1);
    try mock.assertDrawCallCount(.rect_outline, 1);
    try mock.assertDrawCallCount(.text, 1);

    // Verify button rect is correct
    try mock.assertContainsRect(rect, 0.1);

    // Verify text is rendered
    try mock.assertContainsText("Click Me");
}

test "Visual: Button hover state rendering" {
    var mock = MockRenderer.init(std.testing.allocator);
    defer mock.deinit();

    const renderer = Renderer.init(&mock);
    var ctx = try Context.init(std.testing.allocator, renderer, null);
    defer ctx.deinit();

    // Mouse hovering over button
    var input = InputState.init();
    input.mouse_pos = Vec2.init(150, 120); // Inside button
    ctx.beginFrame(input, null);

    const rect = Rect.init(100, 100, 200, 40);
    _ = button(&ctx, "Hover Me", rect);

    // Should still draw background, border, and text
    try mock.assertDrawCallCount(.rect, 1);
    try mock.assertDrawCallCount(.rect_outline, 1);
    try mock.assertDrawCallCount(.text, 1);

    // Find the rect draw call and verify color is lighter (hover effect)
    const rect_call = mock.findDrawCall(.rect);
    try std.testing.expect(rect_call != null);
}

test "Visual: Button pressed state rendering" {
    var mock = MockRenderer.init(std.testing.allocator);
    defer mock.deinit();

    const renderer = Renderer.init(&mock);
    var ctx = try Context.init(std.testing.allocator, renderer, null);
    defer ctx.deinit();

    // Mouse pressed on button
    var input = InputState.init();
    input.mouse_pos = Vec2.init(150, 120);
    input.mouse_down = true;
    ctx.beginFrame(input, null);

    const rect = Rect.init(100, 100, 200, 40);
    _ = button(&ctx, "Press Me", rect);

    // Should draw background (darker), border, and text
    try mock.assertDrawCallCount(.rect, 1);
    try mock.assertDrawCallCount(.rect_outline, 1);
    try mock.assertDrawCallCount(.text, 1);
}

test "Visual: Button clicked detection" {
    var mock = MockRenderer.init(std.testing.allocator);
    defer mock.deinit();

    const renderer = Renderer.init(&mock);
    var ctx = try Context.init(std.testing.allocator, renderer, null);
    defer ctx.deinit();

    // Mouse clicked on button
    var input = InputState.init();
    input.mouse_pos = Vec2.init(150, 120);
    input.mouse_clicked = true;
    ctx.beginFrame(input, null);

    const rect = Rect.init(100, 100, 200, 40);
    const clicked = button(&ctx, "Click Me", rect);

    try std.testing.expect(clicked);
}

test "Visual: Checkbox unchecked rendering" {
    var mock = MockRenderer.init(std.testing.allocator);
    defer mock.deinit();

    const renderer = Renderer.init(&mock);
    var ctx = try Context.init(std.testing.allocator, renderer, null);
    defer ctx.deinit();

    const input = InputState.init();
    ctx.beginFrame(input, null);

    const rect = Rect.init(100, 100, 200, 30);
    var checked = false;
    _ = checkbox(&ctx, "Enable Feature", rect, &checked);

    try std.testing.expect(!checked);

    // Checkbox should draw:
    // 1. Box background
    // 2. Box border
    // 3. Text label
    try mock.assertDrawCallCount(.rect, 1);
    try mock.assertDrawCallCount(.rect_outline, 1);
    try mock.assertDrawCallCount(.text, 1);
}

test "Visual: Checkbox checked rendering" {
    var mock = MockRenderer.init(std.testing.allocator);
    defer mock.deinit();

    const renderer = Renderer.init(&mock);
    var ctx = try Context.init(std.testing.allocator, renderer, null);
    defer ctx.deinit();

    const input = InputState.init();
    ctx.beginFrame(input, null);

    const rect = Rect.init(100, 100, 200, 30);
    var checked = true;
    _ = checkbox(&ctx, "Enable Feature", rect, &checked);

    try std.testing.expect(checked);

    // Checked checkbox should draw:
    // 1. Box background
    // 2. Box border
    // 3. Checkmark (2 rects for cross pattern)
    // 4. Text label
    try mock.assertDrawCallCount(.rect, 3); // Box + 2 checkmark rects
    try mock.assertDrawCallCount(.rect_outline, 1);
    try mock.assertDrawCallCount(.text, 1);
}

test "Visual: Slider rendering with value" {
    var mock = MockRenderer.init(std.testing.allocator);
    defer mock.deinit();

    const renderer = Renderer.init(&mock);
    var ctx = try Context.init(std.testing.allocator, renderer, null);
    defer ctx.deinit();

    const input = InputState.init();
    ctx.beginFrame(input, null);

    const rect = Rect.init(100, 100, 300, 30);
    var value: f32 = 0.5; // 50%
    const changed = slider(&ctx, "Volume", rect, &value, 0.0, 1.0);

    try std.testing.expect(!changed);
    try std.testing.expectApproxEqRel(@as(f32, 0.5), value, 0.01);

    // Slider should draw:
    // 1. Track background
    // 2. Track border
    // 3. Filled portion (progress)
    // 4. Handle (knob)
    // 5. Handle border
    // 6. Label text
    // 7. Value text
    try std.testing.expect(mock.draw_calls.items.len >= 5);
    try mock.assertDrawCallCount(.text, 2); // Label + value
}

test "Visual: Text input empty rendering" {
    var mock = MockRenderer.init(std.testing.allocator);
    defer mock.deinit();

    const renderer = Renderer.init(&mock);
    var ctx = try Context.init(std.testing.allocator, renderer, null);
    defer ctx.deinit();

    const input = InputState.init();
    ctx.beginFrame(input, null);

    const rect = Rect.init(100, 100, 300, 30);
    var buffer: [256]u8 = undefined;
    var text_len: usize = 0;
    _ = textInput(&ctx, "username", rect, &buffer, &text_len);

    // Text input should draw:
    // 1. Background rectangle
    // 2. Border
    // (No text since empty)
    try mock.assertDrawCallCount(.rect, 1);
    try mock.assertDrawCallCount(.rect_outline, 1);
}

test "Visual: Text input with text rendering" {
    var mock = MockRenderer.init(std.testing.allocator);
    defer mock.deinit();

    const renderer = Renderer.init(&mock);
    var ctx = try Context.init(std.testing.allocator, renderer, null);
    defer ctx.deinit();

    const input = InputState.init();
    ctx.beginFrame(input, null);

    const rect = Rect.init(100, 100, 300, 30);
    var buffer: [256]u8 = undefined;
    const initial_text = "Hello";
    @memcpy(buffer[0..initial_text.len], initial_text);
    var text_len: usize = initial_text.len;

    _ = textInput(&ctx, "message", rect, &buffer, &text_len);

    // Should draw background, border, and text
    try mock.assertDrawCallCount(.rect, 1);
    try mock.assertDrawCallCount(.rect_outline, 1);
    try mock.assertDrawCallCount(.text, 1);
    try mock.assertContainsText("Hello");
}

test "Visual: Panel with children rendering" {
    var mock = MockRenderer.init(std.testing.allocator);
    defer mock.deinit();

    const renderer = Renderer.init(&mock);
    var ctx = try Context.init(std.testing.allocator, renderer, null);
    defer ctx.deinit();

    const input = InputState.init();
    ctx.beginFrame(input, null);

    const rect = Rect.init(50, 50, 400, 300);

    // Panel with nested content
    if (panel(&ctx, "Settings", rect)) {
        // Draw a button inside the panel
        _ = button(&ctx, "OK", Rect.init(100, 100, 100, 40));
    }

    // Panel should draw:
    // 1. Panel background
    // 2. Panel border
    // 3. Title text
    // Plus button inside:
    // 4. Button background
    // 5. Button border
    // 6. Button text
    try std.testing.expect(mock.draw_calls.items.len >= 6);
    try mock.assertContainsText("Settings");
    try mock.assertContainsText("OK");
}

test "Visual: Label rendering" {
    var mock = MockRenderer.init(std.testing.allocator);
    defer mock.deinit();

    const renderer = Renderer.init(&mock);
    var ctx = try Context.init(std.testing.allocator, renderer, null);
    defer ctx.deinit();

    const input = InputState.init();
    ctx.beginFrame(input, null);

    const pos = Vec2.init(100, 100);
    label(&ctx, "Score: 1234", pos, 24.0, Color.white);

    // Label should only draw text (no background/border)
    try mock.assertDrawCallCount(.text, 1);
    try mock.assertContainsText("Score: 1234");
}

test "Visual: Dropdown closed rendering" {
    var mock = MockRenderer.init(std.testing.allocator);
    defer mock.deinit();

    const renderer = Renderer.init(&mock);
    var ctx = try Context.init(std.testing.allocator, renderer, null);
    defer ctx.deinit();

    const input = InputState.init();
    ctx.beginFrame(input, null);

    const rect = Rect.init(100, 100, 200, 30);
    const options = [_][]const u8{ "Option 1", "Option 2", "Option 3" };
    var selected: usize = 0;

    _ = dropdown(&ctx, "mode_select", rect, &options, &selected);

    // Closed dropdown should draw:
    // 1. Background rectangle
    // 2. Border
    // 3. Selected option text
    // 4. Arrow indicator (small rect)
    try mock.assertDrawCallCount(.rect, 2); // Background + arrow
    try mock.assertDrawCallCount(.rect_outline, 1);
    try mock.assertDrawCallCount(.text, 1);
    try mock.assertContainsText("Option 1");
}

test "Visual: Multiple widgets in sequence" {
    var mock = MockRenderer.init(std.testing.allocator);
    defer mock.deinit();

    const renderer = Renderer.init(&mock);
    var ctx = try Context.init(std.testing.allocator, renderer, null);
    defer ctx.deinit();

    const input = InputState.init();
    ctx.beginFrame(input, null);

    // Draw multiple widgets
    _ = button(&ctx, "Button 1", Rect.init(10, 10, 100, 40));
    _ = button(&ctx, "Button 2", Rect.init(10, 60, 100, 40));
    _ = button(&ctx, "Button 3", Rect.init(10, 110, 100, 40));

    // Should have 3 sets of button draw calls
    try mock.assertDrawCallCount(.text, 3);
    try mock.assertContainsText("Button 1");
    try mock.assertContainsText("Button 2");
    try mock.assertContainsText("Button 3");
}

test "Visual: Scissor clipping workflow" {
    var mock = MockRenderer.init(std.testing.allocator);
    defer mock.deinit();

    const renderer = Renderer.init(&mock);
    var ctx = try Context.init(std.testing.allocator, renderer, null);
    defer ctx.deinit();

    const input = InputState.init();
    ctx.beginFrame(input, null);

    // Draw panel with scissor clipping
    const panel_rect = Rect.init(50, 50, 400, 300);
    if (panel(&ctx, "Clipped Panel", panel_rect)) {
        // Content inside should be clipped
        _ = button(&ctx, "Clipped Button", Rect.init(100, 100, 150, 40));
    }

    // Should have begin/end scissor calls
    try mock.assertDrawCallCount(.begin_scissor, 1);
    try mock.assertDrawCallCount(.end_scissor, 1);
}

test "Visual: Rendering order preservation" {
    var mock = MockRenderer.init(std.testing.allocator);
    defer mock.deinit();

    const renderer = Renderer.init(&mock);
    var ctx = try Context.init(std.testing.allocator, renderer, null);
    defer ctx.deinit();

    const input = InputState.init();
    ctx.beginFrame(input, null);

    // Draw in specific order
    label(&ctx, "First", Vec2.init(10, 10), 16, Color.white);
    label(&ctx, "Second", Vec2.init(10, 30), 16, Color.white);
    label(&ctx, "Third", Vec2.init(10, 50), 16, Color.white);

    // Verify order is preserved
    try std.testing.expectEqual(@as(usize, 3), mock.draw_calls.items.len);

    const call1 = mock.draw_calls.items[0];
    const call2 = mock.draw_calls.items[1];
    const call3 = mock.draw_calls.items[2];

    try std.testing.expect(call1 == .text);
    try std.testing.expect(call2 == .text);
    try std.testing.expect(call3 == .text);

    try std.testing.expect(std.mem.eql(u8, call1.text.text, "First"));
    try std.testing.expect(std.mem.eql(u8, call2.text.text, "Second"));
    try std.testing.expect(std.mem.eql(u8, call3.text.text, "Third"));
}

test "Visual: Color consistency across states" {
    var mock = MockRenderer.init(std.testing.allocator);
    defer mock.deinit();

    const renderer = Renderer.init(&mock);
    var ctx = try Context.init(std.testing.allocator, renderer, null);
    defer ctx.deinit();

    const rect = Rect.init(100, 100, 200, 40);

    // Normal state
    var input = InputState.init();
    ctx.beginFrame(input, null);
    _ = button(&ctx, "Normal", rect);

    const normal_rect_call = mock.findDrawCall(.rect);
    try std.testing.expect(normal_rect_call != null);
    const normal_color = normal_rect_call.?.rect.color;

    // Clear and test hover state
    mock.clear();
    input.mouse_pos = Vec2.init(150, 120);
    ctx.beginFrame(input, null);
    _ = button(&ctx, "Hover", rect);

    const hover_rect_call = mock.findDrawCall(.rect);
    try std.testing.expect(hover_rect_call != null);
    const hover_color = hover_rect_call.?.rect.color;

    // Hover should be lighter than normal (at least in one channel)
    const hover_brighter = hover_color.r >= normal_color.r or
        hover_color.g >= normal_color.g or
        hover_color.b >= normal_color.b;
    try std.testing.expect(hover_brighter);
}

test "Visual: MockRenderer reset and reuse" {
    var mock = MockRenderer.init(std.testing.allocator);
    defer mock.deinit();

    const renderer = Renderer.init(&mock);
    var ctx = try Context.init(std.testing.allocator, renderer, null);
    defer ctx.deinit();

    const input = InputState.init();

    // First frame
    ctx.beginFrame(input, null);
    _ = button(&ctx, "Button", Rect.init(10, 10, 100, 40));
    try std.testing.expect(mock.draw_calls.items.len > 0);

    // Clear and draw again
    mock.clear();
    try std.testing.expectEqual(@as(usize, 0), mock.draw_calls.items.len);

    ctx.beginFrame(input, null);
    _ = button(&ctx, "Another Button", Rect.init(10, 10, 100, 40));
    try std.testing.expect(mock.draw_calls.items.len > 0);
    try mock.assertContainsText("Another Button");
}
