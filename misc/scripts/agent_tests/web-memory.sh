#!/usr/bin/env bash
# 웹 메모리 검사: 이 머신의 에디터 + GDScript 웹 템플릿으로 시험 프로젝트를 내보내 headless Chrome 에서 측정
# 시험 프로젝트 = 서로 참조하는 GDScript 200개 (파서 해제 패치 효과가 드러나는 구조)
# 필요: bin/godot.*editor*, bin/godot.web.template_release.wasm32.nothreads.zip, Chrome, node
# 결과: $JOB_DIR/web-memory.json, web-memory.png
set -euo pipefail
cd "$(dirname "$0")/../../.."
root=$(pwd)
editor=$(ls -t bin/godot.*editor* 2>/dev/null | grep -v '\.\(zip\|o\|a\)$' | head -1 || true)
template=$(ls -t bin/godot.web.template_release.wasm32.nothreads.zip 2>/dev/null | head -1 || true)
[ -n "$editor" ] || { echo "✘ 에디터 없음 (target=editor 먼저 빌드)"; exit 1; }
[ -n "$template" ] || { echo "✘ 웹 템플릿 없음 (platform=web target=template_release threads=no 먼저 빌드)"; exit 1; }
chmod +x "$editor"
echo "에디터: $editor"; echo "템플릿: $template"

proj="$JOB_DIR/web-project"
. misc/scripts/agent_tests/lib/gdscript-project.sh
make_gdscript_project "$proj" 200
"$editor" --headless --path "$proj" --import >/dev/null 2>&1 || true

# 내보내기 + 브라우저 측정. $1 = 템플릿, $2 = extensions_support(dlink), $3 = 결과 이름,
# $4 = thread_support (기본 false), $5 = script_export_mode (기본 2 압축 토큰, 3 사전 빌드)
run_variant() {
	local tpl=$1 ext=$2 tag=$3 threads=${4:-false} mode=${5:-2} o="$JOB_DIR/web-out-$3"
	rm -rf "$o"; mkdir -p "$o"
	cat > "$proj/export_presets.cfg" <<EOF
[preset.0]
name="Web"
platform="Web"
runnable=true
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path=""
script_export_mode=$mode
[preset.0.options]
custom_template/debug=""
custom_template/release="$root/$tpl"
variant/extensions_support=$ext
variant/thread_support=$threads
vram_texture_compression/for_desktop=true
html/export_icon=false
compression/precompress=true
EOF
	"$editor" --headless --path "$proj" --export-release Web "$o/index.html" 2>&1 | grep -E '^(ERROR|WARNING: .*export)' || true
	[ -f "$o/index.wasm" ] || { echo "✘ [$tag] 내보내기 실패"; exit 1; }
	# compression/precompress: .pck·.wasm(·.side.wasm) 이 gzip 서명(1f8b)으로 시작 → 브라우저 부팅 = 로더 해제 검증
	local files="index.wasm index.pck"
	[ "$ext" = true ] && files="$files index.side.wasm"
	for f in $files; do
		[ "$(head -c2 "$o/$f" | od -An -tx1 | tr -d ' \n')" = "1f8b" ] || { echo "✘ [$tag] $f 미압축"; exit 1; }
		echo "[$tag] precompress: $f $(stat -c%s "$o/$f") B"
	done
	node misc/scripts/web_memory.mjs "$o" "${WEB_MEMORY_SECONDS:-30}" "$JOB_DIR/web-memory-$tag.json"
	echo "✔ [$tag] web-memory 통과"
}

run_variant "$template" false static
# 사전 빌드 (script_export_mode=3): 같은 템플릿, 부팅·힙 비교
run_variant "$template" false static-prebuilt false 3
# dlink 템플릿이 있으면 (platform=web dlink_enabled=yes) side module 경로도 검사
dlink=$(ls -t bin/godot.web.template_release.wasm32.nothreads.dlink.zip 2>/dev/null | head -1 || true)
if [ -n "$dlink" ]; then run_variant "$dlink" true dlink; else echo "(dlink 템플릿 없음 → dlink 검사 생략)"; fi
# 멀티스레드 + dlink + 사전 빌드 (rpg2d 배포 조합) — threads=yes dlink_enabled=yes 템플릿이 있으면
tdlink=$(ls -t bin/godot.web.template_release.wasm32.dlink.zip 2>/dev/null | head -1 || true)
if [ -n "$tdlink" ]; then run_variant "$tdlink" true threads-dlink-prebuilt true 3; else echo "(threads dlink 템플릿 없음 → 생략)"; fi
