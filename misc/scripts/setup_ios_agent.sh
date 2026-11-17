#!/usr/bin/env bash
# Mac 에이전트 iOS 준비: Xcode 설치(xcodes) → 선택·라이선스·첫 실행 → iOS 플랫폼(SDK·시뮬레이터) 받기
# 사용: bash misc/scripts/setup_ios_agent.sh   (Apple ID 로그인·sudo 암호 물어봄)
set -euo pipefail
cd "$(dirname "$0")/../.."

app=$(ls -d /Applications/Xcode*.app 2>/dev/null | head -1 || true)
if [ -z "$app" ]; then
	command -v brew >/dev/null || { echo "✘ Homebrew 없음 → https://brew.sh 설치 후 다시 실행"; exit 1; }
	command -v xcodes >/dev/null || brew install xcodesorg/made/xcodes
	command -v aria2c >/dev/null || brew install aria2
	echo "── Xcode 설치 (Apple ID 로그인 필요, 오래 걸림)"
	xcodes install --latest --experimental-unxip
	app=$(ls -d /Applications/Xcode*.app 2>/dev/null | head -1 || true)
	[ -n "$app" ] || { echo "✘ Xcode 설치 실패"; exit 1; }
fi
echo "── Xcode: $app"
sudo xcode-select -s "$app/Contents/Developer"
sudo xcodebuild -license accept
xcodebuild -runFirstLaunch
echo "── iOS 플랫폼 (SDK·시뮬레이터)"
xcodebuild -downloadPlatform iOS
echo "── 확인"
bash misc/scripts/agent_tests/diag-ios.sh
