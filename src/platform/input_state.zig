const std = @import("std");
const SDL = @import("../sdl.zig");
const ui = @import("../ui.zig");

const Vec2 = ui.Vec2;
const Key = ui.Key;

/// Bridges SDL3's event-driven input to immediate-mode query API
/// Provides clean separation between SDL event handling and game code
pub const InputState = struct {
    allocator: std.mem.Allocator,

    // Mouse state
    mouse_x: f32,
    mouse_y: f32,
    mouse_left_down: bool,
    mouse_left_pressed: bool, // true only on frame of press
    mouse_left_released: bool, // true only on frame of release
    mouse_right_down: bool,
    mouse_right_pressed: bool,
    mouse_right_released: bool,
    mouse_middle_down: bool,
    mouse_middle_pressed: bool,
    mouse_middle_released: bool,
    mouse_wheel_y: f32,

    // Keyboard state (using hashmaps for sparse storage)
    keys_down: std.AutoHashMap(Key, bool),
    keys_pressed: std.AutoHashMap(Key, bool),
    keys_released: std.AutoHashMap(Key, bool),

    // Text input buffer (for UI widgets)
    text_input_buf: [64]u8,
    text_input_len: usize,
    text_input_overflow: bool, // Set to true when buffer overflows

    pub fn init(allocator: std.mem.Allocator) InputState {
        return .{
            .allocator = allocator,
            .mouse_x = 0,
            .mouse_y = 0,
            .mouse_left_down = false,
            .mouse_left_pressed = false,
            .mouse_left_released = false,
            .mouse_right_down = false,
            .mouse_right_pressed = false,
            .mouse_right_released = false,
            .mouse_middle_down = false,
            .mouse_middle_pressed = false,
            .mouse_middle_released = false,
            .mouse_wheel_y = 0,
            .keys_down = std.AutoHashMap(Key, bool).init(allocator),
            .keys_pressed = std.AutoHashMap(Key, bool).init(allocator),
            .keys_released = std.AutoHashMap(Key, bool).init(allocator),
            .text_input_buf = [_]u8{0} ** 64,
            .text_input_len = 0,
            .text_input_overflow = false,
        };
    }

    pub fn deinit(self: *InputState) void {
        self.keys_down.deinit();
        self.keys_pressed.deinit();
        self.keys_released.deinit();
    }

    /// Call at the beginning of each frame to clear transient states
    pub fn beginFrame(self: *InputState) void {
        // Clear pressed/released flags (these are one-frame events)
        self.mouse_left_pressed = false;
        self.mouse_left_released = false;
        self.mouse_right_pressed = false;
        self.mouse_right_released = false;
        self.mouse_middle_pressed = false;
        self.mouse_middle_released = false;
        self.mouse_wheel_y = 0;

        // Clear text input
        self.text_input_len = 0;
        self.text_input_overflow = false;

        // Clear keyboard pressed/released maps
        self.keys_pressed.clearRetainingCapacity();
        self.keys_released.clearRetainingCapacity();
    }

    /// Process an SDL event and update input state
    pub fn handleEvent(self: *InputState, event: *const SDL.c.SDL_Event) !void {
        switch (event.type) {
            SDL.c.SDL_EVENT_MOUSE_MOTION => {
                self.mouse_x = event.motion.x;
                self.mouse_y = event.motion.y;
            },
            SDL.c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                if (event.button.button == SDL.c.SDL_BUTTON_LEFT) {
                    if (!self.mouse_left_down) {
                        self.mouse_left_pressed = true;
                    }
                    self.mouse_left_down = true;
                } else if (event.button.button == SDL.c.SDL_BUTTON_RIGHT) {
                    if (!self.mouse_right_down) {
                        self.mouse_right_pressed = true;
                    }
                    self.mouse_right_down = true;
                } else if (event.button.button == SDL.c.SDL_BUTTON_MIDDLE) {
                    if (!self.mouse_middle_down) {
                        self.mouse_middle_pressed = true;
                    }
                    self.mouse_middle_down = true;
                }
            },
            SDL.c.SDL_EVENT_MOUSE_BUTTON_UP => {
                if (event.button.button == SDL.c.SDL_BUTTON_LEFT) {
                    if (self.mouse_left_down) {
                        self.mouse_left_released = true;
                    }
                    self.mouse_left_down = false;
                } else if (event.button.button == SDL.c.SDL_BUTTON_RIGHT) {
                    if (self.mouse_right_down) {
                        self.mouse_right_released = true;
                    }
                    self.mouse_right_down = false;
                } else if (event.button.button == SDL.c.SDL_BUTTON_MIDDLE) {
                    if (self.mouse_middle_down) {
                        self.mouse_middle_released = true;
                    }
                    self.mouse_middle_down = false;
                }
            },
            SDL.c.SDL_EVENT_MOUSE_WHEEL => {
                self.mouse_wheel_y = event.wheel.y;
            },
            SDL.c.SDL_EVENT_KEY_DOWN => {
                const key = sdlKeyToEngineKey(event.key.key);
                if (key != .unknown) {
                    const was_down = self.keys_down.get(key) orelse false;
                    if (!was_down) {
                        try self.keys_pressed.put(key, true);
                    }
                    try self.keys_down.put(key, true);
                }
            },
            SDL.c.SDL_EVENT_KEY_UP => {
                const key = sdlKeyToEngineKey(event.key.key);
                if (key != .unknown) {
                    const was_down = self.keys_down.get(key) orelse false;
                    if (was_down) {
                        try self.keys_released.put(key, true);
                    }
                    try self.keys_down.put(key, false);
                }
            },
            SDL.c.SDL_EVENT_TEXT_INPUT => {
                // Handle text input for UI widgets
                if (event.text.text) |text_ptr| {
                    const text_len = std.mem.len(text_ptr);
                    if (text_len > 0) {
                        if (self.text_input_len + text_len < self.text_input_buf.len) {
                            @memcpy(self.text_input_buf[self.text_input_len..][0..text_len], text_ptr[0..text_len]);
                            self.text_input_len += text_len;
                        } else {
                            // Buffer overflow - set flag and log warning
                            if (!self.text_input_overflow) {
                                self.text_input_overflow = true;
                                std.log.warn("[InputState] Text input buffer overflow (max {d} bytes). Input truncated.", .{self.text_input_buf.len});
                            }
                        }
                    }
                }
            },
            else => {},
        }
    }

    // Immediate-mode query API

    pub fn isMouseButtonDown(self: *const InputState) bool {
        return self.mouse_left_down;
    }

    pub fn isMouseButtonPressed(self: *const InputState) bool {
        return self.mouse_left_pressed;
    }

    pub fn isMouseButtonReleased(self: *const InputState) bool {
        return self.mouse_left_released;
    }

    pub fn getMousePosition(self: *const InputState) Vec2 {
        return Vec2{ .x = self.mouse_x, .y = self.mouse_y };
    }

    pub fn getMouseWheelMove(self: *const InputState) f32 {
        return self.mouse_wheel_y;
    }

    pub fn isMouseRightButtonDown(self: *const InputState) bool {
        return self.mouse_right_down;
    }

    pub fn isMouseRightButtonPressed(self: *const InputState) bool {
        return self.mouse_right_pressed;
    }

    pub fn isMouseRightButtonReleased(self: *const InputState) bool {
        return self.mouse_right_released;
    }

    pub fn isMouseMiddleButtonDown(self: *const InputState) bool {
        return self.mouse_middle_down;
    }

    pub fn isMouseMiddleButtonPressed(self: *const InputState) bool {
        return self.mouse_middle_pressed;
    }

    pub fn isMouseMiddleButtonReleased(self: *const InputState) bool {
        return self.mouse_middle_released;
    }

    pub fn isKeyDown(self: *const InputState, key: Key) bool {
        return self.keys_down.get(key) orelse false;
    }

    pub fn isKeyPressed(self: *const InputState, key: Key) bool {
        return self.keys_pressed.get(key) orelse false;
    }

    pub fn isKeyReleased(self: *const InputState, key: Key) bool {
        return self.keys_released.get(key) orelse false;
    }

    /// Get the text input buffer for the current frame
    pub fn getTextInput(self: *const InputState) []const u8 {
        return self.text_input_buf[0..self.text_input_len];
    }

    /// Check if text input buffer overflowed this frame
    /// Returns true if input was truncated due to buffer size limit
    pub fn hasTextInputOverflow(self: *const InputState) bool {
        return self.text_input_overflow;
    }

    /// Convert to UI InputState for widget system
    pub fn toUIInputState(self: *const InputState) ui.InputState {
        return ui.InputState{
            .mouse_pos = .{ .x = self.mouse_x, .y = self.mouse_y },
            .mouse_down = self.mouse_left_down,
            .mouse_clicked = self.mouse_left_pressed,
            .mouse_released = self.mouse_left_released,
            .mouse_button = .left,
            .mouse_wheel = self.mouse_wheel_y,
            .text_input = self.text_input_buf[0..self.text_input_len],
            // Map all keyboard keys
            .key_backspace = self.isKeyPressed(.backspace),
            .key_delete = self.isKeyPressed(.delete),
            .key_enter = self.isKeyPressed(.enter),
            .key_tab = self.isKeyPressed(.tab),
            .key_left = self.isKeyPressed(.left),
            .key_right = self.isKeyPressed(.right),
            .key_home = self.isKeyPressed(.home),
            .key_end = self.isKeyPressed(.end),
            .key_escape = self.isKeyPressed(.escape),
        };
    }
};

