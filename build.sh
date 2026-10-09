#!/usr/bin/env bash
# Builds everything needed to run Tessera on Linux:
#   1. native dependencies (bgfx, SDL3, Jolt, ENet, miniaudio, Opus, Dear ImGui) into build/native
#   2. shaders for every backend this machine's shaderc can target
#   3. the launcher
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
beef="${BEEFBUILD:-BeefBuild}"

python3 "$root/tools/patch_textedit.py"
cmake -S "$root/native" -B "$root/build/native" -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build "$root/build/native" -j "$(nproc)"
"$root/tools/compile_shaders.sh"
python3 "$root/tools/make_licenses.py"
# Beef does not notice changed native archives, so force the launcher to relink.
rm -f "$root/build/Debug_Linux64/TesseraLauncher/TesseraLauncher"
"$beef" -workspace="$root" -config=Debug -verbosity=minimal
echo "Done. Start the launcher with: $root/tessera"
