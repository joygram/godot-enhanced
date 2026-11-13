#!/usr/bin/env bash
# 웹 의존성 설치 (콘솔에서 진행 보면서): 소스 갱신 → 남은 설치 정리 → Emscripten 6.0.2 + Playwright 브라우저
#   curl -fsSL https://raw.githubusercontent.com/joygram/godot-enhanced/main/misc/scripts/web-deps.sh | bash
set -euo pipefail
REPO_DIR="${REPO_DIR:-$HOME/workspace/godot-enhanced}"
git -C "$REPO_DIR" fetch -q origin && git -C "$REPO_DIR" checkout -q -f -B main origin/main
cd "$REPO_DIR"
bash misc/scripts/agent_tests/cleanup-web.sh
exec "$HOME/.local/bin/mise" exec -- bash misc/scripts/agent_tests/provision-web.sh