/// Convert SDL keycode to engine Key enum
fn sdlKeyToEngineKey(sdl_key: SDL.c.SDL_Keycode) Key {
    return switch (sdl_key) {
        SDL.c.SDLK_BACKSPACE => .backspace,
        SDL.c.SDLK_DELETE => .delete,
        SDL.c.SDLK_LEFT => .left,
        SDL.c.SDLK_RIGHT => .right,
        SDL.c.SDLK_HOME => .home,
        SDL.c.SDLK_END => .end,
        SDL.c.SDLK_RETURN, SDL.c.SDLK_RETURN2 => .enter,
        SDL.c.SDLK_ESCAPE => .escape,
        SDL.c.SDLK_TAB => .tab,
        else => .unknown,
    };
}

test "InputState init/deinit" {
    var input = InputState.init(std.testing.allocator);
    defer input.deinit();

    try std.testing.expectEqual(@as(f32, 0), input.mouse_x);
    try std.testing.expectEqual(@as(f32, 0), input.mouse_y);
    try std.testing.expectEqual(false, input.mouse_left_down);
}

test "InputState mouse press/release cycle" {
    var input = InputState.init(std.testing.allocator);
    defer input.deinit();

    // Initial state
    try std.testing.expectEqual(false, input.isMouseButtonDown());
    try std.testing.expectEqual(false, input.isMouseButtonPressed());

    // Simulate mouse press
    var press_event = std.mem.zeroes(SDL.c.SDL_Event);
    press_event.type = SDL.c.SDL_EVENT_MOUSE_BUTTON_DOWN;
    press_event.button.button = SDL.c.SDL_BUTTON_LEFT;
    try input.handleEvent(&press_event);

    try std.testing.expectEqual(true, input.isMouseButtonDown());
    try std.testing.expectEqual(true, input.isMouseButtonPressed());

    // Next frame - pressed should clear
    input.beginFrame();
    try std.testing.expectEqual(true, input.isMouseButtonDown());
    try std.testing.expectEqual(false, input.isMouseButtonPressed());

    // Simulate mouse release
    var release_event = std.mem.zeroes(SDL.c.SDL_Event);
    release_event.type = SDL.c.SDL_EVENT_MOUSE_BUTTON_UP;
    release_event.button.button = SDL.c.SDL_BUTTON_LEFT;
    try input.handleEvent(&release_event);

    try std.testing.expectEqual(false, input.isMouseButtonDown());
    try std.testing.expectEqual(true, input.isMouseButtonReleased());

    // Next frame - released should clear
    input.beginFrame();
    try std.testing.expectEqual(false, input.isMouseButtonDown());
    try std.testing.expectEqual(false, input.isMouseButtonReleased());
}

