const std = @import("std");
const AgentiteZ = @import("AgentiteZ");
const sdl = AgentiteZ.sdl;
const bgfx = AgentiteZ.bgfx;
const stb = AgentiteZ.stb_truetype; // Required for stb_truetype allocator exports
const c = sdl.c;

comptime {
    // Force inclusion of stb_truetype exports even if not directly used
    _ = stb;
}

pub fn main() !void {
    std.debug.print("AgentiteZ Minimal Example - Starting...\n", .{});

    // Initialize SDL3
    if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_EVENTS)) {
        std.debug.print("SDL_Init failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLInitFailed;
    }
    defer c.SDL_Quit();

    // Create window
    const window = c.SDL_CreateWindow(
        "AgentiteZ - Minimal Example",
        1920,
        1080,
        c.SDL_WINDOW_RESIZABLE,
    ) orelse {
        std.debug.print("SDL_CreateWindow failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLCreateWindowFailed;
    };
    defer c.SDL_DestroyWindow(window);

    // Get native window handle for bgfx
    const native_window = try getNativeWindow(window);

    // Initialize bgfx
    try initBgfx(native_window, 1920, 1080);
    defer bgfx.shutdown();

    // Get window size
    var window_width: c_int = 0;
    var window_height: c_int = 0;
    _ = c.SDL_GetWindowSize(window, &window_width, &window_height);

    std.debug.print("Minimal example running. Press ESC to exit.\n", .{});
    std.debug.print("Window: {}x{}\n", .{ window_width, window_height });

    // Main loop
    var event: c.SDL_Event = undefined;
    var running = true;
    var frame: u32 = 0;

    while (running) {
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

        // Set view to cover entire window
        bgfx.setViewRect(0, 0, 0, @intCast(window_width), @intCast(window_height));

        // Clear screen to cornflower blue
        bgfx.setViewClear(0, bgfx.ClearFlags_Color | bgfx.ClearFlags_Depth, 0x6495edff, 1.0, 0);

        // Submit empty primitive to view 0
        bgfx.touch(0);

        // Advance to next frame
        _ = bgfx.frame(false);
        frame += 1;

        // Print frame count every 60 frames
        if (frame % 60 == 0) {
            std.debug.print("Frame: {d}\n", .{frame});
        }
    }

    std.debug.print("Shutting down...\n", .{});
}

fn getNativeWindow(window: *c.SDL_Window) !*anyopaque {
    const props = c.SDL_GetWindowProperties(window);
    if (props == 0) {
        std.debug.print("Failed to get window properties\n", .{});
        return error.SDLGetPropertiesFailed;
    }

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

    init.platformData.nwh = native_window;
    init.platformData.ndt = null;
    init.platformData.context = null;
    init.platformData.backBuffer = null;
    init.platformData.backBufferDS = null;
    init.platformData.type = bgfx.NativeWindowHandleType.Default;

    init.type = bgfx.RendererType.Count;
    init.vendorId = bgfx.PciIdFlags_None;
    init.deviceId = 0;
    init.debug = false;
    init.profile = false;

    init.resolution.width = width;
    init.resolution.height = height;
    init.resolution.reset = bgfx.ResetFlags_Vsync;
    init.resolution.numBackBuffers = 2;
    init.resolution.maxFrameLatency = 0;
    init.resolution.debugTextScale = 1;

    if (!bgfx.init(&init)) {
        std.debug.print("bgfx initialization failed\n", .{});
        return error.BgfxInitFailed;
    }
}
