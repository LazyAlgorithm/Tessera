// Shared by fs_dof_blur and fs_dof_combine.

SAMPLER2D(s_depth, 1);

uniform vec4 u_dofParams; // x focus distance (below 0: focus on what is in the middle of the screen), y in-focus range, z largest blur (fraction of the screen's height), w height / width

// The distance in focus: the setting, or (auto-focus) what is in the middle of the screen, from five taps.
float focusDepth()
{
	if (u_dofParams.x >= 0.0)
		return u_dofParams.x;
	float sum = 0.0;
	float count = 0.0;
	for (int i = 0; i < 5; i++)
	{
		vec2 offset = i == 0 ? vec2(0.0, 0.0) : vec2(i == 1 ? 0.02 : (i == 2 ? -0.02 : 0.0), i == 3 ? 0.02 : (i == 4 ? -0.02 : 0.0));
		float d = texture2D(s_depth, vec2(0.5, 0.5) + offset).x;
		if (d >= 0.0)
		{
			sum += min(d, 1000.0);
			count += 1.0;
		}
	}
	return count > 0.0 ? sum / count : 1000.0;
}

// 0 in focus, 1 fully blurred: sharp within half the range either side of the focus, fully blurred a range beyond.
// The viewmodel is always sharp.
float blurAmount(float depth, float focus)
{
	if (depth < 0.0)
		return 0.0;
	float range = max(u_dofParams.y, 0.01);
	return clamp((abs(depth - focus) - range * 0.5) / range, 0.0, 1.0);
}
