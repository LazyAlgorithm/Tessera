using System;
using System.Collections;
using Tessera;

namespace SkinnedMaterialTests;

/// Materials on skinned meshes (docs/skinned-materials.md): a rigged model's parts, one per material in the file, with
/// the file's own materials and textures (inside a .glb, as data: addresses, and as files beside the model), the
/// parts' own .tmat overrides, and saving. Run from this folder: BeefBuild -workspace=Tests/SkinnedMaterials -run
/// (the models are made by make_models.py). Drawing needs a graphics card; check it by eye in the editor.
class Program
{
	static int sFailures;
	static bool Check(bool pass, StringView label)
	{
		Console.WriteLine(scope $"{pass ? "PASS" : "FAIL"}: {label}");
		if (!pass) sFailures++;
		return pass;
	}

	static void CheckModel(StringView file)
	{
		let path = scope $"assets/{file}.glb";
		let model = SkinnedModel.Load(path);
		if (!Check(model != null, scope $"{file}: the rigged model loads"))
			return;
		Check(model.HasOwnMaterials && model.Parts.Count == 2, scope $"{file}: two materials, so two parts with materials of their own");
		if (model.Parts.Count != 2)
			return;
		let skin = model.Parts[0];
		let armour = model.Parts[1];
		Check(skin.name == "Skin" && armour.name == "Armour", scope $"{file}: parts are named after the file's materials");
		Check(skin.indices.Count == 6 && armour.indices.Count == 6, scope $"{file}: each part has its own triangles");
		Check(skin.material.texture == scope $"{path}#image0" && skin.material.normalMap == scope $"{path}#image1", scope $"{file}: the base colour and normal textures come from the file");
		Check(Math.Abs(skin.material.normalStrength - 0.5f) < 0.001f && Math.Abs(skin.material.metallic - 0.1f) < 0.001f && Math.Abs(skin.material.roughness - 0.7f) < 0.001f, scope $"{file}: normal scale, metallic and roughness come from the file");
		Check(skin.material.blend == .Opaque && !skin.material.doubleSided && !skin.material.flatShading, scope $"{file}: an opaque, one-sided, smooth-shaded part");
		Check(armour.material.texture == scope $"{path}#image2" && armour.material.normalMap.IsEmpty, scope $"{file}: the second part has its own texture and no normal map");
		Check(armour.material.blend == .Cutout && Math.Abs(armour.material.cutoff - 0.4f) < 0.001f && armour.material.doubleSided, scope $"{file}: alpha mask and double sides come from the file");
		Check(armour.material.emissiveIntensity > 0 && armour.material.emissive.r > 0.1f && Math.Abs(armour.material.metallic - 0.9f) < 0.001f, scope $"{file}: emissive and metallic come from the file");
	}

	public static int Main(String[] args)
	{
		CheckModel("embedded");
		CheckModel("datauri");
		CheckModel("beside");

		let plain = SkinnedModel.Load("assets/plain.glb");
		Check(plain != null && !plain.HasOwnMaterials && plain.Parts.Count == 1, "a model with one plain material is one mesh, drawn as before");

		// ---- the component ----
		let scene = scope Scene();
		let hero = scene.CreateGameObject("Hero");
		hero.AddComponent<MeshRenderer>();
		let skinned = hero.AddComponent<SkinnedMeshRenderer>();
		skinned.model.Set("assets/embedded.glb");
		skinned.OnValidate();
		Check(skinned.PartCount == 2 && skinned.PartName(0) == "Skin" && skinned.PartName(1) == "Armour", "the component lists the model's parts");
		let path = scope String();
		skinned.SetPartMaterial(1, "Materials/steel.tmat");
		skinned.GetPartMaterial("Armour", path);
		Check(path == "Materials/steel.tmat", "a part can be given a material of its own");
		skinned.GetPartMaterial("Skin", path);
		Check(path.IsEmpty, "the other part keeps the model's");
		skinned.SetPartMaterial(0, "Materials/skin.tmat");
		Check(skinned.materials == "Armour=Materials/steel.tmat;Skin=Materials/skin.tmat", scope $"both are kept ({skinned.materials})");
		skinned.SetPartMaterial(1, "");
		skinned.GetPartMaterial("Armour", path);
		Check(path.IsEmpty && skinned.materials == "Skin=Materials/skin.tmat", "an empty path gives a part back the model's material");
		skinned.SetPartMaterial(0, "bad;path");
		skinned.SetPartMaterial(7, "Materials/x.tmat");
		Check(skinned.materials == "Skin=Materials/skin.tmat", "a path with ; or = and a part that does not exist are refused");

		let text = scope String();
		SceneSerializer.Save(scene, text);
		let loaded = scope Scene();
		SceneSerializer.Load(loaded, text);
		let back = loaded.Find("Hero").GetComponent<SkinnedMeshRenderer>();
		Check(back != null && back.materials == "Skin=Materials/skin.tmat", "a scene keeps the parts' materials");

		let plainObject = scene.CreateGameObject("Plain");
		plainObject.AddComponent<MeshRenderer>();
		let plainSkinned = plainObject.AddComponent<SkinnedMeshRenderer>();
		plainSkinned.model.Set("assets/plain.glb");
		plainSkinned.OnValidate();
		Check(plainSkinned.PartCount == 0, "a plain model has no parts to set");

		Console.WriteLine(sFailures == 0 ? "All skinned material tests passed." : scope $"{sFailures} skinned material test(s) failed.");
		return sFailures == 0 ? 0 : 1;
	}
}
