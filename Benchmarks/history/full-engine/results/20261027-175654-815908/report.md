> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Standalone engine benchmark results

Milliseconds; lower is better. Median of per-run medians. Query timings are per batch of 1,000 queries. Whole-frame intervals include CPU/GPU synchronization and pacing; they are not GPU timestamps.

| Workload | Population | Tessera ms | Unity ms | Unity / Tessera |
|---|---:|---:|---:|---:|
| render-shared | 10000 | 1.6126 | 2.4536 | 1.52 |
| render-materials | 10000 | 15.0815 | 4.0636 | 0.27 |
| render-moving | 10000 | 2.2225 | 3.2189 | 1.45 |
| render-culling | 10000 | 1.0687 | 0.5362 | 0.50 |
| render-shadows | 10000 | 3.0565 | 5.6319 | 1.84 |
| render-spheres | 10000 | 1.5902 | 5.1944 | 3.27 |
| render-lights | 10000 | 1.5711 | 37.0381 | 23.57 |
| render-physics | 10000 | 2.0510 | 16.4071 | 8.00 |
| render-particles | 10000 | 0.9556 | 8.0003 | 8.37 |

Read ../../README.md for scope and interpretation. Rendering uses different native pipelines and is not an equal-image-quality ranking. Scene-empty/scripts are native traversal versus explicit C# calls and are not ranked. CCD and character results require behavior checks.

## Failures

[]
