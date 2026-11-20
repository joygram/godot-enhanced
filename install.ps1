# godot-enhanced installer / updater (Windows)
#   irm https://raw.githubusercontent.com/joygram/godot-enhanced/main/install.ps1 | iex                                   # GDScript editor + web templates
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/joygram/godot-enhanced/main/install.ps1))) csharp     # C# (.NET 11) kit
# Run the same command again to update to the latest release (already-installed releases are skipped).
# Env: GODOT_ENHANCED_HOME (default ~\.godot-enhanced), GODOT_ENHANCED_TAG (pin a release tag)
param([string]$Mode = "editor")
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$Repo = if ($env:GODOT_ENHANCED_REPO) { $env:GODOT_ENHANCED_REPO } else { "joygram/godot-enhanced" }
$Root = if ($env:GODOT_ENHANCED_HOME) { $env:GODOT_ENHANCED_HOME } else { Join-Path $HOME ".godot-enhanced" }
$Arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "x86_64" }
$Data = Join-Path $env:APPDATA "Godot"
function Say($m) { Write-Host "[godot-enhanced] $m" -ForegroundColor Cyan }

function Latest($prefix, $suffix) {
	if ($env:GODOT_ENHANCED_TAG) { return $env:GODOT_ENHANCED_TAG }
	$rels = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases?per_page=50" -Headers @{ Accept = "application/vnd.github+json" }
	$r = $rels | Where-Object { -not $_.draft -and $_.tag_name.StartsWith($prefix) -and ($_.assets | Where-Object { $_.name.EndsWith($suffix) }) } | Select-Object -First 1
	if (-not $r) { throw "No release $prefix* with *$suffix for windows/$Arch." }
	return $r.tag_name
}
function Fetch($tag, $asset, $dest) {
	Say "download $asset"
	Invoke-WebRequest "https://github.com/$Repo/releases/download/$tag/$asset" -OutFile $dest
}
function Link($exe) {
	# godot-enhanced.cmd in ~\.godot-enhanced\bin (added to the user PATH once)
	$bin = Join-Path $Root "bin"; New-Item -ItemType Directory -Force $bin | Out-Null
	Set-Content (Join-Path $bin "godot-enhanced.cmd") "@`"$exe`" %*" -Encoding ASCII
	$path = [Environment]::GetEnvironmentVariable("Path", "User")
	if (($path -split ";") -notcontains $bin) { [Environment]::SetEnvironmentVariable("Path", "$path;$bin", "User"); Say "added $bin to PATH (open a new terminal)" }
	Say "command: godot-enhanced → $exe"
}
function TemplateDir($exe) {
	# Export templates folder the editor looks for = its version without the commit hash
	$console = $exe -replace '\.exe$', '.console.exe'
	$v = (& $(if (Test-Path $console) { $console } else { $exe }) --headless --version | Select-Object -Last 1).Trim()
	return Join-Path $Data "export_templates\$($v.Substring(0, $v.LastIndexOf('.')))"
}

function Install-Editor {
	$tag = Latest "editor-" ".windows.editor.$Arch.zip"
	$dir = Join-Path $Root $tag
	if (Test-Path (Join-Path $dir ".installed")) { Say "$tag already installed" } else {
		Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force $dir | Out-Null
		$zip = Join-Path $dir "editor.zip"
		Fetch $tag "godot-$($tag.Substring(7))-enhanced.windows.editor.$Arch.zip" $zip
		Expand-Archive $zip $dir -Force; Remove-Item $zip
		New-Item (Join-Path $dir ".installed") -ItemType File | Out-Null
	}
	$exe = Join-Path $dir "godot.windows.editor.$Arch.exe"
	Link $exe
	$wtag = Latest "web-template-" "godot.web.template_release.wasm32.zip"
	$tdir = TemplateDir $exe
	$stamp = Join-Path $tdir ".web-template"
	if ((Test-Path $stamp) -and ((Get-Content $stamp) -eq $wtag)) { Say "web templates $wtag already installed" } else {
		New-Item -ItemType Directory -Force $tdir | Out-Null
		$pairs = @{ "wasm32.zip" = "web_release.zip"; "wasm32.nothreads.zip" = "web_nothreads_release.zip"; "wasm32.dlink.zip" = "web_dlink_release.zip"; "wasm32.nothreads.dlink.zip" = "web_dlink_nothreads_release.zip" }
		foreach ($k in $pairs.Keys) { Fetch $wtag "godot.web.template_release.$k" (Join-Path $tdir $pairs[$k]) }
		Set-Content $stamp $wtag
	}
	Say "✔ editor $tag, web templates $wtag → $tdir"
}

function Install-CSharp {
	if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { throw "'dotnet' not found. Install the .NET 11 SDK first." }
	$tag = Latest "dotnet-web-" ".dotnet-web.windows-$Arch.zip"
	$dir = Join-Path $Root $tag
	if (Test-Path (Join-Path $dir ".installed")) { Say "$tag already installed" } else {
		Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force $dir | Out-Null
		$zip = Join-Path $dir "kit.zip"
		Fetch $tag "godot-$($tag.Substring(11))-enhanced.dotnet-web.windows-$Arch.zip" $zip
		Expand-Archive $zip $dir -Force; Remove-Item $zip
		$kit = (Get-ChildItem $dir -Directory | Select-Object -First 1).FullName
		Push-Location $kit; try { cmd /c install.bat } finally { Pop-Location }   # NuGet source + wasm-tools workload
		New-Item (Join-Path $dir ".installed") -ItemType File | Out-Null
	}
	$kit = (Get-ChildItem $dir -Directory | Select-Object -First 1).FullName
	$exe = (Get-ChildItem $kit -Filter "godot.windows.editor.*.mono.exe" | Where-Object { $_.Name -notlike "*console*" } | Select-Object -First 1).FullName
	$tdir = TemplateDir $exe
	New-Item -ItemType Directory -Force $tdir | Out-Null
	Copy-Item (Join-Path $kit "web_*.zip") $tdir -Force
	Link $exe
	Say "✔ C# kit $tag, templates → $tdir"
	Say "project: <TargetFramework>net11.0</TargetFramework>, copy $kit\Program.cs to the project root if it has none"
}

switch ($Mode) {
	{ $_ -in "editor", "update", "" } { Install-Editor }
	{ $_ -in "csharp", "dotnet" } { Install-CSharp }
	default { throw "usage: install.ps1 [editor|csharp]" }
}
