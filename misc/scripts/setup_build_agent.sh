#!/usr/bin/env bash
# 빌드 에이전트 설치 (macOS·Linux). sudo 없이 사용자 영역만 사용.
#   도구 = mise (node·python·uv·scons, 저장소 mise.toml), Emscripten = ~/emsdk, .NET = ~/.dotnet
#
#   curl -fsSL https://raw.githubusercontent.com/joygram/godot-enhanced/main/misc/scripts/setup_build_agent.sh | bash
#
# 선택 환경 변수:
#   BUILD_AGENT_TOKEN  공유 토큰 (없으면 기존 값 → 없으면 생성)
#   REPO_DIR           소스 위치 (기본 ~/workspace/godot-enhanced)
#   WITH_EMSDK=1       웹 템플릿용 Emscripten (EMSDK_VERSION 기본 6.0.2, GDScript·C# 공통)
#   WITH_DOTNET=1      C# 빌드용 .NET 11 SDK + wasm-tools
#   BUILD_AGENT_PORT   기본 8790
#   SKIP_SERVICE=1     서비스 등록 건너뜀 (에이전트가 스스로 재설치할 때)
set -euo pipefail

REPO_URL="https://github.com/joygram/godot-enhanced.git"
REPO_DIR="${REPO_DIR:-$HOME/workspace/godot-enhanced}"
PORT="${BUILD_AGENT_PORT:-8790}"
EMSDK_VERSION="${EMSDK_VERSION:-6.0.2}"
CONF_DIR="$HOME/.config/godot-enhanced"
OS="$(uname -s)"
MISE="$HOME/.local/bin/mise"
say() { printf '\n[setup] %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# 1) 시스템 컴파일러 확인 (설치는 안 함)
say "컴파일러 확인 ($OS)"
if [ "$OS" = "Darwin" ]; then
	xcode-select -p >/dev/null 2>&1 || { xcode-select --install || true; echo "Xcode CLT 설치 완료 후 다시 실행"; exit 1; }
else
	missing=""
	for c in git gcc g++ pkg-config; do have "$c" || missing="$missing $c"; done
	[ -z "$missing" ] || echo "⚠ 없음:$missing → 관리자에게 build-essential pkg-config 등 요청 (Godot Linux 빌드 의존성)"
fi

# 2) mise (사용자 영역)
say "mise"
[ -x "$MISE" ] || curl -fsSL https://mise.run | sh
"$MISE" --version

# 3) 소스
say "소스: $REPO_DIR"
if [ -d "$REPO_DIR/.git" ]; then git -C "$REPO_DIR" fetch -q origin && git -C "$REPO_DIR" checkout -q -f -B main origin/main
else mkdir -p "$(dirname "$REPO_DIR")" && git clone -q "$REPO_URL" "$REPO_DIR"; fi

# 4) 도구 (mise.toml: node, python, uv, scons)
say "도구 설치 (mise install)"
cd "$REPO_DIR"
"$MISE" trust -q "$REPO_DIR/mise.toml"
"$MISE" install -q
"$MISE" exec -- node --version
"$MISE" exec -- scons --version | head -2 | tail -1

# 5) 선택: Emscripten / .NET (사용자 영역)
if [ "${WITH_EMSDK:-0}" = "1" ]; then
	say "Emscripten $EMSDK_VERSION"
	[ -d "$HOME/emsdk" ] || git clone -q https://github.com/emscripten-core/emsdk.git "$HOME/emsdk"
	"$MISE" exec -- "$HOME/emsdk/emsdk" install "$EMSDK_VERSION"
	"$MISE" exec -- "$HOME/emsdk/emsdk" activate "$EMSDK_VERSION"
fi
if [ "${WITH_DOTNET:-0}" = "1" ]; then
	say ".NET 11 SDK + wasm-tools"
	curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$CONF_DIR/dotnet-install.sh" 2>/dev/null || { mkdir -p "$CONF_DIR"; curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$CONF_DIR/dotnet-install.sh"; }
	bash "$CONF_DIR/dotnet-install.sh" --channel 11.0 --install-dir "$HOME/.dotnet"
	"$HOME/.dotnet/dotnet" workload install wasm-tools
fi

