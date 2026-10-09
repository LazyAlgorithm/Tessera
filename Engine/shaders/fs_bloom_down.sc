$input v_texcoord0, v_wpos

// Bloom, first step: shrinks the HDR scene to a quarter of its size, keeping only what is brighter than a
// threshold. The soft knee stops things popping in and out of the glow as they cross it.
#include <bgfx_shader.sh>

SAMPLER2D(s_color, 0);

uniform vec4 u_bloomParams; // x threshold, y knee, zw size of one source texel

vec3 bright(vec2 uv)
{
	vec3 color = min(texture2D(s_color, uv).rgb, vec3_splat(64.0));
	float level = max(color.r, max(color.g, color.b));
	float soft = clamp(level - u_bloomParams.x + u_bloomParams.y, 0.0, 2.0 * u_bloomParams.y);
	soft = soft * soft / (4.0 * u_bloomParams.y + 0.0001);
	float keep = max(soft, level - u_bloomParams.x) / max(level, 0.0001);
	return color * keep;
}

void main()
{
	// Four taps, each between four source texels: a 4 x 4 box in all.
	vec2 d = u_bloomParams.zw;
	vec3 sum = bright(v_texcoord0 + vec2(-d.x, -d.y)) + bright(v_texcoord0 + vec2(d.x, -d.y))
		+ bright(v_texcoord0 + vec2(-d.x, d.y)) + bright(v_texcoord0 + vec2(d.x, d.y));
	gl_FragColor = vec4(sum * 0.25, 1.0);
}
