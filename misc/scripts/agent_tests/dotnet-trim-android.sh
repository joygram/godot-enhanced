#!/usr/bin/env bash
# C# 트리밍 검사: 플랫폼별 PublishTrimmed 평가 + android-arm64 publish 트리밍 끔/켬 크기 비교
# 필요: bin/godot.linuxbsd.editor.x86_64.mono (scons target=editor module_mono_enabled=yes), dotnet SDK
# 기기 실행은 안 함 (빌드·크기만)
set -euo pipefail
cd "$(dirname "$0")/../../.."
root=$(pwd)
command -v dotnet >/dev/null || { echo "✘ dotnet 없음 (.NET 11 SDK 설치 필요)"; exit 1; }
dotnet --list-sdks | grep -q '^11\.' || { echo "✘ .NET 11 SDK 없음: $(dotnet --list-sdks | tr '\n' ' ')"; exit 1; }
exe=$(ls bin/godot.linuxbsd.editor.*.mono 2>/dev/null | head -1 || true)
[ -n "$exe" ] || { echo "✘ C# 편집기 없음 (target=editor module_mono_enabled=yes 먼저 빌드)"; exit 1; }
py=$(command -v python3)
echo "── glue·어셈블리·NuGet"
"$exe" --headless --quit --generate-mono-glue modules/mono/glue >/dev/null 2>&1
rm -rf bin/nuget
"$py" modules/mono/build_scripts/build_assemblies.py --godot-output-dir=./bin --push-nupkgs-local ./bin/nuget >/dev/null
sdk=$(ls bin/nuget/Godot.NET.Sdk.*.nupkg | head -1); ver=$(basename "$sdk" .nupkg); ver=${ver#Godot.NET.Sdk.}
echo "Godot.NET.Sdk $ver"

work="${JOB_DIR:-/tmp}/trim-android"; rm -rf "$work"; mkdir -p "$work/p"
cat > "$work/p/nuget.config" <<EOF
<configuration><packageSources><add key="local" value="$root/bin/nuget" /></packageSources></configuration>
EOF
cat > "$work/p/Game.csproj" <<EOF
<Project Sdk="Godot.NET.Sdk/$ver">
  <PropertyGroup><TargetFramework>net11.0</TargetFramework><EnableDynamicLoading>true</EnableDynamicLoading></PropertyGroup>
</Project>
EOF
cat > "$work/p/Main.cs" <<'EOF'
using Godot;
public partial class Main : Node
{
	[Export] public int[] Values = { 1, 2, 3 };
	public override void _Ready() => GD.Print("trim ok ", Values.Length);
}
EOF
cd "$work/p"
echo "── PublishTrimmed 평가 (기대: web·android true, ios/linux 기본값)"
for rid in browser-wasm android-arm64 ios-arm64 linux-x64; do
	echo "  $rid: '$(dotnet msbuild -getProperty:PublishTrimmed -p:RuntimeIdentifier=$rid -p:Configuration=ExportRelease 2>/dev/null | tr -d '\r')'"
done
for rid in browser-wasm android-arm64; do
	[ "$(dotnet msbuild -getProperty:PublishTrimmed -p:RuntimeIdentifier=$rid -p:Configuration=ExportRelease 2>/dev/null | tr -d '\r')" = true ] || { echo "✘ $rid 트리밍 기본값 아님"; exit 1; }
done
[ "$(dotnet msbuild -getProperty:PublishTrimmed -p:RuntimeIdentifier=linux-x64 -p:Configuration=ExportRelease 2>/dev/null | tr -d '\r')" != true ] || { echo "✘ linux-x64 가 트리밍됨 (범위 밖)"; exit 1; }

echo "── android-arm64 publish"
pub() { dotnet publish -c ExportRelease -r android-arm64 --self-contained -p:PublishTrimmed=$1 -o "$work/out-$1" -v q -nologo; }
pub false; pub true
for m in false true; do
	o="$work/out-$m"
	echo "  PublishTrimmed=$m: 전체 $(du -sk "$o" | cut -f1) KB, dll $(cat "$o"/*.dll | wc -c | awk '{printf "%.1f", $1/1048576}') MB, GodotSharp.dll $(stat -c%s "$o/GodotSharp.dll") B, Game.dll $(stat -c%s "$o/Game.dll") B"
done
[ "$(stat -c%s "$work/out-true/GodotSharp.dll")" -lt "$(stat -c%s "$work/out-false/GodotSharp.dll")" ] || { echo "✘ GodotSharp 안 줄어듦"; exit 1; }
echo "✔ dotnet-trim-android 통과"
