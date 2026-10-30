> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Saved Unity workload audit

Unity was not executed. Exact scenario/population/resolution/fullscreen/warmup/sample settings were checked for every paired row. The saved inputs and original hashes where available are frozen in unity-baselines.json.

- Navigation: archived 20261027-172744 FeatureWorkloads.cs is byte-identical to the current Unity helper. Maze, endpoint schedule, agent settings, bake and serial path operations are retained. Mesh representations and clearance outputs still differ between engines. No parallel Unity reference exists.
- The archived EngineBenchmark.cs versus current source diff is preserved in unity-harness-evolution.patch. New dispatch branches add separate workloads; existing core physics, query, scene and nonsphere rendering branches retain their operations. The timed feature metric label changed without changing measured operations.
- **Sphere rendering is excluded from ranked comparisons.** SphereMesh triangle winding and normal generation changed after the original saved baseline. Its saved milliseconds in the inventory are historical references only.
- The earliest core dataset recorded source hashes but did not retain the matching source text or binary digest. The preserved original standalone Assembly-CSharp.dll was inspected using local Mono.Cecil; its EngineBenchmark methods are saved in unity-original-il.txt. Core query/simulation operations and instancing are consistent with the archived source branches. This is supplementary inspection, not proof of original binary identity: the earliest recorded source hash cannot be reconstructed from the available archives.
- Whole-file hashes differ as new unrelated workloads were added. definition-checks.json reports those differences honestly; it is not an automatic workload equivalence certificate. Rendering quality, character motor semantics, empty/script scene behavior, and contact-versus-collider overlap output remain the limitations stated in REPORT.md.

This comparison reuses saved Unity measurements across sessions. It does not establish equal images, equal solver quality, or equal system load.
