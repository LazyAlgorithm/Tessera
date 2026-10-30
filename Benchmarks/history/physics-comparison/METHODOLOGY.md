> Historical standalone backend benchmark; no Tessera runtime. Full source/data bundle: [physics-engine-results.zip](physics-engine-results.zip).

# Standalone Beef benchmark: Jolt, Box3D, Rapier, Bullet

This suite measures four native 3D physics engines through one Release Beef executable. No Tessera runtime, scene code, renderer, physics wrapper, or build configuration is used. All numbers in the report come from fresh runs of this suite; earlier two-engine results are not reused.

## Machine and tools

AMD Ryzen 9 7900X, 12 physical cores / 24 logical CPUs, approximately 64 GiB installed memory. Nobara Linux, kernel 7.2.11-200.nobara.fc44.x86_64. GCC 16.2.1, Rust 1.99.1, BeefBuild 0.43.6. Beef selected its GNU backend because the matching LLVM linker was unavailable; the Release build uses `-O2`, without LTO. C/C++ engine libraries use Release `-O3`, Rust uses release / opt-level 3, and neither uses LTO. Exact compiler commands and revision hashes are retained in `build/*/compile_commands.json` and `results/metadata.json`.

CPU governor `performance`, boost enabled. Single-worker runs are pinned to logical CPU 0; four-worker runs to CPUs 0–3, distinct physical cores sharing the same L3/CCD. SMT siblings are excluded from the affinity mask. The desktop remained running; frequency and unrelated activity were not laboratory-controlled. All benchmark processes run sequentially, with no compilation during the measured suite. Random ordering and repetitions reduce, but do not eliminate, desktop noise.

### Versions

- Jolt 5.6.0, upstream release commit `e77f175595e64cb44218cc9d9d56fc365ad0e36a`.
- Box3D 0.1.0 development snapshot, upstream main commit `336263320469e5e9febfe18697ab562488f7e97a`.
- Rapier 0.36.1 development snapshot, upstream master commit recorded in metadata (`475caa3…`).
- Bullet 3.26 development snapshot, upstream master commit recorded in metadata (`d3afe76…`). This is the traditional Bullet rigid-body pipeline, not a GPU/OpenCL benchmark.

All engine source checkouts are unmodified. Wrappers, sources, scripts, and binary hashes are supplied. These measurements compare the named revisions, not all historical versions of each engine.

## Beef and native boundaries

`driver/src/Program.bf` owns scene generation, bodies' input descriptions, the outer 60 Hz loop, individual step timing, query generation and the per-query call loop, statistical aggregation, and diagnostic readback. Every engine is reached through exactly the same C ABI in `backend.h` and `backend.cpp`, including matching POD structures checked at startup with `sizeof` validation.

The C++ adapter calls Jolt and Bullet's native C++ APIs, Box3D's native C API, and Rapier's official Rust C bindings. Therefore Rapier's supplied C-binding checks are part of its measured cost. The adapter is intentionally small and does not emulate a full game-engine integration. Bodies/shapes are created outside the timed step loop; query results return the same common fields: hit status, fraction, world-space point, and world-space normal. Jolt rays additionally acquire a body read lock and calculate the surface normal, matching the useful result payload rather than comparing fraction-only queries against richer APIs.

The clock is `std::chrono::steady_clock`, exported as nanoseconds through the same library. Beef calls it immediately before and after a step or query batch. Two clock-call overheads are included in each frame time. Query batches amortize timer overhead. A separate one-million-call no-op test quantifies Beef-to-native call/loop overhead. Separate fresh-process C++-loop controls perform the same simulation steps from inside the adapter, allowing comparison with the Beef outer loop. These controls alternate execution order and are not mixed into the primary rankings.

Native engines inevitably use their implementation languages internally; “using Beef” means the same Beef host and native-boundary path for all four, not rewriting their solvers in Beef.

## Build profiles

`fast`: local CPU throughput profile. Native C/C++ is compiled for `x86-64-v3`; Jolt enables AVX/AVX2 and its usual supporting instruction sets; Box3D selects AVX2 width 8; Rapier uses width 8 and parallel execution. Rust targets x86-64-v3. FMA contraction is disabled in the C/C++ builds; no fast-math is used. Jolt cross-platform-deterministic mode is off. This configuration is not a claim of cross-platform determinism.

