> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Tessera performance confirmation

Updated 2026-10-27T21:24:03

Tessera was rebuilt in Release and rerun in fresh sequential standalone processes. Unity was not rebuilt or rerun after the user requested Tessera-only measurements; its previously saved results are frozen in confirmation-baseline.json. The earlier interrupted paired attempt is excluded.

Five processes per workload. Each process warms up for 120 iterations and records 300 samples, except audio/image decoding (30 warmup, 100 samples). Values below are medians of process medians, in milliseconds; lower is better. Queries contain 1,000 queries per sample. Rendering measures whole-frame intervals, not isolated GPU execution. A positive reduction means Tessera took less time than previously.

| Workload | N | Previous Tessera ms | Rebuilt Tessera ms | Tessera time reduction | Saved Unity ms | Rebuilt Tessera / Unity |
|---|---:|---:|---:|---:|---:|---:|
| physics-overlap-sphere | 1000 | 7.9879 | 6.6828 | 16.3% | 0.4195 | 15.93× |
| physics-overlap-capsule | 1000 | 3.7549 | 2.6929 | 28.3% | 0.2882 | 9.35× |
| physics-overlap-box | 1000 | 1.3436 | 1.3483 | -0.3% | 0.2647 | 5.09× |
| physics-boxcast | 1000 | 0.7922 | 0.7868 | 0.7% | 0.5755 | 1.37× |
| physics-capsulecast | 1000 | 0.8875 | 0.8920 | -0.5% | 0.6279 | 1.42× |
| physics-spherecast | 1000 | 0.8513 | 0.8204 | 3.6% | 0.5884 | 1.39× |
| physics-mesh-raycast | 1000 | 0.5382 | 0.5409 | -0.5% | 0.4109 | 1.32× |
| render-materials | 1000 | 1.5426 | 0.2360 | 84.7% | 0.7544 | 0.31× |
| render-materials | 10000 | 14.8785 | 1.5827 | 89.4% | 4.0636 | 0.39× |
| render-culling | 1000 | 0.2006 | 0.1913 | 4.7% | 0.2030 | 0.94× |
| render-culling | 10000 | 1.0815 | 0.8680 | 19.7% | 0.5362 | 1.62× |
| render-transparency | 1000 | 1.5810 | 0.2927 | 81.5% | 0.7828 | 0.37× |
| render-skinning-cpu | 100 | 12.9152 | 4.3031 | 66.7% | 0.9944 | 4.33× |
| render-skinning-gpu | 100 | 0.8586 | 0.8767 | -2.1% | 0.6225 | 1.41× |
| render-skinning-gpu @1920x1080 | 1000 | 8.5533 | 10.0112 | -17.0% | 4.1077 | 2.44× |
| animator-clips | 100 | 2.1917 | 0.2855 | 87.0% | 0.7680 | 0.37× |
| animator-clips | 1000 | 22.1210 | 2.8996 | 86.9% | 10.4848 | 0.28× |
| animator-layered | 100 | 4.4487 | 1.4366 | 67.7% | 1.1102 | 1.29× |
| animator-layered | 1000 | 45.0267 | 14.8452 | 67.0% | 16.3369 | 0.91× |
| ai-nav-path | 1 | 0.1638 | 0.0123 | 92.5% | 0.0015 | 8.22× |
| ai-nav-path | 100 | 21.5275 | 1.2165 | 94.3% | 0.1075 | 11.32× |
| audio-mix | 100 | 1.3722 | 0.4492 | 67.3% | 0.1588 | 2.83× |
| asset-image-decode | 100 | 106.5083 | 107.3979 | -0.8% | 90.9627 | 1.18× |
| physics-check-sphere | 1000 | — | 0.5981 | — | — | — |
| physics-check-capsule | 1000 | — | 0.6880 | — | — | — |
| physics-check-box | 1000 | — | 1.2974 | — | — | — |

A ratio above 1 means Tessera took longer than the saved Unity measurement; below 1 means less time. These ratios apply only to the listed workloads.

## Repeatability and provenance

