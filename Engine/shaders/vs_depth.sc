$input a_position, i_data0, i_data1, i_data2, i_data3
$output v_depth

// The depth pass for the screen effects: each solid object's distance in front of the camera. The projection comes
// per draw (u_depthViewProj), so the viewmodel, which has its own, is drawn in the same pass.
#include <bgfx_shader.sh>

uniform mat4 u_depthViewProj;
uniform vec4 u_surface;       // y: time in seconds
#include "wind.sh"

void main()
{
	mat4 model = mtxFromCols(i_data0, i_data1, i_data2, i_data3);
	vec4 world = mul(model, vec4(a_position, 1.0));
	world.xyz = tw_bend(world.xyz, i_data3.xyz, u_surface.y);
	gl_Position = mul(u_depthViewProj, world);
	v_depth = mul(u_view, world).z;
}