`deterministic`: Jolt cross-platform-deterministic mode on, AVX/AVX2/F16C/LZCNT/TZCNT off; Box3D compiled without its AVX2 path and forced to width 4; Rapier enhanced-determinism on, SIMD width 4, parallel execution still on. Rust targets x86-64. Bullet is compiled for the baseline CPU in this profile; **Bullet is not thereby guaranteed cross-platform deterministic**. This label describes a comparison configuration, not a certification of every engine or of networking code.

Single precision, assertions/profilers/heavy validation off, no rendering, no GPU simulation, no network, no application event callbacks, no user collision callbacks. Float precision and SIMD settings are reported independently of solver settings.

### Thread counts

The reported count is the requested maximum **active physics workers** and the CPU affinity budget. It is not a count of every live OS thread:

- Jolt: 0 or 3 background workers plus the calling thread, explicitly constructed with the native thread-pool API.
- Box3D: internal scheduler, 1 or 4 workers including the caller.
- Rapier: a private Rayon pool configured with 1 or 4 workers. The host caller can wait while that pool executes; the process may have one additional live thread.
- Bullet: sequential dynamics world for one worker; `btDiscreteDynamicsWorldMt`, `btCollisionDispatcherMt`, `btConstraintSolverPoolMt`, and `btSequentialImpulseConstraintSolverMt` for four workers. The default scheduler is capped at four active threads, but creates additional dormant OS worker threads (24 live process threads were observed). This is included in its real setup/memory cost; all inherit the same CPU affinity.

Queries always execute serially from the Beef caller on CPU 0, regardless of whether the library supports parallel simulation.

## Common physical inputs

Gravity `(0,-9.81,0)` m/s². Density 1,000 kg/m³. Restitution 0. Linear and angular damping 0, avoiding different engine damping formulas. Effective contact friction 0.5: Jolt and Box3D use their normal geometric-mean rule, Rapier uses its default rule on equal coefficients, and Bullet surface coefficients are sqrt(0.5) because Bullet multiplies them. This yields effective friction 0.5 within float rounding.

Static/dynamic collision selection is equivalent: dynamic–dynamic and dynamic–static enabled, static–static irrelevant. No sensors, joints, ignored bodies, custom filtering, controller systems, per-frame transform synchronization, or readback inside the timed steps. Sleep is disabled on all dynamic bodies in main runs. CCD is disabled unless the row explicitly says otherwise.

All initial positions, quaternion components, dimensions, material inputs, and creation order are generated once by the same Beef code path for every engine. The same arithmetic generates mesh vertices/indices and query positions. Cube geometry has zero rounding in all engines, including Bullet's box margin and Jolt's convex radius; this deliberately measures matching sharp geometry instead of each engine's preferred default rounded shape.

Automatic mass/inertia is used for cubes and spheres. Capsule and hull geometry/mass are matched across engines. Bullet's capsule inertia is explicitly set to the analytic cylinder-plus-hemispheres tensor; the square-pyramid hull is centered at its analytic center of mass, with the analytic inertia explicitly supplied to Bullet. This avoids comparing Bullet's approximate bounding-box inertia with the other engines' integrated hull properties. Last-bit differences in floating-point mass calculations remain possible.

### Scenes

Every row lists **dynamic bodies**. Add **one static ground body** in every scene. A mesh ground is one static object containing **2,000 triangles / 1,066 vertices**, not 2,000 static rigid bodies.

- `stack`: 1,000 or 4,000 axis-aligned 1 m cubes on a regular lattice, horizontal/vertical spacing 1.02 m, bottom center y=0.55 m. Lattice width ceil(cuberoot(N)) = 10 or 16. Ideal uncompressed highest center is 9.5 or 15.5 m. This strongly stresses persistent, nearly aligned contacts.
- `tumble`: the same cubes with reproducible rotations around `(1,1,1)/sqrt(3)`, lattice spacing 1.8 m and bottom center y=1 m. Each angle comes from fixed unsigned integer arithmetic. Cubes fall into a disordered pile.
- `spheres`: radius-0.5 m spheres on the stack lattice. Spheres may roll/spread during the run.
- `sparse`: 1 m cubes in a single layer, spacing 3 m, width ceil(sqrt(N)), bottom center y=0.55 m. All still contact the floor; this is not free flight.
- `mesh`: 484 dynamic bodies in a 22×22 single layer, spacing 4 m, center y=8 m. Shapes alternate boxes (half extents 0.5,0.75,1), spheres (r=0.5), capsules (r=0.5, cylindrical half-height 0.75), and square-pyramid convex hulls (vertices `(0,.75,0)`, `(±1,-.25,0)`, `(0,-.25,±1)`). Ground is a shared 40×25-cell triangle grid, 5 m cells, centered horizontally, height `1.5*sin(x*.08)*cos(z*.08)`.

