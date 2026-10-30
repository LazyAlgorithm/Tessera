> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Standalone engine benchmark results

Milliseconds; lower is better. Median of per-run medians. Query timings are per batch of 1,000 queries. Whole-frame intervals include CPU/GPU synchronization and pacing; they are not GPU timestamps.

| Workload | Population | Tessera ms | Unity ms | Unity / Tessera |
|---|---:|---:|---:|---:|
| render-shared | 100 | 0.1291 | incomplete | — |
| render-shared | 1000 | 0.2363 | incomplete | — |
| render-shared | 10000 | 1.5456 | incomplete | — |
| render-materials | 100 | 0.2460 | incomplete | — |
| render-materials | 1000 | 1.5426 | incomplete | — |
| render-materials | 10000 | 14.8785 | incomplete | — |
| render-moving | 100 | 0.1277 | incomplete | — |
| render-moving | 1000 | 0.3053 | incomplete | — |
| render-moving | 10000 | 2.3023 | incomplete | — |
| render-culling | 100 | 0.1105 | incomplete | — |
| render-culling | 1000 | 0.2006 | incomplete | — |
| render-culling | 10000 | 1.0815 | incomplete | — |
| render-shadows | 100 | 0.1541 | incomplete | — |
| render-shadows | 1000 | 0.3712 | incomplete | — |
| render-shadows | 10000 | 2.9772 | incomplete | — |
| render-spheres | 100 | 0.1181 | incomplete | — |
| render-spheres | 1000 | 0.2575 | incomplete | — |
| render-spheres | 10000 | 1.5691 | incomplete | — |
| render-lights | 100 | 0.1259 | incomplete | — |
| render-lights | 1000 | 0.2457 | incomplete | — |
| render-lights | 10000 | 1.6104 | incomplete | — |
| render-physics | 100 | 0.1242 | incomplete | — |
| render-physics | 1000 | 0.2866 | incomplete | — |
| render-physics | 10000 | 2.0550 | incomplete | — |
| render-particles | 100 | 0.1095 | incomplete | — |
| render-particles | 1000 | 0.1907 | incomplete | — |
| render-particles | 10000 | 0.9717 | incomplete | — |

Read ../../README.md for scope and interpretation. Rendering uses different native pipelines and is not an equal-image-quality ranking. Scene-empty/scripts are native traversal versus explicit C# calls and are not ranked. CCD and character results require behavior checks.

## Failures

[]
