$input v_texcoord0, v_wpos

// Resolves the HDR scene to display range: bloom added, exposure, ACES fit, gamma, vignette.
#include <bgfx_shader.sh>

SAMPLER2D(s_color, 0);
SAMPLER2D(s_bloom, 1);

uniform vec4 u_postParams; // x exposure, y vignette strength, z saturation, w bloom amount

void main()
{
	vec3 hdr = (texture2D(s_color, v_texcoord0).rgb + texture2D(s_bloom, v_texcoord0).rgb * u_postParams.w) * u_postParams.x;
	vec3 mapped = clamp((hdr * (2.51 * hdr + vec3_splat(0.03))) / (hdr * (2.43 * hdr + vec3_splat(0.59)) + vec3_splat(0.14)), 0.0, 1.0);
	float luma = dot(mapped, vec3(0.2126, 0.7152, 0.0722));
	mapped = mix(vec3_splat(luma), mapped, u_postParams.z);
	vec2 centered = v_texcoord0 - vec2(0.5, 0.5);
	float vignette = 1.0 - dot(centered, centered) * u_postParams.y;
	vec3 ldr = pow(mapped * vignette, vec3_splat(1.0 / 2.2));
	gl_FragColor = vec4(ldr, 1.0);
}
