const std = @import("std");
const EtherMud = @import("EtherMud");
const sdl = EtherMud.sdl;
const bgfx = EtherMud.bgfx;
const ui = EtherMud.ui;
const ecs = EtherMud.ecs;
const platform = EtherMud.platform;
const config = EtherMud.config;
const renderer = EtherMud.renderer;
const c = sdl.c;

// ECS demo components
const Position = struct {
    x: f32,
    y: f32
};

const Velocity = struct {
    x: f32,
    y: f32
};

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

    // Get DPI scale from SDL3
    const display_id = c.SDL_GetDisplayForWindow(window);
    const content_scale = c.SDL_GetDisplayContentScale(display_id);
    const dpi_scale = if (content_scale > 0) content_scale else 1.0;

    std.debug.print("Window: {}x{}, DPI Scale: {d:.2}x\n", .{ window_width, window_height, dpi_scale });

    // Initialize UI system
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create DPI-aware UI context
    const window_info = ui.WindowInfo{
        .width = window_width,
        .height = window_height,
        .dpi_scale = dpi_scale,
    };

    var renderer_2d = try ui.Renderer2D.init(allocator, @intCast(window_width), @intCast(window_height));
    defer renderer_2d.deinit();

    const ui_renderer = ui.Renderer.init(&renderer_2d);
    var ctx = ui.Context.initWithDpi(allocator, ui_renderer, window_info);
    defer ctx.deinit();

    // Demo state
    var demo_state = DemoState{};

    // Set some initial text
    const initial_text = "Hello World";
    @memcpy(demo_state.text_buffer[0..initial_text.len], initial_text);
    demo_state.text_len = initial_text.len;

    // Enable text input
    _ = c.SDL_StartTextInput(window);

    // Initialize ECS demo
    var ecs_world = ecs.World.init(allocator);
    defer ecs_world.deinit();

    var positions = ecs.ComponentArray(Position).init(allocator);
    defer positions.deinit();

    var velocities = ecs.ComponentArray(Velocity).init(allocator);
    defer velocities.deinit();

    // Create 5 demo entities with random positions and velocities
    // Panel is at 1250,410 with size 400x200, so entities should be in range:
    // X: 1270-1630 (with 20px margin), Y: 470-590 (with margin for labels)
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        const entity = try ecs_world.createEntity();
        const base_x = 1300.0 + @as(f32, @floatFromInt(i)) * 50.0;
        const base_y = 490.0 + @as(f32, @floatFromInt(i % 3)) * 25.0;
        try positions.add(entity, Position{ .x = base_x, .y = base_y });

        const vel_x = 1.0 + @as(f32, @floatFromInt(i)) * 0.3;
        const vel_y = 0.5 - @as(f32, @floatFromInt(i % 2)) * 1.0;
        try velocities.add(entity, Velocity{ .x = vel_x, .y = vel_y });
    }

    std.debug.print("UI Demo initialized! Press ESC to exit.\n", .{});
    std.debug.print("ECS: {d} entities created\n", .{ecs_world.entityCount()});

    // === Load MUD Configuration Data ===
    std.debug.print("\n=== Loading MUD Configuration ===\n", .{});

    var rooms = try config.loadRooms(allocator);
    defer {
        var room_iter = rooms.valueIterator();
        while (room_iter.next()) |room| {
            var room_mut = room.*;
            room_mut.deinit();
        }
        rooms.deinit();
    }

    var items = try config.loadItems(allocator);
    defer {
        var item_iter = items.valueIterator();
        while (item_iter.next()) |item| {
            var item_mut = item.*;
            item_mut.deinit();
        }
        items.deinit();
    }

    var npcs = try config.loadNPCs(allocator);
    defer {
        var npc_iter = npcs.valueIterator();
        while (npc_iter.next()) |npc| {
            var npc_mut = npc.*;
            npc_mut.deinit();
        }
        npcs.deinit();
    }

    std.debug.print("=== Configuration Loading Complete ===\n\n", .{});

    // === Load Font Atlas ===
    std.debug.print("=== Loading Font Atlas ===\n", .{});
    var font_atlas = try renderer.FontAtlas.init(
        allocator,
        "external/bgfx/examples/runtime/font/roboto-regular.ttf",
        24.0, // font size
        false // flip_uv
    );
    defer font_atlas.deinit();
    std.debug.print("=== Font Atlas Ready ===\n\n", .{});

    // Initialize input state
    var input_state = platform.InputState.init(allocator);
    defer input_state.deinit();

    // Main event loop
    var running = true;
    var event: c.SDL_Event = undefined;
    var frame: u32 = 0;

    while (running) {
        // Begin frame - clear transient input states
        input_state.beginFrame();

        // Poll events and update input state
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
                else => {},
            }

            // Let InputState handle the event
            try input_state.handleEvent(&event);
        }

        // Convert to UI InputState for widgets
        const input = input_state.toUIInputState();

        // Update ECS entities
        var pos_iter = positions.iterator();
        while (pos_iter.next()) |entry| {
            if (velocities.get(entry.entity)) |vel| {
                entry.component.x += vel.x;
                entry.component.y += vel.y;

                // Bounce off boundaries (panel area with margins)
                const bounds_x_min: f32 = 1270;
                const bounds_x_max: f32 = 1630;
                const bounds_y_min: f32 = 470;
                const bounds_y_max: f32 = 590;

                if (entry.component.x < bounds_x_min or entry.component.x > bounds_x_max) {
                    vel.x *= -1;
                    entry.component.x = @max(bounds_x_min, @min(bounds_x_max, entry.component.x));
                }
                if (entry.component.y < bounds_y_min or entry.component.y > bounds_y_max) {
                    vel.y *= -1;
                    entry.component.y = @max(bounds_y_min, @min(bounds_y_max, entry.component.y));
                }
            } else |_| {}
        }

        // Set view 0 (main UI) to cover the entire window
        bgfx.setViewRect(0, 0, 0, @intCast(window_width), @intCast(window_height));

        // Set view 1 (overlay) to cover the entire window
        // Views are rendered in order, so view 1 will render after view 0
        bgfx.setViewRect(1, 0, 0, @intCast(window_width), @intCast(window_height));

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
        ui.label(&ctx, "EtherMud Engine Demo", .{ .x = 20, .y = 20 }, 24, ui.Color.white);
        ui.label(&ctx, "UI Widgets + ECS + Layout + Font Atlas + Save/Load + Config", .{ .x = 20, .y = 50 }, 14, ui.Color.gray);

        // Set cursor for auto-layout
        ctx.cursor = .{ .x = 20, .y = 90 };

        // === Buttons Section ===
        ui.label(&ctx, "Buttons:", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 18, ui.Color.white);
        ctx.cursor.y += 25;

        _ = ui.buttonAuto(&ctx, "Click Me!", 150, 35);
        _ = ui.buttonAuto(&ctx, "Another Button", 150, 35);

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
        // Move content down by half letter height (about 7px for 14pt font)
        ui.label(&ctx, tab_content, .{ .x = ctx.cursor.x, .y = ctx.cursor.y + 7 }, 14, ui.Color.white);
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

        ctx.cursor.y += 5;  // Add spacing after panel header
        ui.label(&ctx, "This is a panel!", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 16, ui.Color.white);
        ctx.cursor.y += 25;

        ui.label(&ctx, "Panels can contain other widgets", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 12, ui.Color.gray);
        ctx.cursor.y += 20;

        ui.label(&ctx, "with automatic layout.", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 12, ui.Color.gray);
        ctx.cursor.y += 30;

        _ = ui.buttonAuto(&ctx, "Panel Button", 150, 30);

        ui.endPanel(&ctx);

        // === NEW: Layout System Demo ===
        const layout_panel_rect = ui.Rect.init(1250, 90, 400, 300);
        try ui.beginPanel(&ctx, "Layout System (NEW!)", layout_panel_rect, ui.Color.panel_bg);

        ctx.cursor.y += 5;  // Add spacing after panel header
        ui.label(&ctx, "Automatic widget positioning:", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 14, ui.Color.white);
        ctx.cursor.y += 25;

        // Create vertical layout with center alignment
        var layout = ui.Layout.vertical(
            ui.Rect.init(ctx.cursor.x, ctx.cursor.y, 360, 200),
            .center  // Center-aligned
        ).withSpacing(10).withPadding(5);

        // Auto-positioned buttons - no manual coordinates!
        _ = ui.button(&ctx, "Auto Button 1", layout.nextRect(200, 35));
        _ = ui.button(&ctx, "Auto Button 2", layout.nextRect(200, 35));
        _ = ui.button(&ctx, "Auto Button 3", layout.nextRect(200, 35));

        ui.label(&ctx, "No manual Y coordinates!",
            .{ .x = layout.rect.x + 90, .y = layout.cursor.y + 10 },
            12, ui.Color.imperial_gold);

        ui.endPanel(&ctx);

        // === NEW: ECS System Demo ===
        const ecs_panel_rect = ui.Rect.init(1250, 410, 400, 200);
        try ui.beginPanel(&ctx, "ECS System (NEW!)", ecs_panel_rect, ui.Color.panel_bg);

        ctx.cursor.y += 5;  // Add spacing after panel header

        // Show ECS stats
        var ecs_buf: [128]u8 = undefined;
        const ecs_info = std.fmt.bufPrint(&ecs_buf,
            "Entities: {d} | Components: {d}",
            .{ ecs_world.entityCount(), positions.count() }
        ) catch "ECS Info";

        ui.label(&ctx, ecs_info, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 14, ui.Color.white);
        ctx.cursor.y += 25;

        ui.label(&ctx, "Moving entities with Position + Velocity:",
            .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 12, ui.Color.gray);

        // Draw moving entities as colored dots
        pos_iter = positions.iterator();
        const entity_colors = [_]ui.Color{
            ui.Color.init(255, 100, 100, 255),  // Red
            ui.Color.init(100, 255, 100, 255),  // Green
            ui.Color.init(100, 100, 255, 255),  // Blue
            ui.Color.init(255, 255, 100, 255),  // Yellow
            ui.Color.init(255, 100, 255, 255),  // Magenta
        };
        var entity_idx: usize = 0;
        while (pos_iter.next()) |entry| : (entity_idx += 1) {
            const dot_size: f32 = 12;  // Bigger for visibility
            const dot_rect = ui.Rect.init(
                entry.component.x - dot_size / 2,
                entry.component.y - dot_size / 2,
                dot_size,
                dot_size
            );
            // Draw entity as colored square
            ctx.renderer.drawRect(dot_rect, entity_colors[entity_idx % entity_colors.len]);
        }

        ui.endPanel(&ctx);

        // === NEW: Virtual Resolution Info ===
        const virt_panel_rect = ui.Rect.init(1250, 630, 400, 140);
        try ui.beginPanel(&ctx, "Virtual Resolution (1920x1080)", virt_panel_rect, ui.Color.panel_bg);

        ctx.cursor.y += 5;  // Add spacing after panel header

        const render_scale = ui.RenderScale.init(window_info);

        var virt_buf1: [128]u8 = undefined;
        const virt_line1 = std.fmt.bufPrint(&virt_buf1,
            "Physical: {d}x{d} px",
            .{ window_width, window_height }
        ) catch "Info";
        ui.label(&ctx, virt_line1, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 12, ui.Color.white);
        ctx.cursor.y += 20;

        var virt_buf2: [128]u8 = undefined;
        const virt_line2 = std.fmt.bufPrint(&virt_buf2,
            "Scale: {d:.2}x | DPI: {d:.2}x",
            .{ render_scale.scale, dpi_scale }
        ) catch "Info";
        ui.label(&ctx, virt_line2, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 12, ui.Color.white);
        ctx.cursor.y += 20;

        var virt_buf3: [128]u8 = undefined;
        const virt_line3 = std.fmt.bufPrint(&virt_buf3,
            "Viewport: {d}x{d} px",
            .{ render_scale.viewport_width, render_scale.viewport_height }
        ) catch "Info";
        ui.label(&ctx, virt_line3, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 12, ui.Color.white);
        ctx.cursor.y += 20;

        var virt_buf4: [128]u8 = undefined;
        const virt_line4 = std.fmt.bufPrint(&virt_buf4,
            "Offset: ({d:.0}, {d:.0}) px",
            .{ render_scale.offset_x, render_scale.offset_y }
        ) catch "Info";
        ui.label(&ctx, virt_line4, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 12, ui.Color.gray);

        ui.endPanel(&ctx);

        // === NEW: Input State Demo ===
        const input_panel_rect = ui.Rect.init(800, 410, 400, 270);
        try ui.beginPanel(&ctx, "Input State (NEW!)", input_panel_rect, ui.Color.panel_bg);

        ctx.cursor.y += 5;  // Add spacing after panel header

        // Mouse position
        const mouse_pos = input_state.getMousePosition();
        var mouse_buf: [128]u8 = undefined;
        const mouse_line = std.fmt.bufPrint(&mouse_buf,
            "Mouse: ({d:.0}, {d:.0})",
            .{ mouse_pos.x, mouse_pos.y }
        ) catch "Mouse Info";
        ui.label(&ctx, mouse_line, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 12, ui.Color.white);
        ctx.cursor.y += 20;

        // Mouse buttons - show state with color
        var mouse_btn_buf: [128]u8 = undefined;
        const left_state = if (input_state.isMouseButtonPressed())
            "PRESSED"
        else if (input_state.isMouseButtonDown())
            "DOWN"
        else
            "up";
        const left_color = if (input_state.isMouseButtonPressed())
            ui.Color.init(255, 200, 100, 255)  // Orange for pressed
        else if (input_state.isMouseButtonDown())
            ui.Color.init(100, 255, 100, 255)  // Green for down
        else
            ui.Color.gray;  // Gray for up

        const mouse_btn_line = std.fmt.bufPrint(&mouse_btn_buf,
            "Left: {s} | Right: {s} | Middle: {s}",
            .{
                left_state,
                if (input_state.isMouseRightButtonDown()) "DOWN" else "up",
                if (input_state.isMouseMiddleButtonDown()) "DOWN" else "up"
            }
        ) catch "Button Info";
        ui.label(&ctx, mouse_btn_line, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 12, left_color);
        ctx.cursor.y += 20;

        // Mouse wheel
        const wheel = input_state.getMouseWheelMove();
        var wheel_buf: [128]u8 = undefined;
        const wheel_line = std.fmt.bufPrint(&wheel_buf,
            "Wheel: {d:.1}",
            .{ wheel }
        ) catch "Wheel Info";
        const wheel_color = if (wheel != 0)
            ui.Color.init(255, 200, 100, 255)  // Orange when moving
        else
            ui.Color.gray;
        ui.label(&ctx, wheel_line, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 12, wheel_color);
        ctx.cursor.y += 25;

        // Keyboard - show some common keys
        ui.label(&ctx, "Keyboard (press keys to test):", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 12, ui.Color.white);
        ctx.cursor.y += 20;

        const test_keys = [_]struct { key: ui.Key, name: []const u8 }{
            .{ .key = .escape, .name = "ESC" },
            .{ .key = .enter, .name = "ENTER" },
            .{ .key = .tab, .name = "TAB" },
            .{ .key = .backspace, .name = "BKSP" },
        };

        // Display keys in a row
        const key_start_x = ctx.cursor.x;
        for (test_keys) |test_key| {
            const key_color = if (input_state.isKeyPressed(test_key.key))
                ui.Color.init(255, 200, 100, 255)  // Orange when pressed
            else if (input_state.isKeyDown(test_key.key))
                ui.Color.init(100, 255, 100, 255)  // Green when down
            else
                ui.Color.gray;  // Gray when up

            ui.label(&ctx, test_key.name, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 11, key_color);
            ctx.cursor.x += 85;
        }
        ctx.cursor.x = key_start_x;
        ctx.cursor.y += 20;

        // Arrow keys
        const arrow_keys = [_]struct { key: ui.Key, name: []const u8 }{
            .{ .key = .left, .name = "LEFT" },
            .{ .key = .right, .name = "RIGHT" },
            .{ .key = .home, .name = "HOME" },
            .{ .key = .end, .name = "END" },
        };

        for (arrow_keys) |test_key| {
            const key_color = if (input_state.isKeyPressed(test_key.key))
                ui.Color.init(255, 200, 100, 255)
            else if (input_state.isKeyDown(test_key.key))
                ui.Color.init(100, 255, 100, 255)
            else
                ui.Color.gray;

            ui.label(&ctx, test_key.name, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 11, key_color);
            ctx.cursor.x += 85;
        }

        ctx.cursor.x = key_start_x;
        ctx.cursor.y += 25;

        // Instructions
        ui.label(&ctx, "Orange = Pressed (1 frame)",
            .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 10, ui.Color.init(255, 200, 100, 255));
        ctx.cursor.y += 15;
        ui.label(&ctx, "Green = Down (held)",
            .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 10, ui.Color.init(100, 255, 100, 255));

        ui.endPanel(&ctx);

        // === NEW: Font Atlas Demo ===
        const font_panel_rect = ui.Rect.init(800, 690, 400, 230);
        try ui.beginPanel(&ctx, "Font Atlas (NEW!)", font_panel_rect, ui.Color.panel_bg);

        ctx.cursor.y += 5;  // Add spacing after panel header

        // Atlas info
        var atlas_buf1: [128]u8 = undefined;
        const atlas_line1 = std.fmt.bufPrint(&atlas_buf1,
            "Atlas: {d}x{d} px | Font: {d:.0}px",
            .{ font_atlas.atlas_width, font_atlas.atlas_height, font_atlas.font_size }
        ) catch "Atlas Info";
        ui.label(&ctx, atlas_line1, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 12, ui.Color.white);
        ctx.cursor.y += 20;

        var atlas_buf2: [128]u8 = undefined;
        const atlas_line2 = std.fmt.bufPrint(&atlas_buf2,
            "Line Height: {d:.1}px | 256 glyphs (16x16)",
            .{ font_atlas.line_height }
        ) catch "Atlas Info";
        ui.label(&ctx, atlas_line2, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 12, ui.Color.gray);
        ctx.cursor.y += 25;

        // Text measurement examples
        ui.label(&ctx, "Fast Text Measurement:", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 12, ui.Color.white);
        ctx.cursor.y += 20;

        const test_text1 = "Hello, World!";
        const width1 = font_atlas.measureText(test_text1);
        var measure_buf1: [128]u8 = undefined;
        const measure_line1 = std.fmt.bufPrint(&measure_buf1,
            "\"{s}\" = {d:.1}px",
            .{ test_text1, width1 }
        ) catch "Measure";
        ui.label(&ctx, measure_line1, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 11, ui.Color.init(150, 200, 255, 255));
        ctx.cursor.y += 18;

        const test_text2 = "EtherMud Engine";
        const width2 = font_atlas.measureText(test_text2);
        var measure_buf2: [128]u8 = undefined;
        const measure_line2 = std.fmt.bufPrint(&measure_buf2,
            "\"{s}\" = {d:.1}px",
            .{ test_text2, width2 }
        ) catch "Measure";
        ui.label(&ctx, measure_line2, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 11, ui.Color.init(150, 200, 255, 255));
        ctx.cursor.y += 22;

        // Ellipsis truncation demo
        ui.label(&ctx, "Ellipsis Truncation (max 180px):", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 12, ui.Color.white);
        ctx.cursor.y += 20;

        const long_text = "This is a very long text that will be truncated";
        const max_width: f32 = 180.0;
        const truncation_result = font_atlas.measureTextWithEllipsis(long_text, max_width);
        var truncate_buf: [128]u8 = undefined;
        const truncate_line = if (truncation_result.truncated_len < long_text.len)
            std.fmt.bufPrint(&truncate_buf,
                "\"{s}...\" ({d:.1}px)",
                .{ long_text[0..truncation_result.truncated_len], truncation_result.width }
            ) catch "Truncated"
        else
            std.fmt.bufPrint(&truncate_buf,
                "\"{s}\" (fits!)",
                .{ long_text }
            ) catch "Not Truncated";
        ui.label(&ctx, truncate_line, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 11, ui.Color.init(255, 200, 100, 255));

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
