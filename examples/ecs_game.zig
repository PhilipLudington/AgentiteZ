// ECS Game Example - Demonstrates Entity-Component-System architecture
// Features: Player movement, enemy spawning, collision detection, scoring
const std = @import("std");
const AgentiteZ = @import("AgentiteZ");
const sdl = AgentiteZ.sdl;
const bgfx = AgentiteZ.bgfx;
const stb = AgentiteZ.stb_truetype;
const ui = AgentiteZ.ui;
const ecs = AgentiteZ.ecs;
const platform = AgentiteZ.platform;
const renderer = AgentiteZ.renderer;
const c = sdl.c;

// ============================================================================
// ECS Components
// ============================================================================

const Position = struct {
    x: f32,
    y: f32,
};

const Velocity = struct {
    x: f32,
    y: f32,
};

const Size = struct {
    width: f32,
    height: f32,
};

const EntityType = enum {
    player,
    enemy,
    projectile,
    pickup,
};

const Tag = struct {
    entity_type: EntityType,
};

const Health = struct {
    current: f32,
    max: f32,
};

const Lifetime = struct {
    remaining: f32,
};

// ============================================================================
// Game State
// ============================================================================

const GameState = struct {
    score: u32 = 0,
    enemies_spawned: u32 = 0,
    spawn_timer: f32 = 0,
    spawn_interval: f32 = 2.0,
    game_over: bool = false,
    paused: bool = false,

    // Player entity reference
    player_entity: ?ecs.Entity = null,
};

// ============================================================================
// Game Constants
// ============================================================================

const VIRTUAL_WIDTH: f32 = 1920;
const VIRTUAL_HEIGHT: f32 = 1080;
const PLAYER_SPEED: f32 = 400.0;
const ENEMY_SPEED: f32 = 150.0;
const PROJECTILE_SPEED: f32 = 600.0;
const PLAYER_SIZE: f32 = 40.0;
const ENEMY_SIZE: f32 = 30.0;
const PROJECTILE_SIZE: f32 = 10.0;
const PICKUP_SIZE: f32 = 20.0;

// ============================================================================
// Main Entry Point
// ============================================================================

