> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Latest desktop performance comparison

Release Linux standalone runs, recording disabled. Five fresh processes per navigation case/mode and five interleaved generic/analytic processes per overlap case. Each process performs 120 warmup batches and 300 recorded batches. Values are medians of process medians. Query samples contain 1,000 overlaps; navigation N is paths per batch. Unity remains the frozen historical baseline.

| Workload | N | Latest Tessera ms | Saved Unity ms | Tessera / Unity |
|---|---:|---:|---:|---:|
| ai-nav-path | 100 | 0.643870 | 0.1075 | 5.99× |
| physics-overlap-sphere | 1000 | 1.106695 | 0.4195 | 2.64× |
| physics-overlap-capsule | 1000 | 0.522437 | 0.2882 | 1.81× |
| physics-overlap-box | 1000 | 0.218631 | 0.2647 | 0.83× |

Above 1 means Tessera took longer; below 1 means less time. Detailed overlap contacts and Unity collider-list queries differ; grid/quadtree navigation and Unity polygon NavMesh differ. These are workload-specific comparisons, not equal-quality engine rankings. No Unity project was rebuilt or executed.

## Navigation changes and CPU scaling

| Paths | Previous serial ms | Latest serial ms | CPU worker batch ms | Batch speedup over latest serial |
|---|---:|---:|---:|---:|
| 1 | 0.010104 | 0.006492 | 0.006462 | 1.00× |
| 100 | 0.995586 | 0.643870 | 0.079249 | 8.12× |
| 1000 | — | 6.445674 | 0.638470 | 10.10× |

The serial 100-path workload is 35.3% faster than the start of this pass. The batch case uses the existing FindPaths API and 16 CPU job threads. Every path is still searched and smoothed; checksums, final waypoint counts and path lengths match serial mode across all five repeats. There is no saved Unity parallel-job comparison, so the batch result is not assigned a cross-engine ratio.

The changes cache cardinal portal endpoints and neighbour IDs when chunks rebuild, reuse per-search corridor scratch, and use verified flat quadtree leaves to certify whole line-check intervals. Leaf bounds exclude the outer half-cell on each side; detailed cell/link/height checks resume at boundaries. Uneven leaves and stale metadata fall back to cell traversal. A geometric crossing guess narrows the exact existing convex run search; it does not approximate the selected crossing. Height-only changes and origin/cell-size changes now invalidate the affected cached geometry.

The funnel geometry and returned path representation are retained. The profiler now records about 0.198 ms in smoothing (including 0.165 ms in LineClear) per 100 paths, versus the prior 0.539/0.506 ms. Search is now the largest contributor, around 0.490 ms including 0.076 ms corridor construction. These profiled times include recording overhead and are separate from the production timings above.

Built-in behavior-tree movement tasks previously read status immediately after requesting a path, forcing individual queued searches to run synchronously. A new PathPending property lets those tasks remain Running until Scene.Update completes its existing worker batch. Explicit Path/PathFailed/HasArrived reads retain their synchronous behavior. Existing custom movement drivers default to no pending work. The throughput benchmark measures FindPaths directly, not a full crowd simulation or behavior-tree frame.

## Box overlap optimization

| Query | Generic ms | Analytic ms | Time reduction |
|---|---:|---:|---:|
| physics-overlap-sphere | 6.474934 | 1.106695 | 82.9% |
| physics-overlap-capsule | 2.602041 | 0.522437 | 79.9% |
| physics-overlap-box | 1.317967 | 0.218631 | 83.4% |

The new box path handles aligned boxes whose flat face patches overlap. It calculates a surface contact, normal and exact aligned penetration directly, and conservatively rejects separated pairs. Oblique, near-tangent and rounded-edge/corner cases retain the registered solver. Simulation contacts use the original solver. The exact geometric depth can differ from approximate GJK/EPA depth; tests use an independent aligned-box depth calculation for supported flat contacts, rather than requiring agreement with an approximate solver. One shallow probe has geometric penetration 0.100 versus a generic estimate of about 0.067.

The diagnostic capture before this change shows 1,000 EPA calls per batch taking about 0.956 ms. Final recording-off performance does not include native diagnostic scopes. Physics pile/discrete controls changed by under 1% in the three-process checks (pile 0.4170 to 0.4203 ms; discrete 0.1898 to 0.1910 ms), consistent with run variation rather than a demonstrated material regression. These controls are not exhaustive simulation profiling.

## GPU assessment

No GPU navigation implementation was benchmarked. GPU batching, persistent navigation data, flow fields and crowd steering remain potential experiments for larger workloads. For the current maze, the measured CPU worker batch already handles 1,000 paths in about 0.64 ms. A GPU version must beat end-to-end CPU submission, GPU execution, synchronization and result-transfer costs, and compete with rendering for GPU resources. There is no measured crossover threshold or promised GPU speedup.

- Primary background: [NVIDIA: tree traversal and execution divergence](https://developer.nvidia.com/blog/thinking-parallel-part-ii-tree-traversal-gpu/), [NVIDIA: batching and data-transfer overhead](https://developer.nvidia.com/blog/how-optimize-data-transfers-cuda-cc/). These explain general constraints, not Tessera GPU performance.

## Validation and artifacts

ShapeQueries, Navigation, Layers, Profiler, BehaviorTree, CharacterController and Joints all pass. Tests cover portal/leaf invalidation, height-only changes, relocated/rescaled grids, dense-reference rays, serial/batched path equality, links, costs and deferred movement-task status reads. Box tests cover independent geometric depth, valid surface points, rotated aligned targets, reversed axes, oblique fallback, masks and ignored bodies. The desktop launcher/editor workspace also builds successfully (Debug Linux); no application was launched and no changes were pushed.

Source and binary hashes, final source snapshots, raw samples and process logs are retained. Native convex diagnostics are OFF in production builds. Static flat-box and static maze results do not establish equivalent gains on arbitrary terrain, moving obstacles, oblique shape mixes, rendering, audio or full crowds. Earlier report sections on the Desktop remain historical.

- [Navigation before](../results/20261028-093231-738500/report.md), [final serial/batched runs](../results/20261028-095838-224079/report.md), [final profiler capture](../../archives/full-engine-03.tar.gz).
- [Physics contact summary](../../archives/full-engine-02.tar.gz), [interleaved manifest](../../archives/full-engine-02.tar.gz), [pre-optimization box capture](../../archives/full-engine-02.tar.gz), [final box capture](../../archives/full-engine-01.tar.gz).
- [Regression results](../../archives/full-engine-02.tar.gz), [desktop build](../../archives/full-engine-02.tar.gz).
