$input v_texcoord0, v_wpos

// Depth of field, second step: the sharp picture where it is in focus, the blurred one where it is not. The blur's
// own amount (alpha) lets a blurred foreground edge spill a little over what is behind it.
#include <bgfx_shader.sh>
#include "post.sh"
#include "dof.sh"

SAMPLER2D(s_color, 0);
SAMPLER2D(s_blur, 2);

void main()
{
	vec2 uv = v_texcoord0;
	vec3 sharp = texture2D(s_color, uv).rgb;
	vec4 blurred = texture2D(s_blur, uv);
	float c = blurAmount(texture2D(s_depth, uv).x, focusDepth());
	float amount = smoothstep(0.02, 0.2, max(c, blurred.a));
	gl_FragColor = vec4(mix(sharp, blurred.rgb, amount), 1.0);
}