test "InputState keyboard press/release" {
    var input = InputState.init(std.testing.allocator);
    defer input.deinit();

    // Initial state
    try std.testing.expectEqual(false, input.isKeyDown(.escape));
    try std.testing.expectEqual(false, input.isKeyPressed(.escape));

    // Simulate key press
    var press_event = std.mem.zeroes(SDL.c.SDL_Event);
    press_event.type = SDL.c.SDL_EVENT_KEY_DOWN;
    press_event.key.key = SDL.c.SDLK_ESCAPE;
    try input.handleEvent(&press_event);

    try std.testing.expectEqual(true, input.isKeyDown(.escape));
    try std.testing.expectEqual(true, input.isKeyPressed(.escape));

    // Next frame - pressed should clear
    input.beginFrame();
    try std.testing.expectEqual(true, input.isKeyDown(.escape));
    try std.testing.expectEqual(false, input.isKeyPressed(.escape));

    // Simulate key release
    var release_event = std.mem.zeroes(SDL.c.SDL_Event);
    release_event.type = SDL.c.SDL_EVENT_KEY_UP;
    release_event.key.key = SDL.c.SDLK_ESCAPE;
    try input.handleEvent(&release_event);

    try std.testing.expectEqual(false, input.isKeyDown(.escape));
    try std.testing.expectEqual(true, input.isKeyReleased(.escape));

    // Next frame - released should clear
    input.beginFrame();
    try std.testing.expectEqual(false, input.isKeyDown(.escape));
    try std.testing.expectEqual(false, input.isKeyReleased(.escape));
}