pub fn main() !void {
    std.debug.print("AgentiteZ ECS Game Example\n", .{});
    std.debug.print("Controls: WASD/Arrow keys to move, SPACE to shoot, P to pause, ESC to quit\n\n", .{});

    // Initialize SDL3
    if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_EVENTS)) {
        std.debug.print("SDL_Init failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLInitFailed;
    }
    defer c.SDL_Quit();

    // Create window with HiDPI support
    const window = c.SDL_CreateWindow(
        "AgentiteZ - ECS Game Example",
        1280,
        720,
        c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_HIGH_PIXEL_DENSITY,
    ) orelse {
        std.debug.print("SDL_CreateWindow failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLCreateWindowFailed;
    };
    defer c.SDL_DestroyWindow(window);

    // Get native window handle for bgfx
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

    // Load font atlas
    const base_font_size: f32 = 24.0;
    var font_atlas = try renderer.FontAtlas.init(allocator, font_path, base_font_size * dpi_scale, false);
    defer font_atlas.deinit();
    renderer_2d.setExternalFontAtlas(&font_atlas);

    // Initialize input state
    var input_state = platform.InputState.init(allocator);
    defer input_state.deinit();

    // ========================================================================
    // Initialize ECS World
    // ========================================================================
    var world = ecs.World.init(allocator);
    defer world.deinit();

    // Component arrays
    var positions = ecs.ComponentArray(Position).init(allocator);
    defer positions.deinit();

    var velocities = ecs.ComponentArray(Velocity).init(allocator);
    defer velocities.deinit();

    var sizes = ecs.ComponentArray(Size).init(allocator);
    defer sizes.deinit();

    var tags = ecs.ComponentArray(Tag).init(allocator);
    defer tags.deinit();

    var healths = ecs.ComponentArray(Health).init(allocator);
    defer healths.deinit();

    var lifetimes = ecs.ComponentArray(Lifetime).init(allocator);
    defer lifetimes.deinit();

    // Game state
    var game_state = GameState{};

    // Create player entity
    const player = try world.createEntity();
    game_state.player_entity = player;
    try positions.add(player, .{ .x = VIRTUAL_WIDTH / 2, .y = VIRTUAL_HEIGHT / 2 });
    try velocities.add(player, .{ .x = 0, .y = 0 });
    try sizes.add(player, .{ .width = PLAYER_SIZE, .height = PLAYER_SIZE });
    try tags.add(player, .{ .entity_type = .player });
    try healths.add(player, .{ .current = 100, .max = 100 });

    // PRNG for enemy spawning
    var prng = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    const random = prng.random();

    // Timing
    var last_time = std.time.milliTimestamp();
    var shoot_cooldown: f32 = 0;

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

        // Event handling
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => running = false,
                c.SDL_EVENT_KEY_DOWN => {
                    if (event.key.key == c.SDLK_ESCAPE) running = false;
                    if (event.key.key == c.SDLK_P) game_state.paused = !game_state.paused;
                    if (event.key.key == c.SDLK_R and game_state.game_over) {
                        // Reset game
                        game_state = GameState{};
                        game_state.player_entity = player;
                        if (healths.get(player)) |h| {
                            h.current = h.max;
                        } else |_| {}
                        if (positions.get(player)) |p| {
                            p.x = VIRTUAL_WIDTH / 2;
                            p.y = VIRTUAL_HEIGHT / 2;
                        } else |_| {}
                    }
                },
                c.SDL_EVENT_WINDOW_RESIZED => {
                    window_width = @intCast(event.window.data1);
                    window_height = @intCast(event.window.data2);
                    var new_pixel_width: c_int = undefined;
                    var new_pixel_height: c_int = undefined;
                    _ = c.SDL_GetWindowSizeInPixels(window, &new_pixel_width, &new_pixel_height);
                    bgfx.reset(@intCast(new_pixel_width), @intCast(new_pixel_height), bgfx.ResetFlags_Vsync, bgfx.TextureFormat.Count);
                    renderer_2d.updateWindowSize(@intCast(new_pixel_width), @intCast(new_pixel_height));
                },
                else => {},
            }
            try input_state.handleEvent(&event);
        }

        // Update cooldowns
        if (shoot_cooldown > 0) shoot_cooldown -= dt;

        // Skip game logic if paused or game over
        if (!game_state.paused and !game_state.game_over) {
            // ================================================================
            // Player Input System
            // ================================================================
            if (game_state.player_entity) |player_ent| {
                if (velocities.get(player_ent)) |vel| {
                    vel.x = 0;
                    vel.y = 0;

                    // Use arrow keys for movement (check SDL keyboard state directly)
                    const keyboard_state = c.SDL_GetKeyboardState(null);
                    if (keyboard_state[@intCast(c.SDL_SCANCODE_UP)] or keyboard_state[@intCast(c.SDL_SCANCODE_W)]) vel.y = -PLAYER_SPEED;
                    if (keyboard_state[@intCast(c.SDL_SCANCODE_DOWN)] or keyboard_state[@intCast(c.SDL_SCANCODE_S)]) vel.y = PLAYER_SPEED;
                    if (keyboard_state[@intCast(c.SDL_SCANCODE_LEFT)] or keyboard_state[@intCast(c.SDL_SCANCODE_A)]) vel.x = -PLAYER_SPEED;
                    if (keyboard_state[@intCast(c.SDL_SCANCODE_RIGHT)] or keyboard_state[@intCast(c.SDL_SCANCODE_D)]) vel.x = PLAYER_SPEED;

                    // Normalize diagonal movement
                    if (vel.x != 0 and vel.y != 0) {
                        const factor = 0.7071; // 1/sqrt(2)
                        vel.x *= factor;
                        vel.y *= factor;
                    }
                } else |_| {}

                // Shooting (check space bar directly)
                const keyboard_state = c.SDL_GetKeyboardState(null);
                if (keyboard_state[@intCast(c.SDL_SCANCODE_SPACE)] and shoot_cooldown <= 0) {
                    if (positions.get(player_ent)) |player_pos| {
                        // Create projectile
                        const projectile = try world.createEntity();
                        try positions.add(projectile, .{
                            .x = player_pos.x,
                            .y = player_pos.y - PLAYER_SIZE / 2,
                        });
                        try velocities.add(projectile, .{ .x = 0, .y = -PROJECTILE_SPEED });
                        try sizes.add(projectile, .{ .width = PROJECTILE_SIZE, .height = PROJECTILE_SIZE });
                        try tags.add(projectile, .{ .entity_type = .projectile });
                        try lifetimes.add(projectile, .{ .remaining = 3.0 });
                        shoot_cooldown = 0.2;
                    } else |_| {}
                }
            }

            // ================================================================
            // Enemy Spawning System
            // ================================================================
            game_state.spawn_timer += dt;
            if (game_state.spawn_timer >= game_state.spawn_interval) {
                game_state.spawn_timer = 0;

                // Spawn enemy at random position along top edge
                const enemy = try world.createEntity();
                const spawn_x = random.float(f32) * (VIRTUAL_WIDTH - ENEMY_SIZE * 2) + ENEMY_SIZE;
                try positions.add(enemy, .{ .x = spawn_x, .y = -ENEMY_SIZE });
                try velocities.add(enemy, .{ .x = 0, .y = ENEMY_SPEED });
                try sizes.add(enemy, .{ .width = ENEMY_SIZE, .height = ENEMY_SIZE });
                try tags.add(enemy, .{ .entity_type = .enemy });
                try healths.add(enemy, .{ .current = 1, .max = 1 });

                game_state.enemies_spawned += 1;

                // Gradually increase difficulty
                if (game_state.spawn_interval > 0.5) {
                    game_state.spawn_interval -= 0.05;
                }
            }

            // ================================================================
            // Movement System
            // ================================================================
            var pos_iter = positions.iterator();
            while (pos_iter.next()) |entry| {
                const vel = velocities.get(entry.entity) catch continue;
                entry.component.x += vel.x * dt;
                entry.component.y += vel.y * dt;

                // Clamp player to screen bounds
                if (tags.get(entry.entity)) |tag| {
                    if (tag.entity_type == .player) {
                        if (sizes.get(entry.entity)) |size| {
                            entry.component.x = @max(size.width / 2, @min(VIRTUAL_WIDTH - size.width / 2, entry.component.x));
                            entry.component.y = @max(size.height / 2, @min(VIRTUAL_HEIGHT - size.height / 2, entry.component.y));
                        } else |_| {}
                    }
                } else |_| {}
            }

            // ================================================================
            // Lifetime System
            // ================================================================
            var lifetime_iter = lifetimes.iterator();
            while (lifetime_iter.next()) |entry| {
                entry.component.remaining -= dt;
                if (entry.component.remaining <= 0) {
                    // Mark for removal (simplified: just move off screen)
                    if (positions.get(entry.entity)) |pos| {
                        pos.y = -1000;
                    } else |_| {}
                }
            }

            // ================================================================
            // Collision Detection System
            // ================================================================
            var collision_iter = positions.iterator();
            while (collision_iter.next()) |entry| {
                const tag = tags.get(entry.entity) catch continue;
                const size = sizes.get(entry.entity) catch continue;

                // Check collisions based on entity type
                if (tag.entity_type == .projectile) {
                    // Projectile vs Enemy collision
                    var enemy_iter = positions.iterator();
                    while (enemy_iter.next()) |enemy_entry| {
                        if (enemy_entry.entity.id == entry.entity.id) continue;

                        const enemy_tag = tags.get(enemy_entry.entity) catch continue;
                        if (enemy_tag.entity_type == .enemy) {
                            const enemy_size = sizes.get(enemy_entry.entity) catch continue;
                            if (checkCollision(entry.component.*, size.*, enemy_entry.component.*, enemy_size.*)) {
                                // Destroy enemy and projectile
                                entry.component.y = -1000;
                                enemy_entry.component.y = -1000;
                                game_state.score += 10;
                            }
                        }
                    }
                } else if (tag.entity_type == .enemy) {
                    // Enemy vs Player collision
                    if (game_state.player_entity) |player_ent| {
                        const player_pos = positions.get(player_ent) catch continue;
                        const player_size = sizes.get(player_ent) catch continue;
                        if (checkCollision(entry.component.*, size.*, player_pos.*, player_size.*)) {
                            // Damage player
                            if (healths.get(player_ent)) |player_health| {
                                player_health.current -= 20;
                                if (player_health.current <= 0) {
                                    game_state.game_over = true;
                                }
                            } else |_| {}
                            // Remove enemy
                            entry.component.y = -1000;
                        }
                    }

                    // Remove enemies that go off screen
                    if (entry.component.y > VIRTUAL_HEIGHT + ENEMY_SIZE) {
                        entry.component.y = -1000;
                    }
                }
            }
        }

        // ====================================================================
        // Rendering
        // ====================================================================
        var current_pixel_width: c_int = undefined;
        var current_pixel_height: c_int = undefined;
        _ = c.SDL_GetWindowSizeInPixels(window, &current_pixel_width, &current_pixel_height);

        // Calculate letterbox viewport to maintain 16:9 aspect ratio
        const viewport = renderer.calculateLetterboxViewport(
            @intCast(current_pixel_width),
            @intCast(current_pixel_height),
            1920,
            1080,
        );

        // Set bgfx viewport to the letterboxed area
        bgfx.setViewRect(0, viewport.x, viewport.y, viewport.width, viewport.height);
        bgfx.setViewClear(0, bgfx.ClearFlags_Color | bgfx.ClearFlags_Depth, 0x1a1a2eff, 1.0, 0);

        // Update renderer with viewport info
        renderer_2d.setViewportFromInfo(viewport);

        renderer_2d.beginFrame();

        const current_window_info = ui.WindowInfo{
            .width = window_width,
            .height = window_height,
            .dpi_scale = dpi_scale,
        };
        const input = input_state.toUIInputState();
        ctx.beginFrame(input, current_window_info);

        // Render all entities
        var render_iter = positions.iterator();
        while (render_iter.next()) |entry| {
            // Skip entities that are "destroyed" (moved off screen)
            if (entry.component.y < -500) continue;

            const tag = tags.get(entry.entity) catch continue;
            const size = sizes.get(entry.entity) catch continue;

            const rect = ui.Rect.init(
                entry.component.x - size.width / 2,
                entry.component.y - size.height / 2,
                size.width,
                size.height,
            );

            const color: ui.Color = switch (tag.entity_type) {
                .player => ui.Color.init(100, 200, 255, 255), // Blue
                .enemy => ui.Color.init(255, 100, 100, 255), // Red
                .projectile => ui.Color.init(255, 255, 100, 255), // Yellow
                .pickup => ui.Color.init(100, 255, 100, 255), // Green
            };

            ctx.renderer.drawRect(rect, color);
        }

        // Draw player health bar
        if (game_state.player_entity) |player_ent| {
            if (healths.get(player_ent)) |health| {
                const bar_width: f32 = 200;
                const bar_height: f32 = 20;
                const bar_x: f32 = 20;
                const bar_y: f32 = VIRTUAL_HEIGHT - 40;

                // Background
                ctx.renderer.drawRect(ui.Rect.init(bar_x, bar_y, bar_width, bar_height), ui.Color.init(50, 50, 50, 255));

                // Health fill
                const fill_width = bar_width * (health.current / health.max);
                const health_color = if (health.current > 50)
                    ui.Color.init(100, 255, 100, 255)
                else if (health.current > 25)
                    ui.Color.init(255, 200, 100, 255)
                else
                    ui.Color.init(255, 100, 100, 255);
                ctx.renderer.drawRect(ui.Rect.init(bar_x, bar_y, fill_width, bar_height), health_color);
            } else |_| {}
        }

        // Draw UI
        ui.label(&ctx, "AgentiteZ - ECS Game Example", .{ .x = 20, .y = 20 }, 36, ui.Color.white);

        var score_buf: [64]u8 = undefined;
        const score_text = std.fmt.bufPrint(&score_buf, "Score: {d}", .{game_state.score}) catch "Score: ???";
        ui.label(&ctx, score_text, .{ .x = 20, .y = 65 }, 28, ui.Color.imperial_gold);

        var entities_buf: [64]u8 = undefined;
        const entities_text = std.fmt.bufPrint(&entities_buf, "Entities: {d}", .{world.entityCount()}) catch "Entities: ???";
        ui.label(&ctx, entities_text, .{ .x = 20, .y = 100 }, 22, ui.Color.gray);

        // Game over overlay
        if (game_state.game_over) {
            // Semi-transparent overlay
            ctx.renderer.drawRect(ui.Rect.init(0, 0, VIRTUAL_WIDTH, VIRTUAL_HEIGHT), ui.Color.init(0, 0, 0, 180));

            ui.label(&ctx, "GAME OVER", .{ .x = VIRTUAL_WIDTH / 2 - 180, .y = VIRTUAL_HEIGHT / 2 - 50 }, 72, ui.Color.init(255, 100, 100, 255));

            var final_score_buf: [64]u8 = undefined;
            const final_score_text = std.fmt.bufPrint(&final_score_buf, "Final Score: {d}", .{game_state.score}) catch "Final Score: ???";
            ui.label(&ctx, final_score_text, .{ .x = VIRTUAL_WIDTH / 2 - 120, .y = VIRTUAL_HEIGHT / 2 + 40 }, 36, ui.Color.white);

            ui.label(&ctx, "Press R to restart", .{ .x = VIRTUAL_WIDTH / 2 - 130, .y = VIRTUAL_HEIGHT / 2 + 100 }, 28, ui.Color.gray);
        }

        // Pause overlay
        if (game_state.paused and !game_state.game_over) {
            ctx.renderer.drawRect(ui.Rect.init(0, 0, VIRTUAL_WIDTH, VIRTUAL_HEIGHT), ui.Color.init(0, 0, 0, 150));
            ui.label(&ctx, "PAUSED", .{ .x = VIRTUAL_WIDTH / 2 - 100, .y = VIRTUAL_HEIGHT / 2 - 30 }, 72, ui.Color.white);
            ui.label(&ctx, "Press P to resume", .{ .x = VIRTUAL_WIDTH / 2 - 130, .y = VIRTUAL_HEIGHT / 2 + 60 }, 28, ui.Color.gray);
        }

        // Controls hint
        ui.label(&ctx, "WASD/Arrows: Move | SPACE: Shoot | P: Pause | ESC: Quit", .{ .x = VIRTUAL_WIDTH - 620, .y = VIRTUAL_HEIGHT - 40 }, 20, ui.Color.gray);

        ctx.endFrame();
        renderer_2d.endFrame();

        bgfx.touch(0);
        _ = bgfx.frame(false);
    }

    std.debug.print("Final Score: {d}\n", .{game_state.score});
}

// ============================================================================
// Helper Functions
// ============================================================================

fn checkCollision(pos_a: Position, size_a: Size, pos_b: Position, size_b: Size) bool {
    const a_left = pos_a.x - size_a.width / 2;
    const a_right = pos_a.x + size_a.width / 2;
    const a_top = pos_a.y - size_a.height / 2;
    const a_bottom = pos_a.y + size_a.height / 2;

    const b_left = pos_b.x - size_b.width / 2;
    const b_right = pos_b.x + size_b.width / 2;
    const b_top = pos_b.y - size_b.height / 2;
    const b_bottom = pos_b.y + size_b.height / 2;

    return a_left < b_right and a_right > b_left and a_top < b_bottom and a_bottom > b_top;
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
