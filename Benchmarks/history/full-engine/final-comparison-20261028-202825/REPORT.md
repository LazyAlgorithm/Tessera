> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Rebuilt Tessera versus saved Unity baselines

Completed 2026-10-28T20:38:25.271483. **Unity was not rebuilt or executed**, as requested. All current measurements use a fixed engine/native-archive snapshot so concurrent edits in the shared workspace cannot mix implementations between runs. Benchmark inputs/settings are retained; serial NavMesh uses the existing maze/endpoints of the Unity path workload.

## Main results

Milliseconds per listed batch/frame/tick; lower is better. The ratio is Tessera / saved Unity: above 1 takes longer, below 1 takes less time. These are workload comparisons, with the limits below, rather than an overall engine score.

| Workload | Population / batch | Rebuilt Tessera ms | Saved Unity ms | Tessera / Unity |
|---|---:|---:|---:|---:|
| Fresh serial NavMesh paths | 100 | 0.1825 | 0.1075 | 1.70× |
| physics-free | 1000 | 0.1413 | 0.1771 | 0.80× |
| physics-pile | 1000 | 0.4198 | 0.5208 | 0.81× |
| physics-raycast | 1000 | 0.2985 | 0.3535 | 0.84× |
| physics-overlap-sphere | 1000 | 1.1111 | 0.4195 | 2.65× |
| physics-overlap-capsule | 1000 | 0.5238 | 0.2882 | 1.82× |
| physics-overlap-box | 1000 | 0.2173 | 0.2647 | 0.82× |
| render-shared | 1000 | 0.2477 | 0.5211 | 0.48× |
| render-materials | 1000 | 0.2386 | 0.7544 | 0.32× |
| render-culling | 10000 | 0.9266 | 0.5362 | 1.73× |
| render-skinning-cpu | 100 | 4.2719 | 0.9944 | 4.30× |
| render-skinning-gpu | 100 | 0.9008 | 0.6225 | 1.45× |
| animator-clips | 1000 | 2.8800 | 10.4848 | 0.27× |
| animator-layered | 1000 | 14.7666 | 16.3369 | 0.90× |
| audio-mix | 100 | 0.4463 | 0.1588 | 2.81× |
| asset-image-decode | 100 | 107.2191 | 90.9627 | 1.18× |

Fresh serial walking navigation takes **1.70× the saved Unity timing** (69.8% more time), versus 6.07× for the explicit grid control. That is 3.58× less time than the grid in this maze. The final previous NavMesh measurement was 0.183590 ms / 100; this rerun is 0.182538 ms. It does not restore the initial prototype’s 0.127 ms claim.

## Navigation throughput and updates

| Mode | Requests | Tessera ms | Saved Unity ms |
|---|---:|---:|---:|
| Serial | 1 | 0.001984 | 0.0015 |
| Serial | 10 | 0.018134 | 0.0111 |
| Serial | 100 | 0.182538 | 0.1075 |
| Serial | 1000 | 1.823196 | — |
| CPU batch | 1 | 0.001929 | — |
| CPU batch | 10 | 0.010955 | — |
| CPU batch | 100 | 0.029646 | — |
| CPU batch | 1000 | 0.197727 | — |

There is no matching Unity parallel dataset; batch timings are not assigned a cross-engine ratio. Every NavMesh request searches afresh. The historical grid path harness explicitly disables its route cache. All paths must succeed; serial and batched checks retain path-point counts and lengths, which can differ from Unity’s polygon output.

Supplemental cases retain the previous 40 warmup / 120 samples, three processes each. They have no Unity comparison:

| Workload | Count | Grid ms | NavMesh ms |
|---|---:|---:|---:|
| nav-dynamic | 1 | 0.319665 | 0.943268 |
| nav-dynamic | 100 | 0.325887 | 1.272282 |
| nav-crowd | 100 | 0.082925 | 0.083457 |
| nav-crowd | 1000 | 2.760047 | 3.053128 |
| nav-crowd | 2000 | 11.667499 | 12.448552 |

The moving-carve case rebuilds **4 of 144 tiles** per measured move on a 128 m floor, then finds the specified paths. The grid can reuse repeated routes within an iteration; the mesh does not use that route cache. Crowd timing measures moving agents/local avoidance without rigidbody simulation or rendering. It is not a whole-game frame. Carving remains synchronous, and the grid remains faster in this stress case.

