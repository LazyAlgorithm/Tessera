using System;
using System.Collections;

namespace Tessera;

/// A rigged model loaded from glTF / GLB: bind-pose vertices with bone weights, the skeleton,
/// and its animation clips (sampled at 30 frames per second on import).
class SkinnedModel
{
	public struct Joint
	{
		public String name;
		public int32 parent;
		public Vector3 restPosition;
		public Quaternion restRotation;
		public Vector3 restScale;
		public Matrix4 inverseBind;
		public Matrix4 parentWorld;
	}

	public class Clip
	{
		public String name = new .() ~ delete _;
		public float duration;
		public int32 frames;
		public float[] data ~ delete _; // frames * joints * 10
	}

	public List<Joint> Joints = new .() ~ { for (let j in _) delete j.name; delete _; };
	public List<Clip> Clips = new .() ~ DeleteContainerAndItems!(_);
	// Bind pose in the file's own (right-handed) space; Z is flipped after skinning.
	public List<Vector3> Positions = new .() ~ delete _;
	public List<Vector3> Normals = new .() ~ delete _;
	public List<uint32> Colors = new .() ~ delete _;
	public List<Vector2> UVs = new .() ~ delete _;
	public List<uint16> JointIndices = new .() ~ delete _; // 4 per vertex
	public List<float> Weights = new .() ~ delete _;       // 4 per vertex
	public List<uint32> Indices = new .() ~ delete _;

	static Dictionary<String, SkinnedModel> sCache = new .() ~ DeleteDictionaryAndKeysAndValues!(_);

	public Clip FindClip(StringView name)
	{
		for (let clip in Clips)
		{
			if (clip.name == name)
				return clip;
		}
		return null;
	}

	/// Loads (and caches) a rigged model. Returns null when the file has no skeleton.
	public static SkinnedModel Load(StringView path)
	{
		if (sCache.TryGetValueAlt(path, let cached))
			return cached;
		let full = scope String();
		Assets.ResolvePath(path, full);
		let scene = Native.tn_gltf_load(full.CStr());
		if (scene == null)
			return null;
		defer Native.tn_gltf_free(scene);
		let jointCount = Native.tn_gltf_joint_count(scene);
		if (jointCount == 0)
			return null;

		let model = new SkinnedModel();
		for (int32 j < jointCount)
		{
			let source = Native.tn_gltf_get_joint(scene, j);
			Joint joint;
			joint.name = new String(&source.name);
			joint.parent = source.parent;
			joint.restPosition = .(source.rest[0], source.rest[1], source.rest[2]);
			joint.restRotation = .(source.rest[3], source.rest[4], source.rest[5], source.rest[6]);
			joint.restScale = .(source.rest[7], source.rest[8], source.rest[9]);
			joint.inverseBind = default;
			joint.parentWorld = default;
			for (int i < 16)
			{
				joint.inverseBind.m[i] = source.inverseBind[i];
				joint.parentWorld.m[i] = source.parentWorld[i];
			}
			model.Joints.Add(joint);
		}
		for (int32 a < Native.tn_gltf_anim_count(scene))
		{
			let source = Native.tn_gltf_get_anim(scene, a);
			let clip = new Clip();
			clip.name.Append(&source.name);
			clip.duration = source.duration;
			clip.frames = source.frames;
			let count = source.frames * jointCount * 10;
			clip.data = new float[count];
			Internal.MemCpy(clip.data.Ptr, source.data, count * sizeof(float));
			model.Clips.Add(clip);
		}
		for (uint32 p < Native.tn_gltf_prim_count(scene))
		{
			let prim = Native.tn_gltf_get_prim(scene, p);
			if (prim.joints == null)
				continue;
			let baseVertex = (uint32)model.Positions.Count;
			let baseColor = Color(prim.baseColor[0], prim.baseColor[1], prim.baseColor[2], prim.baseColor[3]);
			for (uint32 v < prim.vertexCount)
			{
				model.Positions.Add(.(prim.positions[v * 3], prim.positions[v * 3 + 1], prim.positions[v * 3 + 2]));
				model.Normals.Add(prim.normals != null ? Vector3(prim.normals[v * 3], prim.normals[v * 3 + 1], prim.normals[v * 3 + 2]) : Vector3.Up);
				var color = baseColor;
				if (prim.colors != null)
				{
					color.r *= prim.colors[v * 4];
					color.g *= prim.colors[v * 4 + 1];
					color.b *= prim.colors[v * 4 + 2];
				}
				// glTF stores linear color; the shader expects sRGB-encoded vertex colors.
				model.Colors.Add(Color(Math.Pow(color.r, 1.0f / 2.2f), Math.Pow(color.g, 1.0f / 2.2f), Math.Pow(color.b, 1.0f / 2.2f), color.a).ToABGR());
				model.UVs.Add(prim.uvs != null ? Vector2(prim.uvs[v * 2], prim.uvs[v * 2 + 1]) : default);
				float total = 0;
				for (int k < 4)
					total += prim.weights[v * 4 + (uint32)k];
				for (int k < 4)
				{
					model.JointIndices.Add((uint16)Math.Min((int32)prim.joints[v * 4 + (uint32)k], jointCount - 1));
					model.Weights.Add(total > 0 ? prim.weights[v * 4 + (uint32)k] / total : (k == 0 ? 1.0f : 0.0f));
				}
			}
			// Mirroring Z on output turns triangles inside out, so swap two corners.
			for (uint32 i = 0; i + 2 < prim.indexCount; i += 3)
			{
				model.Indices.Add(baseVertex + prim.indices[i]);
				model.Indices.Add(baseVertex + prim.indices[i + 2]);
				model.Indices.Add(baseVertex + prim.indices[i + 1]);
			}
		}
		if (model.Positions.Count == 0)
		{
			delete model;
			return null;
		}
		sCache[new String(path)] = model;
		return model;
	}
}
