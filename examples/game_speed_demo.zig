// Game Speed Demo - Demonstrates the Game Speed System
// Features:
// - Speed control widget (full and compact versions)
// - Animated elements that respect game time (bouncing balls)
// - UI elements that use real time (always animate even when paused)
// - Keyboard shortcuts: SPACE=pause, +/-=speed, 1-4=presets
// - Time display showing game time vs real time

const std = @import("std");
const AgentiteZ = @import("AgentiteZ");
const sdl = AgentiteZ.sdl;
const bgfx = AgentiteZ.bgfx;
const stb = AgentiteZ.stb_truetype;
const ui = AgentiteZ.ui;
const platform = AgentiteZ.platform;
const renderer = AgentiteZ.renderer;
const game_speed_mod = AgentiteZ.game_speed;
const c = sdl.c;

const GameSpeed = game_speed_mod.GameSpeed;
const SpeedPreset = game_speed_mod.SpeedPreset;

// ============================================================================
// Demo Constants
// ============================================================================

const VIRTUAL_WIDTH: f32 = 1920;
const VIRTUAL_HEIGHT: f32 = 1080;
const NUM_BALLS: usize = 8;

// ============================================================================
// Bouncing Ball (respects game time)
// ============================================================================

const Ball = struct {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    radius: f32,
    color: ui.Color,

    fn update(self: *Ball, dt: f32) void {
        // Move ball
        self.x += self.vx * dt;
        self.y += self.vy * dt;

        // Bounce off walls
        const play_left: f32 = 50;
        const play_right: f32 = VIRTUAL_WIDTH - 450;
        const play_top: f32 = 150;
        const play_bottom: f32 = VIRTUAL_HEIGHT - 50;

        if (self.x - self.radius < play_left) {
            self.x = play_left + self.radius;
            self.vx = -self.vx;
        }
        if (self.x + self.radius > play_right) {
            self.x = play_right - self.radius;
            self.vx = -self.vx;
        }
        if (self.y - self.radius < play_top) {
            self.y = play_top + self.radius;
            self.vy = -self.vy;
        }
        if (self.y + self.radius > play_bottom) {
            self.y = play_bottom - self.radius;
            self.vy = -self.vy;
        }
    }

    fn draw(self: *const Ball, renderer_2d: *ui.Renderer2D) void {
        // Draw filled circle (approximated with small rect for now)
        const r = self.radius;
        renderer_2d.drawRect(ui.Rect{
            .x = self.x - r,
            .y = self.y - r,
            .width = r * 2,
            .height = r * 2,
        }, self.color);
    }
};

// ============================================================================
// Pulsing Indicator (uses real time - always animates)
// ============================================================================

const PulsingIndicator = struct {
    phase: f32 = 0,

    fn update(self: *PulsingIndicator, dt: f32) void {
        self.phase += dt * 2.0; // 2 Hz pulse
        if (self.phase > std.math.pi * 2.0) {
            self.phase -= std.math.pi * 2.0;
        }
    }

    fn getAlpha(self: *const PulsingIndicator) u8 {
        const t = (@sin(self.phase) + 1.0) / 2.0; // 0 to 1
        return @intFromFloat(128 + t * 127); // 128 to 255
    }
};

// ============================================================================
// Main Entry Point
// ============================================================================

