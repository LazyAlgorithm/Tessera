# How draws are batched

Opaque objects that share a mesh and a look are drawn as one instanced draw call. The renderer sorts the frame's objects by a key (`RenderView.MakeKey`): the mesh, then the material if the renderer has one, otherwise its texture, flat shading, unlit and glow. Each run of equal keys is one draw.

- **Metallic and roughness don't split batches.** Renderers without a material carry their own metallic and roughness in each instance. They go in the bottom row of the instance's world matrix, which is always (0, 0, 0, 1); the shaders rebuild it (`vs_mesh.sc`, `vs_shadow.sc`, `vs_depth.sc`). So 10,000 cubes with 10,000 different metallic/roughness values draw like one material: 1.5 ms, down from 14.9.
- **See-through objects** are drawn back to front. Neighbours in that order that share a key are one instanced draw. Instances blend in order, so the result is the same. 1,000 see-through cubes: 1.6 ms to 0.3 ms.
- **Culling first:** objects out of view that cast no shadow are skipped before their reflection probe and batch key are worked out.
- A different texture, material, reflection probe, lightmap or mirroring (negative scale) starts a new batch.

A custom shader built from the `fs_mesh.sc` / `vs_mesh.sc` templates gets the instance values in `v_surface` (x metallic, y roughness, z 1 when present). Draws with a material always use the material's uniforms.
