// 2D Shapes Demo - Demonstrates 2D rendering primitives and animation
// Features: Rectangles, colors, animation, interpolation, visual effects
const std = @import("std");
const AgentiteZ = @import("AgentiteZ");
const sdl = AgentiteZ.sdl;
const bgfx = AgentiteZ.bgfx;
const stb = AgentiteZ.stb_truetype;
const ui = AgentiteZ.ui;
const platform = AgentiteZ.platform;
const renderer = AgentiteZ.renderer;
const c = sdl.c;

// ============================================================================
// Animation Structures
// ============================================================================

const AnimatedRect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    color: ui.Color,

    // Animation state
    vel_x: f32 = 0,
    vel_y: f32 = 0,
    rotation_speed: f32 = 0,
    scale_speed: f32 = 0,
    phase: f32 = 0,

    fn update(self: *AnimatedRect, dt: f32, bounds_w: f32, bounds_h: f32) void {
        self.x += self.vel_x * dt;
        self.y += self.vel_y * dt;
        self.phase += dt;

        // Bounce off walls
        if (self.x < 0 or self.x + self.width > bounds_w) {
            self.vel_x *= -1;
            self.x = @max(0, @min(bounds_w - self.width, self.x));
        }
        if (self.y < 0 or self.y + self.height > bounds_h) {
            self.vel_y *= -1;
            self.y = @max(0, @min(bounds_h - self.height, self.y));
        }
    }

    fn getRect(self: *const AnimatedRect) ui.Rect {
        return ui.Rect.init(self.x, self.y, self.width, self.height);
    }
};

const ParticleSystem = struct {
    const MAX_PARTICLES = 200;

    const Particle = struct {
        x: f32,
        y: f32,
        vel_x: f32,
        vel_y: f32,
        life: f32,
        max_life: f32,
        size: f32,
        color: ui.Color,
        active: bool = false,
    };

    particles: [MAX_PARTICLES]Particle = undefined,
    spawn_timer: f32 = 0,
    spawn_x: f32 = 0,
    spawn_y: f32 = 0,

    fn init() ParticleSystem {
        var sys = ParticleSystem{};
        for (&sys.particles) |*p| {
            p.active = false;
        }
        return sys;
    }

    fn spawn(self: *ParticleSystem, x: f32, y: f32, random: std.Random) void {
        for (&self.particles) |*p| {
            if (!p.active) {
                const angle = random.float(f32) * std.math.tau;
                const speed = 50 + random.float(f32) * 150;
                p.* = .{
                    .x = x,
                    .y = y,
                    .vel_x = @cos(angle) * speed,
                    .vel_y = @sin(angle) * speed,
                    .life = 1.0 + random.float(f32) * 1.5,
                    .max_life = 1.0 + random.float(f32) * 1.5,
                    .size = 4 + random.float(f32) * 8,
                    .color = ui.Color.init(
                        @intFromFloat(100 + random.float(f32) * 155),
                        @intFromFloat(100 + random.float(f32) * 155),
                        @intFromFloat(200 + random.float(f32) * 55),
                        255,
                    ),
                    .active = true,
                };
                break;
            }
        }
    }

    fn update(self: *ParticleSystem, dt: f32) void {
        for (&self.particles) |*p| {
            if (p.active) {
                p.x += p.vel_x * dt;
                p.y += p.vel_y * dt;
                p.vel_y += 100 * dt; // Gravity
                p.life -= dt;

                if (p.life <= 0) {
                    p.active = false;
                }
            }
        }
    }

    fn render(self: *const ParticleSystem, ctx: *ui.Context) void {
        for (&self.particles) |*p| {
            if (p.active) {
                const alpha_factor = @max(0.0, @min(1.0, p.life / p.max_life));
                const size = @max(1.0, p.size * alpha_factor);
                const alpha: u8 = @intFromFloat(255.0 * alpha_factor);

                const color = ui.Color.init(p.color.r, p.color.g, p.color.b, alpha);
                const rect = ui.Rect.init(p.x - size / 2, p.y - size / 2, size, size);
                ctx.renderer.drawRect(rect, color);
            }
        }
    }
};

