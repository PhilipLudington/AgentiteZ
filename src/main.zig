const std = @import("std");
const EtherMud = @import("EtherMud");
const sdl = EtherMud.sdl;
const bgfx = EtherMud.bgfx;
const ui = EtherMud.ui;
const c = sdl.c;

// Widget demo state
const DemoState = struct {
    // Checkbox states
    enable_feature: bool = false,
    show_advanced: bool = true,
    vsync_enabled: bool = true,

    // Slider values
    volume: f32 = 50.0,
    brightness: f32 = 75.0,
    mouse_sensitivity: f32 = 1.0,

    // Progress bar value (animated)
    progress: f32 = 0.0,

    // Text input
    text_buffer: [64]u8 = [_]u8{0} ** 64,
    text_len: usize = 0,

    // Dropdown
    dropdown_state: ui.DropdownState = .{},

    // Scroll list
    scroll_list_state: ui.ScrollListState = .{},

    // Tab bar
    tab_state: ui.TabBarState = .{},
};

pub fn main() !void {
    std.debug.print("EtherMud UI Demo - Starting...\n", .{});

    // Initialize SDL3
    if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_EVENTS)) {
        std.debug.print("SDL_Init failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLInitFailed;
    }
    defer c.SDL_Quit();

    // Create window
    const window = c.SDL_CreateWindow(
        "EtherMud UI Widget Demo",
        1920,
        1080,
        c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_MAXIMIZED,
    ) orelse {
        std.debug.print("SDL_CreateWindow failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLCreateWindowFailed;
    };
    defer c.SDL_DestroyWindow(window);

    // Get native window handle for bgfx
    const sys_wm_info = try getSDLNativeWindow(window);

    // Initialize bgfx
    try initBgfx(sys_wm_info, 1920, 1080);
    defer bgfx.shutdown();

    // Enable debug text rendering
    bgfx.setDebug(bgfx.DebugFlags_Text);

    // Get actual window size
    var window_width: c_int = 0;
    var window_height: c_int = 0;
    _ = c.SDL_GetWindowSize(window, &window_width, &window_height);

    // Initialize UI system
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var renderer_2d = try ui.Renderer2DProper.init(allocator, @intCast(window_width), @intCast(window_height));
    defer renderer_2d.deinit();

    const renderer = ui.Renderer.init(&renderer_2d);
    var ctx = ui.Context.init(allocator, renderer);
    defer ctx.deinit();

    // Demo state
    var demo_state = DemoState{};

    // Set some initial text
    const initial_text = "Hello World";
    @memcpy(demo_state.text_buffer[0..initial_text.len], initial_text);
    demo_state.text_len = initial_text.len;

    std.debug.print("UI Demo initialized! Press ESC to exit.\n", .{});

    // Main event loop
    var running = true;
    var event: c.SDL_Event = undefined;
    var frame: u32 = 0;

    while (running) {
        // Build input state for UI
        var input = ui.InputState.init();
        var mouse_x: f32 = 0;
        var mouse_y: f32 = 0;
        const mouse_state = c.SDL_GetMouseState(&mouse_x, &mouse_y);
        input.mouse_pos = .{ .x = mouse_x, .y = mouse_y };
        input.mouse_down = (mouse_state & c.SDL_BUTTON_LMASK) != 0;

        // Track if mouse was clicked or released this frame
        var mouse_clicked = false;
        var mouse_released = false;

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
                    renderer_2d.updateWindowSize(@intCast(window_width), @intCast(window_height));
                },
                c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                    if (event.button.button == c.SDL_BUTTON_LEFT) {
                        mouse_clicked = true;
                    }
                },
                c.SDL_EVENT_MOUSE_BUTTON_UP => {
                    if (event.button.button == c.SDL_BUTTON_LEFT) {
                        mouse_released = true;
                    }
                },
                else => {},
            }
        }

        input.mouse_clicked = mouse_clicked;
        input.mouse_released = mouse_released;

        // Set view 0 to cover the entire window
        bgfx.setViewRect(0, 0, 0, @intCast(window_width), @intCast(window_height));

        // Clear the framebuffer
        bgfx.setViewClear(
            0,
            bgfx.ClearFlags_Color | bgfx.ClearFlags_Depth,
            0x2a2a2aff, // Dark gray
            1.0,
            0,
        );

        // Clear debug text
        bgfx.dbgTextClear(0, false);

        // Begin 2D renderer frame
        renderer_2d.beginFrame();

        // Begin UI frame
        ctx.beginFrame(input);

        // Draw title
        ui.label(&ctx, "EtherMud UI Widget Demo", .{ .x = 20, .y = 20 }, 24, ui.Color.white);
        ui.label(&ctx, "Showcasing all widget types", .{ .x = 20, .y = 50 }, 14, ui.Color.gray);

        // Set cursor for auto-layout
        ctx.cursor = .{ .x = 20, .y = 90 };

        // === Buttons Section ===
        ui.label(&ctx, "Buttons:", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 18, ui.Color.white);
        ctx.cursor.y += 25;

        if (ui.buttonAuto(&ctx, "Click Me!", 150, 35)) {
            std.debug.print("Button clicked!\n", .{});
        }

        if (ui.buttonAuto(&ctx, "Another Button", 150, 35)) {
            std.debug.print("Another button clicked!\n", .{});
        }

        ctx.cursor.y += 15;

        // === Checkboxes Section ===
        ui.label(&ctx, "Checkboxes:", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 18, ui.Color.white);
        ctx.cursor.y += 25;

        _ = ui.checkboxAuto(&ctx, "Enable Feature", &demo_state.enable_feature);
        _ = ui.checkboxAuto(&ctx, "Show Advanced Options", &demo_state.show_advanced);
        _ = ui.checkboxAuto(&ctx, "VSync Enabled", &demo_state.vsync_enabled);

        ctx.cursor.y += 15;

        // === Sliders Section ===
        ui.label(&ctx, "Sliders:", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 18, ui.Color.white);
        ctx.cursor.y += 25;

        demo_state.volume = ui.sliderAuto(&ctx, "Volume", 300, demo_state.volume, 0, 100);
        demo_state.brightness = ui.sliderAuto(&ctx, "Brightness", 300, demo_state.brightness, 0, 100);
        demo_state.mouse_sensitivity = ui.sliderAuto(&ctx, "Mouse Sensitivity", 300, demo_state.mouse_sensitivity, 0.1, 5.0);

        ctx.cursor.y += 15;

        // === Progress Bar Section ===
        ui.label(&ctx, "Progress Bar:", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 18, ui.Color.white);
        ctx.cursor.y += 25;

        // Animate progress
        demo_state.progress += 0.005;
        if (demo_state.progress > 1.0) demo_state.progress = 0.0;

        ui.progressBarAuto(&ctx, "Loading...", 300, demo_state.progress, true);

        ctx.cursor.y += 15;

        // === Text Input Section ===
        ui.label(&ctx, "Text Input:", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 18, ui.Color.white);
        ctx.cursor.y += 25;

        ui.textInputAuto(&ctx, "Enter Name:", 300, &demo_state.text_buffer, &demo_state.text_len);

        ctx.cursor.y += 15;

        // === Second Column - Right Side ===
        const col2_x: f32 = 380;
        ctx.cursor = .{ .x = col2_x, .y = 90 };

        // === Dropdown Section ===
        ui.label(&ctx, "Dropdown:", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 18, ui.Color.white);
        ctx.cursor.y += 25;

        const dropdown_options = [_][]const u8{ "Option 1", "Option 2", "Option 3", "Option 4" };
        ui.dropdownAuto(&ctx, "Select Option:", 250, &dropdown_options, &demo_state.dropdown_state);

        ctx.cursor.y += 15;

        // === Tab Bar Section ===
        ui.label(&ctx, "Tab Bar:", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 18, ui.Color.white);
        ctx.cursor.y += 25;

        const tab_labels = [_][]const u8{ "General", "Graphics", "Audio", "Controls" };
        const active_tab = ui.tabBarAuto(&ctx, "settings_tabs", 400, &tab_labels, &demo_state.tab_state);

        // Show different content based on active tab
        const tab_content = switch (active_tab) {
            0 => "General settings would go here",
            1 => "Graphics settings would go here",
            2 => "Audio settings would go here",
            3 => "Controls settings would go here",
            else => "Unknown tab",
        };
        ui.label(&ctx, tab_content, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 14, ui.Color.white);
        ctx.cursor.y += 40;

        // === Scroll List Section ===
        ui.label(&ctx, "Scroll List:", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 18, ui.Color.white);
        ctx.cursor.y += 25;

        const scroll_items = [_][]const u8{
            "Item 1 - First",
            "Item 2 - Second",
            "Item 3 - Third",
            "Item 4 - Fourth",
            "Item 5 - Fifth",
            "Item 6 - Sixth",
            "Item 7 - Seventh",
            "Item 8 - Eighth",
            "Item 9 - Ninth",
            "Item 10 - Tenth",
        };
        ui.scrollListAuto(&ctx, "Select Item:", 300, 150, &scroll_items, &demo_state.scroll_list_state);

        // === Panel Example ===
        ctx.cursor = .{ .x = 800, .y = 90 };
        const panel_rect = ui.Rect.init(800, 90, 400, 300);
        try ui.beginPanel(&ctx, "Info Panel", panel_rect, ui.Color.panel_bg);

        ui.label(&ctx, "This is a panel!", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 16, ui.Color.white);
        ctx.cursor.y += 25;

        ui.label(&ctx, "Panels can contain other widgets", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 12, ui.Color.gray);
        ctx.cursor.y += 20;

        ui.label(&ctx, "with automatic layout.", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 12, ui.Color.gray);
        ctx.cursor.y += 30;

        if (ui.buttonAuto(&ctx, "Panel Button", 150, 30)) {
            std.debug.print("Panel button clicked!\n", .{});
        }

        ui.endPanel(&ctx);

        // === Status Display ===
        var status_buf: [256]u8 = undefined;
        const status = std.fmt.bufPrint(&status_buf, "Frame: {d} | FPS: ~60 | Mouse: ({d:.0}, {d:.0})", .{
            frame,
            input.mouse_pos.x,
            input.mouse_pos.y,
        }) catch "Status";

        ui.label(&ctx, status, .{ .x = 20, .y = @as(f32, @floatFromInt(window_height)) - 30 }, 12, ui.Color.white);

        // Show selected values
        var values_buf: [256]u8 = undefined;
        const values = std.fmt.bufPrint(&values_buf, "Volume: {d:.0} | Brightness: {d:.0} | Selected: {s}", .{
            demo_state.volume,
            demo_state.brightness,
            if (demo_state.scroll_list_state.selected_index) |idx| scroll_items[idx] else "None",
        }) catch "Values";

        ui.label(&ctx, values, .{ .x = 20, .y = @as(f32, @floatFromInt(window_height)) - 50 }, 12, ui.Color.imperial_gold);

        // End UI frame
        ctx.endFrame();

        // End 2D renderer frame (flushes draw batches)
        renderer_2d.endFrame();

        // Submit an empty primitive to view 0
        bgfx.touch(0);

        // Advance to next frame
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
    init.debug = true;
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
