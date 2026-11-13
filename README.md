# godot-ime — Godot 4.7.2 with Korean IME fix, Web (WASM) memory patch and C# web export

Patched build of [Godot Engine](https://github.com/godotengine/godot) `4.7.2-stable`. Upstream history kept intact; three patches on top.

**Keywords:** Godot Korean IME, Godot 한글 입력 버그, Godot Hangul input, Windows IME composition, CJK input, LineEdit / TextEdit caret, Godot web export memory, WASM heap, GDScript parser memory, HTML5 export out of memory, Godot C# web export, Godot .NET web export, C# WebAssembly, Mono WASM, Godot mono HTML5.

| Patch | Platform | Fixes |
|---|---|---|
| [Windows IME queued key](patches/windows-ime-queued-key.md) | Windows editor + game | Korean (Hangul) typing loses caret advance after a syllable is committed |
| [GDScript parser release](patches/gdscript-parser-release.md) | All, aimed at Web / WASM | Syntax trees of mutually dependent scripts stay alive after compile → high peak memory at boot |
| [C# (.NET) web export](patches/dotnet-web-export.md) | Web + C# editor | Export C# projects to the web (Mono on WebAssembly). Experimental. Taken from upstream PR #106125 and ComplexRobot's rebase |

## Branches

- `4.7.2-ime` (default): `4.7.2-stable` (`ed1daf0bf`) + patches. One commit per patch.
- `master`: mirror of upstream `master`, untouched.
- Upstream tags kept (`4.7.2-stable`, …).

## Use

Build this branch:

```sh
git clone --branch 4.7.2-ime --depth 1 https://github.com/joygram/godot-ime.git
cd godot-ime
# Windows editor (MSVC)
python -m SCons platform=windows target=editor arch=x86_64
# Web export template (Emscripten)
scons platform=web target=template_release
```

Or apply the patches to your own Godot 4.7.2 tree:

```sh
git apply patches/godot-4.7.2-windows-ime-queued-key.patch
git apply patches/godot-4.7.2-gdscript-parser-release.patch
git apply patches/godot-4.7.2-dotnet-web-export.patch
```

Apply all three (as above), or only the ones you need — each patch also applies on its own and in any order (checked with `git apply` on `4.7.2-stable`).

## Prebuilt Web export template

- GitHub Actions ([ime_web_template.yml](.github/workflows/ime_web_template.yml)) builds the Web template from this branch and publishes it on [Releases](https://github.com/joygram/godot-ime/releases).
- Assets: `godot.web.template_release.wasm32.nothreads.dlink.zip` (GDExtension support), `godot.web.template_release.wasm32.nothreads.zip`.
- Use: Web export preset → Custom Template → Release → the zip.
- Emscripten 4.0.11. With dlink, your GDExtension web builds must use the same version.
- These are the GDScript templates (no threads). C# web projects need the separate threaded `.mono` templates below.

## C# (.NET) web export

- Needs the C# editor and `.mono` web templates built from this branch with `module_mono_enabled=yes`. How: [patches/dotnet-web-export.md](patches/dotnet-web-export.md).
- Releases: workflow `ime_dotnet_release.yml` publishes them to [Releases](https://github.com/joygram/godot-ime/releases) once it has run successfully. Not published yet.
- No GDExtension in C# web builds. Threaded template: host with COOP / COEP headers.
- Not only C++: the patch also changes C#, MSBuild and SCons files. The build needs the .NET SDK 9 and the `wasm-tools` workload, and ships `GodotSharp` assemblies and NuGet packages next to the editor.

## Keeping up with upstream

```sh
git remote add upstream https://github.com/godotengine/godot.git
git fetch upstream --tags
git checkout -b <new-version>-ime <new-version>-stable
git cherry-pick 4.7.2-stable..origin/4.7.2-ime
```

## Status

- Not an official Godot build. Not submitted upstream yet.
- Tested only on Godot 4.7.2. Other versions: unverified.
- License: MIT, same as Godot. See [LICENSE.txt](LICENSE.txt).
- Original Godot readme: [upstream README](https://github.com/godotengine/godot/blob/4.7.2-stable/README.md).

## Credits

- C# web export: Raul Santos ([godotengine/godot#106125](https://github.com/godotengine/godot/pull/106125)), ComplexRobot ([godot](https://github.com/ComplexRobot/godot), [godot-dotnet-web-export](https://github.com/ComplexRobot/godot-dotnet-web-export)), Dom Finn.
- Godot Engine contributors, MIT license.

---

## 한국어 안내

Godot 4.7.2 공식 소스에 패치 세 개를 더한 빌드입니다. 업스트림 커밋 이력은 그대로 유지합니다.

| 패치 | 플랫폼 | 해결하는 문제 |
|---|---|---|
| [Windows 한글 IME 패치](patches/windows-ime-queued-key.md) | Windows 편집기·게임 | 한글 음절을 확정한 뒤 다음 글자를 입력하면 커서가 앞으로 가지 않는 문제 |
| [GDScript 파서 해제 패치](patches/gdscript-parser-release.md) | 전체 (웹/WASM에서 효과 큼) | 서로 참조하는 스크립트의 구문 트리가 컴파일 뒤에도 남아 부팅 때 메모리 최고치가 높아지는 문제 |
| [C#(.NET) 웹 내보내기 패치](patches/dotnet-web-export.md) | 웹 + C# 편집기 | C# 프로젝트를 웹으로 내보냅니다(WebAssembly 위의 Mono). 실험적 기능이며 업스트림 PR #106125와 ComplexRobot의 재적용본을 가져왔습니다 |

### 브랜치

- `4.7.2-ime` (기본 브랜치): `4.7.2-stable`(`ed1daf0bf`) 위에 패치를 하나씩 커밋으로 올렸습니다.
- `master`: 업스트림 `master`를 그대로 옮겨 온 미러입니다.
- 업스트림 태그(`4.7.2-stable` 등)도 그대로 있습니다.

### 사용법

이 브랜치를 바로 빌드하면 됩니다.

```sh
git clone --branch 4.7.2-ime --depth 1 https://github.com/joygram/godot-ime.git
cd godot-ime
# Windows 편집기 (MSVC)
python -m SCons platform=windows target=editor arch=x86_64
# 웹 내보내기 템플릿 (Emscripten)
scons platform=web target=template_release
```

가지고 있는 Godot 4.7.2 소스에 패치만 적용해도 됩니다. 세 패치를 모두 적용해도 되고, 필요한 것만 골라 적용해도 됩니다. 적용 순서는 상관없습니다(`4.7.2-stable`에서 `git apply`로 모든 조합을 확인했습니다).

```sh
# 모두
git apply patches/godot-4.7.2-windows-ime-queued-key.patch patches/godot-4.7.2-gdscript-parser-release.patch patches/godot-4.7.2-dotnet-web-export.patch
# 하나만
git apply patches/godot-4.7.2-windows-ime-queued-key.patch
```

### 미리 빌드된 웹 템플릿

- GitHub Actions가 이 브랜치로 웹 내보내기 템플릿을 빌드해 [Releases](https://github.com/joygram/godot-ime/releases)에 올립니다.
- `godot.web.template_release.wasm32.nothreads.dlink.zip`: GDExtension을 쓰는 프로젝트용
- `godot.web.template_release.wasm32.nothreads.zip`: 일반 프로젝트용
- 웹 내보내기 프리셋의 Custom Template → Release에 zip 파일을 지정하면 됩니다.
- Emscripten 4.0.11로 빌드했습니다. dlink 템플릿을 쓴다면 GDExtension 웹 빌드도 같은 버전이어야 합니다.
- 위 템플릿은 GDScript용(스레드 없음)입니다. C# 웹 프로젝트는 아래의 별도 `.mono` 템플릿(스레드 사용)이 필요합니다.

### C#(.NET) 웹 내보내기

- `module_mono_enabled=yes`로 이 브랜치에서 빌드한 C# 편집기와 `.mono` 웹 템플릿이 필요합니다. 방법은 [patches/dotnet-web-export.md](patches/dotnet-web-export.md)에 있습니다.
- 결과물은 `ime_dotnet_release.yml` 워크플로가 성공하면 [Releases](https://github.com/joygram/godot-ime/releases)에 올라옵니다. 아직 올라와 있지 않습니다.
- C# 웹 빌드에서는 GDExtension을 쓸 수 없습니다. 스레드를 쓰는 템플릿이라 호스팅에서 COOP / COEP 헤더가 필요합니다.
- C++만 바뀌는 것이 아닙니다. C#, MSBuild, SCons 파일도 바뀌어서 빌드에 .NET SDK 9와 `wasm-tools` 워크로드가 필요하고, 편집기와 함께 `GodotSharp` 어셈블리·NuGet 패키지가 배포됩니다.

### 새 Godot 버전으로 옮기기

```sh
git remote add upstream https://github.com/godotengine/godot.git
git fetch upstream --tags
git checkout -b <새 버전>-ime <새 버전>-stable
git cherry-pick 4.7.2-stable..origin/4.7.2-ime
```

### 상태

- 공식 Godot 빌드가 아니며, 아직 업스트림에 제출하지 않았습니다.
- Godot 4.7.2에서만 확인했습니다. 다른 버전에서는 검증하지 않았습니다.
- 라이선스는 Godot과 같은 MIT입니다.
- C# 웹 내보내기 출처: Raul Santos([godotengine/godot#106125](https://github.com/godotengine/godot/pull/106125)), ComplexRobot, Dom Finn.

**검색어:** 고도 엔진 한글 입력, Godot 한글 IME, 한글 입력 시 커서 안 움직임, 한글 씹힘, LineEdit·TextEdit 한글, 고도 웹 빌드 메모리, Godot WASM 메모리 부족, 고도 C# 웹 내보내기, Godot .NET 웹 빌드

---

> 본 작업은 AI와 함께함 · This work was made with AI assistance.
