using System;
using System.Collections;

namespace Tessera;

/// Draws a rigged model and plays its animation clips, bending the mesh with its skeleton.
/// Export from Blender as glTF 2.0 (.glb) with the armature, mesh and animations included.
///
/// Materials: a model with several materials, or any textures, is drawn in parts, one per material, each with the
/// material saved in the file (its textures included) unless the part is given a .tmat of its own (the Inspector
/// lists the parts; SetPartMaterial from code). A material on the Mesh Renderer covers every part that has none of
/// its own. A model with one plain material is one mesh drawn with the Mesh Renderer's settings, as before.
/// See docs/skinned-materials.md.
[Component]
class SkinnedMeshRenderer : Component
{
	/// Rigged .glb / .gltf file relative to the project's asset folder.
	public String model = new .() ~ delete _;
	/// Clip to start with; empty plays the first clip in the file.
	public String clip = new .() ~ delete _;
	public float speed = 1.0f;
	public bool loop = true;
	/// The parts' own materials, "Part=Materials/skin.tmat;Other=..." (the Inspector edits it as a list).
	[HideInInspector]
	public String materials = new .() ~ delete _;

	SkinnedModel mModel;
	String mLoadedPath = new .() ~ delete _;
	Mesh mMesh ~ delete _;
	// One per part of a model with materials of its own (SkinnedModel.Parts), sharing mMesh's vertices.
	List<MeshRenderer.Part> mParts = new .() ~ { for (let part in _) delete part.mesh; DeleteContainerAndItems!(_); };
	String mResolvedMaterials = new .() ~ delete _;
	int32 mResolvedRendererMaterial = -1;
	SkinnedModel.Clip mCurrent;
	SkinnedModel.Clip mPrevious;
	float mTime;
	float mPreviousTime;
	float mFade;
	float mFadeDuration;
	Matrix4[] mWorld ~ delete _;
	Matrix4[] mSkin ~ delete _;
	bool[] mDone ~ delete _;
	bool mAttachPending;

	public StringView CurrentClip => mCurrent != null ? (StringView)mCurrent.name : "";
	public SkinnedModel Model => mModel;

	public override void OnRegister() => Reload();
	public override void OnValidate() => Reload();

	public override void OnUnregister()
	{
		let renderer = GetComponent<MeshRenderer>();
		if (renderer != null && renderer.RuntimeMesh == mMesh)
			renderer.RuntimeMesh = null;
		if (renderer != null && renderer.RuntimeParts == mParts)
			renderer.RuntimeParts = null;
	}

	/// The model's parts (one per material) when it is drawn in parts, else none: their names are the model's
	/// material names.
	public int PartCount => (mModel != null && mModel.HasOwnMaterials) ? mModel.Parts.Count : 0;
	public StringView PartName(int index) => (index >= 0 && index < PartCount) ? (StringView)mModel.Parts[index].name : "";

	/// The .tmat a part is drawn with instead of the model's own material, or empty.
	public void GetPartMaterial(StringView part, String path)
	{
		path.Clear();
		for (var entry in materials.Split(';'))
		{
			let equals = entry.IndexOf('=');
			if (equals > 0 && entry.Substring(0, equals) == part)
			{
				path.Append(entry.Substring(equals + 1));
				return;
			}
		}
	}

	/// Gives a part a .tmat of its own (empty: back to the model's own material). In a network session, on the server
	/// or on the owner's machine, every machine follows.
	public void SetPartMaterial(int index, StringView path)
	{
		let part = PartName(index);
		if (part.IsEmpty || path.Contains(';') || path.Contains('='))
			return;
		let current = scope String();
		GetPartMaterial(part, current);
		if (current == path)
			return;
		let rebuilt = scope String();
		for (var entry in materials.Split(';'))
		{
			let equals = entry.IndexOf('=');
			if (entry.IsEmpty || (equals > 0 && entry.Substring(0, equals) == part))
				continue;
			rebuilt.AppendF("{}{}", rebuilt.IsEmpty ? "" : ";", entry);
		}
		if (!path.IsEmpty)
			rebuilt.AppendF("{}{}={}", rebuilt.IsEmpty ? "" : ";", part, path);
		materials.Set(rebuilt);
		let renderer = GetComponent<MeshRenderer>();
		if (renderer != null)
			NetworkSync.MaterialChanged(renderer, 2, path, .(index, 0, 0, 0));
	}