// ============================================================================
// EDGE CASE TESTS - Comprehensive coverage for InputState
// ============================================================================

test "InputState: Multiple key presses same frame" {
    var input = InputState.init(std.testing.allocator);
    defer input.deinit();

    // Press multiple keys in same frame
    var event1 = std.mem.zeroes(SDL.c.SDL_Event);
    event1.type = SDL.c.SDL_EVENT_KEY_DOWN;
    event1.key.key = SDL.c.SDLK_ESCAPE;
    try input.handleEvent(&event1);

    var event2 = std.mem.zeroes(SDL.c.SDL_Event);
    event2.type = SDL.c.SDL_EVENT_KEY_DOWN;
    event2.key.key = SDL.c.SDLK_BACKSPACE;
    try input.handleEvent(&event2);

    var event3 = std.mem.zeroes(SDL.c.SDL_Event);
    event3.type = SDL.c.SDL_EVENT_KEY_DOWN;
    event3.key.key = SDL.c.SDLK_TAB;
    try input.handleEvent(&event3);

    // All should be down and pressed
    try std.testing.expectEqual(true, input.isKeyDown(.escape));
    try std.testing.expectEqual(true, input.isKeyPressed(.escape));
    try std.testing.expectEqual(true, input.isKeyDown(.backspace));
    try std.testing.expectEqual(true, input.isKeyPressed(.backspace));
    try std.testing.expectEqual(true, input.isKeyDown(.tab));
    try std.testing.expectEqual(true, input.isKeyPressed(.tab));

    // Next frame - all pressed should clear but down remains
    input.beginFrame();
    try std.testing.expectEqual(true, input.isKeyDown(.escape));
    try std.testing.expectEqual(false, input.isKeyPressed(.escape));
    try std.testing.expectEqual(true, input.isKeyDown(.backspace));
    try std.testing.expectEqual(false, input.isKeyPressed(.backspace));
    try std.testing.expectEqual(true, input.isKeyDown(.tab));
    try std.testing.expectEqual(false, input.isKeyPressed(.tab));
}

test "InputState: Repeated key down events (held key)" {
    var input = InputState.init(std.testing.allocator);
    defer input.deinit();

    // First press
    var press_event = std.mem.zeroes(SDL.c.SDL_Event);
    press_event.type = SDL.c.SDL_EVENT_KEY_DOWN;
    press_event.key.key = SDL.c.SDLK_ESCAPE;
    try input.handleEvent(&press_event);

    try std.testing.expectEqual(true, input.isKeyDown(.escape));
    try std.testing.expectEqual(true, input.isKeyPressed(.escape));

    // Repeated press events (key held, OS sends repeats)
    try input.handleEvent(&press_event);
    try input.handleEvent(&press_event);
    try input.handleEvent(&press_event);

    // Should still be down, but pressed only once
    try std.testing.expectEqual(true, input.isKeyDown(.escape));
    try std.testing.expectEqual(true, input.isKeyPressed(.escape));

    // Next frame - clear pressed
    input.beginFrame();
    try std.testing.expectEqual(true, input.isKeyDown(.escape));
    try std.testing.expectEqual(false, input.isKeyPressed(.escape));
}

test "InputState: Key release without press" {
    var input = InputState.init(std.testing.allocator);
    defer input.deinit();

    // Release key that was never pressed
    var release_event = std.mem.zeroes(SDL.c.SDL_Event);
    release_event.type = SDL.c.SDL_EVENT_KEY_UP;
    release_event.key.key = SDL.c.SDLK_ESCAPE;
    try input.handleEvent(&release_event);

    // Should not register as released (wasn't down)
    try std.testing.expectEqual(false, input.isKeyDown(.escape));
    try std.testing.expectEqual(false, input.isKeyReleased(.escape));
}

test "InputState: Mouse motion tracking" {
    var input = InputState.init(std.testing.allocator);
    defer input.deinit();

    // Initial position
    var pos = input.getMousePosition();
    try std.testing.expectEqual(@as(f32, 0), pos.x);
    try std.testing.expectEqual(@as(f32, 0), pos.y);

    // Move mouse
    var motion_event = std.mem.zeroes(SDL.c.SDL_Event);
    motion_event.type = SDL.c.SDL_EVENT_MOUSE_MOTION;
    motion_event.motion.x = 100.5;
    motion_event.motion.y = 200.75;
    try input.handleEvent(&motion_event);

    pos = input.getMousePosition();
    try std.testing.expectEqual(@as(f32, 100.5), pos.x);
    try std.testing.expectEqual(@as(f32, 200.75), pos.y);

    // Move again
    motion_event.motion.x = 300.0;
    motion_event.motion.y = 400.0;
    try input.handleEvent(&motion_event);

    pos = input.getMousePosition();
    try std.testing.expectEqual(@as(f32, 300.0), pos.x);
    try std.testing.expectEqual(@as(f32, 400.0), pos.y);

    // Position persists across frames
    input.beginFrame();
    pos = input.getMousePosition();
    try std.testing.expectEqual(@as(f32, 300.0), pos.x);
    try std.testing.expectEqual(@as(f32, 400.0), pos.y);
}

