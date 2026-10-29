# Soft bodies

A **Soft Body** (Add Component > Physics) makes an object's Mesh Renderer soft. Its mesh is simulated, vertex by vertex, as **Cloth** (a sheet that hangs, folds and blows: flags, capes, curtains, sails, tablecloths) or as **Jelly** (a closed shape that keeps its volume by pushing out: jelly, rubber balls, cushions, soft tyres). Jolt steps soft bodies on the job threads with the rest of the physics.

Soft bodies fall, fold over and rest on colliders, and they push rigidbodies and are pushed by them: a crate dropped on a jelly sinks into it and is held up. Characters walk through cloth and push it aside. Their sweep ignores soft bodies, and their inner body pushes them.

| Field | Meaning |
|---|---|
| Kind | Cloth or Jelly. |
| Mass | The whole body's weight in kilograms, shared by the vertices that are not pinned. |
| Stiffness | How hard it resists stretching: 1 barely stretches, 0 like elastic. |
| Bend Stiffness | How hard it resists bending: 0 folds freely (silk), 1 holds its shape (leather, rubber). |
| Pressure | Jelly: how hard the air inside pushes out, in pascals, whatever its size. 0 collapses, 200 a soft cushion, 600 jelly, 2000 a firm ball. |
| Damping | How fast it loses speed, like moving through thick air. |
| Friction, Bounciness, Gravity Scale | As on a Rigidbody. |
| Thickness | How far from its surface it keeps other things, in metres. |
| Wind Drag | How much Wind Zones push it (0 not at all). Wind blows on each face by how squarely it faces the wind. |
| Iterations | Solver passes each step: more is stiffer and costs more. |
| Pins | The vertices held to the object, by number (`0-12 40 41`). Painted in the editor. |
| Stiffness Map | Where it is softer than Stiffness says, by vertex (`12=0.5 13=0.25`). Painted in the editor. |

The mesh is simulated with its seams joined. A mesh splits a vertex where its texture or shading has a seam, and the simulation must not tear there. Vertex numbers in Pins and Stiffness Map count the joined vertices. The renderer draws a copy of the mesh that follows the simulation, with its normals and bounds updated every frame.

## Pins

Pinned vertices stay where they are on the object and move with it. Moving, turning or animating the object carries them, and the rest of the cloth swings after them. A cape is cloth pinned along its top edge on an object that is a child of the character's chest bone. A flag is pinned along one side to a pole, and a curtain along its top to a rail.

A soft body with no pins is free. It moves its object: the object's position follows the middle of the body. If a script moves the object, the body goes with it.

## Painting pins and stiffness

Select the object. Under the Soft Body in the Inspector are **Paint Pins** and **Paint Stiffness**. With one picked, the mesh's vertices show in the Scene view (pinned ones orange; with Paint Stiffness, soft ones red), and a brush follows the mouse over the mesh.

- **Paint Pins**: drag to pin vertices; Shift+drag unpins them.
- **Paint Stiffness**: drag to give vertices the Stiffness value on the brush; Shift+drag sets them back to the body's own.

Brush Size is a share of the mesh's size. A stroke is one step of undo. **Clear Pins** and **Clear Stiffness** start again.

## From code

```beef
let curtain = rail.AddComponent<SoftBody>();
curtain.pins.Set("0-10");        // the top row of an 11 x 11 sheet
curtain.windDrag = 2;

// After changing fields while playing:
curtain.Rebuild();

// Where its vertices are now, in the world:
for (let p in curtain.Positions) { ... }

// Put them somewhere (as many positions as SimulatedVertexCount):
curtain.SetPositions(saved);

// What it touched since this was last asked (physics body ids):
let touched = scope List<uint32>();
jelly.TouchingBodies(touched);
```

## Networking

Each machine simulates its own soft bodies. Pinned cloth follows its object, so when the object is networked (a player, a ship, a door), the cloth looks the same everywhere without sending anything about it. A free soft body on an object with a Network Identity is simulated on clients too, and each step it is drawn towards where the server has the object, or jumps there if it is more than 2 m away. Its shape is each machine's own, so squashing and wobbling can differ in detail.

## Limits

- Cloth does not tear, and soft bodies do not dent permanently. A squashed jelly always recovers.
- Pins hold vertices to their object, not to a bone directly. Put the soft body on an object parented to the bone.
- A soft body is one mesh: a Mesh Renderer's own mesh, a builtin or a model's. Big meshes cost more. Keep cloth to a few hundred vertices, and use a low-poly copy for something that only needs to wobble.
- Soft bodies do not collide with each other.
- A sleeping soft body is woken when a moving body touches it.
