> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Standalone engine benchmark results

Milliseconds; lower is better. Median of per-run medians. Query timings are per batch of 1,000 queries. Whole-frame intervals include CPU/GPU synchronization and pacing; they are not GPU timestamps.

| Workload | Population | Tessera ms | Unity ms | Unity / Tessera |
|---|---:|---:|---:|---:|
| ai-nav-path | 1 | 0.1638 | 0.0015 | 0.01 |
| ai-nav-path | 10 | 2.1513 | 0.0111 | 0.01 |
| ai-nav-path | 100 | 21.5275 | 0.1075 | 0.00 |

Read ../../README.md for scope and interpretation. Rendering uses different native pipelines and is not an equal-image-quality ranking. Scene-empty/scripts are native traversal versus explicit C# calls and are not ranked. CCD and character results require behavior checks.

## Failures

[]