pub fn main() !void {
    std.debug.print("\n", .{});
    std.debug.print("===========================================\n", .{});
    std.debug.print("  AgentiteZ Game Speed Demo\n", .{});
    std.debug.print("===========================================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Controls:\n", .{});
    std.debug.print("  SPACE     - Toggle pause\n", .{});
    std.debug.print("  + / =     - Increase speed\n", .{});
    std.debug.print("  -         - Decrease speed\n", .{});
    std.debug.print("  1         - Slow (0.5x)\n", .{});
    std.debug.print("  2         - Normal (1x)\n", .{});
    std.debug.print("  3         - Fast (2x)\n", .{});
    std.debug.print("  4         - Very Fast (4x)\n", .{});
    std.debug.print("  ESC       - Quit\n", .{});
    std.debug.print("\n", .{});

    // Initialize SDL3
    if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_EVENTS)) {
        std.debug.print("SDL_Init failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLInitFailed;
    }
    defer c.SDL_Quit();

    // Create window
    const window = c.SDL_CreateWindow(
        "AgentiteZ - Game Speed Demo",
        1280,
        720,
        c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_HIGH_PIXEL_DENSITY,
    ) orelse {
        std.debug.print("SDL_CreateWindow failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLCreateWindowFailed;
    };
    defer c.SDL_DestroyWindow(window);

    // Get native window handle
    const native_window = try getNativeWindow(window);

    // Get window size
    var window_width: c_int = 0;
    var window_height: c_int = 0;
    _ = c.SDL_GetWindowSize(window, &window_width, &window_height);

    // Get DPI scale
    var pixel_width: c_int = undefined;
    var pixel_height: c_int = undefined;
    _ = c.SDL_GetWindowSizeInPixels(window, &pixel_width, &pixel_height);
    const dpi_scale = @as(f32, @floatFromInt(pixel_width)) / @as(f32, @floatFromInt(window_width));

    // Initialize bgfx
    try initBgfx(native_window, @intCast(pixel_width), @intCast(pixel_height));
    defer bgfx.shutdown();

    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize stb_truetype allocator bridge
    stb.initAllocatorBridge(allocator);
    defer stb.deinitAllocatorBridge();

    // Initialize UI system
    var window_info = ui.WindowInfo{
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

    // Load font atlas
    const base_font_size: f32 = 24.0;
    var font_atlas = try renderer.FontAtlas.init(allocator, font_path, base_font_size * dpi_scale, false);
    defer font_atlas.deinit();
    renderer_2d.setExternalFontAtlas(&font_atlas);

    // Initialize input state
    var input_state = platform.InputState.init(allocator);
    defer input_state.deinit();

    // ========================================================================
    // Initialize Game Speed System
    // ========================================================================
    var speed = GameSpeed.init(.{});

    // ========================================================================
    // Initialize Demo Objects
    // ========================================================================

    // Create bouncing balls with random properties
    var prng = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    const random = prng.random();

    var balls: [NUM_BALLS]Ball = undefined;
    const colors = [_]ui.Color{
        ui.Color.init(255, 100, 100, 255), // Red
        ui.Color.init(100, 255, 100, 255), // Green
        ui.Color.init(100, 100, 255, 255), // Blue
        ui.Color.init(255, 255, 100, 255), // Yellow
        ui.Color.init(255, 100, 255, 255), // Magenta
        ui.Color.init(100, 255, 255, 255), // Cyan
        ui.Color.init(255, 180, 100, 255), // Orange
        ui.Color.init(180, 100, 255, 255), // Purple
    };

    for (&balls, 0..) |*ball, i| {
        ball.* = Ball{
            .x = 200 + random.float(f32) * 800,
            .y = 200 + random.float(f32) * 600,
            .vx = (random.float(f32) - 0.5) * 400,
            .vy = (random.float(f32) - 0.5) * 400,
            .radius = 20 + random.float(f32) * 30,
            .color = colors[i % colors.len],
        };
    }

    // Pulsing indicator (uses real time)
    var pulse = PulsingIndicator{};

    // Timing
    var last_time = std.time.milliTimestamp();

    // Main loop
    var running = true;
    var event: c.SDL_Event = undefined;

    while (running) {
        // Calculate raw delta time
        const current_time = std.time.milliTimestamp();
        const delta_ms = current_time - last_time;
        last_time = current_time;
        const raw_dt: f32 = @as(f32, @floatFromInt(delta_ms)) / 1000.0;

        // Update game speed system
        speed.update(raw_dt);

        input_state.beginFrame();

        // Event handling
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => running = false,
                c.SDL_EVENT_KEY_DOWN => {
                    const key = event.key.key;
                    if (key == c.SDLK_ESCAPE) running = false;

                    // Space to toggle pause
                    if (key == c.SDLK_SPACE) speed.togglePause();

                    // +/= to increase speed
                    if (key == c.SDLK_EQUALS or key == c.SDLK_KP_PLUS) speed.cycleSpeed();

                    // - to decrease speed
                    if (key == c.SDLK_MINUS or key == c.SDLK_KP_MINUS) speed.cyclePrevSpeed();

                    // Number keys for presets
                    if (key == c.SDLK_1) speed.setPreset(.slow);
                    if (key == c.SDLK_2) speed.setPreset(.normal);
                    if (key == c.SDLK_3) speed.setPreset(.fast);
                    if (key == c.SDLK_4) speed.setPreset(.very_fast);
                },
                c.SDL_EVENT_WINDOW_RESIZED => {
                    window_width = @intCast(event.window.data1);
                    window_height = @intCast(event.window.data2);
                    var new_pixel_width: c_int = undefined;
                    var new_pixel_height: c_int = undefined;
                    _ = c.SDL_GetWindowSizeInPixels(window, &new_pixel_width, &new_pixel_height);
                    bgfx.reset(@intCast(new_pixel_width), @intCast(new_pixel_height), bgfx.ResetFlags_Vsync, bgfx.TextureFormat.Count);
                    renderer_2d.updateWindowSize(@intCast(new_pixel_width), @intCast(new_pixel_height));
                    window_info.width = window_width;
                    window_info.height = window_height;
                },
                else => {},
            }
            try input_state.handleEvent(&event);
        }

        // ====================================================================
        // Update Game Objects (using game delta - respects pause/speed)
        // ====================================================================
        const game_dt = speed.getGameDelta();
        for (&balls) |*ball| {
            ball.update(game_dt);
        }

        // ====================================================================
        // Update UI Elements (using real delta - always runs)
        // ====================================================================
        const real_dt = speed.getRealDelta();
        pulse.update(real_dt);

        // ====================================================================
        // Render
        // ====================================================================
        bgfx.setViewClear(0, bgfx.ClearFlags_Color | bgfx.ClearFlags_Depth, 0x1a1a2eFF, 1.0, 0);
        bgfx.setViewRect(0, 0, 0, @intCast(pixel_width), @intCast(pixel_height));
        bgfx.touch(0);

        renderer_2d.beginFrame();
        const input = input_state.toUIInputState();
        ctx.beginFrame(input, window_info);

        // Draw play area background
        renderer_2d.drawRect(ui.Rect{
            .x = 50,
            .y = 150,
            .width = VIRTUAL_WIDTH - 500,
            .height = VIRTUAL_HEIGHT - 200,
        }, ui.Color.init(30, 30, 50, 255));

        // Draw play area border
        renderer_2d.drawRectOutline(ui.Rect{
            .x = 50,
            .y = 150,
            .width = VIRTUAL_WIDTH - 500,
            .height = VIRTUAL_HEIGHT - 200,
        }, ui.Color.init(100, 100, 150, 255), 2);

        // Draw bouncing balls
        for (&balls) |*ball| {
            ball.draw(&renderer_2d);
        }

        // ====================================================================
        // UI Panel (right side)
        // ====================================================================

        // Title
        renderer_2d.drawText("Game Speed Demo", .{ .x = VIRTUAL_WIDTH - 380, .y = 30 }, 28, ui.Color.init(255, 215, 0, 255));

        // Speed Control Widget (full version)
        ctx.cursor = ui.Vec2{ .x = VIRTUAL_WIDTH - 400, .y = 80 };
        _ = ui.speedControlAuto(&ctx, &speed, .{ .show_shortcuts = true });

        // Spacing
        ctx.cursor = ui.Vec2{ .x = VIRTUAL_WIDTH - 400, .y = 180 };

        // Time Display Panel
        try ui.beginPanel(&ctx, "Time Info", ui.Rect{
            .x = VIRTUAL_WIDTH - 400,
            .y = 180,
            .width = 380,
            .height = 180,
        }, ctx.theme.panel_bg);

        // Game Time (affected by speed/pause)
        var game_time_buf: [64]u8 = undefined;
        const game_time_str = std.fmt.bufPrint(&game_time_buf, "Game Time: {d:.2}s", .{speed.getGameTime()}) catch "?";
        ui.label(&ctx, game_time_str, .{ .x = VIRTUAL_WIDTH - 380, .y = 220 }, 20, ui.Color.init(100, 255, 100, 255));

        // Real Time (always advances)
        var real_time_buf: [64]u8 = undefined;
        const real_time_str = std.fmt.bufPrint(&real_time_buf, "Real Time: {d:.2}s", .{speed.getRealTime()}) catch "?";
        ui.label(&ctx, real_time_str, .{ .x = VIRTUAL_WIDTH - 380, .y = 250 }, 20, ui.Color.init(100, 200, 255, 255));

        // Speed Multiplier
        var speed_buf: [64]u8 = undefined;
        const speed_str = std.fmt.bufPrint(&speed_buf, "Speed: {d:.1}x", .{speed.getSpeedMultiplier()}) catch "?";
        ui.label(&ctx, speed_str, .{ .x = VIRTUAL_WIDTH - 380, .y = 280 }, 20, ctx.theme.text_primary);

        // Frame Delta
        var delta_buf: [64]u8 = undefined;
        const delta_str = std.fmt.bufPrint(&delta_buf, "Game Delta: {d:.4}s", .{game_dt}) catch "?";
        ui.label(&ctx, delta_str, .{ .x = VIRTUAL_WIDTH - 380, .y = 310 }, 16, ctx.theme.text_secondary);

        var real_delta_buf: [64]u8 = undefined;
        const real_delta_str = std.fmt.bufPrint(&real_delta_buf, "Real Delta: {d:.4}s", .{real_dt}) catch "?";
        ui.label(&ctx, real_delta_str, .{ .x = VIRTUAL_WIDTH - 380, .y = 335 }, 16, ctx.theme.text_secondary);

        ui.endPanel(&ctx);

        // Compact Speed Control (alternative style)
        ctx.cursor = ui.Vec2{ .x = VIRTUAL_WIDTH - 400, .y = 380 };
        ui.label(&ctx, "Compact Widget:", .{ .x = VIRTUAL_WIDTH - 400, .y = 380 }, 16, ctx.theme.text_secondary);
        _ = ui.speedControlCompact(&ctx, &speed, ui.Rect{
            .x = VIRTUAL_WIDTH - 400,
            .y = 405,
            .width = 120,
            .height = 36,
        });

        // Pulsing "ALWAYS RUNNING" indicator (proves real time works)
        const pulse_alpha = pulse.getAlpha();
        const pulse_color = ui.Color.init(100, 200, 255, pulse_alpha);
        ui.label(&ctx, "UI Always Animates", .{ .x = VIRTUAL_WIDTH - 400, .y = 470 }, 18, pulse_color);
        ui.label(&ctx, "(uses real time)", .{ .x = VIRTUAL_WIDTH - 400, .y = 495 }, 14, ctx.theme.text_secondary);

        // Pause Overlay
        if (speed.isPaused()) {
            // Semi-transparent overlay on play area
            renderer_2d.drawRect(ui.Rect{
                .x = 50,
                .y = 150,
                .width = VIRTUAL_WIDTH - 500,
                .height = VIRTUAL_HEIGHT - 200,
            }, ui.Color.init(0, 0, 0, 150));

            // PAUSED text
            const paused_text = "PAUSED";
            const paused_size: f32 = 72;
            const paused_bounds = renderer_2d.measureText(paused_text, paused_size);
            const paused_x = 50 + (VIRTUAL_WIDTH - 500 - paused_bounds.x) / 2;
            const paused_y = 150 + (VIRTUAL_HEIGHT - 200) / 2 - 36;
            renderer_2d.drawText(paused_text, .{ .x = paused_x, .y = paused_y }, paused_size, ui.Color.init(255, 200, 50, pulse_alpha));

            // Press SPACE hint
            const hint_text = "Press SPACE to resume";
            const hint_size: f32 = 24;
            const hint_bounds = renderer_2d.measureText(hint_text, hint_size);
            const hint_x = 50 + (VIRTUAL_WIDTH - 500 - hint_bounds.x) / 2;
            renderer_2d.drawText(hint_text, .{ .x = hint_x, .y = paused_y + 80 }, hint_size, ctx.theme.text_secondary);
        }

        // Instructions at bottom
        ui.label(&ctx, "SPACE: Pause | +/-: Speed | 1-4: Presets | ESC: Quit", .{ .x = 50, .y = VIRTUAL_HEIGHT - 40 }, 16, ctx.theme.text_secondary);

        // Ball count indicator
        var ball_info: [64]u8 = undefined;
        const ball_str = std.fmt.bufPrint(&ball_info, "{d} bouncing balls (affected by game speed)", .{NUM_BALLS}) catch "?";
        ui.label(&ctx, ball_str, .{ .x = 50, .y = 120 }, 16, ctx.theme.text_secondary);

        ctx.endFrame();
        renderer_2d.endFrame();

        _ = bgfx.frame(false);
    }

    std.debug.print("\nGame Speed Demo ended.\n", .{});
    std.debug.print("Final Game Time: {d:.2}s\n", .{speed.getGameTime()});
    std.debug.print("Final Real Time: {d:.2}s\n", .{speed.getRealTime()});
}

