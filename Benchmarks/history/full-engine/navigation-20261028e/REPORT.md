> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Navigation crowd, route reuse and moving-obstacle optimization — 28 October 2026

Release Linux standalone measurements on this workstation. These are Tessera before/after workloads, not new Unity measurements. All 21 before/after run pairs have matching emitted checksums, path-point counts, node counts and rebuilt-chunk counts.

## Results

Three fresh processes per configuration, 40 warmup iterations and 120 measured iterations each. Table values are the median of process medians in milliseconds. Profiler recording is disabled for timing. Lower is better.

| Workload | Count | Before ms | After ms | Before / after | After process-median range ms |
|---|---:|---:|---:|---:|---:|
| nav-crowd | 100 | 0.446885 | 0.084549 | 5.29× | 0.082189–0.084764 |
| nav-crowd | 1000 | 18.566695 | 3.213480 | 5.78× | 3.109875–3.233106 |
| nav-crowd | 2000 | 68.761939 | 11.928144 | 5.76× | 11.538025–11.935036 |
| nav-path-repeated | 100 | 0.636431 | 0.005340 | 119.18× | 0.005300–0.005541 |
| nav-path-fresh | 100 | 0.394752 | 0.395618 | 1.00× | 0.395273–0.396831 |
| nav-dynamic | 1 | 2.721475 | 0.311906 | 8.73× | 0.311485–0.321509 |
| nav-dynamic | 100 | 5.325219 | 0.315678 | 16.87× | 0.314090–0.318279 |

Crowd counts are moving agents; path counts are requests per iteration. `nav-dynamic` includes moving the obstacle, refreshing its overlay and finding the requested routes. It is not the whole rendered game frame. Repeated routes measure a deliberately favorable warmed-cache workload; its gain is not a fresh-search speedup. Fresh-search time is essentially unchanged in this sample.

## Workloads and changes

- Crowd: open 384 m surface, 2 m cells, agents initially spaced 4 m apart, alternating opposing destinations, 1.5 m/s, 1/60 s simulated timestep. Measures Scene.Update plus finite-position/path-status checksum checks. No agent rigidbodies, character controllers or rendering. Initial destinations and bake are outside timing. A scene-owned point quadtree replaces expensive full-scene neighbor gathering; transform observers keep positions current for motion, parent changes and teleports. The existing exact filters and candidate velocities remain. A velocity already safe for the full horizon exits immediately.
- Repeated routes: 100 requests cycling ten endpoint pairs on the 32 m three-wall maze, 0.5 m cells. Exact snapped-endpoint route caching now includes smoothing for agents, FindPaths and the combined FindPath overload. Cache keys include link permissions, node/cell mode, metadata requirement and smoothing. Capacity defaults to 64 per search/worker, clamped to 256; routes over 256 points and failures are not cached. Lists are copied, revisions invalidate entries and explicit visit budgets still apply.
- Fresh routes: deterministic pseudorandom endpoint pairs vary every iteration on the same maze. This measures cache misses as well as occasional incidental reuse; it is not a proof that every request is unique.
- Dynamic: 128 m surface, 0.5 m cells (65,536 cells), a 4×2×4 m obstacle alternates position every iteration with carveOnlyStationary disabled. One or 100 identical requests follow each overlay refresh. Baked connectivity labels are retained across transient overlays because they depend only on baked cells and links. Search still checks current carved cells/costs. Route caches and affected nodes are invalidated normally. No-op link assignments no longer invalidate the grid.

## Cache-disabled and historical controls

Same new binary with `--uncached`, three processes each:

| Workload (100 requests) | Cache enabled ms | Disabled ms |
|---|---:|---:|
| nav-path-repeated | 0.005340 | 0.635269 |
| nav-path-fresh | 0.395618 | 0.392197 |

The fresh-route cache-on/off difference is small but not zero; cache bookkeeping can cost time when endpoints do not repeat. Set `routeCacheCapacity = 0` when reuse is inappropriate. The existing features harness explicitly disables caching to preserve historical fresh-search comparisons. Its current controls are:

| Historical workload | Requests | Current ms | Process-median range ms |
|---|---:|---:|---:|
| ai-nav-path | 100 | 0.636556 | 0.634964–0.652692 |
| ai-nav-path-batch | 100 | 0.074896 | 0.070056–0.109446 |
| ai-nav-path-batch | 1000 | 0.594523 | 0.593029–0.604100 |

