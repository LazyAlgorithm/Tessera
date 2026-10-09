// Tessera asset decoding: images through stb_image, models through cgltf.
// The glTF loader flattens a file into world-space-ready primitives so the engine side
// only deals with plain vertex/index arrays.

#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_STDIO_WARNINGS
#include "stb_image.h"

#define CGLTF_IMPLEMENTATION
#include "cgltf.h"

#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "tessera_pack.h"

// ---- images ----

unsigned char* tn_image_load(const char* path, int* width, int* height)
{
	int channels = 0;
	// From an asset pack when the file is in one, else from disk.
	size_t size = 0;
	void* packed = tn_pack_read(path, &size);
	if (packed != NULL)
	{
		unsigned char* pixels = stbi_load_from_memory((const stbi_uc*)packed, (int)size, width, height, &channels, 4);
		tn_pack_free(packed);
		return pixels;
	}
	return stbi_load(path, width, height, &channels, 4);
}

void tn_image_free(unsigned char* pixels)
{
	stbi_image_free(pixels);
}

// ---- glTF ----

typedef struct tn_gltf_prim
{
	float* positions; // 3 per vertex
	float* normals;   // 3 per vertex, null when the file has none
	float* uvs;       // 2 per vertex, null when the file has none
	float* colors;    // 4 per vertex, null when the file has none
	uint32_t* indices;
	uint32_t vertexCount;
	uint32_t indexCount;
	float baseColor[4];
	float metallic;
	float roughness;
	float emissive[3];
	float world[16]; // column-major node transform
	char name[64];
	uint16_t* joints; // 4 per vertex, null unless the primitive is skinned
	float* weights;   // 4 per vertex
} tn_gltf_prim;

typedef struct tn_gltf_joint
{
	char name[64];
	int32_t parent;        // index into the joint list, -1 for a root
	float rest[10];        // translation 3, rotation 4 (xyzw), scale 3
	float inverseBind[16];
	float parentWorld[16]; // transform of whatever a root joint hangs from (the armature object)
} tn_gltf_joint;

typedef struct tn_gltf_anim
{
	char name[64];
	float duration;
	int32_t frames;  // sampled at 30 per second
	float* data;     // frames * jointCount * 10 floats, same layout as tn_gltf_joint.rest
} tn_gltf_anim;

typedef struct tn_gltf_scene
{
	tn_gltf_prim* prims;
	uint32_t primCount;
	tn_gltf_joint* joints;
	int32_t jointCount;
	tn_gltf_anim* anims;
	int32_t animCount;
} tn_gltf_scene;

static void tn_identity(float* m)
{
	memset(m, 0, sizeof(float) * 16);
	m[0] = m[5] = m[10] = m[15] = 1.0f;
}

static int tn_find_joint(const cgltf_skin* skin, const cgltf_node* node)
{
	for (cgltf_size i = 0; i < skin->joints_count; i++)
	{
		if (skin->joints[i] == node) return (int)i;
	}
	return -1;
}

// Samples one animation channel at a time into out (3 or 4 floats).
static void tn_sample_channel(const cgltf_animation_sampler* sampler, float time, int components, float* out)
{
	const cgltf_size count = sampler->input->count;
	const int cubic = sampler->interpolation == cgltf_interpolation_type_cubic_spline;
	cgltf_size k = 0;
	float t0 = 0.0f, t1 = 0.0f;
	for (cgltf_size i = 0; i < count; i++)
	{
		float t = 0.0f;
		cgltf_accessor_read_float(sampler->input, i, &t, 1);
		if (t > time) break;
		k = i;
		t0 = t;
	}
	// Cubic spline outputs store in-tangent, value, out-tangent per key; the value is enough here.
	float a[4] = { 0, 0, 0, 1 }, b[4] = { 0, 0, 0, 1 };
	cgltf_accessor_read_float(sampler->output, cubic ? k * 3 + 1 : k, a, (cgltf_size)components);
	if (k + 1 >= count || sampler->interpolation == cgltf_interpolation_type_step)
	{
		memcpy(out, a, sizeof(float) * (size_t)components);
		return;
	}
	cgltf_accessor_read_float(sampler->input, k + 1, &t1, 1);
	cgltf_accessor_read_float(sampler->output, cubic ? (k + 1) * 3 + 1 : k + 1, b, (cgltf_size)components);
	float f = t1 > t0 ? (time - t0) / (t1 - t0) : 0.0f;
	if (f < 0.0f) f = 0.0f;
	if (f > 1.0f) f = 1.0f;
	if (components == 4)
	{
		// Shortest-path blend of rotations, renormalised.
		float dot = a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3];
		float sign = dot < 0.0f ? -1.0f : 1.0f;
		float len = 0.0f;
		for (int i = 0; i < 4; i++) { out[i] = a[i] + (b[i] * sign - a[i]) * f; len += out[i] * out[i]; }
		len = len > 0.0f ? 1.0f / (float)sqrt(len) : 1.0f;
		for (int i = 0; i < 4; i++) out[i] *= len;
	}
	else
	{
		for (int i = 0; i < components; i++) out[i] = a[i] + (b[i] - a[i]) * f;
	}
}

