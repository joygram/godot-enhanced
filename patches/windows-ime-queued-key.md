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

- 증상: 한글 음절 확정 후 다음 글자 입력 시 커서 전진 실패.
- 원인: 조합 시작 메시지에서 마지막 대기 이벤트를 무조건 제거 → 확정 문자 이벤트까지 삭제.
- 변경: 마지막 대기 이벤트가 키다운일 때만 제거.
- 확인: 편집기·게임 입력창에서 `가나다라마바사` 연속 입력·커서 전진 정상(수동 확인).