The non-mesh ground is a sharp 2,000×1×2,000 m box with top y=0. The very large flat box is identical geometry in all engines; its collision-algorithm performance may differ from that of a mesh floor or finite platform.

### Solvers, timesteps and substeps

Every main run advances 600 fixed ticks at 1/60 second: 10 simulated seconds. Main/default solver configuration:

| Engine | Outer calls/tick | Native substeps/collision steps | Solver settings |
|---|---:|---:|---|
| Jolt | 1 | 1 collision step | Default 10 velocity + 2 position iterations; mesh uses 4 + 1 |
| Box3D | 1 | 4 Soft Step solver substeps | Native solver defaults: 30 Hz contacts, damping ratio 10, correction speed cap 3 m/s |
| Rapier | 1 | 4 solver substeps/iterations | 1 internal PGS + 1 stabilization iteration per solver substep |
| Bullet | 1 | 1 fixed integration step | Default 10 solver iterations; mesh uses 5 |

The mesh iteration choices mirror the intention of Jolt's old comparison (Jolt 4 velocity + 1 position, Bullet 5), but **this is not a byte-for-byte rerun of the historical benchmark**: engine revisions, hardware, geometry, materials and some solver implementations differ. It tests whether the broad performance trend holds in a similar modern workload. Original reference: https://jrouwe.nl/jolt/JoltPhysicsMulticoreScaling.pdf.

Substep-control runs use 4,000 stacked cubes at one and four workers. Combined with main runs, every engine is tested with native count 1 and count 4. For Jolt this means `Update(dt, collisionSteps)`, Box3D `Step(dt, substeps)`, Rapier `numSolverIterations`, and Bullet `stepSimulation(dt, substeps, dt/substeps)`. **Equal counts do not mean equal solver work, contact refresh frequency, or accuracy.** Each engine retains its solver algorithm and inner iteration defaults. Both the default and count controls must be read alongside the quality diagnostics, not treated as proof of equal accuracy.

### CCD and failures

Additional mesh tests enable CCD in every engine, at both the default counts and count 4 for all engines. Jolt uses LinearCast; Box3D enables continuous collision; Rapier enables body CCD and one CCD pass; Bullet enables CCD with motion threshold 0.01 m and swept-sphere radius half the smallest half-extent. Bullet's swept-sphere approximation is not identical to shape-based CCD. These are API-supported CCD paths, not equal algorithms.

Trials with escaped centers, nonfinite state, or explicit update errors are retained and marked invalid. Invalid trials are not ranked as successful fast simulations. A finite but visibly compressed/collapsed pile can pass these coarse checks; it remains necessary to examine stack height and residual speed.

## Timing, repetition and validation

396 simulations: 216 optimized main runs; 120 four-wide comparison main runs; 24 substep controls; 12 sleeping-stack runs; 12 mesh CCD runs; 12 mesh CCD/four-step runs. Each configuration has three fresh-process repetitions. Order is shuffled using seed 20261028. No simulation warmup is discarded: initial impacts are part of the common ten-second workload. First/last 120-frame means separate startup and late behavior.

Simulation timings exclude setup, construction, mesh cooking, broadphase preparation, final diagnostics, queries, logging, and teardown. Individual frame timings are collected by Beef. Tables report the median of three per-run means and, separately, the median of three per-run p95 values; they do not pool all frames into one p95. Repeat min/max mean times are supplied in summary CSVs.

Before measurement, every engine/profile/thread configuration passes a two-second free-fall test with an isolated cube and ABI-size checks. The free-fall test checks downward velocity near −19.62 m/s and plausible integrated position, preventing a successful API status from concealing an unadvanced simulation. Main diagnostics inspect every dynamic body's position, quaternion, linear/angular velocity for nonfinite values, active body count, minimum/maximum center height, RMS linear/angular speed, a positional checksum, and escaped centers. Non-mesh escape means center below y=0 or beyond the floor edges; mesh escape means center below y=−5, beneath the entire terrain. These are partial correctness checks, not an exhaustive contact, energy, angular-constraint, or determinism validation.

