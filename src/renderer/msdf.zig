//! MSDF (Multi-channel Signed Distance Field) Text Rendering
//!
//! Provides high-quality scalable text rendering that preserves sharp corners.
//! MSDF uses 3 color channels (RGB) to encode distance information, where the
//! median of the three channels reconstructs the true signed distance.
//!
//! ## Features
//! - Sharp corners preserved (unlike basic SDF)
//! - Smooth text at any scale
//! - Runtime glyph generation from TrueType fonts
//! - Support for outline and shadow effects
//!
//! ## Usage
//! ```zig
//! const msdf = @import("msdf.zig");
//!
//! // Build shape from stb_truetype vertices
//! var shape = try msdf.Shape.fromVertices(allocator, vertices, num_vertices, scale, true);
//! defer shape.deinit();
//!
//! // Generate MSDF bitmap
//! var result = try msdf.generateMsdfForGlyph(allocator, &shape, 48, 4, 4.0);
//! defer result.deinit();
//!
//! // Use result.bitmap as RGB8 texture data
//! ```

pub const math = @import("msdf/math_utils.zig");
pub const edge = @import("msdf/edge.zig");
pub const contour = @import("msdf/contour.zig");
pub const coloring = @import("msdf/edge_coloring.zig");
pub const generator = @import("msdf/msdf_generator.zig");

// Re-export commonly used types
pub const Vec2 = math.Vec2;
pub const SignedDistance = math.SignedDistance;

pub const EdgeColor = edge.EdgeColor;
pub const EdgeSegment = edge.EdgeSegment;
pub const LinearSegment = edge.LinearSegment;
pub const QuadraticSegment = edge.QuadraticSegment;
pub const CubicSegment = edge.CubicSegment;

pub const Contour = contour.Contour;
pub const Shape = contour.Shape;
pub const StbttVertex = contour.StbttVertex;
pub const STBTT_vmove = contour.STBTT_vmove;
pub const STBTT_vline = contour.STBTT_vline;
pub const STBTT_vcurve = contour.STBTT_vcurve;
pub const STBTT_vcubic = contour.STBTT_vcubic;

pub const MsdfConfig = generator.MsdfConfig;
pub const MsdfResult = generator.MsdfResult;

pub const colorEdges = coloring.colorEdges;
pub const colorEdgesDefault = coloring.colorEdgesDefault;
pub const DEFAULT_ANGLE_THRESHOLD = coloring.DEFAULT_ANGLE_THRESHOLD;

pub const generateMsdf = generator.generateMsdf;
pub const generateMsdfForGlyph = generator.generateMsdfForGlyph;

// Math utilities
pub const solveQuadratic = math.solveQuadratic;
pub const solveCubic = math.solveCubic;
pub const clamp = math.clamp;
pub const sign = math.sign;
pub const lerpf = math.lerpf;

test {
    // Run all sub-module tests
    _ = math;
    _ = edge;
    _ = contour;
    _ = coloring;
    _ = generator;
}
