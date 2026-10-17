# ScrapWorkshop sandbox roadmap

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


Development resumed at the user's request on 2026-10-16. Immediate priorities: correct the lift's ground contact and extension, implement the original-style controller matrix/behavior, and integrate original parts individually, while completing the creative work list below. Local RESUME.md retains the prior handoff; graphically verify and package each completed increment.

Latest increment: shared-face bearing mounts, direct plate picking, right-click removal and chunked opaque block surface/collision merging pass 226 native checks. Editor regeneration retains its font link and compiles. Logic configuration and wiring now pass 269 native checks, including engine/controller activation and timer queues; an original-part Logic Workbench is available. Next: finish graphical logic verification, older mechanical layouts, full bearing face-attachment identity, remaining interactive parts and drag building.

## Product target

Open the Tessera project, press Play, and build freely in a flat world. No game modes, survival economy, progression or missions. Original Scrap Mechanic art is imported locally. Engine and gameplay are Tessera implementations.

## Order of work

Current user priorities: keep the world flat; expand creative building with drag placement up to a 16×16 wall, draggable wedges and usable logic parts/circuits. Track implementation and actual-input verification in CHECKLIST.md under “Current creative priorities — user requests.” These features remain pending.

Bearing fidelity is also a current priority: study the original handbook and locally installed scripts, then match placement, moving-body separation, connect-tool gestures and visual feedback, direction reversal, engine behavior, steering and controller programming. Maintain a behavior-by-behavior comparison; existing vehicle smoke tests do not establish original-game parity.

Scale requirement: support thousands of blocks and very large maps with stable creation physics. Benchmark large static builds, editing batches, saves, multiple dynamic creations and articulated assemblies. Track rendering, memory, spatial-query and physics costs independently. Current limits and small-scene checks are not proof of large-world support; publish measured capacities and remaining failures.

The original character and first/third-person controller are explicitly requested: original character assets, locomotion, grounded collision, running/jumping, camera switching and obstruction, tool interaction/animation and seat transitions. Implement and play-compare these as part of the creative experience, rather than treating the current orbit/pan camera as finished player control.

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

Main retains the fixed prototype; separate editable placed-part car scenes now use real joints, motors and suspension. The creative GUI now uses original imported artwork and fonts; full original screen/layout parity remains unfinished. The actual Vulkan scene now runs through X11 and Wayland. Construction and driving have received a graphical smoke playtest; extended driving evaluation, original lift animation and remaining mechanical tooling and extended handling remain pending.

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

## Vehicle variants checkpoint — 2026-10-16

The catalog now has 57 entries: 47 original blocks and ten mechanical items. New stable IDs 1006–1009 add the original large wheel, offroad suspension, electric engine and driver saddle, retaining source UUIDs, sizes, attachment masks, materials and collision data. Large-wheel axle mounting accounts for its five-cell diameter and two-cell depth. The longer suspension uses its third-cell output; the electric motor's initial speed/power come from a source gear. Tuning and separate art/collision corrections remain editable.

142 automated checks, shader compilation and the Main smoke run pass. Checks cover all four placements with native bodies, FBX/Collada units/Y-up, wheel mounting, source saddle hull, the real offroad slider, large electric car movement and graph save/restore. Reimport and append-only catalog synchronization preserve existing scene overrides.

Graphical validation: a separate gallery shows all four variants beside the original driver-seat forward reference. The driver saddle is upright and faces +Z consistently; a side-on wheel comparison confirmed both faces have the same hub detail, so no extra art flip is applied. The separate LargeWheelCar accepts saddle entry, drives at 3.9m/s, brakes/recovers and saves a valid five-group/four-link archive. Main and previously built creations remain available. Original suspension/lift deformation, extended handling and other item families remain open.

## Blueprint occupied-space checkpoint — 2026-10-16

F8 imports now reject logical-footprint penetration into active existing creations before spawning any incoming group. A separating-axis test handles arbitrary creation rotations, quarter-turn item rotations, multi-cell dimensions and differing grid sizes; exact face contact is permitted. Inactive/destroyed creations are ignored. Existing lift-conflict rejection remains in place, and F9/undo/redo replacement does not use import-space rejection. The tool message explains that space must be cleared or the lift released.

Latest verification: 163 native integration checks, both custom shaders and the complete 180-frame headless Main scene pass. Twelve new checks cover atomic rejection, partial penetration, contact, rotated incoming/existing geometry, multi-cell extents, different grid sizes, inactive objects and full replacement. Collision policy deliberately follows logical footprints rather than detailed hulls, so wheel/seat empty corners still reserve space. Graphical testing of this increment remains pending. No desktop control, Python execution, shared-engine edits or other-project changes were used.

## Local standalone player checkpoint — 2026-10-16

The local packaging item now has an editor-free Linux Release player, seven included scenes, main/mechanical launchers, portable per-example save profiles, controls/limitations documentation and checksums. The project-owned shell packager builds in an isolated workspace and leaves shared-engine source and other projects unchanged. Automatic persistence policy is shared by development and packaged entry points; headless, server and no-persistence sessions disable automatic saves.

169 native integration checks, both shaders and source Main smoke validation pass. All seven packaged scenes also run for 180 headless frames from a relocated directory containing spaces and an unrelated working directory, with no construction-save output. The package remains local under Builds/ with a compressed archive. The current binary requires glibc 2.43 and GLIBCXX_3.4.30; graphical package validation, older-host compatibility and Windows packaging are still open. See Distribution/README.md.

## Original creative interface checkpoint — 2026-10-16

Original hotbar/inventory/palette/menu skins, 57 item icons and English names, five tool icons, 40 primary colors and Shentox fonts now replace the temporary instruction overlay. A project-local MyGUI resource adapter respects source state UVs, stretch anchors and button text colors. Inventory tabs/search/pagination and click/drag hotbar assignment drive real tool selection. Escape menu pages provide saves, blueprints, options and workshop switching; U opens implemented part settings. Per-item engine/spring/steering changes survive version-six saves and undo/redo, while versions 1–5 remain readable. Interface preferences persist separately.

192 native checks, shaders and source headless smoke checks pass. Graphical, process-scoped input verifies inventory/category/search, hotbar click/drag, menu/options/help, original sliders/palette, Escape and no click-through. All four mechanical dialogs produce valid native archives; engine UI undo/redo is verified through the actual saved files. Source files remain unchanged; imported UI provenance is recorded locally.

This completes a functional original-art creative UI increment, not the entire original game interface. Original blur/full layout/animation parity, the original controller matrix, title/new-world menus, richer options, character customization and handbook are still open. Survival/challenge screens are outside the current free-build implementation. See UI.md for exact scope and evidence.
