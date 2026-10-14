// Bending in the wind, shared by every vertex shader that draws meshes (the lit pass, the shadow pass and the depth
// pass), so that a plant, its shadow and its depth all move together.
//
// Names here start tw_: a custom shader's properties are names its author chose (speed, height, amount...), and
// plain names would clash with them.

uniform vec4 u_wind;          // xyz: the wind over the whole scene, w: how gusty it is (0 to 1)
uniform vec4 u_windZone[4];   // xyz: the middle of a wind zone, w: how far it reaches (0: not in use)
uniform vec4 u_windPush[4];   // xyz: the wind inside that zone
uniform vec4 u_sway;          // x: how far this draw bends in the wind (0: not at all)
uniform vec4 u_bender[8];     // xyz: something pushing plants aside (a player's feet), w: how far it reaches (0: not in use)
uniform vec4 u_benderPush[8]; // x: how hard it pushes

// A point of an object, moved by the wind. tw_foot is the object's origin (the fourth column of its matrix): each
// object leans and swings about its own foot, more the higher up the point is, so roots stay put and tips move most.
vec3 tw_bend(vec3 tw_point, vec3 tw_foot, float tw_time)
{
	if (u_sway.x <= 0.0)
		return tw_point;
	float tw_height = max(tw_point.y - tw_foot.y, 0.0);
	float tw_lift = tw_height * tw_height / (tw_height + 0.25);
	vec3 tw_moved = tw_point;

	// The wind.
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
		float tw_phase = tw_foot.x * 0.35 + tw_foot.z * 0.27;
		float tw_gust = 0.6 + 0.4 * u_wind.w * sin(tw_time * 0.7 + tw_phase * 0.3);
		float tw_swing = sin(tw_time * (1.6 + tw_speed * 0.25) + tw_phase) * 0.35 + sin(tw_time * 3.7 + tw_phase * 2.3 + tw_point.x * 1.7 + tw_point.z * 1.3) * 0.08;
		float tw_amount = u_sway.x * min(tw_speed, 8.0) * 0.2 * tw_lift * (tw_gust * 0.6 + tw_swing);
		tw_moved += (tw_wind / tw_speed) * tw_amount;
		tw_moved.y -= abs(tw_amount) * 0.2;
	}

	// Things walking through: each point is pushed away from them and pressed down, most at the tips, so that grass
	// parts round a player's feet and closes again behind.
	float tw_give = min(u_sway.x, 1.0);
	for (int tw_who = 0; tw_who < 8; tw_who++)
	{
		float tw_radius = u_bender[tw_who].w;
		if (tw_radius <= 0.001)
			continue;
		vec3 tw_from = tw_point - u_bender[tw_who].xyz;
		float tw_flat = length(tw_from.xz);
		// Only plants at about the height of whatever it is: someone on a bridge does not part the grass below.
		float tw_level = clamp(1.0 - abs(tw_foot.y - u_bender[tw_who].y) / (tw_radius * 2.0 + 0.5), 0.0, 1.0);
		float tw_near = clamp(1.0 - tw_flat / tw_radius, 0.0, 1.0);
		float tw_press = tw_near * tw_near * tw_level * u_benderPush[tw_who].x * tw_give;
		if (tw_press <= 0.0)
			continue;
		vec2 tw_away = tw_flat > 0.0001 ? tw_from.xz / tw_flat : vec2(1.0, 0.0);
		// No further than the plant is tall: it leans over, it does not stretch.
		float tw_lean = min(tw_press * tw_radius * 0.9, tw_height * 0.9) * (tw_lift / max(tw_height, 0.0001));
		tw_moved.xz += tw_away * tw_lean;
		tw_moved.y -= min(tw_press, 1.0) * tw_height * 0.55;
	}
	return tw_moved;
}
