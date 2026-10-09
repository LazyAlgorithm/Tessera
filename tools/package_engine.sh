#!/usr/bin/env bash
# Packs a built copy of Tessera (the launcher and editor) for use on another machine.
#
#   tools/package_engine.sh [output-folder]
#       The whole source tree with the prebuilt Linux libraries, as output-folder/tessera-linux-x64-<date>.tar.gz
#       (default folder: dist). Includes the tests, samples and website.
#
#   tools/package_engine.sh --platform linux|windows --folder <folder>
#       A folder holding only what is needed to run the launcher and editor on that system. It can be moved, or
#       copied to another machine. An earlier package in <folder> is replaced; any other folder is left alone.
#       The editor's File > Build Game window does this (Build: Editor).
#
# Every project compiles its own scripts together with the engine, so the other machine needs the Beef toolchain
# (BeefBuild on the PATH) and, for File > Build Game, Python 3.11+. A Windows package is built here on Linux and
# needs tools/windows/setup.sh to have been run once. Run build.sh first.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
platform=""
folder=""
out="$root/dist"
while [ $# -gt 0 ]; do
	case "$1" in
		--platform) platform="$2"; shift 2 ;;
		--folder) folder="$2"; shift 2 ;;
		*) out="$1"; shift ;;
	esac
done

# Folder packages use the same cross-platform implementation as the editor.
if [ -n "$folder" ]; then
	exec python3 "$root/tools/package_engine.py" --platform "$platform" --folder "$folder"
fi

# The prebuilt native archives a platform's link settings name, at the same paths under $2.
copy_natives() { # pattern, destination
	while IFS= read -r archive; do
		[ -f "$root/$archive" ] || { echo "Missing $archive. Build the native libraries first." >&2; exit 1; }
		mkdir -p "$2/$(dirname "$archive")"
		cp -a "$root/$archive" "$2/$archive"
	done < <(grep -o "$1" "$root/Launcher/BeefProj.toml" | sort -u)
}

