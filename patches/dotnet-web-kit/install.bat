@echo off
rem Installs the C# web export files on Windows. Run from the extracted folder.
set "VERSION=4.7.2.stable"
set "TEMPLATE_FOLDER=%AppData%\Godot\export_templates\%VERSION%.mono"
set "NUGET_FOLDER=%AppData%\NuGet\nuget"

echo Copying export templates to "%TEMPLATE_FOLDER%"...
md "%TEMPLATE_FOLDER%" 2>nul
copy /y "%~dp0web_release.zip" "%TEMPLATE_FOLDER%" >nul
copy /y "%~dp0web_debug.zip" "%TEMPLATE_FOLDER%" >nul

echo Copying NuGet packages to "%NUGET_FOLDER%"...
md "%NUGET_FOLDER%" 2>nul
copy /y "%~dp0nuget\*" "%NUGET_FOLDER%" >nul

rem Run dotnet from a folder without global.json so the SDK choice is not forced.
pushd "%TEMP%"
dotnet nuget add source "%NUGET_FOLDER%" --name NugetSource
echo Installing workload wasm-tools (.NET 9 SDK)...
dotnet workload install wasm-tools
popd

echo Done. With the .NET 10 SDK also run: dotnet workload install wasm-tools-net9
pause
