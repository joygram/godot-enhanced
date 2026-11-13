# godot-enhanced 측정 기록 (4.7.2-0.1.1)

- 기준일: 2026-11-14
- 조건: Emscripten 6.0.2, .NET 11 runtime pack, release 템플릿
- 단위: MB = 1048576 바이트
- wasm 힙은 약 20% 단위로 커지므로 계단형 값으로 나옴

## 1. 0.1.1 개선 (C# 웹, YangVillage)

| 항목 | 이전 | 0.1.1 | 변화 |
|---|---|---|---|
| pck | 64.0 | 10.7 | −83% |
| wasm 힙 (YangVillage) | 160.1 | 95.8 | −40% |
| wasm 힙 (빈 C# 프로젝트) | 154.1 | 79.8 | −48% |
| 관리 힙 | 4.3 | 1.3 | −70% |

적용 항목:
- pck 정리: 웹에서 `.a`, `icudt*.dat`, `package.json`, `wasm-props.json` 제외
- 어셈블리 `need_copy=false`: 데이터 고정 후 복사 없이 열기
- IL 트리밍 (`PublishTrimmed`)
- GC: `MONO_GC_PARAMS=nursery-size=1m`

## 2. GDScript 파서 해제 (rpg2d, 로그 근거)

- 부팅 정적 메모리(`autoload_first`)
  - 패치 전: 145.8–165.5MB (16회)
  - 패치 후: 67.4–68.0MB (13회)
  - 약 −56%
- 패치 에디터 첫 실행(10:07, 릴리스 `88690556f4`)부터 하락

## 3. GDScript vs C# (클래스 200개, nothreads, release)

세 브라우저(Windows Chrome, Mac Safari, Linux Chromium) 힙 값 동일.

| 항목 | GDScript | C# | 차이 |
|---|---|---|---|
| wasm 힙 | 38.4 | 55.4 | +17.0 (.NET 런타임 고정 비용) |
| pck | 0.17 | 7.29 | +7.1 |
| wasm 파일 | 36.4 | 39.4 | +3.0 |

속도 (ms, GD / C#, 각 1회 측정):

| 브라우저 | 부팅 | 수학 | 객체 | 컬렉션 |
|---|---|---|---|---|
| Windows Chrome | 461 / 490 | 69.6 / 23.2 | 109.3 / 90.6 | 57.3 / 45.6 |
| Mac Safari | 350 / 353 | 110.8 / 50.4 | 122.7 / 172.4 | 56.1 / 63.4 |
| Linux Chromium | 657 / 662 | 130.7 / 33.1 | 183.5 / 150.6 | 91.5 / 74.7 |

- 부팅: 차이 없음
- 수학: C# 2.2~4배 빠름
- 객체·컬렉션: Chrome 계열은 C# 우세, Safari 는 GDScript 우세
- 1회 측정 → 편차 미검증

## 4. GodotSharp 트리밍 (YangVillage)

| 항목 | 트리밍 전 | 후 |
|---|---|---|
| GodotSharp.dll | 5.39 | 2.56 |
| pck | 22.6 | 19.5 |
| wasm 힙 | 238.5 | 238.5 |

- 실행·저장/불러오기 정상
- 힙 변화 없음: 다운로드만 줄어듦
- 현재 YangVillage `.csproj` 실험 타깃(`UnrootGodotSharp`)만, SDK 기본값 미반영

## 5. AOT vs 인터프리터 (cs200)

| 항목 | 인터프리터 | AOT |
|---|---|---|
| wasm 파일 | 39.4 | 54.2 (+15) |
| wasm 힙 | 55.4 | 66.5 (+11) |
| 다운로드 합계 | 46.7 | 61.5 |
| 템플릿 | 공용 | 게임 전용, 내보내기마다 재빌드 3~4분 |
| 속도 | 위 표 | 미측정 (`aot-runtime-wasm.c:188` 오류로 실행 실패) |

- 고정 비용 확정, 속도 이득 미검증
- Mono 인터프리터 최적화 옵션 점검: 미착수

## 6. 템플릿 변형

| 변형 | 상태 | 비고 |
|---|---|---|
| threads | 동작 | COOP/COEP 필요 |
| nothreads | 동작 | `diagnostics_tracing` 스텁 링크 |

- threads vs nothreads 같은 프로젝트 비교: 미측정

## 7. 광고 호환 (AdSense 스크립트·iframe·이미지)

| 헤더 모드 | Safari 27.2 | Windows Chrome | Linux Chromium |
|---|---|---|---|
| 헤더 없음 | 로드 | 로드 | 로드 |
| COEP `require-corp` | 로드 | 로드 | 로드 |
| COEP `credentialless` | 미지원 | 로드 | 로드 |

- Safari 에서 threads 쓰려면 `require-corp`
- 실제 승인 사이트 광고 채움: 미검증

## 8. 빌드·릴리스

| 머신 | 산출물 | 결과 |
|---|---|---|
| Linux (b1-w01) | editor zip | `editor-4.7.2-0.1.1` 업로드 |
| Mac (joyui-macmini) | editor zip | `editor-4.7.2-0.1.1` 업로드 |
| Windows (로컬) | web 템플릿 threads / nothreads | 동작 |

- 원격 에이전트: `misc/scripts/remote_build.mjs` (비차단), 대시보드 `misc/scripts/dashboard.mjs`
- 검사: `smoke-editor`, `web-memory`, `web-memory-url`, `ad-compat`

## 9. ICU 일반 링크 + release 개발 컴포넌트 스텁 (cs200, Windows Chrome, 2회씩)

| 항목 | 기존 템플릿 | 새 템플릿 |
|---|---|---|
| wasm 파일 | 39.37 | 39.25 (−0.12) |
| wasm 힙 | 66.5 | 66.5 |
| 부팅 ms | 417–421 | 436–448 |

- 효과 거의 없음 → ICU 는 이미 Invariant, 링커가 대부분 걸러내고 있었음
- 같은 날 재측정 기존 힙 66.5 (3절 55.4 와 다름, 원인 미확인)

## 10. rpg2d DB + 아이콘 300개 (godot-sqlite, Windows Chrome)

| 항목 | GDScript | C# |
|---|---|---|
| wasm 힙 부팅 → DB 후 | 38.4 → 198.8 | 측정 불가 |
| DB 205테이블 80,108행 | 370ms | 측정 불가 |
| 아이콘 300개 | 36ms, 힙 계단 안 넘음 | 측정 불가 |

- C# + GDExtension(dlink) 템플릿 링크 실패: .NET 런타임 팩 `.a` 가 PIC 아님 (`recompile with -fPIC`)
- 즉 C# 웹에서는 godot-sqlite 같은 GDExtension 사용 불가

## 남은 것

- AOT 실행 오류 해결 후 속도 측정, 또는 보류
- Mono 인터프리터 최적화 점검
- GodotSharp 트리밍 SDK 기본값 여부
- threads vs nothreads 비교
- 속도 반복 측정 (편차)
