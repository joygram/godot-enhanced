# godot-enhanced — Godot 4.7.2 with smaller web downloads, Web (WASM) memory patch, C# web export, Korean IME fix and verified Japanese input

Patched build of [Godot Engine](https://github.com/godotengine/godot) `4.7.2-stable`. Upstream history kept intact; patches on top.

## 🐱 Showcase — a Unity game moved to godot-enhanced C#, almost untouched

Same game, two engines. YangVil (cat-raising RPG) ported from Unity to godot-enhanced C# (.NET 11).

- Unity: [joygram/YangVil](https://github.com/joygram/YangVil) · play: https://yangvil.deuklab.workers.dev
- **godot-enhanced C#**: [joygram/yangvil-godot-csharp](https://github.com/joygram/yangvil-godot-csharp) · play: https://yangvil-godot-csharp.deuklab.workers.dev
- Web build of the Godot version = built with godot-enhanced `dotnet-web-4.7.2-0.3.0`

**1. Easy Unity migration**
- Game rules C#: copied as-is (9 of 702 lines changed, save JSON only)
- Art + data tables: same 28 images + 26 tables, unchanged
- UI: engine API mapped 1:1 to Godot nodes, **−25% code**

**2. No license burden**
- Engine = Godot (MIT) + godot-enhanced patches: no runtime fee, royalty or seat cost
- Game code = MIT, full engine source open

**3. Easy C# web deploy**
- C# web export that stock Godot 4 lacks
- One command: latest engine → web build → compress → Cloudflare deploy
- **−44% download** vs Unity (12.2 MB vs 21.8 MB)
- .NET 11, latest C# and standard library

**Measured side by side** (same PC, headless Chrome, no cache)

| Web build (median of 3) | Unity WebGL | C# stock template | C# AOT template |
|---|---|---|---|
| Transfer size | 21.8 MB | **12.2 MB (−44%)** | 14.6 MB |
| First screen | **3.10 s** | 4.44 s | 4.70 s |
| Memory (Chrome total) | **650 MB** | 758 MB | 788 MB |

- AOT template = game AOT output linked via `mono_wasm_aot_dir=` (agent test `dotnet-web-aot`)
- AOT gives no startup gain: startup = wasm compile + engine init; AOT helps C# run time
- Reproduce: `node scripts/web/compare.mjs 3` in yangvil-godot-csharp

## 🔧 0.3.1 — Fix: GDScript prebuild crashed on web (bytecode made on 64-bit, run on wasm32)

| Prebuild (`script_export_mode=3`) on web | 0.3.0 | **0.3.1** |
|---|---|---|
| Boot | crash | **✔** |

- Error: `Index p_op = 156 is out of bounds (Variant::OP_MAX = 25)`, `RuntimeError: operation does not support unaligned accesses`
- Cause: `OPCODE_OPERATOR` cache size followed pointer size (2 slots on 64-bit editor, 1 on wasm32) → instruction length mismatch
- Fix: cache fixed at 2 slots on every platform (`GDScriptFunction::OPERATOR_CACHE_SLOTS`), prebuild format 2 (old prebuilds fall back to tokens)

## 🚀 0.3.0 — GDScript prebuild ships everywhere, all web on Emscripten 7.0.0 (C# too)

| 0.3.0 release | Contents | Status |
|---|---|---|
| `editor-4.7.2-0.3.0` | editors ×6 + export_templates.tpz | ✔ 5 runners verified |
| `web-template-4.7.2-0.3.0` | threads / nothreads × static / dlink | ✔ Emscripten 7.0.0 |
| `dotnet-web-4.7.2-0.3.0` | C# kits Linux · macOS · Windows | ✔ Emscripten 7.0.0 |

**GDScript prebuild in every release** (`script_export_mode=3`)
- Editor + templates from the same release → prebuilt bytecode loads, no parse · analyze · compile
- Template folder `4.7.2.stable.enhanced-0.3.0` keeps editor and templates paired

**C# web on Emscripten 7.0.0**

| C# web template link | 6.0.2 pin | **0.3.0 (7.0.0)** |
|---|---|---|
| release / debug × threads / nothreads | needed old toolchain | **✔ 4 of 4 linked** |

- Error: `undefined symbol: _Unwind_CallPersonality` (`libmono-wasm-eh-wasm.a`)
- Cause: .NET 11 runtime pack prebuilt by Emscripten 6; LLVM 23 renamed it `__gxx_wasm_personality_v0`
- Fix: old name forwards to the new one ([gd_mono_wasm_unwind.cpp](modules/mono/mono_gd/gd_mono_wasm_unwind.cpp))

**Cleanup**
- Removed broken releases `web-template-4.7.2-0.1.9`, `0.2.0` (threads + dlink crash at startup)

## 🔧 0.2.1 — Fix: Emscripten 7.0.0 (latest), web threads + GDExtension work again

- Fix, not a new feature: stock Godot already supports web threads + GDExtension
- Emscripten 7.0.0 (latest) supported, multithreaded web included
- Resolved: 0.2.0 threads + dlink template crashed at startup

| Web template | 0.2.0 (Emscripten 6.0.2) | **0.2.1 (7.0.0)** |
|---|---|---|
| threads + dlink (GDExtension) | ✘ crash at startup | **✔ boots** |
| real game (SQLite GDExtension, threads) | ✘ stalls 49% | **✔ boot 10 s, 0 errors** |

- Web templates (GDScript): Emscripten 6.0.2 → **7.0.0**, set in `misc/scripts/emscripten-version`
- Error: `setting 'sig'`, then GL `LinkError`
- Cause: 6.0.2 bound GL aliases to wasm exports before instantiation
- GDExtension web builds: rebuild with 7.0.0 (6.0.2 side modules → `resolved is not a function`)

## ⚡ 0.2.0 — GDScript prebuild, export templates locked to the release

**GDScript prebuild** (`script_export_mode=3`)
- Export stores compiled classes + bytecode; load skips parse · analyze · compile
- Mismatch or unsupported content → falls back to binary tokens (mode 2)
- Baseline to beat (400 scripts, mode 2): analyze 142 ms, compile 40 ms, parse 23 ms
- Check: agent test `gdscript-prebuild` runs feature scripts in mode 2 and 3, compares output
- Design: [patches/gdscript-prebuild.md](patches/gdscript-prebuild.md)

**Export templates locked**
- Template folder: `4.7.2.stable` → **`4.7.2.stable.enhanced-0.2.0`**
- Editor exports only with templates from its own release; stock Godot or another release never picked up
- Applies to: export lookup, template manager, C# export
- Install: put release templates in `export_templates/4.7.2.stable.enhanced-<version>/`

## ✂️ 0.1.9 — C# iOS: GodotSharp trimming works, binary −63% (opt-in)

| `ios-arm64` NativeAOT, sample C# project | Default | **`GodotTrimGodotSharp=true`** |
|---|---|---|
| `Game.dylib` | 18.6 MB | **6.8 MB (−63%)** |
| Simulator app (Debug) | 139.9 MB | **111.6 MB** |
| Simulator run | ✔ `trim ok 3` | ✔ `trim ok 3` |

- 0.1.7 trimmed build failed at runtime: `instance_create(): native_name == StringName()`
- Cause: NativeAOT removed `NativeName`, which Godot reads by reflection
- Fix: keep list [`GodotSharp.TrimRoots.xml`](modules/mono/editor/Godot.NET.Sdk/Godot.NET.Sdk/Sdk/GodotSharp.TrimRoots.xml), only those fields kept
- Turn on: `<GodotTrimGodotSharp>true</GodotTrimGodotSharp>` in the `.csproj`
- Opt-in: verified on one sample project only

## 🍎 0.1.8 — C# on iOS runs again (.NET 11), verified in the simulator

> With .NET 11, Godot C# iOS exports built but the game had no C#: "`.NET: Failed to load hostfxr`". Fixed and run-tested.

| iOS Simulator (iOS 27.2), sample C# project | Before | **0.1.8** |
|---|---|---|
| Export | "project assembly not found" | **OK** |
| App start | `.NET: Failed to load hostfxr` | **C# `_Ready` runs, `[Export]` array intact** |

- Cause: .NET 11 NativeAOT names the library `libGame.dylib`; Godot looks for `Game.dylib`
- Fix: export plugin drops the `lib` prefix after publish and sets the install name
- Test: [`ios-sim-csharp.sh`](misc/scripts/agent_tests/ios-sim-csharp.sh) — export → `xcodebuild` → `simctl` run → log `trim ok 3`
- Not verified: physical device

## 🧩 0.1.6 — GDExtension web builds pre-compressed too (side module −76%)

> Web games with GDExtensions (dlink) load a ~43 MB `.side.wasm`. 0.1.3 compression skipped it; now it's covered.

| dlink web export (`extensions_support`) | Before | **0.1.6** | |
|---|---|---|---|
| `.side.wasm` (engine side module) | 42.8 MB | **10.1 MB** | **−76%** |
| `.wasm` (main module) | 1.3 MB | **0.5 MB** | **−58%** |

- `.side.wasm` now fetched by the Godot preloader → gzip inflate + loading bar progress
- Handed to Emscripten as a blob URL; no server config
- Verified: headless Chrome, static and dlink exports, 0 errors, heap 38.4 MB both
- Test: [`web-memory.sh`](misc/scripts/agent_tests/web-memory.sh) runs both variants when a dlink template exists

## 📱 0.1.5 — C# Android: managed code −83%, trimmed by default

> Godot C# Android exports ship the whole .NET framework and `GodotSharp`. godot-enhanced trims them, same rule as the web.

| `android-arm64` publish (sample C# project) | Before | **0.1.5** | |
|---|---|---|---|
| Managed `.dll` total | 29.8 MB | **5.0 MB** | **−83%** |
| `GodotSharp.dll` | 5.9 MB | **2.8 MB** | **−52%** |
| Publish folder (with native runtime) | 100.1 MB | **74.9 MB** | **−25%** |

- `PublishTrimmed` on by default for Web and Android; game assembly kept whole (scripts found by reflection)
- One rule in `Sdk.targets` for both platforms. iOS unchanged (NativeAOT)
- Opt out: `<PublishTrimmed>false</PublishTrimmed>`, or keep more with `TrimmerRootAssembly`
- Measured: Linux agent, .NET 11, test [`dotnet-trim.sh`](misc/scripts/agent_tests/dotnet-trim.sh), 2026-11-17
- Not yet verified: running on an Android device

## 🇯🇵 0.1.4 — Japanese input on Linux, verified (日本語入力 OK)

> "Godot won't take Japanese on Linux" — tested on X11 and Wayland with fcitx5 + Mozc, now checked on every agent run.

| Session | Switch | Result |
|---|---|---|
| X11 + fcitx5 | tray / `fcitx5-remote` | `にほんご` ✔ |
| X11 + fcitx5 | `Ctrl+Space` | `にほんご` ✔ |
| Wayland (sway) + fcitx5 | tray / `fcitx5-remote` | `にほんご` ✔, preedit shown |
| Wayland (sway) + fcitx5 | `Ctrl+Space` | `にほんご` ✔, preedit shown |

- Engine unchanged: X11 (XIM) and Wayland (`text-input-v3`) both work
- `Ctrl+Space` reaches fcitx5, not swallowed
- First key right after the first Mozc use may come out Latin → Mozc start-up, same in a plain Xlib app
- Not verified: KDE KWin (headless KWin can't inject keys)
- Setup tips, method, raw results: [patches/linux-ime-japanese.md](patches/linux-ime-japanese.md)
- Tests: [`ime-linux.sh`](misc/scripts/agent_tests/ime-linux.sh), [`ime-wayland.sh`](misc/scripts/agent_tests/ime-wayland.sh)

## 🗜️ 0.1.3 — web download up to −75%, no server setup

> Godot web games are big, and most hosts (itch.io, game portals) don't let you set compression headers. godot-enhanced compresses at export and unpacks in the browser.

| Web download | Before | **Pre-compressed** | |
|---|---|---|---|
| Engine `.wasm`, GDScript template | 36.4 MB | **9.3 MB** | **−75%** |
| Engine `.wasm`, C# template | 39.3 MB | **10.4 MB** | **−73%** |
| Game `.pck` (rpg2d) | 36.5 MB | **22.9 MB** | **−38%** |
| **rpg2d total** (wasm + pck) | 72.9 MB | **32.2 MB** | **−56%** |

- Export option **`compression/precompress`** (Web preset, default off) → `.pck` and `.wasm` gzipped in place
- Loader sees the gzip signature → inflates with the browser's `DecompressionStream`. No server config
- File names unchanged → no double-decompress if the host also gzips
- Loading bar counts downloaded (compressed) bytes
- Measured: gzip -6 on existing exports, 2026-11-17
- Verified: headless Chrome boots a pre-compressed export (wasm 9.7 MB on disk), 0 errors, heap unchanged (38.4 MB)
- dlink `.side.wasm`: covered from 0.1.6. Not yet: C# runtime files (loaded outside the Godot preloader)

## 🚀 0.1.1 — C# on the web, and it's light

> Official Godot 4 **cannot** export C# to the web. godot-enhanced does — then cuts it down hard.

| C# web build (real game, .NET 11) | Before | **0.1.1** | |
|---|---|---|---|
| Download (`.pck`) | 64.0 MB | **10.7 MB** | **−83%** |
| WASM heap after boot | 160.1 MB | **95.8 MB** | **−40%** |
| Empty C# project, WASM heap | 154.1 MB | **79.8 MB** | **−48%** |
| Managed (.NET) heap under load | 4.3 MB | **1.3 MB** | **−70%** |
| Errors in browser | 0 | **0** | save/load verified |

- **PCK diet**: unused `.a`, ICU data, build metadata dropped → 64 → 30 MB
- **Zero-copy assembly load**: `need_copy=false`, no permanent copy peak → heap 160 → 115 MB
- **IL trimming**: unused framework code removed; game + `GodotSharp` kept → 30 → 10.7 MB
- **Web-tuned GC**: 1 MB SGen nursery → shorter minor GCs. Override: `MONO_GC_PARAMS`
- **.NET 11** runtime pack, Emscripten 6.0.2
- Also: Windows Hangul IME fix

### 🔍 GDScript web: a memory leak found in Godot's compiler

- Tracked: rpg2d web boot → WASM heap kept growing, never came back down
- Found: GDScript parsers of mutually dependent scripts hold each other → syntax trees never freed
- Found: compiling a script pulls its whole dependency chain → every tree in memory at once
- Fixed: parser released before dependencies compile; cached parsers cleared after the outermost reload
- Result: trees freed right after compile, lower boot peak. Script behavior unchanged
- Applies to every GDScript project, not only C#. Biggest win on web (heap never shrinks)

| rpg2d boot static memory (`autoload_first`) | Before | **After** | |
|---|---|---|---|
| Desktop run logs, 2026-11-13 | 145.8 – 165.5 MB (16 runs) | **67.4 – 68.0 MB** (13 runs) | **≈ −56%** |

- Drop starts with the first run on the patched editor (10:07, release `88690556f4`)

## 🧩 0.1.2 — GDExtensions in C# web, 3 C# web crashes fixed

> C# web games can now use GDExtensions (e.g. SQLite). Not possible with dlink: the .NET runtime is not PIC.

| C# web crash (any C# web game) | Fix |
|---|---|
| `Variant.As*()`, `Call()` → `aot-runtime-wasm.c:188` | All engine call signatures in the interpreter table |
| `await ToSignal` → `function signature mismatch` | `Error` interop returns 64-bit, matching C# |
| Single-threaded export picked the threaded runtime | Thread choice set early (`Browser.props`) |

| SQLite on the web (rpg2d DB, 80k rows, Chrome) | Heap after | DB read | Download |
|---|---|---|---|
| GDScript + GDExtension (dlink) | 198.8 MB | 386 ms | 77.7 MB |
| **GDScript + static link** | 198.8 MB | **292 ms (−24%)** | **67.8 MB (−9.8)** |
| **C# + static link** (new) | 238.5 MB | **290 ms** | 77.8 MB |
| C# + `Microsoft.Data.Sqlite` | 194.3 MB | 2,228 ms | 77.7 MB |

| 200 classes, same test (Chrome) | GDScript | C# |
|---|---|---|
| WASM heap | 38.4 MB | 55.4 MB (+17, .NET runtime) |
| Integer math | 69.6 ms | **23.2 ms (3×)** |
| Object / collections | 109.3 / 57.3 ms | 90.6 / 45.6 ms |

- `static_gdextensions=sqlite`: GDExtension linked into the web template, source unchanged
- Prebuilt `.a` (release/debug × threads/nothreads) on release `static-gdext-emsdk6.0.2`, fetched by name
- `mono_wasm_native_packages=Id/Version`: NuGet native libraries (e.g. `e_sqlite3`) in the C# template
- C# web templates: threads and **nothreads** (no COOP / COEP needed)
- Shared build cache: Mac reused 1,932 Linux-built objects, compiled 14, 1 min 18 s
- Remote build agents (Linux, macOS): build → test (web memory, Safari WebKit) → release, no SSH
- All numbers and conditions: [BENCHMARKS.md](BENCHMARKS.md)

- Measured: Windows, headless Chrome, debug = release
- Reference: official Godot empty GDScript web = 55.4 MB WASM heap
- Version `<godot>-<enhanced>` → `4.7.2-0.3.0`, source [`ENHANCED_VERSION`](ENHANCED_VERSION)
- Engine build name: `enhanced-0.3.0`

**Keywords:**
- Godot 4 C# web export, Godot 4.7 C# HTML5, "C# projects cannot be exported to the web" fix
- Godot .NET 11 web, Godot C# WebAssembly, Mono WASM, Godot mono HTML5
- Unity to Godot C# migration, Unity alternative web export
- Godot memory optimization, Godot performance optimization, Godot web game too big
- Godot web export memory, WASM heap out of memory, GDScript parser memory leak
- Godot SQLite web, GDExtension web export, GDExtension without dlink, SharedArrayBuffer COOP COEP
- Godot web export threads crash fix, Godot web threads dlink startup error
- "Cannot set properties of undefined (setting 'sig')", "function import requires a callable" Godot
- Godot Emscripten 7, Godot Emscripten 7.0.0 web template, GDExtension rebuild Emscripten 7
- GDScript prebuild, GDScript precompile export, Godot compiled GDScript bytecode, script_export_mode
- Godot C# web Emscripten 7, "undefined symbol: _Unwind_CallPersonality", __gxx_wasm_personality_v0
- Godot web game itch.io Poki CrazyGames, Godot AdSense web, Godot Safari iOS web
- Godot ARM64 Windows Linux, Apple Silicon Godot
- Godot web export size, Godot web build too large, Godot HTML5 gzip brotli compression, itch.io Godot loading slow
- Godot Korean IME, Godot 한글 입력 버그, Godot Hangul input, CJK input, LineEdit / TextEdit caret
- Godot GDExtension web size, Godot side.wasm too big, Godot dlink web export slow loading
- Godot C# iOS export failed to load hostfxr, Godot .NET 11 iOS, Godot C# iOS simulator
- Godot C# iOS app size, Godot NativeAOT iOS binary too big, Godot mono iOS export size
- Godot C# Android APK size, Godot C# Android trimming, Godot mono Android too big, Godot .NET mobile export size
- Godot 일본어 입력, Godot 일본어 IME 리눅스, Godot Japanese input not working
- Godot Japanese IME Linux, Godot Mozc fcitx5 ibus, Godot Wayland text-input-v3 IME
- Godot 日本語入力, Godot 日本語入力 できない, Godot IME 変換 できない, Godot Linux Mozc fcitx5, Godot Wayland 日本語, Godot LineEdit 日本語

| Patch | Platform | Fixes |
|---|---|---|
| [Linux Japanese input check](patches/linux-ime-japanese.md) | Linux X11 + Wayland | Mozc via fcitx5 verified, automated tests |
| Web pre-compression | Web | Big `.pck` / `.wasm` downloads, no server gzip |
| [Windows IME queued key](patches/windows-ime-queued-key.md) | Windows editor + game | Korean (Hangul) typing loses caret advance after a syllable is committed |
| [GDScript parser release](patches/gdscript-parser-release.md) | All, aimed at Web / WASM | Syntax trees of mutually dependent scripts stay alive after compile → high peak memory at boot |
| [C# (.NET) web export](patches/dotnet-web-export.md) | Web + C# editor | Export C# projects to the web (Mono on WebAssembly). Experimental. Taken from upstream PR #106125 and ComplexRobot's rebase |

## Branches

- `main` (default): latest supported Godot version (now `4.7.2-stable`, `ed1daf0bf`) + patches. One commit per patch.
- Version branches (e.g. `4.7`) are cut from `main` only when an older version still needs fixes.
- Upstream Godot: add `https://github.com/godotengine/godot.git` as a remote.
- Upstream tags kept (`4.7.2-stable`, …).

## Use

Build this branch:

```sh
git clone --branch main --depth 1 https://github.com/joygram/godot-enhanced.git
cd godot-enhanced
# Windows editor (MSVC)
python -m SCons platform=windows target=editor arch=x86_64
# Web export template (Emscripten)
scons platform=web target=template_release
```

Or apply the patches to your own Godot 4.7.2 tree:

```sh
git apply patches/godot-4.7.2-windows-ime-queued-key.patch
git apply patches/godot-4.7.2-gdscript-parser-release.patch
git apply patches/godot-4.7.2-dotnet-web-export.patch
```

Apply all three (as above), or only the ones you need — each patch also applies on its own and in any order (checked with `git apply` on `4.7.2-stable`).

## Prebuilt Web export template

- GitHub Actions ([enhanced_web_template.yml](.github/workflows/enhanced_web_template.yml)) builds the Web template from this branch and publishes it on [Releases](https://github.com/joygram/godot-enhanced/releases).
- Assets: 4 zips, threads / nothreads × static / dlink (`godot.web.template_release.wasm32[.nothreads][.dlink].zip`)
- dlink = GDExtension support; threads = server must send COOP / COEP
- Use: Web export preset → Custom Template → Release → the zip.
- Emscripten 7.0.0 (`misc/scripts/emscripten-version`), GDScript and C# alike.
- With dlink, your GDExtension web builds must use the same version.
- These are the GDScript templates. C# web projects need the separate `.mono` templates below.
- GDExtension without dlink: build the template with `static_gdextensions=<name>` (list: [misc/static_gdextensions.json](misc/static_gdextensions.json)).

## C# (.NET) web export

- Targets **.NET 11** (`net11.0`); game projects must use the same framework as the templates. .NET 9 support ended on 2026-11-10.
- Needs the C# editor and `.mono` web templates built from this branch with `module_mono_enabled=yes`. How: [patches/dotnet-web-export.md](patches/dotnet-web-export.md).
- Releases: workflow `enhanced_dotnet_release.yml` publishes them to [Releases](https://github.com/joygram/godot-enhanced/releases) once it has run successfully. Not published yet.
- GDExtension: only statically linked (`static_gdextensions=<name>`), dlink is not possible.
- Threads follow the export preset's Thread Support. Threaded template: host with COOP / COEP headers.
- Not only C++: the patch also changes C#, MSBuild and SCons files. The build needs the .NET 11 SDK and the `wasm-tools` workload, and ships `GodotSharp` assemblies and NuGet packages next to the editor.

## Keeping up with upstream

```sh
git remote add upstream https://github.com/godotengine/godot.git
git fetch upstream --tags
git checkout -b <new-version>-enhanced <new-version>-stable
git cherry-pick 4.7.2-stable..origin/main
```

## Status

- Not an official Godot build. Not submitted upstream yet.
- Tested only on Godot 4.7.2. Other versions: unverified.
- License: MIT, same as Godot. See [LICENSE.txt](LICENSE.txt).
- Original Godot readme: [upstream README](https://github.com/godotengine/godot/blob/4.7.2-stable/README.md).

## Credits

- C# web export: Raul Santos ([godotengine/godot#106125](https://github.com/godotengine/godot/pull/106125)), ComplexRobot ([godot](https://github.com/ComplexRobot/godot), [godot-dotnet-web-export](https://github.com/ComplexRobot/godot-dotnet-web-export)), Dom Finn.
- Godot Engine contributors, MIT license.

---

## 한국어 안내

Godot 4.7.2 공식 소스에 패치를 더한 빌드입니다. 업스트림 커밋 이력은 그대로 유지합니다.

### 🔧 0.3.1 — 수정: 웹 GDScript 사전 빌드 시작 오류 (64비트에서 만든 바이트코드를 wasm32 가 읽음)

| 웹 사전 빌드 (`script_export_mode=3`) | 0.3.0 | **0.3.1** |
|---|---|---|
| 시작 | 오류로 멈춤 | **✔** |

- 오류: `Index p_op = 156 is out of bounds (Variant::OP_MAX = 25)`, `RuntimeError: operation does not support unaligned accesses`
- 원인: `OPCODE_OPERATOR` 캐시 칸 = 포인터 크기 (64비트 편집기 2칸, wasm32 1칸) → 명령 길이 어긋남
- 수정: 캐시 칸 전 플랫폼 2칸 고정 (`GDScriptFunction::OPERATOR_CACHE_SLOTS`), 사전 빌드 포맷 2 (옛 사전 빌드는 토큰으로 대체)

### 🚀 0.3.0 — GDScript 사전 빌드 전 릴리스 탑재, 웹 전부 Emscripten 7.0.0 (C# 포함)

| 0.3.0 릴리스 | 내용 | 상태 |
|---|---|---|
| `editor-4.7.2-0.3.0` | 편집기 6종 + export_templates.tpz | ✔ 러너 5종 검증 |
| `web-template-4.7.2-0.3.0` | 스레드·스레드 없음 × 정적·dlink | ✔ Emscripten 7.0.0 |
| `dotnet-web-4.7.2-0.3.0` | C# 키트 Linux·macOS·Windows | ✔ Emscripten 7.0.0 |

**GDScript 사전 빌드 전 릴리스 탑재** (`script_export_mode=3`)
- 같은 릴리스 편집기·템플릿 → 사전 빌드 바이트코드 적용, 파싱·분석·컴파일 생략
- 템플릿 폴더 `4.7.2.stable.enhanced-0.3.0` 으로 편집기·템플릿 짝 고정

**C# 웹 Emscripten 7.0.0**

| C# 웹 템플릿 링크 | 6.0.2 고정 | **0.3.0 (7.0.0)** |
|---|---|---|
| release·debug × 스레드·스레드 없음 | 구 툴체인 필요 | **✔ 4종 모두 링크** |

- 오류: `undefined symbol: _Unwind_CallPersonality` (`libmono-wasm-eh-wasm.a`)
- 원인: .NET 11 런타임 팩 = Emscripten 6 컴파일, LLVM 23 이 이름을 `__gxx_wasm_personality_v0` 로 바꿈
- 수정: 옛 이름 → 새 함수로 넘김 ([gd_mono_wasm_unwind.cpp](modules/mono/mono_gd/gd_mono_wasm_unwind.cpp))

**정리**
- 결함 릴리스 폐기: `web-template-4.7.2-0.1.9`, `0.2.0` (멀티스레드 + dlink 시작 오류)

### 🔧 0.2.1 — 수정: Emscripten 7.0.0(최신) 지원, 웹 멀티스레드 + GDExtension 다시 동작

- 새 기능 아님: 공식 Godot 도 웹 멀티스레드 + GDExtension 지원
- 최신 Emscripten 7.0.0 지원, 웹 멀티스레드 포함
- 해소: 0.2.0 멀티스레드 + dlink 템플릿 시작 오류

| 웹 템플릿 | 0.2.0 (Emscripten 6.0.2) | **0.2.1 (7.0.0)** |
|---|---|---|
| 멀티스레드 + dlink (GDExtension) | ✘ 시작 즉시 오류 | **✔ 부팅** |
| 실제 게임 (SQLite GDExtension, 멀티스레드) | ✘ 49% 멈춤 | **✔ 10초 부팅, 오류 0** |

- 웹 템플릿 Emscripten 6.0.2 → **7.0.0**, 버전은 `misc/scripts/emscripten-version`
- 오류: `setting 'sig'`, GL `LinkError`
- 원인: 6.0.2 가 GL 별칭을 인스턴스 전에 wasm export 로 묶음
- GDExtension 웹 빌드: 7.0.0 으로 재빌드 필요 (6.0.2 모듈 → `resolved is not a function`)
- 서버: 멀티스레드 = COOP·COEP 헤더 필요 (SharedArrayBuffer)

### ⚡ 0.2.0 — GDScript 사전 빌드, 내보내기 템플릿을 릴리스에 고정

**GDScript 사전 빌드** (`script_export_mode=3`)
- 내보낼 때 컴파일된 클래스·바이트코드 저장, 실행 시 파싱·분석·컴파일 건너뜀
- 버전 불일치·미지원 내용 → 바이너리 토큰(모드 2)으로 대체
- 넘을 기준선 (스크립트 400개, 모드 2): 분석 142 ms, 컴파일 40 ms, 파싱 23 ms
- 검사: 에이전트 검사 `gdscript-prebuild` — 기능 스크립트를 모드 2·3 으로 실행해 출력 비교
- 설계: [patches/gdscript-prebuild.md](patches/gdscript-prebuild.md)

**내보내기 템플릿 고정**
- 템플릿 폴더: `4.7.2.stable` → **`4.7.2.stable.enhanced-0.2.0`**
- 편집기는 자기 릴리스 템플릿으로만 내보냄; 공식 Godot·다른 릴리스 템플릿 안 씀
- 적용: 내보내기 템플릿 찾기, 템플릿 관리자, C# 내보내기
- 설치: 릴리스 템플릿 → `export_templates/4.7.2.stable.enhanced-<버전>/`

### ✂️ 0.1.9 — C# iOS: GodotSharp 트리밍 동작, 바이너리 −63% (선택)

| `ios-arm64` NativeAOT, 표본 C# 프로젝트 | 기본 | **`GodotTrimGodotSharp=true`** |
|---|---|---|
| `Game.dylib` | 18.6 MB | **6.8 MB (−63%)** |
| 시뮬레이터 앱 (Debug) | 139.9 MB | **111.6 MB** |
| 시뮬레이터 실행 | ✔ `trim ok 3` | ✔ `trim ok 3` |

- 0.1.7 트리밍 빌드는 실행 시 실패: `instance_create(): native_name == StringName()`
- 원인: Godot 가 리플렉션으로 읽는 `NativeName` 을 NativeAOT 가 지움
- 수정: 보존 목록 [`GodotSharp.TrimRoots.xml`](modules/mono/editor/Godot.NET.Sdk/Godot.NET.Sdk/Sdk/GodotSharp.TrimRoots.xml), 그 필드만 남김
- 켜기: `.csproj` 에 `<GodotTrimGodotSharp>true</GodotTrimGodotSharp>`
- 선택 옵션: 표본 프로젝트 하나로만 검증

### 🍎 0.1.8 — C# iOS 다시 동작 (.NET 11), 시뮬레이터 실행 검증

| iOS 시뮬레이터 (iOS 27.2), 표본 C# 프로젝트 | 전 | **0.1.8** |
|---|---|---|
| 내보내기 | "project assembly not found" | **정상** |
| 앱 시작 | `.NET: Failed to load hostfxr` | **C# `_Ready` 실행, `[Export]` 배열 정상** |

- 원인: .NET 11 NativeAOT 가 `libGame.dylib` 로 만듦, Godot 는 `Game.dylib` 를 찾음
- 수정: 내보내기 플러그인이 publish 뒤 `lib` 접두 제거·install name 맞춤
- 검사: [`ios-sim-csharp.sh`](misc/scripts/agent_tests/ios-sim-csharp.sh) — 내보내기 → `xcodebuild` → `simctl` 실행 → 로그 `trim ok 3`
- 미검증: 실기기

### 🧩 0.1.6 — GDExtension 웹 빌드도 미리 압축 (side module −76%)

| dlink 웹 내보내기 (`extensions_support`) | 전 | **0.1.6** | |
|---|---|---|---|
| `.side.wasm` (엔진 side module) | 42.8 MB | **10.1 MB** | **−76%** |
| `.wasm` (main module) | 1.3 MB | **0.5 MB** | **−58%** |

- `.side.wasm` 을 Godot 프리로더가 받음 → gzip 해제·진행률 반영
- Emscripten 에 blob URL 로 넘김, 서버 설정 불필요
- 검증: headless Chrome, 정적·dlink 내보내기 모두 오류 0, 힙 38.4 MB
- 검사: [`web-memory.sh`](misc/scripts/agent_tests/web-memory.sh), dlink 템플릿 있으면 두 변형 모두

### 📱 0.1.5 — C# Android: 관리 코드 −83%, 기본 트리밍

| `android-arm64` publish (표본 C# 프로젝트) | 전 | **0.1.5** | |
|---|---|---|---|
| 관리 `.dll` 합계 | 29.8 MB | **5.0 MB** | **−83%** |
| `GodotSharp.dll` | 5.9 MB | **2.8 MB** | **−52%** |
| publish 폴더 (네이티브 런타임 포함) | 100.1 MB | **74.9 MB** | **−25%** |

- 웹·Android `PublishTrimmed` 기본 켬, 게임 어셈블리는 통째 유지
- 규칙 한 곳 `Sdk.targets`, 두 플랫폼 공용. iOS 그대로 (NativeAOT)
- 끄기: `<PublishTrimmed>false</PublishTrimmed>`, 더 남기기: `TrimmerRootAssembly`
- 실측: Linux 에이전트, .NET 11, 검사 [`dotnet-trim.sh`](misc/scripts/agent_tests/dotnet-trim.sh), 2026-11-17
- 미검증: Android 기기 실행

### 🇯🇵 0.1.4 — Linux 일본어 입력(Mozc) 검증, 자동 검사

| 세션 | 전환 | 결과 |
|---|---|---|
| X11 + fcitx5 | 트레이 / `fcitx5-remote` | `にほんご` ✔ |
| X11 + fcitx5 | `Ctrl+Space` | `にほんご` ✔ |
| Wayland (sway) + fcitx5 | 트레이 / `fcitx5-remote` | `にほんご` ✔, 조합 중 글자 표시 |
| Wayland (sway) + fcitx5 | `Ctrl+Space` | `にほんご` ✔, 조합 중 글자 표시 |

- 엔진 수정 없음: X11(XIM)·Wayland(`text-input-v3`) 정상
- `Ctrl+Space` 가로채기 없음 → fcitx5 로 전달
- Mozc 첫 사용 직후 첫 키 라틴 샘 → Mozc 기동 지연, Xlib 단독 앱도 같음
- 미검증: KDE KWin (headless KWin 키 주입 불가)
- 설정 팁·방법·원 결과: [patches/linux-ime-japanese.md](patches/linux-ime-japanese.md)

### 🗜️ 0.1.3 — 웹 다운로드 최대 −75%, 서버 설정 없음

| 웹 다운로드 | 전 | **미리 압축** | |
|---|---|---|---|
| 엔진 `.wasm`, GDScript 템플릿 | 36.4 MB | **9.3 MB** | **−75%** |
| 엔진 `.wasm`, C# 템플릿 | 39.3 MB | **10.4 MB** | **−73%** |
| 게임 `.pck` (rpg2d) | 36.5 MB | **22.9 MB** | **−38%** |
| **rpg2d 합계** (wasm + pck) | 72.9 MB | **32.2 MB** | **−56%** |

- 웹 프리셋 옵션 **`compression/precompress`** (기본 꺼짐) → `.pck`·`.wasm` gzip 압축
- 로더가 gzip 서명 보고 브라우저 `DecompressionStream` 으로 풂. itch.io 등 서버 설정 불필요
- 파일명 유지 → 호스트가 또 gzip 해도 이중 해제 없음
- 실측: 기존 내보내기에 gzip -6, 2026-11-17
- 검증: 미리 압축한 내보내기(디스크 wasm 9.7 MB) headless Chrome 부팅, 오류 0, 힙 변화 없음(38.4 MB)
- dlink `.side.wasm`: 0.1.6 부터 포함. 아직 안 됨: C# 런타임 파일

### 🚀 0.1.1 — C#이 웹에서 돌아가고, 가볍다

> 공식 Godot 4는 C#을 웹으로 **못 내보냅니다.** godot-enhanced는 내보내고, 확 줄였습니다.

| C# 웹 빌드 (실제 게임, .NET 11) | 이전 | **0.1.1** | |
|---|---|---|---|
| 다운로드 (`.pck`) | 64.0 MB | **10.7 MB** | **−83%** |
| 부팅 후 WASM 힙 | 160.1 MB | **95.8 MB** | **−40%** |
| 빈 C# 프로젝트 WASM 힙 | 154.1 MB | **79.8 MB** | **−48%** |
| 부하 중 .NET 관리 힙 | 4.3 MB | **1.3 MB** | **−70%** |
| 브라우저 오류 | 0 | **0** | 저장·불러오기 확인 |

- **pck 다이어트**: 런타임에 안 쓰는 `.a`·ICU 데이터·빌드 메타데이터 제외 → 64 → 30 MB
- **어셈블리 무복사 로드**: `need_copy=false`. 줄지 않는 WASM 힙에 남던 복사 최고치 제거 → 160 → 115 MB
- **IL 트리밍**: 안 쓰는 프레임워크 코드 제거, 게임·`GodotSharp`는 보존 → 30 → 10.7 MB
- **웹용 GC**: SGen nursery 1 MB → 작은 GC가 짧아져 프레임 끊김 감소. `MONO_GC_PARAMS`로 변경 가능
- **.NET 11** 런타임 팩, Emscripten 6.0.2

0.1.1에 함께: Windows 한글 IME 수정.

### 🔍 GDScript 웹: Godot 컴파일러의 메모리 누수를 찾아 막음

- 추적: rpg2d 웹 부팅 → WASM 힙이 계속 커지고 내려오지 않음
- 발견: 서로 참조하는 스크립트의 파서가 서로를 붙잡음 → 구문 트리가 해제되지 않음
- 발견: 스크립트 하나 컴파일 = 의존 사슬 전체 컴파일 → 구문 트리가 한꺼번에 메모리에 올라감
- 해결: 의존 스크립트 컴파일 전에 자기 파서 해제, 가장 바깥 reload 끝나면 파서 캐시 정리
- 결과: 컴파일 직후 구문 트리 해제, 부팅 최고치 감소. 스크립트 동작은 그대로
- C#만이 아니라 모든 GDScript 프로젝트에 적용. 힙이 줄지 않는 웹에서 효과 최대

| rpg2d 부팅 정적 메모리 (`autoload_first`) | 이전 | **이후** | |
|---|---|---|---|
| 데스크톱 실행 로그, 2026-11-13 | 145.8 – 165.5 MB (16회) | **67.4 – 68.0 MB** (13회) | **약 −56%** |

- 패치 에디터(릴리스 `88690556f4`) 첫 실행(10:07)부터 하락

### 🧩 0.1.2 — C# 웹에서 GDExtension, C# 웹 크래시 3종 수정

> 이제 C# 웹 게임도 GDExtension(예: SQLite)을 쓸 수 있습니다. .NET 런타임이 PIC가 아니라 dlink로는 불가능했습니다.

| C# 웹 크래시 (모든 C# 웹 게임) | 수정 |
|---|---|
| `Variant.As*()`, `Call()` → `aot-runtime-wasm.c:188` | 엔진 호출 서명 전부를 인터프리터 표에 |
| `await ToSignal` → `function signature mismatch` | `Error` 반환을 C#과 같은 64비트로 |
| 단일 스레드 내보내기가 멀티스레드 런타임 선택 | 스레드 선택을 앞 단계(`Browser.props`)에서 |

| 웹 SQLite (rpg2d DB, 8만 행, Chrome) | 처리 후 힙 | DB 읽기 | 다운로드 |
|---|---|---|---|
| GDScript + GDExtension (dlink) | 198.8 MB | 386 ms | 77.7 MB |
| **GDScript + 정적 링크** | 198.8 MB | **292 ms (−24%)** | **67.8 MB (−9.8)** |
| **C# + 정적 링크** (신규) | 238.5 MB | **290 ms** | 77.8 MB |
| C# + `Microsoft.Data.Sqlite` | 194.3 MB | 2,228 ms | 77.7 MB |

| 클래스 200개, 같은 테스트 (Chrome) | GDScript | C# |
|---|---|---|
| WASM 힙 | 38.4 MB | 55.4 MB (+17, .NET 런타임) |
| 정수 연산 | 69.6 ms | **23.2 ms (3배)** |
| 객체 / 컬렉션 | 109.3 / 57.3 ms | 90.6 / 45.6 ms |

- `static_gdextensions=sqlite`: GDExtension 소스 수정 없이 웹 템플릿에 정적 링크
- 미리 빌드한 `.a`(release/debug × threads/nothreads)는 릴리스 `static-gdext-emsdk6.0.2`, 이름만으로 받음
- `mono_wasm_native_packages=Id/Version`: NuGet 네이티브 라이브러리(예: `e_sqlite3`)를 C# 템플릿에
- C# 웹 템플릿: threads·**nothreads** 둘 다 (nothreads는 COOP / COEP 불필요)
- 빌드 캐시 공유: Mac이 Linux 빌드 결과 1,932개 재사용, 14개만 컴파일, 1분 18초
- 원격 빌드 에이전트(Linux, macOS): 빌드 → 검사(웹 메모리, Safari WebKit) → 릴리스, SSH 없음
- 전체 수치·조건: [BENCHMARKS.md](BENCHMARKS.md)

- 측정: Windows, headless Chrome, debug·release 템플릿 동일 결과. 참고값: 공식 Godot 빈 GDScript 웹 = WASM 힙 55.4 MB
- 버전: `<Godot>-<enhanced>` → `4.7.2-0.2.0`. 기준 파일 [`ENHANCED_VERSION`](ENHANCED_VERSION). 엔진 빌드 이름 `enhanced-0.2.0`

| 패치 | 플랫폼 | 해결하는 문제 |
|---|---|---|
| [Windows 한글 IME 패치](patches/windows-ime-queued-key.md) | Windows 편집기·게임 | 한글 음절을 확정한 뒤 다음 글자를 입력하면 커서가 앞으로 가지 않는 문제 |
| [GDScript 파서 해제 패치](patches/gdscript-parser-release.md) | 전체 (웹/WASM에서 효과 큼) | 서로 참조하는 스크립트의 구문 트리가 컴파일 뒤에도 남아 부팅 때 메모리 최고치가 높아지는 문제 |
| [C#(.NET) 웹 내보내기 패치](patches/dotnet-web-export.md) | 웹 + C# 편집기 | C# 프로젝트를 웹으로 내보냅니다(WebAssembly 위의 Mono). 실험적 기능이며 업스트림 PR #106125와 ComplexRobot의 재적용본을 가져왔습니다 |

### 브랜치

- `main` (기본 브랜치): 지원하는 최신 Godot 버전(현재 `4.7.2-stable`, `ed1daf0bf`) 위에 패치를 하나씩 커밋으로 올렸습니다.
- 버전 브랜치(예: `4.7`)는 이전 버전을 계속 고쳐야 할 때만 `main`에서 따로 만듭니다.
- 업스트림 Godot은 `https://github.com/godotengine/godot.git`을 원격으로 추가해서 받습니다.
- 업스트림 태그(`4.7.2-stable` 등)도 그대로 있습니다.

### 사용법

이 브랜치를 바로 빌드하면 됩니다.

```sh
git clone --branch main --depth 1 https://github.com/joygram/godot-enhanced.git
cd godot-enhanced
# Windows 편집기 (MSVC)
python -m SCons platform=windows target=editor arch=x86_64
# 웹 내보내기 템플릿 (Emscripten)
scons platform=web target=template_release
```

가지고 있는 Godot 4.7.2 소스에 패치만 적용해도 됩니다. 세 패치를 모두 적용해도 되고, 필요한 것만 골라 적용해도 됩니다. 적용 순서는 상관없습니다(`4.7.2-stable`에서 `git apply`로 모든 조합을 확인했습니다).

```sh
# 모두
git apply patches/godot-4.7.2-windows-ime-queued-key.patch patches/godot-4.7.2-gdscript-parser-release.patch patches/godot-4.7.2-dotnet-web-export.patch
# 하나만
git apply patches/godot-4.7.2-windows-ime-queued-key.patch
```

### 미리 빌드된 웹 템플릿

- GitHub Actions가 이 브랜치로 웹 내보내기 템플릿을 빌드해 [Releases](https://github.com/joygram/godot-enhanced/releases)에 올립니다.
- zip 4종: 스레드·스레드 없음 × 정적·dlink (`godot.web.template_release.wasm32[.nothreads][.dlink].zip`)
- dlink = GDExtension 사용, 스레드 = 서버 COOP·COEP 헤더 필요
- 웹 내보내기 프리셋의 Custom Template → Release에 zip 파일을 지정하면 됩니다.
- Emscripten 7.0.0 (`misc/scripts/emscripten-version`), GDScript·C# 공통. dlink 면 GDExtension 웹 빌드도 같은 버전
- 위 템플릿은 GDScript용입니다. C# 웹 프로젝트는 아래의 별도 `.mono` 템플릿이 필요합니다.
- dlink 없이 GDExtension: 템플릿을 `static_gdextensions=<이름>`으로 빌드 (목록: [misc/static_gdextensions.json](misc/static_gdextensions.json))

### C#(.NET) 웹 내보내기

- **.NET 11**(`net11.0`) 대상입니다. 게임 프로젝트도 템플릿과 같은 버전이어야 합니다. .NET 9는 2026-11-10에 지원이 끝났습니다.
- `module_mono_enabled=yes`로 이 브랜치에서 빌드한 C# 편집기와 `.mono` 웹 템플릿이 필요합니다. 방법은 [patches/dotnet-web-export.md](patches/dotnet-web-export.md)에 있습니다.
- 결과물은 `enhanced_dotnet_release.yml` 워크플로가 성공하면 [Releases](https://github.com/joygram/godot-enhanced/releases)에 올라옵니다. 아직 올라와 있지 않습니다.
- GDExtension은 정적 링크(`static_gdextensions=<이름>`)로만 쓸 수 있습니다. dlink는 불가능합니다.
- 스레드는 내보내기 프리셋의 Thread Support를 따릅니다. 스레드 템플릿은 호스팅에 COOP / COEP 헤더가 필요합니다.
- C++만 바뀌는 것이 아닙니다. C#, MSBuild, SCons 파일도 바뀌어서 빌드에 .NET 11 SDK와 `wasm-tools` 워크로드가 필요하고, 편집기와 함께 `GodotSharp` 어셈블리·NuGet 패키지가 배포됩니다.

### 새 Godot 버전으로 옮기기

```sh
git remote add upstream https://github.com/godotengine/godot.git
git fetch upstream --tags
git checkout -b <새 버전>-enhanced <새 버전>-stable
git cherry-pick 4.7.2-stable..origin/main
```

### 상태

- 공식 Godot 빌드가 아니며, 아직 업스트림에 제출하지 않았습니다.
- Godot 4.7.2에서만 확인했습니다. 다른 버전에서는 검증하지 않았습니다.
- 라이선스는 Godot과 같은 MIT입니다.
- C# 웹 내보내기 출처: Raul Santos([godotengine/godot#106125](https://github.com/godotengine/godot/pull/106125)), ComplexRobot, Dom Finn.

**검색어:**
- 고도 C# 웹 내보내기, 고도 4 C# 웹 빌드 안됨, 고도 엔진 C# HTML5, Godot .NET 웹 빌드
- 유니티에서 고도로 이전, 유니티 대안 웹게임
- 고도 메모리 최적화, 고도 성능 최적화, 고도 메모리 성능 최적화
- 고도 웹 빌드 메모리, Godot WASM 메모리 부족, 고도 웹게임 용량 줄이기
- 고도 SQLite 웹, GDExtension 웹 빌드, 고도 웹게임 광고 애드센스, 고도 사파리 아이폰 웹
- 고도 웹 멀티스레드 오류 해결, 고도 웹 시작 오류, 고도 웹 스레드 dlink 오류
- 고도 Emscripten 7, 고도 Emscripten 7.0.0 웹 템플릿, GDExtension Emscripten 7 재빌드
- 고도 GDScript 사전 빌드, 고도 스크립트 미리 컴파일, GDScript 바이트코드 내보내기
- 고도 C# 웹 Emscripten 7, 고도 C# 웹 링크 오류 _Unwind_CallPersonality
- 고도 ARM64, 애플 실리콘 고도
- 고도 엔진 한글 입력, Godot 한글 IME, 한글 입력 시 커서 안 움직임, 한글 씹힘, LineEdit·TextEdit 한글

---

> 본 작업은 AI와 함께함 · This work was made with AI assistance.
