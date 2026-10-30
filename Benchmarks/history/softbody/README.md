> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Rope and soft-body capacity benchmark

`src/Program.bf` exercises the public Rope and SoftBody components in a real Scene. Cases: cloth, cloth-contact, jelly, jelly-ball, jelly-contact, shell-impacts, shell-surface, shell-convex, rope, rope-load, rope-wrap. Mesh generation follows the existing SoftBodies test fixture. No engine implementation changes are required.

Build `BeefBuild -workspace=Benchmarks/softbody -config=Release`, then run `build/Release_Linux64/Benchmark/Benchmark CASE COUNT RESOLUTION ITERATIONS active|rest cpu|render WARMUP SAMPLES [PROFILE_PATH [SCREENSHOT_PATH]]` from this folder. Use an empty profile path when capturing a screenshot. `cpu` includes Scene.FixedUpdate and Scene.Update (including LateUpdate); `render` also opens the real renderer. Every rendered frame advances one fixed 60 Hz physics tick, intentionally conservative at high render rates. The CPU drive, physics and mesh/update phases are emitted separately.

For reproducible comparisons, copy Engine, the native archive and benchmark project into a snapshot and adjust its project paths before building. The October 29 results directory contains that snapshot, hashes, all commands, sample logs, checks and sampling settings. `run.py` is the original broad sweep; `resume.py` retains completed checkpoint groups and uses shorter exploratory CPU runs plus repeated rendered confirmations. `extra.py` probes dense cloth and refines practical rendered boundaries. `report.py` and `plot.py` regenerate the report and standalone plots.

An accepted run must have complete finite timings, finite final geometry, nonzero renderer draws, and no solver-capacity error. A process returning zero is not sufficient. Invalid configurations are reported as stability failures and never ranked by timing. Shell dent depths, contact counts, vertices, setup time and process RSS are retained. Separate profiler recordings are excluded from capacity statistics.

The useful budget is a few milliseconds, leaving time for the rest of a game. Counts under an entire 16.67 ms simple-scene frame are stress ceilings, not gameplay recommendations. Run representative game content and hardware before setting shipping limits.
