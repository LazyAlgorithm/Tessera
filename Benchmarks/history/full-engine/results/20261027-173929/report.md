> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Standalone engine benchmark results

Milliseconds; lower is better. Median of per-run medians. Query timings are per batch of 1,000 queries. Whole-frame intervals include CPU/GPU synchronization and pacing; they are not GPU timestamps.

| Workload | Population | Tessera ms | Unity ms | Unity / Tessera |
|---|---:|---:|---:|---:|
| model-cube | 1 | 0.0043 | 0.0579 | 13.40 |
| model-cube | 100 | 0.4229 | 8.4450 | 19.97 |
| model-extrude | 1 | 0.0173 | 0.2424 | 13.97 |
| model-extrude | 100 | 1.7252 | 25.9415 | 15.04 |
| model-subdivide | 1 | 0.0183 | 0.7461 | 40.68 |
| model-subdivide | 100 | 1.7653 | 78.8734 | 44.68 |
| model-bevel | 1 | 0.0353 | 0.6494 | 18.38 |
| model-bevel | 100 | 3.5429 | 66.3506 | 18.73 |
| model-weld | 1 | 0.0052 | 0.0978 | 18.67 |
| model-weld | 100 | 0.5190 | 13.8069 | 26.60 |
| asset-image-decode | 1 | 1.0564 | 0.8455 | 0.80 |
| asset-image-decode | 100 | 106.5083 | 90.9627 | 0.85 |
| save-json-encode | 1 | 0.0001 | 0.0012 | 13.33 |
| save-json-encode | 100 | 0.0048 | 0.0151 | 3.14 |
| save-json-decode | 1 | 0.0002 | 0.0019 | 9.50 |
| save-json-decode | 100 | 0.0091 | 0.0366 | 4.04 |
| physics-joints | 1 | 0.0127 | 0.0252 | 1.99 |
| physics-joints | 100 | 0.0768 | 0.0677 | 0.88 |

Read ../../README.md for scope and interpretation. Rendering uses different native pipelines and is not an equal-image-quality ranking. Scene-empty/scripts are native traversal versus explicit C# calls and are not ranked. CCD and character results require behavior checks.

## Failures

[]
