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
- [ ] Run and visually inspect workshop.
- [ ] Validate block add/remove, lift and driving behavior.
- [ ] Add construction save/load so player edits survive restarts.
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
- [ ] Graphically validate pointer placement, tool UI, lift appearance and driving feel.
- [ ] Add undo/redo and durable construction save/load.
- [ ] Expand from the three block definitions to the original item catalog, attachment faces and rotations.
- [ ] Replace temporary vehicle running gear with placeable, connected mechanical parts.

Full ordered roadmap: [ScrapWorkshop roadmap](https://github.com/LazyAlgorithm/Tessera/blob/main/docs/projects/ScrapWorkshop-ROADMAP.md).

## Latest checkpoint

Creation foundation, splitting, initial welding and painting are implemented. Debug compilation passes without warnings. All 25 construction/physics integration checks pass; the complete authored workshop also runs headlessly for 180 frames. Tests exercise the same operations used by the building tools. The starter chassis, catalog definitions and vehicle tuning are editable in the scene.

Graphical verification remains pending: SDL cannot access X11 or Wayland from this execution environment. Mouse/keyboard feel, appearance and driving are not yet play-validated. Welding currently supports compatible block grids; supported sources must be released, grounded sources cannot be dragged, and the starter car's temporary running gear cannot move as a weld source. General placeable mechanics follow later. Original character, tool animations and HUD remain pending. Runtime edits are not yet saved between game launches.

Next milestone: construction persistence/recovery and undo/redo, followed by the original placeable item catalog and actual mechanical assemblies. No survival/game-mode work is planned.
