# GDScript prebuild (0.2.0) — design

- Goal: load exported GDScript without parse / analyze / compile
- Mode: `script_export_mode=3` (Prebuilt), export writes compiled result next to binary tokens
- Fallback: version mismatch or unsupported content → tokens path (mode 2 behavior)

## Baseline (400 scripts, mode 2, Linux headless, 2026-11-17)

| Stage | ms |
|---|---|
| Script loading | 230 |
| Parse | 23 |
| Analyze | 142 |
| Compile | 40 |

- Measured with `GODOT_GDSCRIPT_TIMINGS=1` + [`gdscript-boot.sh`](../misc/scripts/agent_tests/gdscript-boot.sh)

## File (`.gdc`, mode 3)

- Header: magic `GDPB`, format version, engine build hash
- Binary tokens (fallback)
- Prebuilt blob: class tree + functions

## What is stored

- Class flags and names: tool, abstract, local / global / fully qualified name
- Class links: native base name, base script path, subclasses (recursive)
- Class data: members, static vars, constants, signals, rpc config
- Function: code ints, stack / arg sizes, default args, constants, global names
- Function types and children: return / arg types, lambdas (recursive)
- Pointer tables → keys:
  - operator: (op, type A, type B)
  - setter / getter: (type, member)
  - keyed / indexed setter / getter: (type)
  - builtin method: (type, name)
  - constructor: (type, index)
  - utility / gds utility: name
  - MethodBind: (class, method)
- Constants: plain Variant encoded; GDScript ref → path (+ inner class); native class → name; Resource → path
- Data types: kind, builtin, native name, script path, element types

## Runtime-dependent bytecode operands

- `OPCODE_STORE_GLOBAL` global index → codegen records offset; saved as name, re-resolved on load

## Code

- `modules/gdscript/gdscript_prebuild.{h,cpp}` — save / apply
- `GDScript::reload` → apply prebuilt first, fall back to tokens
- Export plugin → mode 3 writes header + tokens + blob
