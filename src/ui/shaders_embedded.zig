// Embedded shaders for 2D rendering
// These are simple shaders written directly as bgfx shader code

const std = @import("std");

// Since we can't easily compile bgfx shaders without shaderc,
// we'll use a simpler approach: create shaders at runtime using bgfx's
// embedded shader system or use the debug draw API enhanced.

// For a complete 2D renderer, we would need:
// 1. vs_color.bin / fs_color.bin - for colored quads
// 2. vs_texture.bin / fs_texture.bin - for textured quads (fonts, images)

// For now, we'll use bgfx's transient buffers with the default shader

// Vertex shader for colored primitives (GLSL-like pseudocode)
// In reality, this needs to be compiled with shaderc
pub const vs_color_source =
    \\$input a_position, a_color0
    \\$output v_color0
    \\
    \\#include <bgfx_shader.sh>
    \\
    \\void main()
    \\{
    \\    gl_Position = mul(u_modelViewProj, vec4(a_position, 1.0));
    \\    v_color0 = a_color0;
    \\}
;

pub const fs_color_source =
    \\$input v_color0
    \\
    \\#include <bgfx_shader.sh>
    \\
    \\void main()
    \\{
    \\    gl_FragColor = v_color0;
    \\}
;

// Vertex shader for textured primitives
pub const vs_texture_source =
    \\$input a_position, a_texcoord0, a_color0
    \\$output v_texcoord0, v_color0
    \\
    \\#include <bgfx_shader.sh>
    \\
    \\void main()
    \\{
    \\    gl_Position = mul(u_modelViewProj, vec4(a_position, 1.0));
    \\    v_texcoord0 = a_texcoord0;
    \\    v_color0 = a_color0;
    \\}
;

pub const fs_texture_source =
    \\$input v_texcoord0, v_color0
    \\
    \\#include <bgfx_shader.sh>
    \\
    \\SAMPLER2D(s_texColor, 0);
    \\
    \\void main()
    \\{
    \\    gl_FragColor = texture2D(s_texColor, v_texcoord0) * v_color0;
    \\}
;

// Note: These shader sources need to be compiled with bgfx's shaderc tool
// For a quick implementation, we'll use an alternative approach with
// debug draw or transient buffers without custom shaders
