#!/usr/bin/env bash
# iOS 시뮬레이터 C# 실행 검사 (Mac 에이전트)
#   iOS 템플릿(기기·시뮬레이터) → ios.zip → 표본 C# 프로젝트 내보내기
#   → xcodebuild(시뮬레이터, 서명 없음) → simctl 설치·실행 → 로그 `trim ok 3` 판정
#   GodotTrimGodotSharp = false(대조군), true 차례로
# 필요: Xcode, iOS 시뮬레이터 런타임, VulkanSDK(MoltenVK), .NET 11 SDK
set -euo pipefail
cd "$(dirname "$0")/../../.."
root=$(pwd)
work="${JOB_DIR:-/tmp}/ios-sim"; rm -rf "$work"; mkdir -p "$work"

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
mvk=$(ls -d "$HOME"/VulkanSDK/*/macOS/lib/MoltenVK.xcframework 2>/dev/null | tail -1 || true)
[ -n "$mvk" ] || { echo "✘ MoltenVK.xcframework 없음 (~/VulkanSDK)"; exit 1; }
cp -R "$mvk" "$t/"
(cd "$t" && zip -qr -y "$work/ios.zip" .)
# 내보내기는 기본 템플릿 위치를 확인함 → 같은 파일을 거기에도
tdir="$HOME/Library/Application Support/Godot/export_templates/$(python3 -c "import version as v; print(f'{v.major}.{v.minor}.{v.patch}')").stable.mono"
mkdir -p "$tdir"; cp "$work/ios.zip" "$tdir/ios.zip"

echo "── 시뮬레이터 준비"
# 런타임이 지원하는 iPhone 기종에서 고름
read -r rt dtype < <(xcrun simctl list runtimes -j | python3 -c '
import json, sys
for r in json.load(sys.stdin)["runtimes"]:
    if r.get("platform") == "iOS" and r.get("isAvailable"):
        ts = [t["identifier"] for t in r.get("supportedDeviceTypes", []) if "iPhone" in t["identifier"]]
        if ts:
            print(r["identifier"], ts[-1]); break
')
[ -n "${rt:-}" ] || { echo "✘ 쓸 수 있는 iOS 런타임·기종 없음"; exit 1; }
echo "런타임 $rt, 기종 $dtype"
udid=$(xcrun simctl create godot-trim-test "$dtype" "$rt")
trap 'xcrun simctl shutdown "$udid" >/dev/null 2>&1; xcrun simctl delete "$udid" >/dev/null 2>&1' EXIT
xcrun simctl boot "$udid"

# $1 = GodotTrimGodotSharp 값. 성공 = 로그에 trim ok 3
run_trim() {
	local trim=$1 w="$work/trim-$1"
	local p="$w/proj"; mkdir -p "$p" "$w/out"
	echo "── 표본 C# 프로젝트 (GodotTrimGodotSharp=$trim)"
	cat > "$p/nuget.config" <<EOF
<configuration><packageSources><add key="local" value="$root/bin/nuget" /></packageSources></configuration>
EOF
	cat > "$p/Game.csproj" <<EOF
<Project Sdk="Godot.NET.Sdk/$ver">
  <PropertyGroup><TargetFramework>net11.0</TargetFramework><EnableDynamicLoading>true</EnableDynamicLoading>
  <GodotTrimGodotSharp>$trim</GodotTrimGodotSharp></PropertyGroup>
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
		GD.PrintErr("trim ok ", Values.Length);
		System.Console.WriteLine("trim ok " + Values.Length);
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
application/bundle_identifier="org.godotenhanced.trim$trim"
application/min_ios_version="15.0"
EOF
	# C# 내보내기는 솔루션 파일 필요 (없으면 C# 부분이 빠진 채 내보냄)
	(cd "$p" && dotnet new sln -n Game --format sln >/dev/null && dotnet sln Game.sln add Game.csproj >/dev/null)
	"$exe" --headless --path "$p" --import >/dev/null 2>&1 || true
	"$exe" --headless --path "$p" --build-solutions --quit >/dev/null 2>&1 || true
	"$exe" --headless --path "$p" --export-debug iOS "$w/out/Game.ipa" >"$w/export.log" 2>&1 || true
	local proj; proj=$(ls -d "$w"/out/*.xcodeproj 2>/dev/null | head -1 || true)
	[ -n "$proj" ] || { echo "✘ [$trim] Xcode 프로젝트 내보내기 실패"; grep -v '^\s*$' "$w/export.log" | tail -30; return 1; }
	echo "[$trim] publish 폴더:"; for d in "$p"/.godot/mono/temp/bin/godot-publish-dotnet/*/; do echo "  $(basename "$d"): $(ls "$d" | tr '\n' ' ' | cut -c1-400)"; done
	echo "[$trim] Game.xcframework:"; find "$w/out/Game.xcframework" -type f -exec ls -l {} \; | awk '{print "  " $5, $NF}' | sed "s#$w/out/##"
	echo "[$trim] 내보내기 C#·dotnet 로그:"; grep -iE 'dotnet|publish|\.net|assembl|C#|error' "$w/export.log" | grep -v first_scan | head -15 || true

	xcodebuild -project "$proj" -scheme "$(basename "$proj" .xcodeproj)" -sdk iphonesimulator -configuration Debug -derivedDataPath "$w/dd" \
		-destination 'generic/platform=iOS Simulator' ARCHS=arm64 CODE_SIGNING_ALLOWED=NO build >"$w/xcodebuild.log" 2>&1 \
		|| { echo "✘ [$trim] xcodebuild 실패"; grep -E 'error:' "$w/xcodebuild.log" | head -20; return 1; }
	local app; app=$(find "$w/dd/Build/Products" -maxdepth 3 -name '*.app' | head -1 || true)
	[ -n "$app" ] || { echo "✘ [$trim] .app 없음"; return 1; }
	echo "[$trim] app $(du -sk "$app" | cut -f1) KB, Frameworks: $(ls "$app/Frameworks" 2>/dev/null | tr '\n' ' '), dotnet: $(find "$app" -iname '*game*' -o -iname '*.dylib' | sed "s#$app/##" | tr '\n' ' ')"

	xcrun simctl install "$udid" "$app"
	local bid; bid=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")
	perl -e 'alarm shift; exec @ARGV' 60 xcrun simctl launch --console-pty --terminate-running-process "$udid" "$bid" >"$w/run.log" 2>&1 || true
	# Godot iOS print → os_log 일 수 있음. 시스템 로그에서도 모음
	xcrun simctl spawn "$udid" log show --last 3m --style compact --predicate "process == \"Game\"" >"$w/syslog.log" 2>&1 || true
	echo "[$trim] Godot·.NET 관련 로그:"
	cat "$w/run.log" "$w/syslog.log" | grep -iE 'trim ok|godot|\.net|mono|dotnet|assembl|script|error|exception|crash|abort' | grep -viE 'coreaudio|gamecontroller|UIKit|FrontBoard' | head -30 || true
	cat "$w/run.log" "$w/syslog.log" | grep -q 'trim ok 3'
}

fail=0
for trim in false true; do
	if run_trim "$trim"; then echo "✔ [GodotTrimGodotSharp=$trim] trim ok 3"; else echo "✘ [GodotTrimGodotSharp=$trim] 실행 확인 실패"; fail=1; fi
done
exit $fail
