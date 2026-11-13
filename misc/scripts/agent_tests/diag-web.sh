#!/usr/bin/env bash
# 진단: 웹 의존성 설치 진행 상황 (돌고 있는 프로세스, 내려받은 파일 크기)
echo "── 프로세스"
ps -eo pid,etime,pcpu,command | grep -E 'emsdk|playwright|npm|curl|python.*emsdk|provision-web' | grep -v grep | cut -c1-200 || echo "(없음)"
echo "── ~/emsdk"
[ -d "$HOME/emsdk" ] && { (cd "$HOME/emsdk" && git log -1 --oneline 2>/dev/null); du -sh "$HOME/emsdk" 2>/dev/null; ls -la "$HOME/emsdk/downloads" 2>/dev/null | tail -5; cat "$HOME/emsdk/.emscripten" 2>/dev/null | head -3; ls "$HOME/emsdk/upstream" 2>/dev/null | head; } || echo "(없음)"
echo "── playwright 캐시"
ls -la "$HOME/Library/Caches/ms-playwright" "$HOME/.cache/ms-playwright" 2>/dev/null | tail -8
du -sh "$HOME/Library/Caches/ms-playwright" "$HOME/.cache/ms-playwright" 2>/dev/null
echo "── node/npm"
command -v node npm python3; node --version 2>&1; python3 --version 2>&1
echo "── 네트워크"
curl -sS -o /dev/null -w 'github %{http_code} %{time_total}s\n' https://github.com 2>&1
curl -sS -o /dev/null -w 'storage.googleapis %{http_code} %{time_total}s\n' https://storage.googleapis.com 2>&1
curl -sS -o /dev/null -w 'playwright cdn %{http_code} %{time_total}s\n' https://playwright.azureedge.net 2>&1
