// Trade System Demo - Demonstrates Inter-Region Trade Routes
// Features:
// - Multiple regions with production/consumption
// - Dynamic supply/demand pricing
// - Trade routes with transport costs
// - Goods in transit tracking
// - Trade agreements and embargoes
// - Per-turn trade reports
//
// Controls:
// - 1-4: Toggle trade routes (Food from Farmland, Ore from Mines, etc.)
// - A: Create free trade agreement between selected regions
// - E: Create embargo between Capital and Port
// - SPACE: Process turn (execute trades, update prices)
// - P: Pause/Resume all routes
// - ESC: Quit

const std = @import("std");
const AgentiteZ = @import("AgentiteZ");
const sdl = AgentiteZ.sdl;
const bgfx = AgentiteZ.bgfx;
const stb = AgentiteZ.stb_truetype;
const ui = AgentiteZ.ui;
const platform = AgentiteZ.platform;
const renderer = AgentiteZ.renderer;
const trade_mod = AgentiteZ.trade;
const c = sdl.c;

// Resources for trade
const Resource = enum {
    food,
    ore,
    luxury,
    weapons,

    pub fn getName(self: Resource) []const u8 {
        return switch (self) {
            .food => "Food",
            .ore => "Ore",
            .luxury => "Luxury",
            .weapons => "Weapons",
        };
    }

    pub fn getColor(self: Resource) ui.Color {
        return switch (self) {
            .food => ui.Color.init(120, 255, 120, 255), // Green
            .ore => ui.Color.init(180, 140, 100, 255), // Brown
            .luxury => ui.Color.init(255, 200, 100, 255), // Gold
            .weapons => ui.Color.init(200, 200, 220, 255), // Silver
        };
    }
};

// Trading regions
const Region = enum {
    capital,
    port_city,
    mining_town,
    farmland,

    pub fn getName(self: Region) []const u8 {
        return switch (self) {
            .capital => "Capital",
            .port_city => "Port City",
            .mining_town => "Mining Town",
            .farmland => "Farmland",
        };
    }

    pub fn getColor(self: Region) ui.Color {
        return switch (self) {
            .capital => ui.Color.init(255, 215, 0, 255), // Gold
            .port_city => ui.Color.init(100, 180, 255, 255), // Blue
            .mining_town => ui.Color.init(180, 140, 100, 255), // Brown
            .farmland => ui.Color.init(120, 200, 100, 255), // Green
        };
    }

    pub fn getPosition(self: Region) struct { x: f32, y: f32 } {
        return switch (self) {
            .capital => .{ .x = 960, .y = 200 },
            .port_city => .{ .x = 1400, .y = 350 },
            .mining_town => .{ .x = 520, .y = 400 },
            .farmland => .{ .x = 960, .y = 550 },
        };
    }
};

const TradeSystem = trade_mod.TradeSystem(Resource, Region);

const VIRTUAL_WIDTH: f32 = 1920;
const VIRTUAL_HEIGHT: f32 = 1080;

// Demo state for notifications
const Notification = struct {
    message: [128]u8 = undefined,
    len: usize = 0,
    timer: f32 = 0,
    color: ui.Color = ui.Color.init(255, 255, 255, 255),

    fn set(self: *Notification, msg: []const u8, col: ui.Color) void {
        const copy_len = @min(msg.len, self.message.len);
        @memcpy(self.message[0..copy_len], msg[0..copy_len]);
        self.len = copy_len;
        self.timer = 3.0;
        self.color = col;
    }

    fn update(self: *Notification, dt: f32) void {
        if (self.timer > 0) {
            self.timer -= dt;
        }
    }

    fn isActive(self: *const Notification) bool {
        return self.timer > 0;
    }

    fn getText(self: *const Notification) []const u8 {
        return self.message[0..self.len];
    }
};

// Track which routes are active by index
const RouteInfo = struct {
    id: ?u32 = null,
    source: Region,
    dest: Region,
    resource: Resource,
    amount: f32 = 30,
};

