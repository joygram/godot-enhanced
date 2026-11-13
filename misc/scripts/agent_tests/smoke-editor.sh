#!/usr/bin/env bash
# 에디터 스모크: 방금 빌드한 에디터 실행 → 버전에 enhanced-<ENHANCED_VERSION> 포함, 빈 프로젝트 열고 닫기
set -euo pipefail
cd "$(dirname "$0")/../../.."
bin=$(ls -t "$JOB_DIR"/godot.*editor* 2>/dev/null | grep -v '\.zip$' | head -1 || true)
[ -n "$bin" ] || bin=$(ls -t bin/godot.*editor* 2>/dev/null | grep -v '\.\(zip\|o\|a\)$' | head -1)
chmod +x "$bin"
want="enhanced-$(tr -d '[:space:]' < ENHANCED_VERSION)"
ver=$("$bin" --headless --version 2>/dev/null | tail -1)
echo "버전: $ver"
case "$ver" in *"$want"*) ;; *) echo "✘ 버전에 $want 없음"; exit 1 ;; esac
proj=$(mktemp -d)
printf 'config_version=5\n[application]\nconfig/name="smoke"\n' > "$proj/project.godot"
log=$("$bin" --headless --path "$proj" --editor --quit 2>&1 || true)
rm -rf "$proj"
if echo "$log" | grep -E '^(ERROR|SCRIPT ERROR)' ; then echo "✘ 에디터 오류"; exit 1; fi
echo "✔ smoke-editor 통과"
