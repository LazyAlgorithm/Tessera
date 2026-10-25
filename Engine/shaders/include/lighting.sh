// The lighting every lit surface shares (fs_mesh.sc, custom shaders, decals): the sun with four shadow cascades,
// up to MAX_LIGHTS point, spot and directional lights with spotlight shadows, hemisphere ambient, reflections of
// the sky and of reflection probes (docs/reflections.md), and distance fog. Include after bgfx_shader.sh.
#ifndef TESSERA_LIGHTING_SH
#define TESSERA_LIGHTING_SH

#define MAX_LIGHTS 16
#define PI 3.14159265

SAMPLER2DSHADOW(s_shadowMap, 1);
SAMPLER2DSHADOW(s_spotShadowMap, 11);
// What surfaces mirror: the nearest reflection probe's cube and the sky's, each with rougher levels down its mips.
SAMPLERCUBE(s_reflectionProbe, 13);
SAMPLERCUBE(s_reflectionSky, 14);

uniform vec4 u_camPos;
uniform vec4 u_sunDir;        // xyz: direction towards the sun, w: shadow strength
uniform vec4 u_sunColor;      // rgb premultiplied by intensity
uniform vec4 u_ambientSky;
uniform vec4 u_ambientGround;
uniform vec4 u_fogColor;      // rgb, a: density
uniform vec4 u_lightPosRange[MAX_LIGHTS];  // xyz position, w range
uniform vec4 u_lightColor[MAX_LIGHTS];     // rgb premultiplied by intensity, w: 1 for spot
uniform vec4 u_lightDirSpot[MAX_LIGHTS];   // xyz spot direction, w cos(outer angle)
uniform vec4 u_lightParams[MAX_LIGHTS];    // x cos(inner angle)
uniform vec4 u_lightCount;
uniform mat4 u_shadowMtx[4];
uniform mat4 u_spotShadowMtx[MAX_LIGHTS];
uniform vec4 u_spotShadowParams[MAX_LIGHTS]; // strength, texel size, depth bias, normal offset
uniform vec4 u_cascadeSplits;
uniform vec4 u_shadowParams;  // x texel size, y depth bias, z enabled, w normal offset
uniform vec4 u_reflection;    // x: 1 with reflection cubes (0: the ambient colours stand in), y: the sky cube's
                              // last level, z: the probe's intensity (0: no probe), w: the scene's reflection intensity
uniform vec4 u_probeMin;      // the probe's box, xyz: its lowest corner, w: 1 to project onto the box
uniform vec4 u_probeMax;      // xyz: its highest corner, w: how far outside it its reflections fade out
uniform vec4 u_probePos;      // xyz: where the probe saw from, w: its cube's last level
uniform vec4 u_ambientParams; // x: 1 to take ambient light from the reflection cubes, y: the scene's ambient intensity

vec3 toLinear3(vec3 c)
{
	return pow(abs(c), vec3_splat(2.2));
}

float distributionGGX(float ndoth, float a)
{
	float a2 = a * a;
	float d = ndoth * ndoth * (a2 - 1.0) + 1.0;
	return a2 / (PI * d * d + 1.0e-6);
}

float visibilitySmith(float ndotv, float ndotl, float a)
{
	float k = a * 0.5;
	float gv = ndotv / (ndotv * (1.0 - k) + k);
	float gl = ndotl / (ndotl * (1.0 - k) + k);
	return gv * gl / (4.0 * ndotv * ndotl + 1.0e-4);
}

vec3 brdf(vec3 n, vec3 v, vec3 l, vec3 albedo, float metallic, float roughness, float specularLevel)
{
	vec3 h = normalize(v + l);
	float ndotl = max(dot(n, l), 0.0);
	float ndotv = max(dot(n, v), 1.0e-3);
	float ndoth = max(dot(n, h), 0.0);
	float vdoth = max(dot(v, h), 0.0);
	float a = roughness * roughness;
	vec3 f0 = mix(vec3_splat(0.04 * specularLevel), albedo, metallic);
	vec3 fresnel = f0 + (vec3_splat(1.0) - f0) * pow(1.0 - vdoth, 5.0);
	vec3 specular = fresnel * (distributionGGX(ndoth, a) * visibilitySmith(ndotv, ndotl, a));
	vec3 diffuse = albedo * (1.0 - metallic) * (1.0 / PI);
	return (diffuse * (vec3_splat(1.0) - fresnel) + specular) * ndotl;
}

