// config.zig
// Configuration loading module

pub const config_loader = @import("config/config_loader.zig");

// Re-export commonly used types
pub const RoomData = config_loader.RoomData;
pub const ItemData = config_loader.ItemData;
pub const NPCData = config_loader.NPCData;
pub const Exit = config_loader.Exit;

// Re-export loader functions
pub const loadRooms = config_loader.loadRooms;
pub const loadItems = config_loader.loadItems;
pub const loadNPCs = config_loader.loadNPCs;

// Tests
test {
    @import("std").testing.refAllDecls(@This());
    _ = @import("config/config_loader_test.zig");
}
