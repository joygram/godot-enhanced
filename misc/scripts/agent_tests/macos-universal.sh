#!/usr/bin/env bash
# macOS universal 편집기: bin 의 x86_64·arm64 편집기를 lipo 로 합쳐 Godot.app → 릴리스 editor-<버전> 업로드
#   자산: godot-<버전>-enhanced.macos.editor.universal.zip (CI enhanced_editor_release.yml 과 같은 이름)
#   전제: 이 작업의 빌드(arch=x86_64) + 이전 arm64 빌드가 bin 에 있음 (없으면 arm64 빌드)
set -euo pipefail
cd "$(dirname "$0")/../../.."
godot=$(python3 -c "import version as v; print(f'{v.major}.{v.minor}.{v.patch}')")
version="$godot-$(tr -d '[:space:]' < ENHANCED_VERSION)"
tag="editor-$version"
repo="$(git remote get-url origin | sed -E 's#(\.git)?$##; s#.*github\.com[:/]##')"
flags="target=editor vulkan=no angle=no accesskit=no debug_symbols=no"
for arch in x86_64 arm64; do
	[ -x bin/godot.macos.editor.$arch ] || scons platform=macos arch=$arch $flags -j"$(sysctl -n hw.ncpu)"
done
work="$(mktemp -d)"
cp -R misc/dist/macos_tools.app "$work/Godot.app"
mkdir -p "$work/Godot.app/Contents/MacOS"
lipo -create bin/godot.macos.editor.x86_64 bin/godot.macos.editor.arm64 -output "$work/Godot.app/Contents/MacOS/Godot"
chmod +x "$work/Godot.app/Contents/MacOS/Godot"
codesign --force --deep -s - "$work/Godot.app"
"$work/Godot.app/Contents/MacOS/Godot" --headless --version
zip="godot-$version-enhanced.macos.editor.universal.zip"
(cd "$work" && ditto -c -k --keepParent Godot.app "$zip")
gh release upload "$tag" -R "$repo" "$work/$zip" --clobber
echo "✔ 올림: $tag/$zip"
