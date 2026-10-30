$input v_texcoord0, v_wpos

// A copy of a picture, for passes that read what is drawn while drawing over it (the water's refraction).
#include <bgfx_shader.sh>

SAMPLER2D(s_color, 0);

void main()
{
	gl_FragColor = texture2D(s_color, v_texcoord0);
}
