#!/usr/bin/env bash
# 웹 메모리 검사: 이 머신의 에디터 + GDScript 웹 템플릿으로 시험 프로젝트를 내보내 headless Chrome 에서 측정
# 시험 프로젝트 = 서로 참조하는 GDScript 200개 (파서 해제 패치 효과가 드러나는 구조)
# 필요: bin/godot.*editor*, bin/godot.web.template_release.wasm32.nothreads.zip, Chrome, node
# 결과: $JOB_DIR/web-memory.json, web-memory.png
set -euo pipefail
cd "$(dirname "$0")/../../.."
root=$(pwd)
editor=$(ls -t bin/godot.*editor* 2>/dev/null | grep -v '\.\(zip\|o\|a\)$' | head -1 || true)
template=$(ls -t bin/godot.web.template_release.wasm32.nothreads.zip 2>/dev/null | head -1 || true)
[ -n "$editor" ] || { echo "✘ 에디터 없음 (target=editor 먼저 빌드)"; exit 1; }
[ -n "$template" ] || { echo "✘ 웹 템플릿 없음 (platform=web target=template_release threads=no 먼저 빌드)"; exit 1; }
chmod +x "$editor"
echo "에디터: $editor"; echo "템플릿: $template"

proj="$JOB_DIR/web-project"; out="$JOB_DIR/web-out"
rm -rf "$proj" "$out"; mkdir -p "$proj/s" "$out"
n=200
for i in $(seq 0 $((n - 1))); do
	next=$(( (i + 1) % n )); prev=$(( (i + n - 1) % n ))
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
	for entry in ProjectSettings.get_global_class_list():
		total += 1
		load(str(entry.path))
	print("boot ok classes=%d peak_static_mb=%.1f" % [total, Performance.get_monitor(Performance.MEMORY_STATIC_MAX) / 1048576.0])
EOF
printf '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://main.gd" id="1"]\n\n[node name="Main" type="Node"]\nscript = ExtResource("1")\n' > "$proj/main.tscn"
printf 'config_version=5\n\n[application]\n\nconfig/name="web-memory"\nrun/main_scene="res://main.tscn"\n' > "$proj/project.godot"
cat > "$proj/export_presets.cfg" <<EOF
[preset.0]
name="Web"
platform="Web"
runnable=true
export_filter="all_resources"
export_path=""
[preset.0.options]
custom_template/debug=""
custom_template/release="$root/$template"
variant/extensions_support=false
variant/thread_support=false
vram_texture_compression/for_desktop=true
html/export_icon=false
EOF

"$editor" --headless --path "$proj" --import >/dev/null 2>&1 || true
"$editor" --headless --path "$proj" --export-release Web "$out/index.html" 2>&1 | grep -E '^(ERROR|WARNING: .*export)' || true
[ -f "$out/index.wasm" ] || { echo "✘ 내보내기 실패"; exit 1; }
node misc/scripts/web_memory.mjs "$out" "${WEB_MEMORY_SECONDS:-30}" "$JOB_DIR/web-memory.json"
echo "✔ web-memory 통과"
