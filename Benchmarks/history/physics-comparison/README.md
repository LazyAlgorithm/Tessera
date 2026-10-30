> Historical standalone backend benchmark; no Tessera runtime. Full source/data bundle: [physics-engine-results.zip](physics-engine-results.zip).

# Standalone Beef physics benchmark

Open `REPORT.md` for results and `METHODOLOGY.md` for exact settings and limitations.

The final matrix contains 396 trials (366 valid, 30 invalid mesh trials), 800 measured query batches (16 million queries), 24 paired Beef/native-loop controls, five no-op controls, and eight final-state diagnostic captures. Invalid trials are retained, not ranked. No Tessera runtime or source is used.

## Re-running on this workstation

Run `./rerun.sh`. It builds both native profiles, builds the Beef driver, validates motion/ABI, runs the matrix, collects final states and generates the report. It takes several minutes. Benchmarks must run sequentially, without compilation or other benchmark programs running concurrently.

## Reproducing elsewhere

1. Clone each upstream engine into `vendor/jolt`, `vendor/box3d`, `vendor/rapier`, `vendor/bullet` and check out the full commit recorded in `results/metadata.json`.
2. Install a Beef compiler, CMake, GCC, Python with matplotlib, and Rust. The build script expects the local Rust installation under `toolchain/cargo` / `toolchain/rustup`. To create that isolated installation, run the supplied rustup installer with `CARGO_HOME="$PWD/toolchain/cargo" RUSTUP_HOME="$PWD/toolchain/rustup" sh rustup-init.sh -y --profile minimal --no-modify-path`.
3. Adjust the BeefBuild path in `rerun.sh` / `capture_quality.py`, and the absolute native link/rpath directory in `driver/BeefProj.toml`, if the extraction path differs.
4. Run `./rerun.sh` and compare settings, output, and CPU topology. The CPU affinity masks assume Linux and four physical cores at CPUs 0–3; adjust them for the target hardware.

`correct_ccd_threshold.py` and `optimize_bullet_queries.py` document corrections made during the original measurement session. The final source already includes those corrections; ordinary reproduction uses `rerun.sh`, not those one-time correction scripts. Superseded controls are retained as audit artifacts and excluded from the final tables.

The archive omits engine checkouts, compiled binaries, and the installed toolchain; exact source revisions and build metadata are included.
