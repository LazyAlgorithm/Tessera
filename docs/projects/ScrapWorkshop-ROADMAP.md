# ScrapWorkshop sandbox roadmap

## Product target

Open the Tessera project, press Play, and build freely in a flat world. No game modes, survival economy, progression or missions. Original Scrap Mechanic art is imported locally. Engine and gameplay are Tessera implementations.

## Order of work

1. **Creation foundation and editor workflow** — separate editable part definitions, construction state, interaction and vehicle simulation. Ground placement starts an anchored creation; a lift starts a supported creation. Quarter-meter grid, exact occupied-cell selection, no duplicate cells, collision rebuilt from placed blocks. Inspector-exposed settings and authored scene examples. Validate headlessly where possible; report graphical limits honestly.
2. **Construction topology** — connected parts form a creation. Removing a bridge splits disconnected groups into new creations, retaining world poses, paint, anchors and physical motion. Ground anchors belong to individual blocks. Only the group attached to the lift stays supported.
3. **Welding and paint** — select source and target faces, preview alignment, reject overlaps, merge connectivity, preserve world pose where compatible; controlled alignment for rotated creations. Paint individual parts with an editor-configurable palette. Undo/redo follows transactional edit commands.
4. **Persistence and recovery** — versioned construction saves, autosave, named blueprints, load validation, world poses and ground/lift state. Preserve creations after sleep/restart. Undo/redo for placement, removal, welding and painting.
5. **Part catalog and tooling** — original item definitions and models; item sizes, rotations, attachment faces, density and collision. Catalog and quickbar. Original lift/tool/HUD assets. Editable definitions and prefab templates; no hard-coded per-item behavior in the interaction controller.
6. **Mechanical assemblies** — placeable seats, wheels, bearings, suspension, engines and controllers. Weld groups versus moving joints, steering/throttle connections and seated control. Build the car from items, rather than relying on the initial fixed vehicle rig.
7. **Player and presentation** — original modular character, skeleton, locomotion and tool animations; first/third-person movement, tool interaction and original HUD artwork. No replacement artwork silently substituted for missing imports.
8. **Play validation and packaging** — verify hit Play, ground builds, lift builds, release, split, weld, paint, save/load, vehicle assembly and driving. Local run/editor launchers, screenshots and playable build. Performance profiling for larger constructions.

Each milestone is implemented and checked before expanding the next one. Subtasks may be delivered incrementally; a roadmap checkbox must distinguish implementation, automated verification and graphical play validation.

## Editor customization requirements

- Place world floor, lighting, cameras and lift in the scene and edit them normally.
- Part definitions live as editable components with stable IDs, paths, physical properties and appearance.
- Construction components and authored block children can be arranged in the editor.
- Expose grid scale, build reach, limits, camera settings, vehicle tuning and palette choices through Inspector fields.
- Keep construction/topology independent of input, HUD and rendering so tests can exercise actual gameplay operations.
- Preserve original source paths and conversion provenance; keep imported assets local.

## Current limits

Main retains the fixed prototype; separate editable placed-part car scenes now use real joints, motors and suspension. The GUI uses temporary engine text. The actual Vulkan scene now runs through X11 and Wayland. Construction and driving have received a graphical smoke playtest; extended driving evaluation, original lift animation and remaining mechanical tooling and extended handling remain pending.

## Verified implementation checkpoint

- [x] Creation foundation and Inspector customization implemented; 55 CPU integration checks pass.
- [x] Split groups preserve their own ground/lift attachment and world placement.
- [x] Initial block weld and paint operations implemented and tested.
- [x] Complete scene starts headlessly for 180 frames.
- [x] Actual-scene graphical smoke playtest: building, removal/splitting, painting, welding, lift release/recovery and starter driving.
- [ ] Extended driving and presentation playtesting.
- [x] Persistence/recovery and undo/redo implemented, automatically checked and smoke-playtested, including a process restart.
- [x] Incremental catalog step: 47 original block definitions, paged selection, editable materials and source identity.
- [x] Reconstructed paint-mask/ASG/normal/tiling material path compiled and smoke-playtested; exact original fidelity remains open.
- [ ] Non-block catalog occupancy/attachments/rotations and fully placeable mechanical assemblies.
- [ ] Original player, tool animation and HUD integration.

The temporary starter vehicle is retained as an editable preview, not a substitute for the mechanical-assembly milestone. Welding currently moves block-only sources with compatible grid sizes/orientations and rejects overlaps atomically. Supported sources must be released first; anchored sources cannot be moved by welding.

## Non-block catalog increment

Six mechanical candidates now have original dimensions, sticky attachment faces, source identity and editable art corrections. Shared oriented occupancy drives actual placement, topology and persistence. This checkpoint has 69 automated checks plus graphical placement/rotation/save-load evidence. General item families and exact hull collision remain open. Native bearing motors, round collision, control wiring and whole-assembly recovery are the next implementation/validation increment; they are not yet marked fully play-validated.

## Verified mechanical increment

98 integration checks, both shaders and the 180-frame Main smoke run pass. Separate MechanicalCar and MechanicalSuspensionCar scenes use placed seats/engines, real driven bearing hinges and round wheels; the latter has four spring sliders and two front steering hinges. Whole-assembly support, recovery and graph persistence are checked. Direct input in the actual Vulkan scene confirms seat entry, throttle, steering, braking, recovery/camera follow and seat→engine tool wiring.

Definitions expose motor speed/torque, angle limits/servo response, suspension travel/stiffness/damping and independent art correction. Version-4 archives preserve the mechanical graph and neutral frames. A full user-built car, every connection-edit path, controller sequencing, original suspension deformation and endurance playtesting remain open. Complete remaining item families/tooling before marking milestones 5–6 complete; the original character and HUD remain later roadmap work.

## Connection editing checkpoint — 2026-10-16

105 automated checks, both shaders and the 180-frame Main smoke run pass. In Connect mode, aim at a mounted bearing and press I to reverse it; X clears an item's incoming control wires. The HUD identifies the incoming mode/direction. A new mode replaces competing bearing controls. Tests cover a placed controller reaching +22.5°, inversion reaching −22.5°, clearing wires and rejection across unrelated assemblies.

Actual-scene input verifies I inversion, X clearing and Ctrl+Z/Y undo/redo. The playtest exposed a stale HUD hover reference after undo replaced creations; selection/hover are now cleared during restore and the repeated graphical test passes. Controller sequencing and complete from-scratch vehicle assembly remain open.

## Controller programs and recovery checkpoint — 2026-10-16

125 automated checks, both shaders and a 180-frame Main smoke run pass. Placed controllers have an optional Inspector-authored four-angle program, configurable step count/timing/speed, looping and return-on-release. Seat W advances, neutral pauses and S reverses. Archives version 5 preserve per-controller programs, accepting versions 1–4. Graph/body rebuild checks guard reused native constraint addresses; duplicate control wires and invalid programs are rejected before mutation.

Actual isolated-scene playtesting confirms controller seat entry, arm playback, pause/reverse, recovery and save/reload. Recovery exposed quaternion-norm drift during repeated lift movement; normalized assembly rotations fix it, with 600 subsequent frames checked automatically. Nonfinite live archives now fail before primary/backup replacement. All example scenes have isolated save folders, and playtest.sh isolates user-data paths as well as enabling reliable scoped X11 automation.

Wheel definitions now expose a mounting point so actual bearing-output placement aligns the axle with the bearing rather than a footprint corner. This is checked automatically and through actual from-scratch placement. The complete user-built car, remaining item families/source hulls, extended handling, original character/tools/HUD and animated lift/suspension art remain open.

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
