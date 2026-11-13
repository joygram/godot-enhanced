#!/usr/bin/env bash
# godot-sqlite 를 웹 정적 라이브러리(.a)로 빌드 → 템플릿 빌드에 static_gdextensions 로 넘김
#   결과: ~/static-gdext/libgdsqlite.web.<threads|nothreads>.a  (진입 함수 sqlite_library_init)
# 환경: GDSQLITE_REF (기본 v4.9), THREADS (기본 no)
set -euo pipefail
ref="${GDSQLITE_REF:-v4.9}"
threads="${THREADS:-no}"
variant=$([ "$threads" = yes ] && echo threads || echo nothreads)
src="$HOME/static-gdext/godot-sqlite"
out="$HOME/static-gdext/libgdsqlite.web.$variant.a"
[ -f "$HOME/emsdk/emsdk_env.sh" ] && source "$HOME/emsdk/emsdk_env.sh"
emcc --version | head -1

if [ ! -d "$src/.git" ]; then
	git clone --depth 1 --branch "$ref" --recurse-submodules --shallow-submodules https://github.com/2shady4u/godot-sqlite.git "$src"
fi
cd "$src"
git fetch -q --depth 1 origin tag "$ref" && git checkout -q "$ref" && git submodule update -q --init --depth 1

# godot-cpp 웹 빌드는 SIDE_MODULE 링크까지 함 → 오브젝트만 모아 정적 아카이브로
scons platform=web target=template_release threads="$threads" -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu)"

work="$(mktemp -d)"
if [ "$threads" = yes ]; then
	cpp_lib="$(ls godot-cpp/bin/libgodot-cpp.web.template_release.wasm32*.a | grep -v nothreads | head -1)"
else
	cpp_lib="$(ls godot-cpp/bin/libgodot-cpp.web.template_release.wasm32*.a | grep nothreads | head -1)"
fi
echo "godot-cpp: $cpp_lib"
objs=$(find src -name "*.o" | sort)
# godot-cpp 아카이브에 같은 이름 멤버가 있어 풀면 덮어씀 → 복사 후 확장 오브젝트를 덧붙임
rm -rf "$work"
cp "$cpp_lib" "$out"
emar q "$out" $objs
emranlib "$out"
syms="$(emnm "$out" 2>/dev/null || true)"
grep -E "[TtW] sqlite_library_init$" <<<"$syms" || { echo "✘ sqlite_library_init 없음"; echo "$objs"; exit 1; }
ls -la "$out"
echo "✔ static-gdext-sqlite → $out"
