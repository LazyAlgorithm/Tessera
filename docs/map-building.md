# Building maps in the editor

Tools in the Scene view for putting levels together from prefabs and models. (The Map Builder window that was here is gone: building maps from pieces belongs in a game's own map editor, which the engine's `MapPieces` supports. See Maps players make.)

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

These settings are kept between sessions (`map_builder.txt` in the editor's settings folder, named for the window they began in).

## Standing things on surfaces

Everything new is stood on what is under it rather than dropped at a fixed height:

- Dragging a prefab or model from Project into the Scene view shows it there, standing on the scenery, terrain or
  ground where the mouse points with its lowest point on the surface, until you let go (see [Dragging](drag-and-drop)).
- GameObject menu items put the new object on the surface in the middle of the view when there is one nearby.

Surfaces are the triangles of drawn meshes (anything with a Mesh Renderer), then voxel terrain, then the ground
plane at height 0.

## Maps players make

Maps that players make and share (`.tmap` files) are made in the game, by a map editor the game provides, which can
use the engine's built-in pieces (`MapPieces`). If the game
has a `MapRules.txt`, such as "at least 4 Spawn Points", saving a scene in the editor warns when it does not meet
them yet, so the game's own levels stay playable as maps. See [Maps](maps).

## Quick Add

Press **Space** over the Scene view to search everything that can be added: the built-in objects of the GameObject
menu, every prefab and model in the project, and an object with any component (engine or game script). Enter takes
the first match. It is placed on the surface under the mouse.

The GameObject menu itself also has **Prefabs** and **Models** submenus (one per folder) and **With Component**, an
empty object carrying the chosen component, by category.

Quick Add also lists the engine's built-in pieces, for blocking out a level before the art is ready:

| Folder | Pieces |
|---|---|
| Primitives | Cube, Sphere, Capsule, Cylinder, Cone, Plane, Quad |
| Walls | Wall 4 m, 2 m and 1 m, Half Wall 4 m, Doorway 4 m, Window Wall 4 m, Pillar (3 m tall, 0.2 m thick) |
| Floors | Floor 1 x 1, 2 x 2, 4 x 4 and 8 x 8 (0.2 m thick), Ramp 4 m (rises 1 m), Stairs 4 m (eight 0.25 m steps), Platform 2 x 2 |

Walls and floors are grey boxes with box colliders. Each is an object with its origin at its foot (a wall's at the
middle of its bottom edge, a floor's at its top) and the boxes as children, sized in whole and half metres so they
meet on the move step. Ramps and stairs rise towards +Z.

## Gizmos

- The selection is boxed even when its pictures are on child objects (prefab instances).
- Components draw their own guides with `OnDrawGizmos(bool selected)`; game scripts can too. For example a race
  game's gate component can draw the course in order, as Tumble Toys: Aviation's `RingPoint` does.

## Checking it from the command line

`--camera "x y z yaw pitch"` puts the Scene view's camera there, for screenshots taken with `--frames N --screenshot file.png`.

## Limits

- One object is selected at a time, so Drop to Surface works on one object (with its children).
- Surface tests use drawn triangles, not colliders: an invisible collider is not a surface to stand things on.
