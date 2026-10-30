> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

<!-- confirmation:start -->
# Latest Tessera-only performance rerun

Updated 2026-10-27T21:24:03.

Results and before/after comparison: historical benchmark root/full-engine/CONFIRMATION.md

Completed groups: 9. Failed runs: 0. Unity baseline reused; Unity was not rebuilt or rerun.

| Workload | N | Previous Tessera ms | Rebuilt Tessera ms | Tessera time reduction | Saved Unity ms | Rebuilt Tessera / Unity |
|---|---:|---:|---:|---:|---:|---:|
| physics-overlap-sphere | 1000 | 7.9879 | 6.6828 | 16.3% | 0.4195 | 15.93× |
| physics-overlap-capsule | 1000 | 3.7549 | 2.6929 | 28.3% | 0.2882 | 9.35× |
| physics-overlap-box | 1000 | 1.3436 | 1.3483 | -0.3% | 0.2647 | 5.09× |
| physics-boxcast | 1000 | 0.7922 | 0.7868 | 0.7% | 0.5755 | 1.37× |
| physics-capsulecast | 1000 | 0.8875 | 0.8920 | -0.5% | 0.6279 | 1.42× |
| physics-spherecast | 1000 | 0.8513 | 0.8204 | 3.6% | 0.5884 | 1.39× |
| physics-mesh-raycast | 1000 | 0.5382 | 0.5409 | -0.5% | 0.4109 | 1.32× |
| render-materials | 1000 | 1.5426 | 0.2360 | 84.7% | 0.7544 | 0.31× |
| render-materials | 10000 | 14.8785 | 1.5827 | 89.4% | 4.0636 | 0.39× |
| render-culling | 1000 | 0.2006 | 0.1913 | 4.7% | 0.2030 | 0.94× |
| render-culling | 10000 | 1.0815 | 0.8680 | 19.7% | 0.5362 | 1.62× |
| render-transparency | 1000 | 1.5810 | 0.2927 | 81.5% | 0.7828 | 0.37× |
| render-skinning-cpu | 100 | 12.9152 | 4.3031 | 66.7% | 0.9944 | 4.33× |
| render-skinning-gpu | 100 | 0.8586 | 0.8767 | -2.1% | 0.6225 | 1.41× |
| render-skinning-gpu @1920x1080 | 1000 | 8.5533 | 10.0112 | -17.0% | 4.1077 | 2.44× |
| animator-clips | 100 | 2.1917 | 0.2855 | 87.0% | 0.7680 | 0.37× |
| animator-clips | 1000 | 22.1210 | 2.8996 | 86.9% | 10.4848 | 0.28× |
| animator-layered | 100 | 4.4487 | 1.4366 | 67.7% | 1.1102 | 1.29× |
| animator-layered | 1000 | 45.0267 | 14.8452 | 67.0% | 16.3369 | 0.91× |
| ai-nav-path | 1 | 0.1638 | 0.0123 | 92.5% | 0.0015 | 8.22× |
| ai-nav-path | 100 | 21.5275 | 1.2165 | 94.3% | 0.1075 | 11.32× |
| audio-mix | 100 | 1.3722 | 0.4492 | 67.3% | 0.1588 | 2.83× |
| asset-image-decode | 100 | 106.5083 | 107.3979 | -0.8% | 90.9627 | 1.18× |
| physics-check-sphere | 1000 | — | 0.5981 | — | — | — |
| physics-check-capsule | 1000 | — | 0.6880 | — | — | — |
| physics-check-box | 1000 | — | 1.2974 | — | — | — |

<!-- confirmation:end -->

# Tessera engine testing — live inventory

Updated: 2026-10-27 18:32:19 CDT

Status: expanded feature testing in progress. Available measurements below are provisional until the suite completes.

Repository: historical benchmark root/full-engine

Unity: 6000.3.27f1 LTS Linux x86_64 installed. Standalone nondevelopment Mono/Vulkan player. Tessera: Beef Release + native -O3.

## Feature checklist

Performance tests only, per request. No functional regression suite is being run. Small validation checks only verify that timed work really happened.

