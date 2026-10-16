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

Initial prototype compiles, but its running gear is fixed and the initial GUI uses temporary engine text. SDL cannot access X11 or Wayland from the current execution environment, so graphical validation has not passed. CPU physics and construction validation will be used for the foundation, without claiming that it proves appearance or interactive feel.

## Verified implementation checkpoint

- [x] Creation foundation and Inspector customization implemented; 25 CPU integration checks pass.
- [x] Split groups preserve their own ground/lift attachment and world placement.
- [x] Initial block weld and paint operations implemented and tested.
- [x] Complete scene starts headlessly for 180 frames.
- [ ] Graphical play validation remains pending because the current runner cannot access the desktop display.
- [ ] Undo/redo, construction persistence and recovery.
- [ ] Original item catalog and fully placeable mechanical assemblies.
- [ ] Original player, tool animation and HUD integration.

The temporary starter vehicle is retained as an editable preview, not a substitute for the mechanical-assembly milestone. Welding currently moves block-only sources with compatible grid sizes/orientations and rejects overlaps atomically. Supported sources must be released first; anchored sources cannot be moved by welding.
