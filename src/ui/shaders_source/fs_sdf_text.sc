$input v_texcoord0, v_color0

/*
 * SDF Text Fragment Shader
 * Renders signed distance field text with smooth edges at any scale
 *
 * Based on Valve's "Improved Alpha-Tested Magnification for Vector Textures and Special Effects"
 * Reference: http://www.valvesoftware.com/publications/2007/SIGGRAPH2007_AlphaTestedMagnification.pdf
 */

#include <bgfx_shader.sh>

SAMPLER2D(s_texColor, 0);

void main()
{
	// Sample the SDF texture (single channel R8)
	float distance = texture2D(s_texColor, v_texcoord0).r;

	// SDF parameters (matching font_atlas.zig generation)
	// onedge_value = 128 / 255 = 0.502
	// pixel_dist_scale = 32.0 (updated from 64.0)
	// We want to render pixels where distance >= onedge_value

	// Simple threshold for sharp edges
	// For smoother antialiasing, use smoothstep:
	float edge = 0.5;  // Corresponds to onedge_value 128
	float smoothing = 0.25 / 32.0;  // Smoothing based on pixel_dist_scale (updated)

	// Calculate alpha with antialiasing
	float alpha = smoothstep(edge - smoothing, edge + smoothing, distance);

	// Apply vertex color and calculated alpha
	gl_FragColor = vec4(v_color0.rgb, v_color0.a * alpha);
}
