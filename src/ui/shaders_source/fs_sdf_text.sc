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
	float sig_dist = texture2D(s_texColor, v_texcoord0).r;

	// SDF parameters (matching font_atlas.zig optimized generation)
	// onedge_value = 180 / 255 = 0.706
	// padding = 6 pixels
	// pixel_dist_scale = 30.0 (maps ±6px range to 0-255 optimally)

	// CRITICAL: Use fwidth() for screen-space antialiasing (per Grok recommendation)
	// This matches bitmap atlas crispness while maintaining SDF scaling benefits
	// fwidth() = abs(dFdx(sig_dist)) + abs(dFdy(sig_dist))
	// Gives us the rate of change of the distance field per screen pixel
	float edge = 0.706;  // Corresponds to onedge_value 180
	float width = fwidth(sig_dist);  // Screen-space AA width

	// Calculate alpha with screen-space antialiasing
	// smoothstep creates smooth transition over the width calculated by fwidth
	float alpha = smoothstep(edge - width, edge + width, sig_dist);

	// Apply vertex color and calculated alpha
	gl_FragColor = vec4(v_color0.rgb, v_color0.a * alpha);
}