## Full measured inventory

The table includes all rerun workload/population combinations. Physics query rows are batches of 1,000 queries against N bodies; simulation rows are per tick. Rendering uses whole-frame intervals. N is characters for skinning/animation, voices for audio, and image decodes for image loading. Baking N=1 means one bake per iteration. Dashes mean no equivalent saved baseline or an intentionally unranked comparison.

### core

| Workload | N | Dimensions | Tessera median ms | Unity median ms | Ratio | Tessera p95 ms | Native process-median range ms |
|---|---:|---|---:|---:|---:|---:|---:|
| physics-free | 100 | — | 0.0244 | 0.0389 | 0.63× | 0.0309 | 0.0221–0.0247 |
| physics-free | 1000 | — | 0.1413 | 0.1771 | 0.80× | 0.1578 | 0.1387–0.1424 |
| physics-pile | 100 | — | 0.0403 | 0.1042 | 0.39× | 0.0757 | 0.0387–0.0750 |
| physics-pile | 1000 | — | 0.4198 | 0.5208 | 0.81× | 0.4787 | 0.4179–0.6587 |
| physics-mixed-shapes | 100 | — | 0.0531 | 0.0634 | 0.84× | 0.0919 | 0.0479–0.0858 |
| physics-mixed-shapes | 1000 | — | 0.5102 | 0.5272 | 0.97× | 0.6034 | 0.5053–0.7748 |
| physics-mesh | 100 | — | 0.0485 | 0.1151 | 0.42× | 0.0566 | 0.0480–0.0871 |
| physics-mesh | 1000 | — | 0.4154 | 0.6315 | 0.66× | 0.4437 | 0.4107–0.6836 |
| physics-raycast | 100 | — | 0.1540 | 0.2375 | 0.65× | 0.1586 | 0.1539–0.1591 |
| physics-raycast | 1000 | — | 0.2985 | 0.3535 | 0.84× | 0.3034 | 0.2962–0.2990 |
| physics-mesh-raycast | 100 | — | 0.3938 | 0.2951 | 1.33× | 0.4000 | 0.3927–0.3955 |
| physics-mesh-raycast | 1000 | — | 0.5392 | 0.4109 | 1.31× | 0.5450 | 0.5378–0.5423 |
| physics-spherecast | 100 | — | 0.5306 | 0.3826 | 1.39× | 0.5393 | 0.5259–0.5368 |
| physics-spherecast | 1000 | — | 0.8217 | 0.5884 | 1.40× | 0.8319 | 0.8192–0.8258 |
| physics-capsulecast | 100 | — | 0.5909 | 0.4133 | 1.43× | 0.5987 | 0.5868–0.5923 |
| physics-capsulecast | 1000 | — | 0.8955 | 0.6279 | 1.43× | 0.9041 | 0.8843–0.8958 |
| physics-boxcast | 100 | — | 0.5553 | 0.3960 | 1.40× | 0.5648 | 0.5493–0.5703 |
| physics-boxcast | 1000 | — | 0.7910 | 0.5755 | 1.37× | 0.8028 | 0.7904–0.7945 |
| physics-overlap-sphere | 100 | — | 0.2332 | 0.1977 | 1.18× | 0.2399 | 0.2325–0.2335 |
| physics-overlap-sphere | 1000 | — | 1.1111 | 0.4195 | 2.65× | 1.1709 | 1.1093–1.1200 |
| physics-overlap-capsule | 100 | — | 0.1611 | 0.1812 | 0.89× | 0.1657 | 0.1593–0.1765 |
| physics-overlap-capsule | 1000 | — | 0.5238 | 0.2882 | 1.82× | 0.5343 | 0.5234–0.5425 |
| physics-overlap-box | 100 | — | 0.1171 | 0.1929 | 0.61× | 0.1210 | 0.1158–0.1187 |
| physics-overlap-box | 1000 | — | 0.2173 | 0.2647 | 0.82× | 0.2235 | 0.2171–0.2238 |
| physics-discrete | 100 | — | 0.0297 | 0.0401 | 0.74× | 0.0473 | 0.0271–0.0474 |
| physics-discrete | 1000 | — | 0.1918 | 0.2183 | 0.88× | 0.2010 | 0.1915–0.3658 |
| physics-ccd | 100 | — | 0.0618 | 0.2152 | 0.29× | 0.1008 | 0.0556–0.1011 |
| physics-ccd | 1000 | — | 0.5136 | 1.3486 | 0.38× | 0.8708 | 0.4915–0.8240 |
| physics-characters-flat | 100 | — | 0.0921 | 0.1262 | — | 0.1326 | 0.0917–0.1419 |
| physics-characters-flat | 1000 | — | 0.8029 | 0.8687 | — | 0.8255 | 0.7920–1.2246 |
| physics-characters-steps | 100 | — | 0.1309 | 0.0880 | — | 0.1422 | 0.0894–0.1434 |
| physics-characters-steps | 1000 | — | 0.7970 | 0.8396 | — | 0.8191 | 0.7857–1.2314 |
| render-shared | 100 | 1280×720 | 0.1194 | 0.2209 | 0.54× | 0.1407 | 0.1138–0.1300 |
| render-shared | 1000 | 1280×720 | 0.2477 | 0.5211 | 0.48× | 0.2656 | 0.2401–0.2589 |
| render-materials | 100 | 1280×720 | 0.1145 | 0.2936 | 0.39× | 0.1377 | 0.1131–0.1212 |
| render-materials | 1000 | 1280×720 | 0.2386 | 0.7544 | 0.32× | 0.2489 | 0.2383–0.2509 |
| render-moving | 100 | 1280×720 | 0.1213 | 0.2419 | 0.50× | 0.1351 | 0.1211–0.1283 |
| render-moving | 1000 | 1280×720 | 0.3086 | 0.5705 | 0.54× | 0.3311 | 0.3076–0.3192 |
| render-culling | 100 | 1280×720 | 0.1250 | 0.1690 | 0.74× | 0.1852 | 0.1094–0.1258 |
| render-culling | 1000 | 1280×720 | 0.1875 | 0.2030 | 0.92× | 0.2134 | 0.1791–0.2000 |
| render-shadows | 100 | 1280×720 | 0.1574 | 0.2601 | 0.60× | 0.2143 | 0.1566–0.1576 |
| render-shadows | 1000 | 1280×720 | 0.3764 | 0.8888 | 0.42× | 0.3854 | 0.3610–0.3794 |
| render-spheres | 100 | 1280×720 | 0.1300 | 0.2424 | — | 0.1529 | 0.1212–0.1306 |
| render-spheres | 1000 | 1280×720 | 0.2587 | 0.6896 | — | 0.2768 | 0.2466–0.2597 |
| render-lights | 100 | 1280×720 | 0.1384 | 0.5253 | 0.26× | 0.1540 | 0.1295–0.1387 |
| render-lights | 1000 | 1280×720 | 0.2631 | 1.6490 | 0.16× | 0.2984 | 0.2567–0.2646 |
| render-physics | 100 | 1280×720 | 0.1220 | 0.3027 | — | 0.1427 | 0.1218–0.1372 |
| render-physics | 1000 | 1280×720 | 0.3042 | 1.0042 | — | 0.3433 | 0.3011–0.3087 |
| render-particles | 100 | 1280×720 | 0.1176 | 0.1951 | 0.60× | 0.1453 | 0.1100–0.1260 |
| render-particles | 1000 | 1280×720 | 0.1857 | 0.4355 | 0.43× | 0.2427 | 0.1853–0.1944 |
| scene-empty | 100 | — | 0.0001 | 0.0002 | — | 0.0001 | 0.0001–0.0001 |
| scene-empty | 1000 | — | 0.0001 | — | — | 0.0001 | 0.0001–0.0001 |
| scene-scripts | 100 | — | 0.0028 | 0.0037 | — | 0.0028 | 0.0027–0.0028 |
| scene-scripts | 1000 | — | 0.0267 | 0.0355 | — | 0.0274 | 0.0265–0.0271 |
| scene-transforms | 100 | — | 0.0027 | 0.0056 | 0.49× | 0.0028 | 0.0027–0.0028 |
| scene-transforms | 1000 | — | 0.0263 | 0.0542 | 0.49× | 0.0268 | 0.0260–0.0266 |
| scene-hierarchy | 100 | — | 0.0086 | 0.0070 | 1.23× | 0.0087 | 0.0086–0.0087 |
| scene-hierarchy | 1000 | — | 0.0855 | 0.0681 | 1.26× | 0.0890 | 0.0855–0.0871 |
| scene-churn | 100 | — | 0.0295 | 0.2021 | 0.15× | 0.0305 | 0.0292–0.0300 |
| scene-churn | 1000 | — | 0.9561 | 2.1335 | 0.45× | 0.9794 | 0.9526–0.9609 |

