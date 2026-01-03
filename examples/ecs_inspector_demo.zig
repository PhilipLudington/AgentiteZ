// ECS Inspector Demo - Demonstrates the ECS Inspector debug UI widget
// Features: Entity browser, component viewer/editor, archetype statistics
const std = @import("std");
const AgentiteZ = @import("AgentiteZ");
const sdl = AgentiteZ.sdl;
const bgfx = AgentiteZ.bgfx;
const stb = AgentiteZ.stb_truetype;
const ui = AgentiteZ.ui;
const ecs = AgentiteZ.ecs;
const prefab = AgentiteZ.prefab;
const platform = AgentiteZ.platform;
const renderer_mod = AgentiteZ.renderer;
const reflection = ecs.reflection;
const c = sdl.c;

// ============================================================================
// Demo Components - Various types to showcase reflection
// ============================================================================

const Position = struct {
    x: f32 = 0,
    y: f32 = 0,
};

const Velocity = struct {
    vx: f32 = 0,
    vy: f32 = 0,
};

const Health = struct {
    current: i32 = 100,
    max: i32 = 100,
    regenerating: bool = false,
};

const EntityInfo = struct {
    name_idx: u32 = 0,
    level: u32 = 1,
    active: bool = true,
};

const Physics = struct {
    mass: f32 = 1.0,
    friction: f32 = 0.1,
    bounce: f32 = 0.5,
};

const Render = struct {
    width: f32 = 32,
    height: f32 = 32,
    color_r: u8 = 255,
    color_g: u8 = 255,
    color_b: u8 = 255,
    visible: bool = true,
};

// ============================================================================
// Entity Names (for display)
// ============================================================================

const entity_names = [_][]const u8{
    "Player",
    "Enemy Scout",
    "Enemy Tank",
    "Projectile",
    "Pickup Health",
    "Pickup Ammo",
    "Obstacle",
    "Trigger Zone",
    "Particle",
    "NPC Merchant",
};

// ============================================================================
// Component Checker - Interface for ECS Inspector
// ============================================================================

const ComponentChecker = struct {
    positions: *ecs.ComponentArray(Position),
    velocities: *ecs.ComponentArray(Velocity),
    healths: *ecs.ComponentArray(Health),
    infos: *ecs.ComponentArray(EntityInfo),
    physics: *ecs.ComponentArray(Physics),
    renders: *ecs.ComponentArray(Render),
    registry: *const prefab.PrefabRegistry,

    pub fn hasComponent(self: *const ComponentChecker, entity: ecs.Entity, type_name: []const u8) bool {
        if (std.mem.eql(u8, type_name, @typeName(Position))) return self.positions.has(entity);
        if (std.mem.eql(u8, type_name, @typeName(Velocity))) return self.velocities.has(entity);
        if (std.mem.eql(u8, type_name, @typeName(Health))) return self.healths.has(entity);
        if (std.mem.eql(u8, type_name, @typeName(EntityInfo))) return self.infos.has(entity);
        if (std.mem.eql(u8, type_name, @typeName(Physics))) return self.physics.has(entity);
        if (std.mem.eql(u8, type_name, @typeName(Render))) return self.renders.has(entity);
        return false;
    }

    pub fn getComponentPtr(self: *const ComponentChecker, entity: ecs.Entity, type_name: []const u8) ?*anyopaque {
        if (std.mem.eql(u8, type_name, @typeName(Position))) {
            return @ptrCast(self.positions.get(entity) catch return null);
        }
        if (std.mem.eql(u8, type_name, @typeName(Velocity))) {
            return @ptrCast(self.velocities.get(entity) catch return null);
        }
        if (std.mem.eql(u8, type_name, @typeName(Health))) {
            return @ptrCast(self.healths.get(entity) catch return null);
        }
        if (std.mem.eql(u8, type_name, @typeName(EntityInfo))) {
            return @ptrCast(self.infos.get(entity) catch return null);
        }
        if (std.mem.eql(u8, type_name, @typeName(Physics))) {
            return @ptrCast(self.physics.get(entity) catch return null);
        }
        if (std.mem.eql(u8, type_name, @typeName(Render))) {
            return @ptrCast(self.renders.get(entity) catch return null);
        }
        return null;
    }
};

// ============================================================================
// Constants
// ============================================================================

const VIRTUAL_WIDTH: f32 = 1920;
const VIRTUAL_HEIGHT: f32 = 1080;
const INSPECTOR_WIDTH: f32 = 500;