// ============================================================================
// Demo State
// ============================================================================

const DemoMode = enum {
    bouncing_boxes,
    color_wave,
    particle_system,
    grid_animation,
    concentric_shapes,
};

const DemoState = struct {
    mode: DemoMode = .bouncing_boxes,
    time: f32 = 0,
    paused: bool = false,

    // Bouncing boxes
    boxes: [8]AnimatedRect = undefined,

    // Particle system
    particles: ParticleSystem = ParticleSystem.init(),

    // Grid animation
    grid_phase: f32 = 0,

    // UI state
    show_controls: bool = true,

    // Virtual mouse position (converted from physical coords)
    virtual_mouse_x: f32 = 0,
    virtual_mouse_y: f32 = 0,
};

// ============================================================================
// Constants
// ============================================================================

const VIRTUAL_WIDTH: f32 = 1920;
const VIRTUAL_HEIGHT: f32 = 1080;

const DEMO_COLORS = [_]ui.Color{
    ui.Color.init(255, 100, 100, 255), // Red
    ui.Color.init(100, 255, 100, 255), // Green
    ui.Color.init(100, 100, 255, 255), // Blue
    ui.Color.init(255, 255, 100, 255), // Yellow
    ui.Color.init(255, 100, 255, 255), // Magenta
    ui.Color.init(100, 255, 255, 255), // Cyan
    ui.Color.init(255, 200, 100, 255), // Orange
    ui.Color.init(200, 100, 255, 255), // Purple
};

// ============================================================================
// Main Entry Point
// ============================================================================

