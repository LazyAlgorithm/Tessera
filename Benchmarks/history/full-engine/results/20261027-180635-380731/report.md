> Historical result: preserved from a local run; this is not a rerun on commit `62f33b0`. Raw-only links download the containing archive; see the archive inventory for its member path.

# Standalone engine benchmark results

Milliseconds; lower is better. Median of per-run medians. Query timings are per batch of 1,000 queries. Whole-frame intervals include CPU/GPU synchronization and pacing; they are not GPU timestamps.

| Workload | Population | Tessera ms | Unity ms | Unity / Tessera |
|---|---:|---:|---:|---:|
| editor-graph-generate | 10 | 0.0026 | incomplete | — |
| editor-graph-generate | 100 | 0.0293 | incomplete | — |
| editor-graph-validate | 10 | 0.0004 | incomplete | — |
| editor-graph-validate | 100 | 0.0091 | incomplete | — |
| editor-code-index | 10 | incomplete | incomplete | — |
| editor-code-index | 100 | incomplete | incomplete | — |
| editor-code-completion | 10 | 0.0089 | incomplete | — |
| editor-code-completion | 100 | 0.0867 | incomplete | — |
| editor-theme-parse | 10 | 0.3462 | incomplete | — |
| editor-theme-parse | 100 | 3.4785 | incomplete | — |

Read ../../README.md for scope and interpretation. Rendering uses different native pipelines and is not an equal-image-quality ranking. Scene-empty/scripts are native traversal versus explicit C# calls and are not ranked. CCD and character results require behavior checks.

## Failures

[
  {
    "run": "tessera-editor-code-index-10-0",
    "error": "exit 139"
  },
  {
    "run": "tessera-editor-code-index-10-1",
    "error": "exit 139"
  },
  {
    "run": "tessera-editor-code-index-10-2",
    "error": "exit 139"
  },
  {
    "run": "tessera-editor-code-index-100-0",
    "error": "exit 139"
  },
  {
    "run": "tessera-editor-code-index-100-1",
    "error": "exit 139"
  },
  {
    "run": "tessera-editor-code-index-100-2",
    "error": "exit 139"
  }
]