// ============================================================================
// Platform-specific helpers
// ============================================================================

fn getNativeWindow(window: *c.SDL_Window) !*anyopaque {
    const props = c.SDL_GetWindowProperties(window);
    if (props == 0) return error.SDLGetPropertiesFailed;

    const native = c.SDL_GetPointerProperty(
        props,
        c.SDL_PROP_WINDOW_COCOA_WINDOW_POINTER,
        null,
    );
    if (native == null) return error.NativeWindowNotFound;

    return native.?;
}

fn initBgfx(native_window: *anyopaque, width: u32, height: u32) !void {
    var init: bgfx.Init = undefined;
    bgfx.initCtor(&init);

    init.type = bgfx.RendererType.Count;
    init.platformData.nwh = native_window;
    init.resolution.width = width;
    init.resolution.height = height;
    init.resolution.reset = bgfx.ResetFlags_Vsync;

    if (!bgfx.init(&init)) {
        return error.BgfxInitFailed;
    }

    bgfx.setDebug(bgfx.DebugFlags_None);
    bgfx.setViewClear(0, bgfx.ClearFlags_Color | bgfx.ClearFlags_Depth, 0x1a1a2eFF, 1.0, 0);
    bgfx.setViewRect(0, 0, 0, @intCast(width), @intCast(height));
}