test "InputState: Mouse wheel accumulation" {
    var input = InputState.init(std.testing.allocator);
    defer input.deinit();

    // Initial wheel state
    try std.testing.expectEqual(@as(f32, 0), input.getMouseWheelMove());

    // Scroll up
    var wheel_event = std.mem.zeroes(SDL.c.SDL_Event);
    wheel_event.type = SDL.c.SDL_EVENT_MOUSE_WHEEL;
    wheel_event.wheel.y = 1.0;
    try input.handleEvent(&wheel_event);

    try std.testing.expectEqual(@as(f32, 1.0), input.getMouseWheelMove());

    // Wheel state clears on next frame
    input.beginFrame();
    try std.testing.expectEqual(@as(f32, 0), input.getMouseWheelMove());

    // Scroll down
    wheel_event.wheel.y = -1.5;
    try input.handleEvent(&wheel_event);
    try std.testing.expectEqual(@as(f32, -1.5), input.getMouseWheelMove());
}

test "InputState: Right mouse button" {
    var input = InputState.init(std.testing.allocator);
    defer input.deinit();

    // Initial state
    try std.testing.expectEqual(false, input.isMouseRightButtonDown());
    try std.testing.expectEqual(false, input.isMouseRightButtonPressed());

    // Press right button
    var press_event = std.mem.zeroes(SDL.c.SDL_Event);
    press_event.type = SDL.c.SDL_EVENT_MOUSE_BUTTON_DOWN;
    press_event.button.button = SDL.c.SDL_BUTTON_RIGHT;
    try input.handleEvent(&press_event);

    try std.testing.expectEqual(true, input.isMouseRightButtonDown());
    try std.testing.expectEqual(true, input.isMouseRightButtonPressed());

    // Next frame
    input.beginFrame();
    try std.testing.expectEqual(true, input.isMouseRightButtonDown());
    try std.testing.expectEqual(false, input.isMouseRightButtonPressed());

    // Release right button
    var release_event = std.mem.zeroes(SDL.c.SDL_Event);
    release_event.type = SDL.c.SDL_EVENT_MOUSE_BUTTON_UP;
    release_event.button.button = SDL.c.SDL_BUTTON_RIGHT;
    try input.handleEvent(&release_event);

    try std.testing.expectEqual(false, input.isMouseRightButtonDown());
    try std.testing.expectEqual(true, input.isMouseRightButtonReleased());
}

test "InputState: Middle mouse button" {
    var input = InputState.init(std.testing.allocator);
    defer input.deinit();

    // Initial state
    try std.testing.expectEqual(false, input.isMouseMiddleButtonDown());
    try std.testing.expectEqual(false, input.isMouseMiddleButtonPressed());

    // Press middle button
    var press_event = std.mem.zeroes(SDL.c.SDL_Event);
    press_event.type = SDL.c.SDL_EVENT_MOUSE_BUTTON_DOWN;
    press_event.button.button = SDL.c.SDL_BUTTON_MIDDLE;
    try input.handleEvent(&press_event);

    try std.testing.expectEqual(true, input.isMouseMiddleButtonDown());
    try std.testing.expectEqual(true, input.isMouseMiddleButtonPressed());

    // Next frame
    input.beginFrame();
    try std.testing.expectEqual(true, input.isMouseMiddleButtonDown());
    try std.testing.expectEqual(false, input.isMouseMiddleButtonPressed());

    // Release middle button
    var release_event = std.mem.zeroes(SDL.c.SDL_Event);
    release_event.type = SDL.c.SDL_EVENT_MOUSE_BUTTON_UP;
    release_event.button.button = SDL.c.SDL_BUTTON_MIDDLE;
    try input.handleEvent(&release_event);

    try std.testing.expectEqual(false, input.isMouseMiddleButtonDown());
    try std.testing.expectEqual(true, input.isMouseMiddleButtonReleased());
}

