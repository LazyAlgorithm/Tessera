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
