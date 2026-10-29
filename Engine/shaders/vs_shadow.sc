$input a_position, i_data0, i_data1, i_data2, i_data3

// Depth-only pass for shadows: the sun's cascades and the point and spot lights' tiles, each drawn through its own
// matrix (a point or spot tile's squeezes the light's view into its part of the atlas).
#include <bgfx_shader.sh>

uniform vec4 u_surface;       // y: time in seconds
uniform mat4 u_shadowViewProj;
#include "wind.sh"

void main()
{
	// The bottom row carries the instance's metallic and roughness (see vs_mesh.sc): it is (0, 0, 0, 1).
	mat4 model = mtxFromCols(vec4(i_data0.xyz, 0.0), vec4(i_data1.xyz, 0.0), vec4(i_data2.xyz, 0.0), i_data3);
	vec4 world = mul(model, vec4(a_position, 1.0));
	// The shadow of something that sways in the wind sways with it.
	world.xyz = tw_bend(world.xyz, i_data3.xyz, u_surface.y);
	gl_Position = mul(u_shadowViewProj, world);
}
