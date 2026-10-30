> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Standalone engine benchmark results

Milliseconds; lower is better. Median of per-run medians. Query timings are per batch of 1,000 queries. Whole-frame intervals include CPU/GPU synchronization and pacing; they are not GPU timestamps.

| Workload | Population | Tessera ms | Unity ms | Unity / Tessera |
|---|---:|---:|---:|---:|
| render-skinning-gpu | 1 | 0.1510 | 0.1828 | 1.21 |
| render-skinning-gpu | 10 | 0.2122 | 0.2687 | 1.27 |
| render-skinning-gpu | 100 | 0.9015 | 0.6225 | 0.69 |
| render-skinning-cpu | 1 | 0.2358 | 0.1876 | 0.80 |
| render-skinning-cpu | 10 | 1.3654 | 0.2740 | 0.20 |
| render-skinning-cpu | 100 | 13.1182 | 0.9944 | 0.08 |

Read ../../README.md for scope and interpretation. Rendering uses different native pipelines and is not an equal-image-quality ranking. Scene-empty/scripts are native traversal versus explicit C# calls and are not ranked. CCD and character results require behavior checks.

## Failures

[]
