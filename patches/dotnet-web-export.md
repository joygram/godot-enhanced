# C# (.NET) web export patch (Mono on WebAssembly)

- Patch: [godot-4.7.2-dotnet-web-export.patch](godot-4.7.2-dotnet-web-export.patch)
- Files: `modules/mono/**` (runtime start, SDK, export plugin, runtime pack), `platform/web/**` (build flags, JS post step, export plugin)
- Size: 18 files, +686 / −36
- Status: experimental. Applies cleanly to `4.7.2-stable` alone and together with the other two patches, in any order (checked with `git apply`). Full build and runtime check in this repository: see "Status" below.

## What it does

- Godot's official .NET editor refuses to export C# projects to the web. This patch lets it.
- The web platform starts the Mono runtime (`mono_wasm_load_runtime`) instead of `hostfxr`.
- `Godot.NET.Sdk` gets `Browser.props` / `Browser.targets`; `GetRuntimePack` fetches the browser runtime pack.
- The web export plugin accepts `.mono` templates and the C# export plugin adds the web build steps.
- A build step erases the generated `DOTNET.setup();` call so the page starts correctly.
- Optional: `scons platform=web module_mono_enabled=yes mono_wasm_aot_dir=<wasm/for-publish>` links a game's AOT-compiled assemblies into the template (the template then only fits that build).

## Not only C++

The patch is mixed, so building it needs more than SCons:

| Kind | Files | Role |
|---|---|---|
| C++ | 2 (`gd_mono.cpp`, `platform/web/export/export_plugin.cpp`) | Start Mono on web, web export plugin |
| C# | 3 (`ExportPlugin.cs`, `ManagedCallbacks.cs`, `GetRuntimePack/Program.cs`) | Editor export steps, runtime pack download, managed callbacks |
| MSBuild | 8 (`.csproj`, `.props`, `.targets`) | `Godot.NET.Sdk` Browser settings, runtime pack project |
| Python / SCons | 5 (`mono_configure.py`, `config.py`, `SCsub`, `detect.py`, `emscripten_helpers.py`) | Build options, mono support on web, JS post step |

- Besides the engine binary the build produces managed output: the `GodotSharp` assemblies and NuGet packages. They must be built after the C# glue is generated and shipped with the editor.
- Build tools needed: SCons, Emscripten 6.0.2 (web), .NET 11 SDK and the `wasm-tools` workload.
- Applying only this patch to a stock tree is not enough for users: they also need the matching NuGet packages (built from the patched SDK files) and `.mono` web templates.

## .NET version: 11

Changed in this repository: the source patch targeted .NET 9; here it targets **.NET 11** (`net11.0`).