static void tn_load_skin(tn_gltf_scene* scene, const cgltf_data* data)
{
	if (data->skins_count == 0) return;
	const cgltf_skin* skin = &data->skins[0];
	scene->jointCount = (int32_t)skin->joints_count;
	scene->joints = (tn_gltf_joint*)calloc((size_t)scene->jointCount, sizeof(tn_gltf_joint));
	for (int j = 0; j < scene->jointCount; j++)
	{
		const cgltf_node* node = skin->joints[j];
		tn_gltf_joint* joint = &scene->joints[j];
		strncpy(joint->name, node->name != NULL ? node->name : "Bone", sizeof(joint->name) - 1);
		joint->parent = node->parent != NULL ? tn_find_joint(skin, node->parent) : -1;
		float rest[10] = { 0, 0, 0, 0, 0, 0, 1, 1, 1, 1 };
		if (node->has_translation) memcpy(rest, node->translation, sizeof(float) * 3);
		if (node->has_rotation) memcpy(rest + 3, node->rotation, sizeof(float) * 4);
		if (node->has_scale) memcpy(rest + 7, node->scale, sizeof(float) * 3);
		memcpy(joint->rest, rest, sizeof(rest));
		tn_identity(joint->inverseBind);
		if (skin->inverse_bind_matrices != NULL)
			cgltf_accessor_read_float(skin->inverse_bind_matrices, (cgltf_size)j, joint->inverseBind, 16);
		tn_identity(joint->parentWorld);
		if (joint->parent < 0 && node->parent != NULL)
			cgltf_node_transform_world(node->parent, joint->parentWorld);
	}

	scene->animCount = (int32_t)data->animations_count;
	scene->anims = (tn_gltf_anim*)calloc(scene->animCount > 0 ? (size_t)scene->animCount : 1, sizeof(tn_gltf_anim));
	for (int a = 0; a < scene->animCount; a++)
	{
		const cgltf_animation* source = &data->animations[a];
		tn_gltf_anim* anim = &scene->anims[a];
		strncpy(anim->name, source->name != NULL ? source->name : "Animation", sizeof(anim->name) - 1);
		float duration = 0.0f;
		for (cgltf_size c = 0; c < source->channels_count; c++)
		{
			const cgltf_accessor* input = source->channels[c].sampler->input;
			float last = 0.0f;
			if (input->count > 0) cgltf_accessor_read_float(input, input->count - 1, &last, 1);
			if (last > duration) duration = last;
		}
		anim->duration = duration > 0.0f ? duration : 0.001f;
		anim->frames = (int32_t)(anim->duration * 30.0f) + 2;
		const size_t stride = (size_t)scene->jointCount * 10;
		anim->data = (float*)malloc(sizeof(float) * stride * (size_t)anim->frames);
		for (int f = 0; f < anim->frames; f++)
		{
			float* frame = anim->data + stride * (size_t)f;
			for (int j = 0; j < scene->jointCount; j++) memcpy(frame + j * 10, scene->joints[j].rest, sizeof(float) * 10);
			float time = (float)f / 30.0f;
			if (time > anim->duration) time = anim->duration;
			for (cgltf_size c = 0; c < source->channels_count; c++)
			{
				const cgltf_animation_channel* channel = &source->channels[c];
				int j = channel->target_node != NULL ? tn_find_joint(skin, channel->target_node) : -1;
				if (j < 0) continue;
				if (channel->target_path == cgltf_animation_path_type_translation) tn_sample_channel(channel->sampler, time, 3, frame + j * 10);
				else if (channel->target_path == cgltf_animation_path_type_rotation) tn_sample_channel(channel->sampler, time, 4, frame + j * 10 + 3);
				else if (channel->target_path == cgltf_animation_path_type_scale) tn_sample_channel(channel->sampler, time, 3, frame + j * 10 + 7);
			}
		}
	}
}

