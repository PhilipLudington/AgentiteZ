// config.zig
// Configuration loading module

pub const loader = @import("config/loader.zig");

// Re-export commonly used types
pub const RoomData = loader.RoomData;
pub const ItemData = loader.ItemData;
pub const NPCData = loader.NPCData;
pub const Exit = loader.Exit;

// Re-export loader functions
pub const loadRooms = loader.loadRooms;
pub const loadItems = loader.loadItems;
pub const loadNPCs = loader.loadNPCs;

// Tests
test {
    @import("std").testing.refAllDecls(@This());
    _ = @import("config/loader_test.zig");
}
