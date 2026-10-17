# ScrapWorkshop implementation checklist

## Three-axis ramps and suspension visuals — 2026-10-16

- [x] Preserve wedge dimensions when switching drag planes with Q/Shift+Q. Keep holding left mouse to adjust width, height and depth in one placement; release once. Display all three dimensions, keep one continuous sloped collider and one undo transaction.
- [x] Test actual mouse input building a 16×16×16 ramp, save/load validation, complete undo/redo and no early placement; all 20 drag-test archives validate. Inspect `Validation/ui-drag-wedge-volume-placed.png`; evidence `Validation/volume-drag-ui-validation.log`.
- [x] Import both original suspension compression poses from each renderable's pose0 mesh. Align pose vertices to rest topology, deform per-instance geometry/normals from measured native slider travel, and retain original materials. Correct suspension art orientation so the fixed end faces its host. Original Steam files are unchanged.
- [x] Verify all four car suspension meshes move with actual slider travel and return exactly to rest; verify the offroad part uses its own longer compression pose. Compile, shaders and 304 native checks pass; the existing vehicle rightward-steering check still fails (`Validation/volume-suspension-final-validation.log`). Headless smoke run passes separately.
- [ ] Compare suspension animation visually against original-game motion, including extreme travel and source-pose correspondence at seams. Exact original physics, damping and steering parity remain open. Updated source build is compiled; distribution packaging remains blocked by the recorded steering test.


This file is the durable progress record. A checked item means its stated evidence exists; implementation and play validation are separate.

## Development resumed — user request, 2026-10-16

The user resumed the creative port and requested completion of the work list. Prior pause/handoff details remain in local `RESUME.md`. At resume, bearing/connection and occupied-cell indexing changes pass 198 native checks and headless smoke validation but are not yet packaged or graphically verified. A 4,096-cube headless benchmark is recorded in Validation/scale-indexed.log; broader large-map and articulated physics support remains pending. Prior packaged-player crash in BuildCreation.At called by WorkshopUi.Draw requires a hover-reference regression fix before another manual-test package.

## Drag building, catalog and mounting increment — 2026-10-16

- [x] Drag-place and drag-remove rectangular surfaces up to 16×16 cells. Preview before release, preflight placement overlap/attachment/limits, rebuild once and record one undo transaction per gesture.
- [x] Drag a continuous wedge with dimensions up to 16 per axis, rotated placement, true sloped convex collision, material tiling and version-eight dimension persistence. Wedge occupancy reserves its bounding grid.
- [x] Verify actual mouse gestures in a separate nested display: 256-block floor, 256-block wall, one 16×1×16 wedge, 256-block removal, and undo/redo. All 16 captured archives validate (`Validation/drag-ui-validation.log`).
- [x] Add 45 original wedge materials and 108 static parts, bringing the catalog and icons to 214 entries. Native checks load their geometry/materials and instantiate physics. Fourteen unsupported source candidates remain recorded in `References/build-import-pending.json`; static props do not acquire unimplemented interactive behavior.
- [x] Restore switch/button source mount offsets so their bases sit flush against the host face. Require solid hosts on both sides of mechanical links and reject direct bearing-to-suspension mounting. Re-author the suspension example with solid carriers and a fresh `MechanicalSuspensionCar-v2` save profile.
- [x] Add original building bindings: left-drag place, right-drag erase, Q/Shift+Q rotate, Q during drag changes plane, I inventory, wheel hotbar and Alt+wheel zoom. Tab/T remain aliases.
- [ ] Complete original character first/third-person movement, camera and tool behavior, exact rotation-set ordering, full bearing face identity, and original-game comparison. Feature parity is not complete.
- [ ] Resolve the suspension vehicle's directional steering integration check. The latest native run passes 293 checks but fails expected rightward displacement; forward propulsion and both steering target angles pass. Manual source build launched for testing while this is investigated.
- [ ] Verify new static-part cutout/transparency materials and broader large articulated-map performance. Existing small-part and block-surface tests do not establish these limits.

## Logic system increment

