> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Tessera / Unity standalone performance study

This suite measures current Tessera engine integrations, not an editor viewport or an empty synthetic render loop. It extends the existing `/home/zerker24/EngineBenchmarks` Tessera harness with a new Unity project and additional Tessera workloads. All projects and results here are new. Existing Unity projects were not opened or edited. No changes were pushed.

## Builds and official sources

Unity **6000.3.27f1**, Unity 6.3 LTS, Linux x86_64 was installed with the existing Unity CLI from Unity's release service. The Editor is at `/home/zerker24/Unity/Hub/Editor/6000.3.27f1/Editor/Unity`. Installation required no administrator rights. The existing Unity Personal license was found in the Flatpak Hub's XDG configuration; license files and credentials are not included here.

- [Unity release notes and downloads](https://unity.com/releases/editor/whats-new/6000.3.27f1)
- [Official release archive](https://unity.com/releases/editor/archive)
- [Physics.Simulate](https://docs.unity3d.com/6000.3/Documentation/ScriptReference/Physics.Simulate.html)
- [BuildPipeline.BuildPlayer](https://docs.unity3d.com/6000.3/Documentation/ScriptReference/BuildPipeline.BuildPlayer.html)

Unity: Linux standalone, Mono backend, `BuildOptions.None`, nondevelopment, no script debugging, Vulkan, linear color, no MSAA, vSync disabled. Mono was available with the Editor and is a shipping standalone configuration; this is not an IL2CPP comparison. Standard material is included as a Resources asset to prevent shader stripping. Build generation is in `unity/Assets/Editor/BenchmarkBuild.cs`.

Tessera: independent Beef Release executable linking the current `<local-tessera>/Engine` and its Release native archives (`-O3 -DNDEBUG`). The Beef toolchain reports ThinLTO disabled because matching LLVM linker tools are unavailable. No administrator installation was attempted. This is not a packaged game export, but it runs the engine directly with no editor overhead. Source/native library hashes and build metadata are retained with the results.

## Reproduce

```bash
cd historical benchmark root/full-engine
BeefBuild -workspace="$PWD/tessera" -config=Release -verbosity=minimal
XDG_CONFIG_HOME=/home/zerker24/.var/app/com.unity.UnityHub/config \
XDG_DATA_HOME=/home/zerker24/.var/app/com.unity.UnityHub/data \
/home/zerker24/Unity/Hub/Editor/6000.3.27f1/Editor/Unity \
  -batchmode -nographics -quit -projectPath "$PWD/unity" \
  -executeMethod BenchmarkBuild.Build -logFile "$PWD/unity-build.log"
python3 run.py --counts 100 1000 --warmup 120 --samples 300 --repeats 3
python3 run.py --suite render --counts 10000 --warmup 120 --samples 300 --repeats 3
python3 run.py --suite scene --counts 10000 --warmup 120 --samples 300 --repeats 3
python3 run.py --engines tessera --scenarios scene-animation-sample scene-serialize scene-deserialize scene-network-codec --counts 100 1000 --warmup 120 --samples 300 --repeats 3
```

Run sequentially on a desktop with hardware GPU access. Never overlap builds or benchmark runs. The runner alternates engine order between repetitions, checks process exits, exact sample counts and finite nonnegative timings, saves per-process output, per-run distributions, peak RSS and correctness observations. It writes CSVs after each process to retain partial evidence if interrupted. `environment.json` includes CPU/GPU/driver data and source hashes. `summary.csv` reports mean, median, p95 and p99 per fresh process; reports use the median of per-process medians. 1,000 divided by frame milliseconds is throughput FPS only for rendering; physics/query rates are not game FPS.

Screenshot collection (`--screenshots`) is for separate visual validation runs. Screenshot readback can stall a frame and is deliberately omitted from production timing runs. Early smoke runs remain as diagnostic evidence, not final results. `builds/`, Beef intermediate products, and Unity Library/Temp directories are ignored. Source, project settings, raw results, screenshots, and reports are retained.

## Workload coverage

| Area | Workloads | Interpretation/checks |
|---|---|---|
| Dynamics | `physics-free`, `physics-pile`, `physics-mixed-shapes`, `physics-mesh` | 60 Hz; boxes/spheres/capsules; gravity and contact load; finite positions and below-terrain checks. |
| Queries | raycast, mesh-raycast, spherecast, capsulecast, boxcast, overlap-sphere/capsule/box | 1,000 queries per sample, reusable overlap buffers, initial physics step to initialize spatial trees; raycasts require 1,000 hits per batch. |
| Fast collision | `physics-discrete`, `physics-ccd` | Reset projectiles above a thin slab at 300 m/s before every step; reset excluded; record tunneled bodies. Different CCD algorithms/solver quality. |
| Characters | flat ground and steps | Native Tessera dynamic CharacterMotor vs a simple Unity capsule velocity motor. Unity is not CharacterController here. No ratios: distinct motor behavior. |
| Rendering | shared geometry/material, unique materials, moving transforms, 90% behind-camera culling, shadows, 320-triangle spheres, 16 point lights | 1280x720; FOV 60; far 1,000; GPU-backed Vulkan in both; screenshots verify framing. Native shading differs. |
| Combined game loop | `render-physics` | Physics plus rendering through standalone engine loops; Tessera uses a real-time accumulator, Unity benchmark explicitly simulates once per rendered frame. This does not represent equal simulated seconds and must not be ranked as identical gameplay. |
| Particles | `render-particles` | N long-lived stationary mesh particles, burst once, gravity/speed zero; check alive count. Tessera has per-particle spin, size/color interpolation and unlit shading; Unity uses its native mesh particle renderer and lit Standard material. Native feature test, not matched particle shader cost. |
| Scene overhead | `scene-empty` | N empty objects; Tessera Scene.Update traverses native systems, Unity CPU baseline has no matching public Scene.Update. No ratio. |
| Script work | `scene-scripts` | Tessera native component Update dispatch vs explicitly invoking C# Tick on disabled MonoBehaviours. Same position increment, different dispatch mechanism. No ratio. |
| Transforms | `scene-transforms`, `scene-hierarchy` | Increment each local position and consume each world position; hierarchy chains of depth 8. Tessera additionally runs Scene.Update. |
| Allocation/lifecycle | `scene-churn` | Create N named objects, add one script, immediately destroy them; N persistent empty objects remain. Includes native lifecycle registration and destruction. |
| Animation sampling (Tessera only) | `scene-animation-sample` | N groups × 32 bone-track samples, 16 keys/track, native position/quaternion/scale interpolation. This isolates clip sampling, not Animator graphs, retargeting or skinning. |
| Scene serialization (Tessera only) | `scene-serialize`, `scene-deserialize` | Native scene text format, N objects; reusable output string for save; fresh scene allocation/load/destruction for load; object count validated. Warm in-memory data, not cold disk throughput. |
| Network serialization (Tessera only) | `scene-network-codec` | N variable-width IDs, Vector3 positions, Quaternion rotations and uint32 flags; native writer and bounds-checked reader; checks every decoded ID, x coordinate and flags. CPU codec only, not packet delivery or prediction. |

## Limits on interpretation

This is a broad engine benchmark suite, not a claim that every feature or real game has been measured. Timing results depend on scene content, native defaults, optimization choices and this machine.

- Physics timings include Tessera fixed/update callbacks and transform sync; Unity uses Physics.Simulate and consumes Rigidbody transforms. Both use native solver/worker defaults and sleeping disabled. They are integration costs, not equal-accuracy solver or programming-language comparisons. Setup is excluded from samples and reported separately.
- Queries include hits and different populated/empty positions in overlap cases. Overlap contact counts and subshape semantics differ. The published check is whether a query found any contact; not equal manifold generation.
- Objects in the original 20×20 lattice stack into layers at counts above 400. Population is not visible object count. Increased population can increase occlusion, culling, overlap or contact density rather than maintaining constant work per object.
- Rendering uses native pipeline defaults (Tessera sky/fog/tonemap and bgfx instancing, Unity Built-in forward/Standard). Quality, batching, shadows and material variants are not equivalent. Screenshots document visible differences. Frame intervals include CPU work, synchronization and GPU backpressure. They do not isolate GPU time or prove a CPU/GPU bottleneck. Desktop composition and other processes can affect tails.
- No overall engine score or universal speed multiplier is valid. Do not average ratios across unrelated query batches, ticks and render frames. CCD results that tunnel do not establish equal correctness.
- Core frame samples are buffered differently by the runtimes; tiny microsecond workloads are sensitive to timer, callback and logging overhead. Repeats and percentiles expose variability but do not remove it.
- Asset import/decode and cold disk loading, full Animator/skinning/IK/retargeting, navigation/pathfinding, audio mixing/streaming, UI/text, terrain/foliage/voxel specializations, joint/ragdoll constraints, networking transport/latency/loss/prediction, editor interaction/reload, platform portability and long-session leak behavior remain **unmeasured**. Their presence in Tessera is not evidence of their performance. A practical game profile should select these based on actual content.
