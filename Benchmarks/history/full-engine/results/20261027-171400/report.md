> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Standalone engine benchmark results

Milliseconds; lower is better. Median of per-run medians. Query timings are per batch of 1,000 queries. Whole-frame intervals include CPU/GPU synchronization and pacing; they are not GPU timestamps.

| Workload | Population | Tessera ms | Unity ms | Unity / Tessera |
|---|---:|---:|---:|---:|
| physics-free | 100 | 0.0224 | 0.0389 | 1.74 |
| physics-free | 1000 | 0.1302 | 0.1771 | 1.36 |
| physics-pile | 100 | 0.0714 | 0.1042 | 1.46 |
| physics-pile | 1000 | 0.6953 | 0.5208 | 0.75 |
| physics-mixed-shapes | 100 | 0.0449 | 0.0634 | 1.41 |
| physics-mixed-shapes | 1000 | 0.5036 | 0.5272 | 1.05 |
| physics-mesh | 100 | 0.0477 | 0.1151 | 2.41 |
| physics-mesh | 1000 | 0.6795 | 0.6315 | 0.93 |
| physics-raycast | 100 | 0.1483 | 0.2375 | 1.60 |
| physics-raycast | 1000 | 0.2893 | 0.3535 | 1.22 |
| physics-mesh-raycast | 100 | 0.3942 | 0.2951 | 0.75 |
| physics-mesh-raycast | 1000 | 0.5382 | 0.4109 | 0.76 |
| physics-spherecast | 100 | 0.5293 | 0.3826 | 0.72 |
| physics-spherecast | 1000 | 0.8513 | 0.5884 | 0.69 |
| physics-capsulecast | 100 | 0.5935 | 0.4133 | 0.70 |
| physics-capsulecast | 1000 | 0.8875 | 0.6279 | 0.71 |
| physics-boxcast | 100 | 0.5574 | 0.3960 | 0.71 |
| physics-boxcast | 1000 | 0.7922 | 0.5755 | 0.73 |
| physics-overlap-sphere | 100 | 2.0720 | 0.1977 | 0.10 |
| physics-overlap-sphere | 1000 | 7.9879 | 0.4195 | 0.05 |
| physics-overlap-capsule | 100 | 1.1373 | 0.1812 | 0.16 |
| physics-overlap-capsule | 1000 | 3.7549 | 0.2882 | 0.08 |
| physics-overlap-box | 100 | 0.4432 | 0.1929 | 0.44 |
| physics-overlap-box | 1000 | 1.3436 | 0.2647 | 0.20 |
| physics-discrete | 100 | 0.0294 | 0.0401 | 1.37 |
| physics-discrete | 1000 | 0.1850 | 0.2183 | 1.18 |
| physics-ccd | 100 | 0.0549 | 0.2152 | 3.92 |
| physics-ccd | 1000 | 0.4729 | 1.3486 | 2.85 |
| physics-characters-flat | 100 | 0.0898 | 0.1262 | — |
| physics-characters-flat | 1000 | 0.7899 | 0.8687 | — |
| physics-characters-steps | 100 | 0.0904 | 0.0880 | — |
| physics-characters-steps | 1000 | 0.7878 | 0.8396 | — |
| render-shared | 100 | 0.1510 | 0.2209 | 1.46 |
| render-shared | 1000 | 0.2418 | 0.5211 | 2.15 |
| render-materials | 100 | 0.2571 | 0.2936 | 1.14 |
| render-materials | 1000 | 1.5225 | 0.7544 | 0.50 |
| render-moving | 100 | 0.1470 | 0.2419 | 1.65 |
| render-moving | 1000 | 0.3204 | 0.5705 | 1.78 |
| render-culling | 100 | 0.1435 | 0.1690 | 1.18 |
| render-culling | 1000 | 0.2058 | 0.2030 | 0.99 |
| render-shadows | 100 | 0.1979 | 0.2601 | 1.31 |
| render-shadows | 1000 | 0.3796 | 0.8888 | 2.34 |
| render-spheres | 100 | 0.1511 | 0.2424 | 1.60 |
| render-spheres | 1000 | 0.2528 | 0.6896 | 2.73 |
| render-lights | 100 | 0.1672 | 0.5253 | 3.14 |
| render-lights | 1000 | 0.2763 | 1.6490 | 5.97 |
| render-physics | 100 | 0.1490 | 0.3027 | 2.03 |
| render-physics | 1000 | 0.2975 | 1.0042 | 3.38 |
| render-particles | 100 | 0.1425 | 0.1951 | 1.37 |
| render-particles | 1000 | 0.1870 | 0.4355 | 2.33 |
| scene-empty | 100 | 0.0001 | 0.0002 | — |
| scene-empty | 1000 | 0.0001 | incomplete | — |
| scene-scripts | 100 | 0.0024 | 0.0037 | — |
| scene-scripts | 1000 | 0.0230 | 0.0355 | — |
| scene-transforms | 100 | 0.0028 | 0.0056 | 2.03 |
| scene-transforms | 1000 | 0.0258 | 0.0542 | 2.10 |
| scene-hierarchy | 100 | 0.0089 | 0.0070 | 0.78 |
| scene-hierarchy | 1000 | 0.0907 | 0.0681 | 0.75 |
| scene-churn | 100 | 0.0261 | 0.2021 | 7.75 |
| scene-churn | 1000 | 0.5909 | 2.1335 | 3.61 |

Read ../../README.md for scope and interpretation. Rendering uses different native pipelines and is not an equal-image-quality ranking. Scene-empty/scripts are native traversal versus explicit C# calls and are not ranked. CCD and character results require behavior checks.

## Failures

[
  {
    "run": "unity-scene-empty-1000-1",
    "error": "Command '['/usr/bin/time', '-f', 'RESOURCE,peak_rss_kib,%M', 'historical benchmark root/full-engine/builds/unity/Benchmark', '-batchmode', '-nographics', '-screen-fullscreen', '0', '-screen-width', '1280', '-screen-height', '720', '--scenario', 'scene-empty', '--count', '1000', '--warmup', '120', '--samples', '300', '--output', 'historical benchmark root/full-engine/results/20261027-171400/unity-scene-empty-1000-1.raw.csv', '-logFile', 'historical benchmark root/full-engine/results/20261027-171400/unity-scene-empty-1000-1.log']' timed out after 180 seconds"
  }
]
