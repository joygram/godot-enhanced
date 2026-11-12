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

## Result

- Syntax trees freed after the outermost reload instead of living until cache clear.
- Dependency chains no longer stack every tree at once → lower peak static memory during boot compile.
- Script behaviour unchanged; compile errors of depended scripts still reported.
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

- Used with web export templates. Editor hot-reload behaviour: unverified.
- Tested on 4.7.2 only.

## 한국어

- 증상: 서로 의존하는 스크립트가 많으면 부팅 컴파일 때 정적 메모리 최고치 상승. 웹은 WASM 힙이 줄지 않아 그대로 유지.
- 원인: 상호 의존 스크립트의 파서가 서로 참조 → 구문 트리가 컴파일 뒤에도 잔존.
- 변경: 자기 파서 해제 뒤 의존 스크립트 컴파일, 최외곽 reload 종료 시 파서 캐시 해제.
- 효과: 부팅 컴파일 최고 메모리 감소. 공개 수치 없음 — 위 스크립트로 직접 비교.
