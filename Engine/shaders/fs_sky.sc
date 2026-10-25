$input v_texcoord0, v_wpos

// Procedural gradient sky with a sun disc, linear HDR output (include/sky.sh).
#include <bgfx_shader.sh>
#include "sky.sh"

uniform vec4 u_camPos;

void main()
{
	gl_FragColor = vec4(skyColor(normalize(v_wpos - u_camPos.xyz), 1.0), 1.0);
}
