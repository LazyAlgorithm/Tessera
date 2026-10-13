# Roadmap

Status on 2026-10-13, and the work agreed and queued, in order.

**How to use this page.** Work happens on `dev` (Tessera and the games), and reaches `main` only once it is checked.
Each queued item is a checkbox: `[x]` done (with the date and the commit), `[~]` in progress (with notes on what is
built and what is left, so anyone can pick it up), `[ ]` not started. Tick an item in the same commit that finishes
it. Every engine feature is only done when it has:

- a way to adjust it in the editor (Inspector fields, a window or a tool), wherever that makes sense;
- a `docs/` page (or a README section), which is what the project website shows;
- networking, where the feature has anything that must be the same on every machine (and a note in its page saying
  so either way);
- a `Tests/` fixture, a line in the README feature list, and compatibility with existing scene and project files.

The website (`website/`, kept on the developer's machine, not in this repository) builds its documentation pages
from the README and `docs/`; a new page also needs a line in `website/content/manifest.php`, given with each item
below, and then `website/update.sh`.

## Done

- Terrain redesign (tiles, generators, LOD, undo); faster CI that caches the native libraries and compilers
- Ringfall: aim assist per weapon and per control type, auto-fire buffer
- Layers, tags and world states. World states now cover collision, drawing, shadows, lights, particles, sound and
  navigation, with a world state menu in the editor toolbar
- HTTPS downloads and zip extraction in the engine (`docs/http.md`)
- Built games: `windowWidth`, `windowHeight` and `escapeQuits` in `project.tessera`; engine releases carry
  `SHA256SUMS.txt`
- **Responsive UI and mobile controls** (2026-10-13, `dev` and `main`): the web canvas sized correctly (it was a
  1600×900 window on phones), SDL following resizes in fullscreen (a phone turned after play started was
  stretched), `@media` rules in UI stylesheets, text measured at the width it is drawn, touch controls in the
  screen's short side, dimmed buttons, sticks hidden until used, flicks (`AddSwipe`), phone 3D resolution by the
  short side. Ringfall: portrait and landscape layouts for every phone screen and the HUD, buttons-only touch
  controls around FIRE, mantling per input type. Docs: `responsive-ui-design.md`, `input.md` (touch), Ringfall's
  `mobile-controls-v2.md`. Website line for the new page:
  `['slug' => 'responsive-ui', 'title' => 'Responsive interfaces', 'category' => 'Engine', 'file' => '../docs/responsive-ui-design.md', 'summary' => 'Interfaces that fit phones and desktops held either way: @media rules, design sizes and the web canvas.'],`
- **Tessera Hub** (github.com/LazyAlgorithm/tessera-hub): installs, updates and starts Ringfall and the engine,
  checks for and installs the tools they need after asking, beta badges and a beta-builds setting, and updates
  itself. Linux and Windows builds are on its Releases page. Tested on Linux: browsing, the tools dialog, installing
  the engine, starting it, settings. Windows built but not yet tried on a real Windows machine.

## Manual steps

1. **Add the `RELEASES_TOKEN` secret to the Ringfall repository** (Settings > Secrets and variables > Actions). It is
   a fine-grained personal access token with *Contents: Read and write* on `LazyAlgorithm/ringfall-releases`. Until
   it is there, Ringfall builds skip the public release (the run shows a notice), so the Hub shows "No release yet"
   for Ringfall. After adding it, push Ringfall to its `release` branch (or run its workflow) once.
2. Try the Hub on Windows: unzip TesseraHub-Windows.zip from the tessera-hub Releases page and run TesseraHub.exe.
3. Optional: macOS needs E18 (below) before the Hub or games can be built for it.

## Queued

Work agreed and queued, in order (see *How to use this page* above for what "done" means).

## Shatterline engine features (general-purpose first)

- [x] E6 first-person viewmodel layer (2026-10-13, `dev`): Camera's Viewmodel Layer / Field Of View / Near Clip /
  Casts Shadows (Inspector, `[Layer]` drop-down), its own render pass over the world, an amber gizmo frustum,
  `docs/viewmodel.md`, `Tests/Viewmodel`. Networking: none needed (local camera only). Ringfall uses it.
  Website line: `['slug' => 'viewmodel', 'title' => 'First-person viewmodel', 'category' => 'Engine', 'file' => '../docs/viewmodel.md', 'summary' => 'A player\'s arms and weapon drawn over the world with their own field of view, never through walls.'],`
- [ ] E7 materials on skinned meshes
- [ ] E10 post-processing: ambient occlusion, depth of field, motion blur, colour grading
- [ ] E9 async scene and asset loading
- [ ] E4 animation layers and blend trees
- [ ] E5 inverse kinematics, built in: two-bone limbs (arms, legs) with a pole target, look-at for heads and spines,
  foot placement on uneven ground, hands on a held weapon; an IK component edited in the Inspector with handles in
  the Scene view; works with the Animator (after the clip, per layer weight) and over the network (targets that
  matter for others synced, the rest worked out on each machine)
- [ ] E5b animation retargeting: play clips made for one rig on another (a shared humanoid bone map, matched by
  name with an editor to fix the matches, bone lengths and rest poses allowed to differ, root motion scaled to the
  target's size); the Animator plays any retargeted clip, and networking already sends clip and state, not bones
- [ ] E11 decals
- [ ] E12 dialogue and subtitles
- [ ] E13 sequencer (cutscenes)
- [ ] E14 navigation upgrades
- [ ] E15 behaviour tree upgrades
- [ ] E16 LOD, occlusion culling, GPU skinning
- [ ] E20 quality presets
- [ ] E18 macOS, E19, E21

## Higher-quality rendering (after the above, one at a time)

1. [ ] Texture mipmaps and GPU texture compression
2. [ ] Image-based lighting and reflection probes
3. [ ] Shadows from point and spot lights, and more lights per view
4. [ ] Baked lighting and global illumination

## Editor

- [ ] Themes: theme files, built-in themes (dark, light, high contrast, Tessera blue), a Theme page in Preferences
  with live colour pickers, import and export

## Last

- [ ] Shader graph: materials' shaders built from nodes, on the existing node editor
- [ ] Visual compute shaders: compute shaders built from nodes
