#!/usr/bin/env bash
# C# 웹 AOT 빌드 (patches/dotnet-web-export.md mono_wasm_aot_dir):
#   게임 AOT publish(RunAOTCompilation) → 그 출력 링크한 전용 웹 템플릿 → 그 템플릿으로 내보내기 → 게임 저장소 릴리스 업로드
# 필요: C# 편집기 (같은 작업에서 먼저 빌드: platform=linuxbsd target=editor module_mono_enabled=yes), ~/emsdk, gh
# 환경: AOT_GAME_REPO (기본 joygram/yangvil-godot-csharp), AOT_GAME_DIR (기본 game), AOT_TAG (기본 web-aot)
set -euo pipefail
cd "$(dirname "$0")/../../.."
root=$PWD
w="${JOB_DIR:-/tmp}/dotnet-web-aot"
rm -rf "$w"; mkdir -p "$w" "$w/out-std" "$w/out-aot"
arch=$(uname -m | sed 's/aarch64/arm64/')
exe="bin/godot.linuxbsd.editor.$arch.mono"
[ -x "$exe" ] || { echo "✘ C# 편집기 없음: $exe"; exit 1; }
repo="${AOT_GAME_REPO:-joygram/yangvil-godot-csharp}"
tag="${AOT_TAG:-web-aot}"
jobs=$(nproc)
py=$(command -v python3)

emver=$(tr -d '[:space:]' < misc/scripts/emscripten-version)
~/emsdk/emsdk install "$emver" >/dev/null
~/emsdk/emsdk activate "$emver" >/dev/null
source ~/emsdk/emsdk_env.sh >/dev/null 2>&1
echo "emcc: $(emcc --version | head -1)"

echo "── glue·C# 어셈블리·NuGet"
"$exe" --headless --quit --generate-mono-glue modules/mono/glue
rm -rf bin/nuget
"$py" modules/mono/build_scripts/build_assemblies.py --godot-output-dir=./bin --push-nupkgs-local ./bin/nuget >"$w/assemblies.log" 2>&1 || { tail -20 "$w/assemblies.log"; exit 1; }

echo "── 게임 $repo"
git clone -q --depth 1 "https://github.com/$repo.git" "$w/repo"
p="$w/repo/${AOT_GAME_DIR:-game}"
dotnet nuget add source "$root/bin/nuget" --name godot-enhanced-local --configfile "$p/nuget.config" >/dev/null

# 템플릿 폴더 = 편집기 버전에서 커밋 해시 뺀 것 (예: 4.7.2.stable.mono.enhanced-0.3.1)
tver=$("$exe" --headless --version | tail -1 | sed -E 's/\.[0-9a-f]{7,}$//')
tdir="$HOME/.local/share/godot/export_templates/$tver"
mkdir -p "$tdir"
cache="$w/aot-std"
mkdir -p "$cache"

echo "── 1차 내보내기 (AOT publish 출력 만들기, 표준 템플릿 $tver)"
if [ ! -f "$tdir/web_release.zip" ]; then
	ever="$($py -c "import version as v; print(f'{v.major}.{v.minor}.{v.patch}')")-$(tr -d '[:space:]' < ENHANCED_VERSION)"
	erepo="$(git remote get-url origin | sed -E 's#(\.git)?$##; s#.*github\.com[:/]##')"
	# 1차 내보내기 = AOT publish 출력만 씀 (결과 버림) → 이 버전 릴리스 없으면 최신 dotnet-web 릴리스 템플릿
	rel="dotnet-web-$ever"
	gh release view "$rel" -R "$erepo" >/dev/null 2>&1 || rel=$(gh release list -R "$erepo" -L 50 --json tagName -q '[.[].tagName | select(startswith("dotnet-web-"))][0]')
	echo "표준 템플릿: $rel"
	# 템플릿 = 키트 zip 안 web_release.zip
	gh release download "$rel" -R "$erepo" -p "*.dotnet-web.linux-$arch.zip" -D "$w/kit" --clobber \
		|| { echo "✘ C# 키트 없음 ($rel)"; exit 1; }
	unzip -q -j "$w"/kit/*.zip '*/web_release.zip' -d "$w/kit" || { echo "✘ 키트에 web_release.zip 없음"; exit 1; }
	mv "$w/kit/web_release.zip" "$tdir/web_release.zip"
fi
"$exe" --headless --path "$p" --import >"$w/import.log" 2>&1 || true
RunAOTCompilation=true timeout 1500 "$exe" --headless --path "$p" --export-release Web "$w/out-std/index.html" >"$w/export-std.log" 2>&1 || true
aot="$p/.godot/mono/temp/obj/ExportRelease/browser-wasm/wasm/for-publish"
[ -f "$aot/driver-gen.c" ] || { echo "✘ AOT 출력 없음 ($aot)"; tail -20 "$w/export-std.log"; exit 1; }
echo "AOT 어셈블리: $(ls "$aot"/*.dll.o | wc -l)개"

echo "── AOT 전용 웹 템플릿 (mono_wasm_aot_dir)"
cp "$tdir/web_release.zip" "$w/web_release.std.zip"
scons platform=web target=template_release module_mono_enabled=yes optimize=speed lto=full mono_wasm_aot_dir="$aot" ccflags="-DNDEBUG" linkflags="-sMALLOC=mimalloc" -j"$jobs" >"$w/build-aot.log" 2>&1 \
	|| { grep -m10 -E 'error' "$w/build-aot.log"; exit 1; }
grep -m1 "Linking .* AOT-compiled" "$w/build-aot.log" || { echo "✘ AOT 링크 로그 없음"; exit 1; }
cp bin/godot.web.template_release.wasm32.mono.zip "$tdir/web_release.zip"

echo "── 2차 내보내기 (AOT 템플릿)"
RunAOTCompilation=true timeout 1500 "$exe" --headless --path "$p" --export-release Web "$w/out-aot/index.html" >"$w/export-aot.log" 2>&1 || true
cp "$w/web_release.std.zip" "$tdir/web_release.zip"
[ -f "$w/out-aot/index.wasm" ] || { echo "✘ AOT 내보내기 실패"; tail -20 "$w/export-aot.log"; exit 1; }
ls -l "$w/out-aot" | tee "${JOB_DIR:-/tmp}/aot-files.txt"

echo "── 업로드 $repo@$tag"
(cd "$w/out-aot" && zip -qr -9 "$w/yangvil-web-aot.zip" .)
gh release view "$tag" -R "$repo" >/dev/null 2>&1 || gh release create "$tag" -R "$repo" --title "Web build (C# AOT template)" \
	--notes "godot-enhanced $(git rev-parse --short HEAD) — mono_wasm_aot_dir 전용 템플릿으로 내보낸 웹 빌드 (비교 측정용)"
gh release upload "$tag" -R "$repo" "$w/yangvil-web-aot.zip" --clobber
echo "✔ dotnet-web-aot 완료 — $repo@$tag/yangvil-web-aot.zip"
