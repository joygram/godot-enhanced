#!/usr/bin/env bash
# 웹 도구 준비: Emscripten(~/emsdk), Playwright 브라우저(Chromium·WebKit). 이미 있으면 건너뜀
# EMSDK_VERSION 기본 4.0.11 (GDScript 웹 템플릿 기준). C# 은 6.0.2 → EMSDK_VERSION=6.0.2
set -euo pipefail
ver="${EMSDK_VERSION:-4.0.11}"
[ -d "$HOME/emsdk" ] || git clone -q https://github.com/emscripten-core/emsdk.git "$HOME/emsdk"
"$HOME/emsdk/emsdk" install "$ver" >/dev/null
"$HOME/emsdk/emsdk" activate "$ver" >/dev/null
source "$HOME/emsdk/emsdk_env.sh" >/dev/null 2>&1
echo "emcc: $(emcc --version | head -1)"
dir="$HOME/.cache/godot-enhanced-web"
mkdir -p "$dir" && cd "$dir"
[ -f package.json ] || npm init -y >/dev/null
[ -d node_modules/playwright ] || npm install -s playwright@1.49.1 >/dev/null
npx -y playwright install chromium webkit >/dev/null
echo "playwright: $(npx playwright --version)"
echo "✔ provision-web 완료"
