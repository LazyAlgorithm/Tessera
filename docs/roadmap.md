# Roadmap

Status on 2026-10-13, and the work agreed and queued, in order.

## Done

- Terrain redesign (tiles, generators, LOD, undo); faster CI that caches the native libraries and compilers
- Ringfall: aim assist per weapon and per control type, auto-fire buffer
- Layers, tags and world states. World states now cover collision, drawing, shadows, lights, particles, sound and
  navigation, with a world state menu in the editor toolbar
- HTTPS downloads and zip extraction in the engine (`docs/http.md`)
- Built games: `windowWidth`, `windowHeight` and `escapeQuits` in `project.tessera`; engine releases carry
  `SHA256SUMS.txt`
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

Work agreed and queued, in order. Each engine feature ships with a docs/ page, a Tests/ fixture, a line in the
README feature list, an editor UI, and compatibility with existing scene and project files.

## Shatterline engine features (general-purpose first)

- E6 first-person viewmodel layer
- E7 materials on skinned meshes
- E10 post-processing: ambient occlusion, depth of field, motion blur, colour grading
- E9 async scene and asset loading
- E4 animation layers and blend trees
- E5 inverse kinematics
- E11 decals
- E12 dialogue and subtitles
- E13 sequencer (cutscenes)
- E14 navigation upgrades
- E15 behaviour tree upgrades
- E16 LOD, occlusion culling, GPU skinning
- E20 quality presets
- E18 macOS, E19, E21

## Higher-quality rendering (after the above, one at a time)

1. Texture mipmaps and GPU texture compression
2. Image-based lighting and reflection probes
3. Shadows from point and spot lights, and more lights per view
4. Baked lighting and global illumination

## Editor

- Themes: theme files, built-in themes (dark, light, high contrast, Tessera blue), a Theme page in Preferences
  with live colour pickers, import and export

## Last

- Shader graph: materials' shaders built from nodes, on the existing node editor
- Visual compute shaders: compute shaders built from nodes
