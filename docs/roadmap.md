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

The website is the GitHub Pages site on this repository's `gh-pages` branch (one page, `index.html`). Its **Manual**
documents each feature in a section of its own (an `h2` with an id, linked from the Manual's sidebar; the site's
search picks it up). A feature on `dev` but not yet in `main` says so in its section.

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
  `mobile-controls-v2.md`. Website: Manual > Touch screens, Phones and tablets.
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
  Website: Manual > First-person viewmodel.
- [x] E7 materials on skinned meshes (2026-10-13, `dev`): the glTF loader reads each material whole and decodes
  its images (in a .glb, data: addresses, files beside it); a rigged model with several materials or textures is
  drawn in parts sharing one skinned vertex buffer (`Mesh.VertexSource`, `MeshRenderer.RuntimeParts`), each with
  the file's material or a `.tmat` per part (Inspector list, `SetPartMaterial`, networked). `docs/skinned-materials.md`,
  `Tests/SkinnedMaterials` (with a model generator). Website: Manual > Materials on skinned meshes.
  Not yet: static (unrigged) models still take one material from their Mesh Renderer; the same parts would do it.
- [x] E6b viewmodel pose (2026-10-13, `dev`): the Viewmodel Pose component (hip and aim poses, aim speed, walk bob
  and sway from the camera's movement, steadier when aiming, recoil with `Kick`), Preview slider and "Use current
  place as Hip / Aim" buttons in the Inspector, `docs/viewmodel.md`, `Tests/Viewmodel`. Networking: none needed.
  Website: Manual > First-person viewmodel.
- [x] E10 post-processing (2026-10-13, `dev`): ambient occlusion, depth of field (with auto-focus), camera motion
  blur and colour grading (contrast, saturation, temperature, tint, colour filter, vignette, lookup tables) as scene
  settings, from a depth pass that leaves the viewmodel alone. Inspector: Scene Settings > Screen Effects and Color
  Grading (Make Neutral Lookup Table). Players' settings: `ScreenEffects` (off on phones). RenderViews now use 17 view
  ids. `docs/post-processing.md`, `Tests/PostProcessing`. Website: Manual > Screen effects.
- [x] E9 async scene and asset loading (2026-10-14): `SceneManager.LoadAsync` / `LoadAdditiveAsync` (stages, Progress,
  allowActivation, Activate), `AssetLoader.Preload` and batches; models, rigged models and textures read and decoded
  on two loading threads, sent to the graphics card within `AssetLoader.UploadBudget` a frame (inline in a browser);
  what a scene names found through its prefabs, scenes and materials. The Scene Loader component (Inspector, scene
  picker, `progress` for a loading bar). Networking: none needed (every machine loads for itself). `docs/loading.md`,
  `Tests/AsyncLoading`. Website: Manual > Loading in the background.
- [x] E4 animation layers and blend trees (2026-10-14): controller layers (each a state machine; weight, Override or
  Additive, a bone mask by name), 1D and 2D freeform blend trees (gradient band weights, clips kept in step), for
  `.tanim` clips and for rigged models' clips with Expose Bones; controllers without them run as before. Animator
  window: Layers list with weight (live), blending and mask; Clip or Blend Tree per state with parameters, clips,
  thresholds or positions and a live diagram. `SetLayerWeight`, `StateIndexOn`, `NormalizedTimeOn`. Networking:
  layer weights follow the owner (states and parameters already did). `docs/animator.md`, `Tests/AnimationLayers`.
  Website: Manual > Animation layers and blend trees.
- [x] E5 inverse kinematics (2026-10-13, `dev` and `main`):
  Limb IK (two-bone arms and legs with a pole, the hand locked to a target's rotation with an offset and a grip
  point, `LetGo` / `Grab` / `SetTarget` so that each arm is freed and returned by itself), Look At IK (head, neck
  and spine sharing the turn, within a limit), Foot Placement (feet on uneven ground, hips lowered, feet tilted),
  Hand Pose (a curl slider for each finger, spread, trigger, ready-made shapes), and `IKSolver` for code (two-bone,
  chains of any length, look-at). A layer over the Animator's pose with a weight, solved after every LateUpdate and
  in the editor; `Expose Bones` on the Skinned Mesh Renderer makes bone objects so that rigged models take part.
  Inspector tools (find hands and feet, Make Target And Pole, Keep Hand's Rotation, shape buttons), Scene view
  gizmos, **Key IK** in the Animation window and recording that ignores IK. Networking: weights and hand shapes
  follow the owner; targets are ordinary objects; the rest is worked out on each machine. `docs/ik.md`, `Tests/IK`.
  Website: the Manual section is still to be written (it lives on `gh-pages`).
  Not yet: joint limits, stretch, a component for chains longer than two bones, fingers wrapping round a shape.
- [x] Terrain: dual contouring, finer ground, brush preview (2026-10-13): Style **Contoured** (one point a cell,
  quads between; seamless across chunks, with level of detail and full-detail collision) and **Contour Sharpness**;
  new terrains are contoured, half-metre voxels, smoothly shaded, with **Flat Shading** for the faceted look and
  Style Smooth for marching cubes; a preview mesh under the brush in the Scene view; generation settings taken out
  of the editor (a terrain there is its tiles; generators are the game's code). `docs/terrain.md`, `Tests/Terrain`.
- [x] Foliage and wind (2026-10-13): the Foliage component (painted, instanced plants; built-in grass, bush, tree
  and pine) with its brush in the Inspector, Wind Zone components (global and sphere), `Wind Sway` on Mesh
  Renderers, bending in the mesh vertex shader. `docs/foliage.md`, `Tests/Foliage`. Networking: scene data, the
  same everywhere; `Wind.At` for code. Not yet: plants with colliders.
- [x] Editor: number fields can be typed into (click, or double-click a slider); the UI tab shows the whole document
  scaled to fit, with named placeholders for canvases (`preview`, `preview-src`).
- [x] Destructible objects from any model (2026-10-13): Voxel Object Shape **Mesh** fills a closed model in as solid
  material, keeping its size, colours and texture coordinates; the outside takes the Mesh Renderer's material and
  the inside an Interior Material or one made from the outside's. `docs/voxel-objects.md`, `Tests/VoxelObject`.
- [x] Foliage follow-ups (2026-10-13): a Foliage tool in the Terrain Tools, undo and redo for brush strokes (applied
  in place), shadows and the depth pass bending in the wind with the plants.
- [x] Foliage: parting round players and following sculpting (2026-10-13): plants bend away from every Character
  Controller and from Foliage Bender components (eight nearest the camera, in the shared wind shader; nothing sent
  over the network), and plants on a terrain ride sculpted ground up and down, removed when buried or left with
  nothing under them, each judged from its own foot so that caves are left alone. `docs/foliage.md`,
  `Tests/Foliage`, `Tests/Terrain`.
- [x] E5b animation retargeting (2026-10-24): play clips made for one rig on another (a shared humanoid bone map,
  matched by name with a Bone Map window to fix the matches, bone lengths, rolls, rest poses and facings allowed to
  differ, hips movement scaled by leg length); the Animator plays any retargeted clip, and networking already sends
  clip and state, not bones. With it, at the user's request: bones drawn and clickable in the Scene view, an IK rig in
  one press with handles, IK snapping and baking, model clips copied into editable ones, and Hand Posing for fingers.
  `docs/retargeting.md`, `Tests/Retargeting`, editor `--rig-test`.
- [x] E11 decals (2026-10-24, `dev` ec61835): a Decal component projects a picture onto the solid scene inside its box (lit,
  shadowed and fogged like the surface, with an angle limit, opacity, unlit and draw order), sharing the depth pass
  with the screen effects and the mesh shader's lighting (`Engine/shaders/include/lighting.sh`); GameObject > Decal,
  Stick to Surface and box picking in the editor; `Decals.Spawn` for pooled short-lived decals, made on every machine
  rather than sent. `docs/decals.md`, `Tests/Decals`, decals in the Sandbox Main scene.
- [x] E12 dialogue and subtitles (2026-10-25, `dev` ff0cb48): `.tdialogue` conversations (speakers, nodes of lines, answers,
  variables, events, jumps and conditions) edited in a Dialogue tab with a preview, played by a Dialogue Runner
  (subtitled lines with voice recordings, answer buttons, keyboard and controller input, kept in saves); Subtitles
  for any sound with an `.srt` beside it or from code, with player settings and captions; a Shared conversation is
  run by the server for everyone. `docs/dialogue.md`, `Tests/Dialogue`, a guide in the Sandbox Main scene.
- [x] E13 sequencer (cutscenes) (2026-10-25, `dev` d1afaf9): `.tsequence` timelines with Transform, Camera (shots and blends),
  Animation, Audio, Show / Hide, Event, Subtitle and Fade tracks, edited on a timeline in the Sequencer tab (scrub
  and play preview on the scene, look through shots, K to key the selected object), played by a Sequence Player
  (pause, skip, seek, loop, restore, saving; `Scene.CameraOverride` / `ViewCamera`); Shared sequences are timed
  by the server for everyone. `docs/sequencer.md`, `Tests/Sequencer`, an intro cutscene in the Sandbox.
- [x] E14 navigation upgrades (2026-10-25, `dev` 424c265): any-angle path smoothing that keeps the grid's clearance; Navigation
  Links (jump, climb, teleport, walk; one-way; cost; agents cross them with events); Navigation Obstacles that carve
  the grid while still and are steered round while moving; Navigation Areas (costly or blocked); local avoidance
  between agents with priorities; SamplePosition, RandomPoint, Raycast, RemainingDistance; Inspector tools and
  gizmos, `--bake-navigation`. `docs/navigation.md`, `Tests/Navigation`, `Scenes/Navigation.tscene` in the Sandbox.
- [x] E15 behaviour tree upgrades (2026-10-25, `dev` fc15e1a): Run Subtree (other files run in place, shared blackboard, shown live,
  Open / New Subtree File, loops refused), tree files read once and shared by all runners; Event Received and Send
  Event (`SendEvent`, `OnTreeEvent`); hearing (`AINoise.Make`, Heard Noise); `#Tag` targets; Can See Sight Points;
  Set / Compare Number, Remember Position, Start Values; Chance, Random Selector, Run Once; Wander on reachable
  points; Ctrl+D duplicate in the Behavior tab. `docs/behavior-trees.md`, `Tests/BehaviorTree`, a guard in the
  Sandbox Navigation scene.
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
