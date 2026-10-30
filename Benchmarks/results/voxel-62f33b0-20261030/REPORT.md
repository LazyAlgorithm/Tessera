# Tessera destructible voxel shooter benchmark

Tested commit **62f33b0e3b97667946e3741903652095f1ecc6e4**. Completed 2026-10-29T20:10:40.203897. Clean commit checkout, fresh Release native dependencies and engine build, Ryzen 9 7900X, RTX 3070 8 GB, Linux/Vulkan. **254 measured processes**; all command lines, samples and checks are retained.

## Assessment

**A bounded shooter with destructible map sections, explosions and digging looks plausible on this desktop. Idle rendering is not the main obstacle. Immediate mesh/collision rebuilds, fragmentation correctness, memory, and scheduling destruction bursts are the important constraints.** This is not a whole-game or multiplayer capacity guarantee.

Every VoxelObject retains a normal generated mesh between edits. Only the affected object remeshes. There is no whole-map rebuild in these tests. Each voxel object still owns a grid, its own mesh and collision data; identical voxel objects do not automatically share their meshes.

## Intact map pieces

720p, one directional light, simple vertex-coloured material, no shadows/AA; all pieces framed together. Mesh colliders are enabled. Values are the worst process p95 among three independent runs. Peak RSS is CPU process resident memory, **not total RAM+VRAM**; it includes renderer/driver allocations and setup peaks.

| Objects | Resolution | Unique voxel meshes p95 ms | Same-geometry shared-mesh control p95 ms | Voxel process peak RSS MiB | Shared control RSS MiB |
|---|---:|---:|---:|---:|---:|
| 100 | 16 | 0.387 | 0.321 | 415.309 | 258.805 |
| 500 | 16 | 0.980 | 0.684 | 1323.125 | 279.668 |
| 1000 | 16 | 1.942 | 0.960 | 2463.191 | 305.711 |
| 100 | 24 | 0.427 | 0.494 | 530.875 | 267.523 |
| 500 | 24 | 1.364 | 1.100 | 1894.051 | 320.965 |
| 1000 | 24 | 3.142 | 2.163 | 3607.117 | 387.934 |
| 100 | 32 | 0.742 | — | 737.270 | — |
| 500 | 32 | 2.603 | — | 2942.520 | — |
| 100 | 48 | 1.275 | — | 1376.676 | — |

The shared-mesh control draws the **same voxel-generated geometry** at the same object count using one source mesh. It retains one VoxelObject, then shares that mesh among ordinary MeshRenderers; it is an instancing/reuse control, not a destructible replacement. All objects still have mesh colliders. RSS includes one extra int8 density backup per benchmark voxel object for reproducible edits, even in idle tests; a game without backups saves that portion. No VRAM ceiling is established.

1080p with shadows and antialiasing enabled:

| Objects | Voxel p95 ms | Shared control p95 ms |
|---|---:|---:|
| 100 | 0.977 | — |
| 500 | 2.329 | 1.903 |

## Bullets and digging

**Bullet carve radius is 0.32 m (64 cm diameter): a large visible chip, not a realistic calibre-sized bullet hole.** Resolution 24 over a 4 m object means 16.7 cm cells; resolution 48 means 8.3 cm cells. Millimetre bullet holes require decals or a different finer/local representation. Objects can instead be made physically smaller at the same resolution for finer cells.

Digging tests use a 4 m grid containing a 3.2 m × 3.2 m × 0.7 m wall and a 0.5 m-radius cut through its centre. The exact mesh collider must let a ray through the new hole after every edit. Other bullet tests use a solid primitive box. Every measured iteration begins with an untimed density-only restore, then performs productive edits; no Fill or mesh/collision rebuilding is hidden in the measured edit. Reset cleanup and correctness scans are outside the narrow SAMPLE action/CPU timers. Full rendered FRAME intervals still include that benchmark housekeeping, so event-frame figures conservatively include work a production game would replace with its own event/cleanup logic.