// ============================================================================
// Main Entry Point
// ============================================================================

pub fn main() !void {
    std.debug.print("AgentiteZ ECS Inspector Demo\n", .{});
    std.debug.print("Features: Entity browser, component viewer/editor, archetype statistics\n", .{});
    std.debug.print("Controls: Click entities in browser, edit values, switch tabs\n\n", .{});

    // Initialize SDL3
    if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_EVENTS)) {
        std.debug.print("SDL_Init failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLInitFailed;
    }
    defer c.SDL_Quit();

    // Create window
    const window = c.SDL_CreateWindow(
        "AgentiteZ - ECS Inspector Demo",
        1600,
        900,
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
    var font_atlas = try renderer_mod.FontAtlas.init(allocator, font_path, base_font_size * dpi_scale, false);
    defer font_atlas.deinit();
    renderer_2d.setExternalFontAtlas(&font_atlas);

    // Initialize input state
    var input_state = platform.InputState.init(allocator);
    defer input_state.deinit();

    // ========================================================================
    // Initialize ECS World and Prefab Registry
    // ========================================================================
    var world = ecs.World.init(allocator);
    defer world.deinit();

    // Component arrays
    var positions = ecs.ComponentArray(Position).init(allocator);
    defer positions.deinit();

    var velocities = ecs.ComponentArray(Velocity).init(allocator);
    defer velocities.deinit();

    var healths = ecs.ComponentArray(Health).init(allocator);
    defer healths.deinit();

    var infos = ecs.ComponentArray(EntityInfo).init(allocator);
    defer infos.deinit();

    var physics_comps = ecs.ComponentArray(Physics).init(allocator);
    defer physics_comps.deinit();

    var renders = ecs.ComponentArray(Render).init(allocator);
    defer renders.deinit();

    // Prefab registry with reflection support
    var registry = prefab.PrefabRegistry.init(allocator);
    defer registry.deinit();

    // Register components with reflection
    try registry.registerComponentTypeWithReflection(Position, &positions);
    try registry.registerComponentTypeWithReflection(Velocity, &velocities);
    try registry.registerComponentTypeWithReflection(Health, &healths);
    try registry.registerComponentTypeWithReflection(EntityInfo, &infos);
    try registry.registerComponentTypeWithReflection(Physics, &physics_comps);
    try registry.registerComponentTypeWithReflection(Render, &renders);

    // Component checker for inspector
    var checker = ComponentChecker{
        .positions = &positions,
        .velocities = &velocities,
        .healths = &healths,
        .infos = &infos,
        .physics = &physics_comps,
        .renders = &renders,
        .registry = &registry,
    };

    // ========================================================================
    // Create Demo Entities
    // ========================================================================
    var entities: std.ArrayList(ecs.Entity) = .{};
    defer entities.deinit(allocator);

    var prng = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    const random = prng.random();

    // Player entity (all components)
    {
        const player = try world.createEntity();
        try entities.append(allocator, player);
        try positions.add(player, .{ .x = 400, .y = 300 });
        try velocities.add(player, .{ .vx = 0, .vy = 0 });
        try healths.add(player, .{ .current = 85, .max = 100, .regenerating = true });
        try infos.add(player, .{ .name_idx = 0, .level = 5, .active = true });
        try physics_comps.add(player, .{ .mass = 1.5, .friction = 0.2, .bounce = 0.3 });
        try renders.add(player, .{ .width = 48, .height = 48, .color_r = 100, .color_g = 200, .color_b = 255, .visible = true });
    }

    // Enemy entities
    for (1..4) |i| {
        const enemy = try world.createEntity();
        try entities.append(allocator, enemy);
        try positions.add(enemy, .{
            .x = 200 + random.float(f32) * 600,
            .y = 100 + random.float(f32) * 400,
        });
        try velocities.add(enemy, .{
            .vx = (random.float(f32) - 0.5) * 100,
            .vy = (random.float(f32) - 0.5) * 100,
        });
        try healths.add(enemy, .{
            .current = @intCast(50 + random.intRangeAtMost(u32, 0, 50)),
            .max = 100,
            .regenerating = false,
        });
        try infos.add(enemy, .{
            .name_idx = @intCast(i),
            .level = @intCast(1 + random.intRangeAtMost(u32, 0, 3)),
            .active = true,
        });
        try renders.add(enemy, .{
            .width = 36,
            .height = 36,
            .color_r = 255,
            .color_g = 100,
            .color_b = 100,
            .visible = true,
        });
    }

    // Projectiles (no health)
    for (0..3) |_| {
        const proj = try world.createEntity();
        try entities.append(allocator, proj);
        try positions.add(proj, .{
            .x = 300 + random.float(f32) * 400,
            .y = 200 + random.float(f32) * 200,
        });
        try velocities.add(proj, .{
            .vx = (random.float(f32) - 0.5) * 300,
            .vy = -200 - random.float(f32) * 100,
        });
        try infos.add(proj, .{ .name_idx = 3, .level = 1, .active = true });
        try renders.add(proj, .{
            .width = 8,
            .height = 16,
            .color_r = 255,
            .color_g = 255,
            .color_b = 100,
            .visible = true,
        });
    }

    // Pickups (no velocity/physics)
    for (0..2) |i| {
        const pickup = try world.createEntity();
        try entities.append(allocator, pickup);
        try positions.add(pickup, .{
            .x = 150 + @as(f32, @floatFromInt(i)) * 200,
            .y = 400 + random.float(f32) * 100,
        });
        try healths.add(pickup, .{ .current = 25, .max = 25, .regenerating = false });
        try infos.add(pickup, .{ .name_idx = @intCast(4 + i), .level = 1, .active = true });
        try renders.add(pickup, .{
            .width = 24,
            .height = 24,
            .color_r = 100,
            .color_g = 255,
            .color_b = 100,
            .visible = true,
        });
    }

    // Static obstacles (position + render only)
    for (0..3) |i| {
        const obstacle = try world.createEntity();
        try entities.append(allocator, obstacle);
        try positions.add(obstacle, .{
            .x = 100 + @as(f32, @floatFromInt(i)) * 300,
            .y = 500,
        });
        try infos.add(obstacle, .{ .name_idx = 6, .level = 1, .active = true });
        try physics_comps.add(obstacle, .{ .mass = 10.0, .friction = 0.8, .bounce = 0.1 });
        try renders.add(obstacle, .{
            .width = 64,
            .height = 64,
            .color_r = 128,
            .color_g = 128,
            .color_b = 128,
            .visible = true,
        });
    }

    std.debug.print("Created {d} demo entities\n", .{entities.items.len});

    // ========================================================================
    // Inspector State
    // ========================================================================
    var inspector_state = ui.widgets.EcsInspectorState{};

    // Timing
    var last_time = std.time.milliTimestamp();

    // Main loop
    var running = true;
    var event: c.SDL_Event = undefined;
    var show_inspector = true;

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
                    if (event.key.key == c.SDLK_I) show_inspector = !show_inspector;
                    if (event.key.key == c.SDLK_SPACE) {
                        // Add a new entity
                        const new_ent = try world.createEntity();
                        try entities.append(allocator, new_ent);
                        try positions.add(new_ent, .{
                            .x = 100 + random.float(f32) * 700,
                            .y = 100 + random.float(f32) * 400,
                        });
                        try velocities.add(new_ent, .{
                            .vx = (random.float(f32) - 0.5) * 200,
                            .vy = (random.float(f32) - 0.5) * 200,
                        });
                        try infos.add(new_ent, .{
                            .name_idx = @intCast(random.intRangeAtMost(u32, 0, entity_names.len - 1)),
                            .level = @intCast(1 + random.intRangeAtMost(u32, 0, 10)),
                            .active = true,
                        });
                        try renders.add(new_ent, .{
                            .width = 20 + random.float(f32) * 40,
                            .height = 20 + random.float(f32) * 40,
                            .color_r = @intCast(random.intRangeAtMost(u32, 50, 255)),
                            .color_g = @intCast(random.intRangeAtMost(u32, 50, 255)),
                            .color_b = @intCast(random.intRangeAtMost(u32, 50, 255)),
                            .visible = true,
                        });
                        std.debug.print("Added new entity {d}\n", .{new_ent.id});
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

        // ====================================================================
        // Update - Simple movement
        // ====================================================================
        var pos_iter = positions.iterator();
        while (pos_iter.next()) |entry| {
            if (velocities.get(entry.entity)) |vel| {
                entry.component.x += vel.vx * dt;
                entry.component.y += vel.vy * dt;

                // Bounce off edges (game area, not inspector)
                const game_width = VIRTUAL_WIDTH - (if (show_inspector) INSPECTOR_WIDTH + 20 else 0);
                if (entry.component.x < 50 or entry.component.x > game_width - 50) {
                    vel.vx = -vel.vx;
                    entry.component.x = std.math.clamp(entry.component.x, 50, game_width - 50);
                }
                if (entry.component.y < 50 or entry.component.y > VIRTUAL_HEIGHT - 100) {
                    vel.vy = -vel.vy;
                    entry.component.y = std.math.clamp(entry.component.y, 50, VIRTUAL_HEIGHT - 100);
                }
            } else |_| {}
        }

        // ====================================================================
        // Rendering
        // ====================================================================
        var current_pixel_width: c_int = undefined;
        var current_pixel_height: c_int = undefined;
        _ = c.SDL_GetWindowSizeInPixels(window, &current_pixel_width, &current_pixel_height);

        // Calculate viewport
        const viewport = renderer_mod.calculateLetterboxViewport(
            @intCast(current_pixel_width),
            @intCast(current_pixel_height),
            1920,
            1080,
        );

        bgfx.setViewRect(0, viewport.x, viewport.y, viewport.width, viewport.height);
        bgfx.setViewClear(0, bgfx.ClearFlags_Color | bgfx.ClearFlags_Depth, 0x1a1a2eff, 1.0, 0);

        renderer_2d.setViewportFromInfo(viewport);
        renderer_2d.beginFrame();

        const current_window_info = ui.WindowInfo{
            .width = window_width,
            .height = window_height,
            .dpi_scale = dpi_scale,
        };
        const input = input_state.toUIInputState();
        ctx.beginFrame(input, current_window_info);

        // Draw game area background
        const game_width = VIRTUAL_WIDTH - (if (show_inspector) INSPECTOR_WIDTH + 20 else 0);
        ctx.renderer.drawRect(ui.Rect.init(0, 0, game_width, VIRTUAL_HEIGHT), ui.Color.init(30, 30, 45, 255));

        // Render all entities
        var render_iter = positions.iterator();
        while (render_iter.next()) |entry| {
            const render_comp = renders.get(entry.entity) catch continue;
            if (!render_comp.visible) continue;

            const rect = ui.Rect.init(
                entry.component.x - render_comp.width / 2,
                entry.component.y - render_comp.height / 2,
                render_comp.width,
                render_comp.height,
            );

            const color = ui.Color.init(render_comp.color_r, render_comp.color_g, render_comp.color_b, 255);
            ctx.renderer.drawRect(rect, color);

            // Highlight selected entity
            if (inspector_state.selected_entity) |sel| {
                if (sel.id == entry.entity.id and sel.generation == entry.entity.generation) {
                    ctx.renderer.drawRectOutline(
                        ui.Rect.init(rect.x - 3, rect.y - 3, rect.width + 6, rect.height + 6),
                        ui.Color.imperial_gold,
                        2.0,
                    );
                }
            }
        }

        // Draw UI labels
        ui.label(&ctx, "AgentiteZ - ECS Inspector Demo", .{ .x = 20, .y = 20 }, 32, ui.Color.white);

        var entity_buf: [64]u8 = undefined;
        const entity_text = std.fmt.bufPrint(&entity_buf, "Entities: {d}", .{entities.items.len}) catch "???";
        ui.label(&ctx, entity_text, .{ .x = 20, .y = 60 }, 22, ui.Color.imperial_gold);

        ui.label(&ctx, "Press SPACE to add entity | I to toggle inspector | ESC to quit", .{ .x = 20, .y = VIRTUAL_HEIGHT - 40 }, 18, ui.Color.gray);

        // Draw ECS Inspector
        if (show_inspector) {
            const inspector_rect = ui.Rect.init(
                VIRTUAL_WIDTH - INSPECTOR_WIDTH - 10,
                10,
                INSPECTOR_WIDTH,
                VIRTUAL_HEIGHT - 20,
            );

            const result = ui.widgets.ecsInspector(
                &ctx,
                "ecs_inspector",
                inspector_rect,
                &registry,
                entities.items,
                &checker,
                &inspector_state,
            );

            if (result.entity_changed) {
                std.debug.print("Selected entity changed\n", .{});
            }
            if (result.field_modified) {
                std.debug.print("Field modified: {s}.{s}\n", .{
                    result.modified_component orelse "?",
                    result.modified_field orelse "?",
                });
            }
        }

        ctx.endFrame();
        renderer_2d.endFrame();

        bgfx.touch(0);
        _ = bgfx.frame(false);
    }

    std.debug.print("ECS Inspector Demo finished.\n", .{});
}

// ============================================================================
// Helper Functions
// ============================================================================

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
