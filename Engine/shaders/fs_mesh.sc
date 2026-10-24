$input v_wpos, v_normal, v_color0, v_texcoord0, v_depth, v_texcoord1

// Forward lit surface: metallic/roughness BRDF, one shadowed directional light with four
// cascades, up to 16 point/spot lights with spotlight shadows, hemisphere ambient and distance fog. Output is linear HDR.
#include <bgfx_shader.sh>

#define MAX_LIGHTS 16
#define PI 3.14159265

SAMPLER2D(s_albedo, 0);
SAMPLER2DSHADOW(s_shadowMap, 1);
SAMPLER2DSHADOW(s_spotShadowMap, 11);
SAMPLER2D(s_texture1, 2);
SAMPLER2D(s_texture2, 3);
SAMPLER2D(s_normalMap, 4);
SAMPLER2D(s_metalRoughMap, 5);
SAMPLER2D(s_occlusionMap, 6);
SAMPLER2D(s_emissiveMap, 7);
SAMPLER2D(s_lightmap, 8);
SAMPLER2D(s_lightmapDirection, 9);
SAMPLER2D(s_lightmapShadowmask, 10);
uniform vec4 u_lightmapTransform;
uniform vec4 u_lightmapDecode;

uniform vec4 u_camPos;
uniform vec4 u_sunDir;        // xyz: direction towards the sun, w: shadow strength
uniform vec4 u_sunColor;      // rgb premultiplied by intensity
uniform vec4 u_ambientSky;
uniform vec4 u_ambientGround;
uniform vec4 u_fogColor;      // rgb, a: density
uniform vec4 u_material;      // x metallic, y roughness, z flat shading, w unlit
uniform vec4 u_emissive;
uniform vec4 u_uvTransform;   // xy tiling, zw offset
uniform vec4 u_surface;       // x alpha cutoff (0: no cutout), y time in seconds, z 1 when the glow takes the surface's own colour
uniform vec4 u_params[8];     // a custom shader's own properties, in the order it declares them
uniform vec4 u_pbr;           // x normal map strength (0: none), y 1 with a metallic-roughness map, z occlusion strength (0: none), w 1 with an emissive map
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

// A custom shader (.tshader) is this file with its properties and its surface code put at the two markers below.
// The surface code may read uv, worldPosition, worldNormal, vertexColor and time, sample mainTexture, texture1 and
// texture2, and change albedo (already linear), alpha, metallic, roughness and emissive. Lighting, shadows and fog
// then apply to the result exactly as they do to the standard material.
#define mainTexture s_albedo
#define texture1 s_texture1
#define texture2 s_texture2
//@PROPERTIES

