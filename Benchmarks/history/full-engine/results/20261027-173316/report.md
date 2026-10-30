> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Standalone engine benchmark results

Milliseconds; lower is better. Median of per-run medians. Query timings are per batch of 1,000 queries. Whole-frame intervals include CPU/GPU synchronization and pacing; they are not GPU timestamps.

| Workload | Population | Tessera ms | Unity ms | Unity / Tessera |
|---|---:|---:|---:|---:|
| model-cube | 1 | 0.0084 | incomplete | — |
| model-extrude | 1 | 0.0278 | incomplete | — |
| model-subdivide | 1 | 0.0289 | incomplete | — |
| model-inset | 1 | 0.0297 | incomplete | — |
| model-bevel | 1 | 0.0682 | incomplete | — |
| model-weld | 1 | 0.0097 | incomplete | — |
| model-decimate | 1 | 0.1436 | incomplete | — |
| model-uv | 1 | 0.0083 | incomplete | — |
| model-triangulate | 1 | 0.0112 | incomplete | — |
| ui-layout | 1 | 0.0041 | incomplete | — |
| ui-parse | 1 | 0.0025 | incomplete | — |
| audio-mix | 1 | incomplete | incomplete | — |
| audio-hrtf | 1 | incomplete | incomplete | — |
| voxel-rebuild | 1 | 0.7596 | incomplete | — |
| voxel-carve | 1 | 0.9462 | incomplete | — |
| terrain-noise | 1 | 0.3190 | incomplete | — |
| animation-ik | 1 | 0.0013 | incomplete | — |
| asset-model-load | 1 | 3.8614 | incomplete | — |
| asset-image-decode | 1 | 3.5121 | incomplete | — |
| save-binary-encode | 1 | 0.0003 | incomplete | — |
| save-binary-decode | 1 | 0.0004 | incomplete | — |
| save-json-encode | 1 | 0.0002 | incomplete | — |
| save-json-decode | 1 | 0.0004 | incomplete | — |
| graph-blackboard | 1 | 0.0002 | incomplete | — |
| dialogue-condition | 1 | 0.0005 | incomplete | — |
| dialogue-parse | 1 | 0.0010 | incomplete | — |
| sequence-parse | 1 | 0.0018 | incomplete | — |
| sequence-evaluate | 1 | 0.0003 | incomplete | — |
| input-parse | 1 | 0.0010 | incomplete | — |
| baking-uv | 1 | 0.1510 | incomplete | — |
| physics-joints | 1 | 0.0067 | incomplete | — |

Read ../../README.md for scope and interpretation. Rendering uses different native pipelines and is not an equal-image-quality ranking. Scene-empty/scripts are native traversal versus explicit C# calls and are not ranked. CCD and character results require behavior checks.

## Failures

[
  {
    "run": "tessera-audio-mix-1-0",
    "error": "exit 1"
  },
  {
    "run": "tessera-audio-hrtf-1-0",
    "error": "exit 1"
  }
]
