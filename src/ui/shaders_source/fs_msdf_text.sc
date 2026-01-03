$input v_texcoord0, v_color0

/*
 * MSDF Text Fragment Shader
 * Renders multi-channel signed distance field text with sharp corners
 *
 * Based on Chlumsky's msdfgen and Valve's Alpha-Tested Magnification paper
 * Reference: https://github.com/Chlumsky/msdfgen
 */

#include <bgfx_shader.sh>

SAMPLER2D(s_texColor, 0);

float median(vec3 rgb) {
    return max(min(rgb.r, rgb.g), min(max(rgb.r, rgb.g), rgb.b));
}

void main()
{
    // Sample the MSDF texture (RGB channels contain distance data)
    vec3 sample = texture2D(s_texColor, v_texcoord0).rgb;

    // Calculate signed distance from median of RGB channels
    // Each channel is encoded as 0-255 mapped to distance range
    // 127.5 = on edge, <127.5 = inside, >127.5 = outside (inverted from generator)
    float sigDist = median(sample) - 0.5;

    // Calculate anti-aliasing width using screen-space derivatives
    // fwidth() gives the rate of change of sigDist across the screen
    float width = fwidth(sigDist);

    // Clamp width to reasonable range for stability
    width = clamp(width, 0.001, 0.5);

    // Calculate opacity with smooth anti-aliasing
    float opacity = clamp(sigDist / width + 0.5, 0.0, 1.0);

    // Apply vertex color with calculated alpha
    gl_FragColor = vec4(v_color0.rgb, v_color0.a * opacity);
}
