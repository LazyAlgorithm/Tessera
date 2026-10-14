// Shared by the screen effects that read the depth pass (fs_ao, fs_ao_apply, fs_dof*, fs_motion_blur).
//
// The depth texture holds each pixel's distance in front of the camera in metres (view-space depth), a very large
// number where nothing was drawn (the sky), and -1 on the first-person viewmodel (Camera.viewmodelLayer), which the
// effects leave alone.

uniform vec4 u_postRight;   // xyz: the camera's right in the world, w: 1 / projection[0] (tan of half the width's angle, or half the width when orthographic)
uniform vec4 u_postUp;      // xyz: up, w: 1 / projection[5]
uniform vec4 u_postForward; // xyz: forward, w: 1 when orthographic
uniform vec4 u_postEye;     // xyz: the camera's position, w: +1 when texture v grows up the screen, -1 when down

#define SKY_DEPTH 60000.0

vec2 uvToNdc(vec2 uv)
{
	return vec2(uv.x * 2.0 - 1.0, (uv.y * 2.0 - 1.0) * u_postEye.w);
}

vec2 ndcToUv(vec2 ndc)
{
	return vec2(ndc.x * 0.5 + 0.5, ndc.y * u_postEye.w * 0.5 + 0.5);
}

// Where the surface at uv is, relative to the camera: x right, y up, z forward (metres).
vec3 viewPosition(vec2 uv, float depth)
{
	vec2 ndc = uvToNdc(uv);
	float s = u_postForward.w > 0.5 ? 1.0 : depth;
	return vec3(ndc.x * u_postRight.w * s, ndc.y * u_postUp.w * s, depth);
}

// The screen position of a point relative to the camera.
vec2 viewToUv(vec3 p)
{
	float s = u_postForward.w > 0.5 ? 1.0 : max(p.z, 0.0001);
	return ndcToUv(vec2(p.x / (u_postRight.w * s), p.y / (u_postUp.w * s)));
}

vec3 worldPosition(vec2 uv, float depth)
{
	vec3 v = viewPosition(uv, depth);
	return u_postEye.xyz + u_postRight.xyz * v.x + u_postUp.xyz * v.y + u_postForward.xyz * v.z;
}

bool isViewmodel(float depth) { return depth < 0.0; }
bool isSky(float depth) { return depth > SKY_DEPTH * 0.5; }
