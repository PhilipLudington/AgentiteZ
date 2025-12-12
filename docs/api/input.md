# Input State Abstraction

Clean event-driven to immediate-mode input API (`src/platform/input_state.zig`).

## Features

- **Persistent state** - One instance per game loop, not rebuilt each frame
- **Press vs Down** - Distinguish between `isKeyPressed()` (one frame) and `isKeyDown()` (held)
- **Frame lifecycle** - Automatic reset of transient states via `beginFrame()`
- **All mouse buttons** - Support for left, right, middle buttons
- **Text input** - Built-in buffering for UI widgets with overflow detection
- **SDL event handling** - Automatic processing via `handleEvent()`

## Usage

```zig
const platform = @import("AgentiteZ").platform;

// Initialize once
var input_state = platform.InputState.init(allocator);
defer input_state.deinit();

// Main loop
while (running) {
    // Clear transient states
    input_state.beginFrame();

    // Process events
    while (SDL_PollEvent(&event)) {
        try input_state.handleEvent(&event);
        // Handle quit, resize, etc.
    }

    // Query input (immediate-mode)
    if (input_state.isKeyPressed(.escape)) {
        // Only true on frame of press
        running = false;
    }
    if (input_state.isMouseButtonDown()) {
        // True while held
        const pos = input_state.getMousePosition();
    }

    // Convert to UI InputState for widgets
    const ui_input = input_state.toUIInputState();
}
```

## Key Methods

- `isMouseButtonPressed()` / `isMouseButtonDown()` - Left mouse
- `isMouseRightButtonPressed()` / `isMouseRightButtonDown()` - Right mouse
- `isMouseMiddleButtonPressed()` / `isMouseMiddleButtonDown()` - Middle mouse
- `isKeyPressed(key)` / `isKeyDown(key)` - Keyboard
- `getMousePosition()` - Current mouse coordinates
- `getMouseWheelMove()` - Wheel delta this frame
- `toUIInputState()` - Convert to UI widget format
