# ScrapWorkshop implementation checklist

This file is the durable progress record. A checked item means its stated evidence exists; implementation and play validation are separate.

- [x] Locate local Tessera engine and project format.
- [x] Create isolated ScrapWorkshop project; leave Steam files unchanged.
- [x] Import original wheel, driver seat, bearing, wood, metal, and concrete assets.
- [x] Record source assets in asset-manifest.json and retain original block definitions.
- [x] Implement flat workshop scene, editable starter chassis, grid placement/removal, material selection and collision rebuilds.
- [x] Implement assembly lift/release, height adjustment and recovery.
- [x] Implement initial raycast suspension, throttle, steering and brake.
- [x] Compile and resolve all errors (BeefBuild Debug completed successfully).
- [x] Run and visually inspect workshop (actual Vulkan/X11 scene; screenshots recorded).
- [x] Smoke-playtest block add/remove, lift release/recovery and starter driving; extended handling tuning remains.
- [x] Add versioned construction save/load; verify an actual process restart restores edits.
- [ ] Import and integrate original character, skeleton and movement animations.
- [ ] Import and integrate original tools and tool animations.
- [ ] Integrate original HUD artwork (current controls use temporary engine text).
- [x] Import and display original lift asset in a fixed pose; extension animation remains pending.
- [ ] Allow wheel, seat, bearing and engine placement with connectivity rules; current vehicle has fixed running gear.
- [ ] Validate vehicle assembly, materials, collision and camera after full import.
- [ ] Package local playable build and document remaining limitations.

## Resume

Project: `/home/zerker24/TesseraProjects/ScrapWorkshop`
Engine: `/home/zerker24/BeefProjects/Tessera`
Build: `BeefBuild -workspace=/home/zerker24/TesseraProjects/ScrapWorkshop -config=Debug`
Asset import: `python tools/import_assets.py`
Build log (initial): `/tmp/scrap-workshop-build.log`

Source and imports are saved on disk. Local execution pauses during system sleep; no automatic AI restart has been configured. Per-checklist ChatGPT app push notifications are not exposed by tools in this session.

## Building sandbox roadmap progress

- [x] Separate creation state, part definitions, player tools and temporary vehicle simulation.
- [x] Author the starter chassis, block children and tunable vehicle component in the editor scene.
- [x] Expose part mass/appearance, grid/reach/limits, lift/camera settings and palette in the Inspector.
- [x] Start new anchored creations by placing blocks on the ground.
- [x] Start supported creations on the lift and release them to physical simulation.
- [x] Split disconnected groups after removal, preserving individual ground/lift attachment state.
- [x] Add transactional grid-compatible block welding with overlap rejection.
- [x] Add per-block paint and a configurable six-color palette.
- [x] Pass 25 construction/physics integration checks and a 180-frame complete-scene headless smoke test.
- [x] Add editor/game launchers, validation script and editor workflow documentation.
- [x] Graphically smoke-test pointer placement, tool UI, split/weld/paint and starter driving.
- [x] Correct block paint-mask conversion, lift scale and rotation, seat forward direction and wheel axle orientation.
- [ ] Extended driving feel and original lift extension animation playtesting.
- [x] Implement and verify bounded undo/redo, validated saves, autosave, backup recovery and named blueprint save/import.
- [ ] Expand from the three block definitions to the original item catalog, attachment faces and rotations.
- [ ] Replace temporary vehicle running gear with placeable, connected mechanical parts.

Full ordered roadmap: [ScrapWorkshop roadmap](https://github.com/LazyAlgorithm/Tessera/blob/main/docs/projects/ScrapWorkshop-ROADMAP.md).

## Latest checkpoint (2026-10-16)

Actual scene now runs graphically through X11 and Wayland using Vulkan. Screenshots and direct input exercise ground placement/removal, split groups, grounded-weld rejection, successful welding, painting, lift release/recovery and starter driving. Extended handling evaluation remains pending. Local imported block diffuse maps now bake their original default color and alpha paint mask into an opaque texture, with provenance in asset-manifest.json. Lift scale corrected from 100 to 1; sideways lift rotation removed. Seat faces +Z; wheel art axles face outward consistently while supported and rolling. Art rotation/scale remain Inspector-editable.

Persistence milestone implemented: versioned checksum construction archives, complete-load validation before mutation, atomic Linux file replacement with previous-save backup, 30-second configurable autosave, startup recovery, named blueprints and bounded undo/redo transactions. Save/load, process restart, blueprint import and paint undo/redo have been exercised in the actual scene. Automated checks cover topology/paint/tuning round-trips, damaged and invalid saves, undo/redo splits, disk backups and wheel orientation. See README.md for controls and Validation/ for logs and screenshots. Headless validation does not read or write player saves.

Next milestone: expand the original placeable item catalog, including attachment and art-axis metadata, before actual mechanical assemblies. Original character, tools, HUD and lift extension animation remain pending. Imported game assets stay local; only progress documentation and selected gameplay screenshots are published.

[Selected gameplay screenshots and validation notes](https://github.com/LazyAlgorithm/Tessera/blob/main/docs/projects/ScrapWorkshop-PROGRESS.md).