test "InputState: Multiple mouse buttons simultaneously" {
    var input = InputState.init(std.testing.allocator);
    defer input.deinit();

    // Press all three buttons
    var left_press = std.mem.zeroes(SDL.c.SDL_Event);
    left_press.type = SDL.c.SDL_EVENT_MOUSE_BUTTON_DOWN;
    left_press.button.button = SDL.c.SDL_BUTTON_LEFT;
    try input.handleEvent(&left_press);

    var right_press = std.mem.zeroes(SDL.c.SDL_Event);
    right_press.type = SDL.c.SDL_EVENT_MOUSE_BUTTON_DOWN;
    right_press.button.button = SDL.c.SDL_BUTTON_RIGHT;
    try input.handleEvent(&right_press);

    var middle_press = std.mem.zeroes(SDL.c.SDL_Event);
    middle_press.type = SDL.c.SDL_EVENT_MOUSE_BUTTON_DOWN;
    middle_press.button.button = SDL.c.SDL_BUTTON_MIDDLE;
    try input.handleEvent(&middle_press);

    // All should be down and pressed
    try std.testing.expectEqual(true, input.isMouseButtonDown());
    try std.testing.expectEqual(true, input.isMouseButtonPressed());
    try std.testing.expectEqual(true, input.isMouseRightButtonDown());
    try std.testing.expectEqual(true, input.isMouseRightButtonPressed());
    try std.testing.expectEqual(true, input.isMouseMiddleButtonDown());
    try std.testing.expectEqual(true, input.isMouseMiddleButtonPressed());

    // Release only left button
    var left_release = std.mem.zeroes(SDL.c.SDL_Event);
    left_release.type = SDL.c.SDL_EVENT_MOUSE_BUTTON_UP;
    left_release.button.button = SDL.c.SDL_BUTTON_LEFT;
    try input.handleEvent(&left_release);

    // Left should be released, others still down
    try std.testing.expectEqual(false, input.isMouseButtonDown());
    try std.testing.expectEqual(true, input.isMouseButtonReleased());
    try std.testing.expectEqual(true, input.isMouseRightButtonDown());
    try std.testing.expectEqual(true, input.isMouseMiddleButtonDown());
}

test "InputState: Text input buffer normal usage" {
    var input = InputState.init(std.testing.allocator);
    defer input.deinit();

    // Initial state
    try std.testing.expectEqual(@as(usize, 0), input.getTextInput().len);
    try std.testing.expectEqual(false, input.hasTextInputOverflow());

    // Simulate text input event
    const test_text = "Hello";
    var text_event = std.mem.zeroes(SDL.c.SDL_Event);
    text_event.type = SDL.c.SDL_EVENT_TEXT_INPUT;
    text_event.text.text = test_text.ptr;
    try input.handleEvent(&text_event);

    // Check text was captured
    const captured = input.getTextInput();
    try std.testing.expectEqual(@as(usize, 5), captured.len);
    try std.testing.expectEqualStrings("Hello", captured);

    // Clear on next frame
    input.beginFrame();
    try std.testing.expectEqual(@as(usize, 0), input.getTextInput().len);
    try std.testing.expectEqual(false, input.hasTextInputOverflow());
}

test "InputState: Text input buffer accumulation" {
    var input = InputState.init(std.testing.allocator);
    defer input.deinit();

    // Multiple text events in same frame
    var event1 = std.mem.zeroes(SDL.c.SDL_Event);
    event1.type = SDL.c.SDL_EVENT_TEXT_INPUT;
    const text1 = "Hello";
    event1.text.text = text1.ptr;
    try input.handleEvent(&event1);

    var event2 = std.mem.zeroes(SDL.c.SDL_Event);
    event2.type = SDL.c.SDL_EVENT_TEXT_INPUT;
    const text2 = " ";
    event2.text.text = text2.ptr;
    try input.handleEvent(&event2);

    var event3 = std.mem.zeroes(SDL.c.SDL_Event);
    event3.type = SDL.c.SDL_EVENT_TEXT_INPUT;
    const text3 = "World";
    event3.text.text = text3.ptr;
    try input.handleEvent(&event3);

    // Should accumulate
    const captured = input.getTextInput();
    try std.testing.expectEqual(@as(usize, 11), captured.len);
    try std.testing.expectEqualStrings("Hello World", captured);
}