static float* tn_read_floats(const cgltf_accessor* accessor, int components)
{
	float* out = (float*)malloc(sizeof(float) * (size_t)components * accessor->count);
	for (cgltf_size i = 0; i < accessor->count; i++)
	{
		float value[4] = { 0.0f, 0.0f, 0.0f, 1.0f };
		cgltf_accessor_read_float(accessor, i, value, 4);
		memcpy(out + i * (size_t)components, value, sizeof(float) * (size_t)components);
	}
	return out;
}

// cgltf reads the model, and any buffer or image files it names, through these: from an asset pack when the file
// is in one, else from disk.
static cgltf_result pack_or_file_read(const struct cgltf_memory_options* memory, const struct cgltf_file_options* file, const char* path, cgltf_size* size, void** data)
{
	size_t length = 0;
	void* packed = tn_pack_read(path, &length);
	if (packed != NULL)
	{
		*size = (cgltf_size)length;
		*data = packed;
		return cgltf_result_success;
	}
	if (tn_pack_exists(path)) return cgltf_result_io_error;   // in a pack, but damaged
	FILE* handle = fopen(path, "rb");
	if (handle == NULL) return cgltf_result_file_not_found;
	fseek(handle, 0, SEEK_END);
	long total = ftell(handle);
	fseek(handle, 0, SEEK_SET);
	void* bytes = total >= 0 ? malloc((size_t)total + 1) : NULL;
	if (bytes == NULL || fread(bytes, 1, (size_t)total, handle) != (size_t)total)
	{
		free(bytes);
		fclose(handle);
		return cgltf_result_io_error;
	}
	fclose(handle);
	*size = (cgltf_size)total;
	*data = bytes;
	return cgltf_result_success;
}

static void pack_or_file_release(const struct cgltf_memory_options* memory, const struct cgltf_file_options* file, void* data, cgltf_size size)
{
	free(data);
}

