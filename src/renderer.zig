// renderer.zig
// Renderer module exports

pub const font_atlas = @import("renderer/font_atlas.zig");
pub const viewport = @import("renderer/viewport.zig");
pub const ui_atlas = @import("renderer/ui_atlas.zig");

// Re-export commonly used types
pub const FontAtlas = font_atlas.FontAtlas;
pub const Glyph = font_atlas.Glyph;
pub const ViewportInfo = viewport.ViewportInfo;
pub const calculateLetterboxViewport = viewport.calculateLetterboxViewport;
pub const UIAtlas = ui_atlas.UIAtlas;
pub const AtlasRegion = ui_atlas.AtlasRegion;