test "InputState: Text input buffer overflow" {
    var input = InputState.init(std.testing.allocator);
    defer input.deinit();

    // Fill buffer to near capacity (64 bytes)
    var event1 = std.mem.zeroes(SDL.c.SDL_Event);
    event1.type = SDL.c.SDL_EVENT_TEXT_INPUT;
    const text1 = "A" ** 60; // 60 bytes
    event1.text.text = text1.ptr;
    try input.handleEvent(&event1);

    try std.testing.expectEqual(@as(usize, 60), input.getTextInput().len);
    try std.testing.expectEqual(false, input.hasTextInputOverflow());

    // Add more text to cause overflow
    var event2 = std.mem.zeroes(SDL.c.SDL_Event);
    event2.type = SDL.c.SDL_EVENT_TEXT_INPUT;
    const text2 = "OVERFLOW";
    event2.text.text = text2.ptr;
    try input.handleEvent(&event2);

    // Should be truncated and overflow flag set
    try std.testing.expectEqual(@as(usize, 60), input.getTextInput().len);
    try std.testing.expectEqual(true, input.hasTextInputOverflow());

    // Overflow flag clears on next frame
    input.beginFrame();
    try std.testing.expectEqual(false, input.hasTextInputOverflow());
}

test "InputState: Text input buffer exact capacity" {
    var input = InputState.init(std.testing.allocator);
    defer input.deinit();

    // Fill buffer to exact capacity
    var event = std.mem.zeroes(SDL.c.SDL_Event);
    event.type = SDL.c.SDL_EVENT_TEXT_INPUT;
    const text = "A" ** 63; // 63 bytes (leaves room for one more)
    event.text.text = text.ptr;
    try input.handleEvent(&event);

    try std.testing.expectEqual(@as(usize, 63), input.getTextInput().len);
    try std.testing.expectEqual(false, input.hasTextInputOverflow());

    // Add one more byte (should not overflow)
    var event2 = std.mem.zeroes(SDL.c.SDL_Event);
    event2.type = SDL.c.SDL_EVENT_TEXT_INPUT;
    const text2 = "B";
    event2.text.text = text2.ptr;
    try input.handleEvent(&event2);

    try std.testing.expectEqual(@as(usize, 64), input.getTextInput().len);
    try std.testing.expectEqual(false, input.hasTextInputOverflow());
}

test "InputState: Unknown key code handling" {
    var input = InputState.init(std.testing.allocator);
    defer input.deinit();

    // Send an unmapped key code
    var event = std.mem.zeroes(SDL.c.SDL_Event);
    event.type = SDL.c.SDL_EVENT_KEY_DOWN;
    event.key.key = 0x12345678; // Invalid keycode

    // Should not crash, should be ignored
    try input.handleEvent(&event);

    // Unknown key should not be tracked
    try std.testing.expectEqual(false, input.isKeyDown(.unknown));
}

test "InputState: Frame lifecycle multiple cycles" {
    var input = InputState.init(std.testing.allocator);
    defer input.deinit();

    // Cycle 1: Press key
    input.beginFrame();
    var press = std.mem.zeroes(SDL.c.SDL_Event);
    press.type = SDL.c.SDL_EVENT_KEY_DOWN;
    press.key.key = SDL.c.SDLK_ESCAPE;
    try input.handleEvent(&press);
    try std.testing.expectEqual(true, input.isKeyPressed(.escape));

    // Cycle 2: Key held
    input.beginFrame();
    try std.testing.expectEqual(false, input.isKeyPressed(.escape));
    try std.testing.expectEqual(true, input.isKeyDown(.escape));

    // Cycle 3: Key held
    input.beginFrame();
    try std.testing.expectEqual(false, input.isKeyPressed(.escape));
    try std.testing.expectEqual(true, input.isKeyDown(.escape));

    // Cycle 4: Release key
    input.beginFrame();
    var release = std.mem.zeroes(SDL.c.SDL_Event);
    release.type = SDL.c.SDL_EVENT_KEY_UP;
    release.key.key = SDL.c.SDLK_ESCAPE;
    try input.handleEvent(&release);
    try std.testing.expectEqual(false, input.isKeyDown(.escape));
    try std.testing.expectEqual(true, input.isKeyReleased(.escape));

    // Cycle 5: Nothing
    input.beginFrame();
    try std.testing.expectEqual(false, input.isKeyDown(.escape));
    try std.testing.expectEqual(false, input.isKeyPressed(.escape));
    try std.testing.expectEqual(false, input.isKeyReleased(.escape));
}

