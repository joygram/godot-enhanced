#!/usr/bin/env bash
# 웹 도구 준비: Emscripten(~/emsdk), Playwright 브라우저(Chromium·WebKit). 이미 있으면 건너뜀
# EMSDK_VERSION 기본 6.0.2 (GDScript·C# 웹 공통). 진행 출력은 그대로 보임
# 직접 실행: ~/.local/bin/mise exec -- bash misc/scripts/agent_tests/provision-web.sh
set -euo pipefail
ver="${EMSDK_VERSION:-6.0.2}"
step() { printf '\n── %s\n' "$*"; }

step "python ($(python3 --version 2>&1))"
# emsdk = Python 3.10+. 낮으면 brew python (sudo 불필요)
if ! python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))'; then
	if command -v brew >/dev/null; then
		brew list python@3.12 >/dev/null 2>&1 || brew install python@3.12
		export EMSDK_PYTHON="$(brew --prefix python@3.12)/bin/python3.12"
		echo "EMSDK_PYTHON=$EMSDK_PYTHON"
	else echo "✘ Python 3.10+ 필요"; exit 1; fi
fi

step "Emscripten $ver"
[ -d "$HOME/emsdk" ] || git clone https://github.com/emscripten-core/emsdk.git "$HOME/emsdk"
"$HOME/emsdk/emsdk" install "$ver"
"$HOME/emsdk/emsdk" activate "$ver"
source "$HOME/emsdk/emsdk_env.sh" >/dev/null 2>&1
echo "emcc: $(emcc --version | head -1)"

dir="$HOME/.cache/godot-enhanced-web"
mkdir -p "$dir" && cd "$dir"
step "npm: playwright"
[ -f package.json ] || npm init -y >/dev/null
[ -d node_modules/playwright ] || npm install --no-fund --no-audit playwright@1.49.1

step "브라우저 내려받기: chromium, webkit"
npx -y playwright install chromium webkit

step "브라우저 실행 확인"
for b in chromium webkit; do
	if node -e "setTimeout(()=>{console.error('60초 안에 안 뜸');process.exit(1)},60000).unref();require('playwright')['$b'].launch().then(b=>b.close()).then(()=>process.exit(0)).catch(e=>{console.error(String(e).split('\n').slice(0,3).join(' | '));process.exit(1)})"; then echo "$b: 실행 OK"
	else echo "$b: 실행 실패 (리눅스는 시스템 라이브러리 누락 가능)"; fi
done
echo "playwright: $(npx playwright --version)"
echo "✔ provision-web 완료"
