# Roadmap

Work agreed and queued, in order. Each engine feature ships with a docs/ page, a Tests/ fixture, a line in the
README feature list, an editor UI, and compatibility with existing scene and project files.

## Shatterline engine features (general-purpose first)

- E2 world states: finish rendering, audio and navigation membership, and a Scene view toggle
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
