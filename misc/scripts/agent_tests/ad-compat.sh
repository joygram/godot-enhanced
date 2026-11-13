#!/usr/bin/env bash
# 광고 호환 검사 (이 머신 브라우저: 맥 = Safari, 리눅스 = Chromium). 결과: $JOB_DIR/ad-compat.json
set -euo pipefail
cd "$(dirname "$0")/../../.."
node misc/scripts/ad_compat.mjs "$JOB_DIR/ad-compat.json"
