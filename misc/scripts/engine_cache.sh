#!/usr/bin/env bash
# 엔진 빌드 캐시(SCons cache_path) 받기·올리기. 모듈·파일별 오브젝트와 libmodule_*.a 가 들어 있어
# 모듈 조합(module_<이름>_enabled)·정적 확장(static_gdextensions)을 바꿔도 바뀐 부분만 컴파일 → 링크
#   fetch <platform>          캐시가 비어 있으면 릴리스에서 받아 풂
#   upload <platform> <args>  현재 소스로 캐시를 채우고(--cache-populate) 릴리스에 올림
# 캐시: $GODOT_CACHE_DIR(기본 ~/godot-cache)/<platform>
# 릴리스: engine-cache-<platform>[-emsdk<버전>], 자산 godot-cache-<platform>.tar.gz
set -euo pipefail
cd "$(dirname "$0")/../.."
cmd="$1"; platform="$2"; shift 2
cache="${GODOT_CACHE_DIR:-$HOME/godot-cache}/$platform"
mkdir -p "$cache"
repo="$(git remote get-url origin | sed -E 's#(\.git)?$##; s#.*github\.com[:/]##')"
tag="engine-cache-$platform"
[ "$platform" = web ] && tag="$tag-emsdk$(emcc -dumpversion)"
asset="godot-cache-$platform.tar.gz"

case "$cmd" in
fetch)
	if [ -n "$(ls -A "$cache" 2>/dev/null)" ]; then echo "캐시 있음: $cache ($(du -sh "$cache" | cut -f1))"; exit 0; fi
	tmp="$(mktemp -d)"
	if gh release download "$tag" -R "$repo" -p "$asset" -D "$tmp" 2>/dev/null; then
		tar -xzf "$tmp/$asset" -C "$cache"
		echo "캐시 받음: $tag → $cache ($(du -sh "$cache" | cut -f1))"
	else
		echo "캐시 릴리스 없음: $tag (전체 빌드)"
	fi
	rm -rf "$tmp"
	;;
upload)
	# 이미 빌드돼 있는 결과도 캐시에 넣음
	scons "$@" cache_path="$cache" --cache-populate -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu)" >/dev/null
	tmp="$(mktemp -d)"
	tar -czf "$tmp/$asset" -C "$cache" .
	ls -la "$tmp/$asset"
	gh release view "$tag" -R "$repo" >/dev/null 2>&1 || gh release create "$tag" -R "$repo" --title "Engine build cache ($platform)" \
		--notes "SCons 빌드 캐시. 빌드 에이전트가 자동으로 받아 씀 (misc/scripts/engine_cache.sh)" >/dev/null
	gh release upload "$tag" -R "$repo" "$tmp/$asset" --clobber
	rm -rf "$tmp"
	echo "✔ 캐시 올림: $tag/$asset"
	;;
*) echo "사용: engine_cache.sh fetch|upload <platform> [scons 인자]"; exit 2 ;;
esac