- [x] Open pointed gate/timer settings with E or U. Add the original six gate modes, original gate skins/icons, timer seconds/ticks sliders, single-tick adjustments and input-disconnect controls. Switch E toggles and button hold/release are live interactions.
- [x] Evaluate synchronous logic at 40 Hz independently of 60 Hz physics: each gate adds one tick, timers add their configured 0–2400 ticks plus the propagation stage. Preserve one-tick pulses, falling edges and feedback-loop timing; avoid same-tick cascades.
- [x] Wire switches/buttons/gates/timers to gates, timers, engines and controllers. Repeating a wire removes it, right-click clears logic inputs, and active output rings/glow provide feedback. Reject duplicates, self-wires, extra timer inputs and unrelated assemblies; drop stale/split wires during evaluation.
- [x] Preserve modes, delays, wiring, switch states and timer queues in saves, blueprints and history. Verify exact timer continuation after restore and gate-setting undo/redo.
- [x] Add Logic Workbench to the workshop menu and package checks: two switches, button, AND/OR, timer, engine and independently driven wheel, with a controller available for further wiring.
- [x] Pass 269 native construction checks, including real engine activation/stop and controller advance/return, plus custom shaders and headless smoke checks (`Validation/logic-validation.log`).
- [x] Verify actual E settings interaction, gate-mode selection, timer adjustment and undo/redo through process-scoped X11 events inside a separate nested display. Five saved archives validate; screenshots are in Validation/ui-logic-settings.png, ui-timer-settings.png and ui-interact-settings.png. Evidence: Validation/logic-ui-validation.log.
- [ ] Compare exact lift/reset behavior and native original timing with instrumented original-game play. The installed scripts verify 40 Hz; an independent simulator's primary documentation supports two-phase one-tick gate propagation. Documented tests validate the port's chosen behavior, not the original binary's internal implementation.
- [ ] Import/integrate sensors and remaining interactive parts individually; measure dense large-circuit performance and original animation/display parity. See local LOGIC.md for current scope and controls.

## Lift ground-fastener correction

- [x] Keep all eight original lowerpike ground spikes rigid with the grounded lower lift assembly. They were incorrectly treated as telescoping rods; remove their extension weights and normal stretching.
- [x] Verify every one of the 208 spike vertices remains identical at rest, two meters of extension and five meters of extension. Platform motion, ground elevation and support-collider checks still pass.
- [x] Compile and pass 228 native construction checks, both custom shaders and headless smoke validation (`Validation/lift-fasteners-validation.log`).
- [ ] Confirm the corrected fasteners visually in the editor or next packaged manual session; exact original extension-animation fidelity remains open.

## Latest verified increment — bearing faces, editor linking and block surfaces

- [x] Persist the project-local UI font library in `project.tessera` so editor regeneration retains it. Regenerate through `Tessera.Editor.Project.WriteBuildFiles` and compile the regenerated workspace successfully (`Validation/editor-regenerated-build.log`). No shared engine edits.
- [x] Make the suspended, placed-part car the default for source/editor and future packaged tests.
- [x] Mount new bearings at a shared block face without a block-sized spacer; preserve separate bodies and native hinges. Use the actual thin plate collision, including bearing-only intermediate carriers. Correct the default suspension demo's wheel and steering offsets.
- [x] Add direct thin-plate selection with rim tolerance, independent of rounded compound-collider cell picking; support right-click removal in Build mode, retaining right-drag orbit and X removal. Native ray hit/miss checks pass; actual pointer removal still needs play validation.
- [x] Cull hidden opaque cube faces, greedily merge equal-paint surfaces in 16-cell chunks, preserve paint/material seams, reuse unchanged geometry, and merge box collision cells into exact cuboids. Dedicated checks cover adjacent blocks, paint, unchanged rebuilds and a 16×16 wall. Existing source hulls and mechanical tests pass.
- [x] Pass 226 construction integration checks, custom shader compilation and headless smoke validation (`Validation/bearing-face-validation.log`).
- [x] Benchmark 4,096 cubes: 25 ms placement, 6 ms rebuild, 16 rendered quads in 4 chunks, 1 collision box, 15 ms capture/validation, 600 stable physics ticks in 426 ms (`Validation/scale-meshed.log`). These CPU measurements do not establish graphical FPS or large articulated-map capacity.
- [ ] Graphically verify bearing removal and flush wheel/steering mounts in the next build. Existing saved constructions and other older example layouts retain their authored body poses; migrate/re-author them without silently changing saved motion/anchors.
- [ ] Complete separate face-attachment identity/occupancy for bearings, including several bearings on different faces of the same host block. The current archive still identifies a bearing by a logical grid address; physical spacing is corrected but data-model parity is unfinished.

