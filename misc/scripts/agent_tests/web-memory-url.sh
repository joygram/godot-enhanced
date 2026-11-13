#!/usr/bin/env bash
# 다른 머신이 만든 웹 빌드(zip, WEB_URL)를 받아 이 머신 브라우저로 메모리 측정
# 결과: $JOB_DIR/web-memory.json, web-memory.png
set -euo pipefail
cd "$(dirname "$0")/../../.."
[ -n "${WEB_URL:-}" ] || { echo "✘ WEB_URL 없음"; exit 1; }
out="$JOB_DIR/web"; mkdir -p "$out"
echo "받기: $WEB_URL"
curl -fsSL "$WEB_URL" -o "$JOB_DIR/web.zip"
unzip -q -o "$JOB_DIR/web.zip" -d "$out"
ls -la "$out" | head
node misc/scripts/web_memory.mjs "$out" "${WEB_MEMORY_SECONDS:-30}" "$JOB_DIR/web-memory.json"
echo "✔ web-memory-url 통과"
