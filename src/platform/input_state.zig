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
                    if (text_len > 0 and self.text_input_len + text_len < self.text_input_buf.len) {
                        @memcpy(self.text_input_buf[self.text_input_len..][0..text_len], text_ptr[0..text_len]);
                        self.text_input_len += text_len;
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
