#!/usr/bin/env bash
# iOS 시뮬레이터 C# 실행 검사 (Mac 에이전트)
#   iOS 템플릿(기기·시뮬레이터) → ios.zip → 표본 C# 프로젝트 내보내기(GodotTrimGodotSharp=true)
#   → xcodebuild(시뮬레이터, 서명 없음) → simctl 설치·실행 → 로그 `trim ok 3` 판정
# 필요: Xcode, iOS 시뮬레이터 런타임, VulkanSDK(MoltenVK), .NET 11 SDK
set -euo pipefail
cd "$(dirname "$0")/../../.."
root=$(pwd)
work="${JOB_DIR:-/tmp}/ios-sim"; rm -rf "$work"; mkdir -p "$work"
TRIM="${IOS_TRIM:-true}"

echo "── 엔진 빌드 (캐시)"
exe=$(ls bin/godot.macos.editor.arm64.mono 2>/dev/null || true)
[ -n "$exe" ] || scons platform=macos target=editor arch=arm64 module_mono_enabled=yes >/dev/null
exe=bin/godot.macos.editor.arm64.mono
for sim in no yes; do
	scons platform=ios target=template_debug arch=arm64 simulator=$sim module_mono_enabled=yes >/dev/null
done
dev_lib=bin/libgodot.ios.template_debug.arm64.a
sim_lib=bin/libgodot.ios.template_debug.arm64.simulator.a
[ -f "$dev_lib" ] && [ -f "$sim_lib" ] || { echo "✘ iOS 템플릿 라이브러리 없음"; ls bin; exit 1; }

