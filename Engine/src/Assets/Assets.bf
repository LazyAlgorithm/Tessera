using System;
using System.Collections;
using Bgfx;

namespace Tessera;

/// Mesh and texture cache keyed by path. "builtin:cube" style names give primitives,
/// anything else is a file relative to the project folder ("models/tree.glb", optionally "#2" for a sub-mesh).
static class Assets
{
	public static String ProjectPath = new .() ~ delete _;

	static Dictionary<String, Mesh> sMeshes = new .() ~ DeleteDictionaryAndKeysAndValues!(_);
	static Dictionary<String, uint16> sTextures = new .() ~ DeleteDictionaryAndKeys!(_);

	public static readonly StringView[?] BuiltinMeshes = .("builtin:cube", "builtin:sphere", "builtin:capsule", "builtin:cylinder", "builtin:cone", "builtin:plane", "builtin:quad");

	public static void Clear()
	{
		for (let entry in sMeshes)
		{
			delete entry.key;
			delete entry.value;
		}
		sMeshes.Clear();
		for (let entry in sTextures)
		{
			if (Gfx.Initialized && entry.value != Gfx.WhiteTexture.idx)
			{
				bgfx.TextureHandle handle;
				handle.idx = entry.value;
				bgfx.destroy_texture(handle);
			}
			delete entry.key;
		}
		sTextures.Clear();
	}

	/// Extra folders searched before the project's own, newest first: mods and Workshop items. A file a mod provides
	/// under the same relative path replaces the project's.
	static List<String> sSearchPaths = new .() ~ DeleteContainerAndItems!(_);
	public static List<String> SearchPaths => sSearchPaths;

	/// Makes a folder's files available by their path relative to it, taking priority over the project's files.
	public static void AddSearchPath(StringView folder)
	{
		for (let existing in sSearchPaths)
		{
			if (existing == folder)
				return;
		}
		sSearchPaths.Add(new String(folder));
	}

	public static void RemoveSearchPath(StringView folder)
	{
		for (let existing in sSearchPaths)
		{
			if (existing == folder)
			{
				sSearchPaths.Remove(existing);
				delete existing;
				return;
			}
		}
	}

	/// The reverse of ResolvePath: a file on disk as a path relative to the project (or to a search path).
	/// A path outside all of them is returned unchanged.
	public static void MakeRelative(StringView fullPath, String outPath)
	{
		for (int i = sSearchPaths.Count - 1; i >= 0; i--)
		{
			if (fullPath.StartsWith(sSearchPaths[i]) && fullPath.Length > sSearchPaths[i].Length && fullPath[sSearchPaths[i].Length] == '/')
			{
				outPath.Append(fullPath.Substring(sSearchPaths[i].Length + 1));
				return;
			}
		}
		if (!ProjectPath.IsEmpty && fullPath.StartsWith(ProjectPath) && fullPath.Length > ProjectPath.Length && fullPath[ProjectPath.Length] == '/')
		{
			outPath.Append(fullPath.Substring(ProjectPath.Length + 1));
			return;
		}
		outPath.Append(fullPath);
	}

	/// Whether a path names a place by itself: /folder on Linux and macOS, C:/folder or \\\\server on Windows.
	public static bool IsAbsolute(StringView path) => path.StartsWith('/') || path.StartsWith('\\') || (path.Length > 2 && path[1] == ':');

	/// Reads one of the project's files as text: from the game's asset pack in a built game, from disk otherwise.
	/// path is relative to the project, like every asset path. False if there is no such file.
	public static bool ReadText(StringView path, String text) => AssetPack.ReadAllText(ResolvePath(path, .. scope .()), text) case .Ok;

	/// Reads one of the project's files as bytes; see ReadText.
	public static bool ReadBytes(StringView path, List<uint8> data) => AssetPack.ReadAll(ResolvePath(path, .. scope .()), data) case .Ok;

	/// Whether the project has this file, packed or loose.
	public static bool FileExists(StringView path) => AssetPack.Exists(ResolvePath(path, .. scope .()));

	public static void ResolvePath(StringView path, String outPath)
	{
		if (IsAbsolute(path) || ProjectPath.IsEmpty)
		{
			outPath.Append(path);
			return;
		}
		for (int i = sSearchPaths.Count - 1; i >= 0; i--)
		{
			let candidate = scope $"{sSearchPaths[i]}/{path}";
			if (System.IO.File.Exists(candidate))
			{
				outPath.Append(candidate);
				return;
			}
		}
		outPath.AppendF("{}/{}", ProjectPath, path);
	}

	public static Mesh GetMesh(StringView path)
	{
		if (path.IsEmpty)
			return null;
		if (sMeshes.TryGetValueAlt(path, let cached))
			return cached;

		Mesh mesh = null;
		if (path.StartsWith("builtin:"))
		{
			switch (path)
			{
			case "builtin:cube": mesh = Primitives.CreateCube();
			case "builtin:sphere": mesh = Primitives.CreateSphere();
			case "builtin:capsule": mesh = Primitives.CreateCapsule();
			case "builtin:cylinder": mesh = Primitives.CreateCylinder();
			case "builtin:cone": mesh = Primitives.CreateCylinder(16, 0);
			case "builtin:plane": mesh = Primitives.CreatePlane();
			case "builtin:quad": mesh = Primitives.CreateQuad();
			default:
			}
		}
		else
		{
			mesh = LoadModel(path);
		}
		if (mesh == null)
		{
			Log.Warning(scope $"Mesh not found: {path}");
			return null;
		}
		sMeshes[new String(path)] = mesh;
		return mesh;
	}

