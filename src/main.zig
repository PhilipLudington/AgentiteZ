const std = @import("std");
const EtherMud = @import("EtherMud");
const sdl = EtherMud.sdl;
const bgfx = EtherMud.bgfx;
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

    std.debug.print("bgfx initialized successfully!\n", .{});
    std.debug.print("Press ESC or close the window to exit.\n", .{});

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
                    const width: u32 = @intCast(event.window.data1);
                    const height: u32 = @intCast(event.window.data2);
                    bgfx.reset(width, height, bgfx.ResetFlags_Vsync, bgfx.TextureFormat.Count);
                },
                else => {},
            }
        }

        // Set view 0 default viewport
        bgfx.setViewRect(0, 0, 0, 1920, 1080);

        // Clear the framebuffer with a cornflower blue color
        bgfx.setViewClear(
            0,
            bgfx.ClearFlags_Color | bgfx.ClearFlags_Depth,
            0x6495edff, // Cornflower blue
            1.0,
            0,
        );

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
