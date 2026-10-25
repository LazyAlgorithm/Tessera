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

## Straight paths

With **Smooth Path** (on by default) an agent goes straight wherever it can, at any angle, instead of along the grid's eight (or 26) directions: each point of the path is joined to the farthest later point it can see. A straight leg is allowed only where every point of it lies among usable cells that the bake linked to each other, so it keeps the same clearance from walls as the grid does, and (walking) only where the floor stays close to the line, so a long leg does not cut through a hill. Corners are kept where they are needed. `NavigationData.Smooth(path)` does the same for a path from `FindPath`.

## Jumps, ladders and teleporters: Navigation Links

A **Navigation Link** (Add Component > AI) is a way across that the grid does not have: a gap to jump, a ledge to drop off, a ladder, a teleporter, a door. It runs from its object to **End** (relative to the object, drawn in the Scene view as an arc). Each end must be within **Snap Distance** of a usable cell; the Inspector says whether both are, **Drop Ends to Ground** puts them on the floor below, and **End at View Centre** moves the end to where the Scene view's camera looks.

- **Kind**: **Jump** (an arc **Jump Height** above the higher end), **Climb** (straight there at a steady pace), **Teleport** (at once) or **Walk**. **Duration** is how long crossing takes.
- **Bidirectional**: off, agents only go from the object to End (a drop they cannot climb back up).
- **Cost Multiplier**: crossing costs the link's length times this, so a high value makes agents use it only when the way round is much longer.

Agents use links when they are the shorter way (turn **Use Links** off on an agent that cannot jump). While crossing, the agent moves itself (through its Character Controller or Rigidbody when it has one) and its `IsCrossingLink` and `CurrentLink` say so; `OnLinkStarted(link)` and `OnLinkFinished(link)` are for playing a jump or climb animation. `FindPath(from, to, path, legLinks)` returns, for each leg, the id of the link it crosses (`NavigationSurface.LinkOf(id)` is the component), or -1.

## Moving obstacles: Navigation Obstacles

A **Navigation Obstacle** marks something that moves and that agents must keep out of: a crate, a car, a gate. Its **Shape** is a box or an upright cylinder of **Size** (in metres, whatever the object's scale; **Fit to Object** sizes it to what the object draws), offset by **Center**. Objects with one are left out of bakes.

- **Carve**: while it stands still, it cuts its shape (plus the agents' radius) out of the grid, so agents plan paths round it, and a path that only went through it fails. With **Carve Only Stationary** (the default) it carves once it has stood still for **Stationary Time**, and while it moves the hole is filled in and agents steer round it instead (see Avoidance); this keeps a moving obstacle from making every agent plan again each frame.
- Off: it is never carved, only steered round.

Carved cells are shown red on the selected surface. In the editor an obstacle is shown carved where it stands.

## Costly and forbidden ground: Navigation Areas

A **Navigation Area** is a box (**Size**, centred on its object) whose cells cost **Cost** times their length to cross: mud, water, a room with a guard. Agents go round it when the way round costs less, and through it when it does not. **Blocked** makes it a place agents never enter. Areas are shown purple (blocked: red) on the selected surface.

Obstacles, areas and links are put on the grid by the surface when any of them changes (each frame it checks), and agents plan again. They are not saved in the `.tnav` asset: they come from the scene.

## Avoidance

With **Avoid Others** (on by default) an agent steers round other agents on the same surface and round obstacles that are not carved (moving ones): each frame it picks, from velocities near the one it wants, the closest that does not run into anything in the next second and a half and that stays on the surface. Two agents meeting each take half the turn; one with a lower **Avoidance Priority** gives way more to one with a higher priority. **Radius** is how wide the agent is for this. Agents that are pushed far off their path by others plan again.

## Queries

```beef
let data = surface.Data;
if (data.SamplePosition(point, 2, let onFloor)) { /* the nearest usable point within 2 metres */ }
if (data.RandomPoint(center, 10, random, let goal)) agent.SetDestination(goal, 3, 0.2f);   // wandering
if (!data.Raycast(eyes, target, let blocked)) { /* an agent could not walk straight there; it stops at blocked */ }
```

`RandomPoint` picks only points reachable from the centre. `NavigationAgent.RemainingDistance` and `Velocity` say how far it still has to go and how fast it means to move; selected in play mode, an agent draws its path (link legs in orange).

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

## Multiplayer

Navigation runs on the server (and in single-player games): agents find paths and move there, and their objects' positions reach the other machines like any moving object's. A client's copy of an agent does nothing by itself. Links, obstacles and areas are read from the server's scene; `OnLinkStarted` and `OnLinkFinished` happen on the server, so an animation played from them should go through an Animator (whose state is sent) or a network event.

## Current limits

This is a surface/volume grid implementation. Walking has one sampled height per X/Z cell, so overlapping floors, bridges with walkable space underneath, and caves need separate surfaces (joined with Navigation Links) or a future layered mesh solution. Flying navigates all three axes. There is no streaming yet. Avoidance is local steering between nearby agents, not a planner for large crowds: very dense groups in narrow corridors can still jam. A link that is a shortcut (a teleporter) makes the search's estimate too low, so a search through one can visit more cells than usual. Smaller cells improve detail at higher memory/bake cost; baked data is specific to the configured agent clearance.

CPU tests cover any-angle smoothing (straight in the open, keeping its clearance round a wall), raycasts, SamplePosition and RandomPoint, carving obstacles (blocking, a smaller one walked round, freeing the cells, carving only when still), costly and blocked areas, links (joining an island, one-way, the jump arc, an agent jumping across with its events, agents that may not use links) and two agents passing each other with avoidance, as well as baking without Play, wall avoidance, saved-data loading in both formats, changed-chunk shortcuts, unchanged distant cells, diagonal 3D flight within a small search budget, unreachable regions, allocation bounds, replanning, arrival at snapped destinations, a flying agent, and a dynamic-body agent that is left alone when idle.

The Sandbox sample's `Scenes/Navigation.tscene` has wandering agents, a wall, a mud area, a crate a looping sequence moves back and forth, and a jump link to an island (`Sandbox --scene Scenes/Navigation.tscene`; in the editor, `--bake-navigation` bakes the scene's surfaces on load to show the grid).
