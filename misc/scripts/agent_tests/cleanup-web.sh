#!/usr/bin/env bash
# 정리: 남은 웹 의존성 설치 프로세스 종료, Playwright 잠금·반쯤 받은 브라우저 삭제
pkill -f 'playwright install' 2>/dev/null && echo "playwright install 종료" || true
pkill -f 'oopDownloadBrowserMain' 2>/dev/null || true
for p in $(pgrep -f 'provision-web.sh' || true); do [ "$p" = "$$" ] || kill "$p" 2>/dev/null || true; done
for c in "$HOME/Library/Caches/ms-playwright" "$HOME/.cache/ms-playwright"; do
	[ -d "$c" ] || continue
	rm -rf "$c/__dirlock"
	# 실행 파일 없는(반쯤 받은) 브라우저 폴더 삭제
	for d in "$c"/chromium-* "$c"/webkit-* "$c"/chromium_headless_shell-*; do
		[ -d "$d" ] || continue
		[ -f "$d/INSTALLATION_COMPLETE" ] || { rm -rf "$d"; echo "삭제: $d"; }
	done
done
echo "✔ cleanup-web 완료"