## Current creative priorities — user requests

Keep the world flat and prioritize creative building before survival/challenge features. These items are requested work, not completed features.

- [ ] Fix lift ground contact and original-style extension: base stays on the ground, moving platform and mechanism follow height changes, and support/collision/save/history agree.
- [ ] Replace the simplified controller dialog/program with the original-style bearing matrix, connection ordering, frame zero plus ten steps, angle editing, speed, loop and activation behavior.
- [ ] Add and integrate the original part catalog one part/family at a time, recording geometry, attachment rules, materials, behavior, UI and verification for each addition. Importing a model alone does not complete a part.

- [ ] Import and integrate the original character with first/third-person movement: walking/running, jumping, grounded collision, camera switching/obstruction, tool use/animations and seat entry/exit. Compare original movement and camera behavior through actual play; keep the world flat.

- [x] Drag-build rectangular block surfaces, including a full 16×16 wall, with a placement preview, attachment/overlap validation and one undoable transaction per drag.
- [x] Add draggable wedges with rotation, correct attachment/collision geometry and save/load support; verify their drag behavior through actual building input.
- [x] Add usable logic parts and wiring: switches/buttons, configurable logic gates and signal propagation into supported interactive parts; preserve circuits in saves, blueprints and undo/redo.
- [ ] Match original bearing behavior and interaction: face placement and moving-body attachment, free hinges, drag wiring, visible colored connection dots/lines/direction arrows, right-click reversal, engine drive/braking, seat steering and controller sequencing. Study original handbook and installed scripts; verify each behavior separately rather than claiming full parity from a working car.
- [ ] Playtest these building tools together in the flat creative world and record evidence before marking them complete.
- [ ] Support thousands of blocks and very large creative maps: benchmark placement/removal/drag batches, rendering, memory, save/load and spatial queries; improve limits and architecture based on measured bottlenecks.
- [ ] Stress-test creation physics with large welded bodies, multiple moving creations and articulated vehicles; check collisions, joints, lift/recovery, splitting/welding and long-running simulation. Record actual block/body/joint counts, frame/tick timings and stability limits; do not claim issue-free physics from small examples.


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
- [x] Integrate original creative hotbar/inventory/palette/menu artwork, item icons and fonts; full-game screen parity remains open below.
- [x] Import and display original lift asset in a fixed pose; extension animation remains pending.
- [x] Allow wheel, seat, bearing and engine placement with connectivity rules; separate mechanical scenes and the from-scratch car validate this alongside Main's retained prototype.
- [ ] Validate vehicle assembly, materials, collision and camera after full import.
- [x] Package a local Linux standalone player and document limitations; headless package validation passes, graphical package validation remains pending.

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

## Vehicle variants checkpoint — 2026-10-16

The catalog now has 57 entries: 47 original blocks and ten mechanical items. New stable IDs 1006–1009 add the original large wheel, offroad suspension, electric engine and driver saddle, retaining source UUIDs, sizes, attachment masks, materials and collision data. Large-wheel axle mounting accounts for its five-cell diameter and two-cell depth. The longer suspension uses its third-cell output; the electric motor's initial speed/power come from a source gear. Tuning and separate art/collision corrections remain editable.

142 automated checks, shader compilation and the Main smoke run pass. Checks cover all four placements with native bodies, FBX/Collada units/Y-up, wheel mounting, source saddle hull, the real offroad slider, large electric car movement and graph save/restore. Reimport and append-only catalog synchronization preserve existing scene overrides.