### scale

| Workload | N | Dimensions | Tessera median ms | Unity median ms | Ratio | Tessera p95 ms | Native process-median range ms |
|---|---:|---|---:|---:|---:|---:|---:|
| render-shared | 10000 | 1280×720 | 1.6386 | 2.4536 | 0.67× | 1.7169 | 1.6224–1.7242 |
| render-materials | 10000 | 1280×720 | 1.5997 | 4.0636 | 0.39× | 1.6873 | 1.5892–1.6528 |
| render-culling | 10000 | 1280×720 | 0.9266 | 0.5362 | 1.73× | 0.9373 | 0.8949–0.9606 |
| render-moving | 10000 | 1280×720 | 2.2742 | 3.2189 | 0.71× | 2.4272 | 2.2699–2.3499 |
| render-shadows | 10000 | 1280×720 | 3.0274 | 5.6319 | 0.54× | 3.0866 | 3.0063–3.0495 |
| render-lights | 10000 | 1280×720 | 1.5873 | 37.0381 | 0.04× | 1.6208 | 1.5829–1.6744 |
| render-particles | 10000 | 1280×720 | 0.9831 | 8.0003 | 0.12× | 0.9936 | 0.9682–0.9833 |
| scene-transforms | 10000 | — | 0.2627 | — | — | 0.2705 | 0.2620–0.2670 |
| scene-hierarchy | 10000 | — | 0.8674 | — | — | 0.8791 | 0.8640–0.8752 |

