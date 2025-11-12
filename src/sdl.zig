const std = @import("std");

pub const c = @cImport({
    @cInclude("SDL3/SDL.h");
});

pub const Window = struct {
    handle: *c.SDL_Window,

    pub fn init(title: [*:0]const u8, width: i32, height: i32) !Window {
        const window = c.SDL_CreateWindow(
            title,
            width,
            height,
            c.SDL_WINDOW_RESIZABLE,
        ) orelse return error.SDLCreateWindowFailed;

        return Window{ .handle = window };
    }

    pub fn deinit(self: Window) void {
        c.SDL_DestroyWindow(self.handle);
    }
};

pub const Event = c.SDL_Event;

pub fn init() !void {
    if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_EVENTS)) {
        return error.SDLInitFailed;
    }
}

pub fn quit() void {
    c.SDL_Quit();
}

pub fn pollEvent(event: *Event) bool {
    return c.SDL_PollEvent(event);
}

pub fn delay(ms: u32) void {
    c.SDL_Delay(ms);
}

pub fn getError() [*:0]const u8 {
    return c.SDL_GetError();
}
