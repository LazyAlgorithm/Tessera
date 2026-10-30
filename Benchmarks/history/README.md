# Historical benchmark archive

These are the earlier results from this session, preserved with their original raw data and available provenance. **They were not rerun on the latest Tessera commit.** The commit-verified voxel run remains in [the main benchmark index](../README.md).

## Main reports

- [Final full-engine versus saved Unity comparison](full-engine/final-comparison-20261028-202825/REPORT.md) — physics, rendering, navigation, skinning, animation, audio and assets.
- [Ropes and all softbody types](softbody/results-20261029-094437/REPORT.md) — 829 primary timing processes plus 69 geometry/variant checks; includes rejected unstable configurations.
- [Standalone Jolt / Box3D / Rapier / Bullet comparison](physics-comparison/REPORT.md) — separate C ABI harness, not Tessera runtime timings.
- [Earlier voxel/destruction run](voxel/results-20261029-191142/REPORT.md).

## Navigation and optimization history

- [box-overlap-20261028d](full-engine/box-overlap-20261028d/REPORT.md)
- [navigation-20261028c](full-engine/navigation-20261028c/REPORT.md)
- [navigation-20261028e](full-engine/navigation-20261028e/REPORT.md)
- [navmesh-20261028](full-engine/navmesh-20261028/REPORT.md)
- [navmesh-default-20261028](full-engine/navmesh-default-20261028/REPORT.md)
- [optimization-20261028](full-engine/optimization-20261028/REPORT.md)
- [optimization-20261028b](full-engine/optimization-20261028b/REPORT.md)
- [profiling-20261028](full-engine/profiling-20261028/REPORT.md)

## Earlier full-engine reports

- [Original engine/Unity comparison](full-engine/COMPARISON.md).
- [Confirmation](full-engine/CONFIRMATION.md), [test status](full-engine/TEST_STATUS.md), [work log](full-engine/WORK_LOG.md).
- [All dated raw-run reports](full-engine/results/) — intermediate, failed and superseded results are retained with their status; they are not all current recommendations.

## Downloadable raw data

7,856 historical artifact files, 382.2 MiB before compression. The [inventory](inventory.json) records every file path, SHA-256, size and containing archive.

- [archives/full-engine-01.tar.gz](archives/full-engine-01.tar.gz) — 1.30 MiB; 28 files.
- [archives/full-engine-02.tar.gz](archives/full-engine-02.tar.gz) — 2.97 MiB; 395 files.
- [archives/full-engine-03.tar.gz](archives/full-engine-03.tar.gz) — 3.20 MiB; 94 files.
- [archives/full-engine-04.tar.gz](archives/full-engine-04.tar.gz) — 2.64 MiB; 171 files.
- [archives/full-engine-05.tar.gz](archives/full-engine-05.tar.gz) — 2.95 MiB; 88 files.
- [archives/full-engine-06.tar.gz](archives/full-engine-06.tar.gz) — 1.36 MiB; 3 files.
- [archives/full-engine-07.tar.gz](archives/full-engine-07.tar.gz) — 6.32 MiB; 1 files.
- [archives/full-engine-08.tar.gz](archives/full-engine-08.tar.gz) — 2.35 MiB; 64 files.
- [archives/full-engine-09.tar.gz](archives/full-engine-09.tar.gz) — 2.62 MiB; 6 files.
- [archives/full-engine-10.tar.gz](archives/full-engine-10.tar.gz) — 2.65 MiB; 9 files.
- [archives/full-engine-11.tar.gz](archives/full-engine-11.tar.gz) — 2.71 MiB; 9 files.
- [archives/full-engine-12.tar.gz](archives/full-engine-12.tar.gz) — 2.90 MiB; 6 files.
- [archives/full-engine-13.tar.gz](archives/full-engine-13.tar.gz) — 2.77 MiB; 13 files.
- [archives/full-engine-14.tar.gz](archives/full-engine-14.tar.gz) — 2.64 MiB; 9 files.
- [archives/full-engine-15.tar.gz](archives/full-engine-15.tar.gz) — 2.74 MiB; 6 files.
- [archives/full-engine-16.tar.gz](archives/full-engine-16.tar.gz) — 2.81 MiB; 9 files.
- [archives/full-engine-17.tar.gz](archives/full-engine-17.tar.gz) — 3.27 MiB; 52 files.
- [archives/full-engine-18.tar.gz](archives/full-engine-18.tar.gz) — 1.57 MiB; 683 files.
- [archives/full-engine-19.tar.gz](archives/full-engine-19.tar.gz) — 2.56 MiB; 1237 files.
- [archives/full-engine-20.tar.gz](archives/full-engine-20.tar.gz) — 1.63 MiB; 1174 files.
- [archives/full-engine-21.tar.gz](archives/full-engine-21.tar.gz) — 2.05 MiB; 880 files.
- [archives/full-engine-22.tar.gz](archives/full-engine-22.tar.gz) — 1.39 MiB; 656 files.
- [archives/full-engine-23.tar.gz](archives/full-engine-23.tar.gz) — 1.24 MiB; 572 files.
- [archives/softbody-01.tar.gz](archives/softbody-01.tar.gz) — 3.80 MiB; 629 files.
- [archives/softbody-02.tar.gz](archives/softbody-02.tar.gz) — 3.71 MiB; 431 files.
- [archives/softbody-03.tar.gz](archives/softbody-03.tar.gz) — 0.51 MiB; 132 files.
- [archives/voxel-01.tar.gz](archives/voxel-01.tar.gz) — 2.02 MiB; 499 files.
- [physics-comparison/physics-engine-results.zip](physics-comparison/physics-engine-results.zip) — 2.09 MiB; 38 files.

## Artifact policy

Extract all `.tar.gz` files into this directory to restore the original `full-engine/`, `softbody/` and `voxel/` result layout. Raw originals are byte-preserved; directly browsable Markdown copies have local filesystem links rewritten for GitHub and include a historical banner. The standalone physics ZIP is preserved exactly.

Included: raw sample/check CSVs, summary tables, original failure/exclusion metadata, profiler captures/reports, build/run logs, graphics, benchmark scripts and captured source snapshots for the major runs where available.

Omitted: executable players, shared/static libraries, object files, generated build caches, vendor dependencies/assets, and duplicate intermediate source copies. Original local paths may remain in raw provenance metadata. An old local source hash is not proof of a Git commit; only the separately labelled commit-verified run has that claim.

The data includes failed, superseded and exploratory runs deliberately. Use the main reports and their comparability warnings before drawing conclusions.
