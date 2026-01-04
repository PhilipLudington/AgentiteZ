// Finance System Demo - Demonstrates Economic Management
// Features:
// - Treasury and debt tracking
// - Income/expense recording with categories
// - Budget allocation and utilization visualization
// - Loan management with interest
// - Per-turn financial reports
// - Deficit and reserve warnings
//
// Controls:
// - 1-5: Add income to different categories
// - Q-T: Add expenses to different categories
// - L: Take a loan
// - R: Repay loan
// - SPACE: End turn (generates report)
// - ESC: Quit

const std = @import("std");
const AgentiteZ = @import("AgentiteZ");
const sdl = AgentiteZ.sdl;
const bgfx = AgentiteZ.bgfx;
const stb = AgentiteZ.stb_truetype;
const ui = AgentiteZ.ui;
const platform = AgentiteZ.platform;
const renderer = AgentiteZ.renderer;
const finance_mod = AgentiteZ.finance;
const c = sdl.c;

// Budget categories for the demo
const Category = enum {
    military,
    research,
    infrastructure,
    trade,
    diplomacy,

    pub fn getName(self: Category) []const u8 {
        return switch (self) {
            .military => "Military",
            .research => "Research",
            .infrastructure => "Infrastructure",
            .trade => "Trade",
            .diplomacy => "Diplomacy",
        };
    }

    pub fn getColor(self: Category) ui.Color {
        return switch (self) {
            .military => ui.Color.init(255, 120, 120, 255), // Bright Red
            .research => ui.Color.init(120, 200, 255, 255), // Bright Blue
            .infrastructure => ui.Color.init(255, 220, 100, 255), // Bright Yellow
            .trade => ui.Color.init(120, 255, 160, 255), // Bright Green
            .diplomacy => ui.Color.init(220, 150, 255, 255), // Bright Purple
        };
    }
};

const FinanceManager = finance_mod.FinanceManager(Category);

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

