> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Optional polygon NavMesh backend — 28 October 2026

Implemented Recast/Detour walking navigation alongside the existing walking/flight grids. Select Backend = NavMesh on NavigationSurface and rebake. Existing scenes default to Grid; Flying always uses the volume grid. No scene assets were automatically migrated.

## Fresh-path benchmark

Release Linux standalone, same three-wall 32 m maze and endpoint sequence as the historical comparison. Grid route caching is explicitly disabled; the NavMesh backend does not use the grid route cache. Every request performs a new search. Five processes per configuration, each with 120 warmup batches and 300 measured batches. Configuration order is deterministically shuffled. Table values are medians of process medians; profiler recording is disabled.

| Execution | Requests per batch | Grid ms | NavMesh ms | Grid / NavMesh |
|---|---:|---:|---:|---:|
| serial | 100 | 0.646981 | 0.126779 | 5.10× |
| batched | 100 | 0.076549 | 0.024741 | 3.09× |
| batched | 1000 | 0.590805 | 0.153073 | 3.86× |

The saved Unity serial result is **0.1075 ms / 100 paths**. Current NavMesh serial is **0.126779 ms**, or **1.18× Unity / 17.9% more time**, versus 6.02× for the grid. No Unity process was rebuilt or executed in this pass. The Tessera worker batch uses 16 job threads; no matching Unity parallel measurement is available.

| Workload | Process-median range ms |
|---|---:|
| ai-nav-path, 100 | 0.642572–0.668913 |
| ai-nav-path-batch, 100 | 0.072011–0.097073 |
| ai-nav-path-batch, 1000 | 0.588501–0.601946 |
| ai-navmesh-path, 100 | 0.123377–0.156449 |
| ai-navmesh-path-batch, 100 | 0.023970–0.027016 |
| ai-navmesh-path-batch, 1000 | 0.151741–0.159515 |

Setup/baking, file I/O and profiler export are outside the path timer. Desktop applications remained open and these runs were not CPU-pinned. The ranges above show process variation, not confidence intervals. Native SIMD/solver settings were not changed. No CPU/GPU overlap or rendered crowd workload is measured by this table.

## Output and comparison limits

Serial and batched outputs match within each backend across repeats: same emitted checksum, final waypoint count and final route length. The backends intentionally return different paths: the final grid route has 11 corners and length 55.652693 m; the final mesh route has 8 corners and length 54.035322 m. Checksums are not expected to match between grid and mesh. This is not a claim of identical bake geometry, sampling, path quality or Unity output. The fixture separately verifies wall clearance, blocked areas, headroom, stacked floors and full-path success.

The NavMesh has voxel-derived floor heights and clearance; it does not retain the grid’s exact cell-link/height semantics. Grid FindPath + Smooth and mesh FindPath both return usable corner paths; mesh Smooth is a no-op because Detour already funnels the corridor. For this workload, changing representation removed most of the previously measured serial gap. These measurements do not establish performance on arbitrary terrain, large meshes or frequent carving.

## Integration

- Vendored upstream Recast Navigation v1.6.0, commit `6dc1667f580357e8a2154c28b7867bea7e8ad3a7`, with its license included in the packaged third-party notices. Only Recast and Detour are compiled. Objects are embedded in the existing native archive, so consuming Beef projects need no new library flags.
- Native baking extracts triangles from the private static query world already filtered by NavigationBaker. This reuses collider transforms, scaled/compound shape support, runtime render meshes, world-state filtering and actor exclusion. Polygon walking supports multiple floors at the same X/Z position.
- NavigationData and NavigationAgent keep the existing destination/query/batching APIs. Each worker owns independent Detour query scratch. Failed/incomplete paths and exhausted budgets fail; they are not silently returned as complete routes. Mesh corridors preserve both ends and per-leg IDs of off-mesh links, retaining agent traversal and events.
- Areas and carving rebuild polygons from the retained static heightfield. Higher costs win overlaps; blocking wins over costs. Existing stationary-carving policy and crowd avoidance remain. Ray casts handle corner/edge starts by considering adjoining polygons containing the same start, without snapping the start out of a blocked footprint.
- Polygon overlays are drawn in the editor. The backend choice is a reflected surface field. Legacy grid assets still load, and polygon geometry saves/loads through the existing .tnav API using the versioned TNM1 format.

