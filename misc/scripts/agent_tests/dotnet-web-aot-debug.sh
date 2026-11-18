#!/usr/bin/env bash
# dotnet-web-aot 의 함수 이름 판 (debug_symbols=yes, lto=none) → 릴리스 web-aot-debug. 스택 추적용
set -euo pipefail
AOT_DEBUG=1 bash "$(dirname "$0")/dotnet-web-aot.sh"