An important setup finding: calling Rapier's collision-only `DetectCollisions` preparation before subsequently advancing this snapshot left bodies unadvanced in the initial smoke test. Simulations therefore use its ordinary creation→Step path. Frozen query tests use DetectCollisions and never subsequently step that world. This workaround is in the adapter; the engine sources are not patched. Startup/validation logs are retained in `results/smoke.log`.

## Query settings

Identical initial unsimulated geometry. Bodies start awake; nothing moves during query timing. Jolt optimizes its broadphase, Bullet updates AABBs/pairs and explicitly optimizes both DBVT trees, Rapier runs collision-only detection, and Box3D uses its populated trees. Query shapes are created/cached outside the timing, except Bullet's inexpensive stack-allocated sphere used for the sweep call.

All queries are **closest-hit**, all layers/categories, dynamic and static objects included; no ignored body, debris logic, application predicate, sensors, or hit-array allocation. World-space origin/delta/radius/kind are passed through the same Beef ABI. Results include point and normal for every backend. Ray origins and sweeps start outside all shapes. Triangle backface behavior is irrelevant in the boxes/spheres scenes; mesh queries are directed toward the top-facing surface. Mesh tests may differ in backface/internal-edge handling according to the engines' defaults.

For both build profiles and all four engines, queries run on 1,000 and 4,000 box/sphere scenes and the 484-body mesh scene. For each query mode: one discarded warmup batch, then five measured batches of 20,000 calls. Median batch ns/query is reported; hit counts, fraction sums, and normal sums are recorded to flag differences in geometry/query behavior. Query timings include Beef's shared origin generation, loop, ABI crossing, and result accumulation. Consequently the timing is useful for the user's requested Beef-hosted comparison, not a pure isolated inner collision-function cost.

Let W be the scene's lattice width. E = W×1.02×0.6 m for boxes/spheres and W×4×0.6 m for mesh. x/z are reproducible samples in [−E,E] using fixed 32-bit arithmetic and 16-bit components.

| Query | Origin and displacement | Result expectations |
|---|---|---|
| Ray down | `(x,100,z)` + `(0,−200,0)`, 200 m | Flat-ground scenes guarantee a hit |
| Ray across | `(-E−2,y,z)` + `(2E+4,0,0)`; y in `[.05,W×1.02+2.05]` | Mixed hits/misses; length 16.24 / 23.584 m for 1,000 / 4,000 box or sphere scenes |
| Ray miss | `(x,100,z)` + `(0,100,0)`, 100 m | No geometry hit |
| Sphere sweep down | Radius .25 m, same 200 m downward path | Closest hit, zero target separation, initial-overlap geometry enabled where applicable |

Jolt sphere casts use `mReturnDeepestPoint=true`; Rapier casts use zero target distance, stop-at-penetration and compute-impact-geometry-on-penetration; Box3D clips a closest-hit callback; Bullet uses its closest convex-sweep callback. The starts are outside all geometry, so initial-overlap semantics do not drive this comparison. Shape casting computes more geometry internally in some engines; matching the public result does not force identical internal algorithms.

## Scope

This suite measures standalone native engine throughput and common queries from Beef. It does not measure Tessera, rendering, network transport, gameplay code, 2D simulation, GPU physics, joint/character-controller performance, WebAssembly, cross-platform replay hashes, power consumption, or migration effort. A deterministic build switch is not itself a cross-platform validation. Actual scene behavior and solver quality can change rankings substantially.

## Final control corrections and audit trail

Before accepting the CCD controls, Bullet's activation threshold was reduced from .25 m to .01 m so the tested impacts actually trigger its CCD path. Those CCD-specific rows were rerun; no non-CCD code path changed. Rapier mesh tests were rerun with an explicit fixed rigid body for the ground, matching the other engines rather than using a standalone static collider. Superseded rows remain in `results/superseded-mesh-controls.csv`. Bullet's frozen query tests were also rerun after explicit DBVT optimization; insertion-built-tree results are retained in `results/superseded-bullet-unbalanced-queries.csv`. The final report uses corrected controls.

Eight additional final-state captures (one per engine and native count 1/4) inspect the 4,000-cube stack after ten seconds. These are diagnostic snapshots, not extra timing repetitions in the main tables. The expected uncompressed mean center height is 7.82 m. Source/binary hashes before and after the diagnostic-only Beef output addition are retained in metadata.
