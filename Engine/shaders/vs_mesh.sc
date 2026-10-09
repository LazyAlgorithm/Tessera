$input a_position, a_normal, a_color0, a_texcoord0, i_data0, i_data1, i_data2, i_data3, i_data4
$output v_wpos, v_normal, v_color0, v_texcoord0, v_depth

// Lit mesh vertex shader. Every draw is instanced: i_data0..3 is the model matrix,
// i_data4 a per-instance tint, so identical meshes batch into one call.
#include <bgfx_shader.sh>

uniform vec4 u_surface;       // y: time in seconds
uniform vec4 u_params[8];     // a custom shader's own properties
//@PROPERTIES

void main()
{
	mat4 model = mtxFromCols(i_data0, i_data1, i_data2, i_data3);
	// A custom shader's vertex code may move position (in the mesh's own space) and read normal, uv and time.
	vec3 position = a_position;
	vec3 normal = a_normal;
	vec2 uv = a_texcoord0;
	float time = u_surface.y;
//@VERTEX
	vec4 wpos = mul(model, vec4(position, 1.0));
	gl_Position = mul(u_viewProj, wpos);
	v_wpos = wpos.xyz;
	v_normal = mul(model, vec4(normal, 0.0)).xyz;
	v_color0 = a_color0 * i_data4;
	v_texcoord0 = a_texcoord0;
	v_depth = gl_Position.w;
}
