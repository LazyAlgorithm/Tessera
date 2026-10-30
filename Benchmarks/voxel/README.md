# Voxel destruction benchmark

Build native dependencies from this checkout in Release, compile the engine shaders, then run:

```sh
BeefBuild -workspace=Benchmarks/voxel -config=Release
python3 Benchmarks/voxel/run.py Benchmarks/results/voxel-local
python3 Benchmarks/voxel/plot.py Benchmarks/results/voxel-local
python3 Benchmarks/voxel/report.py Benchmarks/results/voxel-local
```

The executable accepts `CASE COUNT RESOLUTION EDITS none|mesh|dynamic cpu|render|hq WARMUP SAMPLES [PROFILE_PATH [SCREENSHOT_PATH]]`. Run with the engine assets available in the checkout; `TESSERA_ROOT` can override discovery. Linux link paths are relative to the workspace, with no dependency on another checkout.

Cases cover intact maps, same-geometry shared-mesh controls, ray queries, carving bullets, digging, explosion fan-out, edit coalescing, disconnection, debris, and model voxelization. The `batch` case is a benchmark-only prototype that edits densities and rebuilds once; it is not a shipping engine queue or GPU implementation. Final density FNV hashes and mesh counts are checked against immediate editing.

SAMPLE action/CPU timings exclude repeat-reset and validation work. Full inter-frame FRAME timings include that housekeeping, rendering and presentation. They are not whole-game FPS predictions. Every accepted edit must succeed and remove positive solid samples; digging must open collision to a ray; split fragments must have matching grid layout. Known coarse-grid and nondefault fragment-layout failures are retained as rejected cases. Higher-than-default actual fragmentation is not attempted because of the existing array-sizing issue documented in the report.

Raw sample logs, build/hardware metadata and the tested SHA accompany each report. All benchmark processes run sequentially. Render tests need an interactive Linux Vulkan desktop; this is not a headless CI rendering claim.