Graphical validation: a separate gallery shows all four variants beside the original driver-seat forward reference. The driver saddle is upright and faces +Z consistently; a side-on wheel comparison confirmed both faces have the same hub detail, so no extra art flip is applied. The separate LargeWheelCar accepts saddle entry, drives at 3.9m/s, brakes/recovers and saves a valid five-group/four-link archive. Main and previously built creations remain available. Original suspension/lift deformation, extended handling and other item families remain open.

## Blueprint occupied-space continuation — 2026-10-16

- [x] Reject F8 blueprint imports overlapping active construction footprints before any live mutation.
- [x] Cover arbitrary creation rotations, rotated multi-cell items, different grid sizes and exact face contact.
- [x] Reject all groups atomically when any imported group is blocked; preserve full workshop load behavior.
- [x] Build, compile both shaders, pass 163 native integration checks and run Main headlessly for 180 frames.
- [ ] Graphically verify the new import rejection message and F8 interaction.

This continuation stays within ScrapWorkshop and uses no desktop or Python control. Import reservations use logical item footprints rather than physical hull detail.

## Local standalone player checkpoint — 2026-10-16

- [x] Build an editor-free Linux Release player in an isolated temporary workspace.
- [x] Bundle runtime art/materials/collision data, all seven scenes, compiled shaders and third-party library notices.
- [x] Add main-workshop and suspended-car launchers, controls, save instructions and platform/presentation limitations.
- [x] Preserve no-persistence/headless/server save safeguards in the standalone entry point.
- [x] Separate packaged data from editable-project saves; give every example a portable independent save profile.
- [x] Pass 169 native checks and source shader/headless checks; run each packaged scene for 180 headless frames after relocating through a path with spaces.
- [x] Verify package file checksums and produce a local compressed archive with its own checksum.
- [ ] Graphically validate the standalone player and its launchers.
- [ ] Test older Linux distributions or produce/verify a Windows player.

Build workflow: `./tools/package_local.sh`. Outputs remain under `Builds/`; details are in Distribution/README.md. This host build requires glibc 2.43. Original art stays local. No desktop control or changes to another game/shared-engine source were used.

## Original creative UI checkpoint — 2026-10-16

- [x] Replace the temporary text overlay with original hotbar, inventory, paint and menu artwork and Shentox fonts.
- [x] Import source XML state/stretch metadata, text colors, all 57 available item icons/titles, five tool icons and 40 active paint colors; retain source hashes and layouts locally.
- [x] Wire inventory categories/search, click assignment, drag/drop and all ten hotbar keys to actual construction tools.
- [x] Add resume/save/load, blueprint, camera/autosave options, controls and workshop-selection pages.
- [x] Add working per-item engine, suspension, bearing and controller dialogs with construction history and save persistence.
- [x] Add version-six tuning archives while retaining old-save loading; persist hotbar/options separately with validation.
- [x] Pass 192 native checks, shaders and Main headless smoke validation.
- [x] Graphically verify category/search, hotbar click/drag assignment, original slider/palette behavior, modal menus, Escape and absence of construction click-through using only process-scoped X11 events.
- [x] Verify actual part-dialog edits, native saved archives and engine undo/redo graphically in isolated save profiles.
- [ ] Complete exact original UI layout/blur/animation parity and the original controller matrix.
- [ ] Integrate original title/new-world, graphics/audio/key-binding options, character customization and handbook screens.
- [ ] Integrate any additional game-mode screens if the sandbox scope expands; survival/challenge functionality is not implemented.

The full-game UI is not marked complete. UI.md records the supported creative interface and remaining gaps. Input testing used a project-local C++ helper addressed only to its own process's window; no global pointer/focus control or Python desktop control was used. Steam files, shared-engine source and the other game were unchanged.

Standalone UI follow-up: the updated Release package passes the same scoped graphical interaction tests, including drag/drop and numeric tool switching, plus all four part-dialog save checks and engine undo/redo. All seven packaged scenes also pass headless checks. `./play-local.sh` launches the current verified package. Full-game screen parity remains open as listed above.

- [x] Clear part-dialog references when loading/replacing creations; verify F9 closes the suspension dialog safely in the standalone player. Latest native suite: 192 checks.
