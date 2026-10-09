using System;
using System.Collections;
using System.IO;

namespace Tessera;

/// Asset packs: a built game's assets in one file (`game.tpak`) instead of loose files that anyone can open and
/// change. File > Build... makes the pack; a packed game mounts it by itself when it starts.
///
/// Everything the engine loads (scenes, prefabs, materials, models, textures, sounds, UI documents, shaders...)
/// comes from the pack when it is there and from disk when it is not, so nothing changes while developing. Game
/// code that reads its own data files should do it through this class, or Assets.ReadText / Assets.ReadBytes, for the
/// same reason:
///
///   let text = scope String();
///   if (Assets.ReadText("Data/levels.txt", text)) ...
///
/// A pack keeps assets from being opened or edited with ordinary tools, and a file that was changed anyway fails
/// its checksum and does not load. It is not encryption.
static class AssetPack
{
	[CLink] static extern int32 tn_pack_mount(char8* file, char8* root);
	[CLink] static extern void tn_pack_unmount_all();
	[CLink] static extern int32 tn_pack_exists(char8* path);
	[CLink] static extern int32 tn_pack_has_folder(char8* path);
	[CLink] static extern void* tn_pack_read(char8* path, uint* size);
	[CLink] static extern void tn_pack_free(void* data);
	[CLink] static extern int32 tn_pack_count();
	[CLink] static extern char8* tn_pack_path(int32 index);

	/// How many files are in the mounted packs. 0 when the game runs from loose files.
	public static int FileCount => tn_pack_count();
	public static bool Mounted => tn_pack_count() > 0;

	/// Mounts a pack file. Its files then appear to be inside the folder `root`, where the loose files would have
	/// been. False if the file is missing or is not a pack.
	public static bool Mount(StringView packFile, StringView root)
	{
		return tn_pack_mount(scope String(packFile).CStr(), scope String(root).CStr()) >= 0;
	}

	public static void UnmountAll() => tn_pack_unmount_all();

	/// Whether a full path names a file in a pack.
	public static bool Contains(StringView path) => tn_pack_count() > 0 && tn_pack_exists(scope String(path).CStr()) != 0;

	/// Whether the file exists: in a pack, or on disk.
	public static bool Exists(StringView path) => Contains(path) || File.Exists(path);

	/// Whether the folder exists: holding at least one packed file, or on disk.
	public static bool FolderExists(StringView path) => (tn_pack_count() > 0 && tn_pack_has_folder(scope String(path).CStr()) != 0) || Directory.Exists(path);

	/// Reads a whole file, from a pack if it is in one and from disk otherwise.
	public static Result<void> ReadAll(StringView path, List<uint8> data)
	{
		if (tn_pack_count() > 0)
		{
			let cPath = scope String(path);
			uint size = 0;
			let bytes = tn_pack_read(cPath.CStr(), &size);
			if (bytes != null)
			{
				data.AddRange(Span<uint8>((uint8*)bytes, (int)size));
				tn_pack_free(bytes);
				return .Ok;
			}
			// In the pack but unreadable: the pack was changed. The loose file is not a stand-in for it.
			if (tn_pack_exists(cPath.CStr()) != 0)
				return .Err;
		}
		if (File.ReadAll(path, data) case .Err)
			return .Err;
		return .Ok;
	}

	public static Result<void> ReadAllText(StringView path, String text)
	{
		if (tn_pack_count() > 0)
		{
			let bytes = scope List<uint8>();
			if (Contains(path))
			{
				if (ReadAll(path, bytes) case .Err)
					return .Err;
				text.Append(StringView((char8*)bytes.Ptr, bytes.Count));
				return .Ok;
			}
		}
		if (File.ReadAllText(path, text) case .Err)
			return .Err;
		return .Ok;
	}

	/// The full paths of the packed files inside a folder (and its sub-folders), for code that used to list a folder.
	public static void FilesIn(StringView folder, List<String> paths)
	{
		let prefix = scope String(folder);
		prefix.Replace('\\', '/');
		while (prefix.EndsWith('/'))
			prefix.RemoveFromEnd(1);
		prefix.Append('/');
		for (int32 i = 0; i < tn_pack_count(); i++)
		{
			let path = StringView(tn_pack_path(i));
			if (path.StartsWith(prefix))
				paths.Add(new String(path));
		}
	}
}