| Resolution | Cell size cm (4 m grid) | Mesh generation/edit only, CPU p95 ms | With exact static collision, CPU p95 ms | With convex rigidbody, CPU p95 ms | Carving bullet: rendered p95 ms | Digging through wall: rendered p95 ms |
|---|---:|---:|---:|---:|---:|---:|
| 8 | 50.00 | — | — | — | — | 0.222 |
| 16 | 25.00 | 0.324 | 0.767 | 0.439 | 0.949 | 0.615 |
| 24 | 16.67 | 0.705 | 2.173 | 0.827 | 2.098 | 1.023 |
| 32 | 12.50 | 1.349 | 4.467 | 1.519 | 3.978 | 1.606 |
| 48 | 8.33 | 3.784 | 10.659 | 3.885 | 11.409 | 4.420 |

Resolution-8 bullet tests changed density but failed the benchmark’s positive-solid-sample removal gate; their timings are excluded. This does not prove the engine cannot draw any small dent: it means this coarse grid did not pass this specific material-removal test. Digging at that resolution is tested separately.

The CPU-only collision comparison includes edit, meshing and collider/body rebuilding but no graphics device. The difference between no collider and mesh collider is an estimate of collision integration cost, not a separately instrumented pure Jolt function. Moving convex collision cannot represent concave holes or tunnels; it is appropriate for approximate loose props/debris, not exact traversable wall openings.

Bullets that do not carve are much less demanding:

| Intact objects, resolution 24 | 1,000 ray queries: CPU total p95 ms |
|---|---:|
| 100 | 1.598 |
| 500 | 1.752 |
| 1000 | 1.736 |

All 1,000 ray queries must hit. This is a synthetic query batch, not 1,000 fully simulated projectiles or networked shots.

## Explosions affecting multiple objects

Synthetic fan-out: each affected 4 m-grid box receives its own 1 m-radius carve at a fixed local point. This models the cost of touching N objects, not the geometry of a single 1 m world-space explosion spanning widely separated boxes. Real blast overlap, full object removal and fragmentation can change cost. No fragments are detached in this fan-out case; fragmentation is measured separately.

| Resolution | Affected objects | Rendered median ms | Worst-process rendered p95 ms |
|---|---:|---:|---:|
| 16 | 1 | 0.982 | 1.059 |
| 16 | 4 | 3.363 | 3.605 |
| 16 | 16 | 12.858 | 12.963 |
| 24 | 1 | 2.394 | 2.443 |
| 24 | 4 | 9.228 | 9.422 |
| 24 | 16 | 37.098 | 38.120 |
| 32 | 1 | 4.607 | 4.821 |
| 32 | 4 | 18.055 | 18.827 |
| 32 | 16 | 74.303 | 76.886 |

A 60 FPS frame is 16.67 ms; a 120 FPS frame is 8.33 ms. These destruction costs must fit alongside the rest of the game. They are not whole-game FPS predictions. Event-frame intervals also include the repeat/reset and validation overhead described above; narrow action columns isolate the edit service time.

## Dirty-object queue and coalescing

**Coalescing is measured here in a benchmark-only prototype; it is not enabled in the engine.** It applies the same density edits, then calls the current Rebuild once per dirty object, including exact collision rebuilding. It has no threads, asynchronous collision cooking or compute shader. The prototype omits fragment splitting and networking. Final density FNV hashes, vertex counts and triangle counts must match immediate editing for every paired case.

| Resolution | Edits to one object | Immediate rendered p95 ms | One rebuild rendered p95 ms | Speedup (frame medians) |
|---|---:|---:|---:|---:|
| 16 | 4 | 2.955 | 0.955 | 3.50× |
| 16 | 16 | 11.618 | 0.938 | 12.61× |
| 24 | 4 | 7.683 | 2.081 | 3.70× |
| 24 | 16 | 31.350 | 2.324 | 14.02× |
| 32 | 4 | 15.483 | 4.073 | 3.92× |
| 32 | 16 | 67.498 | 4.256 | 15.42× |

