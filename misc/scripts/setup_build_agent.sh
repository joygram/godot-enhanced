#!/usr/bin/env bash
# 빌드 에이전트 설치 (macOS·Linux). 한 번 실행 → clone, 도구 설치, 서비스 등록.
#
#   curl -fsSL https://raw.githubusercontent.com/joygram/godot-enhanced/main/misc/scripts/setup_build_agent.sh | bash
#
# 선택 환경 변수:
#   BUILD_AGENT_TOKEN  공유 토큰 (없으면 생성해 출력 → Windows 쪽에 같은 값 설정)
#   REPO_DIR           소스 위치 (기본 ~/workspace/godot-enhanced)
#   WITH_EMSDK=1       웹 템플릿용 Emscripten 설치 (EMSDK_VERSION 기본 6.0.2)
#   WITH_DOTNET=1      C# 빌드용 .NET 11 SDK + wasm-tools 설치
#   BUILD_AGENT_PORT   기본 8790
#   NODE_VERSION       nvm 사용 시 node 버전 (기본 nvm default)
set -euo pipefail

REPO_URL="https://github.com/joygram/godot-enhanced.git"
REPO_DIR="${REPO_DIR:-$HOME/workspace/godot-enhanced}"
PORT="${BUILD_AGENT_PORT:-8790}"
EMSDK_VERSION="${EMSDK_VERSION:-6.0.2}"
CONF_DIR="$HOME/.config/godot-enhanced"
OS="$(uname -s)"
say() { printf '\n[setup] %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# 0) nvm 있으면 그 node 사용 (NODE_VERSION 기본 = nvm default)
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [ -s "$NVM_DIR/nvm.sh" ]; then
	# shellcheck disable=SC1091
	set +u; . "$NVM_DIR/nvm.sh"; nvm use "${NODE_VERSION:-default}" >/dev/null || nvm install "${NODE_VERSION:-22}"; set -u
fi

# 1) 기본 도구
say "도구 확인 ($OS)"
if [ "$OS" = "Darwin" ]; then
	xcode-select -p >/dev/null 2>&1 || { xcode-select --install || true; echo "Xcode CLT 설치 완료 후 다시 실행"; exit 1; }
	if ! have brew; then
		/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
		eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
	fi
	for p in git python3 node; do have "$p" || brew install "${p/python3/python}"; done
elif have apt-get; then
	sudo apt-get update -y
	sudo apt-get install -y git python3 python3-pip python3-venv build-essential pkg-config curl \
		libx11-dev libxcursor-dev libxinerama-dev libgl1-mesa-dev libglu1-mesa-dev libasound2-dev \
		libpulse-dev libudev-dev libxi-dev libxrandr-dev libwayland-dev
	have node || { curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt-get install -y nodejs; }
else
	echo "지원 안 함: apt 없는 Linux → git, python3, node, 빌드 도구 직접 설치 후 다시 실행"; exit 1
fi
python3 -m pip install --user --upgrade scons 2>/dev/null || python3 -m pip install --user --break-system-packages --upgrade scons
export PATH="$HOME/.local/bin:$(python3 -c 'import site,os;print(os.path.join(site.USER_BASE,"bin"))'):$PATH"
have scons || { echo "scons 경로 확인 필요"; exit 1; }

# 2) 소스
say "소스: $REPO_DIR"
if [ -d "$REPO_DIR/.git" ]; then git -C "$REPO_DIR" fetch -q origin && git -C "$REPO_DIR" checkout -q main && git -C "$REPO_DIR" pull -q --ff-only || true
else mkdir -p "$(dirname "$REPO_DIR")" && git clone -q "$REPO_URL" "$REPO_DIR"; fi

# 3) 선택: Emscripten / .NET
PRE=""
if [ "${WITH_EMSDK:-0}" = "1" ]; then
	say "Emscripten $EMSDK_VERSION"
	[ -d "$HOME/emsdk" ] || git clone -q https://github.com/emscripten-core/emsdk.git "$HOME/emsdk"
	"$HOME/emsdk/emsdk" install "$EMSDK_VERSION" && "$HOME/emsdk/emsdk" activate "$EMSDK_VERSION"
	PRE="source $HOME/emsdk/emsdk_env.sh >/dev/null"
fi
if [ "${WITH_DOTNET:-0}" = "1" ]; then
	say ".NET 11 SDK + wasm-tools"
	curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
	bash /tmp/dotnet-install.sh --channel 11.0 --install-dir "$HOME/.dotnet"
	"$HOME/.dotnet/dotnet" workload install wasm-tools
	PRE="${PRE:+$PRE && }export DOTNET_ROOT=$HOME/.dotnet PATH=$HOME/.dotnet:\$PATH"
fi

# 4) 토큰·설정
TOKEN="${BUILD_AGENT_TOKEN:-}"
[ -n "$TOKEN" ] || [ ! -f "$CONF_DIR/agent.env" ] || TOKEN="$(sed -n 's/^BUILD_AGENT_TOKEN=//p' "$CONF_DIR/agent.env" | tr -d "'\"")"
[ -n "$TOKEN" ] || TOKEN="$(openssl rand -hex 24)"
BIND="0.0.0.0"; have tailscale && BIND="$(tailscale ip -4 2>/dev/null | head -1 || echo 0.0.0.0)"
mkdir -p "$CONF_DIR"
NODE_BIN="$(command -v node)"
# 값마다 셸 인용 (PATH 등 공백 포함 경로 대비)
{
	printf 'BUILD_AGENT_TOKEN=%q\n' "$TOKEN"
	printf 'BUILD_AGENT_PORT=%q\n' "$PORT"
	printf 'BUILD_AGENT_HOST=%q\n' "$BIND"
	printf 'BUILD_AGENT_PRE=%q\n' "$PRE"
	printf 'PATH=%q\n' "$PATH"
	# 서비스는 로그인 키링에 접근 못 함 → gh 토큰을 직접 전달 (릴리스 업로드용)
	if have gh && gh auth token >/dev/null 2>&1; then printf 'GH_TOKEN=%q\n' "$(gh auth token)"; fi
} > "$CONF_DIR/agent.env"
chmod 600 "$CONF_DIR/agent.env"
RUNNER="$CONF_DIR/run-agent.sh"
if [ -s "$NVM_DIR/nvm.sh" ]; then
	# nvm: 실행 때마다 nvm default 로 node 결정 (버전 바꿔도 유지)
	cat > "$RUNNER" <<EOF
#!/usr/bin/env bash
set -a; source "$CONF_DIR/agent.env"; set +a
export NVM_DIR="$NVM_DIR"; . "\$NVM_DIR/nvm.sh"; nvm use "${NODE_VERSION:-default}" >/dev/null
cd "$REPO_DIR" && exec node misc/scripts/build_agent.mjs
EOF
else
	cat > "$RUNNER" <<EOF
#!/usr/bin/env bash
set -a; source "$CONF_DIR/agent.env"; set +a
cd "$REPO_DIR" && exec "$NODE_BIN" misc/scripts/build_agent.mjs
EOF
fi
chmod +x "$RUNNER"

# 5) 서비스 등록
say "서비스 등록"
if [ "$OS" = "Darwin" ]; then
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
else
	# 시스템 서비스 (사용자 systemd 는 SSH·데스크톱 밖 세션에서 안 뜨는 경우 있음)
	UNIT="/etc/systemd/system/godot-enhanced-build-agent.service"
	sudo tee "$UNIT" >/dev/null <<EOF
[Unit]
Description=godot-enhanced build agent
After=network-online.target tailscaled.service
Wants=network-online.target
[Service]
User=$USER
ExecStart=$RUNNER
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
	sudo systemctl daemon-reload
	sudo systemctl enable godot-enhanced-build-agent.service
	sudo systemctl restart godot-enhanced-build-agent.service
fi

say "완료 — 에이전트 $BIND:$PORT"
echo "Windows 쪽 설정:  setx BUILD_AGENT_TOKEN $TOKEN"
echo "빌드 신호 예:     node misc/scripts/remote_build.mjs $(hostname -s) platform=$([ "$OS" = Darwin ] && echo macos || echo linuxbsd) target=editor"
echo "로그: $([ "$OS" = Darwin ] && echo "$CONF_DIR/agent.log" || echo "journalctl -u godot-enhanced-build-agent -f")"