## Current limitations

The backend is optional and initially monolithic: geometry edits rebuild the entire mesh; any changed link/area/carve overlay rebuilds its polygons synchronously. It does not yet implement tiled incremental rebuilding or DetourTileCache. Moving-obstacle grid timings from the previous report must not be assigned to NavMesh. Native rebuild failures retain the previous native mesh, report failure and reject queries while a pending overlay cannot be committed.

TNM1 stores validated settings and static triangles; load reprocesses those triangles through Recast. It avoids scene queries but is not a precompiled Detour tile format, so load cost includes construction. Runtime annotations are reapplied from scene components. Direct cell-array, cell-region and cell-link mutation APIs remain grid-specific; use world-space sample/path APIs and NavigationLink components for meshes. Grid route caches are not shared with this backend.

Horizontal raster bounds are limited to 4 million cells / 4,096 cells per side, vertical bounds to Recast’s span height, polygon vertices to fewer than 65,535, and query pools to 65,535 nodes. Normal ground plus distinct annotation/link costs use at most 62 cost values. Rotated annotation volumes use conservative projected footprints and height bounds. Mesh paths always return funnel corners, including when Smooth Path is disabled. Flight remains the existing 3D volume implementation. See [navigation documentation](../../README.md#artifact-policy) for API details.

## Tests and builds

Ten regression suites passed: NavigationMesh, Navigation, ShapeQueries, Layers, Profiler, BehaviorTree, CharacterController, Joints, Scenes and InspectorTypes. After final adapter/cache-cleanup changes, NavigationMesh and Navigation passed again. The desktop Debug build succeeds with five existing editor warnings.

New mesh tests cover a wall maze, corner-ray clearance, explicit visit budgets, snap rejection, exact serial/batched corner agreement, random reachable points, geometry/asset round-trips and truncation, conversion back to a grid, full geometry rebuilding, flight fallback, stacked-floor sampling/disconnection, one-way/bidirectional links, permissions, traversal events, carving removal, cost precedence, blocked areas, agent arrival, transformed runtime render geometry, actor exclusion and low headroom.

The standalone native parser/query smoke test passed with AddressSanitizer and UndefinedBehaviorSanitizer. It exercises all truncated prefixes of a valid geometry asset, NaN configuration fields, oversized declared counts, empty geometry and basic nearest/path/ray/budget queries. It is a focused smoke test, not exhaustive fuzzing or a sanitizer build of the entire engine/Jolt dependency.

Linux, Windows and WebAssembly native archives build successfully. Windows/WebAssembly execution and macOS compilation were not tested. The full Windows archive build exposed an existing missing C++17 setting in tessera_collision_support; that target now declares the requirement. Upstream Detour emits a nontrivial-memset warning under Clang; the web archive also emits an existing stb_vorbis pointer-comparison warning. No upstream source was modified.

## Reproduction and artifacts

Build `cmake --build build/native --target tessera_native -j 8`, then `BeefBuild -workspace=Benchmarks/full-engine/features -config=Release` and run `python3 Benchmarks/full-engine/navmesh-20261028/run.py`. The runner records the executable hash, arguments, process results and checks. Use `python3 tools/run_tests.py NavigationMesh Navigation` for the navigation fixtures. The sanitizer reproducer is `python3 Benchmarks/full-engine/navmesh-20261028/native_sanitize.py` (requires Clang sanitizers and existing Jolt archives).

- [Raw results](../../archives/full-engine-04.tar.gz), [manifest](manifest.json), [runner](../../archives/full-engine-04.tar.gz), [sanitizer command](../../archives/full-engine-04.tar.gz), [sanitizer result](../../archives/full-engine-04.tar.gz).
- [Regression suites](../../archives/full-engine-04.tar.gz), [final additional tests](../../archives/full-engine-04.tar.gz), [desktop build](../../archives/full-engine-04.tar.gz), [Linux native build](../../archives/full-engine-04.tar.gz), [Windows native archive](../../archives/full-engine-04.tar.gz), [WebAssembly native archive](../../archives/full-engine-04.tar.gz).
- Final integration source snapshots are in source/; SHA-256 hashes include the vendored source tree in source-sha256.json. Baseline grid implementation/history remains in ../navigation-20261028e. No external publishing or GitHub changes were made.