A queue should deduplicate dirty objects, combine same-object hits, prioritize nearby gameplay-relevant changes, and use a time budget rather than a fixed object count. CPU meshing can be prepared on workers; GPU uploads and physics swaps need safe ownership/commit points. Density changes that happen while a worker is meshing need versioning so completed work does not overwrite newer edits.

A simple queue-drain estimate below uses the **worst process p95 single-object CPU action time** measured for a blast, then assumes whole jobs must fit in the budget. It is arithmetic, not an implemented queue benchmark. It excludes other game work, collision-commit synchronization, async latency and scheduling overhead. An object taking longer than the budget cannot be made cheap merely by putting it in a queue; it needs smaller pieces, finer-grained jobs or background work.

| Resolution | Single-object service estimate ms | Budget ms/frame | Objects/frame | Frames to finish 16 objects | Delay at 60 FPS ms |
|---|---:|---:|---:|---:|---:|
| 16 | 0.889 | 2 | 2 | 8 | 133.3 |
| 16 | 0.889 | 4 | 4 | 4 | 66.7 |
| 16 | 0.889 | 8 | 8 | 2 | 33.3 |
| 24 | 2.257 | 2 | job exceeds budget | — | — |
| 24 | 2.257 | 4 | 1 | 16 | 266.7 |
| 24 | 2.257 | 8 | 3 | 6 | 100.0 |
| 32 | 4.613 | 2 | job exceeds budget | — | — |
| 32 | 4.613 | 4 | job exceeds budget | — | — |
| 32 | 4.613 | 8 | 1 | 16 | 266.7 |

Immediate impact particles, dust and decals can hide short visual delays, but a newly visible hole should not remain blocked by old collision. Voxel-density hitscan queries could respond before mesh/collider replacement; player and rigidbody collision still need an updated representation. A queue does not remove total work, and repeated demand above its service rate grows the backlog.

## Fragment creation and debris

The split test uses two solid lobes joined by a narrow bridge. A centre cut must detach a fragment. It includes fragment allocation, remeshing, convex collision, rigidbody creation and one physics/update tick. Old fragments are removed outside the timer to repeat the same event; this does not measure permanent accumulation.

| Simultaneous splits, resolution 24 | Rendered p95 ms | Fragments per event |
|---|---:|---:|
| 1 | 1.690 | 1 |
| 4 | 5.969 | 4 |
| 16 | 22.943 | 16 |

**Correctness blocker:** the resolution-16 split test fails grid-layout validation. SpawnPiece creates a new default-resolution component, then changes resolution without resizing its sample arrays/counter before copying the parent grid. The observed fragment retains the default 25³ samples instead of 17³. Above default resolution, the source also copies a larger parent grid into default-sized fragment arrays, so those fragmentation cases were deliberately not executed. Fix and regression-test fragment allocation before using mixed resolutions for destructible map pieces. Timings for the rejected split are excluded.

Existing detached pieces retain the full parent-sized voxel grid, even when the fragment is tiny. Their collision is a convex hull, not an exact concave surface. The following debris stress uses already-created separate voxel boxes with convex rigidbodies on a floor; they are gently kept active. It isolates ongoing debris cost, not fragment spawning or a dense rubble pile.

| Active debris objects | Resolution | Worst-process rendered p95 ms | Peak process RSS MiB |
|---|---:|---:|---:|
| 100 | 8 | 0.442 | 360.766 |
| 500 | 8 | 1.635 | 1053.918 |
| 100 | 16 | 0.540 | 410.500 |
| 500 | 16 | 1.784 | 1302.949 |
| 100 | 24 | 0.463 | 517.301 |
| 500 | 24 | 1.696 | 1829.121 |

