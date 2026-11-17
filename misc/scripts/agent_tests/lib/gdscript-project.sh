#!/usr/bin/env bash
# 공용: 서로 참조하는 GDScript N 개 시험 프로젝트 생성 (web-memory·gdscript-boot 가 같이 씀)
# 사용: make_gdscript_project <폴더> [N=200]
# main.gd 가 부팅 시 모든 전역 클래스를 load → 출력 `boot ok classes=<N> ms=<부팅 ms> peak_static_mb=<MB>`
make_gdscript_project() {
	local proj=$1 n=${2:-200}
	rm -rf "$proj"; mkdir -p "$proj/s"
	for i in $(seq 0 $((n - 1))); do
		local next=$(( (i + 1) % n )) prev=$(( (i + n - 1) % n ))
		cat > "$proj/s/c$i.gd" <<EOF
class_name C$i
extends RefCounted
var next_ref: C$next
var prev_ref: C$prev
var data: Dictionary = {"id": $i, "name": "c$i"}
func value(depth: int) -> int:
	if depth <= 0: return $i
	var a := [1, 2, 3, $i]
	for k in range(4): a.append(k * $i)
	return a.size() + depth
func describe() -> String:
	return "C%d -> C%d" % [$i, $next]
EOF
	done
	cat > "$proj/main.gd" <<'EOF'
extends Node
func _ready() -> void:
	var total := 0
	var t0 := Time.get_ticks_usec()
	for entry in ProjectSettings.get_global_class_list():
		total += 1
		load(str(entry.path))
	var load_ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("boot ok classes=%d ms=%d load_ms=%.1f peak_static_mb=%.1f" % [total, Time.get_ticks_msec(), load_ms, Performance.get_monitor(Performance.MEMORY_STATIC_MAX) / 1048576.0])
	if "--bench-quit" in OS.get_cmdline_user_args():
		get_tree().quit()
EOF
	printf '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://main.gd" id="1"]\n\n[node name="Main" type="Node"]\nscript = ExtResource("1")\n' > "$proj/main.tscn"
	printf 'config_version=5\n\n[application]\n\nconfig/name="gdscript-bench"\nrun/main_scene="res://main.tscn"\n' > "$proj/project.godot"
}
