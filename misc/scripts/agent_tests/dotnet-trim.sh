#!/usr/bin/env bash
# C# 트리밍 검사 (기기 실행 없음, 빌드·크기만)
#   Linux: 플랫폼별 PublishTrimmed 평가 + android-arm64 publish 트리밍 끔/켬 크기 비교
#   macOS: ios-arm64 NativeAOT publish, GodotSharp 통째 유지(기본) / 트리밍(GodotTrimGodotSharp=true) 크기 비교
# 필요: C# 편집기 bin/godot.<linuxbsd|macos>.editor.*.mono, .NET 11 SDK, (macOS) Xcode
set -euo pipefail
cd "$(dirname "$0")/../../.."
root=$(pwd)
command -v dotnet >/dev/null || { echo "✘ dotnet 없음 (.NET 11 SDK 설치 필요)"; exit 1; }
dotnet --list-sdks | grep -q '^11\.' || { echo "✘ .NET 11 SDK 없음: $(dotnet --list-sdks | tr '\n' ' ')"; exit 1; }
case "$(uname -s)" in Darwin) os=macos ;; *) os=linuxbsd ;; esac
exe=$(ls bin/godot.$os.editor.*.mono 2>/dev/null | head -1 || true)
[ -n "$exe" ] || { echo "✘ C# 편집기 없음 (target=editor module_mono_enabled=yes 먼저 빌드)"; exit 1; }
size() { wc -c < "$1" | tr -d ' '; }
py=$(command -v python3)
echo "── glue·어셈블리·NuGet"
"$exe" --headless --quit --generate-mono-glue modules/mono/glue >/dev/null 2>&1
rm -rf bin/nuget
"$py" modules/mono/build_scripts/build_assemblies.py --godot-output-dir=./bin --push-nupkgs-local ./bin/nuget >/dev/null
sdk=$(ls bin/nuget/Godot.NET.Sdk.*.nupkg | head -1); ver=$(basename "$sdk" .nupkg); ver=${ver#Godot.NET.Sdk.}
echo "Godot.NET.Sdk $ver"
# 같은 버전 번호로 캐시된 옛 패키지를 쓰지 않게 비움
rm -rf "$HOME/.nuget/packages/godot.net.sdk/$ver" "$HOME/.nuget/packages/godotsharp/$ver" "$HOME/.nuget/packages/godot.sourcegenerators/$ver"

work="${JOB_DIR:-/tmp}/trim"; rm -rf "$work"; mkdir -p "$work/p"
cat > "$work/p/nuget.config" <<EOF
<configuration><packageSources><clear /><add key="local" value="$root/bin/nuget" /><add key="nuget.org" value="https://api.nuget.org/v3/index.json" /></packageSources></configuration>
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
prop() { dotnet msbuild -getProperty:PublishTrimmed -p:RuntimeIdentifier=$1 -p:Configuration=ExportRelease 2>/dev/null | tr -d '\r'; }

if [ "$os" = linuxbsd ]; then
	echo "── PublishTrimmed 평가 (기대: web·android true, linux 빈 값)"
	for rid in browser-wasm android-arm64 ios-arm64 linux-x64; do echo "  $rid: '$(prop $rid)'"; done
	for rid in browser-wasm android-arm64; do [ "$(prop $rid)" = true ] || { echo "✘ $rid 트리밍 기본값 아님"; exit 1; }; done
	[ "$(prop linux-x64)" != true ] || { echo "✘ linux-x64 가 트리밍됨 (범위 밖)"; exit 1; }
	echo "── android-arm64 publish"
	for m in false true; do
		dotnet publish -c ExportRelease -r android-arm64 --self-contained -p:PublishTrimmed=$m -o "$work/out-$m" -v q -nologo
		o="$work/out-$m"
		echo "  PublishTrimmed=$m: 전체 $(du -sk "$o" | cut -f1) KB, dll $(cat "$o"/*.dll | wc -c | awk '{printf "%.1f", $1/1048576}') MB, GodotSharp.dll $(size "$o/GodotSharp.dll") B, Game.dll $(size "$o/Game.dll") B"
	done
	[ "$(size "$work/out-true/GodotSharp.dll")" -lt "$(size "$work/out-false/GodotSharp.dll")" ] || { echo "✘ GodotSharp 안 줄어듦"; exit 1; }

	# Android NativeAOT (linux-bionic): SDK 설정만으로 (내보내기 플러그인과 같은 속성) .so + 진입 심볼
	ndk=$(ls -d "${ANDROID_NDK_ROOT:-}" "$HOME"/Android/Sdk/ndk/* 2>/dev/null | tail -1 || true)
	if [ -n "$ndk" ]; then
		echo "── linux-bionic-arm64 NativeAOT (NDK $(basename "$ndk"))"
		rm -rf obj bin
		echo "  평가: $(dotnet msbuild -p:RuntimeIdentifier=linux-bionic-arm64 -p:GodotTargetPlatform=android -p:Configuration=ExportRelease -getProperty:PublishAot -getProperty:UseMonoRuntime -getProperty:GodotAndroidNativeAot -getProperty:CppCompilerAndLinker 2>&1 | tr -d '\n ')"
		dotnet publish -c ExportRelease -r linux-bionic-arm64 -p:GodotTargetPlatform=android -p:GodotAndroidNdkPath="$ndk" -p:PublishAot=true -o "$work/out-aot" -v q -nologo
		so=$(ls "$work"/out-aot/*Game.so 2>/dev/null | head -1 || true)
		[ -n "$so" ] || { echo "✘ Game .so 없음: $(ls "$work/out-aot" | tr '\n' ' ')"; exit 1; }
		nm="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-nm"
		echo "  $(basename "$so") $(size "$so") B, $(file -b "$so" | cut -d, -f1-2)"
		"$nm" -D --defined-only "$so" | grep -q godotsharp_game_main_init || { echo "✘ godotsharp_game_main_init 심볼 없음"; exit 1; }
		echo "  진입 심볼 godotsharp_game_main_init ✔"
	else
		echo "(Android NDK 없음 → NativeAOT 검사 생략)"
	fi
else
	echo "── ios-arm64 NativeAOT publish (Xcode: $(xcode-select -p))"
	for m in false true; do
		dotnet publish -c ExportRelease -r ios-arm64 -p:GodotTrimGodotSharp=$m -o "$work/out-$m" -v q -nologo
		o="$work/out-$m"
		ls -la "$o"
		bin=$(ls -S "$o"/*.dylib "$o"/*.a 2>/dev/null | head -1 || true)
		[ -n "$bin" ] || { echo "✘ 바이너리 못 찾음"; exit 1; }
		echo "  GodotTrimGodotSharp=$m: 전체 $(du -sk "$o" | cut -f1) KB, 바이너리 $(basename "$bin") $(size "$bin") B"
		echo "$bin" > "$work/bin-$m"
	done
	[ "$(size "$(cat "$work/bin-true")")" -lt "$(size "$(cat "$work/bin-false")")" ] || { echo "✘ iOS 바이너리 안 줄어듦"; exit 1; }
fi
echo "✔ dotnet-trim 통과 ($os)"
