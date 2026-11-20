# godot-enhanced 소스 빌드

- 바로 설치(빌드 없이) = [README 맨 위](README.md#-install--update--one-command)
- 이 문서 = 소스에서 엔진 빌드: 원클릭 명령, 수동 단계, 원리

## 1. 원클릭

```bash
git clone https://github.com/joygram/godot-enhanced.git
cd godot-enhanced
npm run build          # 이 PC 용 편집기 (환경 확인 → 빠진 도구 설치 → 빌드)
```

| 명령 | 결과 |
|---|---|
| `npm run build` | 편집기 `bin/godot.<platform>.editor.<arch>` |
| `npm run build:web` | 웹 템플릿 4종 `bin/godot.web.template_release.wasm32*.zip` |
| `npm run build:csharp` | C# 편집기 `….mono` + `bin/GodotSharp` + `bin/nuget` |
| `npm run doctor[:web\|:csharp]` | 환경 확인만 |
| `npm run setup[:web\|:csharp]` | 빠진 도구 설치만 |

- 필요: Node.js 18+ (npm 실행용)
- SCons 인자 추가: `npm run build -- target=template_release`
- 결과 확인: 빌드 끝에 `--version` 출력, `enhanced-<ENHANCED_VERSION>` 아니면 경고

## 2. 자동 설치 / 수동 단계

| 도구 | 처리 |
|---|---|
| SCons | 자동 (`pip install --user scons`) |
| Emscripten (web) | 자동 (`~/emsdk`, 버전 = `misc/scripts/emscripten-version`) |
| .NET 11 SDK + wasm-tools (csharp) | 자동 (`~/.dotnet`) |
| Linux 빌드 패키지 | 자동 (`sudo apt-get`, 암호 입력) |
| macOS Xcode CLT | 설치 창 띄움 → 끝나면 다시 실행 |
| Windows MSVC | 수동 (아래) |
| git, Python 3.8+ | 수동 (아래) |

수동 명령:

- Windows MSVC:
  `winget install Microsoft.VisualStudio.2022.BuildTools --override "--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --passive"`
- Windows arm64 편집기: VS Installer → 개별 구성 요소 → "MSVC ARM64 빌드 도구"
- Python: Windows `winget install Python.Python.3.12`, macOS `brew install python`, Linux `sudo apt install python3 python3-pip`
- Linux arm64 크로스 빌드(x86_64 PC): `sudo apt-get install -y g++-aarch64-linux-gnu`

## 3. 원리

- 빌드 도구 = SCons. `scons platform=<windows|linuxbsd|macos|web> target=<editor|template_release|template_debug>`
- 편집기 플래그: `accesskit=no debug_symbols=no` + macOS `vulkan=no angle=no`, Windows `d3d12=no`
- 버전 = `version.py`(Godot 4.7.2) + `ENHANCED_VERSION` → `4.7.2.stable.enhanced-<버전>`
- 편집기는 자기 버전 폴더에서만 템플릿 찾음 → `export_templates/4.7.2.stable.enhanced-<버전>/`
- 버전 올린 뒤 이전 버전이 박히면 → `bin/obj` 지우고 다시 빌드

웹 템플릿 4종:

| 파일 | SCons 인자 |
|---|---|
| `web_release.zip` | `module_sqlite_enabled=yes` |
| `web_nothreads_release.zip` | `module_sqlite_enabled=yes threads=no` |
| `web_dlink_release.zip` | `dlink_enabled=yes` |
| `web_dlink_nothreads_release.zip` | `dlink_enabled=yes threads=no` |

- 정적 = SQLite 내장, dlink = GDExtension 용
- 산출 이름 `godot.web.template_release.wasm32[.nothreads][.dlink].zip` → 위 이름으로 템플릿 폴더에

C# 순서:

- C# 편집기(`module_mono_enabled=yes`) → glue(`--generate-mono-glue modules/mono/glue`) → `build_assemblies.py`
- C# 웹 템플릿 = glue 필요 → 편집기 다음 (`module_mono_enabled=yes`, emsdk + wasm-tools)
- 설계: [patches/dotnet-web-export.md](patches/dotnet-web-export.md)

Linux arm64:

- `platform/linuxbsd/detect.py`: x86_64 에서 `arch=arm64` → `aarch64-linux-gnu-*` 자동 사용
- `CC=… CXX=…` 직접 주면 그대로 씀

## 4. 엔진 패치 흐름

1. 소스 수정
2. `npm run local` = 편집기 빌드 → 웹 템플릿 빌드 → 로컬 설치
3. `godot-enhanced` 로 실제 프로젝트 확인 (로컬 설치 = `~/.godot-enhanced/local`)
4. 확인 끝 → `ENHANCED_VERSION` 올림 → 커밋·푸시
5. `npm run release` → 빠진 자산 빌드·업로드
6. 사용자 쪽 = install 명령 재실행 → 최신 릴리스

- 편집기만: `npm run build && npm run install:local`
- C#: `npm run build:csharp && npm run install:local:csharp`
- 로컬 설치 ↔ 릴리스 설치 = 같은 명령 `godot-enhanced`, 마지막 실행한 쪽이 연결됨

## 5. 릴리스 (관리자)

- `npm run release` = 3종 릴리스에서 빠진 자산만 빌드 → 성공한 것만 업로드 → 전체 확인
- `npm run release -- editor` (또는 `web`, `csharp`) = 한 종류만
- `npm run release:check` = 빌드 없이 빠진 자산 확인
- 세 릴리스 = 같은 `ENHANCED_VERSION` (편집기 ↔ 템플릿 폴더 일치)

| 릴리스 | 자산 | 빌드 위치 |
|---|---|---|
| `editor-<버전>` | Windows·Linux x86_64·arm64, macOS universal | 이 PC, linux, mac |
| `web-template-<버전>` | 웹 템플릿 4종 | linux |
| `dotnet-web-<버전>` | C# 웹 템플릿 4종 + 키트 3종 | linux, mac, 이 PC |

### 원격 빌드 설정 (.env)

- 원격 빌드 = 빌드 에이전트(`misc/scripts/build_agent.mjs`)에 HTTP 로 요청, SSH 없음
- 내부망 주소·토큰 = 저장소 `.env` 에만. 커밋 금지 (`.gitignore`)
- 시작: `cp .env.example .env` → 값 채움

```ini
BUILD_AGENT_LINUX_HOST=<linux 에이전트 주소>
BUILD_AGENT_LINUX_TOKEN=<토큰>
BUILD_AGENT_MAC_HOST=<mac 에이전트 주소>
BUILD_AGENT_MAC_TOKEN=<토큰>
# BUILD_AGENT_PORT=8790
```

- 키 = `BUILD_AGENT_<별칭>_HOST`·`_TOKEN`. 별칭 `linux`·`mac` = 릴리스 스크립트가 씀
- 우선순위: 환경 변수 → `.env` → `~/.config/godot-enhanced/agents.json`
- 토큰 = 에이전트 쪽 `~/.config/godot-enhanced/agent.env` 의 `BUILD_AGENT_TOKEN`
- 에이전트 설치: `curl -fsSL https://raw.githubusercontent.com/joygram/godot-enhanced/main/misc/scripts/setup_build_agent.sh | bash`
- macOS 에이전트 = 로그인 세션 LaunchAgent → 재부팅 후 로그인해야 뜸
- 릴리스 노트·로그에 주소 안 남김 (노트 = "Built on a build agent")
