// renderer.zig
// Renderer module exports

pub const font_atlas = @import("renderer/font_atlas.zig");
pub const viewport = @import("renderer/viewport.zig");
pub const ui_atlas = @import("renderer/ui_atlas.zig");

// Re-export commonly used types
pub const FontAtlas = font_atlas.FontAtlas;
pub const Glyph = font_atlas.Glyph;
pub const UIAtlas = ui_atlas.UIAtlas;
pub const AtlasRegion = ui_atlas.AtlasRegion;

// Viewport and Virtual Resolution exports
pub const ViewportInfo = viewport.ViewportInfo;
pub const ScaleMode = viewport.ScaleMode;
pub const VirtualResolution = viewport.VirtualResolution;
pub const calculateLetterboxViewport = viewport.calculateLetterboxViewport;
pub const calculateFitViewport = viewport.calculateFitViewport;
pub const calculateFillViewport = viewport.calculateFillViewport;
pub const calculateStretchViewport = viewport.calculateStretchViewport;