A production game should cap active fragments, remove/merge small debris, and consider converting distant settled rubble to ordinary meshes. Every retained fragment being recursively destructible costs more memory than visual rubble alone. Dense piles, chains of explosions and full structure collapse need additional tests.

## Imported model startup

Setup includes voxelization and initial collision; subsequent idle CPU ticks are not voxelizing the model repeatedly. These are simple built-in closed cube/sphere meshes, not production assets with thousands of triangles. Model voxelization scans samples against source triangles and can be much more expensive for detailed assets. Precompute/cache voxel data for shipped maps rather than voxelizing a whole level during action.

| Source | Resolution | Setup median ms |
|---|---:|---:|
| model-cube | 16 | 3.518 |
| model-cube | 24 | 6.045 |
| model-cube | 32 | 10.143 |
| model-sphere | 16 | 6.954 |
| model-sphere | 24 | 10.897 |
| model-sphere | 32 | 16.061 |

## Compute shaders

GPU meshing was **not benchmarked or implemented**. It could accelerate density processing/visual marching cubes, but current Jolt collision still needs CPU-accessible geometry and CPU shape preparation. A GPU collision-mesh generator would therefore still require asynchronous readback and physics integration. Separate coarse collision meshes may help, provided gameplay holes remain representable. The no-collider versus static-collider rows show why speeding up visual meshing alone cannot eliminate the entire update cost. Start by coalescing edits and profiling mesh/collision stages; evaluate compute against that improved CPU baseline.

## Suggested shooter design

- Use VoxelObjects for independently destructible wall sections, terrain-like blocks and props; leave weapons, characters and tiny cosmetic items as ordinary meshes unless they genuinely need volumetric destruction.
- Begin with resolution 16–24 for ordinary map sections; use small physical chunks for required detail rather than setting every large model to 48. Keep sections closed and avoid very long, thin models that waste a cubic grid.
- Ordinary bullets can use hitscan and decals. Reserve volumetric carving for explosions, digging and selected weapons; if carving every bullet, batch same-object edits before rebuilding.
- Add a deduplicated, versioned update queue with a small measured frame budget, and separate visible/hitscan responsiveness from safe physics-shape commits. Profile its queue age under sustained combat, not only average FPS.
- Fix the nondefault-resolution fragment allocation issue, bound active debris and memory, and test real map geometry with multiple simultaneous explosions before committing to a whole-map destruction design.
- Multiplayer carve event routing and shared fragment identities exist, but these tests are single-process with no network session. Bandwidth, authoritative validation, late-join world state, replication of queue delays and desync resistance are not established. Navigation updates after destruction are not included.

## Full measured inventory

Statistics are medians across processes except the explicitly named worst-process p95. Each event case uses 8 warmup and 40 samples × 3 processes unless its command specifies otherwise; idle/render tests use 40/100, rays 20/80, debris 60/120, model setup 2/10. Separate instrumented profiler runs use one process and do not contribute to practical comparison tables.

