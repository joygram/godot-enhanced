#!/usr/bin/env bash
# 에이전트 릴리스 업로드: JOB_DIR 의 빌드 산출물 → GitHub 릴리스 <kind>-<Godot>-<ENHANCED_VERSION>
# 사용: JOB_DIR=<작업 폴더> bash misc/scripts/agent_release.sh <editor|web-template|dotnet-web>
# 필요: gh auth login
set -euo pipefail
kind="$1"
cd "$(dirname "$0")/../.."
godot=$(python3 -c "import version as v; print(f'{v.major}.{v.minor}.{v.patch}')")
version="$godot-$(tr -d '[:space:]' < ENHANCED_VERSION)"
tag="$kind-$version"
sha=$(git rev-parse HEAD)
host=$(hostname -s)

# 업로드 대상: 실행 파일·zip 을 플랫폼 이름 붙인 zip 으로 묶음
out="$JOB_DIR/upload"; rm -rf "$out"; mkdir -p "$out"
for f in "$JOB_DIR"/*; do
	name=$(basename "$f")
	case "$name" in
		*.zip) cp "$f" "$out/" ;;
		godot.web.*|godot.side.web.*) continue ;; # 웹은 템플릿 zip 만 (js·wasm 낱개 제외)
		godot.*editor*|godot.*template*)
			case "$name" in *.o|*.a|*.lib|*.exp|*.pdb|*.console.exe) continue ;; esac
			# CI 와 같은 이름: godot-<버전>-enhanced.<platform>.<target>.<arch>.zip (Windows 는 .console.exe 도 함께)
			base="${name%.exe}"; base="${base#godot.}"
			files=("$name"); [ -f "$JOB_DIR/${name%.exe}.console.exe" ] && files+=("${name%.exe}.console.exe")
			(cd "$JOB_DIR" && zip -q -9 "$out/godot-$version-enhanced.$base.zip" "${files[@]}") ;;
	esac
done
ls "$out"/* >/dev/null 2>&1 || { echo "[release] 올릴 산출물 없음"; exit 1; }

# origin 저장소로 고정 (gh 가 포크를 상위 저장소로 해석하는 것 방지)
repo="$(git remote get-url origin | sed -E 's#(\.git)?$##; s#.*github\.com[:/]##')"
gh release view "$tag" -R "$repo" >/dev/null 2>&1 || gh release create "$tag" -R "$repo" --target "$sha" \
	--title "$kind $version (godot-enhanced)" --notes "godot-enhanced $version — $kind." || true
gh release upload "$tag" -R "$repo" "$out"/* --clobber
echo "[release] ✔ $tag ← $(ls "$out" | tr '\n' ' ') ($host, ${sha:0:10})"
