const std = @import("std");
const AgentiteZ = @import("AgentiteZ");
const sdl = AgentiteZ.sdl;
const bgfx = AgentiteZ.bgfx;
const stb = AgentiteZ.stb_truetype;
const ui = AgentiteZ.ui;
const platform = AgentiteZ.platform;
const renderer = AgentiteZ.renderer;
const c = sdl.c;

// Simple demo state
const DemoState = struct {
    button_clicks: u32 = 0,
    checkbox_enabled: bool = false,
    slider_value: f32 = 50.0,
};

pub fn main() !void {
    std.debug.print("AgentiteZ Engine - Basic Demo\n", .{});
    std.debug.print("See examples/demo_ui.zig for full widget showcase!\n\n", .{});

    // Initialize SDL3
    if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_EVENTS)) {
        std.debug.print("SDL_Init failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLInitFailed;
    }
    defer c.SDL_Quit();

    // Create window with HiDPI support
    const window = c.SDL_CreateWindow(
        "AgentiteZ - Basic Demo",
        1920,
        1080,
        c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_HIGH_PIXEL_DENSITY,
    ) orelse {
        std.debug.print("SDL_CreateWindow failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLCreateWindowFailed;
    };
    defer c.SDL_DestroyWindow(window);

    // Get native window handle for bgfx
    const sys_wm_info = try getSDLNativeWindow(window);

    // Get window size
    var window_width: c_int = 0;
    var window_height: c_int = 0;
    _ = c.SDL_GetWindowSize(window, &window_width, &window_height);

    // Get DPI scale
    var pixel_width: c_int = undefined;
    var pixel_height: c_int = undefined;
    _ = c.SDL_GetWindowSizeInPixels(window, &pixel_width, &pixel_height);
    const calculated_dpi_scale = @as(f32, @floatFromInt(pixel_width)) / @as(f32, @floatFromInt(window_width));
    var dpi_scale = if (calculated_dpi_scale > 0) calculated_dpi_scale else 1.0;

    std.debug.print("Window: {}x{} logical, {}x{} pixels, DPI: {d:.2}x\n", .{ window_width, window_height, pixel_width, pixel_height, dpi_scale });

    // Initialize bgfx with pixel dimensions
    try initBgfx(sys_wm_info, @intCast(pixel_width), @intCast(pixel_height));
    defer bgfx.shutdown();

    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize stb_truetype allocator bridge
    stb.initAllocatorBridge(allocator);
    defer stb.deinitAllocatorBridge();

    // Create UI system
    const window_info = ui.WindowInfo{
        .width = window_width,
        .height = window_height,
        .dpi_scale = dpi_scale,
    };

    const font_path = "external/bgfx/examples/runtime/font/roboto-regular.ttf";
    var renderer_2d = try ui.Renderer2D.init(allocator, @intCast(window_width), @intCast(window_height), font_path);
    defer renderer_2d.deinit();
    renderer_2d.setDpiScale(dpi_scale);

    const ui_renderer = ui.Renderer.init(&renderer_2d);
    var ctx = ui.Context.initWithDpi(allocator, ui_renderer, window_info);
    defer ctx.deinit();

    // Load font atlas for text rendering
    const base_font_size: f32 = 24.0;
    const dpi_font_size = base_font_size * dpi_scale;
    var font_atlas = try renderer.FontAtlas.init(
        allocator,
        "external/bgfx/examples/runtime/font/roboto-regular.ttf",
        dpi_font_size,
        false
    );
    defer font_atlas.deinit();
    renderer_2d.setExternalFontAtlas(&font_atlas);

    std.debug.print("Font atlas loaded ({d}x{d} px)\n", .{ font_atlas.atlas_width, font_atlas.atlas_height });

    // Initialize input state
    var input_state = platform.InputState.init(allocator);
    defer input_state.deinit();

    // Demo state
    var demo_state = DemoState{};

    std.debug.print("\nBasic demo running. Press ESC to exit.\n", .{});
    std.debug.print("Run 'zig build run' for the full UI showcase!\n\n", .{});

    // Main loop
    var running = true;
    var event: c.SDL_Event = undefined;
    var frame: u32 = 0;

    while (running) {
        input_state.beginFrame();

        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => running = false,
                c.SDL_EVENT_KEY_DOWN => {
                    if (event.key.key == c.SDLK_ESCAPE) running = false;
                },
                c.SDL_EVENT_WINDOW_RESIZED => {
                    window_width = @intCast(event.window.data1);
                    window_height = @intCast(event.window.data2);
                    var new_pixel_width: c_int = undefined;
                    var new_pixel_height: c_int = undefined;
                    _ = c.SDL_GetWindowSizeInPixels(window, &new_pixel_width, &new_pixel_height);
                    bgfx.reset(@intCast(new_pixel_width), @intCast(new_pixel_height), bgfx.ResetFlags_Vsync, bgfx.TextureFormat.Count);
                    renderer_2d.updateWindowSize(@intCast(window_width), @intCast(window_height));
                },
                c.SDL_EVENT_DISPLAY_CONTENT_SCALE_CHANGED => {
                    const new_display_id = c.SDL_GetDisplayForWindow(window);
                    const new_content_scale = c.SDL_GetDisplayContentScale(new_display_id);
                    dpi_scale = if (new_content_scale > 0) new_content_scale else 1.0;
                    renderer_2d.setDpiScale(dpi_scale);
                },
                else => {},
            }
            try input_state.handleEvent(&event);
        }

        const input = input_state.toUIInputState();
        const current_window_info = ui.WindowInfo{
            .width = window_width,
            .height = window_height,
            .dpi_scale = dpi_scale,
        };

        // Get current pixel dimensions for HiDPI
        var current_pixel_width: c_int = undefined;
        var current_pixel_height: c_int = undefined;
        _ = c.SDL_GetWindowSizeInPixels(window, &current_pixel_width, &current_pixel_height);

        bgfx.setViewRect(0, 0, 0, @intCast(current_pixel_width), @intCast(current_pixel_height));
        bgfx.setViewClear(0, bgfx.ClearFlags_Color | bgfx.ClearFlags_Depth, 0x2a2a2aff, 1.0, 0);

        renderer_2d.beginFrame();
        ctx.beginFrame(input, current_window_info);

        // Simple UI demo
        ui.label(&ctx, "AgentiteZ Engine - Basic Demo", .{ .x = 20, .y = 20 }, 24, ui.Color.white);
        ui.label(&ctx, "Run 'zig build run' for the full widget showcase!", .{ .x = 20, .y = 50 }, 14, ui.Color.gray);

        ctx.cursor = .{ .x = 20, .y = 100 };

        // Panel with a few demo widgets
        const panel_rect = ui.Rect.init(20, 100, 500, 400);
        try ui.beginPanel(&ctx, "Quick Demo", panel_rect, ui.Color.panel_bg);

        ctx.cursor.y += 5;
        ui.label(&ctx, "A few example widgets:", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 16, ui.Color.white);
        ctx.cursor.y += 30;

        // Button
        const button_y = ctx.cursor.y;
        if (ui.buttonAuto(&ctx, "Click Me!", 200, 40)) {
            demo_state.button_clicks += 1;
        }
        var clicks_buf: [64]u8 = undefined;
        const clicks_text = std.fmt.bufPrint(&clicks_buf, "Clicks: {d}", .{demo_state.button_clicks}) catch "Clicks";
        ui.label(&ctx, clicks_text, .{ .x = ctx.cursor.x + 210, .y = button_y + 12 }, 12, ui.Color.imperial_gold);

        // Checkbox
        _ = ui.checkboxAuto(&ctx, "Enable Feature", &demo_state.checkbox_enabled);
        const status_text = if (demo_state.checkbox_enabled) "Status: ENABLED" else "Status: disabled";
        const status_color = if (demo_state.checkbox_enabled) ui.Color.init(100, 255, 100, 255) else ui.Color.gray;
        ui.label(&ctx, status_text, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 12, status_color);
        ctx.cursor.y += 25; // Space for status text + gap before next widget

        // Slider
        demo_state.slider_value = ui.sliderAuto(&ctx, "Volume", 300, demo_state.slider_value, 0, 100);
        var volume_buf: [64]u8 = undefined;
        const volume_text = std.fmt.bufPrint(&volume_buf, "Value: {d:.0}", .{demo_state.slider_value}) catch "Value";
        ui.label(&ctx, volume_text, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 12, ui.Color.white);

        ui.endPanel(&ctx);

        // Info panel
        const info_panel_rect = ui.Rect.init(550, 100, 400, 250);
        try ui.beginPanel(&ctx, "Engine Features", info_panel_rect, ui.Color.panel_bg);

        ctx.cursor.y += 5;
        ui.label(&ctx, "Core Systems:", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 16, ui.Color.white);
        ctx.cursor.y += 30;

        ui.label(&ctx, "SDL3 + bgfx rendering", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 14, ui.Color.gray);
        ctx.cursor.y += 22;
        ui.label(&ctx, "UI system with 10+ widgets", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 14, ui.Color.gray);
        ctx.cursor.y += 22;
        ui.label(&ctx, "ECS architecture", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 14, ui.Color.gray);
        ctx.cursor.y += 22;
        ui.label(&ctx, "Font atlas rendering", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 14, ui.Color.gray);
        ctx.cursor.y += 22;
        ui.label(&ctx, "Virtual 1920x1080 resolution", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 14, ui.Color.gray);
        ctx.cursor.y += 22;
        ui.label(&ctx, "HiDPI/Retina support", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 14, ui.Color.gray);
        ctx.cursor.y += 30;

        ui.label(&ctx, "See examples/demo_ui.zig for more!", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 12, ui.Color.imperial_gold);

        ui.endPanel(&ctx);

        // Status
        var status_buf: [128]u8 = undefined;
        const status = std.fmt.bufPrint(&status_buf, "Frame: {d} | Press ESC to exit", .{frame}) catch "Status";
        ui.label(&ctx, status, .{ .x = 20, .y = @as(f32, @floatFromInt(window_height)) - 30 }, 12, ui.Color.white);

        ctx.endFrame();
        renderer_2d.endFrame();

        bgfx.touch(0);
        _ = bgfx.frame(false);
        frame += 1;
    }

    std.debug.print("Shutting down...\n", .{});
}

fn getSDLNativeWindow(window: *c.SDL_Window) !*anyopaque {
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
