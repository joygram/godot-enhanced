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

Patches are independent. Apply either one alone.

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

Godot 4.7.2 공식 소스에 패치 2개를 얹은 빌드. 업스트림 이력 그대로 유지.

- **Windows 한글 IME 패치**: 한글 음절 확정 후 다음 글자 입력 시 커서가 전진하지 않던 문제 수정. 편집기·게임 입력창 공통. → [상세](patches/windows-ime-queued-key.md)
- **GDScript 파서 해제 패치 (웹/WASM)**: 서로 의존하는 스크립트의 구문 트리가 컴파일 뒤에도 남던 것을 해제. 부팅 컴파일 최고 메모리 감소. → [상세](patches/gdscript-parser-release.md)
- 사용: `4.7.2-ime` 브랜치 빌드, 또는 `patches/*.patch` 를 4.7.2 소스에 `git apply`.
- 검색어: 고도 한글 입력, 고도 엔진 한글 IME, Godot 한글 깨짐·씹힘, 커서 안 움직임, 고도 웹 빌드 메모리.