	/// Which material each part draws with: its own .tmat, else the Mesh Renderer's material, else the model's.
	void ResolvePartMaterials(MeshRenderer renderer)
	{
		let rendererMaterial = renderer.ActiveMaterial;
		let rendererKey = rendererMaterial != null ? (int32)(int)Internal.UnsafeCastToPtr(rendererMaterial) ^ rendererMaterial.Revision : 0;
		if (mResolvedMaterials == materials && mResolvedRendererMaterial == rendererKey)
			return;
		mResolvedMaterials.Set(materials);
		mResolvedRendererMaterial = rendererKey;
		let path = scope String();
		for (int i < mParts.Count)
		{
			GetPartMaterial(mModel.Parts[i].name, path);
			let own = path.IsEmpty ? null : Material.Load(path);
			mParts[i].material = own ?? rendererMaterial ?? mModel.Parts[i].material;
		}
	}

	void Reload()
	{
		if (model.IsEmpty || mLoadedPath == model)
		{
			if (mModel != null && !clip.IsEmpty && CurrentClip != clip)
				Play(clip, 0.2f);
			return;
		}
		mLoadedPath.Set(model);
		mModel = SkinnedModel.Load(model);
		mCurrent = null;
		mPrevious = null;
		if (mModel == null)
		{
			Log.Warning(scope $"'{model}' has no skeleton (or could not be read). Use a Mesh Renderer for unrigged models.");
			return;
		}
		delete mWorld;
		delete mSkin;
		delete mDone;
		mWorld = new Matrix4[mModel.Joints.Count];
		mSkin = new Matrix4[mModel.Joints.Count];
		mDone = new bool[mModel.Joints.Count];
		if (mMesh == null)
			mMesh = new Mesh();
		mMesh.Clear();
		for (int i < mModel.Positions.Count)
		{
			let p = mModel.Positions[i];
			let n = mModel.Normals[i];
			mMesh.Vertices.Add(.(.(p.x, p.y, -p.z), .(n.x, n.y, -n.z), mModel.Colors[i], mModel.UVs[i]));
		}
		mMesh.Indices.AddRange(mModel.Indices);
		mMesh.UploadDynamic();
		// A model with materials of its own is drawn in parts, sharing the vertices.
		for (let part in mParts)
			delete part.mesh;
		ClearAndDeleteItems!(mParts);
		if (mModel.HasOwnMaterials)
		{
			for (let source in mModel.Parts)
			{
				let part = new MeshRenderer.Part();
				part.mesh = new Mesh();
				part.mesh.VertexSource = mMesh;
				part.mesh.Indices.AddRange(source.indices);
				part.mesh.UploadIndices();
				part.material = source.material;
				mParts.Add(part);
			}
		}
		mResolvedMaterials.Set("\n");
		mAttachPending = true;
		if (!clip.IsEmpty)
			Play(clip, 0);
		else if (mModel.Clips.Count > 0)
			Play(mModel.Clips[0].name, 0);
	}

	public bool HasClip(StringView name) => mModel != null && mModel.FindClip(name) != null;

	/// Switches clips with a cross-fade. Does nothing if that clip is already playing.
	public void Play(StringView name, float fadeSeconds = 0.15f)
	{
		if (mModel == null || (mCurrent != null && mCurrent.name == name))
			return;
		let next = mModel.FindClip(name);
		if (next == null)
			return;
		mPrevious = mCurrent;
		mPreviousTime = mTime;
		mCurrent = next;
		mTime = 0;
		mFade = 0;
		mFadeDuration = mPrevious != null ? fadeSeconds : 0;
		// In multiplayer a clip started by the server, or by the player who controls this object, plays everywhere.
		NetworkSync.AnimationPlayed(this, name, fadeSeconds);
	}

