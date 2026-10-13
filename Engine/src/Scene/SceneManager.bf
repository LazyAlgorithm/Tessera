using System;
using System.Collections;
using System.IO;

namespace Tessera;

/// Scenes while the game runs: bring another scene's contents into the one that is playing, take them out again,
/// or change to a different scene altogether.
///
///   // A level kept in its own scene file, added to the scene that holds the game's menus and rules:
///   let level = SceneManager.LoadAdditive(Scene, "Scenes/Harbour.tscene", true);
///   ...
///   SceneManager.Unload(level);
///
///   // Or leave this scene for another one (it happens at the start of the next frame):
///   SceneManager.Load("Scenes/Credits.tscene");
///
/// Paths are relative to the project's asset folder, like every other asset path.
static class SceneManager
{
	static String sPending = new .() ~ delete _;
	static String sCurrent = new .() ~ delete _;

	/// The scene asked for with Load that has not been switched to yet, or empty.
	public static StringView Pending => sPending;
	/// The scene last switched to with Load, relative to the asset folder; empty until Load has been used.
	public static StringView Current => sCurrent;

	/// Adds everything in a scene file to a scene that is already loaded, and returns an object that holds it all:
	/// the file's top-level objects become its children. Components wake up at once if the scene is playing.
	/// With applyEnvironment the file's sky, fog and ambient light replace the scene's. Returns null if the file
	/// cannot be read.
	///
	/// Objects get fresh ids, so the same file can be added more than once. Nothing here is networked: in a
	/// multiplayer game every machine loads the scene for itself, as it does its start scene.
	public static GameObject LoadAdditive(Scene scene, StringView path, bool applyEnvironment = false)
	{
		if (scene == null)
			return null;
		// Its pack has not downloaded yet (only in a browser): check AssetPack.SceneReady first.
		if (!AssetPack.SceneReady(path))
		{
			AssetPack.Request(path);
			Log.Error(scope $"Scene not downloaded yet: {path}");
			return null;
		}
		let full = scope String();
		Assets.ResolvePath(path, full);
		let text = scope String();
		if (AssetPack.ReadAllText(full, text) case .Err)
		{
			Log.Error(scope $"Scene not found: {path}");
			return null;
		}
		let before = scene.Roots.Count;
		SceneSerializer.Instantiate(scene, text);
		List<GameObject> added = scope .();
		for (int i = before; i < scene.Roots.Count; i++)
			added.Add(scene.Roots[i]);
		let name = scope String();
		Path.GetFileNameWithoutExtension(path, name);
		let group = scene.CreateGameObject(name);
		// Part of what is running, not of the scene that was saved.
		group.Transient = true;
		for (let object in added)
			object.Transform.SetParent(group.Transform, true);
		if (applyEnvironment)
			SceneSerializer.LoadEnvironment(scene, text);
		return group;
	}

	/// Removes what LoadAdditive added, at once.
	public static void Unload(GameObject group)
	{
		if (group != null && group.Scene != null && !group.IsDestroyed)
			group.Scene.DestroyImmediate(group);
	}

	/// Changes to another scene: at the start of the next frame the running scene is stopped and emptied, the file
	/// is loaded in its place and play carries on in it. A network session in the old scene is closed. In the
	/// editor this happens inside play mode only; stopping still brings back the scene that was being edited.
	public static void Load(StringView path)
	{
		sPending.Set(path);
	}

	/// Called by the application between frames. Returns true if the scene was changed.
	public static bool ApplyPending(Scene scene)
	{
		if (sPending.IsEmpty || scene == null)
			return false;
		// A scene whose pack is still downloading (in a browser) is switched to once it has arrived.
		if (!AssetPack.SceneReady(sPending))
		{
			AssetPack.Request(sPending);
			return false;
		}
		let path = scope String(sPending);
		sPending.Clear();
		let full = scope String();
		Assets.ResolvePath(path, full);
		if (!AssetPack.Exists(full))
		{
			Log.Error(scope $"Scene not found: {path}");
			return false;
		}
		let wasPlaying = scene.IsPlaying;
		if (wasPlaying)
			scene.StopPlay();
		if (scene.Network != null)
		{
			scene.Network.Stop();
			delete scene.Network;
			scene.Network = null;
		}
		// The scene object keeps the path it was opened from: in the editor that is the file being edited.
		let opened = scope String(scene.Path);
		SceneSerializer.LoadFromFile(scene, full);
		scene.Path.Set(opened);
		sCurrent.Set(path);
		if (wasPlaying)
			scene.StartPlay();
		return true;
	}
}
