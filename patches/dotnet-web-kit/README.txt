Godot 4.7.2-ime — C# (.NET) web export kit
==========================================

Experimental. See https://github.com/joygram/godot-ime/blob/4.7.2-ime/patches/dotnet-web-export.md

1. Extract this zip.
2. Run install.bat (Windows) or `bash install.sh` (macOS / Linux).
   It copies web_release.zip / web_debug.zip to the export templates folder
   (<version>.stable.mono), registers ./nuget as a local NuGet source and
   installs the .NET workload wasm-tools.
3. In your project's .csproj set <TargetFramework>net9.0</TargetFramework>.
4. Copy Program.cs (a single `{}`) to your project root if it has none.
5. Open the project with the editor from this zip and export for the web.

Limits: no GDExtension in C# web builds; threaded template, so the web server
must send COOP / COEP headers (itch.io: enable "SharedArrayBuffer support").

한국어: 압축을 풀고 install.bat(Windows) 또는 `bash install.sh`(macOS·Linux)를 실행한 뒤,
프로젝트의 TargetFramework 를 net9.0 으로 바꾸고 Program.cs 를 프로젝트 루트에 복사하세요.
이 압축 파일의 편집기로 프로젝트를 열어 웹으로 내보내면 됩니다.

Based on work by Raul Santos (godotengine/godot#106125), ComplexRobot and Dom Finn.
This work was made with AI assistance. / 본 작업은 AI와 함께함
