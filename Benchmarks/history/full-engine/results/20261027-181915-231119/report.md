> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Standalone engine benchmark results

Milliseconds; lower is better. Median of per-run medians. Query timings are per batch of 1,000 queries. Whole-frame intervals include CPU/GPU synchronization and pacing; they are not GPU timestamps.

| Workload | Population | Tessera ms | Unity ms | Unity / Tessera |
|---|---:|---:|---:|---:|
| render-shared | 1000 | 0.2634 | 0.5426 | 2.06 |
| render-ao | 1000 | 0.3237 | 0.6376 | 1.97 |
| render-skinning-gpu | 1000 | 8.5533 | 4.1077 | 0.48 |

Read ../../README.md for scope and interpretation. Rendering uses different native pipelines and is not an equal-image-quality ranking. Scene-empty/scripts are native traversal versus explicit C# calls and are not ranked. CCD and character results require behavior checks.

## Failures

[]
