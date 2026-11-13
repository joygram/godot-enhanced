#!/usr/bin/env bash
# misc/static_gdextensions.json 의 GDExtension 을 웹 정적 라이브러리(.a)로 빌드 → GitHub 릴리스 업로드
#   변형 4종: template_release|template_debug × threads|nothreads
#   결과: $STATIC_GDEXT_DIR(기본 ~/static-gdext)/<이름>-<ref>.web.<target>.wasm32[.nothreads].a
#   릴리스: static-gdext-emsdk<버전> (자산 이름 = 결과 파일 이름)
# 환경: GDEXT (빌드할 이름, 쉼표, 기본 전체), NO_RELEASE=1 (업로드 생략)
set -euo pipefail
cd "$(dirname "$0")/../../.."
manifest="misc/static_gdextensions.json"
dir="${STATIC_GDEXT_DIR:-$HOME/static-gdext}"
mkdir -p "$dir"
[ -f "$HOME/emsdk/emsdk_env.sh" ] && source "$HOME/emsdk/emsdk_env.sh" >/dev/null
emver="$(emcc -dumpversion)"
echo "emsdk $emver → $dir"
jget() { node -e "const m=require('./$manifest');const e=m['$1'];process.stdout.write(String(e?e['$2']:''))"; }
names="${GDEXT:-$(node -e "console.log(Object.keys(require('./$manifest')).filter(k=>!k.startsWith('_')).join(','))")}"
jobs="$(nproc 2>/dev/null || sysctl -n hw.ncpu)"
built=()

for name in ${names//,/ }; do
	repo="$(jget "$name" repo)"; ref="$(jget "$name" ref)"; entry="$(jget "$name" entry)"
	[ -n "$repo" ] || { echo "✘ $manifest 에 $name 없음"; exit 1; }
	src="$dir/src/$name"
	if [ ! -d "$src/.git" ]; then
		git clone -q --depth 1 --branch "$ref" --recurse-submodules --shallow-submodules "$repo" "$src"
	fi
	(cd "$src" && git fetch -q --depth 1 origin tag "$ref" && git checkout -q "$ref" && git submodule update -q --init --depth 1)

	for target in template_release template_debug; do
		for threads in no yes; do
			suffix=$([ "$threads" = yes ] && echo "" || echo ".nothreads")
			out="$dir/$name-$ref.web.$target.wasm32$suffix.a"
			echo "── $name $ref $target threads=$threads"
			(cd "$src" && find src -name "*.o" -delete && scons -Q platform=web target="$target" threads="$threads" -j"$jobs" >/dev/null)
			# godot-cpp 아카이브에 같은 이름 멤버가 있어 풀면 덮어씀 → 복사 후 확장 오브젝트를 덧붙임
			cpp_lib="$(ls "$src"/godot-cpp/bin/libgodot-cpp.web."$target".wasm32*.a | { if [ "$threads" = yes ]; then grep -v nothreads; else grep nothreads; fi; } | head -1)"
			cp "$cpp_lib" "$out"
			emar q "$out" $(cd "$src" && find src -name "*.o" | sed "s|^|$src/|")
			emranlib "$out"
			syms="$(emnm "$out" 2>/dev/null || true)"
			grep -qE "[TtW] $entry\$" <<<"$syms" || { echo "✘ $out 에 $entry 없음"; exit 1; }
			ls -la "$out"
			built+=("$out")
		done
	done
done

if [ -z "${NO_RELEASE:-}" ] && command -v gh >/dev/null; then
	tag="static-gdext-emsdk$emver"
	gh release view "$tag" >/dev/null 2>&1 || gh release create "$tag" --title "Static GDExtensions (web, emsdk $emver)" \
		--notes "웹 템플릿 정적 링크용 GDExtension. 빌드: scons platform=web static_gdextensions=<이름>" >/dev/null
	gh release upload "$tag" "${built[@]}" --clobber
	echo "릴리스: $tag (${#built[@]}개)"
fi
echo "✔ static-gdext ${#built[@]}개"
