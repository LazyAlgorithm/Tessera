> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Standalone engine benchmark results

Milliseconds; lower is better. Median of per-run medians. Query timings are per batch of 1,000 queries. Whole-frame intervals include CPU/GPU synchronization and pacing; they are not GPU timestamps.

| Workload | Population | Tessera ms | Unity ms | Unity / Tessera |
|---|---:|---:|---:|---:|
| animator-clips | 1 | 0.0240 | 0.0104 | 0.43 |
| animator-clips | 100 | 2.1917 | 0.7680 | 0.35 |
| animator-clips | 1000 | 22.1210 | 10.4848 | 0.47 |
| animator-layered | 1 | 0.0447 | 0.0120 | 0.27 |
| animator-layered | 100 | 4.4487 | 1.1102 | 0.25 |
| animator-layered | 1000 | 45.0267 | 16.3369 | 0.36 |

Read ../../README.md for scope and interpretation. Rendering uses different native pipelines and is not an equal-image-quality ranking. Scene-empty/scripts are native traversal versus explicit C# calls and are not ranked. CCD and character results require behavior checks.

## Failures

[]
