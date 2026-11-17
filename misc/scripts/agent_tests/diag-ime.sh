#!/usr/bin/env bash
# 진단: Linux IME 재현 도구 유무 (Xvfb·ibus·fcitx5·mozc·xdotool), 무암호 sudo 여부
cd "$(dirname "$0")/../../.."
for c in Xvfb xvfb-run ibus ibus-daemon fcitx5 xdotool xprop dbus-launch; do
	printf '%-12s %s\n' "$c" "$(command -v "$c" || echo '-')"
done
echo "mozc: $(ls /usr/lib/ibus-mozc /usr/lib/mozc /usr/lib/*/fcitx5/fcitx5-mozc.so 2>/dev/null | head -3 | tr '\n' ' ')"
echo "dpkg mozc: $(dpkg -l 2>/dev/null | awk '/mozc|ibus|fcitx5/ {print $2}' | tr '\n' ' ')"
echo "sudo -n: $(sudo -n true 2>/dev/null && echo yes || echo no)"
echo "os: $(. /etc/os-release 2>/dev/null; echo "$PRETTY_NAME")"
