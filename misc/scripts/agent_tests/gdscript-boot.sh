#!/usr/bin/env bash
# GDScript 부팅 벤치: 같은 시험 프로젝트(서로 참조하는 GDScript N 개)를 script_export_mode 별로 .pck 내보내
# 데스크톱 headless 로 실행 → 부팅 ms·정적 메모리 최고치 (각 RUNS 회, 중앙값)
# 모드: 0 텍스트 / 1 바이너리 토큰 / 2 압축 바이너리 토큰 (+ 사전 빌드가 들어오면 그 모드)
# 필요: bin/godot.linuxbsd.editor.x86_64 (target=editor)
set -euo pipefail
cd "$(dirname "$0")/../../.."
editor=$(ls -t bin/godot.linuxbsd.editor.* 2>/dev/null | grep -v '\.\(zip\|o\|a\|mono\)$' | head -1 || true)
[ -n "$editor" ] || { echo "✘ 에디터 없음 (platform=linuxbsd target=editor 먼저 빌드)"; exit 1; }
chmod +x "$editor"
N="${GDSCRIPT_BENCH_N:-400}"; RUNS="${GDSCRIPT_BENCH_RUNS:-5}"
work="${JOB_DIR:-/tmp}/gdscript-boot"; rm -rf "$work"; mkdir -p "$work"
. misc/scripts/agent_tests/lib/gdscript-project.sh
proj="$work/proj"; make_gdscript_project "$proj" "$N"
"$editor" --headless --path "$proj" --import >/dev/null 2>&1 || true

median() { sort -n | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}'; }
echo "에디터: $editor, 클래스 $N, 반복 $RUNS"
printf '%-6s %10s %10s %12s\n' mode boot_ms wall_ms static_MB
for mode in ${GDSCRIPT_BENCH_MODES:-0 1 2}; do
	cat > "$proj/export_presets.cfg" <<EOF
[preset.0]
name="Linux"
platform="Linux"
runnable=true
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path=""
script_export_mode=$mode
[preset.0.options]
binary_format/embed_pck=false
EOF
	pck="$work/m$mode.pck"
	"$editor" --headless --path "$proj" --export-pack Linux "$pck" >"$work/export-$mode.log" 2>&1 || true
	[ -f "$pck" ] || { echo "✘ 모드 $mode 내보내기 실패"; tail -5 "$work/export-$mode.log"; exit 1; }
	: >"$work/runs-$mode"
	for r in $(seq 1 "$RUNS"); do
		t0=$(date +%s%N)
		line=$("$editor" --headless --main-pack "$pck" -- --bench-quit 2>&1 | grep -m1 'boot ok' || true)
		t1=$(date +%s%N)
		[ -n "$line" ] || { echo "✘ 모드 $mode 부팅 실패"; exit 1; }
		ms=$(sed -n 's/.* ms=\([0-9]*\).*/\1/p' <<<"$line"); mb=$(sed -n 's/.*peak_static_mb=\([0-9.]*\).*/\1/p' <<<"$line")
		echo "$ms $(( (t1 - t0) / 1000000 )) $mb" >>"$work/runs-$mode"
	done
	printf '%-6s %10s %10s %12s\n' "$mode" "$(cut -d' ' -f1 "$work/runs-$mode" | median)" "$(cut -d' ' -f2 "$work/runs-$mode" | median)" "$(cut -d' ' -f3 "$work/runs-$mode" | median)"
done
echo "✔ gdscript-boot 측정 끝"