if [ -n "$folder" ]; then
	case "$platform" in linux|windows) ;; *) echo "--folder needs --platform linux or --platform windows." >&2; exit 1 ;; esac
	if [ -e "$folder" ]; then
		# Only ever delete a folder this script made.
		if [ ! -d "$folder" ] || { [ -n "$(ls -A "$folder")" ] && [ ! -f "$folder/tessera-package.txt" ]; }; then
			echo "$folder exists and is not an earlier Tessera package, so it is left alone. Choose another folder." >&2; exit 1
		fi
	fi
	mkdir -p "$(dirname "$folder")"
	dest="$(mktemp -d "$(dirname "$folder")/.tessera-package-XXXXXX")"
	trap 'rm -rf "$dest"' EXIT
	# The source projects compile against, what the editor reads at run time, and the tools it runs.
	for item in Engine Editor Launcher tools docs README.md THIRD_PARTY_LICENSES.txt BeefSpace.toml icon.png; do
		cp -a "$root/$item" "$dest/"
	done
	find "$dest" \( -name build -o -name recovery -o -name __pycache__ -o -name '.reload' -o -name 'imgui.ini' \) -prune -exec rm -rf {} +
	if [ "$platform" = linux ]; then
		launcher="$root/build/Debug_Linux64/TesseraLauncher/TesseraLauncher"
		[ -x "$launcher" ] || { echo "The launcher is not built. Run build.sh first." >&2; exit 1; }
		copy_natives 'build/native/[A-Za-z0-9_./-]*\.a' "$dest"
		mkdir -p "$dest/build/Debug_Linux64/TesseraLauncher" "$dest/build/native/bgfx/cmake/bgfx"
		cp -a "$launcher" "$dest/build/Debug_Linux64/TesseraLauncher/"
		cp -a "$root/build/native/bgfx/cmake/bgfx/shaderc" "$dest/build/native/bgfx/cmake/bgfx/"
		printf '#!/usr/bin/env bash\n# Starts the Tessera project launcher.\nroot="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"\nexport TESSERA_ROOT="$root"\nexec "$root/build/Debug_Linux64/TesseraLauncher/TesseraLauncher" "$@"\n' > "$dest/tessera"
		chmod +x "$dest/tessera"
		printf 'Tessera for Linux (x64). Start it with ./tessera\n\nNeeded on this machine: the Beef toolchain (BeefBuild on the PATH), because every project compiles its own\nscripts together with the engine; and Python 3.11 or later for File > Build Game.\n' > "$dest/tessera-package.txt"
	else
		win="${TESSERA_WIN:-$HOME/.local/share/tessera-win}"
		[ -f "$win/beef/bin/BeefBuild.exe" ] && [ -f "$root/build/native-win/tessera_native.lib" ] || { echo "The Windows toolchain is not set up. Run $root/tools/windows/setup.sh once." >&2; exit 1; }
		echo "Building the launcher for Windows..."
		(cd "$root" && WINEPREFIX="$win/wine" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" wine "$win/beef/bin/BeefBuild.exe" -workspace=. -config=Debug -platform=Win64 -verbosity=minimal 2>&1 | grep -v 'MESA\|pci id' || true)
		launcher="$root/build/Debug_Win64/TesseraLauncher/TesseraLauncher.exe"
		[ -f "$launcher" ] || { echo "The Windows launcher did not build." >&2; exit 1; }
		copy_natives 'build/native-win/[A-Za-z0-9_./-]*\.lib' "$dest"
		mkdir -p "$dest/build/Debug_Win64/TesseraLauncher" "$dest/build/native-win/bgfx/cmake/bgfx"
		cp -a "$launcher" "$dest/build/Debug_Win64/TesseraLauncher/"
		# A debug build of a Beef program loads Beef's runtime libraries from beside itself.
		cp -a "$root"/build/Debug_Win64/TesseraLauncher/*.dll "$dest/build/Debug_Win64/TesseraLauncher/"
		cp -a "$root/build/native-win/bgfx/cmake/bgfx/shaderc.exe" "$dest/build/native-win/bgfx/cmake/bgfx/"
		# Scripts that only run on Linux.
		rm -rf "$dest/tools/windows" "$dest/tools/package_engine.sh" "$dest/tools/compile_shaders.sh"
		printf '@echo off\r\nrem Starts the Tessera project launcher.\r\nset "TESSERA_ROOT=%%~dp0."\r\nstart "" "%%~dp0build\\Debug_Win64\\TesseraLauncher\\TesseraLauncher.exe" %%*\r\n' > "$dest/Tessera.bat"
		printf 'Tessera for Windows (64-bit). Start it with Tessera.bat\r\n\r\nNeeded on this machine:\r\n  - A graphics driver with Vulkan (any current NVIDIA, AMD or Intel driver).\r\n  - The Beef toolchain from https://www.beeflang.org, with BeefBuild on the PATH (its installer offers this).\r\n    Every project compiles its own scripts together with the engine.\r\n  - Microsoft C++ Build Tools (the Beef installer says where to get them; they are free).\r\n  - Python 3.11 or later, as "python" on the PATH, for File > Build Game.\r\n\r\nThis package was built on Linux and checked there under Wine, not on a Windows machine.\r\nScripts are not reloaded while the editor runs on Windows: use File > Full Rebuild && Restart after changing them.\r\n' > "$dest/tessera-package.txt"
	fi
	rm -rf "$folder"
	mv "$dest" "$folder"
	chmod 755 "$folder"
	trap - EXIT
	echo "Tessera for $platform packaged at $folder ($(du -sh "$folder" | cut -f1))"
	exit 0
fi

name="tessera-linux-x64-$(date +%Y%m%d)"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
dest="$stage/$name"
mkdir -p "$dest" "$out"

launcher="$root/build/Debug_Linux64/TesseraLauncher/TesseraLauncher"
[ -x "$launcher" ] || { echo "The launcher is not built. Run build.sh first." >&2; exit 1; }
[ -f "$root/build/native/libtessera_native.a" ] || { echo "The native libraries are not built. Run build.sh first." >&2; exit 1; }

# Source that projects compile against, and everything the editor reads at run time.
for item in Engine Editor Launcher Samples Tests tools docs website native README.md THIRD_PARTY_LICENSES.txt BeefSpace.toml tessera build.sh icon.png icon.svg; do
	[ -e "$root/$item" ] && cp -a "$root/$item" "$dest/"
done
# No build output, caches or local state.
find "$dest" \( -name build -o -name recovery -o -name __pycache__ -o -name '.reload' -o -name 'imgui.ini' \) -prune -exec rm -rf {} +

copy_natives 'build/native/[A-Za-z0-9_./-]*\.a' "$dest"
# The launcher itself, and the shader compiler the editor uses.
mkdir -p "$dest/build/Debug_Linux64/TesseraLauncher"
cp -a "$launcher" "$dest/build/Debug_Linux64/TesseraLauncher/"
shaderc="$(find "$root/build/native" -type f -name 'shaderc*' -perm -u+x 2>/dev/null | head -1 || true)"
if [ -n "$shaderc" ]; then
	relative="${shaderc#"$root/"}"
	mkdir -p "$dest/$(dirname "$relative")"
	cp -a "$shaderc" "$dest/$relative"
fi
# Third-party source is only needed to rebuild the native libraries; say where it comes from instead of shipping it.
cat > "$dest/REBUILDING_NATIVE.txt" <<NOTE
This package contains prebuilt native libraries (build/native). To rebuild them you need the third_party folder
from the Tessera source tree, CMake and Ninja; then run build.sh.
NOTE

tar -C "$stage" -czf "$out/$name.tar.gz" "$name"
echo "Packed $out/$name.tar.gz ($(du -h "$out/$name.tar.gz" | cut -f1))"
