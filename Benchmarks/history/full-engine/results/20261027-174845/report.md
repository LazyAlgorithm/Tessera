> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Standalone engine benchmark results

Milliseconds; lower is better. Median of per-run medians. Query timings are per batch of 1,000 queries. Whole-frame intervals include CPU/GPU synchronization and pacing; they are not GPU timestamps.

| Workload | Population | Tessera ms | Unity ms | Unity / Tessera |
|---|---:|---:|---:|---:|
| model-object-cube | 1 | 0.0695 | incomplete | — |
| model-object-extrude | 1 | 0.1087 | incomplete | — |
| model-object-subdivide | 1 | 0.0873 | incomplete | — |
| model-object-bevel | 1 | 0.1151 | incomplete | — |
| model-object-weld | 1 | 0.0446 | incomplete | — |
| rig-autoweights | 1 | 25.4109 | incomplete | — |
| rig-weight-brush | 1 | 0.0592 | incomplete | — |
| rig-pose | 1 | 0.3716 | incomplete | — |
| texture-paint | 1 | 0.5289 | incomplete | — |
| texture-mips-color | 1 | 2.9399 | incomplete | — |
| texture-mips-normal | 1 | 1.8436 | incomplete | — |
| asset-async-cold | 1 | 1.6648 | incomplete | — |
| terrain-mesh | 1 | 1.9185 | incomplete | — |

Read ../../README.md for scope and interpretation. Rendering uses different native pipelines and is not an equal-image-quality ranking. Scene-empty/scripts are native traversal versus explicit C# calls and are not ranked. CCD and character results require behavior checks.

## Failures

[]