// Perspective shadow comparison for a spotlight, bounded to its atlas tile so filtering never reads a neighbour.
float spotShadow(int index, vec3 wpos, vec3 normal)
{
    vec4 params = u_spotShadowParams[index];
    if (params.x <= 0.0) return 1.0;
    vec4 clip = mul(u_spotShadowMtx[index], vec4(wpos + normal * params.w, 1.0));
    if (clip.w <= 0.0) return 1.0;
    vec3 sc = clip.xyz / clip.w;
    if (sc.z < 0.0 || sc.z > 1.0) return 1.0;
    // The matrix already accounts for the graphics API's texture origin. Find the tile from its centre.
    vec4 centreClip = mul(u_spotShadowMtx[index], vec4(u_lightPosRange[index].xyz + u_lightDirSpot[index].xyz, 1.0));
    vec2 tileMin = floor((centreClip.xy / centreClip.w) * 4.0) * 0.25;
    vec2 lo = tileMin + vec2_splat(params.y * 1.5);
    vec2 hi = tileMin + vec2_splat(0.25 - params.y * 1.5);
    if (any(lessThan(sc.xy, tileMin)) || any(greaterThan(sc.xy, tileMin + vec2_splat(0.25)))) return 1.0;
    float depth = sc.z - params.z;
    float sum = 0.0;
    sum += shadow2D(s_spotShadowMap, vec3(clamp(sc.xy + vec2(-0.5,-0.5) * params.y, lo, hi), depth));
    sum += shadow2D(s_spotShadowMap, vec3(clamp(sc.xy + vec2( 0.5,-0.5) * params.y, lo, hi), depth));
    sum += shadow2D(s_spotShadowMap, vec3(clamp(sc.xy + vec2(-0.5, 0.5) * params.y, lo, hi), depth));
    sum += shadow2D(s_spotShadowMap, vec3(clamp(sc.xy + vec2( 0.5, 0.5) * params.y, lo, hi), depth));
    return mix(1.0, sum * 0.25, params.x);
}

float shadowTap(mat4 mtx, vec3 wpos)
{
	vec4 sc = mul(mtx, vec4(wpos, 1.0));
	float texel = u_shadowParams.x;
	float depth = sc.z - u_shadowParams.y;
	float sum = 0.0;
	sum += shadow2D(s_shadowMap, vec3(sc.xy + vec2(-0.5, -0.5) * texel, depth));
	sum += shadow2D(s_shadowMap, vec3(sc.xy + vec2( 0.5, -0.5) * texel, depth));
	sum += shadow2D(s_shadowMap, vec3(sc.xy + vec2(-0.5,  0.5) * texel, depth));
	sum += shadow2D(s_shadowMap, vec3(sc.xy + vec2( 0.5,  0.5) * texel, depth));
	sum += shadow2D(s_shadowMap, vec3(sc.xy + vec2(-1.5,  0.5) * texel, depth));
	sum += shadow2D(s_shadowMap, vec3(sc.xy + vec2( 1.5, -0.5) * texel, depth));
	sum += shadow2D(s_shadowMap, vec3(sc.xy + vec2( 0.5,  1.5) * texel, depth));
	sum += shadow2D(s_shadowMap, vec3(sc.xy + vec2(-0.5, -1.5) * texel, depth));
	return sum * 0.125;
}

float sunShadow(vec3 wpos, vec3 n, float viewDepth)
{
	if (u_shadowParams.z < 0.5 || viewDepth > u_cascadeSplits.w)
	{
		return 1.0;
	}
	vec3 p = wpos + n * u_shadowParams.w;
	float s;
	if (viewDepth < u_cascadeSplits.x)
	{
		s = shadowTap(u_shadowMtx[0], p);
	}
	else if (viewDepth < u_cascadeSplits.y)
	{
		s = shadowTap(u_shadowMtx[1], p + n * u_shadowParams.w);
	}
	else if (viewDepth < u_cascadeSplits.z)
	{
		s = shadowTap(u_shadowMtx[2], p + n * u_shadowParams.w * 3.0);
	}
	else
	{
		s = shadowTap(u_shadowMtx[3], p + n * u_shadowParams.w * 7.0);
	}
	// Fade out towards the end of the last cascade so the shadow distance has no hard edge.
	float fade = clamp((u_cascadeSplits.w - viewDepth) / (u_cascadeSplits.w * 0.1), 0.0, 1.0);
	return mix(1.0, s, fade * u_sunDir.w);
}

