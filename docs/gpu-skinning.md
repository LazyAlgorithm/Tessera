# GPU skinning

Bending a rigged model's vertices to its skeleton every frame is most of what an animated character costs. With **GPU skinning** (on by default, the Skinned Mesh Renderer's **Gpu Skinning**) a compute shader does it on the graphics card, writing straight into the vertex buffer every pass draws from: the scene, shadows, the depth pass of screen effects, decals and custom material shaders all see the bent model, and none of their shaders needs a skinned version. The CPU only works out each joint's matrix, as before, and the model's box from its joints.

Crowds benefit most: a model of 5000 vertices costs the CPU about the same as one of 500.

Where the graphics card cannot run compute shaders (the web build, very old cards) models are bent on the CPU, as before, without anything to set. The log says which: `Skinning: on the GPU`.

## When to turn it off

With GPU skinning the bent vertices exist only on the graphics card; `Mesh.Vertices` on the CPU stays in the rest pose. Turn **Gpu Skinning** off for a model whose bent vertices code reads (cutting a mesh where it is hit, baking a pose). In the editor, clicking a character in the Scene view picks it by its rest pose.

`GpuSkinning.Enabled = false` turns it off for every model (a setting, or to compare); `--cpu-skinning` does it from the command line. The Inspector says, under a Skinned Mesh Renderer, whether its vertices are bent on the GPU or the CPU.

## Bounds

Without bent vertices on the CPU, the model's box (for culling, shadows and LOD) is made from its joints: each joint's box round the vertices it moves, at rest, moved with the joint. It always holds the model, a little loosely (`Tests/GpuSkinning` measures at most about one and a half times the exact box's volume for the sample).

## Networking

Nothing changes: clips and states are sent, not bones or vertices, and each machine bends its own models. A dedicated server bends nothing.

## Tests

`Tests/GpuSkinning` checks, without a graphics card, that the box from the joints holds the model as the CPU bends it at every moment of its clip without being much too big, and that GPU skinning is on by default but not used where it is not available. `python3 run.py` in that folder also draws the Sandbox sample's `Scenes/Skinning.tscene` (three models holding a pose) with GPU and with CPU skinning and checks that the GPU did the bending and that the two pictures are the same.
