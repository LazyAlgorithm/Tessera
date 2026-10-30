> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Standalone engine benchmark results

Milliseconds; lower is better. Median of per-run medians. Query timings are per batch of 1,000 queries. Whole-frame intervals include CPU/GPU synchronization and pacing; they are not GPU timestamps.

| Workload | Population | Tessera ms | Unity ms | Unity / Tessera |
|---|---:|---:|---:|---:|
| model-object-cube | 1 | 0.0117 | incomplete | — |
| model-object-cube | 100 | 1.1320 | incomplete | — |
| model-object-extrude | 1 | 0.0413 | incomplete | — |
| model-object-extrude | 100 | 3.8903 | incomplete | — |
| model-object-subdivide | 1 | 0.0383 | incomplete | — |
| model-object-subdivide | 100 | 3.7239 | incomplete | — |
| model-object-bevel | 1 | 0.0576 | incomplete | — |
| model-object-bevel | 100 | 5.6582 | incomplete | — |
| model-object-weld | 1 | 0.0127 | incomplete | — |
| model-object-weld | 100 | 1.2426 | incomplete | — |
| save-json-encode | 1 | 0.0002 | incomplete | — |
| save-json-encode | 100 | 0.0088 | incomplete | — |
| save-json-decode | 1 | 0.0004 | incomplete | — |
| save-json-decode | 100 | 0.0257 | incomplete | — |

Read ../../README.md for scope and interpretation. Rendering uses different native pipelines and is not an equal-image-quality ranking. Scene-empty/scripts are native traversal versus explicit C# calls and are not ranked. CCD and character results require behavior checks.

## Failures

[]
