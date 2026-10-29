# World streaming

One large open world, built in the editor as one scene, that loads round the players with no code. The scene is
saved as a grid of square cells, each in a file of its own, and only the cells near a player are loaded. Unreal's
World Partition works the same way.

## Turning it on

Click empty space in the Hierarchy to show the Scene Settings, open **World Streaming** and tick **Stream This
Scene**, then save.

| Setting | Default | What it does |
| --- | --- | --- |
| Cell Size | 64 m | A cell's width and depth. |
| Load Radius | 160 m | Cells this close to a source are loaded. They are taken out again half a cell further out, so that a player on a cell's edge does not make it come and go. |
| Stand-in Radius | 800 m | Cells this close that are not loaded show their stand-in (below). |
| Floating Origin | 0 (off) | When the player gets this far from the centre, the whole world moves back round them (below). |

## What streams

The objects at the top of the scene, or at the top of a folder, each go in the cell their position is in, with all
their children. Folders themselves always stay loaded, and only their contents stream, so the Hierarchy keeps its
shape.

These stay loaded wherever the players are:

- objects with **Always Loaded** ticked (the box under the object's name in the Inspector, shown only in a streamed
  scene; the Inspector also shows which cell an object is in);
- objects with, anywhere under them, a Camera, a directional Light, Voxel Terrain (it streams its own chunks), a Spawn
  Point, a Network Identity or a Streaming Source.

Each object keeps its id, so references between objects still work once both are loaded. A reference to an object
in a cell that is not loaded finds nothing until the cell comes in. New objects never take the id of an object in a
cell that is not loaded.

Other parts of the world stream with the objects they belong to:

- **Baked lighting**: each Mesh Renderer names its own lightmap, so lightmaps come and go with their objects. The light
  probes file (`.tprobes`) is one for the scene and stays loaded.
- **Navigation**: a Navigation Surface and its baked `.tnav` go with the cell it stands in. For a large world, use a
  surface for each area instead of one over everything.
- **Foliage**: a Foliage object goes with the cell it stands in, with all its plants. Paint a large world with a
  Foliage object for each area, or tick Always Loaded on one that covers it all.

## Streaming Sources

The world loads round each **Streaming Source** component: put one on the player's object. On a server every
player's object has one, so the world is loaded round each player. A vehicle or a camera can carry one too, and
**Extra Radius** loads further round it (a fast vehicle wants more of the world ahead). With no sources in the scene,
the world streams round its cameras.

## While the game runs

- Cell files are read on a background thread, then the models and textures they name load in the background. A cell
  is added only once all of that is ready, and at most one cell is added a frame, so the game does not stall.
- On the first frame, the cells round each source load straight away, so that nobody starts above missing ground.
- Far cells are taken out.
- **Stand-ins**: when the world is saved, each cell's Mesh Renderers are merged into one mesh in their colours, cut
  down to about 4,000 triangles, and written beside the cell. Cells within the Stand-in Radius that are not loaded
  show it instead, so that the distance is not empty. It is not drawn while the cell is loaded.
- **Floating origin**: far from the centre, floating-point positions lose precision (shaking cameras and physics).
  With Floating Origin set, once the first source is that far from the centre, every top-level object, physics body
  and character is moved back by whole cells. `scene.Streamer.Origin` holds how far the world has moved: a position
  in the scene plus `Origin` is where it is in the world as saved. The floating origin is off in a network session,
  as every machine must agree on positions.

## In the editor

- Opening a streamed scene loads only the cells round the view, and shows the stand-ins of the rest.
- **Window > World Map** (or the button under the World Streaming settings) shows the grid round the view: green is
  loaded, blue is not loaded, orange is taken out but not saved yet. Click a cell to load it, right-click to take it
  out. **Load Around View**, **Load All** and **Take Out All Far** do it for many cells at once.
- Loading or taking out cells starts the undo history afresh: an undo cannot reach across it.
- A cell taken out keeps its objects in memory until the next save, which writes them.
- Moving an object into a cell that is not loaded is fine: saving loads that cell first, so its file is written whole.
- Saving writes only the cells that are loaded, or held. The others are left as they are on disk. A cell left with no
  objects loses its files.
- Play mode streams as a built game does. Stopping puts the editor's cells back as they were.

## On disk

`World.tscene` holds the settings, what stays loaded, a `streamcell x z` line for each cell, and `nextid`. The cells
are in `World.cells/` beside it: `<x>_<z>.tcell` (the objects, in the scene format) and `<x>_<z>.standin.tmesh`. Keep
the folder in version control with the scene. Builds pack the cells (and what they name) with their scene.

A streamed scene is opened as the game's scene (`SceneManager.Load` or `LoadAsync`, or as the start scene). Loaded
additively into another scene, it brings only what stays loaded.

Code can reach the streaming through `scene.Streamer` (a `WorldStreamer`): `Cells`, `Loaded`, `Loading`,
`LoadAround(scene, position)`, `LoadNow(scene, key)`, `CellOf(scene, position)`, `Origin`.

## Test switch

`--world-streaming-test` builds a 5 × 5 world of 50 m cells and checks:

- saving it as cells, with stand-ins;
- opening it with no cells, then loading the cells round a point (ids and folders kept);
- new ids, and a cell taken out and saved;
- an object moved into a cell that is not loaded, and a cell left empty;
- playing with a Streaming Source walking across: the first frame, loading over several frames, taking far cells out,
  stand-ins, and the floating origin (with cells loaded after it moved, in folders and at the top).

It then puts the scene back, removes its files and logs `WORLD-STREAMING-TEST PASS` or `FAIL`.