# 6) 토큰·설정
TOKEN="${BUILD_AGENT_TOKEN:-}"
[ -n "$TOKEN" ] || [ ! -f "$CONF_DIR/agent.env" ] || TOKEN="$(sed -n 's/^BUILD_AGENT_TOKEN=//p' "$CONF_DIR/agent.env" | tr -d "'\"")"
[ -n "$TOKEN" ] || TOKEN="$(openssl rand -hex 24)"
GHTOKEN=""
[ ! -f "$CONF_DIR/agent.env" ] || GHTOKEN="$(sed -n 's/^GH_TOKEN=//p' "$CONF_DIR/agent.env" | tr -d "'\"")"
if have gh && gh auth token >/dev/null 2>&1; then GHTOKEN="$(gh auth token)"; fi
BIND="0.0.0.0"; have tailscale && BIND="$(tailscale ip -4 2>/dev/null | head -1 || echo 0.0.0.0)"
mkdir -p "$CONF_DIR"
DOTNET_PATH=""; [ -d "$HOME/.dotnet" ] && DOTNET_PATH="$HOME/.dotnet:"
{
	printf 'BUILD_AGENT_TOKEN=%q\n' "$TOKEN"
	printf 'BUILD_AGENT_PORT=%q\n' "$PORT"
	printf 'BUILD_AGENT_HOST=%q\n' "$BIND"
	printf 'PATH=%q\n' "$DOTNET_PATH$HOME/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
	[ -z "$DOTNET_PATH" ] || printf 'DOTNET_ROOT=%q\n' "$HOME/.dotnet"
	# 서비스는 로그인 키링에 접근 못 함 → gh 토큰 직접 전달 (릴리스 업로드용)
	[ -z "$GHTOKEN" ] || printf 'GH_TOKEN=%q\n' "$GHTOKEN"
} > "$CONF_DIR/agent.env"
chmod 600 "$CONF_DIR/agent.env"
RUNNER="$CONF_DIR/run-agent.sh"
cat > "$RUNNER" <<EOF
#!/usr/bin/env bash
# mise 가 저장소 mise.toml 의 node·python·scons 를 PATH 에 올린 채 에이전트 실행
set -a; source "$CONF_DIR/agent.env"; set +a
cd "$REPO_DIR" && exec "$MISE" exec -- node misc/scripts/build_agent.mjs
EOF
chmod +x "$RUNNER"

# 7) 서비스 (sudo 없음)
if [ "${SKIP_SERVICE:-0}" = "1" ]; then say "서비스 등록 건너뜀"
elif [ "$OS" = "Darwin" ]; then
	say "서비스: launchd"
	PLIST="$HOME/Library/LaunchAgents/com.godot-enhanced.build-agent.plist"
	mkdir -p "$(dirname "$PLIST")"
	cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.godot-enhanced.build-agent</string>
<key>ProgramArguments</key><array><string>$RUNNER</string></array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
<key>StandardOutPath</key><string>$CONF_DIR/agent.log</string>
<key>StandardErrorPath</key><string>$CONF_DIR/agent.log</string>
</dict></plist>
EOF
	launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
	launchctl bootstrap "gui/$(id -u)" "$PLIST"
elif systemctl cat godot-enhanced-build-agent.service >/dev/null 2>&1; then
	say "서비스: 기존 systemd 서비스 유지 (실행 파일 $RUNNER 갱신됨)"
	pkill -f 'misc/scripts/build_agent.mjs' || true   # Restart=always → 새 설정으로 재시작
else
	say "서비스: 사용자 영역 (crontab @reboot + 감시 루프)"
	LOOP="$CONF_DIR/agent-loop.sh"
	printf '#!/usr/bin/env bash\nwhile true; do "%s" >> "%s/agent.log" 2>&1; sleep 5; done\n' "$RUNNER" "$CONF_DIR" > "$LOOP"
	chmod +x "$LOOP"
	( crontab -l 2>/dev/null | grep -v agent-loop.sh; echo "@reboot $LOOP" ) | crontab -
	pkill -f agent-loop.sh || true; pkill -f 'misc/scripts/build_agent.mjs' || true
	nohup "$LOOP" >/dev/null 2>&1 &
fi

say "완료 — 에이전트 $BIND:$PORT"
echo "토큰: $TOKEN"
echo "로그: $CONF_DIR/agent.log (systemd 서비스면 journalctl -u godot-enhanced-build-agent)"
