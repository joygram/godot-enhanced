#!/usr/bin/env bash
# 진단: 에이전트 머신의 버전 계산·환경 확인
cd "$(dirname "$0")/../../.."
echo "pwd: $(pwd)"
echo "HEAD: $(git rev-parse --short=10 HEAD)"
echo "ENHANCED_VERSION: $(cat ENHANCED_VERSION 2>&1)"
echo "BUILD_NAME env: ${BUILD_NAME-<unset>}"
echo "python3: $(command -v python3) $(python3 --version 2>&1)"
echo "scons: $(command -v scons)"
head -1 "$(command -v scons)" 2>/dev/null | sed 's/^/scons shebang: /'
python3 -c "import methods; print('get_version_info.build =', methods.get_version_info(silent=True)['build'])" 2>&1
grep -h 'BUILD' core/version_generated.gen.h 2>/dev/null | head -3