// The ambient light on a surface facing n, between the ground's colour below and the sky's above.
vec3 hemisphereAmbient(vec3 n)
{
	return mix(u_ambientGround.rgb, u_ambientSky.rgb, n.y * 0.5 + 0.5);
}

// Where a reflection probe's cube is looked up for a ray from wpos along dir: with box projection, the direction from
// the probe to where the ray leaves the box, so that reflections of the walls line up wherever the surface is.
vec3 probeDirection(vec3 wpos, vec3 dir)
{
	if (u_probeMin.w < 0.5)
		return dir;
	vec3 toMax = (u_probeMax.xyz - wpos) / dir;
	vec3 toMin = (u_probeMin.xyz - wpos) / dir;
	vec3 leave = max(toMax, toMin);
	float distance = max(min(min(leave.x, leave.y), leave.z), 0.0);
	return wpos + dir * distance - u_probePos.xyz;
}

// What a surface of this roughness mirrors along dir: the sky, and the probe it is in.
vec3 environmentReflection(vec3 wpos, vec3 dir, float roughness)
{
	vec3 color = textureCubeLod(s_reflectionSky, dir, roughness * u_reflection.y).rgb;
	if (u_reflection.z > 0.0)
	{
		// All of the probe inside its box, fading to none a blend distance outside it.
		vec3 outside = max(max(u_probeMin.xyz - wpos, wpos - u_probeMax.xyz), vec3_splat(0.0));
		float weight = 1.0 - clamp(length(outside) / max(u_probeMax.w, 0.001), 0.0, 1.0);
		if (weight > 0.0)
		{
			vec3 probe = textureCubeLod(s_reflectionProbe, probeDirection(wpos, dir), roughness * u_probePos.w).rgb;
			color = mix(color, probe * u_reflection.z, weight);
		}
	}
	return color * u_reflection.w;
}

// The light from all around on a surface facing n, from the cubes' roughest levels (image-based ambient light): the
// sky's, and inside a probe's box the room it saw.
vec3 environmentAmbient(vec3 wpos, vec3 n)
{
	vec3 color = textureCubeLod(s_reflectionSky, n, u_reflection.y).rgb;
	if (u_reflection.z > 0.0)
	{
		vec3 outside = max(max(u_probeMin.xyz - wpos, wpos - u_probeMax.xyz), vec3_splat(0.0));
		float weight = 1.0 - clamp(length(outside) / max(u_probeMax.w, 0.001), 0.0, 1.0);
		if (weight > 0.0)
			color = mix(color, textureCubeLod(s_reflectionProbe, n, u_probePos.w).rgb * u_reflection.z, weight);
	}
	return color * u_ambientParams.y;
}

// How much of the mirrored light a surface gives back, over every angle of its highlight: Karis' fit of the
// split-sum lookup ("Physically Based Shading on Mobile").
vec3 environmentBrdf(vec3 f0, float roughness, float ndotv)
{
	vec4 r = roughness * vec4(-1.0, -0.0275, -0.572, 0.022) + vec4(1.0, 0.0425, 1.04, -0.04);
	float a004 = min(r.x * r.x, exp2(-9.28 * ndotv)) * r.x + r.y;
	vec2 ab = vec2(-1.04, 1.04) * a004 + r.zw;
	return f0 * ab.x + ab.y;
}

