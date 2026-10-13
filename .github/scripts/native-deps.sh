#!/usr/bin/env bash
# The engine's third-party native libraries (bgfx, SDL, Jolt, ENet, Opus...) only change when third_party/ or the
# native CMake setup does, so CI keeps their build folder in the Actions cache instead of compiling them every run.
#
#   native-deps.sh key <linux|windows|web>   prints the cache key: the git hashes of what the libraries are built from
#   native-deps.sh settle                    after restoring the cache, makes the checked-out third-party sources older
#                                            than the cached objects, so Ninja rebuilds only the engine's own native code
#
# Run from the folder that holds the Tessera checkout's root (pass it as TESSERA, default ./tessera).
set -euo pipefail
tessera="${TESSERA:-tessera}"
case "${1:-}" in
key)
	platform="${2:?platform}"
	parts="$(git -C "$tessera" rev-parse HEAD:third_party HEAD:native/CMakeLists.txt HEAD:tools/patch_textedit.py | cut -c1-12 | tr '\n' '-')"
	echo "native-$platform-v1-${parts%-}"
	;;
settle)
	# A fresh checkout gives every file the current time, which Ninja would take as "changed".
	old='2001-01-01 00:00:00'
	find "$tessera/third_party" -type f -print0 | xargs -0 touch -d "$old"
	touch -d "$old" "$tessera/native/CMakeLists.txt"
	;;
*)
	sed -n 2,9p "$0" | sed 's/^# \?//'
	exit 1
	;;
esac
