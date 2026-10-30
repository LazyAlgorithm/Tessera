> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# NavMesh default, tiled updates and game migrations — 28 October 2026

Completed the walking-backend transition and tiled update work. NavMesh is the default for newly created walking surfaces; Flying still uses the existing volume grid. The walking grid remains available explicitly. Legacy saved grids still load as grids until rebaked, and the editor identifies a loaded asset/backend mismatch. Existing enum values were not reordered.

## Tiled updates

Small rasters (up to 256 voxels per side) stay in one tile; larger rasters use 64×64-voxel tiles with a radius-dependent border. Changes to geometry rebuild intersecting tiles plus their clearance border. Carving, costs and links compare old/new annotations and invalidate both footprints. Static tile heightfields are retained across annotation updates. Initial baking uses watershed regions; rebuilt tiles use monotone partitioning to reduce edit latency. Shared clearance spans and borders remain the same.

Changed tile data is staged and the Detour query mesh is replaced atomically. Unchanged polygon data is copied into the replacement query mesh rather than regenerated. Geometry rebuilds still capture the scene’s static triangles, so this is localized rasterization/polygon construction, not fully constant-time scene editing. Tile loading/streaming and asynchronous rebuilds are not implemented. `Mesh.TileCount` / `Mesh.LastRebuiltTiles` expose work performed. Rare cost-ID compaction rebuilds all tiles; active distinct costs remain bounded to 62 IDs.

Off-mesh links can connect nonadjacent tiles, including reverse travel for bidirectional links. Tests cover corner seams, old/new carve footprints, distant-reference preservation and removal of long links. Opaque positive sample handles avoid exposing unsigned Detour salt bits; callers must treat handles as revision-local. Queries still use independent worker scratch.

Validation exposed and fixed two geometry issues: decorated/compound colliders must export transformed leaf shapes, and coplanar downward faces must clear enclosed floor spans to avoid sampling inside resting solids. Reachability-aware goal snapping now falls back to the nearest reachable polygon within the original snap radius, sharing the visit budget rather than accepting a partial route. Contour simplification uses a tighter 0.5-voxel error than the initial prototype.

## Latest measurements

Release Linux standalone; three processes per configuration, each with 40 warmup and 120 measured batches. Values are medians of process medians in milliseconds. Recording is disabled. Builds and other compilation completed before timing. Processes were sequential, but desktop applications remained open and CPU affinity was not pinned.

| Workload | Requests | Grid ms | NavMesh ms |
|---|---:|---:|---:|
| Fresh serial maze paths | 100 | 0.661759 | 0.183590 |
| CPU-batched maze paths | 100 | — | 0.031494 |
| CPU-batched maze paths | 1000 | — | 0.203412 |
| Moving carve + paths | 1 | 0.325882 | 0.964773 |
| Moving carve + paths | 100 | 0.327406 | 1.275688 |

The saved Unity serial result remains 0.1075 ms / 100 paths. The final NavMesh result is **1.71× that timing**, versus 6.16× for the grid. These final timings supersede the initial prototype’s 0.127 ms / 100 paths: correctness changes and tighter contour construction changed the mesh and its cost. No new Unity or matching Unity parallel test ran. Paths and representations differ, so these are workload comparisons, not equivalent-output engine rankings.

The dynamic workload uses a 128 m floor, 0.5 m Surface Cell Size, and a 4×2×4 m crate alternating positions every iteration. **Four of 144 tiles** rebuild on each measured move. The earlier 256-voxel watershed-only tile trial took about 7.50 ms for carve + one path; the final smaller-tile/monotone implementation takes about 0.965 ms. That earlier trial was already tiled, so this is not a measured monolithic-to-tiled speedup. The grid remains faster for this dynamic stress case, particularly when its repeated routes can be reused. Mesh routes are freshly searched.

Both bakes and initial scene setup are outside the timer. Each batch includes the engine workload’s normal checksums; the dynamic timer includes overlay refresh and requested paths. Raw logs, per-process values, binary hashes and arguments are in [results.csv](../../archives/full-engine-04.tar.gz), [measure-manifest.json](../../archives/full-engine-04.tar.gz) and [measure.py](../../archives/full-engine-04.tar.gz). The first watershed trial is retained separately. These timings do not measure whole rendered games or multiplayer performance.

## Projects migrated

- **ZombieTag:** replaced House’s manually populated navigation graph with a polygon mesh. Spawn and visibility candidates are sampled world points rather than pathfinding cells. Collision proxies preserve the game’s 0.4 m furniture/wall clearance and no-climbing rule; fine voxels retain narrow alternate passages. Furniture tops are explicitly excluded, raised key endpoints snap to reachable approaches, and hallway-removal regression tests now use carving instead of directly mutating cells. The full gameplay self-test passes, including key access, alternate wing loops, safe bot paths, spawning, pursuit, attacks and movement.
- **Polystrike:** replaced waypoint A* with polygon routing. Authored NavNodes remain patrol destinations, while bots follow Vector3 polygon corners with a tighter corner-arrival tolerance. Map reloads invalidate old routes. The new CPU `--navtest SOURCE_ROOT` path validates all five stock maps using the gameplay map loader. Foundry and Depot9/FreshMart patrol destinations are reachable from the tested start; Sanctum and Cutbank also contain disconnected destinations, so the test requires usable routes rather than claiming every authored destination connects. This is not a complete bot-match playthrough.
- **SentinelWalk:** migrated AIExample, NavClickTest and BehaviorTreeTest to NavMesh; rebaked existing GuardNavigation.tnav and NavClickTest.tnav. The offline bake fixture samples all explicitly assigned agent starts. User script components are not registered in that fixture and are skipped; no gameplay scripts were run during baking.
- **Sandbox:** migrated the Navigation sample and validated its bake. It rebuilds on startup and has no saved asset to replace.
- The aviation project, archived builds and historical validation snapshots were not migrated. Explicit grid fixtures and historical benchmarks now select Grid, preserving what they measure.

## Validation

Ten engine suites passed: NavigationMesh, Navigation, Layers, CharacterController, BehaviorTree, Scenes, InspectorTypes, ShapeQueries, Joints and Profiler. The default walking backend is exercised by mesh, world-state, behavior-tree and character-controller checks; grid-specific tests explicitly retain Grid. Flying fallback remains covered.

The native ASan/UBSan smoke test passes, including malformed/truncated assets, invalid settings, empty geometry, budget limits, tile-local carving/removal and over 62 successive cost changes to exercise area-ID reclamation. Native archives build for Linux, Windows and WebAssembly. The root desktop Debug build and both games’ Debug builds succeed. Windows/WebAssembly runtime behavior and macOS compilation were not tested.

- [Engine suites](../../archives/full-engine-04.tar.gz), [desktop build](../../archives/full-engine-04.tar.gz), [native sanitizer](../../archives/full-engine-04.tar.gz), [Windows archive](../../archives/full-engine-04.tar.gz), [WebAssembly archive](../../archives/full-engine-04.tar.gz).
- [ZombieTag gameplay test](../../archives/full-engine-04.tar.gz), [Polystrike map checks](../../archives/full-engine-04.tar.gz), [SentinelWalk rebakes](../../archives/full-engine-04.tar.gz), [Sandbox bake](../../archives/full-engine-04.tar.gz).
- Original project files/assets are retained in before/, with backup manifests. Final changed source snapshots and SHA-256 hashes are retained in source/ and source-sha256.json. The Desktop benchmark summary is updated; older reports remain historical. No GitHub publishing was performed.
