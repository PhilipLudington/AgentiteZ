//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const builtin = @import("builtin");

pub const sdl = @import("sdl.zig");
pub const bgfx = @import("bgfx.zig");
pub const stb_truetype = @import("stb_truetype.zig");
pub const ui = @import("ui.zig");
pub const ecs = @import("ecs.zig");
pub const platform = @import("platform.zig");
pub const data = @import("data.zig");
pub const config = @import("config.zig");
pub const storage = @import("storage.zig");
pub const renderer = @import("renderer.zig");
pub const audio = @import("audio.zig");
pub const camera = @import("camera.zig");
pub const animation = @import("animation.zig");
pub const tilemap = @import("tilemap.zig");
pub const spatial = @import("spatial.zig");
pub const pathfinding = @import("pathfinding.zig");
pub const event = @import("event.zig");
pub const resource = @import("resource.zig");
pub const modifier = @import("modifier.zig");
pub const turn = @import("turn.zig");

// Phase 4: AI Foundation
pub const blackboard = @import("blackboard.zig");
pub const task_queue = @import("task_queue.zig");
pub const personality = @import("personality.zig");

// Phase 5: Strategy Advanced
pub const tech = @import("tech.zig");
pub const fog = @import("fog.zig");
pub const victory = @import("victory.zig");

// Phase 6: AI Advanced
pub const htn = @import("htn.zig");
pub const ai_tracks = @import("ai_tracks.zig");

// Phase 7: Factory Systems
pub const power = @import("power.zig");
pub const crafting = @import("crafting.zig");
pub const rate_tracker = @import("rate_tracker.zig");

// Phase 8: Combat Systems
pub const combat = @import("combat.zig");
pub const fleet = @import("fleet.zig");

// Phase 9: Utility Systems
pub const command = @import("command.zig");
pub const dialog = @import("dialog.zig");
pub const formula = @import("formula.zig");

// Phase 10: Core Infrastructure
pub const prefab = @import("prefab.zig");
pub const scene = @import("scene.zig");
pub const transform = @import("transform.zig");
pub const asset = @import("asset.zig");
pub const async_loader = @import("async_loader.zig");

// Force inclusion of stb_truetype exports (zig_stb_alloc, zig_stb_free)
// These are needed by C code even if not directly referenced from Zig.
comptime {
    _ = stb_truetype;
}

// Include test files for module testing
test {
    _ = @import("audio_test.zig");
}

pub fn bufferedPrint() !void {
    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try stdout.flush(); // Don't forget to flush!
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}