// A surface's colour under every light, before its glow and fog: ambient (already worked out, from the hemisphere
// or a lightmap), the surroundings mirrored, the sun and the scene's lights. bakedMask holds a lightmap's shadow
// mask (all 1 without one); a lightmapped surface skips lights that are baked into it.
vec3 shadeSurface(vec3 wpos, vec3 n, vec3 v, float viewDepth, vec3 albedo, float metallic, float roughness,
	float specularLevel, float occlusion, vec3 ambient, vec4 bakedMask, bool lightmapped)
{
	vec3 mirrored = reflect(-v, n);
	vec3 f0 = mix(vec3_splat(0.04 * specularLevel), albedo, metallic);
	vec3 color;
	if (u_reflection.x > 0.5)
	{
		if (u_ambientParams.x > 0.5 && !lightmapped)
			ambient = environmentAmbient(wpos, n);
		// What the surface mirrors of its surroundings, from the sky's and the probe's cubes: metals all of it,
		// tinted, and other things a little, more at a grazing angle.
		color = ambient * albedo * (1.0 - metallic) * occlusion;
		color += environmentReflection(wpos, mirrored, roughness) * environmentBrdf(f0, roughness, max(dot(n, v), 0.0)) * occlusion;
	}
	else
	{
		// Without reflection cubes (the Low quality preset), the sky and ground colours stand in for them. It is
		// what keeps a smooth metal from looking black where no light shines on it directly.
		color = ambient * albedo * (1.0 - metallic * 0.5) * occlusion;
		vec3 surroundings = mix(u_ambientGround.rgb, u_ambientSky.rgb, clamp(mirrored.y * 0.5 + 0.5, 0.0, 1.0));
		float grazing = pow(1.0 - max(dot(n, v), 0.0), 5.0);
		vec3 reflectance = f0 + (max(vec3_splat(1.0 - roughness), f0) - f0) * grazing;
		color += surroundings * reflectance * (1.0 - roughness * 0.75) * metallic * occlusion;
	}

	float shadow = sunShadow(wpos, n, viewDepth);
	if (u_lightCount.y > 0.5)
	{
		int channel = int(u_lightCount.y - 1.0);
		shadow = min(shadow, bakedMask[channel]);
	}
	color += brdf(n, v, u_sunDir.xyz, albedo, metallic, roughness, specularLevel) * u_sunColor.rgb * shadow * PI;

	for (int i = 0; i < MAX_LIGHTS; i++)
	{
		if (float(i) >= u_lightCount.x)
		{
			break;
		}
		if (u_lightParams[i].w > 0.5 && lightmapped) continue;
		vec3 toLight = u_lightPosRange[i].xyz - wpos;
		float dist = length(toLight);
		float range = u_lightPosRange[i].w;
		bool directional = u_lightColor[i].w > 1.5;
		if (directional || dist < range)
		{
			vec3 l = directional ? -u_lightDirSpot[i].xyz : toLight / max(dist, 1.0e-4);
			float falloff = clamp(1.0 - dist / max(range, 1.0e-4), 0.0, 1.0);
			float atten = falloff * falloff / (1.0 + dist * dist * 0.1);
			if (u_lightParams[i].y > 0.5)
			{
				float ratio = dist * dist / max(range * range, 1.0e-8);
				float fade = max(1.0 - ratio * ratio, 0.0);
				atten = fade * fade / max(dist * dist, 1.0e-6);
			}
			if (directional) atten = 1.0;
			else if (u_lightColor[i].w > 0.5)
			{
				float cosAngle = dot(-l, u_lightDirSpot[i].xyz);
				atten *= smoothstep(u_lightDirSpot[i].w, u_lightParams[i].x, cosAngle);
				atten *= spotShadow(i, wpos, n);
			}
			if (u_lightParams[i].z > 0.5) atten *= bakedMask[int(u_lightParams[i].z - 1.0)];
			color += brdf(n, v, l, albedo, metallic, roughness, specularLevel) * u_lightColor[i].rgb * atten * PI;
		}
	}
	return color;
}

// Distance fog over a colour seen at wpos.
vec3 applyFog(vec3 color, vec3 wpos)
{
	float fogDistance = length(u_camPos.xyz - wpos);
	float fog = 1.0 - exp(-fogDistance * fogDistance * u_fogColor.a * u_fogColor.a);
	return mix(color, u_fogColor.rgb, clamp(fog, 0.0, 1.0));
}

#endif // TESSERA_LIGHTING_SH
