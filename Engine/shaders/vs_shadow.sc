$input a_position, i_data0, i_data1, i_data2, i_data3

// Depth-only pass for the directional light cascades.
#include <bgfx_shader.sh>

uniform vec4 u_surface;       // y: time in seconds
#include "wind.sh"

void main()
{
	mat4 model = mtxFromCols(i_data0, i_data1, i_data2, i_data3);
	vec4 world = mul(model, vec4(a_position, 1.0));
	// The shadow of something that sways in the wind sways with it.
	world.xyz = tw_bend(world.xyz, i_data3.xyz, u_surface.y);
	gl_Position = mul(u_viewProj, world);
}
