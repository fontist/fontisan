#!/usr/bin/env bash
# Build Google's woff2_decompress from a pinned source commit (brotli comes
# pinned via the woff2 submodule). Used by the corpus to cross-check the
# WOFF2 collection and, later, to compare WOFF/WOFF2 encode output after
# decoding (compressed bytes depend on the brotli build, so they are not
# compared directly).
#
# Why `make` and not CMake: upstream's CMakeLists.txt resolves brotli with
# find_package (the SYSTEM brotli, measured: a CMake build on macOS linked
# /opt/homebrew brotli), which would silently un-pin brotli. The Makefile
# compiles the brotli submodule sources into the binary, so the whole decoder
# is pinned by one commit.
#
# Linux / macOS: needs git, make, a C/C++ compiler.
# Windows: run from an MSYS2 MINGW64 shell with
#   pacman -S --needed git make mingw-w64-x86_64-gcc
# (upstream google/woff2 has no Windows CI; this path is untested upstream.)
#
# Output: prints the absolute path of woff2_decompress on stdout (last line).
# Override the install dir with WOFF2_DIR.
set -euo pipefail

PIN="7b67e12355fe7da148db5c19d4261f0a498a9537"
REPO="https://github.com/google/woff2.git"
root="$(cd "$(dirname "$0")/.." && pwd)"
dest="${WOFF2_DIR:-$root/corpus/fonts/.tools/woff2}"
src="$dest/src"
exe="$dest/bin/woff2_decompress"
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) exe="$exe.exe" ;; esac

if [ -x "$exe" ] && [ "$(cat "$dest/PIN" 2>/dev/null || true)" = "$PIN make" ]; then
  echo "woff2_decompress already built at pin $PIN" >&2
  echo "$exe"
  exit 0
fi

command -v git >/dev/null || { echo "build-woff2: git is required" >&2; exit 1; }
command -v make >/dev/null || { echo "build-woff2: make is required" >&2; exit 1; }

rm -rf "$dest"
mkdir -p "$dest/bin"
git clone --recursive "$REPO" "$src" >&2
(
  cd "$src"
  git checkout --quiet "$PIN"
  git submodule update --init --recursive >&2
  test "$(git rev-parse HEAD)" = "$PIN"
)

(cd "$src" && make woff2_decompress -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)" >&2)

built="$src/woff2_decompress"
[ -f "$built" ] || built="$src/woff2_decompress.exe"
[ -f "$built" ] || { echo "build-woff2: woff2_decompress not produced" >&2; exit 1; }
cp "$built" "$exe"
echo "$PIN make" > "$dest/PIN"
echo "$exe"
