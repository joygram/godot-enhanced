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
sdk=$(ls -d "$HOME"/Android/Sdk 2>/dev/null | head -1)
ndk=$(ls -d "$sdk"/ndk/* 2>/dev/null | tail -1)
tc="$ndk/toolchains/llvm/prebuilt/linux-x86_64"
echo "ndk: $ndk"
try() {
	local name=$1; shift
	echo "── $name"
	(cd "$w" && rm -rf out obj bin && dotnet publish -c ExportRelease -o out -nologo -p:PublishAot=true -p:GodotTargetPlatform=android "$@" 2>&1 \
		| grep -E 'error|NETSDK|ILC|clang|ld\.|undefined' | sort -u | head -12)
	echo "  출력: $(ls -la "$w/out" 2>/dev/null | awk '/\.so|Game/ {print $5, $NF}' | tr '\n' ' ')"
	[ -n "$(ls "$w"/out/*.so 2>/dev/null)" ] && file "$w"/out/*.so | head -2
}
try "A android-arm64 + 런타임 팩" -r android-arm64 -p:PublishAotUsingRuntimePack=true
PATH="$tc/bin:$PATH" try "B linux-bionic-arm64 + NDK clang" -r linux-bionic-arm64 -p:DisableUnsupportedError=true \
	-p:PublishAotUsingRuntimePack=true -p:NativeLib=Shared -p:CppCompilerAndLinker=clang -p:SysRoot="$tc/sysroot" \
	-p:LinkerFlavor=lld -p:ObjCopyName=llvm-objcopy
