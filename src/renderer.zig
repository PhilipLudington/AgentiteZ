// renderer.zig
// Renderer module exports

pub const font_atlas = @import("renderer/font_atlas.zig");

// Re-export commonly used types
pub const FontAtlas = font_atlas.FontAtlas;
pub const Glyph = font_atlas.Glyph;