	void SamplePose(SkinnedModel.Clip source, float time, int joint, out Vector3 position, out Quaternion rotation, out Vector3 scale)
	{
		let jointCount = mModel.Joints.Count;
		var t = loop ? time % source.duration : Math.Min(time, source.duration);
		let exact = t * 30.0f;
		let f0 = Math.Min((int)exact, source.frames - 1);
		let f1 = Math.Min(f0 + 1, source.frames - 1);
		let blend = exact - f0;
		let a = source.data.Ptr + (f0 * jointCount + joint) * 10;
		let b = source.data.Ptr + (f1 * jointCount + joint) * 10;
		position = Vector3.Lerp(.(a[0], a[1], a[2]), .(b[0], b[1], b[2]), blend);
		rotation = Quaternion.Slerp(.(a[3], a[4], a[5], a[6]), .(b[3], b[4], b[5], b[6]), blend);
		scale = Vector3.Lerp(.(a[7], a[8], a[9]), .(b[7], b[8], b[9]), blend);
	}

	void ComputeJoint(int index, float weight)
	{
		if (mDone[index])
			return;
		let joint = mModel.Joints[index];
		var position = joint.restPosition;
		var rotation = joint.restRotation;
		var scale = joint.restScale;
		if (mCurrent != null)
		{
			SamplePose(mCurrent, mTime, index, out position, out rotation, out scale);
			if (weight < 1.0f && mPrevious != null)
			{
				Vector3 fromPosition, fromScale;
				Quaternion fromRotation;
				SamplePose(mPrevious, mPreviousTime, index, out fromPosition, out fromRotation, out fromScale);
				position = Vector3.Lerp(fromPosition, position, weight);
				rotation = Quaternion.Slerp(fromRotation, rotation, weight);
				scale = Vector3.Lerp(fromScale, scale, weight);
			}
		}
		let local = Matrix4.TRS(position, rotation, scale);
		if (joint.parent >= 0)
		{
			ComputeJoint(joint.parent, weight);
			mWorld[index] = mWorld[joint.parent] * local;
		}
		else
			mWorld[index] = joint.parentWorld * local;
		mSkin[index] = mWorld[index] * joint.inverseBind;
		mDone[index] = true;
	}

	/// Animates and re-skins every frame, in the editor as well as in play mode.
	public override void OnFrame()
	{
		if (mModel == null || mMesh == null)
			return;
		if (mAttachPending)
		{
			mAttachPending = false;
			var renderer = GetComponent<MeshRenderer>();
			if (renderer == null)
				renderer = GameObject.AddComponent<MeshRenderer>();
			renderer.RuntimeMesh = mMesh;
			renderer.RuntimeParts = mParts.Count > 0 ? mParts : null;
		}
		if (mParts.Count > 0)
		{
			let renderer = GetComponent<MeshRenderer>();
			if (renderer != null)
				ResolvePartMaterials(renderer);
		}
		let step = Time.DeltaTime * speed;
		mTime += step;
		mPreviousTime += step;
		mFade += Time.DeltaTime;
		let weight = (mPrevious != null && mFade < mFadeDuration) ? Mathf.SmoothStep(0, 1, mFade / mFadeDuration) : 1.0f;

		for (int i < mDone.Count)
			mDone[i] = false;
		for (int i < mModel.Joints.Count)
			ComputeJoint(i, weight);

		let positions = mModel.Positions;
		let normals = mModel.Normals;
		let joints = mModel.JointIndices.Ptr;
		let weights = mModel.Weights.Ptr;
		var bounds = Bounds.Empty;
		for (int v < positions.Count)
		{
			let p = positions[v];
			let n = normals[v];
			Vector3 skinned = .Zero;
			Vector3 normal = .Zero;
			for (int k < 4)
			{
				let w = weights[v * 4 + k];
				if (w <= 0)
					continue;
				let matrix = mSkin[joints[v * 4 + k]];
				skinned = skinned + matrix.TransformPoint(p) * w;
				normal = normal + matrix.TransformDirection(n) * w;
			}
			// Into Tessera's left-handed space.
			let outPosition = Vector3(skinned.x, skinned.y, -skinned.z);
			mMesh.Vertices[v].position = outPosition;
			mMesh.Vertices[v].normal = Vector3(normal.x, normal.y, -normal.z).Normalized;
			bounds.Encapsulate(outPosition);
		}
		mMesh.Bounds = bounds;
		mMesh.UpdateDynamic();
		for (let part in mParts)
			part.mesh.Bounds = bounds;
	}
}
