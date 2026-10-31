#!/usr/bin/env bash
# Build native libraries, shaders and the launcher; Python 3.11+ and BeefBuild are required.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "${PYTHON:-python3}" "$root/tools/build.py" "$@"
