# GDScript parser release patch (lower peak memory, aimed at Web / WASM)

- Patch: [godot-4.7.2-gdscript-parser-release.patch](godot-4.7.2-gdscript-parser-release.patch)
- Files: `modules/gdscript/gdscript.cpp`, `gdscript_cache.{h,cpp}`, `gdscript_compiler.{h,cpp}`
- Platform-independent code; matters most on Web where the WASM heap only grows.

## Symptom

- Project with many GDScript files that reference each other (`class_name`, preload, typed members).
- Loading one script pulls its whole dependency cluster.
- Static memory peaks high during boot compile; on Web the WASM heap grows and never shrinks → tab memory stays high, low-memory devices fail.

## Cause

- Parsers of mutually dependent scripts hold references to each other → syntax trees outlive compilation.
- `GDScriptCompiler::compile` compiles depended scripts while the current script's parser is still alive → the whole dependency chain keeps every syntax tree in memory at once.

## Change

- `GDScript::reload`: parser scoped in a block, destroyed before dependencies compile.
- `GDScriptCompiler::finish_dependencies` flag: reload calls `GDScriptCache::finish_compiling` itself, after its own parser is released.
- `GDScriptCache::enter_reload` / `exit_reload`: reload depth counter. When the outermost reload ends, all cached parser refs are cleared, breaking the reference cycles.

## Stages

Built in two steps; each step was shipped as a web template via GitHub Actions in the rpg2d project. This branch carries the final (stage 2) patch, which includes stage 1.

| Stage | Change | Patch sha256 (prefix) |
|---|---|---|
| 1 | Clear cached parser refs when the outermost reload ends (`enter_reload` / `exit_reload`) | `10b4f21d12ad` |
| 2 | + Compile depended scripts after this script's parser is released (`finish_dependencies = false`) | `541da865d923` |

- Stage 1 alone: trees freed after boot, but peak during boot compile still stacked the whole chain.
- Stage 2: removes that stacking → lower peak.

## Result

- Syntax trees freed after the outermost reload instead of living until cache clear.
- Dependency chains no longer stack every tree at once → lower peak static memory during boot compile.
- Script behavior unchanged; compile errors of depended scripts still reported.
- No published benchmark numbers yet. Measure on your project (below).

## Measure

```gdscript
# run with: godot --headless --script probe.gd
extends SceneTree
func _init() -> void:
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		load(str(entry.path))
	print("peak_static_mb=%.1f" % (Performance.get_monitor(Performance.MEMORY_STATIC_MAX) / 1048576.0))
	quit()
```

- Compare official vs patched binary on the same project.
- Web: watch WASM heap size (`HEAP8.length`) after boot.

## Build (web template)

```sh
scons platform=web target=template_release
# with GDExtension support, single-threaded
scons platform=web target=template_release dlink_enabled=yes threads=no
```

## Limits

- Used with web export templates. Editor hot-reload behavior: unverified.
- Tested on 4.7.2 only.

## 한국어

### 증상

- 서로 참조하는 GDScript 가 많은 프로젝트(`class_name`, preload, 타입 지정 멤버).
- 스크립트 하나를 읽으면 의존 묶음 전체가 함께 로드.
- 부팅 컴파일 중 정적 메모리 최고치 상승. 웹은 WASM 힙이 커진 뒤 줄지 않음 → 탭 메모리 고정, 저사양 기기 실패.

### 원인

- 상호 의존 스크립트의 파서가 서로 참조 → 구문 트리가 컴파일 뒤에도 잔존.
- `GDScriptCompiler::compile` 이 자기 파서가 살아 있는 채로 의존 스크립트 컴파일 → 의존 사슬 전체 구문 트리가 동시에 메모리에 쌓임.

### 변경

- `GDScript::reload`: 파서를 블록 안으로 한정, 의존 컴파일 전 해제.
- `GDScriptCompiler::finish_dependencies` 플래그: reload 가 자기 파서 해제 뒤 `GDScriptCache::finish_compiling` 직접 호출.
- `GDScriptCache::enter_reload` / `exit_reload`: reload 깊이 계수. 최외곽 reload 종료 시 캐시된 파서 참조 전부 해제 → 순환 참조 끊음.

### 단계

- 1단계: 최외곽 reload 종료 시 파서 캐시 해제. 패치 해시 `10b4f21d12ad`.
- 2단계: + 자기 파서 해제 뒤 의존 컴파일. 패치 해시 `541da865d923`.
- 두 단계 모두 rpg2d 프로젝트 GitHub Actions 로 웹 템플릿 빌드·배포. 이 브랜치는 2단계(1단계 포함) 최종본.
- 1단계만: 부팅 후 해제는 되나 부팅 컴파일 중 최고치는 그대로. 2단계: 쌓임 제거 → 최고치 감소.

### 결과

- 구문 트리를 캐시 정리 때가 아니라 최외곽 reload 직후 해제.
- 의존 사슬이 구문 트리를 한꺼번에 붙잡지 않음 → 부팅 컴파일 최고 정적 메모리 감소.
- 스크립트 동작 변화 없음. 의존 스크립트 컴파일 오류 보고 유지.
- 공개 벤치마크 수치 없음 → 위 `Measure` 스크립트로 공식판·패치판 직접 비교.

### 한계

- 웹 내보내기 템플릿에서 사용. 편집기 핫 리로드 동작 미검증.
- 4.7.2 에서만 확인.

---

> 본 작업은 AI와 함께함 · This work was made with AI assistance.
