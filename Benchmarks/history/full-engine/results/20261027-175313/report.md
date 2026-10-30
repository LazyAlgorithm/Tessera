> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Standalone engine benchmark results

Milliseconds; lower is better. Median of per-run medians. Query timings are per batch of 1,000 queries. Whole-frame intervals include CPU/GPU synchronization and pacing; they are not GPU timestamps.

| Workload | Population | Tessera ms | Unity ms | Unity / Tessera |
|---|---:|---:|---:|---:|
| ui-layout | 100 | 0.0981 | incomplete | — |
| ui-layout | 1000 | 0.4733 | incomplete | — |
| ui-parse | 100 | 0.0315 | incomplete | — |
| ui-parse | 1000 | 0.1465 | incomplete | — |
| save-binary-encode | 100 | 0.0049 | incomplete | — |
| save-binary-encode | 1000 | 0.0503 | incomplete | — |
| save-binary-decode | 100 | 0.0074 | incomplete | — |
| save-binary-decode | 1000 | 0.0787 | incomplete | — |
| graph-blackboard | 100 | 0.0054 | incomplete | — |
| graph-blackboard | 1000 | 0.0530 | incomplete | — |
| dialogue-condition | 100 | 0.0183 | incomplete | — |
| dialogue-condition | 1000 | 0.1835 | incomplete | — |
| dialogue-parse | 100 | 0.0651 | incomplete | — |
| dialogue-parse | 1000 | 2.5203 | incomplete | — |
| sequence-parse | 100 | 0.0895 | incomplete | — |
| sequence-parse | 1000 | 0.8891 | incomplete | — |
| sequence-evaluate | 100 | 0.0165 | incomplete | — |
| sequence-evaluate | 1000 | 0.1591 | incomplete | — |
| input-parse | 100 | 0.0348 | incomplete | — |
| input-parse | 1000 | 0.3400 | incomplete | — |
| animation-ik | 100 | 0.0859 | incomplete | — |
| animation-ik | 1000 | 0.8777 | incomplete | — |
| network-snapshot-pack | 100 | 0.0088 | incomplete | — |
| network-snapshot-pack | 1000 | 0.0881 | incomplete | — |
| anti-cheat-guard | 100 | 0.0003 | incomplete | — |
| anti-cheat-guard | 1000 | 0.0037 | incomplete | — |

Read ../../README.md for scope and interpretation. Rendering uses different native pipelines and is not an equal-image-quality ranking. Scene-empty/scripts are native traversal versus explicit C# calls and are not ranked. CCD and character results require behavior checks.

## Failures

[]