| Feature | Performance status | Performance coverage | Unity comparison |
|---|---|---|---|
| Achievements | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| AnimationLayers | Pending performance measurement | Layer blending planned | Animator comparison planned |
| Animator | Pending performance measurement | Track interpolation added; full rig planned | Rig comparison planned |
| AntiCheat | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| AssetPack | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| AsyncLoading | Pending performance measurement | Asset loading workload planned | Loading equivalents planned |
| Audio | Measurements available / expanding | Playback/mixing workload planned | AudioSource equivalent planned |
| Baking | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| BehaviorTree | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| CharacterController | Measurements available / expanding | Flat/step capsule motors | Behavior differs; not ranked |
| CodeEditor | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| Culling | Measurements available / expanding | 90% behind-camera population | Available |
| Decals | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| Dialogue | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| Foliage | Pending performance measurement | Instancing workload planned | Mesh instancing equivalent |
| GpuSkinning | Measurements available / expanding | GPU/CPU skinned-mesh crowd benchmark planned | Matching generated rig/mesh planned |
| GraphApi | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| GraphVariables | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| Http | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| IK | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| InputActions | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| InspectorTypes | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| Joints | Pending performance measurement | Constraint workload planned | Rigidbody joints planned |
| Layers | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| Lighting | Measurements available / expanding | 16 point lights; directional shadows | Available native pipeline comparison |
| Maps | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| Material | Measurements available / expanding | Shared/unique materials | Available native pipeline comparison |
| Modeling | Measurements available / expanding | Topology/primitive/mesh edit operations planned | Unity Mesh API where equivalent; editor tools separate |
| Navigation | Measurements available / expanding | Bake/pathfinding workload planned | NavMesh package if available |
| Network | Pending performance measurement | Native packet codec added; transport planned | No built-in matching transport; explicitly identify package |
| NetworkBandwidth | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| PhysicsPrediction | Pending performance measurement | Network prediction planned | Requires matched implementation |
| PostProcessing | Pending performance measurement | Effect workload planned | Pipeline-specific comparison |
| Quality | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| References | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| Reflections | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| Retargeting | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| Rigging | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| Saving | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| Scenes | Measurements available / expanding | Empty/scripts/transforms/hierarchy/churn; save/load | Available; dispatch differences flagged |
| ScriptCatalog | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| ScriptReload | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| Sequencer | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| ShapeQueries | Measurements available / expanding | 8 query cases, 1,000 queries/sample | Available |
| SkinnedMaterials | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| SpawnPoints | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| Terrain | Pending performance measurement | Mesh collision; terrain generation planned | Mesh collision available |
| Textures | Pending performance measurement | Texture workload planned | Texture upload/decode planned |
| Themes | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| UIDocuments | Measurements available / expanding | Feature-specific test planned | Assess equivalent API/package |
| Viewmodel | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| Voice | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |
| VoxelObject | Pending performance measurement | Feature-specific test planned | Assess equivalent API/package |

## Available standalone timing results

Median of completed process medians, in milliseconds; lower is better. Partial runs are labeled by repetition count. Query values are per 1,000-query batch, not individual query. Render intervals are native whole-frame measurements, not equal-quality GPU comparisons.

