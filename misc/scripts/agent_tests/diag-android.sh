#!/usr/bin/env bash
# 진단: Android C# NativeAOT 도구 (SDK·NDK·Java) + 표본 프로젝트 android-arm64 PublishAot 시도
cd "$(dirname "$0")/../../.."
root=$(pwd)
echo "ANDROID_HOME=${ANDROID_HOME:-} ANDROID_SDK_ROOT=${ANDROID_SDK_ROOT:-} ANDROID_NDK_ROOT=${ANDROID_NDK_ROOT:-}"
for d in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Android/Sdk" "$HOME/android-sdk" /opt/android-sdk /usr/lib/android-sdk; do
	[ -n "$d" ] && [ -d "$d" ] && echo "sdk: $d → ndk: $(ls "$d/ndk" 2>/dev/null | tr '\n' ' ') build-tools: $(ls "$d/build-tools" 2>/dev/null | tr '\n' ' ')"
done
echo "찾기 (ndk·cmdline-tools·sdkmanager):"
find / -xdev -maxdepth 6 \( -type d \( -name ndk -o -name cmdline-tools -o -name platform-tools \) -o -name sdkmanager \) 2>/dev/null | grep -v '/proc/' | head -20
echo "java: $(command -v java) $(java -version 2>&1 | head -1)"
echo "sdkmanager: $(command -v sdkmanager || echo -)"
echo "dotnet workloads: $(dotnet workload list 2>/dev/null | tail -n +4 | tr '\n' ' ')"
ver=$(basename "$(ls bin/nuget/Godot.NET.Sdk.*.nupkg 2>/dev/null | head -1)" .nupkg); ver=${ver#Godot.NET.Sdk.}
[ -n "$ver" ] || { echo "(bin/nuget 없음 → publish 시도 생략)"; exit 0; }
w="${JOB_DIR:-/tmp}/aot-android"; rm -rf "$w"; mkdir -p "$w"
cat > "$w/nuget.config" <<EOF
<configuration><packageSources><clear /><add key="local" value="$root/bin/nuget" /><add key="nuget.org" value="https://api.nuget.org/v3/index.json" /></packageSources></configuration>
EOF
printf '<Project Sdk="Godot.NET.Sdk/%s"><PropertyGroup><TargetFramework>net11.0</TargetFramework><EnableDynamicLoading>true</EnableDynamicLoading></PropertyGroup></Project>\n' "$ver" > "$w/Game.csproj"
printf 'using Godot;\npublic partial class Main : Node { public override void _Ready() => GD.Print("aot ok"); }\n' > "$w/Main.cs"
echo "── android-arm64 PublishAot=true"
(cd "$w" && dotnet publish -c ExportRelease -r android-arm64 -p:PublishAot=true -o out -nologo 2>&1 | grep -E 'error|warning NETSDK|NETSDK|ILC|clang|ndk|NDK' | head -20)
echo "출력: $(ls "$w/out" 2>/dev/null | tr '\n' ' ')"