- .NET 9 reached end of support on 2026-11-10, the day .NET 11 shipped.
- The framework is set in one place, `modules/mono/runtime/GetRuntimePack/GetRuntimePack.csproj`; `mono_configure.py` reads it from there. `GetRuntimePack/global.json` pins the .NET 11 SDK.
- Memory: from .NET 10 on, the Mono GC on WebAssembly allocates each 16 KB heap block with its own `posix_memalign` (.NET 9 grouped 32 blocks). With Emscripten's default allocator this can double the heap's footprint in linear memory ([dotnet/runtime#136152](https://github.com/dotnet/runtime/issues/136152), open). The web templates here link `-sMALLOC=mimalloc`; whether that avoids the overhead is not measured yet.
- CoreCLR on WebAssembly is opt-in in .NET 11; this patch uses Mono, the default browser runtime in .NET 11.

## Sources

The code is not original to this repository. It is taken, unchanged in logic, on top of `4.7.2-stable`:

- Upstream pull request [godotengine/godot#106125](https://github.com/godotengine/godot/pull/106125) "[.NET] Add web export support" by Raul Santos (still open upstream).
- [ComplexRobot/godot](https://github.com/ComplexRobot/godot), branch `dotnet/mono-static-linking` at `d1cc834954`: rebase onto Godot 4.7, fixes, and the `DOTNET.setup();` erase step. Includes two pull requests by Dom Finn: optional AOT linking and Mono debug level 0 in release templates.
- Build recipe and install steps follow [ComplexRobot/godot-dotnet-web-export](https://github.com/ComplexRobot/godot-dotnet-web-export), which also ships ready-made Windows / macOS (Apple Silicon) editors.

Our own addition: it is kept as one patch file so it can be applied alone or with the IME and GDScript patches.

## Requirements (game project)

- `.csproj`: `<TargetFramework>net11.0</TargetFramework>`. It must be the framework the web templates were built for; a template only runs games built for its own .NET version.
- .NET 11 SDK with the `wasm-tools` workload.
- A `Program.cs` with at least one top-level statement in the project root; `{}` is enough.
- Web templates `web_release.zip` / `web_debug.zip` in `export_templates/<version>.stable.mono`.
- The NuGet packages built with the editor (`GodotSharp` etc.) in a local NuGet source.
- You may need this in the `.csproj`:

```xml
<ItemGroup>
  <TrimmerRootAssembly Include="System.Private.CoreLib" />
  <TrimmerRootAssembly Include="System.Runtime" />
</ItemGroup>
```

## Limits

- Experimental. Web builds lack some features:
  - No GDExtension (the .NET runtime is built without position-independent code). `godot-sqlite` and similar addons do not work in C# web builds.
  - Globalization is always in invariant mode; some BCL APIs (for example crypto) do not work.
- This is a **threaded** web template (`WasmEnableThreads=true`). It is not the `nothreads` template used by the GDScript web export in this repository. Hosting must serve it cross-origin isolated (COOP / COEP headers) so `SharedArrayBuffer` works (itch.io: enable "SharedArrayBuffer support").
- Only Godot 4.7.2.

## Build

Editor with C# (Windows shown; macOS: `platform=macos`; Linux: `platform=linuxbsd`):

```sh
scons platform=windows target=editor module_mono_enabled=yes
bin/godot.windows.editor.x86_64.mono.exe --headless --generate-mono-glue modules/mono/glue
python modules/mono/build_scripts/build_assemblies.py --godot-output-dir=./bin --push-nupkgs-local ./bin/nuget
```

Web templates (Linux, Emscripten, .NET SDK with the `wasm-tools` workload):

```sh
scons platform=web target=template_release module_mono_enabled=yes
scons platform=web target=template_debug module_mono_enabled=yes
```

- Output: `bin/godot.web.template_release.wasm32.mono.zip` and `...template_debug...mono.zip`. Rename to `web_release.zip` / `web_debug.zip`.
- Use Emscripten 6.0.2, the version the .NET 11 Mono runtime pack is built with (`dotnet/runtime` `release/11.0`). The source project used 6.0.5 with .NET 9 and noted that 6.0.6 / 6.0.7 with full LTO ran out of memory on the standard runner.

## Status

- Patch application: checked.
- Build and an actual C# web export from this branch: not yet verified here. Release assets will be listed on [Releases](https://github.com/joygram/godot-ime/releases) after the workflow `ime_dotnet_release.yml` has run successfully.

## 한국어

### 하는 일

- 공식 Godot .NET 편집기는 C# 프로젝트를 웹으로 내보내지 못합니다. 이 패치가 그것을 가능하게 합니다.
- 웹 플랫폼이 `hostfxr` 대신 Mono 런타임(`mono_wasm_load_runtime`)을 시작합니다.
- `Godot.NET.Sdk`에 `Browser.props` / `Browser.targets`가 추가되고, `GetRuntimePack`이 브라우저용 런타임 팩을 받아 옵니다.
- 웹 내보내기 플러그인이 `.mono` 템플릿을 인식하고, C# 내보내기 플러그인에 웹 빌드 단계가 추가됩니다.
- 빌드 중 생성된 JS에서 `DOTNET.setup();` 호출을 지워 페이지가 올바르게 시작되게 합니다.
- 선택 사항: `mono_wasm_aot_dir=<wasm/for-publish>` 옵션으로 게임의 AOT 컴파일 어셈블리를 템플릿에 링크할 수 있습니다(그 빌드 전용 템플릿이 됩니다).

### C++만이 아닙니다

이 패치는 여러 종류가 섞여 있어서, 빌드에 SCons 말고 다른 도구도 필요합니다.

| 종류 | 파일 수 | 역할 |
|---|---|---|
| C++ | 2 | 웹에서 Mono 시작, 웹 내보내기 플러그인 |
| C# | 3 | 편집기 내보내기 단계, 런타임 팩 다운로드, 관리 코드 콜백 |
| MSBuild | 8 | `Godot.NET.Sdk`의 Browser 설정, 런타임 팩 프로젝트 |
| Python / SCons | 5 | 빌드 옵션, 웹의 mono 지원, JS 후처리 |

- 결과물이 엔진 바이너리 하나로 끝나지 않습니다. `GodotSharp` 어셈블리와 NuGet 패키지도 함께 만들어야 하고, C# 글루를 먼저 생성한 뒤에 빌드해서 편집기와 함께 배포합니다.
- 필요한 도구: SCons, Emscripten 6.0.2(웹), .NET 11 SDK, `wasm-tools` 워크로드.
- 패치만 일반 소스에 적용해서는 사용자가 쓸 수 없습니다. 패치된 SDK로 만든 NuGet 패키지와 `.mono` 웹 템플릿이 함께 있어야 합니다.

### .NET 버전: 11

이 저장소에서 바꾼 점: 원본 패치는 .NET 9 기준이었고, 여기서는 **.NET 11**(`net11.0`)을 대상으로 합니다.

- .NET 9는 .NET 11이 나온 2026-11-10에 지원이 끝났습니다.
- 대상 프레임워크는 `modules/mono/runtime/GetRuntimePack/GetRuntimePack.csproj` 한 곳에서만 정하고, `mono_configure.py`가 그 값을 읽습니다. `GetRuntimePack/global.json`이 .NET 11 SDK를 고정합니다.
- 메모리: .NET 10부터 WebAssembly의 Mono GC가 16KB 힙 블록을 하나씩 `posix_memalign`으로 할당합니다(.NET 9는 32개씩 묶음). Emscripten 기본 할당기에서는 선형 메모리 사용량이 약 2배가 될 수 있습니다([dotnet/runtime#136152](https://github.com/dotnet/runtime/issues/136152), 미해결). 여기 웹 템플릿은 `-sMALLOC=mimalloc`으로 링크하지만, 이것으로 낭비가 없어지는지는 아직 측정하지 않았습니다.
- .NET 11에서 CoreCLR on WebAssembly는 선택 기능이고, 이 패치는 .NET 11의 기본 브라우저 런타임인 Mono를 씁니다.

### 출처

이 저장소에서 새로 만든 코드가 아니라, 논리는 그대로 두고 `4.7.2-stable` 위에 올린 것입니다.

- 업스트림 PR [godotengine/godot#106125](https://github.com/godotengine/godot/pull/106125) "[.NET] Add web export support" — Raul Santos (업스트림에서는 아직 열려 있음)
- [ComplexRobot/godot](https://github.com/ComplexRobot/godot)의 `dotnet/mono-static-linking` 브랜치(`d1cc834954`) — Godot 4.7 재적용, 수정, `DOTNET.setup();` 제거 단계. Dom Finn의 PR 두 건(AOT 링크 옵션, 릴리스 템플릿의 Mono 디버그 레벨 0)도 포함합니다.
- 빌드·설치 절차는 [ComplexRobot/godot-dotnet-web-export](https://github.com/ComplexRobot/godot-dotnet-web-export)를 따랐습니다. 그 저장소는 Windows·macOS(Apple Silicon)용 완성 편집기도 배포합니다.

### 게임 프로젝트 요구 사항

- `.csproj`의 `TargetFramework`를 `net11.0`으로 설정합니다. 웹 템플릿을 빌드한 .NET 버전과 같아야 하며, 템플릿은 자기 버전으로 빌드한 게임만 실행합니다.
- .NET 11 SDK와 `wasm-tools` 워크로드가 필요합니다.
- 프로젝트 루트에 최상위 문장이 하나 이상 있는 `Program.cs`가 필요합니다. `{}`만 있어도 됩니다.
- `export_templates/<버전>.stable.mono` 폴더에 `web_release.zip` / `web_debug.zip`을 둡니다.
- 편집기와 함께 빌드한 NuGet 패키지(`GodotSharp` 등)를 로컬 NuGet 소스로 등록합니다.

### 한계

- 실험적 기능입니다. 웹 빌드에서는 일부 기능이 빠집니다.
  - GDExtension을 쓸 수 없습니다(.NET 런타임이 위치 독립 코드 없이 빌드됨). `godot-sqlite` 같은 애드온은 C# 웹 빌드에서 동작하지 않습니다.
  - 세계화는 항상 invariant 모드이고, 암호화 등 일부 BCL API는 동작하지 않습니다.
- **스레드 사용** 웹 템플릿입니다(`WasmEnableThreads=true`). 이 저장소의 GDScript 웹 내보내기가 쓰는 `nothreads` 템플릿과 다릅니다. `SharedArrayBuffer`가 동작하도록 호스팅에서 COOP / COEP 헤더를 보내야 합니다(itch.io는 "SharedArrayBuffer support" 켜기).
- Godot 4.7.2에서만 다룹니다.

### 빌드

- 위 Build 절의 명령을 그대로 쓰면 됩니다. C# 편집기를 먼저 빌드해 글루와 NuGet 패키지를 만든 뒤, 웹 템플릿(release / debug)을 리눅스에서 빌드합니다.
- 결과물 이름을 `web_release.zip` / `web_debug.zip`으로 바꿔 사용합니다.

### 상태

- 패치 적용: 확인했습니다. 단독으로도, 다른 두 패치와 함께도, 순서와 무관하게 적용됩니다.
- 이 브랜치에서의 빌드와 실제 C# 웹 내보내기: 아직 검증하지 않았습니다. `ime_dotnet_release.yml` 워크플로가 성공하면 [Releases](https://github.com/joygram/godot-ime/releases)에 결과물을 올리고 이 문서를 갱신합니다.

---

> 본 작업은 AI와 함께함 · This work was made with AI assistance.
