$input v_texcoord0, v_wpos

// Ambient occlusion, second step: blurs the half-size occlusion without letting it cross from one surface to
// another (taps far from this pixel's depth count for little), and darkens the scene by it.
#include <bgfx_shader.sh>
#include "post.sh"

SAMPLER2D(s_color, 0);
SAMPLER2D(s_ao, 1);
SAMPLER2D(s_depth, 2);

uniform vec4 u_aoParams; // zw one occlusion texel

void main()
{
	vec2 uv = v_texcoord0;
	vec3 color = texture2D(s_color, uv).rgb;
	float d = texture2D(s_depth, uv).x;
	if (isViewmodel(d) || isSky(d))
	{
		gl_FragColor = vec4(color, 1.0);
		return;
	}
	float tolerance = 0.05 + d * 0.04;
	float sum = 0.0;
	float weights = 0.0;
	for (int y = -1; y <= 1; y++)
	{
		for (int x = -1; x <= 1; x++)
		{
			vec2 tap = uv + vec2(float(x), float(y)) * u_aoParams.zw;
			float w = max(1.0 - abs(texture2D(s_depth, tap).x - d) / tolerance, 0.0);
			sum += texture2D(s_ao, tap).x * w;
			weights += w;
		}
	}
	float ao = weights > 0.001 ? sum / weights : 1.0;
	gl_FragColor = vec4(color * ao, 1.0);
}
