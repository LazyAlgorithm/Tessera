$input v_texcoord0, v_wpos

// Bloom, second step: one direction of a wide Gaussian blur. Run across, then down.
#include <bgfx_shader.sh>

SAMPLER2D(s_color, 0);

uniform vec4 u_bloomParams; // zw: one texel along the direction of the blur

void main()
{
	vec2 d = u_bloomParams.zw;
	// Nine samples placed between texels do the work of seventeen.
	vec3 sum = texture2D(s_color, v_texcoord0).rgb * 0.1964826;
	sum += (texture2D(s_color, v_texcoord0 + d * 1.4117647).rgb + texture2D(s_color, v_texcoord0 - d * 1.4117647).rgb) * 0.2969069;
	sum += (texture2D(s_color, v_texcoord0 + d * 3.2941176).rgb + texture2D(s_color, v_texcoord0 - d * 3.2941176).rgb) * 0.0944703;
	sum += (texture2D(s_color, v_texcoord0 + d * 5.1764706).rgb + texture2D(s_color, v_texcoord0 - d * 5.1764706).rgb) * 0.0103813;
	gl_FragColor = vec4(sum, 1.0);
}
