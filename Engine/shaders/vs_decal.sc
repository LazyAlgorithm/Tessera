$input a_position
$output v_wpos

// A decal's box: the unit cube placed by u_decalBox. Only its back faces are drawn, so that the decal still shows
// with the camera inside the box; fs_decal.sc finds the surfaces behind each pixel.
#include <bgfx_shader.sh>

uniform mat4 u_decalBox;

void main()
{
	vec4 world = mul(u_decalBox, vec4(a_position, 1.0));
	v_wpos = world.xyz;
	gl_Position = mul(u_viewProj, world);
}
