> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Standalone engine benchmark results

Milliseconds; lower is better. Median of per-run medians. Query timings are per batch of 1,000 queries. Whole-frame intervals include CPU/GPU synchronization and pacing; they are not GPU timestamps.

| Workload | Population | Tessera ms | Unity ms | Unity / Tessera |
|---|---:|---:|---:|---:|
| animation-retarget | 1 | 0.8276 | incomplete | — |
| model-csg-subtract | 1 | 0.0599 | incomplete | — |
| model-uv-smart | 1 | 0.0388 | incomplete | — |
| model-large-subdivide | 1 | 72.7956 | incomplete | — |
| model-large-uv-smart | 1 | 20.3309 | incomplete | — |
| anti-cheat-process-scan | 1 | 0.0239 | incomplete | — |

Read ../../README.md for scope and interpretation. Rendering uses different native pipelines and is not an equal-image-quality ranking. Scene-empty/scripts are native traversal versus explicit C# calls and are not ranked. CCD and character results require behavior checks.

## Failures

[]
