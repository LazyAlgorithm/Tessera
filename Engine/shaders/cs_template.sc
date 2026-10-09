// The frame a compute shader (.tcompute) is put into. Its code runs once for every pixel of a texture and decides
// that pixel's new value. It may read: pixel (ivec2), size (ivec2), uv (vec2, 0 to 1), time, and the texture as it
// was before this step with previous(uv). It writes: result (vec4), which starts as the pixel's previous value.
#include "bgfx_compute.sh"

IMAGE2D_WO(s_target, @FORMAT, 0);
SAMPLER2D(s_previous, 1);

uniform vec4 u_surface;       // y time in seconds, z width, w height
uniform vec4 u_params[8];     // the shader's own properties, in the order it declares them
#define previous(coordinate) texture2DLod(s_previous, coordinate, 0.0)
//@PROPERTIES

NUM_THREADS(8, 8, 1)
void main()
{
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(int(u_surface.z), int(u_surface.w));
	if (pixel.x >= size.x || pixel.y >= size.y)
	{
		return;
	}
	vec2 uv = (vec2(pixel) + vec2_splat(0.5)) / vec2(size);
	float time = u_surface.y;
	vec4 result = previous(uv);
//@COMPUTE
	imageStore(s_target, pixel, result);
}