pub fn main() !void {
    std.debug.print("\n", .{});
    std.debug.print("===========================================\n", .{});
    std.debug.print("  AgentiteZ Trade System Demo\n", .{});
    std.debug.print("===========================================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Controls:\n", .{});
    std.debug.print("  1         - Toggle Food route (Farmland -> Capital)\n", .{});
    std.debug.print("  2         - Toggle Ore route (Mining Town -> Port City)\n", .{});
    std.debug.print("  3         - Toggle Luxury route (Port City -> Capital)\n", .{});
    std.debug.print("  4         - Toggle Weapons route (Mining Town -> Capital)\n", .{});
    std.debug.print("  A         - Create free trade (Capital <-> Port City)\n", .{});
    std.debug.print("  E         - Toggle embargo (Capital <-> Mining Town)\n", .{});
    std.debug.print("  SPACE     - Process turn\n", .{});
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
        "AgentiteZ - Trade System Demo",
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
    // Initialize Trade System
    // ========================================================================
    var ts = TradeSystem.initWithConfig(allocator, .{
        .base_transport_cost = 0.05,
        .base_travel_time = 1.0,
        .default_tariff_rate = 0.10,
        .price_elasticity = 0.3,
        .auto_update_prices = true,
    });
    defer ts.deinit();

    // Set up regional markets
    // Capital - high demand, low production
    ts.setBasePrice(.capital, .food, 100);
    ts.setBasePrice(.capital, .ore, 120);
    ts.setBasePrice(.capital, .luxury, 200);
    ts.setBasePrice(.capital, .weapons, 150);
    ts.setRegionDemand(.capital, .food, 80);
    ts.setRegionDemand(.capital, .ore, 40);
    ts.setRegionDemand(.capital, .luxury, 30);
    ts.setRegionDemand(.capital, .weapons, 20);
    ts.setStockpile(.capital, .food, 50);

    // Port City - luxury production, ore demand
    ts.setBasePrice(.port_city, .food, 90);
    ts.setBasePrice(.port_city, .ore, 100);
    ts.setBasePrice(.port_city, .luxury, 150);
    ts.setBasePrice(.port_city, .weapons, 180);
    ts.setRegionProduction(.port_city, .luxury, 60);
    ts.setRegionDemand(.port_city, .ore, 50);
    ts.setStockpile(.port_city, .luxury, 100);

    // Mining Town - ore production, weapon production
    ts.setBasePrice(.mining_town, .food, 110);
    ts.setBasePrice(.mining_town, .ore, 60);
    ts.setBasePrice(.mining_town, .luxury, 250);
    ts.setBasePrice(.mining_town, .weapons, 100);
    ts.setRegionProduction(.mining_town, .ore, 80);
    ts.setRegionProduction(.mining_town, .weapons, 40);
    ts.setRegionDemand(.mining_town, .food, 60);
    ts.setStockpile(.mining_town, .ore, 150);
    ts.setStockpile(.mining_town, .weapons, 80);

    // Farmland - food production
    ts.setBasePrice(.farmland, .food, 50);
    ts.setBasePrice(.farmland, .ore, 150);
    ts.setBasePrice(.farmland, .luxury, 220);
    ts.setBasePrice(.farmland, .weapons, 200);
    ts.setRegionProduction(.farmland, .food, 100);
    ts.setStockpile(.farmland, .food, 200);

    // Route definitions
    var routes = [_]RouteInfo{
        .{ .source = .farmland, .dest = .capital, .resource = .food, .amount = 40 },
        .{ .source = .mining_town, .dest = .port_city, .resource = .ore, .amount = 35 },
        .{ .source = .port_city, .dest = .capital, .resource = .luxury, .amount = 25 },
        .{ .source = .mining_town, .dest = .capital, .resource = .weapons, .amount = 20 },
    };

    // Notification state
    var notification = Notification{};

    // Embargo state
    var has_embargo = false;

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

        notification.update(dt);
        input_state.beginFrame();

        // Event handling
        while (c.SDL_PollEvent(&event)) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => running = false,
                c.SDL_EVENT_KEY_DOWN => {
                    const key = event.key.key;
                    if (key == c.SDLK_ESCAPE) running = false;

                    // Toggle routes (1-4)
                    const route_key: ?usize = if (key == c.SDLK_1) 0 else if (key == c.SDLK_2) 1 else if (key == c.SDLK_3) 2 else if (key == c.SDLK_4) 3 else null;
                    if (route_key) |i| {
                        var route = &routes[i];
                        if (route.id) |id| {
                            // Delete route
                            _ = ts.deleteRoute(id);
                            route.id = null;
                            var buf: [64]u8 = undefined;
                            const msg = std.fmt.bufPrint(&buf, "Route {d} disabled: {s} -> {s}", .{
                                i + 1,
                                route.source.getName(),
                                route.dest.getName(),
                            }) catch "Route disabled";
                            notification.set(msg, ui.Color.init(255, 150, 150, 255));
                        } else {
                            // Create route
                            if (ts.createRoute(.{
                                .source = route.source,
                                .destination = route.dest,
                                .resource = route.resource,
                                .amount_per_turn = route.amount,
                                .distance = 2.0,
                            })) |id| {
                                route.id = id;
                                var buf: [64]u8 = undefined;
                                const msg = std.fmt.bufPrint(&buf, "Route {d} enabled: {s} -> {s}", .{
                                    i + 1,
                                    route.source.getName(),
                                    route.dest.getName(),
                                }) catch "Route enabled";
                                notification.set(msg, ui.Color.init(150, 255, 150, 255));
                            } else |_| {
                                notification.set("Failed to create route", ui.Color.init(255, 100, 100, 255));
                            }
                        }
                    }

                    // Free trade agreement (A)
                    if (key == c.SDLK_A) {
                        ts.createAgreement(.capital, .port_city, .free_trade, 0, 0, null) catch {
                            notification.set("Failed to create agreement", ui.Color.init(255, 100, 100, 255));
                            continue;
                        };
                        notification.set("Free Trade: Capital <-> Port City", ui.Color.init(100, 200, 255, 255));
                    }

                    // Toggle embargo (E)
                    if (key == c.SDLK_E) {
                        if (has_embargo) {
                            ts.removeAgreement(.capital, .mining_town);
                            has_embargo = false;
                            notification.set("Embargo lifted: Capital <-> Mining Town", ui.Color.init(150, 255, 150, 255));
                        } else {
                            ts.createAgreement(.capital, .mining_town, .embargo, 0, 0, null) catch {
                                notification.set("Failed to create embargo", ui.Color.init(255, 100, 100, 255));
                                continue;
                            };
                            has_embargo = true;
                            notification.set("EMBARGO: Capital <-> Mining Town", ui.Color.init(255, 100, 100, 255));
                        }
                    }

                    // Process turn (SPACE)
                    if (key == c.SDLK_SPACE) {
                        const report = ts.processTurn() catch {
                            notification.set("Error processing turn", ui.Color.init(255, 80, 80, 255));
                            continue;
                        };
                        var buf: [128]u8 = undefined;
                        const msg = std.fmt.bufPrint(&buf, "Turn {d}: {d} trades, profit {d:.0}", .{
                            report.turn,
                            report.trades_executed,
                            report.total_profit,
                        }) catch "Turn processed";
                        if (report.total_profit >= 0) {
                            notification.set(msg, ui.Color.init(120, 255, 120, 255));
                        } else {
                            notification.set(msg, ui.Color.init(255, 180, 120, 255));
                        }
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
                    window_info.width = window_width;
                    window_info.height = window_height;
                },
                else => {},
            }
            try input_state.handleEvent(&event);
        }

        // ====================================================================
        // Render
        // ====================================================================
        bgfx.setViewClear(0, bgfx.ClearFlags_Color | bgfx.ClearFlags_Depth, 0x1a2a1aFF, 1.0, 0);
        bgfx.setViewRect(0, 0, 0, @intCast(pixel_width), @intCast(pixel_height));
        bgfx.touch(0);

        renderer_2d.beginFrame();
        const input = input_state.toUIInputState();
        ctx.beginFrame(input, window_info);

        const bright_text = ui.Color.init(230, 230, 240, 255);
        const dim_text = ui.Color.init(150, 150, 170, 255);

        // Title
        renderer_2d.drawText("Trade System Demo", .{ .x = 50, .y = 30 }, 36, ui.Color.init(255, 215, 0, 255));

        // Turn indicator
        var turn_buf: [32]u8 = undefined;
        const turn_str = std.fmt.bufPrint(&turn_buf, "Turn: {d}", .{ts.getCurrentTurn()}) catch "Turn: ?";
        renderer_2d.drawText(turn_str, .{ .x = VIRTUAL_WIDTH - 200, .y = 30 }, 32, bright_text);

        // ====================================================================
        // Draw Regions (as circles with info)
        // ====================================================================
        const regions = [_]Region{ .capital, .port_city, .mining_town, .farmland };
        const resources = [_]Resource{ .food, .ore, .luxury, .weapons };

        for (regions) |region| {
            const pos = region.getPosition();

            // Draw region circle
            renderer_2d.drawRect(ui.Rect{
                .x = pos.x - 60,
                .y = pos.y - 60,
                .width = 120,
                .height = 120,
            }, region.getColor());

            // Region name
            const name = region.getName();
            const name_bounds = renderer_2d.measureText(name, 24);
            renderer_2d.drawText(name, .{ .x = pos.x - name_bounds.x / 2, .y = pos.y - 50 }, 24, ui.Color.init(40, 40, 40, 255));

            // Stockpile info (text below region)
            var y_offset: f32 = 70;
            for (resources) |res| {
                const market = ts.getMarket(region, res);
                if (market.stockpile > 0 or market.production > 0 or market.demand > 0) {
                    var info_buf: [48]u8 = undefined;
                    const info_str = std.fmt.bufPrint(&info_buf, "{s}: {d:.0}", .{ res.getName(), market.stockpile }) catch "?";
                    renderer_2d.drawText(info_str, .{ .x = pos.x - 50, .y = pos.y + y_offset }, 18, res.getColor());
                    y_offset += 22;
                }
            }
        }

        // ====================================================================
        // Draw Trade Routes (as lines between regions)
        // ====================================================================
        for (routes, 0..) |route, i| {
            const src_pos = route.source.getPosition();
            const dst_pos = route.dest.getPosition();

            // Calculate line positions (offset from center)
            const dx = dst_pos.x - src_pos.x;
            const dy = dst_pos.y - src_pos.y;
            const dist = @sqrt(dx * dx + dy * dy);
            const nx = dx / dist;
            const ny = dy / dist;

            // Start/end points offset from region centers
            const start_x = src_pos.x + nx * 70;
            const start_y = src_pos.y + ny * 70;
            const end_x = dst_pos.x - nx * 70;
            const end_y = dst_pos.y - ny * 70;

            // Route color based on status
            var route_color: ui.Color = undefined;
            if (route.id) |id| {
                const full_route = ts.getRoute(id);
                if (full_route) |r| {
                    route_color = switch (r.status) {
                        .active => route.resource.getColor(),
                        .blocked => ui.Color.init(255, 80, 80, 255),
                        .insufficient_supply => ui.Color.init(255, 200, 80, 255),
                        else => ui.Color.init(100, 100, 100, 255),
                    };
                } else {
                    route_color = ui.Color.init(60, 60, 80, 255);
                }
            } else {
                route_color = ui.Color.init(60, 60, 80, 255);
            }

            // Draw route line (as thin rect)
            const line_width: f32 = if (route.id != null) 4 else 2;
            const angle = std.math.atan2(dy, dx);
            const cos_a = @cos(angle);
            const sin_a = @sin(angle);

            // Draw multiple small segments to approximate line
            const segments: usize = 20;
            for (0..segments) |s| {
                const t = @as(f32, @floatFromInt(s)) / @as(f32, @floatFromInt(segments));
                const seg_x = start_x + (end_x - start_x) * t;
                const seg_y = start_y + (end_y - start_y) * t;

                renderer_2d.drawRect(ui.Rect{
                    .x = seg_x - line_width / 2,
                    .y = seg_y - line_width / 2,
                    .width = (end_x - start_x) / @as(f32, @floatFromInt(segments)) + line_width,
                    .height = line_width,
                }, route_color);
            }

            // Route label
            const mid_x = (start_x + end_x) / 2;
            const mid_y = (start_y + end_y) / 2 - 15;
            var label_buf: [32]u8 = undefined;
            const label_str = std.fmt.bufPrint(&label_buf, "{d}: {s}", .{ i + 1, route.resource.getName() }) catch "?";
            renderer_2d.drawText(label_str, .{ .x = mid_x - 40, .y = mid_y }, 20, route_color);

            // Show amount if active
            if (route.id != null) {
                var amt_buf: [16]u8 = undefined;
                const amt_str = std.fmt.bufPrint(&amt_buf, "{d:.0}/t", .{route.amount}) catch "?";
                renderer_2d.drawText(amt_str, .{ .x = mid_x - 20, .y = mid_y + 22 }, 18, dim_text);
            }

            _ = cos_a;
            _ = sin_a;
        }

        // ====================================================================
        // Routes Panel (Left side)
        // ====================================================================
        try ui.beginPanel(&ctx, "Trade Routes", ui.Rect{
            .x = 50,
            .y = 80,
            .width = 380,
            .height = 280,
        }, ctx.theme.panel_bg);

        renderer_2d.drawText("Active Routes:", .{ .x = 70, .y = 115 }, 24, bright_text);

        for (routes, 0..) |route, i| {
            const y_pos: f32 = 150 + @as(f32, @floatFromInt(i)) * 38;

            var route_buf: [64]u8 = undefined;
            const status_str = if (route.id) |id| blk: {
                if (ts.getRoute(id)) |r| {
                    break :blk switch (r.status) {
                        .active => "Active",
                        .blocked => "BLOCKED",
                        .insufficient_supply => "Low Supply",
                        else => "Inactive",
                    };
                }
                break :blk "Unknown";
            } else "Disabled";

            const route_str = std.fmt.bufPrint(&route_buf, "[{d}] {s} -> {s}: {s}", .{
                i + 1,
                route.source.getName(),
                route.dest.getName(),
                status_str,
            }) catch "?";

            const color = if (route.id != null) route.resource.getColor() else dim_text;
            renderer_2d.drawText(route_str, .{ .x = 70, .y = y_pos }, 20, color);
        }

        ui.endPanel(&ctx);

        // ====================================================================
        // In Transit Panel (Below routes)
        // ====================================================================
        try ui.beginPanel(&ctx, "Goods in Transit", ui.Rect{
            .x = 50,
            .y = 380,
            .width = 380,
            .height = 220,
        }, ctx.theme.panel_bg);

        renderer_2d.drawText("Shipments:", .{ .x = 70, .y = 415 }, 24, bright_text);

        const in_transit = ts.getInTransit();
        if (in_transit.len == 0) {
            renderer_2d.drawText("No shipments in transit", .{ .x = 70, .y = 455 }, 20, dim_text);
        } else {
            var transit_y: f32 = 455;
            for (in_transit, 0..) |shipment, i| {
                if (i >= 5) {
                    renderer_2d.drawText("...", .{ .x = 70, .y = transit_y }, 18, dim_text);
                    break;
                }
                var transit_buf: [64]u8 = undefined;
                const transit_str = std.fmt.bufPrint(&transit_buf, "{s}: {d:.0} -> {s} (T{d})", .{
                    shipment.resource.getName(),
                    shipment.amount,
                    shipment.destination.getName(),
                    shipment.arrival_turn,
                }) catch "?";
                renderer_2d.drawText(transit_str, .{ .x = 70, .y = transit_y }, 18, shipment.resource.getColor());
                transit_y += 26;
            }
        }

        ui.endPanel(&ctx);

        // ====================================================================
        // Market Prices Panel (Right side)
        // ====================================================================
        try ui.beginPanel(&ctx, "Market Prices", ui.Rect{
            .x = VIRTUAL_WIDTH - 420,
            .y = 80,
            .width = 370,
            .height = 520,
        }, ctx.theme.panel_bg);

        renderer_2d.drawText("Current Prices:", .{ .x = VIRTUAL_WIDTH - 400, .y = 115 }, 24, bright_text);

        var row: f32 = 0;
        for (regions) |region| {
            const y_base: f32 = 155 + row * 115;
            renderer_2d.drawText(region.getName(), .{ .x = VIRTUAL_WIDTH - 400, .y = y_base }, 22, region.getColor());

            for (resources, 0..) |res, j| {
                const market = ts.getMarket(region, res);
                if (market.base_price > 0) {
                    const y_pos = y_base + 28 + @as(f32, @floatFromInt(j)) * 22;
                    var price_buf: [48]u8 = undefined;
                    const price_change = (market.current_price / market.base_price - 1) * 100;
                    const price_str = std.fmt.bufPrint(&price_buf, "  {s}: {d:.0} ({s}{d:.0}%)", .{
                        res.getName(),
                        market.current_price,
                        if (price_change >= 0) "+" else "",
                        price_change,
                    }) catch "?";
                    const price_color = if (price_change > 5)
                        ui.Color.init(255, 150, 150, 255)
                    else if (price_change < -5)
                        ui.Color.init(150, 255, 150, 255)
                    else
                        dim_text;
                    renderer_2d.drawText(price_str, .{ .x = VIRTUAL_WIDTH - 400, .y = y_pos }, 18, price_color);
                }
            }
            row += 1;
        }

        ui.endPanel(&ctx);

        // ====================================================================
        // Trade Report Panel (Bottom center)
        // ====================================================================
        try ui.beginPanel(&ctx, "Trade Report", ui.Rect{
            .x = 450,
            .y = 620,
            .width = 550,
            .height = 200,
        }, ctx.theme.panel_bg);

        if (ts.getLastReport()) |report| {
            var report_buf: [128]u8 = undefined;
            const report_str = std.fmt.bufPrint(&report_buf, "Turn {d}: {d} trades executed", .{
                report.turn,
                report.trades_executed,
            }) catch "?";
            renderer_2d.drawText(report_str, .{ .x = 470, .y = 660 }, 26, bright_text);

            var revenue_buf: [64]u8 = undefined;
            const revenue_str = std.fmt.bufPrint(&revenue_buf, "Revenue: {d:.0}  Costs: {d:.0}  Tariffs: {d:.0}", .{
                report.total_revenue,
                report.total_transport_costs,
                report.total_tariffs,
            }) catch "?";
            renderer_2d.drawText(revenue_str, .{ .x = 470, .y = 700 }, 20, dim_text);

            var profit_buf: [64]u8 = undefined;
            const profit_str = std.fmt.bufPrint(&profit_buf, "Net Profit: {s}{d:.0}", .{
                if (report.total_profit >= 0) "+" else "",
                report.total_profit,
            }) catch "?";
            const profit_color = if (report.total_profit >= 0) ui.Color.init(120, 255, 120, 255) else ui.Color.init(255, 120, 120, 255);
            renderer_2d.drawText(profit_str, .{ .x = 470, .y = 740 }, 28, profit_color);
        } else {
            renderer_2d.drawText("Press SPACE to process first turn", .{ .x = 470, .y = 700 }, 24, dim_text);
        }

        ui.endPanel(&ctx);

        // ====================================================================
        // Agreements Panel (Bottom right)
        // ====================================================================
        try ui.beginPanel(&ctx, "Trade Agreements", ui.Rect{
            .x = VIRTUAL_WIDTH - 420,
            .y = 620,
            .width = 370,
            .height = 200,
        }, ctx.theme.panel_bg);

        renderer_2d.drawText("Agreements:", .{ .x = VIRTUAL_WIDTH - 400, .y = 655 }, 24, bright_text);

        const agreements = ts.getAgreements();
        if (agreements.len == 0) {
            renderer_2d.drawText("No active agreements", .{ .x = VIRTUAL_WIDTH - 400, .y = 695 }, 20, dim_text);
            renderer_2d.drawText("Press A for free trade", .{ .x = VIRTUAL_WIDTH - 400, .y = 725 }, 18, dim_text);
            renderer_2d.drawText("Press E for embargo", .{ .x = VIRTUAL_WIDTH - 400, .y = 750 }, 18, dim_text);
        } else {
            var agree_y: f32 = 695;
            for (agreements) |agreement| {
                var agree_buf: [64]u8 = undefined;
                const type_str = switch (agreement.agreement_type) {
                    .free_trade => "Free Trade",
                    .embargo => "EMBARGO",
                    .most_favored_nation => "MFN",
                    else => "Agreement",
                };
                const agree_str = std.fmt.bufPrint(&agree_buf, "{s} <-> {s}: {s}", .{
                    agreement.party_a.getName(),
                    agreement.party_b.getName(),
                    type_str,
                }) catch "?";
                const agree_color = if (agreement.agreement_type == .embargo)
                    ui.Color.init(255, 100, 100, 255)
                else
                    ui.Color.init(100, 200, 255, 255);
                renderer_2d.drawText(agree_str, .{ .x = VIRTUAL_WIDTH - 400, .y = agree_y }, 20, agree_color);
                agree_y += 30;
            }
        }

        ui.endPanel(&ctx);

        // ====================================================================
        // Controls hint
        // ====================================================================
        renderer_2d.drawText("1-4: Toggle Routes  |  A: Free Trade  |  E: Embargo  |  SPACE: Process Turn  |  ESC: Quit", .{ .x = 50, .y = VIRTUAL_HEIGHT - 50 }, 22, dim_text);

        // ====================================================================
        // Notification
        // ====================================================================
        if (notification.isActive()) {
            const alpha: u8 = @intFromFloat(@min(255, notification.timer * 255));
            var notif_color = notification.color;
            notif_color.a = alpha;

            const notif_text = notification.getText();
            const text_bounds = renderer_2d.measureText(notif_text, 32);
            const notif_x = (VIRTUAL_WIDTH - text_bounds.x) / 2;

            renderer_2d.drawText(notif_text, .{ .x = notif_x, .y = 850 }, 32, notif_color);
        }

        ctx.endFrame();
        renderer_2d.endFrame();

        _ = bgfx.frame(false);
    }

    std.debug.print("\nTrade Demo ended.\n", .{});
    std.debug.print("Total trades: {d}\n", .{ts.getHistory().len});
    std.debug.print("Total revenue: {d:.0}\n", .{ts.getTotalRevenue()});
    std.debug.print("Total profit: {d:.0}\n", .{ts.getTotalProfit()});
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
    bgfx.setViewClear(0, bgfx.ClearFlags_Color | bgfx.ClearFlags_Depth, 0x1a2a1aFF, 1.0, 0);
    bgfx.setViewRect(0, 0, 0, @intCast(width), @intCast(height));
}
