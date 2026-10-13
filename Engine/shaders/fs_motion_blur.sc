$input v_texcoord0, v_wpos

// Camera motion blur: where each pixel's surface was on screen last frame (its depth, put back through last frame's
// camera), and a smear along the way it moved. Moving objects seen by a still camera are not blurred, and neither is
// the viewmodel.
#include <bgfx_shader.sh>
#include "post.sh"

SAMPLER2D(s_color, 0);
SAMPLER2D(s_depth, 1);

uniform mat4 u_prevViewProj;
uniform vec4 u_motionParams; // x strength (the share of a frame's movement smeared), y longest smear (fraction of the screen)

void main()
{
	vec2 uv = v_texcoord0;
	vec3 color = texture2D(s_color, uv).rgb;
	float d = texture2D(s_depth, uv).x;
	if (isViewmodel(d))
	{
		gl_FragColor = vec4(color, 1.0);
		return;
	}
	vec4 clip = mul(u_prevViewProj, vec4(worldPosition(uv, d), 1.0));
	if (clip.w <= 0.0001)
	{
		gl_FragColor = vec4(color, 1.0);
		return;
	}
	vec2 velocity = (uv - ndcToUv(clip.xy / clip.w)) * u_motionParams.x;
	float speed = length(velocity);
	if (speed > u_motionParams.y)
		velocity *= u_motionParams.y / speed;
	if (speed < 0.0005)
	{
		gl_FragColor = vec4(color, 1.0);
		return;
	}
	vec3 sum = color;
	float weights = 1.0;
	for (int i = 0; i < 8; i++)
	{
		vec2 tap = uv + velocity * ((float(i) + 0.5) / 8.0 - 0.5);
		if (!isViewmodel(texture2D(s_depth, tap).x))
		{
			sum += texture2D(s_color, tap).rgb;
			weights += 1.0;
		}
	}
	gl_FragColor = vec4(sum / weights, 1.0);
}
