using System;
using System.Collections;
using System.IO;
using System.Threading;
using Tessera;

namespace MapTests;

class Program
{
	static int sFailures;

	static bool Check(bool pass, StringView label)
	{
		Console.WriteLine(scope $"{pass ? "PASS" : "FAIL"}: {label}");
		if (!pass)
			sFailures++;
		return pass;
	}

	/// Runs frames until the terrain has stopped loading.
	static void Settle(Scene scene, VoxelTerrain terrain)
	{
		int stable = 0, last = -1;
		for (int i = 0; i < 4000 && stable < 40; i++)
		{
			Time.DeltaTime = 0.016f;
			Time.UnscaledDeltaTime = 0.016f;
			scene.Update();
			Thread.Sleep(2);
			if (terrain.ChunkCount == last && terrain.PendingChunks == 0)
				stable++;
			else
				stable = 0;
			last = terrain.ChunkCount;
		}
	}

	static float Ground(VoxelTerrain terrain, float x, float z)
	{
		Vector3 point;
		if (terrain.Raycast(Ray(.(x, 60, z), .(0, -1, 0)), 200, out point))
			return point.y;
		return float.NaN;
	}

	static VoxelTerrain MakeTerrain(Scene scene)
	{
		let terrain = scene.CreateGameObject("Terrain").AddComponent<VoxelTerrain>();
		terrain.voxelSize = 1;
		terrain.tileSize = 2;
		terrain.style = .Smooth;
		terrain.generateColliders = false;
		terrain.lodDistance = 0;
		terrain.OnValidate();
		return terrain;
	}

	static bool HasProblem(MapFileInfo map, StringView words)
	{
		for (let problem in map.Problems)
		{
			if (problem.Contains(words))
				return true;
		}
		return false;
	}

	static MapFileInfo Named(List<MapFileInfo> maps, StringView fileName)
	{
		for (let map in maps)
		{
			if (map.File.EndsWith(fileName))
				return map;
		}
		return null;
	}

	static void Empty(StringView folder)
	{
		if (!Directory.Exists(folder))
			return;
		for (let entry in Directory.EnumerateFiles(folder))
			File.Delete(entry.GetFilePath(.. scope .())).IgnoreError();
	}

