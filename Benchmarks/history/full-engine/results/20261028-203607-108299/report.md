> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Standalone engine benchmark results

Milliseconds; lower is better. Median of per-run medians. Query timings are per batch of 1,000 queries. Whole-frame intervals include CPU/GPU synchronization and pacing; they are not GPU timestamps.

| Workload | Population | Tessera ms | Unity ms | Unity / Tessera |
|---|---:|---:|---:|---:|
| ai-navmesh-path | 1 | 0.0020 | incomplete | — |
| ai-navmesh-path | 10 | 0.0181 | incomplete | — |
| ai-navmesh-path | 100 | 0.1825 | incomplete | — |
| ai-navmesh-path | 1000 | 1.8232 | incomplete | — |
| ai-navmesh-path-batch | 1 | 0.0019 | incomplete | — |
| ai-navmesh-path-batch | 10 | 0.0110 | incomplete | — |
| ai-navmesh-path-batch | 100 | 0.0296 | incomplete | — |
| ai-navmesh-path-batch | 1000 | 0.1977 | incomplete | — |

Read ../../README.md for scope and interpretation. Rendering uses different native pipelines and is not an equal-image-quality ranking. Scene-empty/scripts are native traversal versus explicit C# calls and are not ranked. CCD and character results require behavior checks.

## Failures

[]
