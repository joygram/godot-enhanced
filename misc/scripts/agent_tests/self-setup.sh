#!/usr/bin/env bash
# 에이전트 자기 재설치: 원격 터미널 없이 도구(mise·emsdk·.NET) 갱신 → 끝나면 에이전트 재시작
# 환경: WITH_EMSDK, WITH_DOTNET, EMSDK_VERSION 그대로 전달
set -euo pipefail
cd "$(dirname "$0")/../../.."
SKIP_SERVICE=1 WITH_EMSDK="${WITH_EMSDK:-1}" WITH_DOTNET="${WITH_DOTNET:-0}" bash misc/scripts/setup_build_agent.sh
touch "$JOB_DIR/.restart"
echo "✔ self-setup 완료 → 에이전트 재시작"
