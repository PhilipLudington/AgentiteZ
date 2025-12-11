// UI Forms Example - Demonstrates interactive forms with all widget types
// Features: Text input, dropdowns, sliders, checkboxes, validation, data binding
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
// Form Data Structures
// ============================================================================

const UserProfile = struct {
    // Text fields
    name_buffer: [64]u8 = [_]u8{0} ** 64,
    name_len: usize = 0,

    email_buffer: [64]u8 = [_]u8{0} ** 64,
    email_len: usize = 0,

    bio_buffer: [256]u8 = [_]u8{0} ** 256,
    bio_len: usize = 0,

    // Numeric values
    age: f32 = 25,
    experience_years: f32 = 0,

    // Selections
    role_dropdown: ui.DropdownState = .{},
    skill_level_dropdown: ui.DropdownState = .{},
    country_dropdown: ui.DropdownState = .{},

    // Checkboxes
    receive_newsletter: bool = false,
    accept_terms: bool = false,
    enable_notifications: bool = true,
    dark_mode: bool = false,

    // Tab state
    tab_state: ui.TabBarState = .{},

    fn getName(self: *const UserProfile) []const u8 {
        return self.name_buffer[0..self.name_len];
    }

    fn getEmail(self: *const UserProfile) []const u8 {
        return self.email_buffer[0..self.email_len];
    }

    fn getBio(self: *const UserProfile) []const u8 {
        return self.bio_buffer[0..self.bio_len];
    }
};

const GameSettings = struct {
    // Audio
    master_volume: f32 = 80,
    music_volume: f32 = 70,
    sfx_volume: f32 = 90,
    voice_volume: f32 = 100,

    // Graphics
    resolution_dropdown: ui.DropdownState = .{},
    quality_dropdown: ui.DropdownState = .{},
    brightness: f32 = 50,
    contrast: f32 = 50,
    gamma: f32 = 1.0,

    // Options
    vsync: bool = true,
    fullscreen: bool = false,
    show_fps: bool = false,
    antialiasing: bool = true,
    motion_blur: bool = false,

    // Gameplay
    difficulty_dropdown: ui.DropdownState = .{},
    mouse_sensitivity: f32 = 1.0,
    invert_y: bool = false,
    auto_save: bool = true,
};

const FormValidation = struct {
    name_valid: bool = true,
    email_valid: bool = true,
    terms_accepted: bool = false,

    fn isFormValid(self: *const FormValidation) bool {
        return self.name_valid and self.email_valid and self.terms_accepted;
    }
};

// ============================================================================
// Dropdown Options
// ============================================================================

const role_options = [_][]const u8{ "Developer", "Designer", "Manager", "QA Engineer", "DevOps" };
const skill_options = [_][]const u8{ "Beginner", "Intermediate", "Advanced", "Expert" };
const country_options = [_][]const u8{ "United States", "United Kingdom", "Canada", "Germany", "Japan", "Australia" };
const resolution_options = [_][]const u8{ "1280x720", "1920x1080", "2560x1440", "3840x2160" };
const quality_options = [_][]const u8{ "Low", "Medium", "High", "Ultra" };
const difficulty_options = [_][]const u8{ "Easy", "Normal", "Hard", "Nightmare" };

// ============================================================================
// Main Entry Point
// ============================================================================

