> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Standalone engine benchmark results

Milliseconds; lower is better. Median of per-run medians. Query timings are per batch of 1,000 queries. Whole-frame intervals include CPU/GPU synchronization and pacing; they are not GPU timestamps.

| Workload | Population | Tessera ms | Unity ms | Unity / Tessera |
|---|---:|---:|---:|---:|
| model-cube | 1 | 0.0044 | 0.0626 | 14.17 |
| model-extrude | 1 | 0.0178 | 0.2357 | 13.28 |
| model-subdivide | 1 | 0.0187 | 0.7385 | 39.55 |
| model-bevel | 1 | 0.0371 | 0.6412 | 17.28 |
| model-weld | 1 | 0.0055 | 0.0980 | 17.73 |
| asset-image-decode | 1 | 1.0608 | 0.8869 | 0.84 |
| save-json-encode | 1 | 0.0001 | 0.0012 | 15.00 |
| save-json-decode | 1 | 0.0002 | 0.0018 | 9.47 |
| physics-joints | 1 | 0.0108 | 0.0311 | 2.87 |
| audio-mix | 1 | incomplete | 0.0134 | — |
| render-ao | 1 | 0.1841 | 0.3218 | 1.75 |
| render-dof | 1 | 0.2365 | 0.2482 | 1.05 |
| render-bloom | 1 | 0.1828 | 0.2645 | 1.45 |
| render-motion-blur | 1 | 0.1657 | 0.3149 | 1.90 |
| render-grading | 1 | 0.1674 | 0.2281 | 1.36 |
| render-transparency | 1 | 0.1446 | 0.1657 | 1.15 |
| render-reflections | 1 | 0.2060 | 0.2717 | 1.32 |

Read ../../README.md for scope and interpretation. Rendering uses different native pipelines and is not an equal-image-quality ranking. Scene-empty/scripts are native traversal versus explicit C# calls and are not ranked. CCD and character results require behavior checks.

## Failures

[
  {
    "run": "tessera-audio-mix-1-0",
    "error": "exit 1"
  }
]
