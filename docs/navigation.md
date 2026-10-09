# Navigation

Add Navigation Surface from Add Component > AI. Its position is the minimum corner of the bake volume; Size is its extent. Set cell size, chunk size, agent radius/height, maximum step and slope. Enable Flying for a 3D free-space grid. Walking samples the highest supporting floor at each X/Z cell; obstacles lower than Max Step do not block a cell, so the cells at the foot of a stair stay walkable. A flying agent is an upright capsule of Agent Height centred on the cell (a sphere when the height is twice the radius), so set the height to the craft's real height.

With the surface selected, the Scene view shows the bake volume as a box and, once baked or loaded, every walkable floor cell as a see-through blue overlay with a darker line on each side an agent cannot cross. A flight volume shows the free cells that touch something solid instead. A dimmer second box appears when the stored bake used different bounds from the current fields. Draw Navigation turns the overlay off; F frames the whole volume.

Click Bake & Save Navigation in the Inspector. The editor writes a binary `.tnav` asset (text assets from earlier builds still load, but have no diagonal links until baked again); the Baked Data field accepts a project asset. Baking uses a private Jolt query world and never starts gameplay. It includes active static colliders and, when enabled, static render meshes, including procedural RuntimeMesh geometry. Actors marked with NavigationAgent or Rigidbody are excluded, including their descendants.

Baked data loads in Awake. Leave Rebuild On Start disabled to avoid runtime baking. Enable it for a generated world, or call Bake after creating geometry. These methods work in standalone games.

Add Navigation Agent to an object and assign its Navigation Surface. Scripts can call `SetDestination(position, speed, stoppingDistance)` on the NavigationAgent and check `HasArrived` or `PathFailed`. Call `StopMovement()` to stop it.

NavigationAgent also supports script calls:

```beef
navigation.SetDestination(destination, speed, stoppingDistance);
if (navigation.PathFailed) { /* no reachable path */ }
if (navigation.HasArrived) { /* reached snapped destination */ }
navigation.StopMovement();
```

Snap Distance bounds how far endpoints can be moved to a usable cell. Arrival refers to that snapped endpoint. Base Offset is the offset from the object's origin to its feet for walking, or its center for flying. For a capsule whose object origin is one meter above its feet, use `(0, -1, 0)`. Agents without a Rigidbody follow the path directly; kinematic bodies follow their transforms. Dynamic Rigidbody agents receive horizontal velocity for walking, and three-axis velocity for flight, only while they are following a path: an idle, failed or arrived agent leaves its body's velocity alone, so it can be pushed or dropped. Walking agents measure waypoint and arrival distance on the ground plane. Turn Speed limits how fast Face Movement turns (0 turns instantly). Configure gravity appropriately for flying bodies. An agent whose object has a `CharacterController` walks its path through the controller instead, so it climbs steps and stays on slopes. A dynamic Rigidbody agent still depends on the body's own ability to get over steps.

## Changes and chunks

After changing or regenerating mesh geometry, rebuild the affected bounds:

```beef
surface.Rebuild(changedBounds);
```

Include both the old and new bounds when moving/removing geometry. Sampling expands to intersecting chunks, with neighboring cell links refreshed. A revision change makes agents replan. Otherwise an agent searches only when its destination changes or it is pushed off its path, never more often than Repath Interval; a failed search is retried about once a second. The Inspector's Rebuild Changed Chunks controls expose the same operation; SaveData persists runtime changes when desired. Runtime rebuilds do not save automatically.

Chunk sampling is local, and a rebuild copies only the geometry whose bounds reach the rebuilt chunks into its temporary collision world. This implementation does not stream collision geometry or load/unload navigation chunks. Rebuilds and path searches are synchronous, so large updates should be scheduled over successive frames. Grids are limited to one million cells.

## Path search

Paths are found with A* over the baked grid. Walking cells link to eight neighbours (four sides and four diagonals); flying cells link to all 26 neighbours. Every link was swept with the agent's shape at bake time, so a diagonal exists only where the agent fits. The cost of a step is its length, the estimate to the goal is the octile distance over the grid (exact in open space), and the open list is a binary heap. `FindPath` stops after a visit budget (200,000 cells by default) and sets `BudgetExceeded` when that, rather than a blocked route, is why it failed.

Cells are also labelled by connected region after each bake. A goal snaps to the nearest cell in the start's region within Snap Distance, and a goal with no such cell fails immediately without a search. An endpoint that lies inside a usable cell uses that cell, so a point beside a thin wall is not moved across it. The agent merges cells in a straight line into one leg; routes are still limited to the grid's 26 directions, not arbitrary angles.

## Current limits

This is a surface/volume grid implementation. Walking has one sampled height per X/Z cell, so overlapping floors, bridges with walkable space underneath, and caves need separate surfaces or a future layered mesh solution. Flying navigates all three axes. There are no off-mesh jump links, crowd avoidance, dynamic obstacle steering, any-angle path smoothing or streaming yet. Smaller cells improve detail at higher memory/bake cost; baked data is specific to the configured agent clearance.

CPU tests cover baking without Play, wall avoidance, saved-data loading in both formats, changed-chunk shortcuts, unchanged distant cells, diagonal 3D flight within a small search budget, unreachable regions, allocation bounds, replanning, arrival at snapped destinations, a flying agent, and a dynamic-body agent that is left alone when idle.
