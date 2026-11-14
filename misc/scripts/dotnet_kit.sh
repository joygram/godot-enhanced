#!/usr/bin/env bash
# C# 키트 만들기·올리기 (CI enhanced_dotnet_release.yml 과 같은 구성, 로컬·빌드 에이전트용)
#   전제: 이 OS 의 C# 편집기 빌드 완료 (scons target=editor module_mono_enabled=yes)
#   순서: glue 생성 → C# 어셈블리·NuGet → 웹 템플릿(릴리스 dotnet-web-<버전> 에서) → 키트 zip → 릴리스 업로드
#   결과: godot-<버전>-enhanced.dotnet-web.<windows|linux|macos>-<arch>.zip
# 사용: bash misc/scripts/dotnet_kit.sh   (NO_UPLOAD=1 → 업로드 생략)
set -euo pipefail
cd "$(dirname "$0")/../.."
godot=$(python3 -c "import version as v; print(f'{v.major}.{v.minor}.{v.patch}')" 2>/dev/null || python -c "import version as v; print(f'{v.major}.{v.minor}.{v.patch}')")
version="$godot-$(tr -d '[:space:]' < ENHANCED_VERSION)"
tag="dotnet-web-$version"
repo="$(git remote get-url origin | sed -E 's#(\.git)?$##; s#.*github\.com[:/]##')"
py=$(command -v python3 || command -v python)

case "$(uname -s)" in
	MINGW*|MSYS*|CYGWIN*) os=windows ;;
	Darwin) os=macos ;;
	*) os=linux ;;
esac
case "$(uname -m)" in arm64|aarch64) arch=arm64 ;; *) arch=x86_64 ;; esac
plat=$([ "$os" = linux ] && echo linuxbsd || echo "$os")
exe=$(ls bin/godot.$plat.editor.$arch.mono$([ "$os" = windows ] && echo .console.exe) 2>/dev/null | head -1)
[ -n "$exe" ] || { echo "✘ C# 편집기 없음: bin/godot.$plat.editor.$arch.mono*"; exit 1; }
"$exe" --headless --version

if [ -n "${SKIP_ASSEMBLIES:-}" ] && ls bin/nuget/*.nupkg >/dev/null 2>&1; then
	echo "── glue·어셈블리 생략 (SKIP_ASSEMBLIES, 기존 bin/nuget)"
else
	echo "── glue"
	"$exe" --headless --quit --generate-mono-glue modules/mono/glue
	echo "── C# 어셈블리·NuGet"
	rm -rf bin/nuget
	"$py" modules/mono/build_scripts/build_assemblies.py --godot-output-dir=./bin --push-nupkgs-local ./bin/nuget
fi

work="$(mktemp -d)"
name="godot-$version-enhanced.dotnet-web.$os-$arch"
d="$work/$name"; mkdir -p "$d/nuget"
cp bin/nuget/*.nupkg "$d/nuget/"
cp patches/dotnet-web-kit/{Program.cs,global.json,README.txt,install.sh,install.bat} "$d/"
echo "── 웹 템플릿 ($tag)"
for pair in "godot.web.template_release.wasm32.mono.zip:web_release.zip" "godot.web.template_release.wasm32.nothreads.mono.zip:web_nothreads_release.zip" \
	"godot.web.template_debug.wasm32.mono.zip:web_debug.zip" "godot.web.template_debug.wasm32.nothreads.mono.zip:web_nothreads_debug.zip"; do
	ok=""
	for try in 1 2 3 4; do
		if gh release download "$tag" -R "$repo" -p "${pair%%:*}" -D "$work" --clobber 2>/dev/null; then ok=1; break; fi
		sleep 5 # 네트워크(TLS) 일시 오류 재시도
	done
	if [ -n "$ok" ]; then mv "$work/${pair%%:*}" "$d/${pair##*:}"; echo "  ${pair##*:}"; else echo "  (없음: ${pair%%:*})"; fi
done
[ -f "$d/web_release.zip" ] || { echo "✘ 웹 릴리스 템플릿 없음 ($tag)"; exit 1; }
# debug 템플릿이 없으면 release 로 대신 (설치 스크립트가 둘 다 요구)
[ -f "$d/web_debug.zip" ] || cp "$d/web_release.zip" "$d/web_debug.zip"

if [ "$os" = macos ]; then
	app="$d/Godot.app"
	cp -R misc/dist/macos_tools.app "$app"
	mkdir -p "$app/Contents/MacOS"
	cp "$exe" "$app/Contents/MacOS/Godot"; chmod +x "$app/Contents/MacOS/Godot"
	cp -R bin/GodotSharp "$app/Contents/Resources/GodotSharp"
	codesign --force --deep --sign - "$app"
	(cd "$work" && ditto -c -k --keepParent "$name" "$name.zip")
else
	cp bin/godot.$plat.editor.$arch.mono* "$d/"
	rm -f "$d"/*.pdb "$d"/*.lib "$d"/*.exp
	cp -r bin/GodotSharp "$d/GodotSharp"
	if [ "$os" = windows ]; then (cd "$work" && powershell -NoProfile -Command "Compress-Archive -Path '$name' -DestinationPath '$name.zip' -Force"); else (cd "$work" && zip -qr -9 "$name.zip" "$name"); fi
fi
ls -la "$work/$name.zip"

if [ -z "${NO_UPLOAD:-}" ]; then
	gh release view "$tag" -R "$repo" >/dev/null 2>&1 || gh release create "$tag" -R "$repo" --target "$(git rev-parse HEAD)" \
		--title "C# web export kit $version (godot-enhanced)" --notes "C# (.NET 11) editor + GodotSharp + NuGet + web templates, per platform." || true
	gh release upload "$tag" -R "$repo" "$work/$name.zip" --clobber
	echo "✔ 올림: $tag/$name.zip"
fi
