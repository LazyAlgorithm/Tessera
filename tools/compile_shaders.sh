#!/usr/bin/env bash
# Compatibility wrapper; the Python implementation also runs on Windows.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
exec "${PYTHON:-python3}" "$root/tools/compile_shaders.py" "$@"