### navigation

| Workload | N | Dimensions | Tessera median ms | Unity median ms | Ratio | Tessera p95 ms | Native process-median range ms |
|---|---:|---|---:|---:|---:|---:|---:|
| ai-navmesh-path | 1 | — | 0.0020 | 0.0015 | 1.32× | 0.0021 | 0.0019–0.0021 |
| ai-navmesh-path | 10 | — | 0.0181 | 0.0111 | 1.63× | 0.0188 | 0.0181–0.0185 |
| ai-navmesh-path | 100 | — | 0.1825 | 0.1075 | 1.70× | 0.1900 | 0.1815–0.1836 |
| ai-navmesh-path | 1000 | — | 1.8232 | — | — | 1.8573 | 1.8179–1.8821 |
| ai-navmesh-path-batch | 1 | — | 0.0019 | — | — | 0.0020 | 0.0019–0.0020 |
| ai-navmesh-path-batch | 10 | — | 0.0110 | — | — | 0.0137 | 0.0093–0.0126 |
| ai-navmesh-path-batch | 100 | — | 0.0296 | — | — | 0.0347 | 0.0295–0.0363 |
| ai-navmesh-path-batch | 1000 | — | 0.1977 | — | — | 0.2128 | 0.1931–0.2006 |

### grid-control

| Workload | N | Dimensions | Tessera median ms | Unity median ms | Ratio | Tessera p95 ms | Native process-median range ms |
|---|---:|---|---:|---:|---:|---:|---:|
| ai-nav-path | 100 | — | 0.6528 | 0.1075 | 6.07× | 0.6657 | 0.6499–0.6740 |

### baking

| Workload | N | Dimensions | Tessera median ms | Unity median ms | Ratio | Tessera p95 ms | Native process-median range ms |
|---|---:|---|---:|---:|---:|---:|---:|
| ai-navmesh-bake | 1 | — | 4.2040 | 2.3639 | 1.78× | 4.2803 | 4.1828–4.2046 |
| ai-nav-bake | 1 | — | 6.2645 | 2.3639 | 2.65× | 6.3334 | 6.2320–6.2894 |

