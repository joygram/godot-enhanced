# net11 전환 호환 이슈 (미검증)

SDK 11 환경에서 빌드·테스트 전. 확인 필요 항목만 기록.

## 빌드
- SDK 11 설치 후 `modules/mono/build_scripts/build_assemblies.py` 전체 빌드 확인 필요
- `GodotPlugins` 출력 경로 `bin/<cfg>/net11.0` 일치 확인 필요
- `gd_mono.cpp` SDK 탐색(hostfxr, `dotnet --list-sdks`) 11 대응 확인 필요
- `linux_builds.yml` 등 CI = `11.0.x` 전환, 러너 SDK 11 설치 가능 여부 확인 필요

## 테스트
- `Godot.SourceGenerators.Tests`: `Microsoft.NETCore.App.Ref` 11.0.0 패키지 존재 여부 미확인
- `Microsoft.CodeAnalysis.CSharp.Workspaces` 4.8.0 = net11 참조 어셈블리 호환 미확인
- 식별자 `Constants.Net110` (구 `Net80`)

## 사용자 프로젝트
- 기존 `net8.0` 게임 프로젝트 = GodotSharp 로드 불가 → `TargetFramework` net11.0 수정 필요
- `GodotMinimumRequiredTfm` = `net11.0` → 구 프로젝트에서 경고·거절 가능
- 서드파티 NuGet = net11 호환 미확인

## 유지
- `netstandard2.0` (Godot.NET.Sdk, SourceGenerators, IdeMessaging, Internal) = Roslyn·IDE 호환 위해 유지
- `LangVersion` 변경 없음
