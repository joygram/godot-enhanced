#!/usr/bin/env bash
# Linux X11 IME 재현: Xvfb + fcitx5 + Mozc + xdotool 로 Godot LineEdit 에 일본어 입력
# 경우 A: fcitx5-remote 로 mozc 켜고 타이핑 / 경우 B: Ctrl+Space 로 켜고 타이핑
# 판정: Godot 출력 `IME_RESULT:` 줄에 히라가나 포함 → 통과
# 필요: bin/godot.*editor*, Xvfb, fcitx5, fcitx5-mozc, xdotool, dbus-launch
set -uo pipefail
cd "$(dirname "$0")/../../.."
editor=$(ls -t bin/godot.linuxbsd.editor.* 2>/dev/null | grep -v '\.\(zip\|o\|a\)$' | head -1 || true)
[ -n "$editor" ] || { echo "✘ 에디터 없음 (platform=linuxbsd target=editor 먼저 빌드)"; exit 1; }
chmod +x "$editor"
work="${JOB_DIR:-/tmp}/ime-linux"; rm -rf "$work"; mkdir -p "$work/proj" "$work/home/.config/fcitx5"
export HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config"

cat > "$XDG_CONFIG_HOME/fcitx5/profile" <<'EOF'
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=mozc

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=mozc
Layout=

[GroupOrder]
0=Default
EOF

cat > "$work/proj/main.gd" <<'EOF'
extends Control
func _ready() -> void:
	var le := LineEdit.new()
	le.size = Vector2(600, 40)
	add_child(le)
	le.grab_focus()
	le.text_changed.connect(func(t: String) -> void: print("IME_TEXT:", t))
	le.text_submitted.connect(func(t: String) -> void:
		print("IME_RESULT:", t)
		get_tree().quit())
	print("IME_READY")
func _notification(what: int) -> void:
	if what == NOTIFICATION_OS_IME_UPDATE:
		print("IME_PREEDIT:", DisplayServer.ime_get_text())
EOF
printf '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://main.gd" id="1"]\n\n[node name="Main" type="Control"]\nlayout_mode = 3\nanchors_preset = 15\nscript = ExtResource("1")\n' > "$work/proj/main.tscn"
printf 'config_version=5\n\n[application]\n\nconfig/name="ime-linux"\nrun/main_scene="res://main.tscn"\n\n[rendering]\n\nrenderer/rendering_method="gl_compatibility"\n' > "$work/proj/project.godot"
"$editor" --headless --path "$work/proj" --import >/dev/null 2>&1 || true

export DISPLAY=:77
Xvfb :77 -screen 0 1280x720x24 >/dev/null 2>&1 &
xvfb_pid=$!
eval "$(dbus-launch --sh-syntax)"
export XMODIFIERS=@im=fcitx GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx
fcitx5 -d --replace >"$work/fcitx5.log" 2>&1
sleep 3
cleanup() { pkill -P $$ 2>/dev/null; kill "$xvfb_pid" 2>/dev/null; fcitx5-remote -e 2>/dev/null; kill "$DBUS_SESSION_BUS_PID" 2>/dev/null; }
trap cleanup EXIT

run_case() {
	local name=$1 log="$work/$1.log"
	fcitx5-remote -s keyboard-us 2>/dev/null
	timeout 45 "$editor" --path "$work/proj" --display-driver x11 --rendering-driver opengl3 --verbose >"$log" 2>&1 &
	local gpid=$!
	for _ in $(seq 1 60); do grep -q IME_READY "$log" && break; sleep 0.5; done
	grep -q IME_READY "$log" || { echo "✘ [$name] 부팅 안 됨"; tail -20 "$log"; return 1; }
	local win; win=$(xdotool search --sync --limit 1 --name ime-linux)
	xdotool windowactivate --sync "$win" 2>/dev/null; xdotool windowfocus --sync "$win"
	sleep 1
	if [ "$name" = remote ]; then
		fcitx5-remote -s mozc
	else
		xdotool key --clearmodifiers ctrl+space
	fi
	sleep 1
	echo "[$name] fcitx5 현재 IM: $(fcitx5-remote -n 2>/dev/null) 상태: $(fcitx5-remote 2>/dev/null)"
	xdotool type --delay 120 nihongo
	sleep 1
	xdotool key Return; sleep 1; xdotool key Return
	wait "$gpid" 2>/dev/null
	echo "[$name] $(grep -E '^IME_(PREEDIT|TEXT|RESULT):' "$log" | tail -6 | tr '\n' ' ')"
	grep -E '^IME_RESULT:.*[ぁ-ん]' "$log" >/dev/null
}

fail=0
for c in remote ctrlspace; do
	if run_case "$c"; then echo "✔ [$c] 일본어 입력됨"; else echo "✘ [$c] 일본어 입력 안 됨"; fail=1; fi
done
echo "--- fcitx5.log"; tail -15 "$work/fcitx5.log"
exit $fail
