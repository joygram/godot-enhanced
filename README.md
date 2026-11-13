# godot-enhanced — Godot 4.7.2 with Korean IME fix, Web (WASM) memory patch and C# web export

Patched build of [Godot Engine](https://github.com/godotengine/godot) `4.7.2-stable`. Upstream history kept intact; three patches on top.

## 🚀 0.1.1 — C# on the web, and it's light

> Official Godot 4 **cannot** export C# to the web. godot-enhanced does — then cuts it down hard.

| C# web build (real game, .NET 11) | Before | **0.1.1** | |
|---|---|---|---|
| Download (`.pck`) | 64.0 MB | **10.7 MB** | **−83%** |
| WASM heap after boot | 160.1 MB | **95.8 MB** | **−40%** |
| Empty C# project, WASM heap | 154.1 MB | **79.8 MB** | **−48%** |
| Managed (.NET) heap under load | 4.3 MB | **1.3 MB** | **−70%** |
| Errors in browser | 0 | **0** | save/load verified |

- **PCK diet**: unused `.a`, ICU data, build metadata dropped → 64 → 30 MB
- **Zero-copy assembly load**: `need_copy=false`, no permanent copy peak → heap 160 → 115 MB
- **IL trimming**: unused framework code removed; game + `GodotSharp` kept → 30 → 10.7 MB
- **Web-tuned GC**: 1 MB SGen nursery → shorter minor GCs. Override: `MONO_GC_PARAMS`
- **.NET 11** runtime pack, Emscripten 6.0.2
- Also: Windows Hangul IME fix

### 🔍 GDScript web: a memory leak found in Godot's compiler

- Tracked: rpg2d web boot → WASM heap kept growing, never came back down
- Found: GDScript parsers of mutually dependent scripts hold each other → syntax trees never freed
- Found: compiling a script pulls its whole dependency chain → every tree in memory at once
- Fixed: parser released before dependencies compile; cached parsers cleared after the outermost reload
- Result: trees freed right after compile, lower boot peak. Script behavior unchanged
- Applies to every GDScript project, not only C#. Biggest win on web (heap never shrinks)

| rpg2d boot static memory (`autoload_first`) | Before | **After** | |
|---|---|---|---|
| Desktop run logs, 2026-11-13 | 145.8 – 165.5 MB (16 runs) | **67.4 – 68.0 MB** (13 runs) | **≈ −56%** |

- Drop starts with the first run on the patched editor (10:07, release `88690556f4`)

- Measured: Windows, headless Chrome, debug = release
- Reference: official Godot empty GDScript web = 55.4 MB WASM heap
- Version `<godot>-<enhanced>` → `4.7.2-0.1.1`, source [`ENHANCED_VERSION`](ENHANCED_VERSION)
- Engine build name: `enhanced-0.1.1`

**Keywords:** Godot Korean IME, Godot 한글 입력 버그, Godot Hangul input, Windows IME composition, CJK input, LineEdit / TextEdit caret, Godot web export memory, WASM heap, GDScript parser memory, HTML5 export out of memory, Godot C# web export, Godot .NET web export, C# WebAssembly, Mono WASM, Godot mono HTML5.

| Patch | Platform | Fixes |
|---|---|---|
| [Windows IME queued key](patches/windows-ime-queued-key.md) | Windows editor + game | Korean (Hangul) typing loses caret advance after a syllable is committed |
| [GDScript parser release](patches/gdscript-parser-release.md) | All, aimed at Web / WASM | Syntax trees of mutually dependent scripts stay alive after compile → high peak memory at boot |
| [C# (.NET) web export](patches/dotnet-web-export.md) | Web + C# editor | Export C# projects to the web (Mono on WebAssembly). Experimental. Taken from upstream PR #106125 and ComplexRobot's rebase |

## Branches

- `main` (default): latest supported Godot version (now `4.7.2-stable`, `ed1daf0bf`) + patches. One commit per patch.
- Version branches (e.g. `4.7`) are cut from `main` only when an older version still needs fixes.
- Upstream Godot: add `https://github.com/godotengine/godot.git` as a remote.
- Upstream tags kept (`4.7.2-stable`, …).

## Use

Build this branch:

```sh
git clone --branch main --depth 1 https://github.com/joygram/godot-enhanced.git
cd godot-enhanced
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

- GitHub Actions ([enhanced_web_template.yml](.github/workflows/enhanced_web_template.yml)) builds the Web template from this branch and publishes it on [Releases](https://github.com/joygram/godot-enhanced/releases).
- Assets: `godot.web.template_release.wasm32.nothreads.dlink.zip` (GDExtension support), `godot.web.template_release.wasm32.nothreads.zip`.
- Use: Web export preset → Custom Template → Release → the zip.
- Emscripten 6.0.2 (GDScript and C# alike). With dlink, your GDExtension web builds must use the same version.
- These are the GDScript templates (no threads). C# web projects need the separate threaded `.mono` templates below.

## C# (.NET) web export

- Targets **.NET 11** (`net11.0`); game projects must use the same framework as the templates. .NET 9 support ended on 2026-11-10.
- Needs the C# editor and `.mono` web templates built from this branch with `module_mono_enabled=yes`. How: [patches/dotnet-web-export.md](patches/dotnet-web-export.md).
- Releases: workflow `enhanced_dotnet_release.yml` publishes them to [Releases](https://github.com/joygram/godot-enhanced/releases) once it has run successfully. Not published yet.
- No GDExtension in C# web builds. Threaded template: host with COOP / COEP headers.
- Not only C++: the patch also changes C#, MSBuild and SCons files. The build needs the .NET 11 SDK and the `wasm-tools` workload, and ships `GodotSharp` assemblies and NuGet packages next to the editor.

## Keeping up with upstream

```sh
git remote add upstream https://github.com/godotengine/godot.git
git fetch upstream --tags
git checkout -b <new-version>-enhanced <new-version>-stable
git cherry-pick 4.7.2-stable..origin/main
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

### 🚀 0.1.1 — C#이 웹에서 돌아가고, 가볍다

> 공식 Godot 4는 C#을 웹으로 **못 내보냅니다.** godot-enhanced는 내보내고, 확 줄였습니다.

| C# 웹 빌드 (실제 게임, .NET 11) | 이전 | **0.1.1** | |
|---|---|---|---|
| 다운로드 (`.pck`) | 64.0 MB | **10.7 MB** | **−83%** |
| 부팅 후 WASM 힙 | 160.1 MB | **95.8 MB** | **−40%** |
| 빈 C# 프로젝트 WASM 힙 | 154.1 MB | **79.8 MB** | **−48%** |
| 부하 중 .NET 관리 힙 | 4.3 MB | **1.3 MB** | **−70%** |
| 브라우저 오류 | 0 | **0** | 저장·불러오기 확인 |

- **pck 다이어트**: 런타임에 안 쓰는 `.a`·ICU 데이터·빌드 메타데이터 제외 → 64 → 30 MB
- **어셈블리 무복사 로드**: `need_copy=false`. 줄지 않는 WASM 힙에 남던 복사 최고치 제거 → 160 → 115 MB
- **IL 트리밍**: 안 쓰는 프레임워크 코드 제거, 게임·`GodotSharp`는 보존 → 30 → 10.7 MB
- **웹용 GC**: SGen nursery 1 MB → 작은 GC가 짧아져 프레임 끊김 감소. `MONO_GC_PARAMS`로 변경 가능
- **.NET 11** 런타임 팩, Emscripten 6.0.2

0.1.1에 함께: Windows 한글 IME 수정.

### 🔍 GDScript 웹: Godot 컴파일러의 메모리 누수를 찾아 막음

- 추적: rpg2d 웹 부팅 → WASM 힙이 계속 커지고 내려오지 않음
- 발견: 서로 참조하는 스크립트의 파서가 서로를 붙잡음 → 구문 트리가 해제되지 않음
- 발견: 스크립트 하나 컴파일 = 의존 사슬 전체 컴파일 → 구문 트리가 한꺼번에 메모리에 올라감
- 해결: 의존 스크립트 컴파일 전에 자기 파서 해제, 가장 바깥 reload 끝나면 파서 캐시 정리
- 결과: 컴파일 직후 구문 트리 해제, 부팅 최고치 감소. 스크립트 동작은 그대로
- C#만이 아니라 모든 GDScript 프로젝트에 적용. 힙이 줄지 않는 웹에서 효과 최대

| rpg2d 부팅 정적 메모리 (`autoload_first`) | 이전 | **이후** | |
|---|---|---|---|
| 데스크톱 실행 로그, 2026-11-13 | 145.8 – 165.5 MB (16회) | **67.4 – 68.0 MB** (13회) | **약 −56%** |

- 패치 에디터(릴리스 `88690556f4`) 첫 실행(10:07)부터 하락

- 측정: Windows, headless Chrome, debug·release 템플릿 동일 결과. 참고값: 공식 Godot 빈 GDScript 웹 = WASM 힙 55.4 MB
- 버전: `<Godot>-<enhanced>` → `4.7.2-0.1.1`. 기준 파일 [`ENHANCED_VERSION`](ENHANCED_VERSION). 엔진 빌드 이름 `enhanced-0.1.1`

| 패치 | 플랫폼 | 해결하는 문제 |
|---|---|---|
| [Windows 한글 IME 패치](patches/windows-ime-queued-key.md) | Windows 편집기·게임 | 한글 음절을 확정한 뒤 다음 글자를 입력하면 커서가 앞으로 가지 않는 문제 |
| [GDScript 파서 해제 패치](patches/gdscript-parser-release.md) | 전체 (웹/WASM에서 효과 큼) | 서로 참조하는 스크립트의 구문 트리가 컴파일 뒤에도 남아 부팅 때 메모리 최고치가 높아지는 문제 |
| [C#(.NET) 웹 내보내기 패치](patches/dotnet-web-export.md) | 웹 + C# 편집기 | C# 프로젝트를 웹으로 내보냅니다(WebAssembly 위의 Mono). 실험적 기능이며 업스트림 PR #106125와 ComplexRobot의 재적용본을 가져왔습니다 |

### 브랜치

- `main` (기본 브랜치): 지원하는 최신 Godot 버전(현재 `4.7.2-stable`, `ed1daf0bf`) 위에 패치를 하나씩 커밋으로 올렸습니다.
- 버전 브랜치(예: `4.7`)는 이전 버전을 계속 고쳐야 할 때만 `main`에서 따로 만듭니다.
- 업스트림 Godot은 `https://github.com/godotengine/godot.git`을 원격으로 추가해서 받습니다.
- 업스트림 태그(`4.7.2-stable` 등)도 그대로 있습니다.

### 사용법

이 브랜치를 바로 빌드하면 됩니다.

```sh
git clone --branch main --depth 1 https://github.com/joygram/godot-enhanced.git
cd godot-enhanced
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

- GitHub Actions가 이 브랜치로 웹 내보내기 템플릿을 빌드해 [Releases](https://github.com/joygram/godot-enhanced/releases)에 올립니다.
- `godot.web.template_release.wasm32.nothreads.dlink.zip`: GDExtension을 쓰는 프로젝트용
- `godot.web.template_release.wasm32.nothreads.zip`: 일반 프로젝트용
- 웹 내보내기 프리셋의 Custom Template → Release에 zip 파일을 지정하면 됩니다.
- Emscripten 6.0.2로 빌드합니다(GDScript·C# 공통). dlink 템플릿을 쓴다면 GDExtension 웹 빌드도 같은 버전이어야 합니다.
- 위 템플릿은 GDScript용(스레드 없음)입니다. C# 웹 프로젝트는 아래의 별도 `.mono` 템플릿(스레드 사용)이 필요합니다.

### C#(.NET) 웹 내보내기

- **.NET 11**(`net11.0`) 대상입니다. 게임 프로젝트도 템플릿과 같은 버전이어야 합니다. .NET 9는 2026-11-10에 지원이 끝났습니다.
- `module_mono_enabled=yes`로 이 브랜치에서 빌드한 C# 편집기와 `.mono` 웹 템플릿이 필요합니다. 방법은 [patches/dotnet-web-export.md](patches/dotnet-web-export.md)에 있습니다.
- 결과물은 `enhanced_dotnet_release.yml` 워크플로가 성공하면 [Releases](https://github.com/joygram/godot-enhanced/releases)에 올라옵니다. 아직 올라와 있지 않습니다.
- C# 웹 빌드에서는 GDExtension을 쓸 수 없습니다. 스레드를 쓰는 템플릿이라 호스팅에서 COOP / COEP 헤더가 필요합니다.
- C++만 바뀌는 것이 아닙니다. C#, MSBuild, SCons 파일도 바뀌어서 빌드에 .NET 11 SDK와 `wasm-tools` 워크로드가 필요하고, 편집기와 함께 `GodotSharp` 어셈블리·NuGet 패키지가 배포됩니다.

### 새 Godot 버전으로 옮기기

```sh
git remote add upstream https://github.com/godotengine/godot.git
git fetch upstream --tags
git checkout -b <새 버전>-enhanced <새 버전>-stable
git cherry-pick 4.7.2-stable..origin/main
```

### 상태

- 공식 Godot 빌드가 아니며, 아직 업스트림에 제출하지 않았습니다.
- Godot 4.7.2에서만 확인했습니다. 다른 버전에서는 검증하지 않았습니다.
- 라이선스는 Godot과 같은 MIT입니다.
- C# 웹 내보내기 출처: Raul Santos([godotengine/godot#106125](https://github.com/godotengine/godot/pull/106125)), ComplexRobot, Dom Finn.

**검색어:** 고도 엔진 한글 입력, Godot 한글 IME, 한글 입력 시 커서 안 움직임, 한글 씹힘, LineEdit·TextEdit 한글, 고도 웹 빌드 메모리, Godot WASM 메모리 부족, 고도 C# 웹 내보내기, Godot .NET 웹 빌드

---

> 본 작업은 AI와 함께함 · This work was made with AI assistance.