| Workload | N | Processes | Range of process medians ms | Median process p95 ms | Raw results |
|---|---:|---:|---:|---:|---|
| physics-overlap-sphere | 1000 | 5 | 6.6567–6.8735 | 6.6967 | [20261027-211927-171666](results/20261027-211927-171666/report.md) |
| physics-overlap-capsule | 1000 | 5 | 2.6822–2.8607 | 2.7248 | [20261027-211927-171666](results/20261027-211927-171666/report.md) |
| physics-overlap-box | 1000 | 5 | 1.3437–1.3492 | 1.3675 | [20261027-211927-171666](results/20261027-211927-171666/report.md) |
| physics-boxcast | 1000 | 5 | 0.7838–0.8052 | 0.7914 | [20261027-211927-171666](results/20261027-211927-171666/report.md) |
| physics-capsulecast | 1000 | 5 | 0.8886–0.9149 | 0.9001 | [20261027-211927-171666](results/20261027-211927-171666/report.md) |
| physics-spherecast | 1000 | 5 | 0.8194–0.8468 | 0.8306 | [20261027-211927-171666](results/20261027-211927-171666/report.md) |
| physics-mesh-raycast | 1000 | 5 | 0.5394–0.5539 | 0.5466 | [20261027-211927-171666](results/20261027-211927-171666/report.md) |
| render-materials | 1000 | 5 | 0.2311–0.2405 | 0.2591 | [20261027-211957-023441](results/20261027-211957-023441/report.md) |
| render-materials | 10000 | 5 | 1.5110–1.5917 | 1.7034 | [20261027-211957-023441](results/20261027-211957-023441/report.md) |
| render-culling | 1000 | 5 | 0.1803–0.1933 | 0.2343 | [20261027-211957-023441](results/20261027-211957-023441/report.md) |
| render-culling | 10000 | 5 | 0.8562–0.9074 | 0.9058 | [20261027-211957-023441](results/20261027-211957-023441/report.md) |
| render-transparency | 1000 | 5 | 0.2804–0.2991 | 0.3892 | [20261027-212010-353561](results/20261027-212010-353561/report.md) |
| render-skinning-cpu | 100 | 5 | 4.1848–4.3386 | 4.5219 | [20261027-212012-807264](results/20261027-212012-807264/report.md) |
| render-skinning-gpu | 100 | 5 | 0.8739–0.9273 | 1.2957 | [20261027-212012-807264](results/20261027-212012-807264/report.md) |
| render-skinning-gpu @1920x1080 | 1000 | 5 | 9.9995–10.0323 | 20.1576 | [20261027-212029-103523](results/20261027-212029-103523/report.md) |
| animator-clips | 100 | 5 | 0.2835–0.2862 | 0.2921 | [20261027-212114-417144](results/20261027-212114-417144/report.md) |
| animator-clips | 1000 | 5 | 2.8701–2.9261 | 2.9619 | [20261027-212114-417144](results/20261027-212114-417144/report.md) |
| animator-layered | 100 | 5 | 1.4345–1.4443 | 1.4584 | [20261027-212114-417144](results/20261027-212114-417144/report.md) |
| animator-layered | 1000 | 5 | 14.7427–14.9455 | 15.3063 | [20261027-212114-417144](results/20261027-212114-417144/report.md) |
| ai-nav-path | 1 | 5 | 0.0123–0.0124 | 0.0125 | [20261027-212156-749957](results/20261027-212156-749957/report.md) |
| ai-nav-path | 100 | 5 | 1.2136–1.2630 | 1.2545 | [20261027-212156-749957](results/20261027-212156-749957/report.md) |
| audio-mix | 100 | 5 | 0.4470–0.4599 | 0.4677 | [20261027-212159-761198](results/20261027-212159-761198/report.md) |
| asset-image-decode | 100 | 5 | 106.3086–108.1478 | 108.0774 | [20261027-212159-761198](results/20261027-212159-761198/report.md) |
| physics-check-sphere | 1000 | 5 | 0.5957–0.6301 | 0.6335 | [20261027-212343-741144](results/20261027-212343-741144/report.md) |
| physics-check-capsule | 1000 | 5 | 0.6837–0.6970 | 0.7119 | [20261027-212343-741144](results/20261027-212343-741144/report.md) |
| physics-check-box | 1000 | 5 | 1.2922–1.3433 | 1.3161 | [20261027-212343-741144](results/20261027-212343-741144/report.md) |

## Interpretation limits

- CheckSphere/CheckBox/CheckCapsule are new any-hit queries. They stop at the first contact and have no matching saved Unity Check* measurement. They are reported separately from full contact-collecting overlaps; no cross-engine ratio is assigned.
- Existing overlap comparisons retain the original operations: Tessera collects shape contacts while Unity Overlap*NonAlloc collects colliders. Contact detail differs even where query geometry matches.
- Navigation compares Tessera grid paths with Unity polygon NavMesh paths. Path shape and representation differ; this is not an equal-quality pathfinding ranking.
- Rendering pipelines, lighting and effects differ. Tessera rendering controls are antialiasing off, render scale 1, VSync off; framebuffer dimensions are checked. Skinning forces all characters to deform. CPU/GPU skinning use separate saved Unity builds.
- N means bodies for physics, objects for rendering, characters for skinning/animators, path requests for navigation, voices for audio, and image decodes for image loading. Audio captures 1,024 stereo frames at 48 kHz per sample.
- Old and new runs occurred at different times. Ratios against frozen Unity baselines do not control changes in machine load, temperature or clocks between sessions. Per-run environment and logs remain available.
- Only performance measurements and checks that timed work occurred were run. Existing Unity projects and engine source were not modified by this rerun; no changes were pushed.

## Build and validation

Release builds succeeded for tessera, features, extended and animation. The additional physics-checks project was built against the captured engine snapshot: concurrent live profiler additions caused a compile failure in its first attempt, and were left untouched. The successful snapshot build includes the new Check* methods. CMake/Ninja reported native libraries up to date. GNU linking was used; ThinLTO tools are unavailable. See confirmation-*-build.log, confirmation-build-manifest.json, confirmation-engine-source/, RERUN_MANIFEST.json and each result folder for build hashes, settings, source snapshots, raw samples and validation checks.

Completed jobs: 9. Recorded failed runs: 0.
[]
