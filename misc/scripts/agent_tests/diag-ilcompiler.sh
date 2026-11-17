#!/usr/bin/env bash
# 진단: NativeAOT(ILCompiler) 가 공유 라이브러리 이름에 lib 접두를 붙이는 규칙 — NuGet 패키지·런타임 팩·SDK 모두
d="$HOME/.nuget/packages"
sdkroot="$(dirname "$(readlink -f "$(command -v dotnet)" 2>/dev/null || command -v dotnet)")"
echo "dotnet root: $sdkroot"
for base in "$d" "$sdkroot/packs" "$sdkroot/sdk"; do
	echo "── $base"
	grep -rln "NativeBinaryPrefix" "$base" --include='*.targets' --include='*.props' 2>/dev/null | head -10
done
echo "── UseNativeLibPrefix 를 쓰는 곳"
grep -rn "UseNativeLibPrefix" "$d" "$sdkroot/packs" "$sdkroot/sdk" --include='*.targets' --include='*.props' 2>/dev/null | head -20
echo "── 접두 규칙 줄"
grep -rn "<NativeBinaryPrefix" "$d" "$sdkroot/packs" "$sdkroot/sdk" --include='*.targets' --include='*.props' 2>/dev/null | head -20
