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
- [x] Pass 55 construction/physics/material integration checks and a 180-frame complete-scene headless smoke test.
- [x] Add editor/game launchers, validation script and editor workflow documentation.
- [x] Graphically smoke-test pointer placement, tool UI, split/weld/paint and starter driving.
- [x] Correct block paint-mask conversion, lift scale and rotation, seat forward direction and wheel axle orientation.
- [ ] Extended driving feel and original lift extension animation playtesting.
- [x] Implement and verify bounded undo/redo, validated saves, autosave, backup recovery and named blueprint save/import.
- [x] Import 47 original base/Survival block definitions with stable IDs, source UUIDs and paged selection; verify all placements automatically and several through actual input.
- [x] Reconstruct local DIF paint-mask/ASG/normal/tiling materials; compile both shaders and inspect continuous planks and mask-preserving paint in the actual scene.
- [ ] Match exact original glass/refraction, reflections, normal convention and material response through reference comparison.
- [ ] Expand block-only occupancy into the original non-block item catalog, attachment rules and rotations.
- [ ] Replace temporary vehicle running gear with placeable, connected mechanical parts.

Full ordered roadmap: [ScrapWorkshop roadmap](https://github.com/LazyAlgorithm/Tessera/blob/main/docs/projects/ScrapWorkshop-ROADMAP.md).

## Latest checkpoint (2026-10-16)

Actual scene now runs graphically through X11 and Wayland using Vulkan. Screenshots and direct input exercise ground placement/removal, split groups, grounded-weld rejection, successful welding, painting, lift release/recovery and starter driving. Extended handling evaluation remains pending. The local material path now samples separate original diffuse/ASG/normal maps, uses masked absolute paint and applies definition tiling across adjacent cells. The first opaque texture bake remains a fallback; provenance is recorded locally. Lift scale corrected from 100 to 1; sideways lift rotation removed. Seat faces +Z; wheel art axles face outward consistently while supported and rolling. Art rotation/scale remain Inspector-editable.

Persistence milestone implemented: versioned checksum construction archives, complete-load validation before mutation, atomic Linux file replacement with previous-save backup, 30-second configurable autosave, startup recovery, named blueprints and bounded undo/redo transactions. Save/load, process restart, blueprint import and paint undo/redo have been exercised in the actual scene. Automated checks cover topology/paint/tuning round-trips, damaged and invalid saves, undo/redo splits, disk backups and wheel orientation. See README.md for controls and Validation/ for logs and screenshots. Headless validation does not read or write player saves.

Current continuation: oriented non-block geometry is implemented; placed-part mechanical examples now run, while remaining item families and extended mechanics tooling remain open. The 47-block catalog and reconstructed material path are implemented and checked as incremental catalog work; full catalog/mechanical milestones remain open. Latest validation: 55 automated checks, shader compilation and a 180-frame headless scene run. See MATERIALS.md for the shader/material investigation and exact fidelity limits. Original character, tools, HUD and lift extension animation remain pending. Imported game assets stay local; only progress documentation and selected gameplay screenshots are published.

[Selected gameplay screenshots and validation notes](https://github.com/LazyAlgorithm/Tessera/blob/main/docs/projects/ScrapWorkshop-PROGRESS.md).

The original baked texture conversion described above is retained as an opaque fallback/editor history. Runtime blocks now use separate original DIF/ASG/normal maps, original default paint and creation-local tiling. Actual-scene backup recovery and rejection of both invalid primary/backup saves were checked in an isolated save folder.

## Continuation: non-block geometry checkpoint

- [x] Shared multi-cell occupancy, grid rotations, attachment masks and whole-item selection/removal implemented.
- [x] Split/weld operations preserve oriented item geometry; archive version 3 preserves item rotations and occupied-cell budgets while accepting earlier archives.
- [x] Six original item candidates imported with source UUID, dimensions, sticky faces, mass and independent art corrections; reimport preserves editor overrides.
- [x] Geometry/catalog checkpoint: 69 automated checks and actual-scene placement of all six candidates, seat rotation and item-layout save/reload.
- [ ] Complete the remaining original item families and source hull collision.
- [ ] Validate actual placed-part mechanics and controls separately from catalog placement.

Mechanics continuation is in progress: native hinge/motor and round cylinder collision are implemented locally; physics integration checks exercise motor rotation, axle retention, assembly lift/recovery and graph persistence. Full driving/play validation is still underway. The original fixed rig remains in Main.tscene, with a separate MechanicalCar scene for the placed-part example.

## Placed-part mechanics checkpoint — 2026-10-16

- [x] Implement separate welded bodies across real bearing hinges, editable engine motors, round wheel collision and four spring suspension sliders.
- [x] Implement placed-seat throttle/brake/steering, seat→engine/controller and engine/seat/controller→bearing connections, and a single target-angle controller.
- [x] Preserve complete mechanical assemblies through lift/recovery, validated saves, blueprints and undo/redo.
- [x] Verify 98 automated integration checks, shader compilation and 180-frame Main scene smoke run.
- [x] Graphically smoke-playtest the separate suspended car: seat entry, throttle, steering, braking, recovery/camera follow and seat→engine tool wiring.
- [ ] Build an entire working car from scratch through actual tool input; check every wire/edit combination.
- [ ] Add controller sequencing, remaining item families and source hull collision.
- [ ] Extended handling, rough-terrain endurance, original suspension/lift deformation, character/tools/HUD and packaging.

Main retains the editable fixed prototype. MechanicalCar and MechanicalSuspensionCar are ordinary placed-part examples without PrototypeVehicle components. This checkpoint verifies a working mechanical increment, not the entire catalog or presentation roadmap. Details and local evidence: Validation/MECHANICS-2026-10-16.md.

## Connection editing checkpoint — 2026-10-16

105 automated checks, both shaders and the 180-frame Main smoke run pass. In Connect mode, aim at a mounted bearing and press I to reverse it; X clears an item's incoming control wires. The HUD identifies the incoming mode/direction. A new mode replaces competing bearing controls. Tests cover a placed controller reaching +22.5°, inversion reaching −22.5°, clearing wires and rejection across unrelated assemblies.

Actual-scene input verifies I inversion, X clearing and Ctrl+Z/Y undo/redo. The playtest exposed a stale HUD hover reference after undo replaced creations; selection/hover are now cleared during restore and the repeated graphical test passes. Controller sequencing and complete from-scratch vehicle assembly remain open.

- [x] Connection editing/inversion implemented, automatically checked and graphically verified with undo/redo.

## Controller programs and recovery checkpoint — 2026-10-16

125 automated checks, both shaders and a 180-frame Main smoke run pass. Placed controllers have an optional Inspector-authored four-angle program, configurable step count/timing/speed, looping and return-on-release. Seat W advances, neutral pauses and S reverses. Archives version 5 preserve per-controller programs, accepting versions 1–4. Graph/body rebuild checks guard reused native constraint addresses; duplicate control wires and invalid programs are rejected before mutation.

Actual isolated-scene playtesting confirms controller seat entry, arm playback, pause/reverse, recovery and save/reload. Recovery exposed quaternion-norm drift during repeated lift movement; normalized assembly rotations fix it, with 600 subsequent frames checked automatically. Nonfinite live archives now fail before primary/backup replacement. All example scenes have isolated save folders, and playtest.sh isolates user-data paths as well as enabling reliable scoped X11 automation.

Wheel definitions now expose a mounting point so actual bearing-output placement aligns the axle with the bearing rather than a footprint corner. This is checked automatically and through actual from-scratch placement. The complete user-built car, remaining item families/source hulls, extended handling, original character/tools/HUD and animated lift/suspension art remain open.

- [x] Optional controller sequencing implemented, automatically checked and graphically smoke-playtested in a separate editable bench scene.
- [x] Repeated-recovery rotation drift fixed; invalid live saves rejected; demo/player-data isolation added.

## From-scratch vehicle checkpoint — 2026-10-16

- [x] Build a complete working vehicle through actual catalog, keyboard and mouse input in an initially empty workshop.
- [x] Place 20 wood items, four bearings, four wheels, a driver seat and an engine; mount each wheel as a separate rigidbody group.
- [x] Wire seat→engine and engine→all four bearings through Connect; invert both left wheels through I.
- [x] Release, enter the seat, drive at 7.3m/s, brake, recover, save/reload and drive again.
- [x] Validate the saved result through the native read-only archive checker: five welded groups, 30 items and four mechanical links.

The saved construction and evidence remain in Validation/FromScratch/. No scene-authored creation or direct state injection was used for this build. The authored suspended car separately covers steering/spring behavior; controller programs have their own bench. Full manual steering/suspension assembly and every connection combination remain broader playtests.

Latest automated suite: 126 checks, both shaders and a 180-frame Main smoke run. The servo now wraps orientation error so a 270° target settles at its equivalent orientation instead of spinning indefinitely. The CLI `--check-construction-save PATH` checks archive checksum, catalog, topology, graph and program data without changing the scene or saves; it correctly rejects the preserved nonfinite incident sample.

## Original collision-shape checkpoint — 2026-10-16

132 automated checks, both shaders and the Main smoke run pass. The imported driver seat now uses its original eight collision vertices as a convex child in the creation compound, replacing the full occupied-cell box approximation. Wheel/bearing/suspension definitions use round cylinders; engine/controller use their source box dimensions. Logical occupied cells and attachment rules remain separate from physical hull detail.

Tests distinguish the seat's upper taper, upper center and wider lower volume, verify rotated collision, and confirm malformed/degenerate editable hulls fall back to cell collision. Definitions expose collisionHull, hullRotation, hullOffset and hullMargin. Reimport preserved Main's editable definitions byte for byte. This completes the six imported items' source primitive/hull path; it does not cover unimported families or every source compound-hull format.

Actual scene: the saved from-scratch car loaded, the source seat was aimed/selected and entered after release, the car drove at 6.6m/s, braked/recovered and saved a valid five-group/four-joint archive. Source-hull logs and images remain local under Validation/. Imported collision data also stays local.
