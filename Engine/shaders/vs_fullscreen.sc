$input a_position, a_texcoord0
$output v_texcoord0, v_wpos

// Fullscreen triangle. v_wpos carries the far-plane world position for sky rays.
#include <bgfx_shader.sh>

void main()
{
	gl_Position = vec4(a_position.xy, 1.0, 1.0);
	v_texcoord0 = a_texcoord0;
	vec4 far = mul(u_invViewProj, vec4(a_position.xy, 1.0, 1.0));
	v_wpos = far.xyz / far.w;
}
