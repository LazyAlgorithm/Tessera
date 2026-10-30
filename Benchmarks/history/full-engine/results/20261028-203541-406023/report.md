> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Standalone engine benchmark results

Milliseconds; lower is better. Median of per-run medians. Query timings are per batch of 1,000 queries. Whole-frame intervals include CPU/GPU synchronization and pacing; they are not GPU timestamps.

| Workload | Population | Tessera ms | Unity ms | Unity / Tessera |
|---|---:|---:|---:|---:|
| render-shared | 10000 | 1.6386 | incomplete | — |
| render-materials | 10000 | 1.5997 | incomplete | — |
| render-culling | 10000 | 0.9266 | incomplete | — |
| render-moving | 10000 | 2.2742 | incomplete | — |
| render-shadows | 10000 | 3.0274 | incomplete | — |
| render-lights | 10000 | 1.5873 | incomplete | — |
| render-particles | 10000 | 0.9831 | incomplete | — |
| scene-transforms | 10000 | 0.2627 | incomplete | — |
| scene-hierarchy | 10000 | 0.8674 | incomplete | — |

Read ../../README.md for scope and interpretation. Rendering uses different native pipelines and is not an equal-image-quality ranking. Scene-empty/scripts are native traversal versus explicit C# calls and are not ranked. CCD and character results require behavior checks.

## Failures

[]