The saved Unity serial result is 0.1075 ms per 100 paths. Current uncached serial Tessera remains about 5.9× that saved timing. The job-batched timing is a separate parallel workload; there is no matching new Unity parallel run here. Cache hits must not be used to claim equivalent fresh-path Unity performance. Batch processes showed scheduling variation; raw per-process results are retained.

## Profiling and remaining limits

Separate engine-profiler captures contain 64 measured frames after warmup. Recording adds overhead, so these values explain the bottleneck and do not replace the unrecorded table. Crowd 1,000-agent neighbor gathering fell from 15.817 ms to 2.972 ms average self time. Dynamic connectivity rebuilding fell from 2.536 ms to effectively zero; node refresh remains about 0.284 ms.

The crowd quadtree still scans public radius/baseOffset scalars on each query to preserve immediate edits. It removes expensive transforms/activity checks for distant agents, but is not a fully subquadratic solver. Dense crowds and many noncarved obstacles can remain expensive; obstacles still use the existing scan. Dynamic updates still inspect the grid for node changes. Cache invalidation is conservative across any revision, and caches are worker-local rather than globally shared. No GPU navigation was introduced.

The transform observer null check also affects non-navigation objects. Controls with 10,000 objects:

| Workload | Before ms | After ms |
|---|---:|---:|
| scene-transforms | 0.257193 | 0.265303 |
| scene-hierarchy | 0.899806 | 0.848520 |

Independent transform updates increased roughly 0.008 ms (3%) in this sample; hierarchy updates improved, which may include build/layout or clock variation. These short controls are not an isolated instruction-cost measurement.

## Physics report follow-up

The separately supplied [Box3D/Jolt report](../../README.md#artifact-policy) supports an optional backend prototype: four-thread rounded/sparse migration checks favor Box3D four-substep simulation by 2.68–3.43×. Most closest-hit rays favor Jolt, and character behavior, motors, miniature mechanisms, filtered/all-hit overlaps, rollback and shipping platforms remain unvalidated. No physics backend was replaced in this pass.

Its Jolt capacity failure is addressed with configuration and visibility: `PhysicsWorld.ConfigureCapacity(bodies, bodyPairs, contacts)` must be called before native world creation; existing defaults are preserved. `LastStepError` exposes Jolt overflow bits (1/2/4) and newly observed bits are logged. Body creation beyond the native pool returns the invalid ID without tracking it. This does not automatically grow capacity or prove the reported sharp-stack stress scene now succeeds under default limits. The report’s successful larger configuration is 16,384 bodies / 262,144 pairs / 131,072 constraints; increased limits require more memory.

## Validation and reproduction

Eight regression suites passed: Navigation, ShapeQueries, Layers, Profiler, BehaviorTree, CharacterController, Joints and Scenes. Additional combined-smoothed-route cache assertions passed in a subsequent Navigation run. Tests cover copied lists/link metadata, cache keys/eviction/disable/visit budgets, carving invalidation, quadtree/full-scan agreement, parent motion/teleports/live offset/radius edits and body-capacity exhaustion. Root Debug desktop build succeeded with five existing editor warnings; Release navigation-load, features and tessera harnesses built successfully. No native solver migration or physics simulation speed claim is made by these engine changes.

Build: `BeefBuild -workspace=Benchmarks/full-engine/navigation-load -config=Release`. Run `python3 Benchmarks/full-engine/navigation-20261028e/run.py after`. `before` uses the preserved baseline executable. Optional direct arguments: `SCENARIO COUNT WARMUP SAMPLES --uncached` or `--capture /absolute/path.tprofile`. The baseline harness performed FindPath then Smooth; the after harness uses the combined equivalent operation to reuse smoothed routes.

Artifacts: [before data](../../archives/full-engine-03.tar.gz), [after data](../../archives/full-engine-03.tar.gz), [before manifest](../../archives/full-engine-03.tar.gz), [after manifest](../../archives/full-engine-03.tar.gz), [cache-disabled controls](../../archives/full-engine-04.tar.gz), [historical/transform controls](../../archives/full-engine-03.tar.gz), [tests](../../archives/full-engine-04.tar.gz), [additional navigation tests](../../archives/full-engine-04.tar.gz), [desktop build](../../archives/full-engine-04.tar.gz), [crowd profile](../../archives/full-engine-03.tar.gz), [dynamic profile](../../archives/full-engine-04.tar.gz). Raw logs, baseline source backups, first trial and native profiler captures are retained in this directory. Source snapshots/hashes describe the final implementation; baseline binary hash is in before-manifest.json. Desktop applications remained open; these runs were not CPU-pinned and do not provide confidence intervals, memory measurements or shipping-platform validation.
