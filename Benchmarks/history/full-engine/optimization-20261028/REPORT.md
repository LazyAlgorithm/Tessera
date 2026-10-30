> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Desktop optimization — 28 October 2026

Walking navigation now uses adaptive quadtree subdivision with cached exit runs. Physics overlaps stream full contacts directly from Jolt rather than collecting a temporary all-hit array. Existing contact detail, layer masks, ignored bodies and debris filtering are retained.

Release Linux desktop runs; median of process medians, milliseconds. Before: three fresh processes; after: five. Each process warms up for 120 iterations and records 300 samples. Physics samples contain 1,000 queries; navigation samples contain N requests. Positive reduction means less time. No cached paths or benchmark-only fast paths were added.

| Workload | N | Before ms | After ms | Reduction | Saved Unity ms | After / Unity |
|---|---:|---:|---:|---:|---:|---:|
| physics-overlap-sphere | 1000 | 6.730880 | 6.483921 | 3.7% | 0.4195 | 15.46× |
| ai-nav-path | 100 | 1.213205 | 1.134192 | 6.5% | 0.1075 | 10.55× |
| physics-overlap-capsule | 1000 | 2.695416 | 2.597201 | 3.6% | 0.2882 | 9.01× |
| physics-overlap-box | 1000 | 1.348259 | 1.304416 | 3.3% | 0.2647 | 4.93× |
| ai-nav-path | 1 | 0.012233 | 0.011391 | 6.9% | 0.0015 | 7.59× |

The largest measured gaps remain sphere overlaps, navigation and capsule overlaps. The small overlap gains do not close these gaps. Sphere contact generation remains effectively unchanged. Saved Unity timings are historical context: Unity was neither rebuilt nor rerun. Tessera overlaps return detailed contacts while Unity collected colliders; Tessera grid navigation and Unity polygon NavMesh have different representations. Ratios are workload-specific, not equal-feature engine rankings.

Quadtree details: each chunk recursively splits along adaptive X/Z planes into up to four child regions. Uniform regions are flattened into search leaves. Split planes follow cell-state boundaries; a midpoint fallback after 16 adaptive levels bounds recursion. Flying navigation keeps volume boxes. Fixed square splits were tested and rejected after slowing this maze from ~1.21 ms to ~4.34 ms per 100 requests; adaptive splits avoid that fragmentation. Leaf merging experiments failed the existing path-length criterion and were removed. Exit runs refresh after all changed chunks rebuild. Searches also avoid linear touched-node deduplication.

Validation: Navigation, ShapeQueries and Layers passed, including new partial-chunk and one-cell-wide grid cases, cost-overlay changes and restoration. Existing tests cover ledges, maze path lengths, obstacles, links, batched searches, flight and visit budgets. Release benchmark builds succeeded. Final timed runs reported zero failures. This pass does not measure desktop rendering, audio or other engine areas again.

Raw data and provenance:
- [Navigation before](../results/20261028-074911-208749/report.md), [after](../results/20261028-075808-392164/report.md).
- [Physics before](../results/20261028-075021-111695/report.md), [after](../results/20261028-075811-227522/report.md).
- [Final tests](../../archives/full-engine-04.tar.gz), [navigation build](../../archives/full-engine-04.tar.gz), [physics build](../../archives/full-engine-04.tar.gz).
- Changed-source snapshots are in `source/`, hashes in `source-sha256.json`; benchmark runners record binary hashes, settings, checks and samples.
- Earlier exploratory runs remain in results/20261028-* and are excluded from the final after column. Some preliminary before measurements overlapped briefly with builds; these small percentage gains should be treated as local observations, not a machine-controlled performance guarantee.
