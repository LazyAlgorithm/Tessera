> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Standalone engine benchmark results

Milliseconds; lower is better. Median of per-run medians. Query timings are per batch of 1,000 queries. Whole-frame intervals include CPU/GPU synchronization and pacing; they are not GPU timestamps.

| Workload | Population | Tessera ms | Unity ms | Unity / Tessera |
|---|---:|---:|---:|---:|
| physics-free | 100 | 0.0244 | incomplete | — |
| physics-free | 1000 | 0.1413 | incomplete | — |
| physics-pile | 100 | 0.0403 | incomplete | — |
| physics-pile | 1000 | 0.4198 | incomplete | — |
| physics-mixed-shapes | 100 | 0.0531 | incomplete | — |
| physics-mixed-shapes | 1000 | 0.5102 | incomplete | — |
| physics-mesh | 100 | 0.0485 | incomplete | — |
| physics-mesh | 1000 | 0.4154 | incomplete | — |
| physics-raycast | 100 | 0.1540 | incomplete | — |
| physics-raycast | 1000 | 0.2985 | incomplete | — |
| physics-mesh-raycast | 100 | 0.3938 | incomplete | — |
| physics-mesh-raycast | 1000 | 0.5392 | incomplete | — |
| physics-spherecast | 100 | 0.5306 | incomplete | — |
| physics-spherecast | 1000 | 0.8217 | incomplete | — |
| physics-capsulecast | 100 | 0.5909 | incomplete | — |
| physics-capsulecast | 1000 | 0.8955 | incomplete | — |
| physics-boxcast | 100 | 0.5553 | incomplete | — |
| physics-boxcast | 1000 | 0.7910 | incomplete | — |
| physics-overlap-sphere | 100 | 0.2332 | incomplete | — |
| physics-overlap-sphere | 1000 | 1.1111 | incomplete | — |
| physics-overlap-capsule | 100 | 0.1611 | incomplete | — |
| physics-overlap-capsule | 1000 | 0.5238 | incomplete | — |
| physics-overlap-box | 100 | 0.1171 | incomplete | — |
| physics-overlap-box | 1000 | 0.2173 | incomplete | — |
| physics-discrete | 100 | 0.0297 | incomplete | — |
| physics-discrete | 1000 | 0.1918 | incomplete | — |
| physics-ccd | 100 | 0.0618 | incomplete | — |
| physics-ccd | 1000 | 0.5136 | incomplete | — |
| physics-characters-flat | 100 | 0.0921 | incomplete | — |
| physics-characters-flat | 1000 | 0.8029 | incomplete | — |
| physics-characters-steps | 100 | 0.1309 | incomplete | — |
| physics-characters-steps | 1000 | 0.7970 | incomplete | — |
| render-shared | 100 | 0.1194 | incomplete | — |
| render-shared | 1000 | 0.2477 | incomplete | — |
| render-materials | 100 | 0.1145 | incomplete | — |
| render-materials | 1000 | 0.2386 | incomplete | — |
| render-moving | 100 | 0.1213 | incomplete | — |
| render-moving | 1000 | 0.3086 | incomplete | — |
| render-culling | 100 | 0.1250 | incomplete | — |
| render-culling | 1000 | 0.1875 | incomplete | — |
| render-shadows | 100 | 0.1574 | incomplete | — |
| render-shadows | 1000 | 0.3764 | incomplete | — |
| render-spheres | 100 | 0.1300 | incomplete | — |
| render-spheres | 1000 | 0.2587 | incomplete | — |
| render-lights | 100 | 0.1384 | incomplete | — |
| render-lights | 1000 | 0.2631 | incomplete | — |
| render-physics | 100 | 0.1220 | incomplete | — |
| render-physics | 1000 | 0.3042 | incomplete | — |
| render-particles | 100 | 0.1176 | incomplete | — |
| render-particles | 1000 | 0.1857 | incomplete | — |
| scene-empty | 100 | 0.0001 | incomplete | — |
| scene-empty | 1000 | 0.0001 | incomplete | — |
| scene-scripts | 100 | 0.0028 | incomplete | — |
| scene-scripts | 1000 | 0.0267 | incomplete | — |
| scene-transforms | 100 | 0.0027 | incomplete | — |
| scene-transforms | 1000 | 0.0263 | incomplete | — |
| scene-hierarchy | 100 | 0.0086 | incomplete | — |
| scene-hierarchy | 1000 | 0.0855 | incomplete | — |
| scene-churn | 100 | 0.0295 | incomplete | — |
| scene-churn | 1000 | 0.9561 | incomplete | — |

Read ../../README.md for scope and interpretation. Rendering uses different native pipelines and is not an equal-image-quality ranking. Scene-empty/scripts are native traversal versus explicit C# calls and are not ranked. CCD and character results require behavior checks.

## Failures

[]
