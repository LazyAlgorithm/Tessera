# Polygon navigation regression fixture

Build the native archive, then run `BeefBuild -workspace=Tests/NavigationMesh -config=Debug -run` from the repository root, or `python3 tools/run_tests.py NavigationMesh`.

The fixture covers maze clearance, line casts from corners, explicit search budgets, endpoint rejection, serial/worker agreement, random reachable points, asset round-trips/truncation, geometry rebuilding, flight fallback, stacked floors, one-way/bidirectional links, link permissions/events, carving, cost/blocked areas and agent arrival.

`native_smoke.cpp` runs the native side on its own under AddressSanitizer and UndefinedBehaviorSanitizer: asset parsing (every truncated prefix too), NaN settings, oversized counts, empty geometry, nearest/path/ray queries and a zero search budget. `python3 Tests/NavigationMesh/sanitize.py` builds it with `clang++` against Recast, Detour and the Jolt archives in `build/native`, and runs it.