	/// Loads a glTF / GLB file. Without a "#index" suffix every primitive is merged into one mesh.
	static Mesh LoadModel(StringView path)
	{
		var filePart = path;
		int32 only = -1;
		let hash = path.LastIndexOf('#');
		if (hash >= 0)
		{
			filePart = path.Substring(0, hash);
			only = SceneSerializer.ParseInt(path.Substring(hash + 1));
		}
		let full = scope String();
		ResolvePath(filePart, full);
		let scene = Native.tn_gltf_load(full.CStr());
		if (scene == null)
			return null;
		defer Native.tn_gltf_free(scene);

		let mesh = new Mesh();
		mesh.Name.Set(path);
		let count = Native.tn_gltf_prim_count(scene);
		for (uint32 p = 0; p < count; p++)
		{
			if (only >= 0 && (uint32)only != p)
				continue;
			let prim = Native.tn_gltf_get_prim(scene, p);
			Matrix4 world = default;
			for (int i < 16)
				world.m[i] = prim.world[i];
			// glTF is right-handed with +Z towards the viewer; flip Z into Tessera's left-handed space.
			let flip = Matrix4.Scale(.(1, 1, -1));
			world = flip * world;
			let baseColor = Color(prim.baseColor[0], prim.baseColor[1], prim.baseColor[2], prim.baseColor[3]);
			let baseVertex = (uint32)mesh.Vertices.Count;
			for (uint32 v = 0; v < prim.vertexCount; v++)
			{
				let position = Vector3(prim.positions[v * 3], prim.positions[v * 3 + 1], prim.positions[v * 3 + 2]);
				var normal = Vector3.Up;
				if (prim.normals != null)
					normal = .(prim.normals[v * 3], prim.normals[v * 3 + 1], prim.normals[v * 3 + 2]);
				var color = baseColor;
				if (prim.colors != null)
				{
					color.r *= prim.colors[v * 4];
					color.g *= prim.colors[v * 4 + 1];
					color.b *= prim.colors[v * 4 + 2];
					color.a *= prim.colors[v * 4 + 3];
				}
				// glTF stores linear color; the shader expects sRGB-encoded vertex colors.
				color = .(Math.Pow(color.r, 1.0f / 2.2f), Math.Pow(color.g, 1.0f / 2.2f), Math.Pow(color.b, 1.0f / 2.2f), color.a);
				Vector2 uv = default;
				if (prim.uvs != null)
					uv = .(prim.uvs[v * 2], prim.uvs[v * 2 + 1]); // glTF and Tessera both put V = 0 at the top of the image
				mesh.AddVertex(world.TransformPoint(position), world.TransformDirection(normal).Normalized, color, uv);
			}
			// Mirroring Z turns every triangle inside out, so swap two corners to face it outwards again.
			for (uint32 i = 0; i + 2 < prim.indexCount; i += 3)
				mesh.AddTriangle(baseVertex + prim.indices[i], baseVertex + prim.indices[i + 2], baseVertex + prim.indices[i + 1]);
			if (prim.normals == null)
				mesh.RecalculateNormals();
		}
		mesh.Upload();
		return mesh;
	}

	/// Makes a texture from RGBA pixels (4 bytes a pixel) under a name of its own, such as an image found inside a
	/// model ("Models/hero.glb#image2"), so that GetTexture, and every Material naming it, finds it. Does nothing if
	/// a texture of that name is already there. Returns it.
	public static bgfx.TextureHandle AddTexture(StringView path, uint8* pixels, int32 width, int32 height)
	{
		if (sTextures.TryGetValueAlt(path, let cached))
		{
			bgfx.TextureHandle handle;
			handle.idx = cached;
			return handle;
		}
		if (pixels == null || width <= 0 || height <= 0 || !Gfx.Initialized)
			return Gfx.WhiteTexture;
		let texture = bgfx.create_texture_2d((uint16)width, (uint16)height, false, 1, .RGBA8, 0, bgfx.copy(pixels, (uint32)(width * height * 4)), 0);
		sTextures[new String(path)] = texture.idx;
		return texture;
	}

	public static bgfx.TextureHandle GetTexture(StringView path)
	{
		if (path.IsEmpty)
			return Gfx.WhiteTexture;
		if (sTextures.TryGetValueAlt(path, let cached))
		{
			bgfx.TextureHandle handle;
			handle.idx = cached;
			return handle;
		}
		let full = scope String();
		ResolvePath(path, full);
		let texture = Gfx.LoadTexture(full);
		sTextures[new String(path)] = texture.idx;
		return texture;
	}
}
