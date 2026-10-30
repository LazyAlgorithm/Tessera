# Tessera benchmark results

## Latest commit-verified run

- [Voxel shooter and destruction suite — 2026-10-30](results/voxel-62f33b0-20261030/REPORT.md): tested engine commit `62f33b0e3b97667946e3741903652095f1ecc6e4`, fresh Release build, 254 processes. Includes raw samples, plots, source/build hashes and known validation failures.
- [Portable voxel benchmark harness](voxel/README.md).

## Earlier results

- [Full historical archive and raw-data downloads](history/README.md).
- [Final full-engine versus saved Unity comparison](history/full-engine/final-comparison-20261028-202825/REPORT.md): physics, rendering, navigation, skinning, animation, audio and assets.
- [Ropes and all softbody types](history/softbody/results-20261029-094437/REPORT.md): cloth, jelly, both shell dent modes, convex shells, free/loaded/wrapped ropes, solver density and stability checks.
- [Jolt, Box3D, Rapier and Bullet comparison](history/physics-comparison/REPORT.md): standalone common-C-ABI benchmark; not Tessera runtime measurements.
- [Navigation, NavMesh, batching, tiled updates and optimization history](history/README.md#navigation-and-optimization-history).
- [Earlier voxel/destruction run](history/voxel/results-20261029-191142/REPORT.md).

Historical runs are dated local snapshots, not new measurements of the current commit. Raw samples, profiler captures, original failure/superseded records and available source provenance are retained in checksummed archives. The archive index explains omitted build/runtime binaries and which source snapshots were captured.

These are workload measurements, not whole-game frame-rate guarantees or a universal engine ranking. No engine implementation changes are part of this results publication.