pub fn main() !void {
    std.debug.print("AgentiteZ 2D Shapes Demo\n", .{});
    std.debug.print("Press 1-5 to switch demos, SPACE to pause, H to toggle help\n\n", .{});

    // Initialize SDL3
    if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_EVENTS)) {
        std.debug.print("SDL_Init failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLInitFailed;
    }
    defer c.SDL_Quit();

    // Create window
    const window = c.SDL_CreateWindow(
        "AgentiteZ - 2D Shapes Demo",
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
    var dpi_scale = @as(f32, @floatFromInt(pixel_width)) / @as(f32, @floatFromInt(window_width));

    // Initialize bgfx
    try initBgfx(native_window, @intCast(pixel_width), @intCast(pixel_height));
    defer bgfx.shutdown();

    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize stb_truetype
    stb.initAllocatorBridge(allocator);
    defer stb.deinitAllocatorBridge();

    // Initialize UI system
    const font_path = "external/bgfx/examples/runtime/font/roboto-regular.ttf";
    var renderer_2d = try ui.Renderer2D.init(allocator, @intCast(window_width), @intCast(window_height), font_path);
    defer renderer_2d.deinit();
    renderer_2d.setDpiScale(dpi_scale);

    const ui_renderer = ui.Renderer.init(&renderer_2d);
    var ctx = ui.Context.initWithDpi(allocator, ui_renderer, ui.WindowInfo{
        .width = window_width,
        .height = window_height,
        .dpi_scale = dpi_scale,
    });
    defer ctx.deinit();

    // Load font atlas
    var font_atlas = try renderer.FontAtlas.init(allocator, font_path, 24.0 * dpi_scale, false);
    defer font_atlas.deinit();
    renderer_2d.setExternalFontAtlas(&font_atlas);

    // Initialize input state
    var input_state = platform.InputState.init(allocator);
    defer input_state.deinit();

    // Initialize PRNG
    var prng = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    const random = prng.random();

    // Initialize demo state
    var state = DemoState{};
    initBouncingBoxes(&state, random);

    // Timing
    var last_time = std.time.milliTimestamp();

    // Main loop
    var running = true;
    var event: c.SDL_Event = undefined;

    while (running) {
        // Calculate delta time
        const current_time = std.time.milliTimestamp();
        const delta_ms = current_time - last_time;
        last_time = current_time;
        const dt: f32 = @as(f32, @floatFromInt(delta_ms)) / 1000.0;

        input_state.beginFrame();

        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => running = false,
                c.SDL_EVENT_KEY_DOWN => {
                    const key = event.key.key;
                    if (key == c.SDLK_ESCAPE) running = false;
                    if (key == c.SDLK_SPACE) state.paused = !state.paused;
                    if (key == c.SDLK_H) state.show_controls = !state.show_controls;
                    if (key == c.SDLK_1) {
                        state.mode = .bouncing_boxes;
                        initBouncingBoxes(&state, random);
                    }
                    if (key == c.SDLK_2) state.mode = .color_wave;
                    if (key == c.SDLK_3) state.mode = .particle_system;
                    if (key == c.SDLK_4) state.mode = .grid_animation;
                    if (key == c.SDLK_5) state.mode = .concentric_shapes;
                },
                c.SDL_EVENT_WINDOW_RESIZED => {
                    window_width = @intCast(event.window.data1);
                    window_height = @intCast(event.window.data2);
                    var new_pixel_width: c_int = undefined;
                    var new_pixel_height: c_int = undefined;
                    _ = c.SDL_GetWindowSizeInPixels(window, &new_pixel_width, &new_pixel_height);
                    bgfx.reset(@intCast(new_pixel_width), @intCast(new_pixel_height), bgfx.ResetFlags_Vsync, bgfx.TextureFormat.Count);
                    // updateWindowSize now handles letterbox calculation internally
                    renderer_2d.updateWindowSize(@intCast(new_pixel_width), @intCast(new_pixel_height));
                },
                c.SDL_EVENT_DISPLAY_CONTENT_SCALE_CHANGED => {
                    const display_id = c.SDL_GetDisplayForWindow(window);
                    const new_scale = c.SDL_GetDisplayContentScale(display_id);
                    dpi_scale = if (new_scale > 0) new_scale else 1.0;
                    renderer_2d.setDpiScale(dpi_scale);
                },
                else => {},
            }
            try input_state.handleEvent(&event);
        }

        // Get current pixel dimensions for coordinate conversion
        var current_pixel_width: c_int = undefined;
        var current_pixel_height: c_int = undefined;
        _ = c.SDL_GetWindowSizeInPixels(window, &current_pixel_width, &current_pixel_height);

        // Calculate letterbox viewport (needed for both update and rendering)
        const viewport = renderer.calculateLetterboxViewport(
            @intCast(current_pixel_width),
            @intCast(current_pixel_height),
            1920,
            1080,
        );

        // Convert mouse position to virtual coordinates (always, for rendering)
        const raw_mouse = input_state.getMousePosition();
        // SDL gives us logical coordinates, multiply by DPI scale to get physical pixels
        const physical_mouse_x = raw_mouse.x * dpi_scale;
        const physical_mouse_y = raw_mouse.y * dpi_scale;
        // Account for letterbox offset and scale to convert to virtual coords
        state.virtual_mouse_x = (physical_mouse_x - @as(f32, @floatFromInt(viewport.x))) / viewport.scale;
        state.virtual_mouse_y = (physical_mouse_y - @as(f32, @floatFromInt(viewport.y))) / viewport.scale;

        // Update
        if (!state.paused) {
            state.time += dt;

            switch (state.mode) {
                .bouncing_boxes => {
                    for (&state.boxes) |*box| {
                        box.update(dt, VIRTUAL_WIDTH, VIRTUAL_HEIGHT - 100);
                    }
                },
                .particle_system => {
                    state.particles.update(dt);
                    state.particles.spawn_timer += dt;

                    if (state.particles.spawn_timer > 0.02) {
                        state.particles.spawn_timer = 0;
                        var i: u32 = 0;
                        while (i < 3) : (i += 1) {
                            state.particles.spawn(state.virtual_mouse_x, state.virtual_mouse_y, random);
                        }
                    }
                },
                .grid_animation => {
                    state.grid_phase += dt * 2;
                },
                else => {},
            }
        }

        // ====================================================================
        // Rendering
        // ====================================================================

        // Set bgfx viewport to the letterboxed area
        bgfx.setViewRect(0, viewport.x, viewport.y, viewport.width, viewport.height);
        bgfx.setViewClear(0, bgfx.ClearFlags_Color | bgfx.ClearFlags_Depth, 0x1a1a2eff, 1.0, 0);

        // Update renderer with viewport info for proper coordinate transformation
        renderer_2d.setViewportFromInfo(viewport);

        renderer_2d.beginFrame();

        const window_info = ui.WindowInfo{
            .width = window_width,
            .height = window_height,
            .dpi_scale = dpi_scale,
        };
        const input = input_state.toUIInputState();
        ctx.beginFrame(input, window_info);

        // Render current demo
        switch (state.mode) {
            .bouncing_boxes => renderBouncingBoxes(&state, &ctx),
            .color_wave => renderColorWave(&state, &ctx),
            .particle_system => renderParticleSystem(&state, &ctx),
            .grid_animation => renderGridAnimation(&state, &ctx),
            .concentric_shapes => renderConcentricShapes(&state, &ctx),
        }

        // Title
        const mode_name = switch (state.mode) {
            .bouncing_boxes => "Bouncing Boxes",
            .color_wave => "Color Wave",
            .particle_system => "Particle System",
            .grid_animation => "Grid Animation",
            .concentric_shapes => "Concentric Shapes",
        };

        var title_buf: [64]u8 = undefined;
        const title = std.fmt.bufPrint(&title_buf, "AgentiteZ - {s}", .{mode_name}) catch "AgentiteZ";
        ui.label(&ctx, title, .{ .x = 20, .y = 20 }, 28, ui.Color.white);

        // Controls overlay
        if (state.show_controls) {
            const panel_rect = ui.Rect.init(VIRTUAL_WIDTH - 320, 20, 300, 200);
            try ui.beginPanel(&ctx, "Controls", panel_rect, ui.Color.init(30, 30, 50, 220));

            ctx.cursor.y += 5;
            ui.label(&ctx, "1-5: Switch demo mode", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 13, ui.Color.white);
            ctx.cursor.y += 20;
            ui.label(&ctx, "SPACE: Pause/Resume", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 13, ui.Color.white);
            ctx.cursor.y += 20;
            ui.label(&ctx, "H: Toggle this help", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 13, ui.Color.white);
            ctx.cursor.y += 20;
            ui.label(&ctx, "ESC: Exit", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 13, ui.Color.white);
            ctx.cursor.y += 30;

            if (state.mode == .particle_system) {
                ui.label(&ctx, "Move mouse to spawn particles!", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 12, ui.Color.imperial_gold);
            }

            ui.endPanel(&ctx);
        }

        // Pause indicator
        if (state.paused) {
            ui.label(&ctx, "PAUSED", .{ .x = VIRTUAL_WIDTH / 2 - 60, .y = 20 }, 32, ui.Color.init(255, 200, 100, 255));
        }

        // FPS/Time display
        var time_buf: [64]u8 = undefined;
        const time_text = std.fmt.bufPrint(&time_buf, "Time: {d:.1}s", .{state.time}) catch "???";
        ui.label(&ctx, time_text, .{ .x = 20, .y = VIRTUAL_HEIGHT - 30 }, 12, ui.Color.gray);

        ctx.endFrame();
        renderer_2d.endFrame();

        bgfx.touch(0);
        _ = bgfx.frame(false);
    }
}

