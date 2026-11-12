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

- Windows, 한국어 IME(Microsoft 한글 입력기).
- 편집기 또는 게임 내 `LineEdit` / `TextEdit` 에 `가나다라마바사` 연속 입력.
- 음절 확정 직후 다음 글자 입력 시 커서 전진 실패.
- 영문 입력은 정상.

### 원인

- Godot 은 키 메시지를 `key_event_buffer` 에 쌓았다가 나중에 처리.
- `WM_IME_STARTCOMPOSITION` 에서 마지막 대기 이벤트를 조합 시작 키다운으로 보고 무조건 제거.
- 한글 IME 는 한 번의 키 입력으로 이전 음절 확정 + 다음 조합 시작 → 마지막 대기 이벤트가 확정 문자(`WM_CHAR`)일 수 있음.
- 그 확정 문자 이벤트까지 삭제됨.

### 변경

- 마지막 대기 이벤트가 `WM_KEYDOWN` / `WM_SYSKEYDOWN` 일 때만 제거.

### 결과

- 한글 연속 입력 시 모든 음절 유지, 커서가 마지막 글자 뒤에 위치.
- 편집기 텍스트 입력·게임 입력창에서 `가나다라마바사` 수동 확인.
- 자동 테스트 없음. 일본어·중국어 IME 미검증.

### 빌드

- 위 `Build` 절 명령 그대로. 내보내기 템플릿은 `template_release` / `template_debug` 별도 빌드.

---

> 본 작업은 AI와 함께함 · This work was made with AI assistance.
