$input v_depth

// Writes the distance in front of the camera, or -1 for the viewmodel (u_depthParams.x = 1), which the screen
// effects leave alone.
#include <bgfx_shader.sh>

uniform vec4 u_depthParams;

void main()
{
	gl_FragColor = vec4(u_depthParams.x > 0.5 ? -1.0 : v_depth, 0.0, 0.0, 1.0);
}
