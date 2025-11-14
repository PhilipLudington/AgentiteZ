// ui_atlas.zig
// UI texture atlas system for icons, borders, and themed UI elements
// Supports 9-slice scaling for borders and regular texture regions

const std = @import("std");
const bgfx = @import("../bgfx.zig");
const log = @import("../log.zig");

/// Atlas region representing a texture area
pub const AtlasRegion = struct {
    /// UV coordinates in atlas (normalized 0-1)
    uv_x0: f32,
    uv_y0: f32,
    uv_x1: f32,
    uv_y1: f32,

    /// Original pixel size
    width: u32,
    height: u32,

    /// 9-slice border sizes (in pixels from edges)
    /// Set all to 0 for regular texture (no slicing)
    border_left: u32 = 0,
    border_right: u32 = 0,
    border_top: u32 = 0,
    border_bottom: u32 = 0,

    /// Check if this region uses 9-slice
    pub fn is9Slice(self: *const AtlasRegion) bool {
        return self.border_left > 0 or self.border_right > 0 or
            self.border_top > 0 or self.border_bottom > 0;
    }
};

/// UI texture atlas containing themed UI elements
pub const UIAtlas = struct {
    texture: bgfx.TextureHandle,
    regions: std.StringHashMap(AtlasRegion),
    atlas_width: u32,
    atlas_height: u32,
    allocator: std.mem.Allocator,

    /// Create a UI atlas from an image file and metadata
    /// For now, we'll create a simple procedurally generated atlas
    pub fn init(allocator: std.mem.Allocator) !UIAtlas {
        return initProcedural(allocator);
    }

    /// Create a procedurally generated UI atlas (for initial implementation)
    fn initProcedural(allocator: std.mem.Allocator) !UIAtlas {
        const atlas_width: u32 = 256;
        const atlas_height: u32 = 256;

        // Allocate RGBA8 atlas
        const atlas_data = try allocator.alloc(u8, atlas_width * atlas_height * 4);
        defer allocator.free(atlas_data);

        // Fill with procedural patterns
        generateProceduralAtlas(atlas_data, atlas_width, atlas_height);

        // Create bgfx texture
        const mem = bgfx.copy(atlas_data.ptr, @intCast(atlas_data.len));
        const texture = bgfx.createTexture2D(
            @intCast(atlas_width),
            @intCast(atlas_height),
            false, // no mipmaps
            1, // single layer
            bgfx.TextureFormat.RGBA8,
            0, // flags (default)
            mem,
        );

        // Create regions map
        var regions = std.StringHashMap(AtlasRegion).init(allocator);
        errdefer regions.deinit();

        // Add procedurally generated regions
        try addProceduralRegions(&regions, atlas_width, atlas_height);

        std.debug.print("UIAtlas: Created procedural atlas {d}x{d} with {d} regions\n", .{ atlas_width, atlas_height, regions.count() });

        return UIAtlas{
            .texture = texture,
            .regions = regions,
            .atlas_width = atlas_width,
            .atlas_height = atlas_height,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *UIAtlas) void {
        bgfx.destroyTexture(self.texture);

        // Free all region name keys
        var iter = self.regions.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.regions.deinit();
    }

    /// Get a region by name
    pub fn getRegion(self: *const UIAtlas, name: []const u8) ?*const AtlasRegion {
        return self.regions.getPtr(name);
    }
};

/// 9-slice region info for rendering
pub const SliceInfo = struct {
    /// UV coordinates for the 9 regions
    /// Layout: [0]=TL, [1]=T, [2]=TR,
    ///         [3]=L,  [4]=C, [5]=R,
    ///         [6]=BL, [7]=B, [8]=BR
    uvs: [9]struct { x0: f32, y0: f32, x1: f32, y1: f32 },

    /// Pixel dimensions for the 9 regions in the target rectangle
    /// Same layout as uvs
    rects: [9]struct { x: f32, y: f32, w: f32, h: f32 },
};

/// Calculate 9-slice rendering info for an atlas region
/// target_x, target_y, target_w, target_h: destination rectangle in screen space
pub fn calculate9Slice(region: *const AtlasRegion, target_x: f32, target_y: f32, target_w: f32, target_h: f32) SliceInfo {
    var info: SliceInfo = undefined;

    // Convert border sizes to normalized UV space
    const region_w_f: f32 = @floatFromInt(region.width);
    const region_h_f: f32 = @floatFromInt(region.height);
    const border_l_uv: f32 = @as(f32, @floatFromInt(region.border_left)) / region_w_f;
    const border_r_uv: f32 = @as(f32, @floatFromInt(region.border_right)) / region_w_f;
    const border_t_uv: f32 = @as(f32, @floatFromInt(region.border_top)) / region_h_f;
    const border_b_uv: f32 = @as(f32, @floatFromInt(region.border_bottom)) / region_h_f;

    // Border pixel sizes in target space (keep same pixel size as source)
    const border_l_px: f32 = @floatFromInt(region.border_left);
    const border_r_px: f32 = @floatFromInt(region.border_right);
    const border_t_px: f32 = @floatFromInt(region.border_top);
    const border_b_px: f32 = @floatFromInt(region.border_bottom);

    // Calculate UV coordinates for 9 slices
    const uv = region;

    // Top-left corner
    info.uvs[0] = .{ .x0 = uv.uv_x0, .y0 = uv.uv_y0, .x1 = uv.uv_x0 + border_l_uv, .y1 = uv.uv_y0 + border_t_uv };
    info.rects[0] = .{ .x = target_x, .y = target_y, .w = border_l_px, .h = border_t_px };

    // Top edge (stretched horizontally)
    info.uvs[1] = .{ .x0 = uv.uv_x0 + border_l_uv, .y0 = uv.uv_y0, .x1 = uv.uv_x1 - border_r_uv, .y1 = uv.uv_y0 + border_t_uv };
    info.rects[1] = .{ .x = target_x + border_l_px, .y = target_y, .w = target_w - border_l_px - border_r_px, .h = border_t_px };

    // Top-right corner
    info.uvs[2] = .{ .x0 = uv.uv_x1 - border_r_uv, .y0 = uv.uv_y0, .x1 = uv.uv_x1, .y1 = uv.uv_y0 + border_t_uv };
    info.rects[2] = .{ .x = target_x + target_w - border_r_px, .y = target_y, .w = border_r_px, .h = border_t_px };

    // Left edge (stretched vertically)
    info.uvs[3] = .{ .x0 = uv.uv_x0, .y0 = uv.uv_y0 + border_t_uv, .x1 = uv.uv_x0 + border_l_uv, .y1 = uv.uv_y1 - border_b_uv };
    info.rects[3] = .{ .x = target_x, .y = target_y + border_t_px, .w = border_l_px, .h = target_h - border_t_px - border_b_px };

    // Center (stretched both ways)
    info.uvs[4] = .{ .x0 = uv.uv_x0 + border_l_uv, .y0 = uv.uv_y0 + border_t_uv, .x1 = uv.uv_x1 - border_r_uv, .y1 = uv.uv_y1 - border_b_uv };
    info.rects[4] = .{ .x = target_x + border_l_px, .y = target_y + border_t_px, .w = target_w - border_l_px - border_r_px, .h = target_h - border_t_px - border_b_px };

    // Right edge (stretched vertically)
    info.uvs[5] = .{ .x0 = uv.uv_x1 - border_r_uv, .y0 = uv.uv_y0 + border_t_uv, .x1 = uv.uv_x1, .y1 = uv.uv_y1 - border_b_uv };
    info.rects[5] = .{ .x = target_x + target_w - border_r_px, .y = target_y + border_t_px, .w = border_r_px, .h = target_h - border_t_px - border_b_px };

    // Bottom-left corner
    info.uvs[6] = .{ .x0 = uv.uv_x0, .y0 = uv.uv_y1 - border_b_uv, .x1 = uv.uv_x0 + border_l_uv, .y1 = uv.uv_y1 };
    info.rects[6] = .{ .x = target_x, .y = target_y + target_h - border_b_px, .w = border_l_px, .h = border_b_px };

    // Bottom edge (stretched horizontally)
    info.uvs[7] = .{ .x0 = uv.uv_x0 + border_l_uv, .y0 = uv.uv_y1 - border_b_uv, .x1 = uv.uv_x1 - border_r_uv, .y1 = uv.uv_y1 };
    info.rects[7] = .{ .x = target_x + border_l_px, .y = target_y + target_h - border_b_px, .w = target_w - border_l_px - border_r_px, .h = border_b_px };

    // Bottom-right corner
    info.uvs[8] = .{ .x0 = uv.uv_x1 - border_r_uv, .y0 = uv.uv_y1 - border_b_uv, .x1 = uv.uv_x1, .y1 = uv.uv_y1 };
    info.rects[8] = .{ .x = target_x + target_w - border_r_px, .y = target_y + target_h - border_b_px, .w = border_r_px, .h = border_b_px };

    return info;
}

/// Generate procedural UI atlas with patterns
fn generateProceduralAtlas(data: []u8, width: u32, height: u32) void {
    // Clear to dark gray background
    for (0..height) |y| {
        for (0..width) |x| {
            const idx = (y * width + x) * 4;
            data[idx + 0] = 40; // R
            data[idx + 1] = 40; // G
            data[idx + 2] = 45; // B
            data[idx + 3] = 255; // A
        }
    }

    // Button normal (0,0 - 63,31) - Light gray with subtle border
    drawRectangle(data, width, 0, 0, 64, 32, .{ 80, 85, 95, 255 });
    drawBorder(data, width, 0, 0, 64, 32, 4, .{ 100, 105, 115, 255 });

    // Button hover (64,0 - 127,31) - Slightly lighter
    drawRectangle(data, width, 64, 0, 64, 32, .{ 95, 100, 110, 255 });
    drawBorder(data, width, 64, 0, 64, 32, 4, .{ 115, 120, 130, 255 });

    // Button pressed (128,0 - 191,31) - Darker
    drawRectangle(data, width, 128, 0, 64, 32, .{ 60, 65, 75, 255 });
    drawBorder(data, width, 128, 0, 64, 32, 4, .{ 80, 85, 95, 255 });

    // Panel border (0,32 - 63,95) - Decorative border with 9-slice
    drawRectangle(data, width, 0, 32, 64, 64, .{ 70, 75, 85, 255 });
    drawBorder(data, width, 0, 32, 64, 64, 8, .{ 90, 95, 105, 255 });
    // Inner border for 9-slice visualization
    drawBorder(data, width, 8, 40, 48, 48, 2, .{ 110, 115, 125, 255 });

    // Checkbox unchecked (64,32 - 79,47) - 16x16
    drawRectangle(data, width, 64, 32, 16, 16, .{ 70, 75, 85, 255 });
    drawBorder(data, width, 64, 32, 16, 16, 2, .{ 100, 105, 115, 255 });

    // Checkbox checked (80,32 - 95,47) - 16x16 with checkmark
    drawRectangle(data, width, 80, 32, 16, 16, .{ 70, 75, 85, 255 });
    drawBorder(data, width, 80, 32, 16, 16, 2, .{ 100, 105, 115, 255 });
    // Simple checkmark (diagonal lines)
    drawLine(data, width, 82, 40, 86, 44, .{ 120, 220, 120, 255 });
    drawLine(data, width, 86, 44, 93, 35, .{ 120, 220, 120, 255 });

    // Radio unchecked (96,32 - 111,47) - 16x16 circle outline
    drawCircle(data, width, 104, 40, 6, false, .{ 100, 105, 115, 255 });

    // Radio checked (112,32 - 127,47) - 16x16 filled circle
    drawCircle(data, width, 120, 40, 6, false, .{ 100, 105, 115, 255 });
    drawCircle(data, width, 120, 40, 3, true, .{ 120, 220, 120, 255 });

    // Dropdown arrow (128,32 - 135,39) - 8x8 down arrow
    drawTriangle(data, width, 132, 34, 129, 38, 135, 38, .{ 200, 200, 200, 255 });

    // Scrollbar (0,96 - 15,127) - 16x32 vertical bar
    drawRectangle(data, width, 0, 96, 16, 32, .{ 70, 75, 85, 255 });
    drawBorder(data, width, 0, 96, 16, 32, 2, .{ 90, 95, 105, 255 });
}

/// Draw filled rectangle
fn drawRectangle(data: []u8, width: u32, x: u32, y: u32, w: u32, h: u32, color: [4]u8) void {
    for (0..h) |dy| {
        for (0..w) |dx| {
            const px = x + @as(u32, @intCast(dx));
            const py = y + @as(u32, @intCast(dy));
            const idx = (py * width + px) * 4;
            if (idx + 3 < data.len) {
                data[idx + 0] = color[0];
                data[idx + 1] = color[1];
                data[idx + 2] = color[2];
                data[idx + 3] = color[3];
            }
        }
    }
}

/// Draw border around rectangle
fn drawBorder(data: []u8, width: u32, x: u32, y: u32, w: u32, h: u32, thickness: u32, color: [4]u8) void {
    // Top and bottom borders
    for (0..thickness) |t| {
        const t_u32: u32 = @intCast(t);
        for (0..w) |dx| {
            const dx_u32: u32 = @intCast(dx);
            // Top
            setPixel(data, width, x + dx_u32, y + t_u32, color);
            // Bottom
            if (h > t_u32) {
                setPixel(data, width, x + dx_u32, y + h - t_u32 - 1, color);
            }
        }
    }

    // Left and right borders
    for (0..thickness) |t| {
        const t_u32: u32 = @intCast(t);
        for (0..h) |dy| {
            const dy_u32: u32 = @intCast(dy);
            // Left
            setPixel(data, width, x + t_u32, y + dy_u32, color);
            // Right
            if (w > t_u32) {
                setPixel(data, width, x + w - t_u32 - 1, y + dy_u32, color);
            }
        }
    }
}

/// Draw a line (simple Bresenham)
fn drawLine(data: []u8, width: u32, x0: u32, y0: u32, x1: u32, y1: u32, color: [4]u8) void {
    const dx = if (x1 > x0) x1 - x0 else x0 - x1;
    const dy = if (y1 > y0) y1 - y0 else y0 - y1;
    const sx: i32 = if (x0 < x1) 1 else -1;
    const sy: i32 = if (y0 < y1) 1 else -1;
    var err: i32 = @as(i32, @intCast(dx)) - @as(i32, @intCast(dy));

    var x: i32 = @intCast(x0);
    var y: i32 = @intCast(y0);
    const x1_i32: i32 = @intCast(x1);
    const y1_i32: i32 = @intCast(y1);

    while (true) {
        if (x >= 0 and y >= 0) {
            setPixel(data, width, @intCast(x), @intCast(y), color);
        }

        if (x == x1_i32 and y == y1_i32) break;

        const e2 = err * 2;
        if (e2 > -@as(i32, @intCast(dy))) {
            err -= @as(i32, @intCast(dy));
            x += sx;
        }
        if (e2 < @as(i32, @intCast(dx))) {
            err += @as(i32, @intCast(dx));
            y += sy;
        }
    }
}

/// Draw a circle
fn drawCircle(data: []u8, width: u32, cx: u32, cy: u32, radius: u32, filled: bool, color: [4]u8) void {
    const r_i32: i32 = @intCast(radius);
    const cx_i32: i32 = @intCast(cx);
    const cy_i32: i32 = @intCast(cy);

    var y: i32 = -r_i32;
    while (y <= r_i32) : (y += 1) {
        var x: i32 = -r_i32;
        while (x <= r_i32) : (x += 1) {
            const dist_sq = x * x + y * y;
            const r_sq = r_i32 * r_i32;

            if (filled) {
                if (dist_sq <= r_sq) {
                    const px = cx_i32 + x;
                    const py = cy_i32 + y;
                    if (px >= 0 and py >= 0) {
                        setPixel(data, width, @intCast(px), @intCast(py), color);
                    }
                }
            } else {
                // Outline only (ring)
                if (dist_sq >= (r_sq - r_i32 * 2) and dist_sq <= r_sq) {
                    const px = cx_i32 + x;
                    const py = cy_i32 + y;
                    if (px >= 0 and py >= 0) {
                        setPixel(data, width, @intCast(px), @intCast(py), color);
                    }
                }
            }
        }
    }
}

/// Draw a triangle (filled)
fn drawTriangle(data: []u8, width: u32, x0: u32, y0: u32, x1: u32, y1: u32, x2: u32, y2: u32, color: [4]u8) void {
    // Simple filled triangle using scanline
    // Find bounding box
    const min_x = @min(@min(x0, x1), x2);
    const max_x = @max(@max(x0, x1), x2);
    const min_y = @min(@min(y0, y1), y2);
    const max_y = @max(@max(y0, y1), y2);

    // Check each pixel in bounding box
    var y = min_y;
    while (y <= max_y) : (y += 1) {
        var x = min_x;
        while (x <= max_x) : (x += 1) {
            if (pointInTriangle(x, y, x0, y0, x1, y1, x2, y2)) {
                setPixel(data, width, x, y, color);
            }
        }
    }
}

/// Check if point is inside triangle using barycentric coordinates
fn pointInTriangle(px: u32, py: u32, x0: u32, y0: u32, x1: u32, y1: u32, x2: u32, y2: u32) bool {
    const px_f: f32 = @floatFromInt(px);
    const py_f: f32 = @floatFromInt(py);
    const x0_f: f32 = @floatFromInt(x0);
    const y0_f: f32 = @floatFromInt(y0);
    const x1_f: f32 = @floatFromInt(x1);
    const y1_f: f32 = @floatFromInt(y1);
    const x2_f: f32 = @floatFromInt(x2);
    const y2_f: f32 = @floatFromInt(y2);

    const denom = ((y1_f - y2_f) * (x0_f - x2_f) + (x2_f - x1_f) * (y0_f - y2_f));
    if (@abs(denom) < 0.001) return false;

    const a = ((y1_f - y2_f) * (px_f - x2_f) + (x2_f - x1_f) * (py_f - y2_f)) / denom;
    const b = ((y2_f - y0_f) * (px_f - x2_f) + (x0_f - x2_f) * (py_f - y2_f)) / denom;
    const c = 1.0 - a - b;

    return a >= 0.0 and a <= 1.0 and b >= 0.0 and b <= 1.0 and c >= 0.0 and c <= 1.0;
}

/// Set a pixel in the atlas
fn setPixel(data: []u8, width: u32, x: u32, y: u32, color: [4]u8) void {
    const idx = (y * width + x) * 4;
    if (idx + 3 < data.len) {
        data[idx + 0] = color[0];
        data[idx + 1] = color[1];
        data[idx + 2] = color[2];
        data[idx + 3] = color[3];
    }
}

/// Add procedural regions to the atlas
fn addProceduralRegions(regions: *std.StringHashMap(AtlasRegion), atlas_width: u32, atlas_height: u32) !void {
    const width_f: f32 = @floatFromInt(atlas_width);
    const height_f: f32 = @floatFromInt(atlas_height);

    // Helper to add region
    const addRegion = struct {
        fn add(r: *std.StringHashMap(AtlasRegion), name: []const u8, x: u32, y: u32, w: u32, h: u32, w_f: f32, h_f: f32, bl: u32, br: u32, bt: u32, bb: u32) !void {
            const allocator = r.allocator;
            const name_copy = try allocator.dupe(u8, name);
            errdefer allocator.free(name_copy);

            try r.put(name_copy, AtlasRegion{
                .uv_x0 = @as(f32, @floatFromInt(x)) / w_f,
                .uv_y0 = @as(f32, @floatFromInt(y)) / h_f,
                .uv_x1 = @as(f32, @floatFromInt(x + w)) / w_f,
                .uv_y1 = @as(f32, @floatFromInt(y + h)) / h_f,
                .width = w,
                .height = h,
                .border_left = bl,
                .border_right = br,
                .border_top = bt,
                .border_bottom = bb,
            });
        }
    }.add;

    // Buttons (no 9-slice needed for small buttons)
    try addRegion(regions, "button_normal", 0, 0, 64, 32, width_f, height_f, 4, 4, 4, 4);
    try addRegion(regions, "button_hover", 64, 0, 64, 32, width_f, height_f, 4, 4, 4, 4);
    try addRegion(regions, "button_pressed", 128, 0, 64, 32, width_f, height_f, 4, 4, 4, 4);

    // Panel with 9-slice borders
    try addRegion(regions, "panel", 0, 32, 64, 64, width_f, height_f, 8, 8, 8, 8);

    // Icons (no 9-slice)
    try addRegion(regions, "checkbox_unchecked", 64, 32, 16, 16, width_f, height_f, 0, 0, 0, 0);
    try addRegion(regions, "checkbox_checked", 80, 32, 16, 16, width_f, height_f, 0, 0, 0, 0);
    try addRegion(regions, "radio_unchecked", 96, 32, 16, 16, width_f, height_f, 0, 0, 0, 0);
    try addRegion(regions, "radio_checked", 112, 32, 16, 16, width_f, height_f, 0, 0, 0, 0);
    try addRegion(regions, "dropdown_arrow", 128, 32, 8, 8, width_f, height_f, 0, 0, 0, 0);

    // Scrollbar with 9-slice
    try addRegion(regions, "scrollbar", 0, 96, 16, 32, width_f, height_f, 2, 2, 4, 4);
}