void main()
{
	vec2 uv = v_texcoord0 * u_uvTransform.xy + u_uvTransform.zw;
	vec3 worldPosition = v_wpos;
	vec3 worldNormal = normalize(v_normal);
	vec4 vertexColor = v_color0;
	float time = u_surface.y;
	vec4 tex = texture2D(s_albedo, uv);
	vec3 albedo = toLinear3(v_color0.rgb * tex.rgb);
	float alpha = v_color0.a * tex.a;
	float metallic = u_material.x;
	float roughness = u_material.y;
	float specularLevel = 1.0;
	// With "emissive from colour" the bright parts of a model glow in their own colour and its dark parts do not.
	vec3 emissive = u_emissive.rgb * mix(vec3_splat(1.0), albedo, u_surface.z);
//@SURFACE
	// The PBR maps, in the glTF layout: roughness in green and metallic in blue of one texture, occlusion in red.
	if (u_pbr.y > 0.5)
	{
		vec4 metalRough = texture2D(s_metalRoughMap, uv);
		roughness *= metalRough.g;
		metallic *= metalRough.b;
	}
	float occlusion = 1.0;
	if (u_pbr.z > 0.0)
	{
		occlusion = mix(1.0, texture2D(s_occlusionMap, uv).r, u_pbr.z);
	}
	if (u_pbr.w > 0.5)
	{
		emissive *= toLinear3(texture2D(s_emissiveMap, uv).rgb);
	}
	if (u_surface.x > 0.0 && alpha < u_surface.x - 0.00001)
	{
		discard;
	}

	if (u_material.w > 0.5)
	{
		gl_FragColor = vec4(albedo + emissive, alpha);
		return;
	}

	vec3 v = normalize(u_camPos.xyz - v_wpos);
	vec3 n;
	if (u_material.z > 0.5)
	{
		// Faceted low-poly look without duplicating vertices: derive the face normal.
		n = normalize(cross(dFdx(v_wpos), dFdy(v_wpos)));
		if (dot(n, v) < 0.0)
		{
			n = -n;
		}
	}
	else
	{
		n = normalize(v_normal);
	}

	if (u_pbr.x > 0.0)
	{
		// A normal map without tangents stored in the mesh: the surface's own directions are worked out from how
		// position and texture coordinates change across the pixel.
		vec3 mapped = texture2D(s_normalMap, uv).xyz * 2.0 - 1.0;
		mapped.xy *= u_pbr.x;
		vec3 dp1 = dFdx(v_wpos);
		vec3 dp2 = dFdy(v_wpos);
		vec2 duv1 = dFdx(uv);
		vec2 duv2 = dFdy(uv);
		vec3 dp2perp = cross(dp2, n);
		vec3 dp1perp = cross(n, dp1);
		vec3 tangent = dp2perp * duv1.x + dp1perp * duv2.x;
		vec3 bitangent = dp2perp * duv1.y + dp1perp * duv2.y;
		float scale = inversesqrt(max(max(dot(tangent, tangent), dot(bitangent, bitangent)), 1.0e-12));
		n = normalize(tangent * (scale * mapped.x) + bitangent * (scale * mapped.y) + n * mapped.z);
	}

	metallic = clamp(metallic, 0.0, 1.0);
	roughness = clamp(roughness, 0.045, 1.0);

	vec3 ambient = mix(u_ambientGround.rgb, u_ambientSky.rgb, n.y * 0.5 + 0.5);
	if (u_lightmapDecode.w > 0.5)
    {
        vec4 baked = texture2D(s_lightmap, v_texcoord1 * u_lightmapTransform.xy + u_lightmapTransform.zw);
        vec3 irradiance = u_lightmapDecode.z > 0.5 ? toLinear3(baked.rgb) : baked.rgb;
        ambient = irradiance * u_lightmapDecode.x * pow(max(baked.a, 0.0), u_lightmapDecode.y);
        if (mod(u_lightmapDecode.w - 1.0,2.0) > 0.5)
        {
            vec4 direction = texture2D(s_lightmapDirection, v_texcoord1 * u_lightmapTransform.xy + u_lightmapTransform.zw);
            ambient *= (dot(n, direction.xyz - vec3_splat(0.5)) + 0.5) / max(direction.w, 0.0001);
        }
    }
    vec3 color = ambient * albedo * (1.0 - metallic * 0.5) * occlusion;
	// What the surface mirrors of its surroundings: there is no environment map, so the sky and ground colours
	// stand in for one. It is what keeps a smooth metal from looking black where no light shines on it directly.
	vec3 mirrored = reflect(-v, n);
	vec3 surroundings = mix(u_ambientGround.rgb, u_ambientSky.rgb, clamp(mirrored.y * 0.5 + 0.5, 0.0, 1.0));
	vec3 f0 = mix(vec3_splat(0.04 * specularLevel), albedo, metallic);
	float grazing = pow(1.0 - max(dot(n, v), 0.0), 5.0);
	vec3 reflectance = f0 + (max(vec3_splat(1.0 - roughness), f0) - f0) * grazing;
	color += surroundings * reflectance * (1.0 - roughness * 0.75) * metallic * occlusion;

	vec4 bakedMask = vec4_splat(1.0);
    if (u_lightmapDecode.w > 2.5)
        bakedMask = texture2D(s_lightmapShadowmask, v_texcoord1 * u_lightmapTransform.xy + u_lightmapTransform.zw);
    float shadow = sunShadow(v_wpos, n, v_depth);
    if (u_lightCount.y > 0.5)
    {
        int channel = int(u_lightCount.y - 1.0);
        shadow = min(shadow,bakedMask[channel]);
    }
	color += brdf(n, v, u_sunDir.xyz, albedo, metallic, roughness, specularLevel) * u_sunColor.rgb * shadow * PI;

	for (int i = 0; i < MAX_LIGHTS; i++)
	{
		if (float(i) >= u_lightCount.x)
		{
			break;
		}
		if (u_lightParams[i].w > 0.5 && u_lightmapDecode.w > 0.5) continue;
		vec3 toLight = u_lightPosRange[i].xyz - v_wpos;
        float dist = length(toLight);
        float range = u_lightPosRange[i].w;
        bool directional = u_lightColor[i].w > 1.5;
        if (directional || dist < range)
        {
            vec3 l = directional ? -u_lightDirSpot[i].xyz : toLight / max(dist,1.0e-4);
            float falloff = clamp(1.0 - dist / max(range,1.0e-4),0.0,1.0);
            float atten = falloff * falloff / (1.0 + dist * dist * 0.1);
            if (u_lightParams[i].y > 0.5)
            {
                float ratio = dist * dist / max(range * range,1.0e-8);
                float fade = max(1.0 - ratio * ratio,0.0);
                atten = fade * fade / max(dist * dist,1.0e-6);
            }
            if (directional) atten = 1.0;
            else if (u_lightColor[i].w > 0.5)
            {
                float cosAngle = dot(-l,u_lightDirSpot[i].xyz);
                atten *= smoothstep(u_lightDirSpot[i].w,u_lightParams[i].x,cosAngle);
                atten *= spotShadow(i, v_wpos, n);
            }
            if (u_lightParams[i].z > 0.5) atten *= bakedMask[int(u_lightParams[i].z - 1.0)];
            color += brdf(n,v,l,albedo,metallic,roughness,specularLevel) * u_lightColor[i].rgb * atten * PI;
        }
	}

	color += emissive;

	float fogDistance = length(u_camPos.xyz - v_wpos);
	float fog = 1.0 - exp(-fogDistance * fogDistance * u_fogColor.a * u_fogColor.a);
	color = mix(color, u_fogColor.rgb, clamp(fog, 0.0, 1.0));

	gl_FragColor = vec4(color, alpha);
}
