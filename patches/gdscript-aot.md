# GDScript AOT — 사전 빌드(.gdc) → C++ (1.0.1) — 설계

- 목표: 사전 빌드 함수 → C++ → clang 네이티브. VM 분기 루프 제거
- 컴파일러: clang 계열 (emcc·clang·Xcode·MSVC)
- 원칙: 명령 의미 새로 안 씀 → VM 명령 본문 그대로 재사용

## 방식

- VM 명령 본문 → `modules/gdscript/gdscript_vm_ops.inc` 분리, VM·AOT 공용 (VM 동작 변화 없음)
- 함수마다 C++ 한 개:
  - 바이트코드 → `static const int code[]` (상수)
  - 명령마다 라벨 `L<ip>:` + 그 명령 본문만 include (`AOT_OP`·`ip` 상수)
  - 순차 진행·점프 → `switch (ip)` → clang 상수 전파로 직접 점프
  - 피연산자 주소 = 상수 → 스택 고정 오프셋
- 스택·인자·반환·오류 처리 = VM `call` 앞뒤 그대로

## 범위

- 대상: `await` 없는 함수
- `await` 든 함수 → VM 유지 (`GDScriptFunctionState` 그대로, 흐름 코드라 속도 무관)
- 람다 → 1차 제외, VM 유지
- 지원 안 되는 명령 하나라도 있으면 → 그 함수 통째 VM

## 연결

- `GDScriptFunction` 에 네이티브 포인터 추가
- `GDScriptFunction::call` → 포인터 있으면 네이티브, 없으면 VM
- 등록 표: (스크립트 경로, 함수 이름, 바이트코드 해시) → 포인터. 해시 다르면 미적용 → VM
- VM ↔ 네이티브 상호 호출 = 기존 call 경로 그대로

## 생성·빌드

- 생성: 내보내기 때 사전 빌드 직후 → `gdscript_aot/<스크립트>.cpp` + 등록 표
- 데스크톱·iOS: 템플릿과 정적 링크
- 웹 static: 템플릿에 링크 (게임별 템플릿 빌드)
- 웹 dlink: side module(.wasm) 따로 → 엔진 템플릿 재사용

## 검증

- 에이전트 검사 `gdscript-prebuild` 기능 스크립트 → VM·AOT 출력 비교
- `gdscript-boot` 벤치 + rpg2d → 속도·wasm 크기 실측

## 이후

- C# IL → 같은 중간 단계 → 같은 C++ 생성기 (참조 카운트 + 순환 수거기)

## 단계

1. VM 명령 본문 `.inc` 분리 — 동작 동일 확인
2. 생성기: await·람다 없는 함수만, 데스크톱 정적 링크
3. 등록 표·해시 검사·VM 대체
4. 웹 static → dlink side module