| Workload | Objects | Tessera ms (runs) | Unity ms (runs) |
|---|---:|---:|---:|
| ai-behavior-tree | 100 | 0.0245 (3) | Pending / no equivalent |
| ai-behavior-tree | 1000 | 0.2562 (3) | Pending / no equivalent |
| ai-nav-bake | 1 | 6.1903 (3) | 2.3639 (3) |
| ai-nav-path | 1 | 0.1638 (3) | 0.0015 (3) |
| ai-nav-path | 10 | 2.1513 (3) | 0.0111 (3) |
| ai-nav-path | 100 | 21.5275 (3) | 0.1075 (3) |
| animation-ik | 100 | 0.0859 (3) | Pending / no equivalent |
| animation-ik | 1000 | 0.8777 (3) | Pending / no equivalent |
| animation-retarget | 1 | 0.6165 (3) | Pending / no equivalent |
| animation-retarget | 10 | 6.1281 (3) | Pending / no equivalent |
| animator-clips | 1 | 0.0240 (3) | 0.0104 (3) |
| animator-clips | 100 | 2.1917 (3) | 0.7680 (3) |
| animator-clips | 1000 | 22.1210 (3) | 10.4848 (3) |
| animator-layered | 1 | 0.0447 (3) | 0.0120 (3) |
| animator-layered | 100 | 4.4487 (3) | 1.1102 (3) |
| animator-layered | 1000 | 45.0267 (3) | 16.3369 (3) |
| anti-cheat-guard | 100 | 0.0003 (3) | Pending / no equivalent |
| anti-cheat-guard | 1000 | 0.0037 (3) | Pending / no equivalent |
| anti-cheat-process-scan | 1 | 0.0093 (3) | Pending / no equivalent |
| anti-cheat-process-scan | 10 | 0.0915 (3) | Pending / no equivalent |
| asset-async-cache | 1 | 1.1822 (3) | Pending / no equivalent |
| asset-async-cold | 1 | 1.7948 (5) | Pending / no equivalent |
| asset-image-decode | 1 | 1.0564 (3) | 0.8455 (3) |
| asset-image-decode | 100 | 106.5083 (3) | 90.9627 (3) |
| asset-model-load | 1 | 1.2360 (3) | Pending / no equivalent |
| asset-model-load | 10 | 12.4073 (3) | Pending / no equivalent |
| asset-pack-read | 1 | 0.1099 (3) | Pending / no equivalent |
| asset-pack-read | 10 | 1.0960 (3) | Pending / no equivalent |
| audio-hrtf | 1 | 0.1450 (3) | Pending / no equivalent |
| audio-hrtf | 10 | 1.2064 (3) | Pending / no equivalent |
| audio-mix | 1 | 0.0407 (3) | 0.0331 (3) |
| audio-mix | 10 | 0.1600 (3) | 0.0447 (3) |
| audio-mix | 100 | 1.3722 (3) | 0.1588 (3) |
| baking-lightmap | 1 | 4.0709 (3) | Pending / no equivalent |
| baking-lightmap | 10 | 4.4723 (3) | Pending / no equivalent |
| baking-uv | 1 | 0.0865 (3) | Pending / no equivalent |
| baking-uv | 10 | 0.8409 (3) | Pending / no equivalent |
| dialogue-condition | 100 | 0.0183 (3) | Pending / no equivalent |
| dialogue-condition | 1000 | 0.1835 (3) | Pending / no equivalent |
| dialogue-parse | 100 | 0.0651 (3) | Pending / no equivalent |
| dialogue-parse | 1000 | 2.5203 (3) | Pending / no equivalent |
| editor-api-index | 1 | 22.9440 (3) | Pending / no equivalent |
| editor-code-completion | 10 | 0.0089 (3) | Pending / no equivalent |
| editor-code-completion | 100 | 0.0867 (3) | Pending / no equivalent |
| editor-code-index | 10 | 0.0095 (3) | Pending / no equivalent |
| editor-code-index | 100 | 0.0963 (3) | Pending / no equivalent |
| editor-graph-generate | 10 | 0.0026 (3) | Pending / no equivalent |
| editor-graph-generate | 100 | 0.0293 (3) | Pending / no equivalent |
| editor-graph-validate | 10 | 0.0004 (3) | Pending / no equivalent |
| editor-graph-validate | 100 | 0.0091 (3) | Pending / no equivalent |
| editor-theme-parse | 10 | 0.3462 (3) | Pending / no equivalent |
| editor-theme-parse | 100 | 3.4785 (3) | Pending / no equivalent |
| graph-blackboard | 100 | 0.0054 (3) | Pending / no equivalent |
| graph-blackboard | 1000 | 0.0530 (3) | Pending / no equivalent |
| http-local | 1 | 0.1033 (3) | 0.1201 (3) |
| http-local | 10 | 0.9630 (3) | 1.1636 (3) |
| input-parse | 100 | 0.0348 (3) | Pending / no equivalent |
| input-parse | 1000 | 0.3400 (3) | Pending / no equivalent |
| model-algorithm-array | 1 | 0.0147 (3) | Pending / no equivalent |
| model-algorithm-array | 10 | 0.1433 (3) | Pending / no equivalent |
| model-algorithm-bevel | 1 | 0.0353 (3) | Pending / no equivalent |
| model-algorithm-bevel | 100 | 3.5429 (3) | Pending / no equivalent |
| model-algorithm-csg-subtract | 1 | 0.0251 (3) | Pending / no equivalent |
| model-algorithm-csg-subtract | 10 | 0.2473 (3) | Pending / no equivalent |
| model-algorithm-cube | 1 | 0.0043 (3) | Pending / no equivalent |
| model-algorithm-cube | 100 | 0.4229 (3) | Pending / no equivalent |
| model-algorithm-decimate | 1 | 0.0806 (3) | Pending / no equivalent |
| model-algorithm-decimate | 10 | 0.7784 (3) | Pending / no equivalent |
| model-algorithm-extrude | 1 | 0.0173 (3) | Pending / no equivalent |
| model-algorithm-extrude | 100 | 1.7252 (3) | Pending / no equivalent |
| model-algorithm-inset | 1 | 0.0197 (3) | Pending / no equivalent |
| model-algorithm-inset | 10 | 0.1893 (3) | Pending / no equivalent |
| model-algorithm-large-subdivide | 1 | 73.1569 (3) | Pending / no equivalent |
| model-algorithm-large-uv-smart | 1 | 19.6030 (3) | Pending / no equivalent |
| model-algorithm-loopcut | 1 | 0.0232 (3) | Pending / no equivalent |
| model-algorithm-loopcut | 10 | 0.1872 (3) | Pending / no equivalent |
| model-algorithm-mirror | 1 | 0.0115 (3) | Pending / no equivalent |
| model-algorithm-mirror | 10 | 0.1126 (3) | Pending / no equivalent |
| model-algorithm-poke | 1 | 0.0106 (3) | Pending / no equivalent |
| model-algorithm-poke | 10 | 0.0948 (3) | Pending / no equivalent |
| model-algorithm-primitives | 1 | 0.0044 (3) | Pending / no equivalent |
| model-algorithm-primitives | 10 | 0.3381 (3) | Pending / no equivalent |
| model-algorithm-primitives | 12 | 0.3955 (3) | Pending / no equivalent |
| model-algorithm-primitives | 120 | 3.9405 (3) | Pending / no equivalent |
| model-algorithm-solidify | 1 | 0.0091 (3) | Pending / no equivalent |
| model-algorithm-solidify | 10 | 0.0899 (3) | Pending / no equivalent |
| model-algorithm-split-edge | 1 | 0.0051 (3) | Pending / no equivalent |
| model-algorithm-split-edge | 10 | 0.0470 (3) | Pending / no equivalent |
| model-algorithm-subdivide | 1 | 0.0183 (3) | Pending / no equivalent |
| model-algorithm-subdivide | 100 | 1.7653 (3) | Pending / no equivalent |
| model-algorithm-triangulate | 1 | 0.0079 (3) | Pending / no equivalent |
| model-algorithm-triangulate | 10 | 0.0646 (3) | Pending / no equivalent |
| model-algorithm-uv | 1 | 0.0047 (3) | Pending / no equivalent |
| model-algorithm-uv | 10 | 0.0470 (3) | Pending / no equivalent |
| model-algorithm-uv-cylinder | 1 | 0.0049 (3) | Pending / no equivalent |
| model-algorithm-uv-cylinder | 10 | 0.0464 (3) | Pending / no equivalent |
| model-algorithm-uv-pack | 1 | 0.0151 (3) | Pending / no equivalent |
| model-algorithm-uv-pack | 10 | 0.1497 (3) | Pending / no equivalent |
| model-algorithm-uv-planar | 1 | 0.0050 (3) | Pending / no equivalent |
| model-algorithm-uv-planar | 10 | 0.0484 (3) | Pending / no equivalent |
| model-algorithm-uv-smart | 1 | 0.0119 (3) | Pending / no equivalent |
| model-algorithm-uv-smart | 10 | 0.1149 (3) | Pending / no equivalent |
| model-algorithm-uv-sphere | 1 | 0.0051 (3) | Pending / no equivalent |
| model-algorithm-uv-sphere | 10 | 0.0491 (3) | Pending / no equivalent |
| model-algorithm-uv-unwrap | 1 | 0.0128 (3) | Pending / no equivalent |
| model-algorithm-uv-unwrap | 10 | 0.1265 (3) | Pending / no equivalent |
| model-algorithm-weld | 1 | 0.0052 (3) | Pending / no equivalent |
| model-algorithm-weld | 100 | 0.5190 (3) | Pending / no equivalent |
| model-object-bevel | 1 | 0.0576 (3) | 0.6494 (3) |
| model-object-bevel | 100 | 5.6582 (3) | 66.3506 (3) |
| model-object-cube | 1 | 0.0117 (3) | 0.0579 (3) |
| model-object-cube | 100 | 1.1320 (3) | 8.4450 (3) |
| model-object-extrude | 1 | 0.0413 (3) | 0.2424 (3) |
| model-object-extrude | 100 | 3.8903 (3) | 25.9415 (3) |
| model-object-subdivide | 1 | 0.0383 (3) | 0.7461 (3) |
| model-object-subdivide | 100 | 3.7239 (3) | 78.8734 (3) |
| model-object-weld | 1 | 0.0127 (3) | 0.0978 (3) |
| model-object-weld | 100 | 1.2426 (3) | 13.8069 (3) |
| network-compress | 1 | 0.7795 (3) | Pending / no equivalent |
| network-compress | 10 | 7.8018 (3) | Pending / no equivalent |
| network-loopback | 1 | 0.0083 (3) | Pending / no equivalent |
| network-loopback | 10 | 0.0100 (3) | Pending / no equivalent |
| network-snapshot-pack | 100 | 0.0088 (3) | Pending / no equivalent |
| network-snapshot-pack | 1000 | 0.0881 (3) | Pending / no equivalent |
| physics-boxcast | 100 | 0.5574 (3) | 0.3960 (3) |
| physics-boxcast | 1000 | 0.7922 (3) | 0.5755 (3) |
| physics-capsulecast | 100 | 0.5935 (3) | 0.4133 (3) |
| physics-capsulecast | 1000 | 0.8875 (3) | 0.6279 (3) |
| physics-ccd | 100 | 0.0549 (3) | 0.2152 (3) |
| physics-ccd | 1000 | 0.4729 (3) | 1.3486 (3) |
| physics-characters-flat | 100 | 0.0898 (3) | 0.1262 (3) |
| physics-characters-flat | 1000 | 0.7899 (3) | 0.8687 (3) |
| physics-characters-steps | 100 | 0.0904 (3) | 0.0880 (3) |
| physics-characters-steps | 1000 | 0.7878 (3) | 0.8396 (3) |
| physics-discrete | 100 | 0.0294 (3) | 0.0401 (3) |
| physics-discrete | 1000 | 0.1850 (3) | 0.2183 (3) |
| physics-free | 100 | 0.0224 (3) | 0.0389 (3) |
| physics-free | 1000 | 0.1302 (3) | 0.1771 (3) |
| physics-joints | 1 | 0.0127 (3) | 0.0252 (3) |
| physics-joints | 100 | 0.0768 (3) | 0.0677 (3) |
| physics-mesh | 100 | 0.0477 (3) | 0.1151 (3) |
| physics-mesh | 1000 | 0.6795 (3) | 0.6315 (3) |
| physics-mesh-raycast | 100 | 0.3942 (3) | 0.2951 (3) |
| physics-mesh-raycast | 1000 | 0.5382 (3) | 0.4109 (3) |
| physics-mixed-shapes | 100 | 0.0449 (3) | 0.0634 (3) |
| physics-mixed-shapes | 1000 | 0.5036 (3) | 0.5272 (3) |
| physics-overlap-box | 100 | 0.4432 (3) | 0.1929 (3) |
| physics-overlap-box | 1000 | 1.3436 (3) | 0.2647 (3) |
| physics-overlap-capsule | 100 | 1.1373 (3) | 0.1812 (3) |
| physics-overlap-capsule | 1000 | 3.7549 (3) | 0.2882 (3) |
| physics-overlap-sphere | 100 | 2.0720 (3) | 0.1977 (3) |
| physics-overlap-sphere | 1000 | 7.9879 (3) | 0.4195 (3) |
| physics-pile | 100 | 0.0714 (3) | 0.1042 (3) |
| physics-pile | 1000 | 0.6953 (3) | 0.5208 (3) |
| physics-raycast | 100 | 0.1483 (3) | 0.2375 (3) |
| physics-raycast | 1000 | 0.2893 (3) | 0.3535 (3) |
| physics-spherecast | 100 | 0.5293 (3) | 0.3826 (3) |
| physics-spherecast | 1000 | 0.8513 (3) | 0.5884 (3) |
| render-ao | 100 | 0.1422 (3) | 0.2815 (3) |
| render-ao | 1000 | 0.3218 (3) | 0.6374 (3) |
| render-ao@1920x1080 | 1000 | 0.3237 (3) | 0.6376 (3) |
| render-bloom | 100 | 0.1229 (3) | 0.3861 (3) |
| render-bloom | 1000 | 0.2676 (3) | 0.8278 (3) |
| render-culling | 100 | 0.1105 (3) | 0.1690 (3) |
| render-culling | 1000 | 0.2006 (3) | 0.2030 (3) |
| render-culling | 10000 | 1.0815 (3) | 0.5362 (3) |
| render-dof | 100 | 0.1946 (3) | 0.2671 (3) |
| render-dof | 1000 | 0.3089 (3) | 0.5884 (3) |
| render-grading | 100 | 0.1224 (3) | 0.2636 (3) |
| render-grading | 1000 | 0.2565 (3) | 0.5874 (3) |
| render-lights | 100 | 0.1259 (3) | 0.5253 (3) |
| render-lights | 1000 | 0.2457 (3) | 1.6490 (3) |
| render-lights | 10000 | 1.6104 (3) | 37.0381 (3) |
| render-materials | 100 | 0.2460 (3) | 0.2936 (3) |
| render-materials | 1000 | 1.5426 (3) | 0.7544 (3) |
| render-materials | 10000 | 14.8785 (3) | 4.0636 (3) |
| render-motion-blur | 100 | 0.1379 (3) | 0.2763 (3) |
| render-motion-blur | 1000 | 0.3058 (3) | 0.5981 (3) |
| render-moving | 100 | 0.1277 (3) | 0.2419 (3) |
| render-moving | 1000 | 0.3053 (3) | 0.5705 (3) |
| render-moving | 10000 | 2.3023 (3) | 3.2189 (3) |
| render-particles | 100 | 0.1095 (3) | 0.1951 (3) |
| render-particles | 1000 | 0.1907 (3) | 0.4355 (3) |
| render-particles | 10000 | 0.9717 (3) | 8.0003 (3) |
| render-physics | 100 | 0.1242 (3) | 0.3027 (3) |
| render-physics | 1000 | 0.2866 (3) | 1.0042 (3) |
| render-physics | 10000 | 2.0550 (3) | 16.4071 (3) |
| render-reflections | 100 | 0.1438 (3) | 0.3094 (3) |
| render-reflections | 1000 | 0.3914 (3) | 0.6645 (3) |
| render-shadows | 100 | 0.1541 (3) | 0.2601 (3) |
| render-shadows | 1000 | 0.3712 (3) | 0.8888 (3) |
| render-shadows | 10000 | 2.9772 (3) | 5.6319 (3) |
| render-shared | 100 | 0.1291 (3) | 0.2209 (3) |
| render-shared | 1000 | 0.2363 (3) | 0.5211 (3) |
| render-shared | 10000 | 1.5456 (3) | 2.4536 (3) |
| render-shared@1920x1080 | 1000 | 0.2634 (3) | 0.5426 (3) |
| render-skinning-cpu | 1 | 0.2421 (3) | 0.1876 (3) |
| render-skinning-cpu | 10 | 1.3314 (3) | 0.2740 (3) |
| render-skinning-cpu | 100 | 12.9152 (3) | 0.9944 (3) |
| render-skinning-gpu | 1 | 0.1194 (3) | 0.1828 (3) |
| render-skinning-gpu | 10 | 0.1828 (3) | 0.2687 (3) |
| render-skinning-gpu | 100 | 0.8586 (3) | 0.6225 (3) |
| render-skinning-gpu@1920x1080 | 1000 | 8.5533 (3) | 4.1077 (3) |
| render-spheres | 100 | 0.1181 (3) | 0.2424 (3) |
| render-spheres | 1000 | 0.2575 (3) | 0.6896 (3) |
| render-spheres | 10000 | 1.5691 (3) | 5.1944 (3) |
| render-transparency | 100 | 0.2397 (3) | 0.3116 (3) |
| render-transparency | 1000 | 1.5810 (3) | 0.7828 (3) |
| rig-autoweights | 1 | 22.9156 (3) | Pending / no equivalent |
| rig-autoweights | 10 | 228.9713 (3) | Pending / no equivalent |
| rig-pose | 1 | 0.3490 (3) | Pending / no equivalent |
| rig-pose | 10 | 3.4669 (3) | Pending / no equivalent |
| rig-weight-brush | 1 | 0.0508 (3) | Pending / no equivalent |
| rig-weight-brush | 10 | 0.4454 (3) | Pending / no equivalent |
| save-binary-decode | 100 | 0.0074 (3) | Pending / no equivalent |
| save-binary-decode | 1000 | 0.0787 (3) | Pending / no equivalent |
| save-binary-encode | 100 | 0.0049 (3) | Pending / no equivalent |
| save-binary-encode | 1000 | 0.0503 (3) | Pending / no equivalent |
| save-json-decode | 1 | 0.0004 (3) | 0.0019 (3) |
| save-json-decode | 100 | 0.0257 (3) | 0.0366 (3) |
| save-json-encode | 1 | 0.0002 (3) | 0.0012 (3) |
| save-json-encode | 100 | 0.0088 (3) | 0.0151 (3) |
| scene-churn | 100 | 0.0261 (3) | 0.2021 (3) |
| scene-churn | 1000 | 0.5909 (3) | 2.1335 (3) |
| scene-empty | 100 | 0.0001 (3) | 0.0002 (3) |
| scene-empty | 1000 | 0.0001 (3) | 0.0002 (2) |
| scene-hierarchy | 100 | 0.0089 (3) | 0.0070 (3) |
| scene-hierarchy | 1000 | 0.0907 (3) | 0.0681 (3) |
| scene-scripts | 100 | 0.0024 (3) | 0.0037 (3) |
| scene-scripts | 1000 | 0.0230 (3) | 0.0355 (3) |
| scene-transforms | 100 | 0.0028 (3) | 0.0056 (3) |
| scene-transforms | 1000 | 0.0258 (3) | 0.0542 (3) |
| sequence-evaluate | 100 | 0.0165 (3) | Pending / no equivalent |
| sequence-evaluate | 1000 | 0.1591 (3) | Pending / no equivalent |
| sequence-parse | 100 | 0.0895 (3) | Pending / no equivalent |
| sequence-parse | 1000 | 0.8891 (3) | Pending / no equivalent |
| terrain-mesh | 1 | 1.3925 (3) | Pending / no equivalent |
| terrain-mesh | 10 | 2.7111 (3) | Pending / no equivalent |
| terrain-noise | 1 | 0.0994 (3) | Pending / no equivalent |
| terrain-noise | 10 | 1.7391 (3) | Pending / no equivalent |
| texture-mips-color | 1 | 0.9230 (3) | Pending / no equivalent |
| texture-mips-color | 10 | 9.1749 (3) | Pending / no equivalent |
| texture-mips-normal | 1 | 1.5980 (3) | Pending / no equivalent |
| texture-mips-normal | 10 | 16.0303 (3) | Pending / no equivalent |
| texture-paint | 1 | 0.5113 (3) | Pending / no equivalent |
| texture-paint | 10 | 5.1309 (3) | Pending / no equivalent |
| ui-layout | 100 | 0.0981 (3) | Pending / no equivalent |
| ui-layout | 1000 | 0.4733 (3) | Pending / no equivalent |
| ui-parse | 100 | 0.0315 (3) | Pending / no equivalent |
| ui-parse | 1000 | 0.1465 (3) | Pending / no equivalent |
| voice-decode | 1 | 0.0086 (3) | Pending / no equivalent |
| voice-decode | 10 | 0.0824 (3) | Pending / no equivalent |
| voice-encode | 1 | 0.1327 (3) | Pending / no equivalent |
| voice-encode | 10 | 1.2601 (3) | Pending / no equivalent |
| voxel-carve | 1 | 0.6385 (3) | Pending / no equivalent |
| voxel-carve | 10 | 6.3557 (3) | Pending / no equivalent |
| voxel-rebuild | 1 | 0.5447 (3) | Pending / no equivalent |
| voxel-rebuild | 10 | 5.4080 (3) | Pending / no equivalent |