	public static int Main(String[] args)
	{
		let folder = scope String();
		Path.GetTempPath(folder);
		folder.Append("/tessera-map-test");
		let maps = scope $"{folder}/Maps";
		Directory.CreateDirectory(scope $"{folder}/Textures").IgnoreError();
		Directory.CreateDirectory(maps).IgnoreError();
		Empty(maps);
		Empty(scope $"{folder}/Scenes/Level.terrain");
		Assets.ProjectPath.Set(folder);
		GamePaths.Game.Set("Map Test");
		GamePaths.SetGameFolder(folder);
		File.WriteAllText(scope $"{folder}/Textures/stone.png" , "not really a picture").IgnoreError();
		VoxelTerrain.Viewers.Clear();

		// ---- a level, sculpted and saved, exported as a map ----
		float hill;
		{
			let level = scope Scene();
			level.Name.Set("Level");
			Scene.Active = level;
			let floor = level.CreateGameObject("Floor");
			let renderer = floor.AddComponent<MeshRenderer>();
			renderer.mesh.Set("builtin:cube");
			renderer.texture.Set("Textures/stone.png");
			level.CreateGameObject("Start").AddComponent<SpawnPoint>();
			let terrain = MakeTerrain(level);
			Settle(level, terrain);
			for (int i < 30)
				terrain.Brush(.(16, 0, 16), 5, 0.1f, .Raise);
			Settle(level, terrain);
			hill = Ground(terrain, 16, 16);
			Directory.CreateDirectory(scope $"{folder}/Scenes").IgnoreError();
			terrain.editsFolder.Set("Scenes/Level.terrain");
			SceneSerializer.SaveToFile(level, scope $"{folder}/Scenes/Level.tscene");
			Check(hill > 1, scope $"the level has a sculpted hill ({hill:0.0} m)");
			let problems = scope List<String>();
			defer
			{
				ClearAndDeleteItems!(problems);
			}
			let exported = MapFiles.Export(level, scope $"{maps}/Level.tmap" , "Harbour Hill", "A tester", "A hill by the sea.", problems) case .Ok;
			Check(exported && problems.Count == 0, scope $"a scene exports as a map file with nothing missing ({problems.Count} problems)");
			let pack = scope PackFile();
			Check(pack.Open(scope $"{maps}/Level.tmap") case .Ok && pack.Has("map.txt") && pack.Has("map.tscene") && pack.Has("terrain1/tile_1.voxels"),
				"it holds its description, its scene and the terrain's sculpting");
			Directory.DelTree(scope $"{folder}/Scenes/Level.terrain").IgnoreError();
		}

		// ---- found and checked ----
		{
			let found = scope List<MapFileInfo>();
			defer
			{
				ClearAndDeleteItems!(found);
			}
			let playable = MapFiles.Find(maps, found);
			let map = found.Count > 0 ? found[0] : null;
			Check(playable == 1 && map != null && map.Ok, "Find lists the map, with no problems");
			Check(map != null && map.Name == "Harbour Hill" && map.Author == "A tester" && map.Description == "A hill by the sea." && map.Game == "Map Test",
				"with the name, author, description and game it was exported with");
			Check(map != null && map.CountComponents("Tessera.SpawnPoint") == 1 && map.CountComponents("Tessera.VoxelTerrain") == 1,
				"a game can count what is in it (one spawn point, one terrain)");
			Check(MapFiles.Find(scope $"{folder}/NoSuchFolder" , found) == 0, "a missing Maps folder finds nothing");

			// ---- played: mounted and added to a running scene, sculpting and all ----
			let game = scope Scene();
			Scene.Active = game;
			game.CreateGameObject("Game");
			game.StartPlay();
			let scenePath = map.ScenePath(.. scope .());
			Check(!AssetPack.Exists(Assets.ResolvePath(scenePath, .. scope .())), "before it is mounted its scene cannot be read");
			Check(MapFiles.Mount(map) && map.Mounted && AssetPack.Exists(Assets.ResolvePath(scenePath, .. scope .())), "mounting it makes its scene readable");
			let group = SceneManager.LoadAdditive(game, scenePath, true);
			let terrain = game.FindComponent<VoxelTerrain>();
			Check(group != null && terrain != null && game.FindComponent<SpawnPoint>() != null, "its scene loads into the game like any other");
			if (terrain != null)
			{
				Settle(game, terrain);
				let height = Ground(terrain, 16, 16);
				Check(Math.Abs(height - hill) < 0.3f, scope $"and its terrain has the sculpting from the map ({height:0.0} m, {hill:0.0} m when exported)");
			}
			SceneManager.Unload(group);
			MapFiles.Unmount(map);
			Check(!map.Mounted && !AssetPack.Exists(Assets.ResolvePath(scenePath, .. scope .())), "unmounting it frees its files");
			game.StopPlay();
		}

		// ---- maps with something wrong ----
		{
			File.Copy(scope $"{maps}/Level.tmap" , scope $"{maps}/Copy of Level.tmap").IgnoreError();
			File.WriteAllText(scope $"{maps}/Junk.tmap" , "this is not a map").IgnoreError();
			// A copy with one byte of its scene changed.
			let bytes = scope List<uint8>();
			File.ReadAll(scope $"{maps}/Level.tmap" , bytes).IgnoreError();
			bytes[bytes.Count / 2] ^= 0x5A;
			File.WriteAll(scope $"{maps}/Damaged.tmap" , bytes).IgnoreError();
			// Made by another game, and one that names a file and a component the game does not have.
			let other = scope Scene();
			other.Name.Set("Other");
			other.CreateGameObject("Thing").AddComponent<MeshRenderer>().mesh.Set("Models/missing.glb");
			let problems = scope List<String>();
			defer
			{
				ClearAndDeleteItems!(problems);
			}
			MapFiles.Export(other, scope $"{maps}/Missing.tmap" , "Missing Things", "", "", problems).IgnoreError();
			Check(problems.Count == 1 && problems[0].Contains("Models/missing.glb"), "Export says when the scene names a file the project does not have");
			GamePaths.Game.Set("Another Game");
			MapFiles.Export(other, scope $"{maps}/Foreign.tmap" , "Foreign", "", "", problems).IgnoreError();
			GamePaths.Game.Set("Map Test");
			let scene = "scene \"Odd\"\nobject 1 parent 0 active 1 name \"Odd\"\ntransform 0 0 0 0 0 0 1 1 1 1\ncomponent Nowhere.Gizmo enabled 1\n";
			let info = "tmap 1\nid odd-1\nname Odd\ngame Map Test\n";
			let newer = "tmap 99\nid newer-1\nname Newer\ngame Map Test\n";
			(StringView name, Span<uint8> data)[2] oddFiles = .(("map.txt", .((uint8*)info.Ptr, info.Length)), ("map.tscene", .((uint8*)scene.Ptr, scene.Length)));
			PackFile.Write(scope $"{maps}/Odd.tmap" , oddFiles).IgnoreError();
			(StringView name, Span<uint8> data)[2] newerFiles = .(("map.txt", .((uint8*)newer.Ptr, newer.Length)), ("map.tscene", .((uint8*)scene.Ptr, scene.Length)));
			PackFile.Write(scope $"{maps}/Newer.tmap" , newerFiles).IgnoreError();

			let found = scope List<MapFileInfo>();
			defer
			{
				ClearAndDeleteItems!(found);
			}
			let playable = MapFiles.Find(maps, found);
			Check(playable == 1 && found.Count == 8, scope $"of eight map files only the good one can be played ({playable} of {found.Count})");
			let junk = Named(found, "/Junk.tmap");
			Check(junk != null && HasProblem(junk, "not a map file"), "a file that is not a map says so");
			let damaged = Named(found, "/Damaged.tmap");
			Check(damaged != null && HasProblem(damaged, "damaged"), "a changed map file is caught by its checksums");
			let foreign = Named(found, "/Foreign.tmap");
			Check(foreign != null && HasProblem(foreign, "made for Another Game"), "a map for another game is refused");
			let missing = Named(found, "/Missing.tmap");
			Check(missing != null && HasProblem(missing, "needs Models/missing.glb"), "a map that needs a file the game lacks is refused");
			let odd = Named(found, "/Odd.tmap");
			Check(odd != null && HasProblem(odd, "uses Nowhere.Gizmo"), "a map with a component the game lacks is refused");
			let newerMap = Named(found, "/Newer.tmap");
			Check(newerMap != null && HasProblem(newerMap, "newer version"), "a map from a newer engine is refused");
			let original = Named(found, "/Level.tmap");
			let copy = Named(found, "/Copy of Level.tmap");
			Check(copy != null && original != null && copy.Id == original.Id && (copy.Ok != original.Ok), "a renamed copy is the same map, and only one of the two is listed as playable");
			Check(junk != null && !MapFiles.Mount(junk), "a map with problems cannot be mounted");
		}

		Console.WriteLine(sFailures == 0 ? "ALL MAP TESTS PASSED" : scope $"{sFailures} MAP TESTS FAILED");
		return sFailures == 0 ? 0 : 1;
	}
}