tn_gltf_scene* tn_gltf_load(const char* path)
{
	cgltf_options options;
	memset(&options, 0, sizeof(options));
	options.file.read = pack_or_file_read;
	options.file.release = pack_or_file_release;
	cgltf_data* data = NULL;
	if (cgltf_parse_file(&options, path, &data) != cgltf_result_success) return NULL;
	if (cgltf_load_buffers(&options, data, path) != cgltf_result_success)
	{
		cgltf_free(data);
		return NULL;
	}

	uint32_t total = 0;
	for (cgltf_size n = 0; n < data->nodes_count; n++)
	{
		if (data->nodes[n].mesh != NULL) total += (uint32_t)data->nodes[n].mesh->primitives_count;
	}

	tn_gltf_scene* scene = (tn_gltf_scene*)calloc(1, sizeof(tn_gltf_scene));
	scene->prims = (tn_gltf_prim*)calloc(total > 0 ? total : 1, sizeof(tn_gltf_prim));

	for (cgltf_size n = 0; n < data->nodes_count; n++)
	{
		const cgltf_node* node = &data->nodes[n];
		if (node->mesh == NULL) continue;
		for (cgltf_size p = 0; p < node->mesh->primitives_count; p++)
		{
			const cgltf_primitive* src = &node->mesh->primitives[p];
			if (src->type != cgltf_primitive_type_triangles) continue;

			const cgltf_accessor* position = NULL;
			const cgltf_accessor* normal = NULL;
			const cgltf_accessor* uv = NULL;
			const cgltf_accessor* color = NULL;
			const cgltf_accessor* joints = NULL;
			const cgltf_accessor* weights = NULL;
			for (cgltf_size a = 0; a < src->attributes_count; a++)
			{
				const cgltf_attribute* attribute = &src->attributes[a];
				if (attribute->type == cgltf_attribute_type_position) position = attribute->data;
				else if (attribute->type == cgltf_attribute_type_normal) normal = attribute->data;
				else if (attribute->type == cgltf_attribute_type_texcoord && attribute->index == 0) uv = attribute->data;
				else if (attribute->type == cgltf_attribute_type_color && attribute->index == 0) color = attribute->data;
				else if (attribute->type == cgltf_attribute_type_joints && attribute->index == 0) joints = attribute->data;
				else if (attribute->type == cgltf_attribute_type_weights && attribute->index == 0) weights = attribute->data;
			}
			if (position == NULL) continue;

			tn_gltf_prim* dst = &scene->prims[scene->primCount++];
			dst->vertexCount = (uint32_t)position->count;
			dst->positions = tn_read_floats(position, 3);
			if (normal != NULL) dst->normals = tn_read_floats(normal, 3);
			if (uv != NULL) dst->uvs = tn_read_floats(uv, 2);
			if (color != NULL) dst->colors = tn_read_floats(color, 4);
			if (node->skin != NULL && joints != NULL && weights != NULL)
			{
				dst->weights = tn_read_floats(weights, 4);
				dst->joints = (uint16_t*)malloc(sizeof(uint16_t) * 4 * joints->count);
				for (cgltf_size i = 0; i < joints->count; i++)
				{
					cgltf_uint index[4] = { 0, 0, 0, 0 };
					cgltf_accessor_read_uint(joints, i, index, 4);
					for (int k = 0; k < 4; k++) dst->joints[i * 4 + k] = (uint16_t)index[k];
				}
			}

			if (src->indices != NULL)
			{
				dst->indexCount = (uint32_t)src->indices->count;
				dst->indices = (uint32_t*)malloc(sizeof(uint32_t) * dst->indexCount);
				for (cgltf_size i = 0; i < src->indices->count; i++)
				{
					dst->indices[i] = (uint32_t)cgltf_accessor_read_index(src->indices, i);
				}
			}
			else
			{
				dst->indexCount = dst->vertexCount;
				dst->indices = (uint32_t*)malloc(sizeof(uint32_t) * dst->indexCount);
				for (uint32_t i = 0; i < dst->indexCount; i++) dst->indices[i] = i;
			}

			dst->baseColor[0] = dst->baseColor[1] = dst->baseColor[2] = dst->baseColor[3] = 1.0f;
			dst->metallic = 0.0f;
			dst->roughness = 1.0f;
			if (src->material != NULL)
			{
				if (src->material->has_pbr_metallic_roughness)
				{
					memcpy(dst->baseColor, src->material->pbr_metallic_roughness.base_color_factor, sizeof(float) * 4);
					dst->metallic = src->material->pbr_metallic_roughness.metallic_factor;
					dst->roughness = src->material->pbr_metallic_roughness.roughness_factor;
				}
				memcpy(dst->emissive, src->material->emissive_factor, sizeof(float) * 3);
			}

			// A skinned mesh is placed by its bones; the node's own transform does not apply.
			if (dst->joints != NULL) tn_identity(dst->world);
			else cgltf_node_transform_world(node, dst->world);
			const char* name = node->name != NULL ? node->name : (node->mesh->name != NULL ? node->mesh->name : "Mesh");
			strncpy(dst->name, name, sizeof(dst->name) - 1);
		}
	}

	tn_load_skin(scene, data);
	cgltf_free(data);
	return scene;
}

int32_t tn_gltf_joint_count(const tn_gltf_scene* scene) { return scene != NULL ? scene->jointCount : 0; }
const tn_gltf_joint* tn_gltf_get_joint(const tn_gltf_scene* scene, int32_t index) { return &scene->joints[index]; }
int32_t tn_gltf_anim_count(const tn_gltf_scene* scene) { return scene != NULL ? scene->animCount : 0; }
const tn_gltf_anim* tn_gltf_get_anim(const tn_gltf_scene* scene, int32_t index) { return &scene->anims[index]; }

uint32_t tn_gltf_prim_count(const tn_gltf_scene* scene)
{
	return scene != NULL ? scene->primCount : 0;
}

const tn_gltf_prim* tn_gltf_get_prim(const tn_gltf_scene* scene, uint32_t index)
{
	return &scene->prims[index];
}

void tn_gltf_free(tn_gltf_scene* scene)
{
	if (scene == NULL) return;
	for (uint32_t i = 0; i < scene->primCount; i++)
	{
		free(scene->prims[i].positions);
		free(scene->prims[i].normals);
		free(scene->prims[i].uvs);
		free(scene->prims[i].colors);
		free(scene->prims[i].indices);
		free(scene->prims[i].joints);
		free(scene->prims[i].weights);
	}
	for (int32_t i = 0; i < scene->animCount; i++) free(scene->anims[i].data);
	free(scene->anims);
	free(scene->joints);
	free(scene->prims);
	free(scene);
}
