> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Profiling the remaining desktop gaps

Captured with the engine profiler in Release Linux standalone workloads. Three fresh recording-off processes and three recording-on processes per case; 120 warmup batches, then 64 measured batches per process. One profiler frame is one workload batch, not a rendered gameplay frame. All warmup and scene setup are excluded from captures. No Unity process ran. No optimization algorithm changed in this pass.

## Recording overhead

Batch values are medians of process medians from BENCH rows, excluding EndFrame collection and report/file writing. On/off differences include recording overhead and process-to-process clock or scheduling variation; they do not isolate instrumentation cost or replace the earlier unprofiled engine comparison.

| Workload | N | Recording off ms | Recording on ms | Increase |
|---|---:|---:|---:|---:|
| ai-nav-path | 1 | 0.011702 | 0.012388 | 5.9% |
| ai-nav-path | 100 | 1.171863 | 1.241684 | 6.0% |
| physics-overlap-box | 1000 | 1.381236 | 1.672113 | 21.1% |
| physics-overlap-capsule | 1000 | 2.713710 | 2.954343 | 8.9% |
| physics-overlap-sphere | 1000 | 6.741014 | 6.799609 | 0.9% |

## Physics

Each batch contains 1,000 overlap queries against 1,000 box bodies. Markers report median across three captures of average per-frame times, rounded to the engine report’s 0.001 ms precision. The native marker includes broadphase/narrowphase traversal and full contact collection; it does not separately resolve GJK, EPA or individual native shape-pair routines.

| Query | Native contacts ms | Hit mapping ms | Query preparation ms | Shape cache ms | Native / recorded frame |
|---|---:|---:|---:|---:|---:|
| sphere | 6.451 | 0.101 | 0.035 | 0.035 | 94.9% |
| capsule | 2.561 | 0.060 | 0.040 | 0.046 | 86.7% |
| box | 1.362 | 0.052 | 0.040 | 0.038 | 81.3% |

The measured bottleneck is inside the native contact query. Shape caching, engine preparation and mapping hits back to objects are small contributors. Specialized sphere–box and capsule–box contact paths are therefore better candidates than further list-copy changes. This is a priority inference from these workloads; the capture does not prove which internal native algorithm dominates. Further native sampling or markers would be needed before choosing that implementation.

## Navigation

100 paths per frame on the existing maze; no route cache. Search total includes corridor construction. Smoothing total includes line checks: do not add these nested totals together.

| Marker | Self ms / 100 paths | Total ms / 100 paths | Calls / batch |
|---|---:|---:|---:|
| Navigation.Smooth | 0.036 | 0.698 | 100 |
| Navigation.LineClear | 0.662 | 0.662 | 900 |
| Navigation.Search | 0.417 | 0.507 | 100 |
| Navigation.Corridor | 0.090 | 0.090 | 100 |
| Navigation.Nearest | 0.012 | 0.016 | 200 |
| Navigation.Regions | 0.007 | 0.007 | 200 |
| Navigation.Nodes | 0.004 | 0.004 | 100 |

Smoothing is 55.9% of the recorded CPU frame; line checks account for 94.8% of smoothing time. There are 900 LineClear calls per 100 paths (nine per path). The capture reports 2,500 search visits per batch, or 25 nodes per path. Search including its corridor is 0.507 ms; corridor construction alone is 0.090 ms. Region labels and quadtree revision checks are not the dominant work in this steady-state workload.

The first navigation optimization should target repeated line-of-sight traversal during smoothing. LineClear currently advances in quarter-cell increments and validates the surrounding linked cells. An exact grid-boundary traversal or reuse of already verified corridor segments could reduce redundant work, but must retain clearance, diagonal-link, ledge and height checks. Adding another graph hierarchy is a lower priority for this particular maze. Skipping smoothing would change path behavior and is not a demonstrated equivalent optimization.

## Validation and artifacts

Profiler, Navigation, ShapeQueries and Layers: four suites passed. All 30 processes exited successfully, every process emitted all 64 samples, all 15 captures contain 64 frames, and hits/path length/waypoint counts/checksums match between recording modes. This profiles warmed serial queries and paths; it does not establish cold-bake, moving-obstacle, crowds, worker scaling, rendering, skinning or audio bottlenecks.

- [Test results](../../archives/full-engine-17.tar.gz), [run manifest](manifest.json), [runner](../../archives/full-engine-17.tar.gz).
- [Sphere capture report](../../archives/full-engine-16.tar.gz), [capsule report](../../archives/full-engine-15.tar.gz), [box report](../../archives/full-engine-13.tar.gz).
- [100-path capture report](../../archives/full-engine-08.tar.gz), [single-path report](../../archives/full-engine-08.tar.gz).
- Matching `.tprofile` files open in Window > Profiler > Load. All process logs, repeats and an earlier coarse capture pass are retained here.
- Source snapshots and SHA-256 hashes are in source/ and source-sha256.json. Instrumentation is opt-in through the engine’s recording switch; the benchmark harness accepts `SCENARIO COUNT WARMUP SAMPLES --capture /absolute/path.tprofile`.
