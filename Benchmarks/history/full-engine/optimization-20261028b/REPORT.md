> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Desktop optimization results — contact queries and navigation

Production Release binaries, profiler recording disabled, native diagnostic option OFF. Times are milliseconds; lower is better. Each process performs 120 warmup batches and records 300 batches. Values are medians of five process medians. Physics samples contain 1,000 queries; navigation samples contain N paths.

| Workload | N | Before / generic ms | Optimized ms | Time reduction | Speedup | Saved Unity ms | Optimized / Unity |
|---|---:|---:|---:|---:|---:|---:|---:|
| physics-overlap-sphere | 1000 | 6.485369 | 1.107165 | 82.9% | 5.86× | 0.4195 | 2.64× |
| physics-overlap-capsule | 1000 | 2.607736 | 0.524731 | 79.9% | 4.97× | 0.2882 | 1.82× |
| physics-overlap-box | 1000 | 1.316615 | 1.312697 | 0.3% | 1.00× | 0.2647 | 4.96× |
| ai-nav-path | 100 | 1.176426 | 0.997915 | 15.2% | 1.18× | 0.1075 | 9.28× |
| ai-nav-path | 1 | 0.011652 | 0.010079 | 13.5% | 1.16× | 0.0015 | 6.72× |

Physics compares generic and analytic modes of the same binary, interleaved in alternating order in fresh processes. Box overlaps are a control: the small difference is consistent with run variation. Navigation compares the previous sampler binary with the new interval traversal, each in five fresh processes. Unity values remain frozen historical context: detailed overlap contacts differ from Unity collider-list queries, and Tessera grid paths differ from polygon NavMesh paths. These are workload-specific ratios, not equal-feature engine rankings.

## Changes

- Walking line checks traverse intervals between grid edges and centre lines. The surrounding linked-cell region is checked once per interval with a specialized four-corner test. Double-precision event coordinates avoid losing very short corner intervals to float interpolation. Connectivity, walkability and endpoint validation remain, and height clearance is checked across the full interval, including within-cell and destination-edge cases that the old sampler could miss. Flying retains the original volume sampler.
- Sphere–box queries use exact flat-face/interior contacts and a conservative distance rejection for separated pairs. Aligned interior capsule–box contacts use an exact nearest-face calculation. Near-tangent contacts, rounded edge/corner contacts, oblique capsules, unsupported scaling/settings and all other pairs retain the registered Jolt solver. Contact points, normals, penetration depth, body/subshape IDs and filtering remain part of the API.
- The fast routines run only within overlap queries; the dispatch wrappers immediately delegate simulation and unsupported operations to their original handlers. `PhysicsWorld.useAnalyticOverlapContacts = false` provides the comparison mode. No path cache, omitted smoothing or benchmark-specific geometry shortcut was introduced.
- A focused, optional native profiler bridge exposes convex-pair and EPA scopes. It is OFF for all final timing runs. CMake adds a read-only lookup accessor to the fetched Jolt CollisionDispatch header so the original handlers can be preserved; the patch is applied on configure and does not replace solver algorithms. This accessor is an integration maintenance point when upgrading Jolt.

## Profile evidence

The native diagnostic capture before optimization recorded 1,000 EPA calls per batch: about 3.930 ms for sphere queries and 2.033 ms for capsules. Convex dispatch was called 16,820 times in the sphere batch and 2,000 times in the capsule batch. These instrumented figures include material observer overhead and are not the production comparison above. They established where to specialize.

The final navigation capture records 0.539 ms in smoothing and 0.506 ms in LineClear per 100 paths, compared with the prior profiled medians of 0.698 ms and 0.662 ms. Search/corridor work is essentially unchanged (0.508 ms total search, 25 visits per path). The production navigation timings above measure the net gain without recording.

## Validation and scope

Navigation, ShapeQueries, Layers, Profiler, CharacterController and Joints all pass. New cases cover dense-reference ray validation across a wall, simultaneous grid crossings, thin/partial bounds, centre-line travel, destination bounds, within-cell height and endpoint-height checks. Shape queries compare analytic against generic contacts on rotated boxes across faces, radii, capsule axes, exterior probes, ignored bodies, masks, tangency and oblique fallback. Existing suites also cover compound/mesh behavior, buffer growth, physics movement and profiler recording.

All 30 final contact processes emitted 300 samples and 420,000 successful queries each. Navigation before/after waypoint counts, path lengths and checksums match; all ten final navigation processes completed without failures. This batch is favorable to flat-face box contacts and aligned capsules. General game gains depend on shape mix and queries; unsupported pairs keep their previous solver cost. Skinning, audio and rendering were not changed in this pass.

## Artifacts

- Navigation [before](../results/20261028-085315-999319/report.md) and [after](../results/20261028-091322-308349/report.md); per-run source/binary metadata is retained.
- [Physics raw summary](../../archives/full-engine-05.tar.gz), [interleaved run manifest](../../archives/full-engine-05.tar.gz), [runner](../../archives/full-engine-05.tar.gz), [tests](../../archives/full-engine-08.tar.gz).
- Native diagnostics: [sphere EPA](../../archives/full-engine-08.tar.gz), [capsule EPA](../../archives/full-engine-05.tar.gz).
- Final captures: [navigation](../../archives/full-engine-05.tar.gz), [sphere](../../archives/full-engine-06.tar.gz), [capsule](../../archives/full-engine-04.tar.gz). Corresponding .tprofile files open in the engine profiler.
- Earlier interior-only trials and preliminary navigation runs are retained but excluded from the final optimized column.
- Final source snapshots and hashes: source/ and source-sha256.json. Native archive hashes and CMake diagnostic setting are in manifest.json.
