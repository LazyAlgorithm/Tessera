> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Standalone engine benchmark results

Milliseconds; lower is better. Median of per-run medians. Query timings are per batch of 1,000 queries. Whole-frame intervals include CPU/GPU synchronization and pacing; they are not GPU timestamps.

| Workload | Population | Tessera ms | Unity ms | Unity / Tessera |
|---|---:|---:|---:|---:|
| render-ao | 100 | 0.1422 | incomplete | — |
| render-ao | 1000 | 0.3218 | incomplete | — |
| render-dof | 100 | 0.1946 | incomplete | — |
| render-dof | 1000 | 0.3089 | incomplete | — |
| render-bloom | 100 | 0.1229 | incomplete | — |
| render-bloom | 1000 | 0.2676 | incomplete | — |
| render-motion-blur | 100 | 0.1379 | incomplete | — |
| render-motion-blur | 1000 | 0.3058 | incomplete | — |
| render-grading | 100 | 0.1224 | incomplete | — |
| render-grading | 1000 | 0.2565 | incomplete | — |
| render-transparency | 100 | 0.2397 | incomplete | — |
| render-transparency | 1000 | 1.5810 | incomplete | — |
| render-reflections | 100 | 0.1438 | incomplete | — |
| render-reflections | 1000 | 0.3914 | incomplete | — |

Read ../../README.md for scope and interpretation. Rendering uses different native pipelines and is not an equal-image-quality ranking. Scene-empty/scripts are native traversal versus explicit C# calls and are not ranked. CCD and character results require behavior checks.

## Failures

[]
