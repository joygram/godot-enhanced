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

- `class_name`, preload, 타입 지정 멤버 등으로 서로 참조하는 GDScript가 많은 프로젝트에서 나타납니다.
- 스크립트 하나를 불러오면 의존하는 스크립트 묶음 전체가 함께 로드됩니다.
- 부팅 중 컴파일할 때 정적 메모리 최고치가 높아집니다. 웹에서는 WASM 힙이 한 번 커지면 줄어들지 않아서, 탭 메모리가 높은 채로 남고 메모리가 적은 기기에서는 실행에 실패할 수 있습니다.

### 원인

- 서로 의존하는 스크립트의 파서가 서로를 참조하고 있어서, 컴파일이 끝난 뒤에도 구문 트리가 해제되지 않습니다.
- `GDScriptCompiler::compile`은 자기 파서를 쥔 채로 의존 스크립트를 컴파일합니다. 그래서 의존 사슬에 있는 모든 구문 트리가 한꺼번에 메모리에 올라갑니다.

### 수정 내용

- `GDScript::reload`: 파서를 블록 안에 두어, 의존 스크립트를 컴파일하기 전에 해제합니다.
- `GDScriptCompiler::finish_dependencies` 플래그: reload가 자기 파서를 해제한 뒤 `GDScriptCache::finish_compiling`을 직접 호출합니다.
- `GDScriptCache::enter_reload` / `exit_reload`: reload 깊이를 셉니다. 가장 바깥 reload가 끝나면 캐시된 파서 참조를 모두 해제해 순환 참조를 끊습니다.

### 단계

| 단계 | 변경 | 패치 해시(앞자리) |
|---|---|---|
| 1 | 가장 바깥 reload가 끝날 때 파서 캐시 해제 | `10b4f21d12ad` |
| 2 | + 자기 파서를 해제한 뒤 의존 스크립트 컴파일 | `541da865d923` |

- 두 단계 모두 rpg2d 프로젝트의 GitHub Actions로 웹 템플릿을 빌드해 배포했습니다. 이 브랜치에는 1단계를 포함한 2단계 최종본이 들어 있습니다.
- 1단계만으로는 부팅이 끝난 뒤에 해제될 뿐, 부팅 컴파일 중의 최고치는 그대로였습니다. 2단계에서 구문 트리가 쌓이는 문제를 없애 최고치를 낮췄습니다.

### 결과

- 구문 트리가 캐시를 정리할 때가 아니라 가장 바깥 reload가 끝난 직후 해제됩니다.
- 의존 사슬이 구문 트리를 한꺼번에 붙잡지 않으므로 부팅 컴파일 중 정적 메모리 최고치가 낮아집니다.
- 스크립트 동작은 바뀌지 않으며, 의존 스크립트의 컴파일 오류도 그대로 보고됩니다.
- 공개된 벤치마크 수치는 아직 없습니다. 위 Measure 절의 스크립트로 공식 빌드와 패치 빌드를 직접 비교해 보세요.

### 한계

- 웹 내보내기 템플릿에서 사용했습니다. 편집기 핫 리로드 동작은 검증하지 않았습니다.
- Godot 4.7.2에서만 확인했습니다.

---

> 본 작업은 AI와 함께함 · This work was made with AI assistance.
