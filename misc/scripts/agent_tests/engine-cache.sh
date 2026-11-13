#!/usr/bin/env bash
# 이 작업의 빌드 인자(SCONS_ARGS)로 엔진 빌드 캐시를 채워 릴리스에 올림 (misc/scripts/engine_cache.sh)
set -euo pipefail
cd "$(dirname "$0")/../../.."
[ -n "${SCONS_ARGS:-}" ] || { echo "✘ 빌드 인자 없음 (scons 인자와 함께 보낼 것)"; exit 1; }
platform="$(sed -nE 's/.*platform=([a-z]+).*/\1/p' <<<"$SCONS_ARGS")"
# cache_path 는 engine_cache.sh 가 정함
args="$(sed -E 's/(^| )cache_path=[^ ]*//' <<<"$SCONS_ARGS")"
# shellcheck disable=SC2086
bash misc/scripts/engine_cache.sh upload "$platform" $args
