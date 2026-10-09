#!/usr/bin/env bash
# Compiles Engine/shaders/*.sc for every backend this host's shaderc can target.
# Direct3D bytecode needs the Windows shader compiler, so run this on Windows to add dx11.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
shaderc="${SHADERC:-$root/build/native/bgfx/cmake/bgfx/shaderc}"
src="$root/Engine/shaders"
out="$root/Engine/assets/shaders"
include="$root/third_party/bgfx.cmake/bgfx/src"
status=0

compile() { # name type
	local name="$1" type="$2" target profile platform
	for target in spirv glsl essl metal; do
		case "$target" in
			spirv) profile=spirv; platform=linux ;;
			glsl) profile=430; platform=linux ;;
			essl) profile=310_es; platform=android ;;
			metal) profile=metal; platform=osx ;;
		esac
		mkdir -p "$out/$target"
		if ! "$shaderc" -f "$src/$name.sc" -o "$out/$target/$name.bin" --type "$type" \
			--platform "$platform" -p "$profile" -i "$include" --varyingdef "$src/varying.def.sc" -O 3; then
			echo "FAILED: $name ($target)" >&2
			status=1
		fi
	done
}

for file in "$src"/vs_*.sc; do compile "$(basename "$file" .sc)" vertex; done
for file in "$src"/fs_*.sc; do compile "$(basename "$file" .sc)" fragment; done
exit $status
