> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Voxel shooter benchmark

Build `BeefBuild -workspace=Benchmarks/voxel -config=Release`. Run the benchmark executable with `CASE COUNT RESOLUTION EDITS none|mesh|dynamic cpu|render|hq WARMUP SAMPLES [PROFILE_PATH [SCREENSHOT_PATH]]`.

The saved results use a frozen Engine/native archive snapshot with absolute project paths. `run.py RESULTS_DIRECTORY` builds the measurement matrix after that snapshot has been built; `report.py` and `plot.py` regenerate the standalone report and charts. Commands, per-sample logs, source/binary hashes, expected validation rejections and equivalence checks are archived with the result.

Cases include intact maps, shared-mesh controls, ray queries, carving bullets, wall digging, explosion fan-out, splitting, ongoing debris, and model voxelization. The `batch` case is a benchmark-only density-edit coalescing prototype; no engine queue or GPU compute implementation is introduced. Its final density hashes and mesh counts must match the immediate `burst` case.

SAMPLE action/CPU timings exclude repeat-reset and validation work. Inter-frame FRAME timings include that housekeeping plus normal rendering. Report them separately. Edits must succeed and remove solid samples; digging must open a collider hole; splitting must create fragments with the correct grid layout. At nondefault resolutions the existing fragment allocation bug must be fixed before using fragmentation; higher-than-default fragment cases are not executed because the source copies into default-sized arrays.
