const std = @import("std");
const EtherMud = @import("EtherMud");
const sdl = EtherMud.sdl;
const c = sdl.c;

pub fn main() !void {
    std.debug.print("EtherMud - Starting game engine...\n", .{});

    // Initialize SDL3
    if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_EVENTS)) {
        std.debug.print("SDL_Init failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLInitFailed;
    }
    defer c.SDL_Quit();

    // Create window (1080p, maximized)
    const window = c.SDL_CreateWindow(
        "EtherMud Game Engine",
        1920,
        1080,
        c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_MAXIMIZED,
    ) orelse {
        std.debug.print("SDL_CreateWindow failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLCreateWindowFailed;
    };
    defer c.SDL_DestroyWindow(window);

    std.debug.print("Window created successfully!\n", .{});
    std.debug.print("Press ESC or close the window to exit.\n", .{});

    // Main event loop
    var running = true;
    var event: c.SDL_Event = undefined;

    while (running) {
        // Poll events
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => {
                    running = false;
                },
                c.SDL_EVENT_KEY_DOWN => {
                    if (event.key.key == c.SDLK_ESCAPE) {
                        running = false;
                    }
                },
                else => {},
            }
        }

        // Small delay to prevent busy-waiting
        c.SDL_Delay(16); // ~60 FPS
    }

    std.debug.print("Shutting down...\n", .{});
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
