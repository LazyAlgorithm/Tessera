# Building maps in the editor

Tools in the Scene view and the **Map Builder** window for putting levels together from prefabs and models.

## Transform handles and snapping

- **W / E / R / T** pick Move, Rotate, Scale or **All** (all three handles at once). The toolbar has the same buttons.
- **Snap** (toolbar) makes the handles move, turn and scale in steps. The **v** button beside it sets the steps: move
  (default 0.25 m), turn (15 degrees) and scale (0.1). Holding **Ctrl** while dragging does the opposite of the Snap
  button, so with Snap off Ctrl still snaps, as before.
- While snapping, a small grid at the selection's foot shows the move step.
- **[** and **]** turn the selection by the turn step about the vertical axis.
- **End** (Edit > Drop to Surface) rests the selection on the highest surface under its footprint. Edit > Snap to
  Grid and Turn 90 Degrees are there too.
- The **height guide** is a line from the bottom of the selection to whatever is under it, labelled with the height,
  for placing things that float (pickups, rings, lamps). It can be turned off in the snap settings.
- **Camera speed** is in the snap settings; while flying (right mouse button held), the mouse wheel changes it.
  Panning and the wheel's dolly follow it, so small rooms and big outdoor maps both move at a usable pace.

These settings are kept between sessions (`map_builder.txt` in the editor's settings folder).

## Standing things on surfaces

Everything new is stood on what is under it rather than dropped at a fixed height:

- Dragging a prefab or model from Project into the Scene view stands it on the scenery, terrain or ground where the
  mouse points, with its lowest point on the surface.
- GameObject menu items put the new object on the surface in the middle of the view when there is one nearby.

Surfaces are the triangles of drawn meshes (anything with a Mesh Renderer), then voxel terrain, then the ground
plane at height 0.

## Map Builder window

Window > Map Builder (or the toolbar button) lists every prefab and model in the project, prefabs first, as
thumbnails, with a search box and a folder filter. A model that a prefab already places is not listed by itself:
the prefab is the one to use, with its materials and collision. The model is still in the Project panel.

Three built-in folders come first in every project:

| Folder | Pieces |
|---|---|
| Primitives | Cube, Sphere, Capsule, Cylinder, Cone, Plane, Quad |
| Walls | Wall 4 m, 2 m and 1 m, Half Wall 4 m, Doorway 4 m, Window Wall 4 m, Pillar (3 m tall, 0.2 m thick) |
| Floors | Floor 1 x 1, 2 x 2, 4 x 4 and 8 x 8 (0.2 m thick), Ramp 4 m (rises 1 m), Stairs 4 m (eight 0.25 m steps), Platform 2 x 2 |

Walls and floors are grey boxes with box colliders, for blocking out a level before the art is ready. Each is an
object with its origin at its foot (a wall's at the middle of its bottom edge, a floor's at its top) and the boxes
as children, sized in whole and half metres so they meet on the move step. Ramps and stairs rise towards +Z. Tint
or replace them like any other object.

- **Click a tile** to start placing it: a box the size of the asset follows the mouse over the scenery; each click in
  the Scene view places one. **[** and **]** turn the next one. **Esc**, *Stop placing* or clicking the tile again
  ends placing. Tiles can also be dragged into the Scene view or the Hierarchy.
- **Random turn**, **Turn to surface** (stand it along the surface's slope instead of upright) and **Random scale**
  (between the two numbers) apply to every placed object.
- **Inside the selected folder** puts new objects in the selected Hierarchy folder (or the folder of the selected
  object), so a map can be kept in groups as it is built.
- **Selection** tools: Drop to surface, Snap to grid, Turn 90, Upright (keep only the turn about Y), **Array** (that
  many copies, each a step X Y Z further and a turn further than the one before: fences, shelves of books, rows of
  desks) and **Scatter copies** (copies dropped onto the surfaces within a radius around the selection, each turned at
  random: clutter, rocks, toys).

## Playing it in the game

File > Export Scene as Map... writes the scene as a `.tmap` file into the game's `Maps` folder (and each build's), where
a game that looks for maps lists it without being built again. See [Maps](maps).

## Quick Add

Press **Space** over the Scene view to search everything that can be added: the built-in objects of the GameObject
menu, every prefab and model in the project, and an object with any component (engine or game script). Enter takes
the first match. It is placed on the surface under the mouse.

The GameObject menu itself also has **Prefabs** and **Models** submenus (one per folder) and **With Component**, an
empty object carrying the chosen component, by category.

## Gizmos

- The selection is boxed even when its pictures are on child objects (prefab instances).
- Components draw their own guides with `OnDrawGizmos(bool selected)`; game scripts can too. For example a race
  game's gate component can draw the course in order, as Tumble Toys: Aviation's `RingPoint` does.

## Checking it from the command line

`--map-builder` opens the window, and `--map-builder-search <text>` fills its search box. `--camera "x y z yaw pitch"`
puts the Scene view's camera there, for screenshots. `--map-builder-test` drops a cube onto what is under the scene's middle (looking
down from `--map-builder-height`, 50 m by default, so a room can be tested from inside), stamps a prefab
(`--map-builder-asset <path>`, or the first prefab in the project) on top of it, makes an array and a scatter, and
logs `MAP-BUILDER-TEST PASS` or `FAIL`. `--map-builder-preview` leaves the placement preview showing in the middle of
the view, for a screenshot taken with `--frames N --screenshot file.png`.

## Limits

- One object is selected at a time, so arrays, scatter and drop work on one object (with its children).
- Surface tests use drawn triangles, not colliders: an invisible collider is not a surface to stand things on.
- Placing with **Turn to surface** puts the object's pivot on the surface, so it suits models whose pivot is at
  their foot; upright placing uses the drawn bounds and works for any pivot.
