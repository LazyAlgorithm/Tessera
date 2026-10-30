# Reproducible engine benchmarks

- [Voxel shooter/destruction results, 2026-10-30](results/voxel-62f33b0-20261030/REPORT.md): clean Release build of engine commit `62f33b0e3b97667946e3741903652095f1ecc6e4` on Ryzen 9 7900X / RTX 3070. Covers intact maps, bullet carving, digging, explosion fan-out, a benchmark-only coalescing prototype, fragments, debris and model voxelization. Includes raw samples, hardware/build metadata and validation failures.
- [Voxel harness and reproduction instructions](voxel/README.md).

These are workload measurements, not whole-game frame-rate guarantees. Engine source stays unchanged; experimental benchmark-only paths are labelled explicitly.
