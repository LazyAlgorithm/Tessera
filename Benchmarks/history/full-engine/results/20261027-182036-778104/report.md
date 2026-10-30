> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Standalone engine benchmark results

Milliseconds; lower is better. Median of per-run medians. Query timings are per batch of 1,000 queries. Whole-frame intervals include CPU/GPU synchronization and pacing; they are not GPU timestamps.

| Workload | Population | Tessera ms | Unity ms | Unity / Tessera |
|---|---:|---:|---:|---:|
| animation-retarget | 1 | 0.6165 | incomplete | — |
| animation-retarget | 10 | 6.1281 | incomplete | — |
| anti-cheat-process-scan | 1 | 0.0093 | incomplete | — |
| anti-cheat-process-scan | 10 | 0.0915 | incomplete | — |
| model-csg-subtract | 1 | 0.0251 | incomplete | — |
| model-csg-subtract | 10 | 0.2473 | incomplete | — |
| model-mirror | 1 | 0.0115 | incomplete | — |
| model-mirror | 10 | 0.1126 | incomplete | — |
| model-array | 1 | 0.0147 | incomplete | — |
| model-array | 10 | 0.1433 | incomplete | — |
| model-solidify | 1 | 0.0091 | incomplete | — |
| model-solidify | 10 | 0.0899 | incomplete | — |
| model-poke | 1 | 0.0106 | incomplete | — |
| model-poke | 10 | 0.0948 | incomplete | — |
| model-loopcut | 1 | 0.0232 | incomplete | — |
| model-loopcut | 10 | 0.1872 | incomplete | — |
| model-split-edge | 1 | 0.0051 | incomplete | — |
| model-split-edge | 10 | 0.0470 | incomplete | — |
| model-uv-planar | 1 | 0.0050 | incomplete | — |
| model-uv-planar | 10 | 0.0484 | incomplete | — |
| model-uv-cylinder | 1 | 0.0049 | incomplete | — |
| model-uv-cylinder | 10 | 0.0464 | incomplete | — |
| model-uv-sphere | 1 | 0.0051 | incomplete | — |
| model-uv-sphere | 10 | 0.0491 | incomplete | — |
| model-uv-unwrap | 1 | 0.0128 | incomplete | — |
| model-uv-unwrap | 10 | 0.1265 | incomplete | — |
| model-uv-smart | 1 | 0.0119 | incomplete | — |
| model-uv-smart | 10 | 0.1149 | incomplete | — |
| model-uv-pack | 1 | 0.0151 | incomplete | — |
| model-uv-pack | 10 | 0.1497 | incomplete | — |

Read ../../README.md for scope and interpretation. Rendering uses different native pipelines and is not an equal-image-quality ranking. Scene-empty/scripts are native traversal versus explicit C# calls and are not ranked. CCD and character results require behavior checks.

## Failures

[]
