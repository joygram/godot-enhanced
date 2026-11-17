#!/usr/bin/env bash
# GDScript 사전 빌드 동작 검사: 같은 기능 스크립트를 모드 2(압축 토큰)·3(사전 빌드)로 내보내 실행 → 출력 줄이 같아야 통과
# 기능: 상속·super, 내부 클래스, 정적 변수·함수, enum, const, 타입 배열·딕셔너리, setter/getter, 시그널,
#       람다·캡처, Callable, await, match, preload, 전역 클래스, 오토로드, 문자열 포맷, 예외 경로 없음
# 필요: bin/godot.linuxbsd.editor.x86_64
set -euo pipefail
cd "$(dirname "$0")/../../.."
editor=$(ls -t bin/godot.*.editor.* 2>/dev/null | grep -v '\.\(zip\|o\|a\|mono\|app\)$' | head -1 || true)
[ -n "$editor" ] || { echo "✘ 에디터 없음"; exit 1; }
chmod +x "$editor"
w="${JOB_DIR:-/tmp}/gdscript-prebuild"; rm -rf "$w"; p="$w/proj"; mkdir -p "$p"

cat > "$p/base.gd" <<'EOF'
class_name PbBase
extends RefCounted
signal changed(value: int)
enum Kind { A, B = 5, C }
const NAMES := ["zero", "one"]
static var created := 0
var hp: int = 10:
	set(v):
		hp = clampi(v, 0, 100)
		changed.emit(hp)
	get:
		return hp
func _init() -> void:
	created += 1
func describe() -> String:
	return "base hp=%d kind=%d" % [hp, Kind.B]
static func twice(x: int) -> int:
	return x * 2
EOF
cat > "$p/child.gd" <<'EOF'
class_name PbChild
extends PbBase
class Inner:
	var items: Array[int] = [3, 1, 2]
	func sorted() -> Array[int]:
		var c := items.duplicate()
		c.sort()
		return c
var tags: Dictionary[String, int] = {"a": 1}
func describe() -> String:
	return "child(" + super.describe() + ")"
func inner_sum() -> int:
	var total := 0
	for v in Inner.new().sorted():
		total += v
	return total
EOF
cat > "$p/auto.gd" <<'EOF'
extends Node
var counter := 7
func bump() -> int:
	counter += 1
	return counter
EOF
cat > "$p/main.gd" <<'EOF'
extends Node
const Base := preload("res://base.gd")
var log_lines: PackedStringArray = []
func out(s: String) -> void:
	print("PB ", s)
func _ready() -> void:
	var c := PbChild.new()
	var seen := []
	c.changed.connect(func(v): seen.append(v))
	c.hp = 250
	out("setter %d seen %s" % [c.hp, str(seen)])
	out(c.describe())
	out("inner %d" % c.inner_sum())
	out("static %d created %d" % [PbBase.twice(21), PbBase.created])
	out("enum %d %d const %s" % [PbBase.Kind.C, Base.Kind.A, PbBase.NAMES[1]])
	out("typed dict %s" % str(c.tags))
	var add := func(a: int, b: int) -> int: return a + b + c.hp
	out("lambda %d" % add.call(1, 2))
	var cb := Callable(c, "describe")
	out("callable %s" % cb.call())
	out("autoload %d" % Auto.bump())
	match c.hp:
		100: out("match hundred")
		_: out("match other")
	var arr: Array[String] = []
	for i in 3:
		arr.append(str(i * i))
	out("loop %s" % ",".join(arr))
	out("vector %s" % str(Vector2(3, 4).length()))
	await get_tree().process_frame
	out("await ok")
	out("done")
	get_tree().quit()
EOF
printf '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://main.gd" id="1"]\n\n[node name="Main" type="Node"]\nscript = ExtResource("1")\n' > "$p/main.tscn"
printf 'config_version=5\n\n[application]\n\nconfig/name="prebuild-test"\nrun/main_scene="res://main.tscn"\n\n[autoload]\n\nAuto="*res://auto.gd"\n' > "$p/project.godot"
"$editor" --headless --path "$p" --import >/dev/null 2>&1 || true

run_mode() {
	local mode=$1
	cat > "$p/export_presets.cfg" <<EOF
[preset.0]
name="Linux"
platform="Linux"
runnable=true
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path=""
script_export_mode=$mode
[preset.0.options]
EOF
	"$editor" --headless --path "$p" --export-pack Linux "$w/m$mode.pck" >"$w/export-$mode.log" 2>&1 || true
	[ -f "$w/m$mode.pck" ] || { echo "✘ 모드 $mode 내보내기 실패"; tail -5 "$w/export-$mode.log"; exit 1; }
	grep -h "GDScript prebuild" "$w/export-$mode.log" || true
	GODOT_GDSCRIPT_TIMINGS=1 timeout 30 "$editor" --headless --main-pack "$w/m$mode.pck" >"$w/run-$mode.log" 2>&1 || true
	grep '^PB ' "$w/run-$mode.log" >"$w/out-$mode.txt" || true
	echo "[모드 $mode] $(wc -l <"$w/out-$mode.txt") 줄, $(grep -m1 gdscript_timings "$w/run-$mode.log" || echo '계측 없음')"
	grep -E 'ERROR|SCRIPT ERROR' "$w/run-$mode.log" | head -5 || true
}
run_mode 2
run_mode 3
cat "$w/out-2.txt"
grep -q '^PB done$' "$w/out-2.txt" || { echo "✘ 기준(모드 2) 실행이 끝까지 안 감"; exit 1; }
if diff "$w/out-2.txt" "$w/out-3.txt" >"$w/diff.txt"; then
	echo "✔ gdscript-prebuild 통과 — 모드 3 출력이 모드 2와 같음"
else
	echo "✘ 출력 다름:"; cat "$w/diff.txt"; exit 1
fi
