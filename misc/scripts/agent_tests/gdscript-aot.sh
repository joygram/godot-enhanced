#!/usr/bin/env bash
# GDScript AOT 검사 (patches/gdscript-aot.md): gdscript-prebuild 기능 스크립트를
#   편집기로 사전 빌드 내보내기(GODOT_GDSCRIPT_AOT_DIR → C++) → 그 C++ 넣어 릴리스 템플릿 빌드 → 실행
#   통과 = 출력이 VM 기준(모드 2)과 같고, AOT 로 연결된 함수가 1개 이상
# 필요: bin/godot.<platform>.editor.* (같은 작업에서 먼저 빌드)
set -euo pipefail
cd "$(dirname "$0")/../../.."
editor=$(ls -t bin/godot.*.editor.* 2>/dev/null | grep -v '\.\(zip\|o\|a\|mono\|app\)$' | head -1 || true)
[ -n "$editor" ] || { echo "✘ 에디터 없음"; exit 1; }
chmod +x "$editor"
platform=$(basename "$editor" | cut -d. -f2)
arch=$(basename "$editor" | cut -d. -f4)

# 기능 스크립트·모드 2/3 내보내기는 gdscript-prebuild 와 같음 (그 검사가 만든 프로젝트 재사용)
JOB_DIR="${JOB_DIR:-/tmp}" bash misc/scripts/agent_tests/gdscript-prebuild.sh
w="${JOB_DIR:-/tmp}/gdscript-prebuild"; p="$w/proj"; aot="$w/aot"
rm -rf "$aot"; mkdir -p "$aot"

GODOT_GDSCRIPT_AOT_DIR="$aot" "$editor" --headless --path "$p" --export-pack Linux "$w/aot.pck" >"$w/export-aot.log" 2>&1 || true
grep -h "GDScript AOT" "$w/export-aot.log" || { echo "✘ AOT 생성 로그 없음"; tail -5 "$w/export-aot.log"; exit 1; }
ls "$aot"/gd_aot_*.cpp >/dev/null 2>&1 || { echo "✘ 생성된 C++ 없음"; exit 1; }

jobs=$( (nproc || sysctl -n hw.ncpu) 2>/dev/null | head -1)
scons platform="$platform" arch="$arch" target=template_release gdscript_aot_dir="$aot" -j"$jobs" >"$w/build-aot.log" 2>&1 || { echo "✘ AOT 템플릿 빌드 실패"; grep -m10 -E 'error' "$w/build-aot.log"; exit 1; }
template=$(ls -t bin/godot.$platform.template_release.* 2>/dev/null | grep -v '\.\(zip\|o\|a\)$' | head -1)
[ -n "$template" ] || { echo "✘ 템플릿 없음"; exit 1; }
chmod +x "$template"

timeout 30 "$template" --headless --verbose --main-pack "$w/aot.pck" >"$w/run-aot.log" 2>&1 || true
grep '^PB ' "$w/run-aot.log" >"$w/out-aot.txt" || true
native=$(grep -c "GDScript AOT: native" "$w/run-aot.log" || true)
echo "[AOT] $(wc -l <"$w/out-aot.txt") 줄, 네이티브 함수 $native 개"
grep -E 'ERROR|SCRIPT ERROR|bytecode changed' "$w/run-aot.log" | head -5 || true
[ "$native" -gt 0 ] || { echo "✘ AOT 로 연결된 함수 없음"; exit 1; }
if diff "$w/out-2.txt" "$w/out-aot.txt" >"$w/diff-aot.txt"; then
	echo "✔ gdscript-aot 통과 — AOT 템플릿 출력이 VM 기준과 같음 (네이티브 $native 개)"
else
	echo "✘ 출력 다름:"; cat "$w/diff-aot.txt"; exit 1
fi
