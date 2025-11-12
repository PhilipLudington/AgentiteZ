const std = @import("std");
const EtherMud = @import("EtherMud");
const sdl = EtherMud.sdl;
const bgfx = EtherMud.bgfx;
const stb = EtherMud.stb_truetype;
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

    // Get native window handle for bgfx
    const sys_wm_info = try getSDLNativeWindow(window);

    // Initialize bgfx with SDL window
    try initBgfx(sys_wm_info, 1920, 1080);
    defer bgfx.shutdown();

    // Enable debug text rendering
    bgfx.setDebug(bgfx.DebugFlags_Text);

    std.debug.print("bgfx initialized successfully!\n", .{});
    std.debug.print("Press ESC or close the window to exit.\n", .{});

    // Get actual window size
    var window_width: c_int = 0;
    var window_height: c_int = 0;
    _ = c.SDL_GetWindowSize(window, &window_width, &window_height);

    // Main event loop
    var running = true;
    var event: c.SDL_Event = undefined;
    var frame: u32 = 0;

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
                c.SDL_EVENT_WINDOW_RESIZED => {
                    window_width = @intCast(event.window.data1);
                    window_height = @intCast(event.window.data2);
                    bgfx.reset(@intCast(window_width), @intCast(window_height), bgfx.ResetFlags_Vsync, bgfx.TextureFormat.Count);
                },
                else => {},
            }
        }

        // Set view 0 to cover the entire window
        bgfx.setViewRect(0, 0, 0, @intCast(window_width), @intCast(window_height));

        // Clear the framebuffer with a cornflower blue color
        bgfx.setViewClear(
            0,
            bgfx.ClearFlags_Color | bgfx.ClearFlags_Depth,
            0x6495edff, // Cornflower blue
            1.0,
            0,
        );

        // Use bgfx debug text
        bgfx.dbgTextClear(0, false);

        // bgfx debug text uses 8x16 pixel characters
        // Calculate screen dimensions in character cells based on actual window size
        const screen_cols: u16 = @intCast(@divTrunc(window_width, 8));
        const screen_rows: u16 = @intCast(@divTrunc(window_height, 16));

        // Create text buffer for just the message
        const message = "All your base are belong to us";
        const msg_width: u16 = @intCast(message.len);
        const msg_height: u16 = 1;
        var text_buffer = [_]u8{0} ** (message.len * 2); // 2 bytes per char (char + color)

        // Fill the buffer with our message
        for (message, 0..) |char, i| {
            text_buffer[i * 2] = char;
            text_buffer[i * 2 + 1] = 0x0f; // white on black
        }

        // Position the text centered on screen
        const pos_x: u16 = (screen_cols - msg_width) / 2;
        const pos_y: u16 = screen_rows / 2;

        bgfx.dbgTextImage(pos_x, pos_y, msg_width, msg_height, &text_buffer, msg_width * 2);

        // Submit an empty primitive to view 0
        bgfx.touch(0);

        // Advance to next frame
        _ = bgfx.frame(false);
        frame += 1;
    }

    std.debug.print("Shutting down...\n", .{});
}

fn getSDLNativeWindow(window: *c.SDL_Window) !*anyopaque {
    // Get the native window handle using SDL3's properties system
    const props = c.SDL_GetWindowProperties(window);
    if (props == 0) {
        std.debug.print("Failed to get window properties\n", .{});
        return error.SDLGetPropertiesFailed;
    }

    // On macOS, get the NSWindow handle
    const native_window = c.SDL_GetPointerProperty(
        props,
        c.SDL_PROP_WINDOW_COCOA_WINDOW_POINTER,
        null,
    ) orelse {
        std.debug.print("Failed to get native window handle\n", .{});
        return error.SDLGetNativeWindowFailed;
    };

    return native_window;
}

fn initBgfx(native_window: *anyopaque, width: u32, height: u32) !void {
    var init: bgfx.Init = undefined;
    bgfx.initCtor(&init);

    // Set platform data
    init.platformData.nwh = native_window;
    init.platformData.ndt = null;
    init.platformData.context = null;
    init.platformData.backBuffer = null;
    init.platformData.backBufferDS = null;
    init.platformData.type = bgfx.NativeWindowHandleType.Default;

    // Configure renderer
    init.type = bgfx.RendererType.Count; // Auto-select renderer
    init.vendorId = bgfx.PciIdFlags_None;
    init.deviceId = 0;
    init.debug = true;
    init.profile = false;

    // Set resolution
    init.resolution.width = width;
    init.resolution.height = height;
    init.resolution.reset = bgfx.ResetFlags_Vsync;
    init.resolution.numBackBuffers = 2;
    init.resolution.maxFrameLatency = 0;
    init.resolution.debugTextScale = 1;

    // Initialize bgfx
    if (!bgfx.init(&init)) {
        std.debug.print("bgfx initialization failed\n", .{});
        return error.BgfxInitFailed;
    }
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
