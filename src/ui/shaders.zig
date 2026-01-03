const std = @import("std");
const bgfx = @import("../bgfx.zig");

/// Shader programs for UI rendering
pub const ShaderPrograms = struct {
    /// Program for rendering colored primitives (rectangles, lines, etc.)
    color_program: bgfx.ProgramHandle,

    /// Program for rendering textured primitives (text, images)
    texture_program: bgfx.ProgramHandle,

    /// Program for rendering SDF (Signed Distance Field) text
    sdf_text_program: bgfx.ProgramHandle,

    /// Program for rendering MSDF (Multi-channel Signed Distance Field) text
    msdf_text_program: bgfx.ProgramHandle,

    /// Texture sampler uniform for texture program
    texture_sampler: bgfx.UniformHandle,

    /// Initialize shader programs by loading and compiling embedded shader binaries
    pub fn init() !ShaderPrograms {
        // Load color shaders
        const vs_color_data = @embedFile("shaders_data/vs_color.bin");
        const fs_color_data = @embedFile("shaders_data/fs_color.bin");

        // Create shader handles
        const vs_color_mem = bgfx.copy(vs_color_data.ptr, @intCast(vs_color_data.len));
        const vs_color = bgfx.createShader(vs_color_mem);

        const fs_color_mem = bgfx.copy(fs_color_data.ptr, @intCast(fs_color_data.len));
        const fs_color = bgfx.createShader(fs_color_mem);

        // Create color program (true = destroy shaders after linking)
        const color_program = bgfx.createProgram(vs_color, fs_color, true);

        // Load texture shaders
        const vs_texture_data = @embedFile("shaders_data/vs_texture.bin");
        const fs_texture_data = @embedFile("shaders_data/fs_texture.bin");

        // Create shader handles
        const vs_texture_mem = bgfx.copy(vs_texture_data.ptr, @intCast(vs_texture_data.len));
        const vs_texture = bgfx.createShader(vs_texture_mem);

        const fs_texture_mem = bgfx.copy(fs_texture_data.ptr, @intCast(fs_texture_data.len));
        const fs_texture = bgfx.createShader(fs_texture_mem);

        // Create texture program
        const texture_program = bgfx.createProgram(vs_texture, fs_texture, true);

        // Load SDF text shaders
        const vs_sdf_text_data = @embedFile("shaders_data/vs_sdf_text.bin");
        const fs_sdf_text_data = @embedFile("shaders_data/fs_sdf_text.bin");

        // Create shader handles
        const vs_sdf_text_mem = bgfx.copy(vs_sdf_text_data.ptr, @intCast(vs_sdf_text_data.len));
        const vs_sdf_text = bgfx.createShader(vs_sdf_text_mem);

        const fs_sdf_text_mem = bgfx.copy(fs_sdf_text_data.ptr, @intCast(fs_sdf_text_data.len));
        const fs_sdf_text = bgfx.createShader(fs_sdf_text_mem);

        // Create SDF text program
        const sdf_text_program = bgfx.createProgram(vs_sdf_text, fs_sdf_text, true);

        // Load MSDF text shaders (reuse SDF vertex shader, different fragment shader)
        const vs_msdf_text_data = @embedFile("shaders_data/vs_sdf_text.bin");
        const fs_msdf_text_data = @embedFile("shaders_data/fs_msdf_text.bin");

        // Create shader handles
        const vs_msdf_text_mem = bgfx.copy(vs_msdf_text_data.ptr, @intCast(vs_msdf_text_data.len));
        const vs_msdf_text = bgfx.createShader(vs_msdf_text_mem);

        const fs_msdf_text_mem = bgfx.copy(fs_msdf_text_data.ptr, @intCast(fs_msdf_text_data.len));
        const fs_msdf_text = bgfx.createShader(fs_msdf_text_mem);

        // Create MSDF text program
        const msdf_text_program = bgfx.createProgram(vs_msdf_text, fs_msdf_text, true);

        // Create texture sampler uniform
        const texture_sampler = bgfx.createUniform("s_texColor", bgfx.UniformType.Sampler, 1);

        return ShaderPrograms{
            .color_program = color_program,
            .texture_program = texture_program,
            .sdf_text_program = sdf_text_program,
            .msdf_text_program = msdf_text_program,
            .texture_sampler = texture_sampler,
        };
    }

    /// Clean up shader programs
    pub fn deinit(self: ShaderPrograms) void {
        bgfx.destroyProgram(self.color_program);
        bgfx.destroyProgram(self.texture_program);
        bgfx.destroyProgram(self.sdf_text_program);
        bgfx.destroyProgram(self.msdf_text_program);
        bgfx.destroyUniform(self.texture_sampler);
    }
};