| Case | N | Res | Edits | Collision | Mode | Action median ms | Action p95 ms | Physics median ms | CPU total p95 ms | Worst-process frame p95 ms | Setup ms | RSS MiB |
|---|---:|---:|---:|---|---|---:|---:|---:|---:|---:|---:|---:|
| idle | 100 | 16 | 0 | mesh | render | 0.000 | 0.000 | 0.004 | 0.011 | 0.387 | 150.374 | 415.309 |
| shared | 100 | 16 | 0 | mesh | render | 0.000 | 0.000 | 0.003 | 0.007 | 0.321 | 35.134 | 258.805 |
| idle | 500 | 16 | 0 | mesh | render | 0.000 | 0.000 | 0.015 | 0.047 | 0.980 | 739.028 | 1323.125 |
| shared | 500 | 16 | 0 | mesh | render | 0.000 | 0.000 | 0.009 | 0.026 | 0.684 | 160.432 | 279.668 |
| idle | 1000 | 16 | 0 | mesh | render | 0.000 | 0.000 | 0.030 | 0.092 | 1.942 | 1520.316 | 2463.191 |
| shared | 1000 | 16 | 0 | mesh | render | 0.000 | 0.000 | 0.016 | 0.051 | 0.960 | 326.441 | 305.711 |
| idle | 100 | 24 | 0 | mesh | render | 0.000 | 0.000 | 0.004 | 0.013 | 0.427 | 293.721 | 530.875 |
| shared | 100 | 24 | 0 | mesh | render | 0.000 | 0.000 | 0.003 | 0.008 | 0.494 | 117.277 | 267.523 |
| idle | 500 | 24 | 0 | mesh | render | 0.000 | 0.000 | 0.016 | 0.047 | 1.364 | 1462.924 | 1894.051 |
| shared | 500 | 24 | 0 | mesh | render | 0.000 | 0.000 | 0.009 | 0.030 | 1.100 | 585.506 | 320.965 |
| idle | 1000 | 24 | 0 | mesh | render | 0.000 | 0.000 | 0.034 | 0.105 | 3.142 | 2847.054 | 3607.117 |
| shared | 1000 | 24 | 0 | mesh | render | 0.000 | 0.000 | 0.017 | 0.060 | 2.163 | 1133.716 | 387.934 |
| idle | 100 | 32 | 0 | mesh | render | 0.000 | 0.000 | 0.004 | 0.010 | 0.742 | 496.952 | 737.270 |
| idle | 500 | 32 | 0 | mesh | render | 0.000 | 0.000 | 0.013 | 0.050 | 2.603 | 2461.754 | 2942.520 |
| idle | 100 | 48 | 0 | mesh | render | 0.000 | 0.000 | 0.004 | 0.013 | 1.275 | 1174.040 | 1376.676 |
| idle | 100 | 24 | 0 | mesh | hq | 0.000 | 0.000 | 0.005 | 0.011 | 0.977 | 298.861 | 530.344 |
| idle | 500 | 24 | 0 | mesh | hq | 0.000 | 0.000 | 0.017 | 0.049 | 2.329 | 1413.976 | 1894.879 |
| shared | 500 | 24 | 0 | mesh | hq | 0.000 | 0.000 | 0.009 | 0.031 | 1.903 | 567.192 | 321.297 |
| rays | 100 | 24 | 0 | mesh | cpu | 1.562 | 1.591 | 0.003 | 1.598 | — | 261.050 | 83.867 |
| rays | 500 | 24 | 0 | mesh | cpu | 1.678 | 1.714 | 0.014 | 1.752 | — | 1300.740 | 358.504 |
| rays | 1000 | 24 | 0 | mesh | cpu | 1.604 | 1.654 | 0.028 | 1.736 | — | 2611.692 | 701.688 |
| slab | 1 | 8 | 1 | mesh | render | 0.074 | 0.079 | 0.001 | 0.081 | 0.222 | 1.785 | 250.152 |
| shots | 1 | 16 | 1 | none | cpu | 0.255 | 0.320 | 0.001 | 0.323 | — | 1.962 | 13.727 |
| shots | 1 | 16 | 1 | mesh | cpu | 0.720 | 0.739 | 0.001 | 0.741 | — | 2.583 | 14.355 |
| shots | 1 | 16 | 1 | dynamic | cpu | 0.323 | 0.380 | 0.018 | 0.394 | — | 2.178 | 14.059 |
| shots | 1 | 16 | 1 | mesh | render | 0.659 | 0.683 | 0.002 | 0.685 | 0.949 | 2.575 | 250.984 |
| slab | 1 | 16 | 1 | mesh | render | 0.321 | 0.374 | 0.002 | 0.376 | 0.615 | 2.100 | 250.434 |
| shots-split | 1 | 16 | 1 | mesh | cpu | 0.734 | 0.758 | 0.001 | 0.759 | — | 2.614 | 14.359 |
| shots | 1 | 24 | 1 | none | cpu | 0.681 | 0.688 | 0.001 | 0.688 | — | 2.718 | 13.785 |
| shots | 1 | 24 | 1 | mesh | cpu | 2.151 | 2.172 | 0.001 | 2.174 | — | 4.140 | 15.473 |
| shots | 1 | 24 | 1 | dynamic | cpu | 0.768 | 0.782 | 0.017 | 0.813 | — | 2.696 | 14.012 |
| shots | 1 | 24 | 1 | mesh | render | 1.818 | 1.837 | 0.002 | 1.839 | 2.098 | 4.017 | 253.125 |
| slab | 1 | 24 | 1 | mesh | render | 0.815 | 0.831 | 0.002 | 0.833 | 1.023 | 2.995 | 251.383 |
| shots-split | 1 | 24 | 1 | mesh | cpu | 2.212 | 2.223 | 0.001 | 2.224 | — | 4.275 | 15.539 |
| shots | 1 | 32 | 1 | none | cpu | 1.326 | 1.348 | 0.001 | 1.349 | — | 3.505 | 14.609 |
| shots | 1 | 32 | 1 | mesh | cpu | 4.281 | 4.317 | 0.001 | 4.319 | — | 6.973 | 17.809 |
| shots | 1 | 32 | 1 | dynamic | cpu | 1.457 | 1.467 | 0.018 | 1.489 | — | 3.575 | 14.723 |
| shots | 1 | 32 | 1 | mesh | render | 3.601 | 3.625 | 0.002 | 3.628 | 3.978 | 6.702 | 254.887 |
| slab | 1 | 32 | 1 | mesh | render | 1.419 | 1.432 | 0.002 | 1.434 | 1.606 | 4.048 | 251.148 |
| shots-split | 1 | 32 | 1 | mesh | cpu | 4.440 | 4.463 | 0.001 | 4.465 | — | 6.877 | 17.965 |
| shots | 1 | 48 | 1 | none | cpu | 3.413 | 3.642 | 0.001 | 3.643 | — | 6.701 | 16.672 |
| shots | 1 | 48 | 1 | mesh | cpu | 10.589 | 10.659 | 0.001 | 10.662 | — | 14.841 | 23.957 |
| shots | 1 | 48 | 1 | dynamic | cpu | 3.538 | 3.883 | 0.011 | 3.913 | — | 7.085 | 17.078 |
| shots | 1 | 48 | 1 | mesh | render | 10.883 | 11.047 | 0.003 | 11.051 | 11.409 | 14.702 | 263.395 |
| slab | 1 | 48 | 1 | mesh | render | 3.995 | 4.046 | 0.002 | 4.048 | 4.420 | 8.635 | 254.902 |
| shots-split | 1 | 48 | 1 | mesh | cpu | 11.168 | 11.227 | 0.001 | 11.229 | — | 14.767 | 24.324 |
| blast | 1 | 16 | 1 | mesh | render | 0.827 | 0.874 | 0.002 | 0.876 | 1.059 | 2.648 | 250.879 |
| blast | 4 | 16 | 4 | mesh | render | 3.173 | 3.214 | 0.002 | 3.217 | 3.605 | 7.508 | 253.641 |
| blast | 16 | 16 | 16 | mesh | render | 12.448 | 12.524 | 0.003 | 12.529 | 12.963 | 25.494 | 265.230 |
| blast | 1 | 24 | 1 | mesh | render | 2.233 | 2.251 | 0.002 | 2.253 | 2.443 | 4.188 | 252.875 |
| blast | 4 | 24 | 4 | mesh | render | 8.928 | 8.983 | 0.002 | 8.987 | 9.422 | 12.996 | 258.305 |
| blast | 16 | 24 | 16 | mesh | render | 36.144 | 36.537 | 0.007 | 36.547 | 38.120 | 47.866 | 281.500 |
| blast | 1 | 32 | 1 | mesh | render | 4.402 | 4.427 | 0.002 | 4.429 | 4.821 | 6.745 | 255.766 |
| blast | 4 | 32 | 4 | mesh | render | 17.589 | 17.699 | 0.002 | 17.703 | 18.827 | 21.851 | 265.945 |
| blast | 16 | 32 | 16 | mesh | render | 72.462 | 72.695 | 0.010 | 72.708 | 76.886 | 82.343 | 317.246 |
| burst | 1 | 16 | 4 | mesh | render | 2.663 | 2.683 | 0.002 | 2.685 | 2.955 | 2.681 | 252.129 |
| batch | 1 | 16 | 4 | mesh | render | 0.673 | 0.693 | 0.002 | 0.695 | 0.955 | 2.605 | 250.992 |
| burst | 1 | 16 | 16 | mesh | render | 10.961 | 10.977 | 0.002 | 10.980 | 11.618 | 2.723 | 254.672 |
| batch | 1 | 16 | 16 | mesh | render | 0.749 | 0.771 | 0.002 | 0.773 | 0.938 | 2.669 | 250.570 |
| burst | 1 | 24 | 4 | mesh | render | 7.380 | 7.424 | 0.002 | 7.426 | 7.683 | 4.207 | 254.762 |
| batch | 1 | 24 | 4 | mesh | render | 1.892 | 1.909 | 0.002 | 1.911 | 2.081 | 4.190 | 252.523 |
| burst | 1 | 24 | 16 | mesh | render | 30.474 | 30.612 | 0.003 | 30.617 | 31.350 | 4.171 | 261.840 |
| batch | 1 | 24 | 16 | mesh | render | 2.048 | 2.069 | 0.002 | 2.071 | 2.324 | 4.167 | 252.246 |
| burst | 1 | 32 | 4 | mesh | render | 15.077 | 15.115 | 0.002 | 15.117 | 15.483 | 6.868 | 258.605 |
| batch | 1 | 32 | 4 | mesh | render | 3.727 | 3.747 | 0.002 | 3.749 | 4.073 | 6.949 | 254.898 |
| burst | 1 | 32 | 16 | mesh | render | 64.055 | 66.251 | 0.006 | 66.260 | 67.498 | 6.685 | 271.621 |
| batch | 1 | 32 | 16 | mesh | render | 4.020 | 4.048 | 0.002 | 4.050 | 4.256 | 6.945 | 255.801 |
| split | 1 | 24 | 1 | mesh | render | 1.268 | 1.283 | 0.143 | 1.428 | 1.690 | 2.566 | 252.762 |
| split | 4 | 24 | 4 | mesh | render | 5.023 | 5.067 | 0.449 | 5.534 | 5.969 | 7.683 | 262.309 |
| split | 16 | 24 | 16 | mesh | render | 19.691 | 20.342 | 1.516 | 21.914 | 22.943 | 27.645 | 281.031 |
| debris | 100 | 8 | 0 | dynamic | render | 0.004 | 0.004 | 0.074 | 0.140 | 0.442 | 98.651 | 360.766 |
| debris | 500 | 8 | 0 | dynamic | render | 0.019 | 0.019 | 0.271 | 0.522 | 1.635 | 469.825 | 1053.918 |
| debris | 100 | 16 | 0 | dynamic | render | 0.004 | 0.004 | 0.114 | 0.211 | 0.540 | 127.082 | 410.500 |
| debris | 500 | 16 | 0 | dynamic | render | 0.020 | 0.022 | 0.449 | 0.813 | 1.784 | 623.634 | 1302.949 |
| debris | 100 | 24 | 0 | dynamic | render | 0.004 | 0.004 | 0.074 | 0.146 | 0.463 | 182.372 | 517.301 |
| debris | 500 | 24 | 0 | dynamic | render | 0.020 | 0.021 | 0.276 | 0.580 | 1.696 | 891.822 | 1829.121 |
| model-cube | 1 | 16 | 0 | mesh | cpu | 0.000 | 0.000 | 0.001 | 0.001 | — | 3.518 | 14.137 |
| model-cube | 1 | 24 | 0 | mesh | cpu | 0.000 | 0.000 | 0.001 | 0.001 | — | 6.045 | 15.312 |
| model-cube | 1 | 32 | 0 | mesh | cpu | 0.000 | 0.000 | 0.001 | 0.001 | — | 10.143 | 17.793 |
| model-sphere | 1 | 16 | 0 | mesh | cpu | 0.000 | 0.000 | 0.001 | 0.001 | — | 6.954 | 14.371 |
| model-sphere | 1 | 24 | 0 | mesh | cpu | 0.000 | 0.000 | 0.001 | 0.001 | — | 10.897 | 15.023 |
| model-sphere | 1 | 32 | 0 | mesh | cpu | 0.000 | 0.000 | 0.001 | 0.001 | — | 16.061 | 16.516 |