echo "── glue·어셈블리·NuGet"
"$exe" --headless --quit --generate-mono-glue modules/mono/glue >/dev/null 2>&1
python3 modules/mono/build_scripts/build_assemblies.py --godot-output-dir=./bin --push-nupkgs-local ./bin/nuget >/dev/null
ver=$(basename "$(ls bin/nuget/Godot.NET.Sdk.*.nupkg | head -1)" .nupkg); ver=${ver#Godot.NET.Sdk.}
rm -rf "$HOME/.nuget/packages/godot.net.sdk/$ver" "$HOME/.nuget/packages/godotsharp/$ver" "$HOME/.nuget/packages/godot.sourcegenerators/$ver"

echo "── ios.zip"
t="$work/tpl"; cp -R misc/dist/apple_embedded_xcode "$t"
cp "$dev_lib" "$t/libgodot.ios.debug.xcframework/ios-arm64/libgodot.a"
cp "$sim_lib" "$t/libgodot.ios.debug.xcframework/ios-arm64_x86_64-simulator/libgodot.a"
cp "$t/libgodot.ios.debug.xcframework/ios-arm64/libgodot.a" "$t/libgodot.ios.release.xcframework/ios-arm64/libgodot.a"
cp "$t/libgodot.ios.debug.xcframework/ios-arm64_x86_64-simulator/libgodot.a" "$t/libgodot.ios.release.xcframework/ios-arm64_x86_64-simulator/libgodot.a"
mvk=$(ls -d "$HOME"/VulkanSDK/*/macOS/lib/MoltenVK.xcframework 2>/dev/null | tail -1)
[ -n "$mvk" ] || { echo "✘ MoltenVK.xcframework 없음 (~/VulkanSDK)"; exit 1; }
cp -R "$mvk" "$t/"
(cd "$t" && zip -qr -y "$work/ios.zip" .)
# 내보내기는 기본 템플릿 위치를 확인함 → 같은 파일을 거기에도
tdir="$HOME/Library/Application Support/Godot/export_templates/$(python3 -c "import version as v; print(f'{v.major}.{v.minor}.{v.patch}')").stable.mono"
mkdir -p "$tdir"; cp "$work/ios.zip" "$tdir/ios.zip"

echo "── 표본 C# 프로젝트 (GodotTrimGodotSharp=$TRIM)"
p="$work/proj"; mkdir -p "$p"
cat > "$p/nuget.config" <<EOF
<configuration><packageSources><add key="local" value="$root/bin/nuget" /></packageSources></configuration>
EOF
cat > "$p/Game.csproj" <<EOF
<Project Sdk="Godot.NET.Sdk/$ver">
  <PropertyGroup><TargetFramework>net11.0</TargetFramework><EnableDynamicLoading>true</EnableDynamicLoading>
  <GodotTrimGodotSharp>$TRIM</GodotTrimGodotSharp></PropertyGroup>
</Project>
EOF
cat > "$p/Main.cs" <<'EOF'
using Godot;
public partial class Main : Node
{
	[Export] public int[] Values = { 1, 2, 3 };
	public override void _Ready()
	{
		GD.Print("trim ok ", Values.Length);
		GetTree().Quit();
	}
}
EOF
# 아이콘 (없으면 iOS 아이콘 내보내기 실패): 1024×1024 단색 PNG
python3 - "$p/icon.png" <<'PY'
import struct, sys, zlib
w = h = 1024
raw = b"".join(b"\x00" + b"\x47\x8c\xbf" * w for _ in range(h))
def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
open(sys.argv[1], "wb").write(png)
PY
printf '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://Main.cs" id="1"]\n\n[node name="Main" type="Node"]\nscript = ExtResource("1")\n' > "$p/main.tscn"
printf 'config_version=5\n\n[application]\n\nconfig/name="Game"\nrun/main_scene="res://main.tscn"\nconfig/icon="res://icon.png"\n\n[dotnet]\n\nproject/assembly_name="Game"\n\n[rendering]\n\nrenderer/rendering_method="gl_compatibility"\nrenderer/rendering_method.mobile="gl_compatibility"\ntextures/vram_compression/import_etc2_astc=true\n' > "$p/project.godot"
cat > "$p/export_presets.cfg" <<EOF
[preset.0]
name="iOS"
platform="iOS"
runnable=true
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path=""
[preset.0.options]
custom_template/debug="$work/ios.zip"
custom_template/release="$work/ios.zip"
application/export_project_only=true
application/app_store_team_id="ABCDE12345"
application/bundle_identifier="org.godotenhanced.trimtest"
application/min_ios_version="15.0"
EOF
"$exe" --headless --path "$p" --import >/dev/null 2>&1 || true
"$exe" --headless --path "$p" --build-solutions --quit >/dev/null 2>&1 || true
mkdir -p "$work/out"
"$exe" --headless --path "$p" --export-debug iOS "$work/out/Game.ipa" >"$work/export.log" 2>&1 || true
proj=$(ls -d "$work"/out/*.xcodeproj 2>/dev/null | head -1 || true)
[ -n "$proj" ] || { echo "✘ Xcode 프로젝트 내보내기 실패"; grep -v '^\s*$' "$work/export.log" | tail -40; exit 1; }
echo "xcodeproj: $proj"
echo "── 내보내기 로그 (끝)"; grep -v '^\s*$' "$work/export.log" | grep -v first_scan | tail -25
echo "── xcodeproj 내용"; ls -la "$proj" "$work/out"

echo "── xcodebuild (시뮬레이터)"
scheme=$(basename "$proj" .xcodeproj)
xcodebuild -project "$proj" -scheme "$scheme" -sdk iphonesimulator -configuration Debug -derivedDataPath "$work/dd" \
	-destination 'generic/platform=iOS Simulator' ARCHS=arm64 CODE_SIGNING_ALLOWED=NO build >"$work/xcodebuild.log" 2>&1 \
	|| { echo "✘ xcodebuild 실패"; grep -E 'error:' "$work/xcodebuild.log" | head -20; exit 1; }
app=$(find "$work/dd/Build/Products" -maxdepth 3 -name '*.app' | head -1 || true)
[ -n "$app" ] || { echo "✘ .app 없음"; exit 1; }
echo "app: $app ($(du -sk "$app" | cut -f1) KB)"

echo "── 시뮬레이터 실행"
dtype=$(xcrun simctl list devicetypes | grep -o 'com.apple.CoreSimulator.SimDeviceType.iPhone-[^)]*' | tail -1)
rt=$(xcrun simctl list runtimes | grep -o 'com.apple.CoreSimulator.SimRuntime.iOS-[^ ]*' | head -1)
udid=$(xcrun simctl create godot-trim-test "$dtype" "$rt")
trap 'xcrun simctl shutdown "$udid" >/dev/null 2>&1; xcrun simctl delete "$udid" >/dev/null 2>&1' EXIT
xcrun simctl boot "$udid"
xcrun simctl install "$udid" "$app"
bid=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")
perl -e 'alarm shift; exec @ARGV' 90 xcrun simctl launch --console-pty "$udid" "$bid" >"$work/run.log" 2>&1 || true
grep -E 'trim ok|ERROR|Exception|exception' "$work/run.log" | head -20
grep -q 'trim ok 3' "$work/run.log" || { echo "✘ 실행 로그에 trim ok 3 없음"; tail -30 "$work/run.log"; exit 1; }
echo "✔ ios-sim-csharp 통과 (GodotTrimGodotSharp=$TRIM)"
