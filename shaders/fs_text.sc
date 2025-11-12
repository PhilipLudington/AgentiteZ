$input v_texcoord0

#include <bgfx_shader.sh>

SAMPLER2D(s_texColor, 0);

void main()
{
    float alpha = texture2D(s_texColor, v_texcoord0).r;
    gl_FragColor = vec4(1.0, 1.0, 1.0, alpha);
}