## Reproducibility and validation

- 254 measurement processes: 249 pass fixture validation; 5 rejected. Rejections are four coarse-grid bullet cases and one nondefault fragment-layout case, not accepted performance wins.
- Accepted runs must return success, emit complete finite timings, report finite final mesh positions, and have no solver-capacity error. Every edit must report success and remove positive solid samples; fragment tests must actually create pieces with the correct grid layout. Digging must open collision to a ray. Ray batches must all hit. Rendered runs must emit all frame intervals and nonzero draw calls.
- All geometry is local to a isolated checkout of the recorded commit and freshly built native dependencies. No engine implementation changes were made. The coalescing prototype lives only in the benchmark harness. The engine commit and its source files were not modified. Native archive was built with the current Release configuration; Beef Release uses GNU linking with ThinLTO unavailable.
- Timed edit/action includes CarveLocal or the prototype, full mesh creation, collision rebuilding and uploads on rendered runs. CPU total also includes one 60 Hz Scene.FixedUpdate and one Scene.Update. Full-frame intervals include rendering/presentation. At overload this harness does not accumulate real-time catch-up ticks; it measures service cost, not sustained whole-game FPS.
- Density restoration, fragment cleanup needed to repeat an identical event and correctness scans are outside SAMPLE action/CPU timings but are included in inter-frame FRAME timings. Final aggregate checks are after the measurement loop. A real game still pays for its own cleanup and event routing. Extremely complex accumulated damage, dense debris piles, production material interiors, many lights, network traffic and player simulation are not covered. The floor and test colliders are physics-only; real environment drawing adds work.
- Resolution is cells along the grid’s longest side, clamped to 8–48. Primitive test grids are 4 m across, with the engine’s normal empty margin; cubes are therefore smaller than the grid. A slab is a custom thin density field. Spawned pieces keep the same parent grid.
- Peak RSS includes temporary/driver/benchmark allocations and is not a memory allocator breakdown or VRAM measurement. Processes run sequentially, unpinned, on an ordinary desktop; clocks and background load are uncontrolled. Small run-to-run differences are not guarantees.

- [Per-group CSV](summary.csv), [per-process CSV](processes.csv), [commands and checks](manifest.json), [source hashes](source-sha256.json), [benchmark source](../../voxel/src/Program.bf), [runner](../../voxel/run.py).
- All raw phase samples, frame intervals, profiler recordings and build logs are packaged in [raw-data.tar.gz](raw-data.tar.gz); its file list and SHA-256 are in [artifact-integrity.json](artifact-integrity.json).

## Charts

![Voxel rendering, destruction, coalescing and memory](voxel-capacity.png)

[Export SVG](voxel-capacity.svg).

[Validation audit](validation.json), [environment](environment.json), [wall-hole visual check](slab.png).
