# Desktop water and engine networking validation

See [REPORT.md](REPORT.md) for measured limits and transport coverage. Source engine revision: `6cfa1faa568940e629b71d9999605319d55bc037`.

The benchmark projects link this checkout's Release native archives. Build the native engine and current shaders first using the repository's build instructions; `shaderc` must be available. BeefBuild and the system native libraries are required. Render benchmarks need an actual GPU/display.

```
python3 Benchmarks/water-network/prepare_fixture_paths.py
python3 tools/run_tests.py
python3 Benchmarks/water-network/run_checks.py results/functional
BeefBuild -workspace=Benchmarks/water-network/features -config=Release -run
BeefBuild -workspace=Benchmarks/water-network/water -config=Release
BeefBuild -workspace=Benchmarks/water-network/network -config=Release
python3 Benchmarks/water-network/run_water.py results/water
python3 Benchmarks/water-network/run_water.py results/shell --shell-only
python3 Benchmarks/water-network/run_water.py results/spot --spot-only
python3 Benchmarks/water-network/run_network.py results/network
python3 Benchmarks/water-network/run_network.py results/network-after-fix --after-fix
```

Run performance workloads sequentially. The fixture path adapter modifies legacy absolute library paths in test project files; use an isolated checkout. It does not modify engine implementation. Harness launchers set `TESSERA_ROOT` for nested executable asset lookup.

Water: three fresh processes per normal workload, 120 warmup + 300 sampled steps each; separate 10,000-frame traversal, surface-query and profiler runs. `--render-only` runs only rendered cases; the offscreen scene target is explicitly checked at the requested size, independent of window-manager size restrictions. CPU tests include physics and normal component mesh updates but no GPU rendering. Low and realistic looks share the same wave-height override; ocean comparisons intentionally hold mesh spacing constant to isolate the visual effects.

Network: independent processes, real-time 60 Hz simulation, 1–31 remote clients, clean and impaired UDP, 0–1,024 props. Each scenario has about 10 seconds of active measurement plus initialization/final convergence. Outputs distinguish application, transport-offered and actual ENet UDP payload totals. Synthetic final truth packets are outside measured traffic windows. See [COVERAGE.md](COVERAGE.md) for exact subsystem evidence and exclusions.

`default` retains engine defaults; `exact` enables batched full body records; `body` switches remote records to QuantizedBody; `optimized` also uses 10 Hz remote snapshots, disables remote physics prediction, and enables ENet lossless compression. `framed` uses the transport-independent compression path over UDP. `budget` limits snapshot application payload to 64,000 bytes/s/client; this is not a cap on total wire traffic. `mixed` adds repeated reliable light enabled/intensity/color changes to the optimized profile.

Full CPU runner saves fixture summaries; the focused functional runner saves full logs. Feature workflow deltas include other concurrent session traffic and are not isolated costs per action. Raw logs are retained even for exploratory or superseded runs; report selection rules identify which measurements count.
