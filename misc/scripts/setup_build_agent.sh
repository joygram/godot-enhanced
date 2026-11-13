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
set -euo pipefail

REPO_URL="https://github.com/joygram/godot-enhanced.git"
REPO_DIR="${REPO_DIR:-$HOME/workspace/godot-enhanced}"
PORT="${BUILD_AGENT_PORT:-8790}"
EMSDK_VERSION="${EMSDK_VERSION:-6.0.2}"
CONF_DIR="$HOME/.config/godot-enhanced"
OS="$(uname -s)"
say() { printf '\n[setup] %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

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
[ -n "$TOKEN" ] || [ ! -f "$CONF_DIR/agent.env" ] || TOKEN="$(sed -n 's/^BUILD_AGENT_TOKEN=//p' "$CONF_DIR/agent.env")"
[ -n "$TOKEN" ] || TOKEN="$(openssl rand -hex 24)"
BIND="0.0.0.0"; have tailscale && BIND="$(tailscale ip -4 2>/dev/null | head -1 || echo 0.0.0.0)"
mkdir -p "$CONF_DIR"
cat > "$CONF_DIR/agent.env" <<EOF
BUILD_AGENT_TOKEN=$TOKEN
BUILD_AGENT_PORT=$PORT
BUILD_AGENT_HOST=$BIND
BUILD_AGENT_PRE=$PRE
PATH=$PATH
EOF
chmod 600 "$CONF_DIR/agent.env"
RUNNER="$CONF_DIR/run-agent.sh"
cat > "$RUNNER" <<EOF
#!/usr/bin/env bash
set -a; source "$CONF_DIR/agent.env"; set +a
cd "$REPO_DIR" && exec node misc/scripts/build_agent.mjs
EOF
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
	UNIT="$HOME/.config/systemd/user/godot-enhanced-build-agent.service"
	mkdir -p "$(dirname "$UNIT")"
	cat > "$UNIT" <<EOF
[Unit]
Description=godot-enhanced build agent
After=network-online.target
[Service]
ExecStart=$RUNNER
Restart=always
[Install]
WantedBy=default.target
EOF
	systemctl --user daemon-reload
	systemctl --user enable --now godot-enhanced-build-agent.service
	loginctl enable-linger "$USER" 2>/dev/null || sudo loginctl enable-linger "$USER" || true
fi

say "완료 — 에이전트 $BIND:$PORT"
echo "Windows 쪽 설정:  setx BUILD_AGENT_TOKEN $TOKEN"
echo "빌드 신호 예:     node misc/scripts/remote_build.mjs $(hostname -s) platform=$([ "$OS" = Darwin ] && echo macos || echo linuxbsd) target=editor"
echo "로그: $([ "$OS" = Darwin ] && echo "$CONF_DIR/agent.log" || echo "journalctl --user -u godot-enhanced-build-agent -f")"
