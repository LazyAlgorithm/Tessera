$input v_texcoord0, v_wpos

// Procedural gradient sky with a sun disc, linear HDR output.
#include <bgfx_shader.sh>

uniform vec4 u_camPos;
uniform vec4 u_sunDir;
uniform vec4 u_sunColor;
uniform vec4 u_skyZenith;
uniform vec4 u_skyHorizon;
uniform vec4 u_skyGround;

void main()
{
	vec3 dir = normalize(v_wpos - u_camPos.xyz);
	float up = dir.y;
	vec3 sky = mix(u_skyHorizon.rgb, u_skyZenith.rgb, pow(clamp(up, 0.0, 1.0), 0.45));
	vec3 ground = mix(u_skyHorizon.rgb, u_skyGround.rgb, pow(clamp(-up, 0.0, 1.0), 0.35));
	vec3 color = up >= 0.0 ? sky : ground;

	float sun = max(dot(dir, u_sunDir.xyz), 0.0);
	float disc = smoothstep(0.9993, 0.9997, sun);
	float glow = pow(sun, 180.0) * 0.6 + pow(sun, 12.0) * 0.12;
	vec3 sunTint = u_sunColor.rgb / max(max(u_sunColor.r, max(u_sunColor.g, u_sunColor.b)), 1.0e-3);
	color += sunTint * (disc * 12.0 + glow) * step(-0.02, up);

	gl_FragColor = vec4(color, 1.0);
}
