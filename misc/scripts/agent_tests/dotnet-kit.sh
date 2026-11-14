#!/usr/bin/env bash
# 빌드 에이전트: C# 편집기 빌드 뒤 C# 키트 만들어 릴리스에 올림 (misc/scripts/dotnet_kit.sh)
set -euo pipefail
cd "$(dirname "$0")/../../.."
bash misc/scripts/dotnet_kit.sh
