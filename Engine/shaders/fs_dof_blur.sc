$input v_texcoord0, v_wpos

// Depth of field, first step (at half size): a wide round blur in which each nearby pixel takes part only as far
// as its own blur reaches, so a sharp subject does not smear into the blurred background behind it.
#include <bgfx_shader.sh>
#include "post.sh"
#include "dof.sh"

SAMPLER2D(s_color, 0);

void main()
{
	vec2 uv = v_texcoord0;
	float focus = focusDepth();
	float d = texture2D(s_depth, uv).x;
	float c = blurAmount(d, focus);
	vec3 sum = texture2D(s_color, uv).rgb;
	float weights = 1.0;
	for (int i = 0; i < 24; i++)
	{
		float t = sqrt((float(i) + 0.5) / 24.0);
		float angle = float(i) * 2.3999632;
		vec2 tap = uv + vec2(cos(angle) * u_dofParams.w, sin(angle)) * (t * u_dofParams.z);
		float td = texture2D(s_depth, tap).x;
		float tc = blurAmount(td, focus);
		// Something behind this pixel is seen through its blur only as far as this pixel is blurred itself.
		float reach = td > d ? min(tc, c) : tc;
		float w = clamp((reach - t) * 8.0 + 1.0, 0.0, 1.0);
		sum += texture2D(s_color, tap).rgb * w;
		weights += w;
	}
	gl_FragColor = vec4(sum / weights, c);
}
