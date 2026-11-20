#!/usr/bin/env bash
# 빌드 에이전트: C# 편집기 빌드 뒤 glue + GodotSharp·NuGet (C# 웹 템플릿 빌드 전제, 작업 사이 저장소에 남음)
set -euo pipefail
cd "$(dirname "$0")/../../.."
exe=$(ls bin/godot.*.editor.*.mono 2>/dev/null | head -1)
[ -x "$exe" ] || { echo "✘ C# 편집기 없음: bin/godot.*.editor.*.mono"; exit 1; }
"$exe" --headless --version
"$exe" --headless --quit --generate-mono-glue modules/mono/glue
rm -rf bin/nuget
python3 modules/mono/build_scripts/build_assemblies.py --godot-output-dir=./bin --push-nupkgs-local ./bin/nuget
echo "✔ glue·GodotSharp·NuGet"