// ============================================================================
// Demo Initialization
// ============================================================================

fn initBouncingBoxes(state: *DemoState, random: std.Random) void {
    for (&state.boxes, 0..) |*box, i| {
        const size = 40 + random.float(f32) * 60;
        box.* = .{
            .x = random.float(f32) * (VIRTUAL_WIDTH - size),
            .y = random.float(f32) * (VIRTUAL_HEIGHT - 200),
            .width = size,
            .height = size,
            .color = DEMO_COLORS[i % DEMO_COLORS.len],
            .vel_x = (random.float(f32) - 0.5) * 400,
            .vel_y = (random.float(f32) - 0.5) * 400,
            .phase = random.float(f32) * std.math.tau,
        };
    }
}

// ============================================================================
// Demo Renderers
// ============================================================================

fn renderBouncingBoxes(state: *DemoState, ctx: *ui.Context) void {
    for (&state.boxes) |*box| {
        // Pulsing size effect
        const pulse = 1.0 + @sin(state.time * 3 + box.phase) * 0.1;
        const w = box.width * pulse;
        const h = box.height * pulse;
        const x = box.x - (w - box.width) / 2;
        const y = box.y - (h - box.height) / 2;

        ctx.renderer.drawRect(ui.Rect.init(x, y, w, h), box.color);

        // Draw border (saturating add to avoid overflow)
        const border_color = ui.Color.init(
            @min(@as(u16, 255), @as(u16, box.color.r) + 50),
            @min(@as(u16, 255), @as(u16, box.color.g) + 50),
            @min(@as(u16, 255), @as(u16, box.color.b) + 50),
            255,
        );
        ctx.renderer.drawRect(ui.Rect.init(x, y, w, 3), border_color);
        ctx.renderer.drawRect(ui.Rect.init(x, y + h - 3, w, 3), border_color);
        ctx.renderer.drawRect(ui.Rect.init(x, y, 3, h), border_color);
        ctx.renderer.drawRect(ui.Rect.init(x + w - 3, y, 3, h), border_color);
    }
}

