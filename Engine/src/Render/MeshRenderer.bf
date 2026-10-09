using System;
using System.Collections;
using Bgfx;

namespace Tessera;

/// Draws a mesh with an inline material. Identical mesh/material pairs are batched into instanced draws.
[Component]
class MeshRenderer : Component
{
	/// "builtin:cube", "builtin:sphere", ... or a model path relative to the project.
	public String mesh = new .("builtin:cube") ~ delete _;
	public Color color = .White;
	[Range(0, 1)]
	public float metallic = 0.0f;
	[Range(0, 1)]
	public float roughness = 0.85f;
	public Color emissive = .Black;
	public float emissiveIntensity = 0.0f;
	/// The glow is multiplied by the surface's own colour (vertex colours and texture): the bright parts of a model
	/// glow in their own colour and the dark parts stay dark. Set Emissive to white to keep the colours as they are.
	public bool emissiveFromColor = false;
	/// Faceted shading computed per triangle: the low-poly look without duplicated vertices.
	public bool flatShading = true;
	public bool unlit = false;
	public bool castShadows = true;
	/// Casts its shadow without being drawn itself. For what the camera must not see but the sun still should:
	/// the head and arms of a first-person player's own body, say.
	public bool shadowOnly = false;
	/// Optional albedo texture path relative to the project.
	public String texture = new .() ~ delete _;
	/// A material (.tmat) made in the editor. With one set, it decides how the surface looks and the fields above
	/// are ignored, except Color, which tints this object on top of the material, and Cast Shadows.
	public String material = new .() ~ delete _;

	Tessera.Material mSharedMaterial;
	Tessera.Material mMaterialInstance ~ delete _;
	String mResolvedMaterial = new .() ~ delete _;

	/// The material from the Material field, shared with every other renderer that names it. Null with none set.
	public Tessera.Material SharedMaterial
	{
		get
		{
			if (mResolvedMaterial != material)
			{
				mResolvedMaterial.Set(material);
				mSharedMaterial = Tessera.Material.Load(material);
				// A copy made for this object was a copy of the old material.
				DeleteAndNullify!(mMaterialInstance);
			}
			return mSharedMaterial;
		}
	}

	/// This object's own copy of its material, made the first time it is asked for. Change it to change this
	/// object without changing the others that share the material. Null with no material set.
	public Tessera.Material Material
	{
		get
		{
			let shared = SharedMaterial;
			if (shared == null)
				return null;
			if (mMaterialInstance == null)
				mMaterialInstance = shared.Clone();
			return mMaterialInstance;
		}
	}

	/// What the renderer draws with: this object's own copy if it has one, otherwise the shared material.
	public Tessera.Material ActiveMaterial
	{
		get
		{
			let shared = SharedMaterial;
			return mMaterialInstance != null ? mMaterialInstance : shared;
		}
	}

	/// Changes which material this object uses. In a network session, on the server or on the owner's machine,
	/// every machine follows.
	public void SetMaterial(StringView materialPath)
	{
		if (material == materialPath)
			return;
		material.Set(materialPath);
		NetworkSync.MaterialChanged(this, 0, materialPath, default);
	}

	/// Sets a property of this object's own copy of its material: one of the custom shader's properties by name,
	/// or "color", "emissive", "metallic", "roughness", "emissiveIntensity", "cutoff", "tiling" and "offset".
	/// In a network session, on the server or the owner's machine, every machine follows.
	public void SetMaterialValue(StringView name, Vector4 value)
	{
		let own = Material;
		if (own == null)
			return;
		switch (name)
		{
		case "color": own.color = .(value.x, value.y, value.z, value.w);
		case "emissive": own.emissive = .(value.x, value.y, value.z, value.w);
		case "metallic": own.metallic = Mathf.Clamp01(value.x);
		case "roughness": own.roughness = Mathf.Clamp01(value.x);
		case "emissiveIntensity": own.emissiveIntensity = Math.Max(value.x, 0);
		case "cutoff": own.cutoff = Mathf.Clamp01(value.x);
		case "tiling": own.tiling = .(value.x, value.y);
		case "offset": own.offset = .(value.x, value.y);
		default:
			own.SetVector(name, value);
		}
		own.Changed();
		NetworkSync.MaterialChanged(this, 1, name, value);
	}
	public void SetMaterialFloat(StringView name, float value) => SetMaterialValue(name, .(value, 0, 0, 0));
	public void SetMaterialColor(StringView name, Color value) => SetMaterialValue(name, .(value.r, value.g, value.b, value.a));

	/// World-space offset applied only when drawing. The network layer uses it to blend out corrections.
	[NonSerialized]
	public Vector3 VisualOffset;
	/// A texture made at run time (a Compute Texture, say) to draw with instead of the one named by the
	/// material or the Texture field. Set it invalid again to go back.
	[NonSerialized]
	public bgfx.TextureHandle TextureOverride = .() { idx = uint16.MaxValue };

	Mesh mResolvedMesh;
	Mesh mRuntimeMesh;
	String mResolvedPath = new .() ~ delete _;
	bool mResolved;
	bgfx.TextureHandle mTexture = .() { idx = uint16.MaxValue };
	String mResolvedTexture = new .() ~ delete _;

	public override void OnRegister() => Scene.Renderers.Add(this);
	public override void OnUnregister() => Scene.Renderers.Remove(this);

	/// Assign a procedurally built mesh. The renderer does not take ownership.
	public Mesh RuntimeMesh
	{
		get => mRuntimeMesh;
		set { mRuntimeMesh = value; }
	}

	public Mesh ActiveMesh
	{
		get
		{
			if (mRuntimeMesh != null)
				return mRuntimeMesh;
			if (!mResolved || mResolvedPath != mesh)
			{
				mResolvedPath.Set(mesh);
				mResolvedMesh = Assets.GetMesh(mesh);
				mResolved = true;
			}
			return mResolvedMesh;
		}
	}

	public bgfx.TextureHandle ActiveTexture
	{
		get
		{
			if (!mTexture.Valid || mResolvedTexture != texture)
			{
				mResolvedTexture.Set(texture);
				mTexture = Assets.GetTexture(texture);
			}
			return mTexture;
		}
	}

	public Bounds WorldBounds
	{
		get
		{
			let m = ActiveMesh;
			if (m == null)
				return .(Transform.Position, Transform.Position);
			return m.Bounds.Transformed(Transform.LocalToWorld);
		}
	}
}
