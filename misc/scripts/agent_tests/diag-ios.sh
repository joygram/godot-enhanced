#!/usr/bin/env bash
# 진단: iOS C# (NativeAOT) 빌드·시뮬레이터 실행 도구 유무 (Mac 에이전트)
cd "$(dirname "$0")/../../.."
echo "macOS: $(sw_vers -productVersion 2>/dev/null || echo -) $(uname -m)"
echo "xcode: $(xcodebuild -version 2>/dev/null | tr '\n' ' ' || echo -)"
echo "xcode-select: $(xcode-select -p 2>/dev/null || echo -)"
echo "ios sdk: $(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null || echo -), sim sdk: $(xcrun --sdk iphonesimulator --show-sdk-version 2>/dev/null || echo -)"
echo "sim runtimes: $(xcrun simctl list runtimes 2>/dev/null | grep -i ios | tr '\n' ' ' || echo -)"
echo "dotnet: $(command -v dotnet || echo -)"
echo "dotnet sdks: $(dotnet --list-sdks 2>/dev/null | tr '\n' ' ')"
echo "mono editor: $(ls bin/godot.macos.editor.*.mono 2>/dev/null | tr '\n' ' ')"
echo "ios templates: $(ls bin/*ios* 2>/dev/null | tr '\n' ' ')"
