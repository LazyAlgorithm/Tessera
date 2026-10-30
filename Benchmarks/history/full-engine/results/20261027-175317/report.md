> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Standalone engine benchmark results

Milliseconds; lower is better. Median of per-run medians. Query timings are per batch of 1,000 queries. Whole-frame intervals include CPU/GPU synchronization and pacing; they are not GPU timestamps.

| Workload | Population | Tessera ms | Unity ms | Unity / Tessera |
|---|---:|---:|---:|---:|
| model-inset | 1 | 0.0197 | incomplete | — |
| model-inset | 10 | 0.1893 | incomplete | — |
| model-primitives | 1 | 0.0044 | incomplete | — |
| model-primitives | 10 | 0.3381 | incomplete | — |
| model-decimate | 1 | 0.0806 | incomplete | — |
| model-decimate | 10 | 0.7784 | incomplete | — |
| model-uv | 1 | 0.0047 | incomplete | — |
| model-uv | 10 | 0.0470 | incomplete | — |
| model-triangulate | 1 | 0.0079 | incomplete | — |
| model-triangulate | 10 | 0.0646 | incomplete | — |
| audio-hrtf | 1 | 0.1450 | incomplete | — |
| audio-hrtf | 10 | 1.2064 | incomplete | — |
| voxel-rebuild | 1 | 0.5447 | incomplete | — |
| voxel-rebuild | 10 | 5.4080 | incomplete | — |
| voxel-carve | 1 | 0.6385 | incomplete | — |
| voxel-carve | 10 | 6.3557 | incomplete | — |
| terrain-noise | 1 | 0.0994 | incomplete | — |
| terrain-noise | 10 | 1.7391 | incomplete | — |
| asset-model-load | 1 | 1.2360 | incomplete | — |
| asset-model-load | 10 | 12.4073 | incomplete | — |
| asset-pack-read | 1 | 0.1099 | incomplete | — |
| asset-pack-read | 10 | 1.0960 | incomplete | — |
| network-compress | 1 | 0.7795 | incomplete | — |
| network-compress | 10 | 7.8018 | incomplete | — |
| network-loopback | 1 | 0.0083 | incomplete | — |
| network-loopback | 10 | 0.0100 | incomplete | — |
| voice-encode | 1 | 0.1327 | incomplete | — |
| voice-encode | 10 | 1.2601 | incomplete | — |
| voice-decode | 1 | 0.0086 | incomplete | — |
| voice-decode | 10 | 0.0824 | incomplete | — |
| baking-uv | 1 | 0.0865 | incomplete | — |
| baking-uv | 10 | 0.8409 | incomplete | — |
| baking-lightmap | 1 | 4.0709 | incomplete | — |
| baking-lightmap | 10 | 4.4723 | incomplete | — |
| rig-autoweights | 1 | 22.9156 | incomplete | — |
| rig-autoweights | 10 | 228.9713 | incomplete | — |
| rig-weight-brush | 1 | 0.0508 | incomplete | — |
| rig-weight-brush | 10 | 0.4454 | incomplete | — |
| rig-pose | 1 | 0.3490 | incomplete | — |
| rig-pose | 10 | 3.4669 | incomplete | — |
| texture-paint | 1 | 0.5113 | incomplete | — |
| texture-paint | 10 | 5.1309 | incomplete | — |
| texture-mips-color | 1 | 0.9230 | incomplete | — |
| texture-mips-color | 10 | 9.1749 | incomplete | — |
| texture-mips-normal | 1 | 1.5980 | incomplete | — |
| texture-mips-normal | 10 | 16.0303 | incomplete | — |
| terrain-mesh | 1 | 1.3925 | incomplete | — |
| terrain-mesh | 10 | 2.7111 | incomplete | — |

Read ../../README.md for scope and interpretation. Rendering uses different native pipelines and is not an equal-image-quality ranking. Scene-empty/scripts are native traversal versus explicit C# calls and are not ranked. CCD and character results require behavior checks.

## Failures

[]