pub fn main() !void {
    std.debug.print("\n", .{});
    std.debug.print("===========================================\n", .{});
    std.debug.print("  AgentiteZ Finance System Demo\n", .{});
    std.debug.print("===========================================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Controls:\n", .{});
    std.debug.print("  1-5       - Add income (Military/Research/Infra/Trade/Diplomacy)\n", .{});
    std.debug.print("  Q-T       - Add expense (Military/Research/Infra/Trade/Diplomacy)\n", .{});
    std.debug.print("  L         - Take a loan (1000 @ 5%)\n", .{});
    std.debug.print("  R         - Repay loan (500)\n", .{});
    std.debug.print("  SPACE     - End turn (process finances)\n", .{});
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
        "AgentiteZ - Finance System Demo",
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
    // Initialize Finance System
    // ========================================================================
    var fm = FinanceManager.initWithConfig(allocator, .{
        .deficit_policy = .allow_debt,
        .treasury_policy = .warn_only,
        .debt_interest_rate = 0.05,
        .reserve_threshold = 500,
    });
    defer fm.deinit();

    // Set initial treasury
    fm.setTreasury(5000);

    // Set up budgets
    fm.setBudget(.military, .{ .allocated = 2000, .priority = 1 });
    fm.setBudget(.research, .{ .allocated = 1500, .priority = 2 });
    fm.setBudget(.infrastructure, .{ .allocated = 1000, .priority = 3 });
    fm.setBudget(.trade, .{ .allocated = 500, .priority = 4 });
    fm.setBudget(.diplomacy, .{ .allocated = 500, .priority = 5 });

    // Notification state
    var notification = Notification{};

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

                    // Income keys (1-5)
                    if (key == c.SDLK_1) {
                        fm.recordIncome(.military, 500, "Military contract") catch {};
                        notification.set("+500 Military Income", Category.military.getColor());
                    }
                    if (key == c.SDLK_2) {
                        fm.recordIncome(.research, 400, "Research grant") catch {};
                        notification.set("+400 Research Income", Category.research.getColor());
                    }
                    if (key == c.SDLK_3) {
                        fm.recordIncome(.infrastructure, 300, "Toll revenue") catch {};
                        notification.set("+300 Infrastructure Income", Category.infrastructure.getColor());
                    }
                    if (key == c.SDLK_4) {
                        fm.recordIncome(.trade, 600, "Export revenue") catch {};
                        notification.set("+600 Trade Income", Category.trade.getColor());
                    }
                    if (key == c.SDLK_5) {
                        fm.recordIncome(.diplomacy, 200, "Treaty bonus") catch {};
                        notification.set("+200 Diplomacy Income", Category.diplomacy.getColor());
                    }

                    // Expense keys (Q-T)
                    if (key == c.SDLK_Q) {
                        const result = fm.recordExpense(.military, 300, "Unit upkeep") catch .blocked_by_policy;
                        if (result == .success) {
                            notification.set("-300 Military Expense", ui.Color.init(255, 150, 150, 255));
                        } else {
                            notification.set("Expense blocked!", ui.Color.init(255, 80, 80, 255));
                        }
                    }
                    if (key == c.SDLK_W) {
                        const result = fm.recordExpense(.research, 250, "Lab costs") catch .blocked_by_policy;
                        if (result == .success) {
                            notification.set("-250 Research Expense", ui.Color.init(150, 200, 255, 255));
                        } else {
                            notification.set("Expense blocked!", ui.Color.init(255, 80, 80, 255));
                        }
                    }
                    if (key == c.SDLK_E) {
                        const result = fm.recordExpense(.infrastructure, 200, "Maintenance") catch .blocked_by_policy;
                        if (result == .success) {
                            notification.set("-200 Infrastructure Expense", ui.Color.init(255, 220, 150, 255));
                        } else {
                            notification.set("Expense blocked!", ui.Color.init(255, 80, 80, 255));
                        }
                    }
                    if (key == c.SDLK_R) {
                        const result = fm.recordExpense(.trade, 150, "Shipping costs") catch .blocked_by_policy;
                        if (result == .success) {
                            notification.set("-150 Trade Expense", ui.Color.init(150, 255, 180, 255));
                        } else {
                            notification.set("Expense blocked!", ui.Color.init(255, 80, 80, 255));
                        }
                    }
                    if (key == c.SDLK_T) {
                        const result = fm.recordExpense(.diplomacy, 100, "Embassy costs") catch .blocked_by_policy;
                        if (result == .success) {
                            notification.set("-100 Diplomacy Expense", ui.Color.init(200, 150, 255, 255));
                        } else {
                            notification.set("Expense blocked!", ui.Color.init(255, 80, 80, 255));
                        }
                    }

                    // Loan management
                    if (key == c.SDLK_L) {
                        fm.takeLoan(1000, 0.05, null, "Emergency loan") catch {
                            notification.set("Cannot take loan - max debt reached", ui.Color.init(255, 80, 80, 255));
                            continue;
                        };
                        notification.set("+1000 Loan taken (5% interest)", ui.Color.init(255, 200, 80, 255));
                    }
                    if (key == c.SDLK_R and event.key.mod == 0) {
                        // Only R without modifiers for repay (SDLK_R is also trade expense)
                    }

                    // End turn
                    if (key == c.SDLK_SPACE) {
                        const report = fm.endTurn() catch {
                            notification.set("Error ending turn", ui.Color.init(255, 80, 80, 255));
                            continue;
                        };
                        var buf: [128]u8 = undefined;
                        const msg = std.fmt.bufPrint(&buf, "Turn {d} ended: Net {d:.0}", .{ report.turn, report.net_change }) catch "Turn ended";
                        if (report.net_change >= 0) {
                            notification.set(msg, ui.Color.init(100, 255, 100, 255));
                        } else {
                            notification.set(msg, ui.Color.init(255, 100, 100, 255));
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
        bgfx.setViewClear(0, bgfx.ClearFlags_Color | bgfx.ClearFlags_Depth, 0x1a1a2eFF, 1.0, 0);
        bgfx.setViewRect(0, 0, 0, @intCast(pixel_width), @intCast(pixel_height));
        bgfx.touch(0);

        renderer_2d.beginFrame();
        const input = input_state.toUIInputState();
        ctx.beginFrame(input, window_info);

        // Title
        renderer_2d.drawText("Finance System Demo", .{ .x = 50, .y = 30 }, 32, ui.Color.init(255, 215, 0, 255));

        // Bright text color for better readability
        const bright_text = ui.Color.init(230, 230, 240, 255);
        const bright_secondary = ui.Color.init(180, 180, 200, 255);

        // Turn indicator
        var turn_buf: [32]u8 = undefined;
        const turn_str = std.fmt.bufPrint(&turn_buf, "Turn: {d}", .{fm.getCurrentTurn()}) catch "Turn: ?";
        renderer_2d.drawText(turn_str, .{ .x = VIRTUAL_WIDTH - 180, .y = 30 }, 28, bright_text);

        // ====================================================================
        // Treasury Panel (Left side)
        // ====================================================================
        try ui.beginPanel(&ctx, "Treasury", ui.Rect{
            .x = 50,
            .y = 80,
            .width = 350,
            .height = 360,
        }, ctx.theme.panel_bg);

        // Treasury balance
        var treasury_buf: [64]u8 = undefined;
        const treasury = fm.getTreasury();
        const treasury_str = std.fmt.bufPrint(&treasury_buf, "Treasury: {d:.0}", .{treasury}) catch "?";
        const treasury_color = if (treasury < 0) ui.Color.init(255, 100, 100, 255) else if (treasury < 500) ui.Color.init(255, 220, 100, 255) else ui.Color.init(120, 255, 120, 255);
        renderer_2d.drawText(treasury_str, .{ .x = 70, .y = 120 }, 32, treasury_color);

        // Debt
        var debt_buf: [64]u8 = undefined;
        const debt = fm.getDebt();
        const debt_str = std.fmt.bufPrint(&debt_buf, "Debt: {d:.0}", .{debt}) catch "?";
        renderer_2d.drawText(debt_str, .{ .x = 70, .y = 165 }, 26, if (debt > 0) ui.Color.init(255, 180, 100, 255) else bright_secondary);

        // Net worth
        var net_buf: [64]u8 = undefined;
        const net_str = std.fmt.bufPrint(&net_buf, "Net Worth: {d:.0}", .{fm.getNetWorth()}) catch "?";
        renderer_2d.drawText(net_str, .{ .x = 70, .y = 205 }, 26, bright_text);

        // Loans
        var loan_buf: [64]u8 = undefined;
        const loan_str = std.fmt.bufPrint(&loan_buf, "Active Loans: {d}", .{fm.getLoanCount()}) catch "?";
        renderer_2d.drawText(loan_str, .{ .x = 70, .y = 245 }, 22, bright_secondary);

        // Projected balance
        var proj_buf: [64]u8 = undefined;
        const proj_str = std.fmt.bufPrint(&proj_buf, "Balance: {d:.0}", .{fm.getProjectedBalance()}) catch "?";
        renderer_2d.drawText(proj_str, .{ .x = 70, .y = 280 }, 22, bright_secondary);

        // Warnings
        if (fm.isInDeficit()) {
            renderer_2d.drawText("! DEFICIT", .{ .x = 70, .y = 320 }, 20, ui.Color.init(255, 100, 100, 255));
        } else if (fm.isBelowReserve()) {
            renderer_2d.drawText("! LOW RESERVES", .{ .x = 70, .y = 320 }, 20, ui.Color.init(255, 220, 100, 255));
        }

        ui.endPanel(&ctx);

        // ====================================================================
        // Current Turn Activity (Middle)
        // ====================================================================
        try ui.beginPanel(&ctx, "Current Turn", ui.Rect{
            .x = 420,
            .y = 80,
            .width = 500,
            .height = 360,
        }, ctx.theme.panel_bg);

        // Income/Expense totals
        var income_buf: [64]u8 = undefined;
        const income_str = std.fmt.bufPrint(&income_buf, "Income: +{d:.0}", .{fm.getTotalIncome()}) catch "?";
        renderer_2d.drawText(income_str, .{ .x = 440, .y = 120 }, 28, ui.Color.init(120, 255, 120, 255));

        var expense_buf: [64]u8 = undefined;
        const expense_str = std.fmt.bufPrint(&expense_buf, "Expenses: -{d:.0}", .{fm.getTotalExpenses()}) catch "?";
        renderer_2d.drawText(expense_str, .{ .x = 440, .y = 160 }, 28, ui.Color.init(255, 120, 120, 255));

        var net_turn_buf: [64]u8 = undefined;
        const net_turn = fm.getTotalIncome() - fm.getTotalExpenses();
        const net_turn_str = std.fmt.bufPrint(&net_turn_buf, "Net: {s}{d:.0}", .{ if (net_turn >= 0) "+" else "", net_turn }) catch "?";
        renderer_2d.drawText(net_turn_str, .{ .x = 440, .y = 200 }, 28, if (net_turn >= 0) ui.Color.init(120, 220, 120, 255) else ui.Color.init(255, 180, 120, 255));

        // Per-category breakdown
        renderer_2d.drawText("By Category:", .{ .x = 640, .y = 120 }, 20, bright_secondary);

        const categories = [_]Category{ .military, .research, .infrastructure, .trade, .diplomacy };
        for (categories, 0..) |cat, i| {
            const y_pos: f32 = 150 + @as(f32, @floatFromInt(i)) * 28;
            const cat_income = fm.getCategoryIncome(cat);
            const cat_expense = fm.getCategoryExpenses(cat);
            const cat_net = cat_income - cat_expense;

            var cat_buf: [64]u8 = undefined;
            const cat_str = std.fmt.bufPrint(&cat_buf, "{s}: {s}{d:.0}", .{
                cat.getName(),
                if (cat_net >= 0) "+" else "",
                cat_net,
            }) catch "?";
            renderer_2d.drawText(cat_str, .{ .x = 640, .y = y_pos }, 18, cat.getColor());
        }

        ui.endPanel(&ctx);

        // ====================================================================
        // Budget Panel (Right side)
        // ====================================================================
        try ui.beginPanel(&ctx, "Budgets", ui.Rect{
            .x = 940,
            .y = 80,
            .width = 350,
            .height = 360,
        }, ctx.theme.panel_bg);

        var total_budget_buf: [64]u8 = undefined;
        const total_budget_str = std.fmt.bufPrint(&total_budget_buf, "Total Budget: {d:.0}", .{fm.getTotalBudget()}) catch "?";
        renderer_2d.drawText(total_budget_str, .{ .x = 960, .y = 120 }, 22, bright_text);

        // Budget bars for each category
        for (categories, 0..) |cat, i| {
            const y_pos: f32 = 155 + @as(f32, @floatFromInt(i)) * 45;
            const budget = fm.getBudget(cat);
            const spent = fm.getCategoryExpenses(cat);
            const utilization = fm.getBudgetUtilization(cat);

            // Category label
            renderer_2d.drawText(cat.getName(), .{ .x = 960, .y = y_pos }, 18, cat.getColor());

            // Budget bar background
            const bar_x: f32 = 960;
            const bar_y: f32 = y_pos + 22;
            const bar_width: f32 = 280;
            const bar_height: f32 = 14;

            renderer_2d.drawRect(ui.Rect{
                .x = bar_x,
                .y = bar_y,
                .width = bar_width,
                .height = bar_height,
            }, ui.Color.init(50, 50, 70, 255));

            // Budget bar fill
            const fill_ratio = @min(1.0, spent / @max(1, budget.allocated));
            const fill_color = if (utilization > 100) ui.Color.init(255, 100, 100, 255) else if (utilization > 80) ui.Color.init(255, 220, 100, 255) else cat.getColor();

            renderer_2d.drawRect(ui.Rect{
                .x = bar_x,
                .y = bar_y,
                .width = bar_width * @as(f32, @floatCast(fill_ratio)),
                .height = bar_height,
            }, fill_color);

            // Utilization text
            var util_buf: [32]u8 = undefined;
            const util_str = std.fmt.bufPrint(&util_buf, "{d:.0}%", .{utilization}) catch "?";
            renderer_2d.drawText(util_str, .{ .x = bar_x + bar_width + 10, .y = y_pos + 18 }, 16, bright_secondary);
        }

        ui.endPanel(&ctx);

        // ====================================================================
        // Last Report Panel (Bottom)
        // ====================================================================
        try ui.beginPanel(&ctx, "Last Report", ui.Rect{
            .x = 50,
            .y = 460,
            .width = 600,
            .height = 280,
        }, ctx.theme.panel_bg);

        if (fm.getLastReport()) |report| {
            var report_turn_buf: [64]u8 = undefined;
            const report_turn_str = std.fmt.bufPrint(&report_turn_buf, "Turn {d} Report", .{report.turn}) catch "?";
            renderer_2d.drawText(report_turn_str, .{ .x = 70, .y = 500 }, 24, ui.Color.init(255, 220, 100, 255));

            var report_income_buf: [64]u8 = undefined;
            const report_income_str = std.fmt.bufPrint(&report_income_buf, "Total Income: +{d:.0}", .{report.total_income}) catch "?";
            renderer_2d.drawText(report_income_str, .{ .x = 70, .y = 535 }, 20, ui.Color.init(120, 255, 120, 255));

            var report_expense_buf: [64]u8 = undefined;
            const report_expense_str = std.fmt.bufPrint(&report_expense_buf, "Total Expenses: -{d:.0}", .{report.total_expenses}) catch "?";
            renderer_2d.drawText(report_expense_str, .{ .x = 70, .y = 565 }, 20, ui.Color.init(255, 120, 120, 255));

            var report_net_buf: [64]u8 = undefined;
            const report_net_str = std.fmt.bufPrint(&report_net_buf, "Net Change: {s}{d:.0}", .{ if (report.net_change >= 0) "+" else "", report.net_change }) catch "?";
            renderer_2d.drawText(report_net_str, .{ .x = 70, .y = 595 }, 20, if (report.isProfitable()) ui.Color.init(120, 220, 120, 255) else ui.Color.init(255, 180, 120, 255));

            if (report.interest_paid > 0) {
                var interest_buf: [64]u8 = undefined;
                const interest_str = std.fmt.bufPrint(&interest_buf, "Interest Paid: -{d:.0}", .{report.interest_paid}) catch "?";
                renderer_2d.drawText(interest_str, .{ .x = 70, .y = 625 }, 18, ui.Color.init(255, 200, 100, 255));
            }

            var margin_buf: [64]u8 = undefined;
            const margin_str = std.fmt.bufPrint(&margin_buf, "Profit Margin: {d:.1}%", .{report.getProfitMargin()}) catch "?";
            renderer_2d.drawText(margin_str, .{ .x = 70, .y = 655 }, 18, bright_secondary);

            // Category breakdown
            renderer_2d.drawText("Category Breakdown:", .{ .x = 320, .y = 500 }, 20, bright_secondary);
            for (categories, 0..) |cat, i| {
                const y_pos: f32 = 530 + @as(f32, @floatFromInt(i)) * 26;
                const cat_summary = report.getCategory(cat);

                var cat_report_buf: [64]u8 = undefined;
                const cat_report_str = std.fmt.bufPrint(&cat_report_buf, "{s}: +{d:.0} -{d:.0} = {s}{d:.0}", .{
                    cat.getName(),
                    cat_summary.income,
                    cat_summary.expenses,
                    if (cat_summary.net >= 0) "+" else "",
                    cat_summary.net,
                }) catch "?";
                renderer_2d.drawText(cat_report_str, .{ .x = 320, .y = y_pos }, 17, cat.getColor());
            }

            // Warnings
            if (report.deficit_warning) {
                renderer_2d.drawText("! DEFICIT WARNING", .{ .x = 70, .y = 680 }, 18, ui.Color.init(255, 100, 100, 255));
            }
            if (report.hasOverBudget()) {
                renderer_2d.drawText("! OVER BUDGET", .{ .x = 240, .y = 680 }, 18, ui.Color.init(255, 200, 100, 255));
            }
        } else {
            renderer_2d.drawText("No reports yet - press SPACE to end turn", .{ .x = 70, .y = 550 }, 22, bright_secondary);
        }

        ui.endPanel(&ctx);

        // ====================================================================
        // Controls Panel (Bottom right)
        // ====================================================================
        try ui.beginPanel(&ctx, "Controls", ui.Rect{
            .x = 670,
            .y = 460,
            .width = 620,
            .height = 280,
        }, ctx.theme.panel_bg);

        renderer_2d.drawText("Income Keys (1-5):", .{ .x = 690, .y = 500 }, 20, ui.Color.init(120, 255, 120, 255));
        renderer_2d.drawText("1: Military  2: Research  3: Infra  4: Trade  5: Diplomacy", .{ .x = 690, .y = 530 }, 18, bright_secondary);

        renderer_2d.drawText("Expense Keys (Q-T):", .{ .x = 690, .y = 570 }, 20, ui.Color.init(255, 120, 120, 255));
        renderer_2d.drawText("Q: Military  W: Research  E: Infra  R: Trade  T: Diplomacy", .{ .x = 690, .y = 600 }, 18, bright_secondary);

        renderer_2d.drawText("Loan Keys:", .{ .x = 690, .y = 640 }, 20, ui.Color.init(255, 220, 100, 255));
        renderer_2d.drawText("L: Take Loan (+1000 @ 5%)", .{ .x = 690, .y = 670 }, 18, bright_secondary);

        renderer_2d.drawText("SPACE: End Turn   ESC: Quit", .{ .x = 690, .y = 710 }, 20, bright_text);

        ui.endPanel(&ctx);

        // ====================================================================
        // Notification
        // ====================================================================
        if (notification.isActive()) {
            const alpha: u8 = @intFromFloat(@min(255, notification.timer * 255));
            var notif_color = notification.color;
            notif_color.a = alpha;

            // Center notification at bottom
            const notif_text = notification.getText();
            const text_bounds = renderer_2d.measureText(notif_text, 28);
            const notif_x = (VIRTUAL_WIDTH - text_bounds.x) / 2;

            renderer_2d.drawText(notif_text, .{ .x = notif_x, .y = 760 }, 28, notif_color);
        }

        ctx.endFrame();
        renderer_2d.endFrame();

        _ = bgfx.frame(false);
    }

    std.debug.print("\nFinance Demo ended.\n", .{});
    std.debug.print("Final Treasury: {d:.0}\n", .{fm.getTreasury()});
    std.debug.print("Final Debt: {d:.0}\n", .{fm.getDebt()});
    std.debug.print("Final Net Worth: {d:.0}\n", .{fm.getNetWorth()});
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