test "InputState: All mapped keys" {
    var input = InputState.init(std.testing.allocator);
    defer input.deinit();

    const key_mappings = [_]struct { sdl: SDL.c.SDL_Keycode, engine: Key }{
        .{ .sdl = SDL.c.SDLK_BACKSPACE, .engine = .backspace },
        .{ .sdl = SDL.c.SDLK_DELETE, .engine = .delete },
        .{ .sdl = SDL.c.SDLK_LEFT, .engine = .left },
        .{ .sdl = SDL.c.SDLK_RIGHT, .engine = .right },
        .{ .sdl = SDL.c.SDLK_HOME, .engine = .home },
        .{ .sdl = SDL.c.SDLK_END, .engine = .end },
        .{ .sdl = SDL.c.SDLK_RETURN, .engine = .enter },
        .{ .sdl = SDL.c.SDLK_RETURN2, .engine = .enter },
        .{ .sdl = SDL.c.SDLK_ESCAPE, .engine = .escape },
        .{ .sdl = SDL.c.SDLK_TAB, .engine = .tab },
    };

    // Test each key mapping
    for (key_mappings) |mapping| {
        input.beginFrame();

        var press_event = std.mem.zeroes(SDL.c.SDL_Event);
        press_event.type = SDL.c.SDL_EVENT_KEY_DOWN;
        press_event.key.key = mapping.sdl;
        try input.handleEvent(&press_event);

        try std.testing.expectEqual(true, input.isKeyDown(mapping.engine));
        try std.testing.expectEqual(true, input.isKeyPressed(mapping.engine));
    }
}

test "InputState: toUIInputState conversion" {
    var input = InputState.init(std.testing.allocator);
    defer input.deinit();

    // Set up various input states
    var motion = std.mem.zeroes(SDL.c.SDL_Event);
    motion.type = SDL.c.SDL_EVENT_MOUSE_MOTION;
    motion.motion.x = 100.0;
    motion.motion.y = 200.0;
    try input.handleEvent(&motion);

    var mouse_press = std.mem.zeroes(SDL.c.SDL_Event);
    mouse_press.type = SDL.c.SDL_EVENT_MOUSE_BUTTON_DOWN;
    mouse_press.button.button = SDL.c.SDL_BUTTON_LEFT;
    try input.handleEvent(&mouse_press);

    var wheel = std.mem.zeroes(SDL.c.SDL_Event);
    wheel.type = SDL.c.SDL_EVENT_MOUSE_WHEEL;
    wheel.wheel.y = 1.5;
    try input.handleEvent(&wheel);

    var key = std.mem.zeroes(SDL.c.SDL_Event);
    key.type = SDL.c.SDL_EVENT_KEY_DOWN;
    key.key.key = SDL.c.SDLK_BACKSPACE;
    try input.handleEvent(&key);

    const test_text = "Test";
    var text = std.mem.zeroes(SDL.c.SDL_Event);
    text.type = SDL.c.SDL_EVENT_TEXT_INPUT;
    text.text.text = test_text.ptr;
    try input.handleEvent(&text);

    // Convert to UI state
    const ui_state = input.toUIInputState();

    // Verify conversion
    try std.testing.expectEqual(@as(f32, 100.0), ui_state.mouse_pos.x);
    try std.testing.expectEqual(@as(f32, 200.0), ui_state.mouse_pos.y);
    try std.testing.expectEqual(true, ui_state.mouse_down);
    try std.testing.expectEqual(true, ui_state.mouse_clicked);
    try std.testing.expectEqual(@as(f32, 1.5), ui_state.mouse_wheel);
    try std.testing.expectEqual(true, ui_state.key_backspace);
    try std.testing.expectEqualStrings("Test", ui_state.text_input);
}

test "InputState: Mouse button repeat press ignored" {
    var input = InputState.init(std.testing.allocator);
    defer input.deinit();

    // Press mouse button
    var press = std.mem.zeroes(SDL.c.SDL_Event);
    press.type = SDL.c.SDL_EVENT_MOUSE_BUTTON_DOWN;
    press.button.button = SDL.c.SDL_BUTTON_LEFT;
    try input.handleEvent(&press);

    try std.testing.expectEqual(true, input.isMouseButtonPressed());

    // Press again while already down (shouldn't trigger pressed again)
    try input.handleEvent(&press);
    try std.testing.expectEqual(true, input.isMouseButtonDown());
    try std.testing.expectEqual(true, input.isMouseButtonPressed());

    // Next frame - clear pressed
    input.beginFrame();

    // Press again (still down, shouldn't set pressed)
    try input.handleEvent(&press);
    try std.testing.expectEqual(true, input.isMouseButtonDown());
    try std.testing.expectEqual(false, input.isMouseButtonPressed());
}

test "InputState: Mouse release without down" {
    var input = InputState.init(std.testing.allocator);
    defer input.deinit();

    // Release button that wasn't pressed
    var release = std.mem.zeroes(SDL.c.SDL_Event);
    release.type = SDL.c.SDL_EVENT_MOUSE_BUTTON_UP;
    release.button.button = SDL.c.SDL_BUTTON_LEFT;
    try input.handleEvent(&release);

    // Should not register as released
    try std.testing.expectEqual(false, input.isMouseButtonReleased());
    try std.testing.expectEqual(false, input.isMouseButtonDown());
}
