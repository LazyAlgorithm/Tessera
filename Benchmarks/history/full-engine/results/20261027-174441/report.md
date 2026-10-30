> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Standalone engine benchmark results

Milliseconds; lower is better. Median of per-run medians. Query timings are per batch of 1,000 queries. Whole-frame intervals include CPU/GPU synchronization and pacing; they are not GPU timestamps.

| Workload | Population | Tessera ms | Unity ms | Unity / Tessera |
|---|---:|---:|---:|---:|
| render-ao | 100 | 0.1840 | 0.2815 | 1.53 |
| render-ao | 1000 | 0.3101 | 0.6374 | 2.06 |
| render-dof | 100 | 0.2424 | 0.2671 | 1.10 |
| render-dof | 1000 | 0.3282 | 0.5884 | 1.79 |
| render-bloom | 100 | 0.1817 | 0.3861 | 2.13 |
| render-bloom | 1000 | 0.2694 | 0.8278 | 3.07 |
| render-motion-blur | 100 | 0.1829 | 0.2763 | 1.51 |
| render-motion-blur | 1000 | 0.3079 | 0.5981 | 1.94 |
| render-grading | 100 | 0.1472 | 0.2636 | 1.79 |
| render-grading | 1000 | 0.2654 | 0.5874 | 2.21 |
| render-transparency | 100 | 0.2624 | 0.3116 | 1.19 |
| render-transparency | 1000 | 1.6449 | 0.7828 | 0.48 |
| render-reflections | 100 | 0.1468 | 0.3094 | 2.11 |
| render-reflections | 1000 | 0.3912 | 0.6645 | 1.70 |

Read ../../README.md for scope and interpretation. Rendering uses different native pipelines and is not an equal-image-quality ranking. Scene-empty/scripts are native traversal versus explicit C# calls and are not ranked. CCD and character results require behavior checks.

## Failures

[]
