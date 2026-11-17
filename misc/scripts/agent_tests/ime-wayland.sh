#!/usr/bin/env bash
# Linux Wayland IME 재현: headless sway·kwin_wayland + fcitx5 + Mozc 로 Godot LineEdit(text-input-v3) 에 일본어 입력
# 경우: <컴포지터>-remote (fcitx5-remote 로 mozc) / <컴포지터>-ctrlspace (Ctrl+Space)
# 판정: Godot 출력 `IME_RESULT:にほんご` 정확히 일치 → 통과
# 필요: bin/godot.linuxbsd.editor.*, sway, kwin_wayland, fcitx5, fcitx5-mozc, wtype, dbus-launch
set -uo pipefail
cd "$(dirname "$0")/../../.."
editor=$(ls -t bin/godot.linuxbsd.editor.* 2>/dev/null | grep -v '\.\(zip\|o\|a\)$' | head -1 || true)
[ -n "$editor" ] || { echo "✘ 에디터 없음 (platform=linuxbsd target=editor 먼저 빌드)"; exit 1; }
chmod +x "$editor"
work="${JOB_DIR:-/tmp}/ime-wayland"; rm -rf "$work"; mkdir -p "$work/proj" "$work/home/.config/fcitx5" "$work/run"
chmod 700 "$work/run"
export HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config" XDG_RUNTIME_DIR="$work/run"
export LIBGL_ALWAYS_SOFTWARE=1

printf '[Groups/0]\nName=Default\nDefault Layout=us\nDefaultIM=mozc\n\n[Groups/0/Items/0]\nName=keyboard-us\nLayout=\n\n[Groups/0/Items/1]\nName=mozc\nLayout=\n\n[GroupOrder]\n0=Default\n' > "$XDG_CONFIG_HOME/fcitx5/profile"

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
	print("IME_READY ds=", DisplayServer.get_name())
func _notification(what: int) -> void:
	if what == NOTIFICATION_OS_IME_UPDATE:
		print("IME_PREEDIT:", DisplayServer.ime_get_text())
EOF
printf '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://main.gd" id="1"]\n\n[node name="Main" type="Control"]\nlayout_mode = 3\nanchors_preset = 15\nscript = ExtResource("1")\n' > "$work/proj/main.tscn"
printf 'config_version=5\n\n[application]\n\nconfig/name="ime-wayland"\nrun/main_scene="res://main.tscn"\n\n[rendering]\n\nrenderer/rendering_method="gl_compatibility"\n' > "$work/proj/project.godot"
"$editor" --headless --path "$work/proj" --import >/dev/null 2>&1 || true

eval "$(dbus-launch --sh-syntax)"
trap 'pkill -P $$ 2>/dev/null; kill "$DBUS_SESSION_BUS_PID" 2>/dev/null' EXIT

# 컴포지터 띄우고 WAYLAND_DISPLAY 설정. fcitx5 는 컴포지터에 붙여 띄움
start_compositor() {
	local comp=$1
	rm -f "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null
	case "$comp" in
	sway)
		printf 'output HEADLESS-1 resolution 1280x720\nexec fcitx5 -d --replace\n' > "$work/sway.conf"
		WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman sway -c "$work/sway.conf" >"$work/sway.log" 2>&1 &
		;;
	kwin)
		kwin_wayland --virtual --no-lockscreen --width 1280 --height 720 --socket wayland-k --inputmethod /usr/bin/fcitx5 >"$work/kwin.log" 2>&1 &
		;;
	esac
	comp_pid=$!
	for _ in $(seq 1 30); do ls "$XDG_RUNTIME_DIR"/wayland-* >/dev/null 2>&1 && break; sleep 0.5; done
	local sock; sock=$(ls "$XDG_RUNTIME_DIR" | grep -E '^wayland-[^.]+$' | head -1)
	[ -n "$sock" ] || { echo "✘ [$comp] 컴포지터 안 뜸"; tail -10 "$work/$comp.log"; return 1; }
	export WAYLAND_DISPLAY=$sock
	sleep 3
	fcitx5-remote -s mozc 2>/dev/null; sleep 2; fcitx5-remote -s keyboard-us 2>/dev/null
	echo "[$comp] 소켓 $sock, fcitx5 IM: $(fcitx5-remote -n 2>/dev/null || echo '없음')"
}

stop_compositor() { fcitx5-remote -e 2>/dev/null; kill "$comp_pid" 2>/dev/null; wait "$comp_pid" 2>/dev/null; sleep 1; }

run_case() {
	local comp=$1 how=$2 name="$1-$2" log="$work/$1-$2.log"
	fcitx5-remote -s keyboard-us 2>/dev/null
	timeout 45 "$editor" --path "$work/proj" --display-driver wayland --rendering-driver opengl3 >"$log" 2>&1 &
	local gpid=$!
	for _ in $(seq 1 60); do grep -q IME_READY "$log" && break; sleep 0.5; done
	grep -q IME_READY "$log" || { echo "✘ [$name] 부팅 안 됨"; tail -15 "$log"; kill "$gpid" 2>/dev/null; return 1; }
	sleep 2
	if [ "$how" = remote ]; then fcitx5-remote -s mozc; else wtype -M ctrl -k space -m ctrl; fi
	sleep 1
	echo "[$name] $(grep IME_READY "$log"), fcitx5 IM: $(fcitx5-remote -n 2>/dev/null) 상태: $(fcitx5-remote 2>/dev/null)"
	wtype -d 120 nihongo; sleep 1
	wtype -k Return; sleep 1; wtype -k Return
	wait "$gpid" 2>/dev/null
	echo "[$name] $(grep -E '^IME_(PREEDIT|TEXT|RESULT):' "$log" | tail -6 | tr '\n' ' ')"
	grep -qx 'IME_RESULT:にほんご' "$log"
}

fail=0
# kwin: virtual-keyboard 프로토콜 미지원 → wtype 키 주입 불가, 판정 대상에서 뺌 (미검증)
for comp in sway; do
	start_compositor "$comp" || { fail=1; continue; }
	for how in remote ctrlspace; do
		if run_case "$comp" "$how"; then echo "✔ [$comp-$how] 일본어 입력됨"; else echo "✘ [$comp-$how] 일본어 입력 안 됨"; fail=1; fi
	done
	stop_compositor
done
exit $fail