### skinning

| Workload | N | Dimensions | Tessera median ms | Unity median ms | Ratio | Tessera p95 ms | Native process-median range ms |
|---|---:|---|---:|---:|---:|---:|---:|
| render-skinning-cpu | 100 | 1280×720 | 4.2719 | 0.9944 | 4.30× | 8.3441 | 4.2076–4.3412 |
| render-skinning-gpu | 100 | 1280×720 | 0.9008 | 0.6225 | 1.45× | 1.0339 | 0.8847–1.3552 |

### skinning-1080

| Workload | N | Dimensions | Tessera median ms | Unity median ms | Ratio | Tessera p95 ms | Native process-median range ms |
|---|---:|---|---:|---:|---:|---:|---:|
| render-skinning-gpu | 1000 | 1920×1080 fullscreen | 10.0246 | 4.1077 | 2.44× | 20.2256 | 9.9953–10.0462 |

### transparency

| Workload | N | Dimensions | Tessera median ms | Unity median ms | Ratio | Tessera p95 ms | Native process-median range ms |
|---|---:|---|---:|---:|---:|---:|---:|
| render-transparency | 1000 | 1280×720 | 0.3061 | 0.7828 | 0.39× | 0.3189 | 0.2927–0.3139 |

### animation

| Workload | N | Dimensions | Tessera median ms | Unity median ms | Ratio | Tessera p95 ms | Native process-median range ms |
|---|---:|---|---:|---:|---:|---:|---:|
| animator-clips | 100 | — | 0.2849 | 0.7680 | 0.37× | 0.2936 | 0.2843–0.2870 |
| animator-clips | 1000 | — | 2.8800 | 10.4848 | 0.27× | 2.9643 | 2.8737–2.8840 |
| animator-layered | 100 | — | 1.4370 | 1.1102 | 1.29× | 1.4534 | 1.4296–1.4395 |
| animator-layered | 1000 | — | 14.7666 | 16.3369 | 0.90× | 15.1066 | 14.7523–14.9056 |

### audio-image

| Workload | N | Dimensions | Tessera median ms | Unity median ms | Ratio | Tessera p95 ms | Native process-median range ms |
|---|---:|---|---:|---:|---:|---:|---:|
| audio-mix | 100 | — | 0.4463 | 0.1588 | 2.81× | 0.4707 | 0.4449–0.4469 |
| asset-image-decode | 100 | — | 107.2191 | 90.9627 | 1.18× | 107.6610 | 107.2160–107.4298 |

## Comparability and provenance

- Unity inputs are the newest complete saved sets for the exact scenario, population, resolution and fullscreen setting. Warmup/sample counts match every paired row. Unity is 6000.3.27f1 nondevelopment Mono standalone; CPU/GPU skinning remain separate baseline builds. The original saved environment/source/binary hashes, where recorded, are frozen in unity-baselines.json. Repetition counts may differ (five current navigation processes versus three saved Unity processes); table values always use the median of process medians.
- Core runs use 120 warmup / 300 samples, three processes. Navigation uses five processes at those same sample counts. Baking uses 10 / 100 and audio/image uses 30 / 100 to match their saved datasets. No profiler recording or screenshots are enabled. Native archives are Release -O3; Beef Release uses GNU linking with ThinLTO unavailable.
- All binaries were rebuilt from snapshot/Engine and the captured native archive. The shared workspace was undergoing navigation API refactoring. Four snapshot-only call sites were adapted from struct arguments to the captured parameter API, preserving the same field values/flags. See snapshot-adapters.patch. Those adaptations did not change live engine files or workload geometry/settings. This measures the captured build, not edits made after the snapshot.
- Whole-file source hashes are recorded in definition-checks.json; differences include added unrelated workloads and do not prove equivalent definitions by themselves. The relevant branch audit is documented in workload-audit.md. Historical render-spheres timings are retained for reference but their ratios are excluded because sphere winding/normals changed. NavMesh serial/bake scenario aliases map to Unity’s existing ai-nav-path/ai-nav-bake definitions. Representation, contour construction and native bake integration differ even with matching geometry/agent inputs.
- Rendering pipelines and image quality differ, so lower whole-frame intervals are not an equal-image-quality engine ranking. Rendering includes synchronization/pacing rather than isolated GPU timestamps. Render-physics advances differing simulated time per rendered frame; its ratio is omitted. Character motor behavior and empty/script scene traversal differ; those ratios are omitted as well.
- Overlap contact detail differs: Tessera collects contacts, Unity returns colliders through NonAlloc APIs. Sphere/capsule/box sweep and ray settings retain their existing workload definitions. Native solver capacity logs were checked and no invalid overflow measurements were accepted. Solver defaults/quality still differ.
- Frozen Unity results were measured earlier. Scheduling, desktop/GPU load, temperature and clocks were not controlled across sessions. Current processes ran sequentially, were not CPU-pinned, and kept desktop applications open. Ranges show process variation, not confidence intervals. No universal engine score is calculated.