## Result locations

- 20261027-171258: historical benchmark root/full-engine/results/20261027-171258/report.md
- 20261027-171400: historical benchmark root/full-engine/results/20261027-171400/report.md
- 20261027-172520: historical benchmark root/full-engine/results/20261027-172520/report.md
- 20261027-172540: historical benchmark root/full-engine/results/20261027-172540/report.md
- 20261027-172744: historical benchmark root/full-engine/results/20261027-172744/report.md
- 20261027-172834: historical benchmark root/full-engine/results/20261027-172834/report.md
- 20261027-172844: historical benchmark root/full-engine/results/20261027-172844/report.md
- 20261027-173316: historical benchmark root/full-engine/results/20261027-173316/report.md
- 20261027-173348: historical benchmark root/full-engine/results/20261027-173348/report.md
- 20261027-173621: historical benchmark root/full-engine/results/20261027-173621/report.md
- 20261027-173929: historical benchmark root/full-engine/results/20261027-173929/report.md
- 20261027-174441: historical benchmark root/full-engine/results/20261027-174441/report.md
- 20261027-174845: historical benchmark root/full-engine/results/20261027-174845/report.md
- 20261027-175018: historical benchmark root/full-engine/results/20261027-175018/report.md
- 20261027-175307: historical benchmark root/full-engine/results/20261027-175307/report.md
- 20261027-175313: historical benchmark root/full-engine/results/20261027-175313/report.md
- 20261027-175317: historical benchmark root/full-engine/results/20261027-175317/report.md
- 20261027-175513: historical benchmark root/full-engine/results/20261027-175513/report.md
- 20261027-175559-925240: historical benchmark root/full-engine/results/20261027-175559-925240/report.md
- 20261027-175600-593591: historical benchmark root/full-engine/results/20261027-175600-593591/report.md
- 20261027-175627-728245: historical benchmark root/full-engine/results/20261027-175627-728245/report.md
- 20261027-175654-815908: historical benchmark root/full-engine/results/20261027-175654-815908/report.md
- 20261027-180235-436406: historical benchmark root/full-engine/results/20261027-180235-436406/report.md
- 20261027-180334-304828: historical benchmark root/full-engine/results/20261027-180334-304828/report.md
- 20261027-180627-701204: historical benchmark root/full-engine/results/20261027-180627-701204/report.md
- 20261027-180635-380731: historical benchmark root/full-engine/results/20261027-180635-380731/report.md
- 20261027-180936-130869: historical benchmark root/full-engine/results/20261027-180936-130869/report.md
- 20261027-180938-706616: historical benchmark root/full-engine/results/20261027-180938-706616/report.md
- 20261027-180939-060530: historical benchmark root/full-engine/results/20261027-180939-060530/report.md
- 20261027-181624-897467: historical benchmark root/full-engine/results/20261027-181624-897467/report.md
- 20261027-181715-487508: historical benchmark root/full-engine/results/20261027-181715-487508/report.md
- 20261027-181828-386064: historical benchmark root/full-engine/results/20261027-181828-386064/report.md
- 20261027-181856-107631: historical benchmark root/full-engine/results/20261027-181856-107631/report.md
- 20261027-181915-231119: historical benchmark root/full-engine/results/20261027-181915-231119/report.md
- 20261027-182022-039876: historical benchmark root/full-engine/results/20261027-182022-039876/report.md
- 20261027-182036-778104: historical benchmark root/full-engine/results/20261027-182036-778104/report.md
- 20261027-182040-466499: historical benchmark root/full-engine/results/20261027-182040-466499/report.md
- 20261027-182109-863971: historical benchmark root/full-engine/results/20261027-182109-863971/report.md
- 20261027-182612-063829: historical benchmark root/full-engine/results/20261027-182612-063829/report.md

## Scope and interpretation

Every discovered feature area is listed above. Pending means it has not yet been performance-tested in this study. No absent result is a pass. No universal engine speed score is assigned. Full engine feature coverage is being expanded following the request to include GPU skinning, modeling and all comparable subsystems.

Methodology and limitations: historical benchmark root/full-engine/README.md
