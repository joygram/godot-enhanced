#!/usr/bin/env bash
# 진단: NativeAOT(ILCompiler) 가 공유 라이브러리 이름에 lib 접두를 붙이는 속성
d="$HOME/.nuget/packages"
ls -d "$d"/microsoft.dotnet.ilcompiler* "$d"/runtime.*.microsoft.dotnet.ilcompiler* 2>/dev/null | head
grep -rn "NativeBinaryPrefix\|<NativeBinary \|<NativeBinary>\|NativeLibPrefix" "$d"/microsoft.dotnet.ilcompiler*/*/build/*.targets "$d"/microsoft.dotnet.ilcompiler*/*/build/*.props 2>/dev/null | head -20