## Completion and artifacts

**286 primary processes across 90 workload/population/settings cases, plus 30 supplemental processes, completed successfully.** 82 cases have saved Unity timings. All ten job groups have zero failed runs. The positive NavMesh polygon count, path successes, ray hits, nonfinite-body checks and framebuffer checks confirm the timed work ran. Previous game/engine regression results are separate from this performance-only rerun.

- [Comparison CSV](comparison.csv), [job manifest](manifest.json), [build hashes](builds.json), [frozen Unity inputs](unity-baselines.json), [definition checks](definition-checks.json), [workload audit](workload-audit.md).
- [Supplemental data](supplemental.csv), [supplemental commands/checks](../../archives/full-engine-02.tar.gz), [runner](../../archives/full-engine-02.tar.gz), [source hashes](snapshot-sha256.json), [snapshot adapters](../../archives/full-engine-02.tar.gz).
- Every job links its raw samples, checks, environment and logs below. Archived logs from the initial build attempts are not treated as measurements. No Unity process, user game scene, or shipping build was changed for this rerun.

- core: [report](../results/20261028-203456-438323/report.md), [samples](../../archives/full-engine-22.tar.gz), [checks](../../archives/full-engine-22.tar.gz), [environment](../results/20261028-203456-438323/environment.json).
- scale: [report](../results/20261028-203541-406023/report.md), [samples](../../archives/full-engine-23.tar.gz), [checks](../../archives/full-engine-23.tar.gz), [environment](../results/20261028-203541-406023/environment.json).
- navigation: [report](../results/20261028-203607-108299/report.md), [samples](../../archives/full-engine-23.tar.gz), [checks](../../archives/full-engine-23.tar.gz), [environment](../results/20261028-203607-108299/environment.json).
- grid-control: [report](../results/20261028-203612-785879/report.md), [samples](../../archives/full-engine-23.tar.gz), [checks](../../archives/full-engine-23.tar.gz), [environment](../results/20261028-203612-785879/environment.json).
- baking: [report](../results/20261028-203613-935299/report.md), [samples](../../archives/full-engine-23.tar.gz), [checks](../../archives/full-engine-23.tar.gz), [environment](../results/20261028-203613-935299/environment.json).
- skinning: [report](../results/20261028-203617-706802/report.md), [samples](../../archives/full-engine-23.tar.gz), [checks](../../archives/full-engine-23.tar.gz), [environment](../results/20261028-203617-706802/environment.json).
- skinning-1080: [report](../results/20261028-203628-186253/report.md), [samples](../../archives/full-engine-23.tar.gz), [checks](../../archives/full-engine-23.tar.gz), [environment](../results/20261028-203628-186253/environment.json).
- transparency: [report](../results/20261028-203654-738701/report.md), [samples](../../archives/full-engine-23.tar.gz), [checks](../../archives/full-engine-23.tar.gz), [environment](../results/20261028-203654-738701/environment.json).
- animation: [report](../results/20261028-203656-265313/report.md), [samples](../../archives/full-engine-23.tar.gz), [checks](../../archives/full-engine-23.tar.gz), [environment](../results/20261028-203656-265313/environment.json).
- audio-image: [report](../results/20261028-203722-229084/report.md), [samples](../../archives/full-engine-23.tar.gz), [checks](../../archives/full-engine-23.tar.gz), [environment](../results/20261028-203722-229084/environment.json).
