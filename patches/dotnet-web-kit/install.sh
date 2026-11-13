#!/usr/bin/env bash
# Installs the C# web export files on macOS / Linux.
# Usage: bash install.sh   (run from the extracted folder)
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
version=${GODOT_VERSION:-4.7.2.stable}

for file in web_release.zip web_debug.zip nuget; do
  [[ -e "$here/$file" ]] || { echo "Error: '$here/$file' not found." >&2; exit 1; }
done
command -v dotnet >/dev/null || { echo "Error: 'dotnet' not found. Install the .NET 9 SDK first." >&2; exit 1; }

case "$(uname -s)" in
  Darwin) data_dir="$HOME/Library/Application Support/Godot" ;;
  *) data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/godot" ;;
esac
template_dir="$data_dir/export_templates/$version.mono"
nuget_dir="$HOME/.nuget/NuGet/nuget"

echo "Copying export templates to '$template_dir'..."
mkdir -p "$template_dir"
cp -f "$here/web_release.zip" "$here/web_debug.zip" "$template_dir/"

echo "Copying NuGet packages to '$nuget_dir'..."
mkdir -p "$nuget_dir"
cp -f "$here"/nuget/* "$nuget_dir/"

# Run dotnet outside this folder so its global.json does not pick the SDK.
cd "$(mktemp -d)"
if dotnet nuget list source | grep -qF "$nuget_dir"; then
  echo "'$nuget_dir' is already a NuGet source."
else
  dotnet nuget add source "$nuget_dir" --name NugetSource || echo "Warning: could not add the NuGet source." >&2
fi

# net9.0 projects: the .NET 9 SDK uses wasm-tools, the .NET 10 SDK needs wasm-tools-net9.
sdk_major=$(dotnet --version | cut -d. -f1)
if (( sdk_major >= 10 )); then workload=wasm-tools-net9; else workload=wasm-tools; fi
echo "Installing workload $workload..."
dotnet workload install "$workload" || echo "Warning: workload install failed; try again with sudo." >&2

echo "Done. If export fails with NETSDK1147, run 'dotnet workload repair'."
