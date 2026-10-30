> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Standalone engine benchmark results

Milliseconds; lower is better. Median of per-run medians. Query timings are per batch of 1,000 queries. Whole-frame intervals include CPU/GPU synchronization and pacing; they are not GPU timestamps.

| Workload | Population | Tessera ms | Unity ms | Unity / Tessera |
|---|---:|---:|---:|---:|
| audio-mix | 1 | 0.0189 | incomplete | — |

Read ../../README.md for scope and interpretation. Rendering uses different native pipelines and is not an equal-image-quality ranking. Scene-empty/scripts are native traversal versus explicit C# calls and are not ranked. CCD and character results require behavior checks.

## Failures

[
  {
    "run": "unity-audio-mix-1-0",
    "error": "Command '['/usr/bin/time', '-f', 'RESOURCE,peak_rss_kib,%M', 'historical benchmark root/full-engine/builds/unity-extras/Benchmark', '-batchmode', '-nographics', '-screen-fullscreen', '0', '-screen-width', '1280', '-screen-height', '720', '--scenario', 'audio-mix', '--count', '1', '--warmup', '10', '--samples', '20', '--output', 'historical benchmark root/full-engine/results/20261027-173621/unity-audio-mix-1-0.raw.csv', '-logFile', 'historical benchmark root/full-engine/results/20261027-173621/unity-audio-mix-1-0.log']' timed out after 20 seconds"
  }
]
