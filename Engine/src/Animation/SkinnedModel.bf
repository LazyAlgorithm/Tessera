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

	/// One part of the model for each of its materials (a character's skin, cloth and armour): its triangles, as
	/// indices into the vertex lists above, and the material the file gives it.
	public class Part
	{
		/// The material's name in the file, or "Part 2" when it has none.
		public String name = new .() ~ delete _;
		public List<uint32> indices = new .() ~ delete _;
		/// Which of the file's materials it is (-1: the primitives that had none).
		public int32 fileMaterial;
		/// Made from the file: colour factor (in the vertex colours, so white here), metallic and roughness, and
		/// the base colour, normal, metallic-roughness, occlusion and emissive textures, alpha mode and double sides.
		public Material material ~ delete _;
	}
	public List<Part> Parts = new .() ~ DeleteContainerAndItems!(_);
	/// True when the parts are drawn with materials of their own: the file has more than one material, or any
	/// textures. Otherwise the model is one mesh drawn with its Mesh Renderer's settings, as before.
	public bool HasOwnMaterials;

	static Dictionary<String, SkinnedModel> sCache = new .() ~ DeleteDictionaryAndKeysAndValues!(_);

	/// A joint's pose in a clip at a time (seconds), in the model's own right-handed space, as the clip's frames give it.
	public void SampleJoint(Clip clip, float time, bool loop, int joint, out Vector3 position, out Quaternion rotation, out Vector3 scale)
	{
		let jointCount = Joints.Count;
		let t = loop ? (clip.duration > 0 ? time % clip.duration : 0) : Math.Min(time, clip.duration);
		let exact = t * 30.0f;
		let f0 = Math.Clamp((int)exact, 0, clip.frames - 1);
		let f1 = Math.Min(f0 + 1, clip.frames - 1);
		let blend = exact - f0;
		let a = clip.data.Ptr + (f0 * jointCount + joint) * 10;
		let b = clip.data.Ptr + (f1 * jointCount + joint) * 10;
		position = Vector3.Lerp(.(a[0], a[1], a[2]), .(b[0], b[1], b[2]), blend);
		rotation = Quaternion.Slerp(.(a[3], a[4], a[5], a[6]), .(b[3], b[4], b[5], b[6]), blend);
		scale = Vector3.Lerp(.(a[7], a[8], a[9]), .(b[7], b[8], b[9]), blend);
	}

	/// A joint's number by its name, or -1.
	public int FindJoint(StringView name)
	{
		for (int i < Joints.Count)
		{
			if (Joints[i].name == name)
				return i;
		}
		return -1;
	}

	public Clip FindClip(StringView name)
	{
		for (let clip in Clips)
		{
			if (clip.name == name)
				return clip;
		}
		return null;
	}

	/// An image found in a model, read on a loading thread and turned into a texture on the main thread.
	public class PendingImage
	{
		public String name = new .() ~ delete _;
		public uint8[] pixels ~ delete _;
		public int32 width, height;
	}

	/// True when the model is loaded already (Load returns it at once).
	public static bool IsLoaded(StringView path) => sCache.ContainsKeyAlt(path);

	/// Loads (and caches) a rigged model. Returns null when the file has no skeleton.
	public static SkinnedModel Load(StringView path)
	{
		if (sCache.TryGetValueAlt(path, let cached))
			return cached;
		let model = Build(path, null);
		if (model != null)
			sCache[new String(path)] = model;
		return model;
	}

	/// Takes a model read on a loading thread (Build) into the cache, making textures of its images. Returns the
	/// model now cached under that path (an earlier one if it was loaded meanwhile; the new one is then deleted).
	public static SkinnedModel Adopt(StringView path, SkinnedModel model, List<PendingImage> images)
	{
		for (let image in images)
			Assets.AddTexture(image.name, image.pixels.Ptr, image.width, image.height);
		if (sCache.TryGetValueAlt(path, let cached))
		{
			delete model;
			return cached;
		}
		if (model != null)
			sCache[new String(path)] = model;
		return model;
	}

	/// Reads a rigged model without touching the graphics card or the cache, so that it can run on a loading thread:
	/// with images given, the model's pictures are copied into it instead of being made into textures.
	public static SkinnedModel Build(StringView path, List<PendingImage> images)
	{
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
		// The file's images become textures named after it: "Models/hero.glb#image2".
		let imageNames = scope List<String>();
		defer { for (let name in imageNames) delete name; }
		for (int32 i < Native.tn_gltf_image_count(scene))
		{
			int32 width = 0, height = 0;
			let pixels = Native.tn_gltf_get_image(scene, i, &width, &height);
			let name = new String()..AppendF("{}#image{}", path, i);
			imageNames.Add(name);
			if (pixels != null && images != null)
			{
				let image = new PendingImage();
				image.name.Set(name);
				image.width = width;
				image.height = height;
				image.pixels = new uint8[width * height * 4];
				Internal.MemCpy(image.pixels.Ptr, pixels, width * height * 4);
				images.Add(image);
			}
			else if (pixels != null)
				Assets.AddTexture(name, pixels, width, height);
		}
		void Image(String into, int32 index)
		{
			into.Clear();
			if (index >= 0 && index < imageNames.Count)
				into.Set(imageNames[index]);
		}
		bool anyTexture = false;
		for (uint32 p < Native.tn_gltf_prim_count(scene))
		{
			let prim = Native.tn_gltf_get_prim(scene, p);
			if (prim.joints == null)
				continue;
			// The part for this primitive's material, made the first time it comes up.
			Part part = null;
			for (let existing in model.Parts)
			{
				if (existing.fileMaterial == prim.material)
					part = existing;
			}
			if (part == null)
			{
				part = new Part();
				part.fileMaterial = prim.material;
				part.name.Append(&prim.materialName);
				if (part.name.IsEmpty)
					part.name.AppendF("Part {}", model.Parts.Count + 1);
				let material = part.material = new Material();
				material.flatShading = false;
				material.metallic = prim.metallic;
				material.roughness = prim.roughness;
				material.emissive = Color(prim.emissive[0], prim.emissive[1], prim.emissive[2], 1);
				material.emissiveIntensity = (prim.emissive[0] + prim.emissive[1] + prim.emissive[2]) > 0 ? 1 : 0;
				Image(material.texture, prim.baseColorImage);
				Image(material.normalMap, prim.normalImage);
				material.normalStrength = prim.normalScale;
				Image(material.metallicRoughnessMap, prim.metalRoughImage);
				Image(material.occlusionMap, prim.occlusionImage);
				material.occlusionStrength = prim.occlusionStrength;
				Image(material.emissiveMap, prim.emissiveImage);
				if (!material.emissiveMap.IsEmpty)
					material.emissiveIntensity = 1;
				material.blend = prim.alphaMode == 1 ? .Cutout : (prim.alphaMode == 2 ? .Transparent : .Opaque);
				material.cutoff = prim.alphaCutoff;
				material.doubleSided = prim.doubleSided != 0;
				anyTexture |= !material.texture.IsEmpty || !material.normalMap.IsEmpty || !material.metallicRoughnessMap.IsEmpty || !material.occlusionMap.IsEmpty || !material.emissiveMap.IsEmpty;
				model.Parts.Add(part);
			}
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
				part.indices.Add(baseVertex + prim.indices[i]);
				part.indices.Add(baseVertex + prim.indices[i + 2]);
				part.indices.Add(baseVertex + prim.indices[i + 1]);
			}
		}
		model.HasOwnMaterials = model.Parts.Count > 1 || anyTexture;
		if (model.Positions.Count == 0)
		{
			delete model;
			return null;
		}
		return model;
	}
}
