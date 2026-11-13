# godot-ime — Godot 4.7.2 with Korean IME fix and Web (WASM) GDScript memory patch

Patched build of [Godot Engine](https://github.com/godotengine/godot) `4.7.2-stable`. Upstream history kept intact; two small patches on top.

**Keywords:** Godot Korean IME, Godot 한글 입력 버그, Godot Hangul input, Windows IME composition, CJK input, LineEdit / TextEdit caret, Godot web export memory, WASM heap, GDScript parser memory, HTML5 export out of memory.

| Patch | Platform | Fixes |
|---|---|---|
| [Windows IME queued key](patches/windows-ime-queued-key.md) | Windows editor + game | Korean (Hangul) typing loses caret advance after a syllable is committed |
| [GDScript parser release](patches/gdscript-parser-release.md) | All, aimed at Web / WASM | Syntax trees of mutually dependent scripts stay alive after compile → high peak memory at boot |

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
```

Apply both (as above), or only the one you need — each patch also applies on its own, in any order.

## Prebuilt Web export template

- GitHub Actions ([ime_web_template.yml](.github/workflows/ime_web_template.yml)) builds the Web template from this branch and publishes it on [Releases](https://github.com/joygram/godot-ime/releases).
- Assets: `godot.web.template_release.wasm32.nothreads.dlink.zip` (GDExtension support), `godot.web.template_release.wasm32.nothreads.zip`.
- Use: Web export preset → Custom Template → Release → the zip.
- Emscripten 4.0.11. With dlink, your GDExtension web builds must use the same version.

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

---

## 한국어 안내

Godot 4.7.2 공식 소스에 패치 두 개를 더한 빌드입니다. 업스트림 커밋 이력은 그대로 유지합니다.

| 패치 | 플랫폼 | 해결하는 문제 |
|---|---|---|
| [Windows 한글 IME 패치](patches/windows-ime-queued-key.md) | Windows 편집기·게임 | 한글 음절을 확정한 뒤 다음 글자를 입력하면 커서가 앞으로 가지 않는 문제 |
| [GDScript 파서 해제 패치](patches/gdscript-parser-release.md) | 전체 (웹/WASM에서 효과 큼) | 서로 참조하는 스크립트의 구문 트리가 컴파일 뒤에도 남아 부팅 때 메모리 최고치가 높아지는 문제 |

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

가지고 있는 Godot 4.7.2 소스에 패치만 적용해도 됩니다. 두 패치를 함께 적용해도 되고, 필요한 것 하나만 적용해도 됩니다. 적용 순서는 상관없습니다.

```sh
# 둘 다
git apply patches/godot-4.7.2-windows-ime-queued-key.patch patches/godot-4.7.2-gdscript-parser-release.patch
# 하나만
git apply patches/godot-4.7.2-windows-ime-queued-key.patch
```

### 미리 빌드된 웹 템플릿

- GitHub Actions가 이 브랜치로 웹 내보내기 템플릿을 빌드해 [Releases](https://github.com/joygram/godot-ime/releases)에 올립니다.
- `godot.web.template_release.wasm32.nothreads.dlink.zip`: GDExtension을 쓰는 프로젝트용
- `godot.web.template_release.wasm32.nothreads.zip`: 일반 프로젝트용
- 웹 내보내기 프리셋의 Custom Template → Release에 zip 파일을 지정하면 됩니다.
- Emscripten 4.0.11로 빌드했습니다. dlink 템플릿을 쓴다면 GDExtension 웹 빌드도 같은 버전이어야 합니다.

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

**검색어:** 고도 엔진 한글 입력, Godot 한글 IME, 한글 입력 시 커서 안 움직임, 한글 씹힘, LineEdit·TextEdit 한글, 고도 웹 빌드 메모리, Godot WASM 메모리 부족

---

> 본 작업은 AI와 함께함 · This work was made with AI assistance.
