# Tessera v0.1.0-beta.1

Early beta of the Tessera engine, project launcher, and editor for Linux x64 and Windows x64.

- Portable folders with a launcher at the top level, engine assets, project templates, shader compiler, and the source/native libraries required to compile game scripts.
- Cross-platform Python packaging, also available through the editor's Build window.
- Windows process hardening preserves the original process access list and restores it during shutdown. Ringfall/Steam compatibility still needs testing with hardening enabled.

Start `Tessera` on Linux or `Tessera.exe` on Windows. BeefBuild and Python 3.11+ are required to edit/build projects. Windows also needs Microsoft C++ Build Tools. Graphics drivers and normal operating-system libraries are prerequisites.

Since v0.1.0-beta.1: scripts reload while the editor runs on Windows as they do on Linux (tested under Wine; not yet on a Windows machine).

Also since v0.1.0-beta.1:

- Faster scenes. Destroying an object no longer looks through every field of every component by reflection (a frame destroying 30 objects in a scene of 4,000 components went from about 200 ms to under 1 ms), each class's fields are worked out once, `FindComponent` and the per-frame audio, wind, spawn and navigation lookups use an index by class, shadow draws of the same mesh are batched together again, a missing model is no longer looked for on disk every frame, an animated model that nothing draws (off screen, too far away to cast a shadow) is bent only every eighth frame (on a dedicated server not at all) while its animation keeps playing, and voxel terrain works out which chunks it wants only when a viewer moves a quarter of a chunk or a setting changes.
- `Application.Quit()`: a game's quit (or `Running = false`) closes a built game and stops Play in the editor, with no change to game code.
- Destroying an object (or unloading a scene) tells every component under it that it is going before any object is freed, so a component's `OnUnregister` can still look at its children: an IK component on a rig no longer crashes when its scene is unloaded.
- One code style across the engine, applied by `tools/format/format_code.py` (`docs/coding-style.md`).
- The code was restructured for reading and changing: long methods (the longest were 300 to 700 lines) are split into named steps, large classes (voxel terrain, networking, rendering) are split into files by area, repeated code is shared, constants are named, and the commonly used API has doc comments. No public API was removed or renamed: games build unchanged.
- Fixed: the editor's Input Actions window crashed on an action with a touch binding, and touch bindings could not be put on direction actions.

Known limitations: macOS and browser exports are not supported. This is an early beta; back up projects before use.

Validation: Linux package creates a project and that project compiles using the packaged engine/editor and native archives. Windows packages require a native Windows launch/create/build smoke test before release validation can be claimed.
