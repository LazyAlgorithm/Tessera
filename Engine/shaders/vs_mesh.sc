$input a_position, a_normal, a_color0, a_texcoord0, i_data0, i_data1, i_data2, i_data3, i_data4
$output v_wpos, v_normal, v_color0, v_texcoord0, v_depth

// Lit mesh vertex shader. Every draw is instanced: i_data0..3 is the model matrix,
// i_data4 a per-instance tint, so identical meshes batch into one call.
#include <bgfx_shader.sh>

uniform vec4 u_surface;       // y: time in seconds
uniform vec4 u_params[8];     // a custom shader's own properties
uniform vec4 u_wind;          // xyz: the wind over the whole scene, w: how gusty it is (0 to 1)
uniform vec4 u_windZone[4];   // xyz: the middle of a wind zone, w: how far it reaches (0: not in use)
uniform vec4 u_windPush[4];   // xyz: the wind inside that zone
uniform vec4 u_sway;          // x: how far this draw bends in the wind (0: not at all)
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
	if (u_sway.x > 0.0)
	{
		// Bending in the wind: each plant leans and swings about its own foot (the object's origin), more the
		// higher up the point is, so roots stay put and tips move most.
		vec3 tw_foot = i_data3.xyz;
		vec3 tw_wind = u_wind.xyz;
		for (int tw_zone = 0; tw_zone < 4; tw_zone++)
		{
			float tw_reach = max(u_windZone[tw_zone].w, 0.0001);
			float tw_inside = clamp(1.0 - length(tw_foot - u_windZone[tw_zone].xyz) / tw_reach, 0.0, 1.0);
			tw_wind += u_windPush[tw_zone].xyz * tw_inside * step(0.001, u_windZone[tw_zone].w);
		}
		float tw_speed = length(tw_wind);
		if (tw_speed > 0.0001)
		{
			float tw_height = max(wpos.y - tw_foot.y, 0.0);
			float tw_phase = tw_foot.x * 0.35 + tw_foot.z * 0.27;
			float tw_gust = 0.6 + 0.4 * u_wind.w * sin(time * 0.7 + tw_phase * 0.3);
			float tw_swing = sin(time * (1.6 + tw_speed * 0.25) + tw_phase) * 0.35 + sin(time * 3.7 + tw_phase * 2.3 + wpos.x * 1.7 + wpos.z * 1.3) * 0.08;
			float tw_amount = u_sway.x * min(tw_speed, 8.0) * 0.2 * (tw_height * tw_height / (tw_height + 0.25)) * (tw_gust * 0.6 + tw_swing);
			wpos.xyz += (tw_wind / tw_speed) * tw_amount;
			wpos.y -= abs(tw_amount) * 0.2;
		}
	}
	gl_Position = mul(u_viewProj, wpos);
	v_wpos = wpos.xyz;
	v_normal = mul(model, vec4(normal, 0.0)).xyz;
	v_color0 = a_color0 * i_data4;
	v_texcoord0 = a_texcoord0;
	v_depth = gl_Position.w;
}
