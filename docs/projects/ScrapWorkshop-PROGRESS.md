# ScrapWorkshop progress — 2026-10-16

The actual Tessera scene now runs through X11 and Wayland with Vulkan. Building, lift release/recovery, splitting, welding, painting and starter driving received a direct-input graphical smoke test. Implementation, automated checks and playtesting remain distinct in the [checklist](ScrapWorkshop-CHECKLIST.md) and [roadmap](ScrapWorkshop-ROADMAP.md).

## Corrected art orientation and block materials

Block diffuse alpha is an original paint mask; local import now bakes its default block color into an opaque texture. The lift scale is corrected and its extra sideways rotation removed. The seat faces the vehicle's +Z forward direction. Left/right wheel art axles face outward and retain their facing while rolling. Vehicle art rotations and scales are Inspector-editable and survive saves. Up/Down adjusts lift height without also panning the camera.

![Supported starter with corrected seat, wheels and upright fixed-pose lift](screenshots/ScrapWorkshop-lift-upright-raised-final.png)

The lift art remains a fixed pose following the support height; ground-to-platform extension animation is still pending.

![Actual starter driving after orientation correction](screenshots/ScrapWorkshop-corrected-driving-final.png)

## Construction transactions and recovery

Versioned checksum archives retain creations, grid cells, materials, paint, world poses, motion, anchors, support state and prototype tuning. Loads validate the complete archive before replacing constructions. Local file saves replace atomically on Linux and retain a previous-save backup. Autosave, startup recovery, named blueprint save/import and bounded undo/redo are implemented.

Automated checks exercise the real construction operations and persistence failure paths. Actual-scene checks include F5/F9 save/load, a process restart restoring edits, named blueprint save/import and Ctrl+Z/Y paint undo/redo. The headless suite disables player-save access.

![Successful weld observed through actual tool input](screenshots/ScrapWorkshop-weld-second.png)

![Paint redo in the actual scene after save/restart validation](screenshots/ScrapWorkshop-redo-confirmed.png)

## Remaining work

Extended driving evaluation, the original item catalog with attachment/art-axis metadata, placeable mechanical assemblies, original player/tool/HUD integration, lift extension animation and packaging remain. Blueprint import currently uses the saved world pose and may overlap unrelated constructions. Paint uses a tint over baked default block colors; exact original shader behavior remains pending.

Only progress documentation and selected rendered gameplay screenshots are published. Imported source game models, textures, definitions and local gameplay source remain local.

## Latest catalog and material checkpoint

55 automated checks, both custom shader compilations, and a 180-frame headless scene run pass. All 47 base-game/Survival block definitions retain stable IDs and source UUIDs; the catalog is paged and editor-editable. Placement of every catalog block is checked automatically; several selections were placed through actual input. General non-block occupancy/attachment rules remain pending.

The earlier baked textures shown above have now been superseded for runtime materials. Original DIF/ASG/normal channels stay separate, paint follows the diffuse mask, and texture tiling spans adjacent blocks in creation coordinates. The existing wheel/seat/bearing/lift preview meshes also have companion-map materials. This is a reconstructed material response, not verified pixel parity with the original game. See [material investigation and remaining differences](ScrapWorkshop-MATERIALS.md).

![Reconstructed materials with original tiling and companion maps](screenshots/ScrapWorkshop-materials-final.png)

![Blue paint retains the original wood detail through its paint mask](screenshots/ScrapWorkshop-paint-mask-final.png)

![Paged original block catalog in the actual scene](screenshots/ScrapWorkshop-catalog-materials-final.png)

Actual-scene recovery was additionally checked in an isolated save folder: a damaged primary successfully loaded its valid backup; two invalid copies left the live workshop intact and paused autosave. Version-2 saves preserve explicit white paint separately from an original default color; version-1 saves remain readable. Exact specular/gloss calibration, original normal convention, glass refraction and environment reflections remain open.
