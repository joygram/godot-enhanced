#!/usr/bin/env bash
# 진단: emsdk dylink 가 side module(.side.wasm) 을 어디서 읽는지 (loadLibData·readAsync·preloadedWasm)
cd "$(dirname "$0")/../../.."
em=$(command -v emcc || true)
[ -n "$em" ] || { for d in "${EMSDK:-}" "$HOME/emsdk"; do [ -x "$d/upstream/emscripten/emcc" ] && em="$d/upstream/emscripten/emcc"; done; }
echo "emcc: $em"
src="$(dirname "$(readlink -f "$em")")/src"
f=$(ls "$src"/lib/libdylink.js "$src"/library_dylink.js 2>/dev/null | head -1)
echo "file: $f"
rg -n "function loadLibData|loadLibData|readAsync|preloadedWasm|asyncLoad|findObject|loadDynamicLibrary\(|dynamicLibraries" "$f" | head -40
echo "── findLibraryFS"
awk '/findLibraryFS = /{p=1} p{print NR": "$0; n++} n>30{exit}' "$f"
echo "── loadDylibs 호출 위치"
rg -n "loadDylibs|addRunDependency\('loadDylibs|preRun" "$src"/preamble.js "$src"/postamble.js "$f" 2>/dev/null | head -20
