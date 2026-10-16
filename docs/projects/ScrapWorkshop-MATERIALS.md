# Original material reconstruction

The original game's installed `Data/Render/Materials/block_materials.json` enables ASG and normal textures, custom tiling and texture arrays. It defines separate alpha and glass passes with refraction/transmission parameters. The `.rend` files for the wheel, seat, bearing and lift likewise reference diffuse, ASG and normal maps. Original block definitions contain default paint colors and tiling spans. These files were inspected locally; their artwork and definitions are not published.

The first prototype used only DIF and repeated a complete texture on every quarter-meter cell. Baking a default color into that texture made blocks visible but was an approximation; multiplying paint over that bake also gave incorrect paint colors. Those deficiencies were visible in the first screenshots.

## Implemented in Tessera

- Lossless local PNG imports preserve separate original DIF/ASG/NOR channels. Their provenance is in `References/block-material-manifest.json` and `References/part-material-manifest.json`.
- `src/Shaders/OriginalBlock.tshader` projects UVs in creation-local grid coordinates and uses the original definition's tiling span, so adjacent blocks share texture scale and moving creations retain their textures.
- DIF alpha masks paint versus fixed texture detail. Unpainted blocks use the original definition's default color; painted blocks use the selected absolute color. An explicit paint flag distinguishes white paint from the original unpainted color. Version-2 saves preserve it; version-1 saves remain readable.
- ASG channels drive configurable opacity, specular response, emission and inverse-gloss roughness. This is a reconstructed response, not a verified byte-for-byte match of the original game's lighting equations. Normal maps use Tessera's tangent-space material path; exact original normal convention still needs reference comparison.
- `OriginalPart.tshader` uses the imported mesh's own UVs for existing wheel/seat/bearing/lift materials. The preview seat uses the installed creative driver's-seat default orange tint; the mesh itself is the retained legacy import.
- Every material is an ordinary `.tmat` asset editable in Tessera. Definitions expose material path, original default paint, texture tiling and art corrections. Existing `.tmat` files and scene overrides survive reimport. `python tools/import_assets.py` now imports the complete block catalog and all companion maps.

Tessera shader-template fixes, kept local: `Engine/shaders/vs_mesh.sc` now forwards the custom vertex `uv` variable; previously it discarded it. `fs_mesh.sc` exposes a dielectric specular-level input with default 1, retaining the standard behavior for shaders which do not override it. Before-edit copies are in `Validation/Checkpoints/`. Compiled custom shader binaries stay local under `src/Shaders/Compiled/`. Both `run.sh` and `validate.sh` compile the shaders with Tessera's own compiler.

## Verification and remaining differences

The actual Vulkan scene visibly shows continuous wood planks instead of a full texture repeated on each block. Direct-input blue paint preserves the grain/detail. Orientation is checked on the lift and while driving. The block catalog has 47 original base/Survival definitions; several catalog selections were placed and inspected, and all 47 are automatically checked for placement and save identity. This does not establish visual fidelity of every individual material.

Glass is currently alpha blending, with an editable opacity approximation. Original refraction, exact specular/gloss calibration, metal profiles, normal-map handedness, matching environment reflections, original color grading and broader material-by-material comparisons remain pending. Original lift extension animation is also pending. Imported assets remain local.

For background, [this original frame analysis](https://steamcommunity.com/sharedfiles/filedetails/?id=2097314062) directly examines the game's normal/ASG buffers and lighting/transparency passes. A newer [shader reconstruction toolchain](https://github.com/TechnologicNick/scrap-mechanic-shader-toolchain) documents recovering compiled shader behavior; its documented reconstruction workflow requires Windows. No recovered original shader source has been claimed or published here.
