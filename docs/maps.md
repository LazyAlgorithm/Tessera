# Maps

A map is a scene exported from the editor into one `.tmap` file. A game looks for map files in a folder and plays
them without being built again, so a level can be made in the editor and tried in the built game straight away, or
handed to players as a single file.

## Exporting a map

Open the scene and choose **File > Export Scene as Map...**:

| Field | Meaning |
|---|---|
| Name, Author, Description | Shown by the game (the name in its menu). |
| Folder | Where the file goes: the project's `Maps` folder by default, where the game finds it when it runs from the editor. |
| Also put it in each build of the game | Copies the file into `Maps` beside every built copy of the game under the project's `Builds` folder (any folder there, or one level down, with a `game.tessera` or `game.tpak`). |

The scene is saved first. The map holds the scene and the scene's own data, which is each Voxel Terrain's sculpting.
Everything else it uses comes from the game: models, prefabs, materials, textures, sounds and scripts. A map can only
use what the game has, and the export window lists any file the scene names that the project lacks.

`--export-map [name]` does the same from the command line for the scene given with `--scene`, and logs
`MAP-EXPORT PASS` or `FAIL`.

## Finding and playing maps

```beef
let maps = scope List<MapFileInfo>();
defer { ClearAndDeleteItems!(maps); }
MapFiles.Find(MapFiles.Folder(.. scope .()), maps);
for (let map in maps)
{
    if (map.Ok)
        Log.Info(map.Name);  // list it in the menu
    else
        Log.Warning(scope $"{map.File}: {map.Problems[0]}");
}

// To play one: mount it, then load its scene as any other.
if (MapFiles.Mount(map))
    SceneManager.LoadAdditive(Scene, map.ScenePath(.. scope .()), true);
```

`MapFiles.Folder` is the `Maps` folder in `GamePaths.GameFolder`. That is the folder beside a built game's program, or
the project's folder when the game runs from the editor. `Find` looks at every `.tmap` file in a folder and returns
them sorted by name, broken ones included, each with `Problems` saying why it cannot be played:

- the file is not a map, or is damaged (each file inside has a checksum, so a changed or cut-short map is caught here,
  not halfway through loading);
- it was made for another game (`Game`, the project's name when it was exported);
- it was made with a newer version of the engine;
- it uses a component the game does not have, or names a file the game does not have;
- it is the same map (the same `Id`) as one listed already, such as a renamed copy.

A game adds its own checks with `map.AddProblem`, and can count what is in the map with
`map.CountComponents("Tessera.SpawnPoint")`. `Mount` reads the map's files into memory, where they are found before
the game's own files. `Unmount` frees them; unload the map's scene first.

`Id` stays the same when the file is renamed or copied, so players with the same map have the same `Id`. In
multiplayer, share the `Id` of the map in play (a `[Sync]` string, or the session context): every player needs the
map file, and one who lacks it can say so instead of loading the wrong level.

## The file

A `.tmap` file is an asset pack in the format the engine's own packs use (`native/tessera_pack.c`). It holds
`map.txt` (the name, author, description, game and `Id`), `map.tscene`, and the terrain sculpting folders. While it
is mounted its files appear in the project's `.maps/<Id>/` folder. `tools/pack_assets.py --list` and `--verify`
read it. `PackFile` reads and writes one such pack from Beef.

## Limits

- A map carries no assets of its own: new models, materials or scripts reach players with the next build of the game.
- Lightmaps baked for the scene are not carried with it.
- Mounting reads the whole map into memory. Maps are small (a sculpted terrain tile is about 70 KB), but a map is not
  streamed.

CPU tests (`Tests/Maps`) cover:

- exporting a sculpted level, finding it, reading its details, counting its components;
- mounting it, loading it into a running scene with its sculpting, and unmounting it;
- refusing eight kinds of bad map: junk, damaged, another game's, a missing file, an unknown component, a newer
  format, a duplicate, and mounting a refused one.