fn renderColorWave(state: *DemoState, ctx: *ui.Context) void {
    const cols: u32 = 32;
    const rows: u32 = 18;
    const cell_w = VIRTUAL_WIDTH / @as(f32, @floatFromInt(cols));
    const cell_h = (VIRTUAL_HEIGHT - 100) / @as(f32, @floatFromInt(rows));

    var row: u32 = 0;
    while (row < rows) : (row += 1) {
        var col: u32 = 0;
        while (col < cols) : (col += 1) {
            const x = @as(f32, @floatFromInt(col)) * cell_w;
            const y = @as(f32, @floatFromInt(row)) * cell_h + 80;

            // Wave effect
            const wave = @sin(state.time * 2 + @as(f32, @floatFromInt(col)) * 0.3 + @as(f32, @floatFromInt(row)) * 0.2);
            const brightness = (wave + 1) / 2;

            // Color based on position and time
            const hue = (@as(f32, @floatFromInt(col + row)) / @as(f32, @floatFromInt(cols + rows)) + state.time * 0.1);
            const color = hsvToRgb(hue, 0.8, brightness);

            const padding: f32 = 2;
            ctx.renderer.drawRect(ui.Rect.init(x + padding, y + padding, cell_w - padding * 2, cell_h - padding * 2), color);
        }
    }
}

fn renderParticleSystem(state: *DemoState, ctx: *ui.Context) void {
    state.particles.render(ctx);

    // Draw spawn indicator at mouse (using virtual coordinates)
    ctx.renderer.drawRect(
        ui.Rect.init(state.virtual_mouse_x - 5, state.virtual_mouse_y - 5, 10, 10),
        ui.Color.init(255, 255, 255, 100),
    );
}

