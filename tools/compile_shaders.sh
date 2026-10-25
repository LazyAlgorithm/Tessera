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
	local name="$1" type="$2" target profile platform targets="spirv glsl essl webgl metal"
	# WebGL 2 has no compute shaders: the web build skins on the CPU.
	[ "$type" = compute ] && targets="spirv glsl essl metal"
	for target in $targets; do
		case "$target" in
			spirv) profile=spirv; platform=linux ;;
			glsl) profile=430; platform=linux ;;
			essl) profile=310_es; platform=android ;;
			# WebGL 2 is OpenGL ES 3.0: the web build's shaders.
			webgl) profile=300_es; platform=asm.js ;;
			metal) profile=metal; platform=osx ;;
		esac
		mkdir -p "$out/$target"
		if ! "$shaderc" -f "$src/$name.sc" -o "$out/$target/$name.bin" --type "$type" \
			--platform "$platform" -p "$profile" -i "$include" -i "$src/include" --varyingdef "$src/varying.def.sc" -O 3; then
			echo "FAILED: $name ($target)" >&2
			status=1
		fi
	done
}

for file in "$src"/vs_*.sc; do compile "$(basename "$file" .sc)" vertex; done
for file in "$src"/fs_*.sc; do compile "$(basename "$file" .sc)" fragment; done
# Built-in compute shaders (cs_template.sc is the frame for .tcompute files, filled in when one is compiled).
for file in "$src"/cs_*.sc; do
	[ "$(basename "$file")" = cs_template.sc ] || compile "$(basename "$file" .sc)" compute
done
exit $status
