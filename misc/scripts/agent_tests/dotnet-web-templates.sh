#!/usr/bin/env bash
# 빌드 에이전트(Linux): C# 웹 템플릿 4종 → 릴리스 dotnet-web-<버전> (CI enhanced_dotnet_release.yml web-templates 와 같은 구성)
#   전제: 이 작업에서 C# 편집기 빌드 (platform=linuxbsd target=editor module_mono_enabled=yes), .NET 11 SDK + wasm-tools, emsdk
#   순서: glue → C# 어셈블리·NuGet → 템플릿 release·debug × threads·nothreads → 업로드
set -euo pipefail
cd "$(dirname "$0")/../../.."
godot=$(python3 -c "import version as v; print(f'{v.major}.{v.minor}.{v.patch}')")
version="$godot-$(tr -d '[:space:]' < ENHANCED_VERSION)"
tag="dotnet-web-$version"
repo="$(git remote get-url origin | sed -E 's#(\.git)?$##; s#.*github\.com[:/]##')"
exe=$(ls bin/godot.linuxbsd.editor.*.mono | head -1)
[ -x "$exe" ] || { echo "✘ C# 편집기 없음: bin/godot.linuxbsd.editor.*.mono"; exit 1; }
[ -f "$HOME/emsdk/emsdk_env.sh" ] && source "$HOME/emsdk/emsdk_env.sh" >/dev/null
"$exe" --headless --version

echo "── glue"
"$exe" --headless --quit --generate-mono-glue modules/mono/glue
echo "── C# 어셈블리·NuGet"
rm -rf bin/nuget
python3 modules/mono/build_scripts/build_assemblies.py --godot-output-dir=./bin --push-nupkgs-local ./bin/nuget

jobs=$(nproc)
out=()
for spec in "template_release:lto=full:" "template_debug:lto=thin:" "template_release:lto=full threads=no:.nothreads" "template_debug:lto=thin threads=no:.nothreads"; do
	IFS=: read -r target flags suffix <<< "$spec"
	echo "── $target$suffix"
	scons platform=web target=$target module_mono_enabled=yes optimize=speed $flags ccflags="-DNDEBUG" linkflags="-sMALLOC=mimalloc" -j"$jobs"
	out+=("bin/godot.web.$target.wasm32$suffix.mono.zip")
done

gh release view "$tag" -R "$repo" >/dev/null 2>&1 || gh release create "$tag" -R "$repo" --target "$(git rev-parse HEAD)" \
	--title "C# web export kit $version (godot-enhanced)" --notes "C# (.NET 11) editor + GodotSharp + NuGet + web templates, per platform."
gh release upload "$tag" -R "$repo" "${out[@]}" --clobber
echo "✔ 올림: $tag ← ${out[*]}"