fn renderGridAnimation(state: *DemoState, ctx: *ui.Context) void {
    const grid_size: u32 = 12;
    const spacing: f32 = 80;
    const start_x = (VIRTUAL_WIDTH - @as(f32, @floatFromInt(grid_size - 1)) * spacing) / 2;
    const start_y = (VIRTUAL_HEIGHT - @as(f32, @floatFromInt(grid_size - 1)) * spacing) / 2;

    var row: u32 = 0;
    while (row < grid_size) : (row += 1) {
        var col: u32 = 0;
        while (col < grid_size) : (col += 1) {
            const base_x = start_x + @as(f32, @floatFromInt(col)) * spacing;
            const base_y = start_y + @as(f32, @floatFromInt(row)) * spacing;

            // Distance from center
            const cx = @as(f32, @floatFromInt(grid_size)) / 2;
            const dx = @as(f32, @floatFromInt(col)) - cx;
            const dy = @as(f32, @floatFromInt(row)) - cx;
            const dist = @sqrt(dx * dx + dy * dy);

            // Ripple effect
            const wave = @sin(state.grid_phase - dist * 0.5) * 0.5 + 0.5;
            const size = 10 + wave * 30;

            // Color based on wave
            const color_idx = @as(usize, @intFromFloat(wave * 7)) % DEMO_COLORS.len;
            const color = DEMO_COLORS[color_idx];

            ctx.renderer.drawRect(
                ui.Rect.init(base_x - size / 2, base_y - size / 2, size, size),
                color,
            );
        }
    }
}

fn renderConcentricShapes(state: *DemoState, ctx: *ui.Context) void {
    const center_x = VIRTUAL_WIDTH / 2;
    const center_y = VIRTUAL_HEIGHT / 2;
    const max_radius: f32 = 400;
    const ring_count: u32 = 20;

    var i: u32 = ring_count;
    while (i > 0) : (i -= 1) {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(ring_count));
        const radius = max_radius * t;

        // Pulsing effect
        const pulse = @sin(state.time * 2 - t * 5) * 0.2 + 1.0;
        const actual_radius = radius * pulse;

        // Rotating color
        const hue = t + state.time * 0.1;
        const color = hsvToRgb(hue, 0.7, 0.8);

        // Draw as rectangle (approximation of ring)
        const thickness: f32 = max_radius / @as(f32, @floatFromInt(ring_count)) * 0.8;
        ctx.renderer.drawRect(
            ui.Rect.init(
                center_x - actual_radius,
                center_y - actual_radius,
                actual_radius * 2,
                thickness,
            ),
            color,
        );
        ctx.renderer.drawRect(
            ui.Rect.init(
                center_x - actual_radius,
                center_y + actual_radius - thickness,
                actual_radius * 2,
                thickness,
            ),
            color,
        );
        ctx.renderer.drawRect(
            ui.Rect.init(
                center_x - actual_radius,
                center_y - actual_radius,
                thickness,
                actual_radius * 2,
            ),
            color,
        );
        ctx.renderer.drawRect(
            ui.Rect.init(
                center_x + actual_radius - thickness,
                center_y - actual_radius,
                thickness,
                actual_radius * 2,
            ),
            color,
        );
    }
}

// ============================================================================
// Helper Functions
// ============================================================================

fn hsvToRgb(h: f32, s: f32, v: f32) ui.Color {
    const hue = @mod(h, 1.0) * 6.0;
    const i = @as(u32, @intFromFloat(@floor(hue)));
    const f = hue - @floor(hue);
    const p = v * (1 - s);
    const q = v * (1 - s * f);
    const t = v * (1 - s * (1 - f));

    var r: f32 = 0;
    var g: f32 = 0;
    var b: f32 = 0;

    switch (i % 6) {
        0 => {
            r = v;
            g = t;
            b = p;
        },
        1 => {
            r = q;
            g = v;
            b = p;
        },
        2 => {
            r = p;
            g = v;
            b = t;
        },
        3 => {
            r = p;
            g = q;
            b = v;
        },
        4 => {
            r = t;
            g = p;
            b = v;
        },
        5 => {
            r = v;
            g = p;
            b = q;
        },
        else => {},
    }

    return ui.Color.init(
        @intFromFloat(r * 255),
        @intFromFloat(g * 255),
        @intFromFloat(b * 255),
        255,
    );
}

fn getNativeWindow(window: *c.SDL_Window) !*anyopaque {
    const props = c.SDL_GetWindowProperties(window);
    if (props == 0) return error.SDLGetPropertiesFailed;
    return c.SDL_GetPointerProperty(props, c.SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, null) orelse error.SDLGetNativeWindowFailed;
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

    if (!bgfx.init(&init)) return error.BgfxInitFailed;
}