pub fn main() !void {
    std.debug.print("AgentiteZ UI Forms Example\n", .{});
    std.debug.print("Demonstrates interactive forms with all widget types\n\n", .{});

    // Initialize SDL3
    if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_EVENTS)) {
        std.debug.print("SDL_Init failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLInitFailed;
    }
    defer c.SDL_Quit();

    // Create window (16:9 aspect ratio)
    const window = c.SDL_CreateWindow(
        "AgentiteZ - UI Forms Example",
        1280,
        720,
        c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_HIGH_PIXEL_DENSITY,
    ) orelse {
        std.debug.print("SDL_CreateWindow failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLCreateWindowFailed;
    };
    defer c.SDL_DestroyWindow(window);

    // Enable text input
    _ = c.SDL_StartTextInput(window);

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

    // Load font atlas (38.0 = 24.0 * 1.58 for ~58% larger text)
    var font_atlas = try renderer.FontAtlas.init(allocator, font_path, 38.0 * dpi_scale, false);
    defer font_atlas.deinit();
    renderer_2d.setExternalFontAtlas(&font_atlas);

    // Initialize input state
    var input_state = platform.InputState.init(allocator);
    defer input_state.deinit();

    // ========================================================================
    // Form State
    // ========================================================================
    var profile = UserProfile{};
    var settings = GameSettings{};
    var validation = FormValidation{};

    // Set default name
    const default_name = "John Doe";
    @memcpy(profile.name_buffer[0..default_name.len], default_name);
    profile.name_len = default_name.len;

    // Form state
    var active_form: enum { profile, settings, preview } = .profile;
    var show_submit_message = false;
    var submit_message_timer: f32 = 0;

    // Main loop
    var running = true;
    var event: c.SDL_Event = undefined;

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

        // Update submit message timer
        if (show_submit_message) {
            submit_message_timer -= 0.016; // ~60fps
            if (submit_message_timer <= 0) {
                show_submit_message = false;
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

        // Convert mouse position to virtual coordinates
        const raw_mouse = input_state.getMousePosition();
        const physical_mouse_x = raw_mouse.x * dpi_scale;
        const physical_mouse_y = raw_mouse.y * dpi_scale;
        const virtual_mouse_x = (physical_mouse_x - @as(f32, @floatFromInt(viewport.x))) / viewport.scale;
        const virtual_mouse_y = (physical_mouse_y - @as(f32, @floatFromInt(viewport.y))) / viewport.scale;

        // Background color changes with dark mode
        const bg_color: u32 = if (profile.dark_mode) 0x1a1a2eff else 0x2a3a4aff;
        bgfx.setViewRect(0, viewport.x, viewport.y, viewport.width, viewport.height);
        bgfx.setViewClear(0, bgfx.ClearFlags_Color | bgfx.ClearFlags_Depth, bg_color, 1.0, 0);

        // Set up overlay view (view 1) for dropdowns/modals - same viewport, no clear
        bgfx.setViewRect(1, viewport.x, viewport.y, viewport.width, viewport.height);
        bgfx.setViewClear(1, bgfx.ClearFlags_None, 0, 1.0, 0);

        // Update renderer with viewport info
        renderer_2d.setViewportFromInfo(viewport);

        renderer_2d.beginFrame();

        const window_info = ui.WindowInfo{
            .width = window_width,
            .height = window_height,
            .dpi_scale = dpi_scale,
        };
        // Get base input state and override mouse position with virtual coordinates
        var input = input_state.toUIInputState();
        input.mouse_pos = .{ .x = virtual_mouse_x, .y = virtual_mouse_y };
        ctx.beginFrame(input, window_info);

        // Title
        ui.label(&ctx, "AgentiteZ - UI Forms Example", .{ .x = 20, .y = 20 }, 28, ui.Color.white);
        ui.label(&ctx, "Interactive forms demonstrating all widget types", .{ .x = 20, .y = 55 }, 14, ui.Color.gray);

        // Main form selector tabs
        const tab_labels = [_][]const u8{ "User Profile", "Game Settings", "Data Preview" };
        ctx.cursor = .{ .x = 20, .y = 100 };
        const selected_tab = ui.tabBarAuto(&ctx, "main_tabs", 600, &tab_labels, &profile.tab_state);

        active_form = switch (selected_tab) {
            0 => .profile,
            1 => .settings,
            2 => .preview,
            else => .profile,
        };

        // ====================================================================
        // User Profile Form
        // ====================================================================
        if (active_form == .profile) {
            const form_panel = ui.Rect.init(20, 160, 650, 700);
            try ui.beginPanel(&ctx, "User Profile", form_panel, ui.Color.panel_bg);

            ctx.cursor.y += 10;

            // Name field
            ui.label(&ctx, "Full Name *", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 14, ui.Color.white);
            ctx.cursor.y += 20;
            ui.textInputAuto(&ctx, "name_input", 400, &profile.name_buffer, &profile.name_len);

            // Validation
            validation.name_valid = profile.name_len >= 2;
            if (!validation.name_valid and profile.name_len > 0) {
                ui.label(&ctx, "Name must be at least 2 characters", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 11, ui.Color.init(255, 100, 100, 255));
                ctx.cursor.y += 15;
            }
            ctx.cursor.y += 10;

            // Email field
            ui.label(&ctx, "Email Address *", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 14, ui.Color.white);
            ctx.cursor.y += 20;
            ui.textInputAuto(&ctx, "email_input", 400, &profile.email_buffer, &profile.email_len);

            // Simple email validation (contains @)
            validation.email_valid = profile.email_len == 0 or std.mem.indexOf(u8, profile.getEmail(), "@") != null;
            if (!validation.email_valid) {
                ui.label(&ctx, "Please enter a valid email address", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 11, ui.Color.init(255, 100, 100, 255));
                ctx.cursor.y += 15;
            }
            ctx.cursor.y += 10;

            // Age slider
            ui.label(&ctx, "Age", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 14, ui.Color.white);
            ctx.cursor.y += 5;
            profile.age = ui.sliderAuto(&ctx, "", 400, profile.age, 18, 100);

            var age_buf: [32]u8 = undefined;
            const age_text = std.fmt.bufPrint(&age_buf, "{d:.0} years old", .{profile.age}) catch "???";
            ui.label(&ctx, age_text, .{ .x = ctx.cursor.x + 420, .y = ctx.cursor.y - 25 }, 12, ui.Color.gray);

            ctx.cursor.y += 10;

            // Role dropdown
            ui.label(&ctx, "Role", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 14, ui.Color.white);
            ctx.cursor.y += 20;
            ui.dropdownAuto(&ctx, "role_dropdown", 300, &role_options, &profile.role_dropdown);

            ctx.cursor.y += 10;

            // Skill level dropdown
            ui.label(&ctx, "Skill Level", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 14, ui.Color.white);
            ctx.cursor.y += 20;
            ui.dropdownAuto(&ctx, "skill_dropdown", 300, &skill_options, &profile.skill_level_dropdown);

            ctx.cursor.y += 10;

            // Experience slider
            ui.label(&ctx, "Years of Experience", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 14, ui.Color.white);
            ctx.cursor.y += 5;
            profile.experience_years = ui.sliderAuto(&ctx, "", 400, profile.experience_years, 0, 30);

            var exp_buf: [32]u8 = undefined;
            const exp_text = std.fmt.bufPrint(&exp_buf, "{d:.0} years", .{profile.experience_years}) catch "???";
            ui.label(&ctx, exp_text, .{ .x = ctx.cursor.x + 420, .y = ctx.cursor.y - 25 }, 12, ui.Color.gray);

            ctx.cursor.y += 15;

            // Checkboxes section
            ui.label(&ctx, "Preferences", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 16, ui.Color.white);
            ctx.cursor.y += 25;

            _ = ui.checkboxAuto(&ctx, "Receive newsletter", &profile.receive_newsletter);
            _ = ui.checkboxAuto(&ctx, "Enable notifications", &profile.enable_notifications);
            _ = ui.checkboxAuto(&ctx, "Dark mode", &profile.dark_mode);

            ctx.cursor.y += 10;

            // Terms checkbox (required)
            _ = ui.checkboxAuto(&ctx, "I accept the terms and conditions *", &profile.accept_terms);
            validation.terms_accepted = profile.accept_terms;

            if (!validation.terms_accepted) {
                ui.label(&ctx, "You must accept the terms to continue", .{ .x = ctx.cursor.x + 30, .y = ctx.cursor.y }, 11, ui.Color.init(255, 150, 100, 255));
                ctx.cursor.y += 15;
            }

            ui.endPanel(&ctx);

            // Submit button (outside panel)
            ctx.cursor = .{ .x = 20, .y = 880 };
            const can_submit = validation.isFormValid();
            const submit_color = if (can_submit) ui.Color.init(100, 200, 100, 255) else ui.Color.init(100, 100, 100, 255);

            if (ui.buttonAuto(&ctx, "Submit Profile", 200, 45)) {
                if (can_submit) {
                    show_submit_message = true;
                    submit_message_timer = 3.0;
                    std.debug.print("Profile submitted: {s}\n", .{profile.getName()});
                }
            }

            // Show submit status
            if (show_submit_message) {
                ui.label(&ctx, "Profile saved successfully!", .{ .x = 240, .y = 890 }, 16, ui.Color.init(100, 255, 100, 255));
            } else if (!can_submit) {
                ui.label(&ctx, "Please fill all required fields (*)", .{ .x = 240, .y = 890 }, 14, submit_color);
            }
        }

        // ====================================================================
        // Game Settings Form
        // ====================================================================
        if (active_form == .settings) {
            // Audio Settings Panel
            const audio_panel = ui.Rect.init(20, 160, 400, 340);
            try ui.beginPanel(&ctx, "Audio Settings", audio_panel, ui.Color.panel_bg);

            ctx.cursor.y += 10;

            settings.master_volume = ui.sliderAuto(&ctx, "Master Volume", 300, settings.master_volume, 0, 100);
            settings.music_volume = ui.sliderAuto(&ctx, "Music Volume", 300, settings.music_volume, 0, 100);
            settings.sfx_volume = ui.sliderAuto(&ctx, "SFX Volume", 300, settings.sfx_volume, 0, 100);
            settings.voice_volume = ui.sliderAuto(&ctx, "Voice Volume", 300, settings.voice_volume, 0, 100);

            // Volume visualization
            ctx.cursor.y += 10;
            ui.label(&ctx, "Volume Levels:", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 12, ui.Color.gray);
            ctx.cursor.y += 20;

            const bar_width: f32 = 250;
            const bar_height: f32 = 8;
            const volumes = [_]struct { name: []const u8, value: f32 }{
                .{ .name = "Master", .value = settings.master_volume },
                .{ .name = "Music", .value = settings.music_volume },
                .{ .name = "SFX", .value = settings.sfx_volume },
            };

            for (volumes) |vol| {
                ui.label(&ctx, vol.name, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 10, ui.Color.gray);
                ctx.renderer.drawRect(ui.Rect.init(ctx.cursor.x + 60, ctx.cursor.y, bar_width, bar_height), ui.Color.init(50, 50, 50, 255));
                ctx.renderer.drawRect(ui.Rect.init(ctx.cursor.x + 60, ctx.cursor.y, bar_width * vol.value / 100, bar_height), ui.Color.init(100, 200, 100, 255));
                ctx.cursor.y += 15;
            }

            ui.endPanel(&ctx);

            // Graphics Settings Panel
            const graphics_panel = ui.Rect.init(440, 160, 400, 340);
            try ui.beginPanel(&ctx, "Graphics Settings", graphics_panel, ui.Color.panel_bg);

            ctx.cursor.y += 10;

            ui.label(&ctx, "Resolution", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 14, ui.Color.white);
            ctx.cursor.y += 20;
            ui.dropdownAuto(&ctx, "resolution_dropdown", 250, &resolution_options, &settings.resolution_dropdown);

            ctx.cursor.y += 5;

            ui.label(&ctx, "Quality Preset", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 14, ui.Color.white);
            ctx.cursor.y += 20;
            ui.dropdownAuto(&ctx, "quality_dropdown", 250, &quality_options, &settings.quality_dropdown);

            ctx.cursor.y += 5;

            settings.brightness = ui.sliderAuto(&ctx, "Brightness", 300, settings.brightness, 0, 100);
            settings.gamma = ui.sliderAuto(&ctx, "Gamma", 300, settings.gamma, 0.5, 2.5);

            ui.endPanel(&ctx);

            // Options Panel
            const options_panel = ui.Rect.init(20, 520, 400, 200);
            try ui.beginPanel(&ctx, "Display Options", options_panel, ui.Color.panel_bg);

            ctx.cursor.y += 10;

            _ = ui.checkboxAuto(&ctx, "VSync", &settings.vsync);
            _ = ui.checkboxAuto(&ctx, "Fullscreen", &settings.fullscreen);
            _ = ui.checkboxAuto(&ctx, "Show FPS Counter", &settings.show_fps);
            _ = ui.checkboxAuto(&ctx, "Anti-Aliasing", &settings.antialiasing);
            _ = ui.checkboxAuto(&ctx, "Motion Blur", &settings.motion_blur);

            ui.endPanel(&ctx);

            // Gameplay Panel
            const gameplay_panel = ui.Rect.init(440, 520, 400, 200);
            try ui.beginPanel(&ctx, "Gameplay", gameplay_panel, ui.Color.panel_bg);

            ctx.cursor.y += 10;

            ui.label(&ctx, "Difficulty", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 14, ui.Color.white);
            ctx.cursor.y += 20;
            ui.dropdownAuto(&ctx, "difficulty_dropdown", 250, &difficulty_options, &settings.difficulty_dropdown);

            ctx.cursor.y += 5;

            settings.mouse_sensitivity = ui.sliderAuto(&ctx, "Mouse Sensitivity", 300, settings.mouse_sensitivity, 0.1, 3.0);

            ctx.cursor.y += 5;

            _ = ui.checkboxAuto(&ctx, "Invert Y-Axis", &settings.invert_y);
            _ = ui.checkboxAuto(&ctx, "Auto-Save", &settings.auto_save);

            ui.endPanel(&ctx);

            // Apply/Reset buttons
            ctx.cursor = .{ .x = 20, .y = 740 };
            if (ui.buttonAuto(&ctx, "Apply Settings", 150, 40)) {
                std.debug.print("Settings applied!\n", .{});
                show_submit_message = true;
                submit_message_timer = 2.0;
            }
            if (ui.buttonAuto(&ctx, "Reset to Defaults", 150, 40)) {
                settings = GameSettings{};
            }

            if (show_submit_message) {
                ui.label(&ctx, "Settings applied!", .{ .x = ctx.cursor.x, .y = ctx.cursor.y - 30 }, 14, ui.Color.init(100, 255, 100, 255));
            }
        }

        // ====================================================================
        // Data Preview
        // ====================================================================
        if (active_form == .preview) {
            const preview_panel = ui.Rect.init(20, 160, 820, 600);
            try ui.beginPanel(&ctx, "Form Data Preview", preview_panel, ui.Color.panel_bg);

            ctx.cursor.y += 10;

            ui.label(&ctx, "User Profile Data:", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 18, ui.Color.imperial_gold);
            ctx.cursor.y += 30;

            var buf: [256]u8 = undefined;

            const name_line = std.fmt.bufPrint(&buf, "Name: {s}", .{if (profile.name_len > 0) profile.getName() else "(not set)"}) catch "???";
            ui.label(&ctx, name_line, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 14, ui.Color.white);
            ctx.cursor.y += 22;

            const email_line = std.fmt.bufPrint(&buf, "Email: {s}", .{if (profile.email_len > 0) profile.getEmail() else "(not set)"}) catch "???";
            ui.label(&ctx, email_line, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 14, ui.Color.white);
            ctx.cursor.y += 22;

            const age_line = std.fmt.bufPrint(&buf, "Age: {d:.0} years", .{profile.age}) catch "???";
            ui.label(&ctx, age_line, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 14, ui.Color.white);
            ctx.cursor.y += 22;

            const role_idx = profile.role_dropdown.selected_index;
            const role_line = std.fmt.bufPrint(&buf, "Role: {s}", .{role_options[role_idx]}) catch "???";
            ui.label(&ctx, role_line, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 14, ui.Color.white);
            ctx.cursor.y += 22;

            const skill_idx = profile.skill_level_dropdown.selected_index;
            const skill_line = std.fmt.bufPrint(&buf, "Skill Level: {s}", .{skill_options[skill_idx]}) catch "???";
            ui.label(&ctx, skill_line, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 14, ui.Color.white);
            ctx.cursor.y += 22;

            const exp_line = std.fmt.bufPrint(&buf, "Experience: {d:.0} years", .{profile.experience_years}) catch "???";
            ui.label(&ctx, exp_line, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 14, ui.Color.white);
            ctx.cursor.y += 30;

            // Preferences
            ui.label(&ctx, "Preferences:", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 16, ui.Color.imperial_gold);
            ctx.cursor.y += 25;

            const prefs = [_]struct { name: []const u8, enabled: bool }{
                .{ .name = "Newsletter", .enabled = profile.receive_newsletter },
                .{ .name = "Notifications", .enabled = profile.enable_notifications },
                .{ .name = "Dark Mode", .enabled = profile.dark_mode },
                .{ .name = "Terms Accepted", .enabled = profile.accept_terms },
            };

            for (prefs) |pref| {
                const status = if (pref.enabled) "Enabled" else "Disabled";
                const color = if (pref.enabled) ui.Color.init(100, 255, 100, 255) else ui.Color.init(150, 150, 150, 255);
                const pref_line = std.fmt.bufPrint(&buf, "{s}: {s}", .{ pref.name, status }) catch "???";
                ui.label(&ctx, pref_line, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 13, color);
                ctx.cursor.y += 20;
            }

            ctx.cursor.y += 20;

            // Game Settings Preview
            ui.label(&ctx, "Game Settings:", .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 18, ui.Color.imperial_gold);
            ctx.cursor.y += 30;

            const res_idx = settings.resolution_dropdown.selected_index;
            const quality_idx = settings.quality_dropdown.selected_index;
            const diff_idx = settings.difficulty_dropdown.selected_index;

            const settings_lines = [_][]const u8{
                std.fmt.bufPrint(&buf, "Resolution: {s}", .{resolution_options[res_idx]}) catch "???",
            };
            _ = settings_lines;

            const res_line = std.fmt.bufPrint(&buf, "Resolution: {s}", .{resolution_options[res_idx]}) catch "???";
            ui.label(&ctx, res_line, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 14, ui.Color.white);
            ctx.cursor.y += 22;

            const quality_line = std.fmt.bufPrint(&buf, "Quality: {s}", .{quality_options[quality_idx]}) catch "???";
            ui.label(&ctx, quality_line, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 14, ui.Color.white);
            ctx.cursor.y += 22;

            const diff_line = std.fmt.bufPrint(&buf, "Difficulty: {s}", .{difficulty_options[diff_idx]}) catch "???";
            ui.label(&ctx, diff_line, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 14, ui.Color.white);
            ctx.cursor.y += 22;

            const vol_line = std.fmt.bufPrint(&buf, "Master Volume: {d:.0}%", .{settings.master_volume}) catch "???";
            ui.label(&ctx, vol_line, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 14, ui.Color.white);
            ctx.cursor.y += 22;

            const sens_line = std.fmt.bufPrint(&buf, "Mouse Sensitivity: {d:.2}x", .{settings.mouse_sensitivity}) catch "???";
            ui.label(&ctx, sens_line, .{ .x = ctx.cursor.x, .y = ctx.cursor.y }, 14, ui.Color.white);

            ui.endPanel(&ctx);
        }

        // Footer (use virtual height 1080, not window height)
        ui.label(&ctx, "Press ESC to exit | All data is stored in memory only", .{ .x = 20, .y = 1050 }, 12, ui.Color.gray);

        ctx.endFrame();
        renderer_2d.endFrame();

        bgfx.touch(0);
        bgfx.touch(1); // Touch overlay view for dropdowns
        _ = bgfx.frame(false);
    }
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
