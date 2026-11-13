# Windows IME queued key patch (Korean / Hangul input fix)

- Patch: [godot-4.7.2-windows-ime-queued-key.patch](godot-4.7.2-windows-ime-queued-key.patch)
- File: `platform/windows/display_server_windows.cpp`, `WM_IME_STARTCOMPOSITION`
- Size: 1 condition, 2 lines

## Symptom

- Windows, Korean IME (Microsoft 한글 입력기).
- Type `가나다라마바사` in the editor or an in-game `LineEdit` / `TextEdit`.
- After a syllable is committed, the next character does not advance the caret.
- Latin typing unaffected.

## Cause

- Godot queues key messages in `key_event_buffer` and processes them later.
- On `WM_IME_STARTCOMPOSITION` it drops the last queued event, assuming it is the key-down that started the composition.
- Korean IME commits the previous syllable and starts the next composition in one keystroke → the last queued event can be the committed `WM_CHAR`, not a key-down.
- That event was dropped unconditionally.

## Change

- Drop the last queued event only when it is `WM_KEYDOWN` or `WM_SYSKEYDOWN`.

```diff
-				if (key_event_pos > 0) {
+				if (key_event_pos > 0 &&
+						(key_event_buffer[key_event_pos - 1].uMsg == WM_KEYDOWN || key_event_buffer[key_event_pos - 1].uMsg == WM_SYSKEYDOWN)) {
 					key_event_pos--;
 				}
```

## Result

- Continuous Hangul typing keeps every syllable; caret ends after the last one.
- Confirmed by hand in the editor script/text fields and an in-game input box (`가나다라마바사`).
- No automated test. Japanese / Chinese IME: unverified.

## Build

```sh
python -m SCons platform=windows target=editor arch=x86_64
# export templates need separate builds
python -m SCons platform=windows target=template_release arch=x86_64
python -m SCons platform=windows target=template_debug arch=x86_64
```

## 한국어

### 증상

- Windows에서 Microsoft 한글 입력기를 쓸 때 발생합니다.
- 편집기나 게임 안의 `LineEdit` / `TextEdit`에 `가나다라마바사`처럼 이어서 입력하면, 한 음절이 확정된 직후 다음 글자에서 커서가 앞으로 가지 않습니다.
- 영문 입력에는 문제가 없습니다.

### 원인

- Godot은 키 메시지를 `key_event_buffer`에 모아 두었다가 나중에 처리합니다.
- 조합이 시작될 때(`WM_IME_STARTCOMPOSITION`) 버퍼의 마지막 이벤트를 "조합을 시작한 키다운"으로 보고 무조건 지웁니다.
- 한글 IME는 키 한 번으로 이전 음절을 확정하고 다음 조합을 시작합니다. 그래서 버퍼의 마지막 이벤트가 확정된 글자(`WM_CHAR`)일 수 있고, 이 이벤트까지 지워졌습니다.

### 수정 내용

- 버퍼의 마지막 이벤트가 `WM_KEYDOWN` 또는 `WM_SYSKEYDOWN`일 때만 지우도록 조건을 하나 추가했습니다(2줄).

### 결과

- 한글을 이어서 입력해도 모든 음절이 남고, 커서가 마지막 글자 뒤에 놓입니다.
- 편집기 텍스트 입력과 게임 입력창에서 `가나다라마바사`를 직접 입력해 확인했습니다.
- 자동 테스트는 없습니다. 일본어·중국어 IME에서는 검증하지 않았습니다.

### 빌드

- 위 Build 절의 명령을 그대로 쓰면 됩니다. 내보내기 템플릿은 `template_release`와 `template_debug`를 따로 빌드해야 합니다.

---

> 본 작업은 AI와 함께함 · This work was made with AI assistance.
