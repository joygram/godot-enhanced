#!/usr/bin/env bash
# Installs the C# web export files on macOS / Linux.
# Usage: bash install.sh   (run from the extracted folder)
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
version=${GODOT_VERSION:-4.7.2.stable}

for file in web_release.zip web_debug.zip nuget; do
  [[ -e "$here/$file" ]] || { echo "Error: '$here/$file' not found." >&2; exit 1; }
done
command -v dotnet >/dev/null || { echo "Error: 'dotnet' not found. Install the .NET 11 SDK first." >&2; exit 1; }

case "$(uname -s)" in
  Darwin) data_dir="$HOME/Library/Application Support/Godot" ;;
  *) data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/godot" ;;
esac
template_dir="$data_dir/export_templates/$version.mono"
nuget_dir="$HOME/.nuget/NuGet/nuget"

echo "Copying export templates to '$template_dir'..."
mkdir -p "$template_dir"
cp -f "$here/web_release.zip" "$here/web_debug.zip" "$template_dir/"
# Single-threaded templates (Thread Support off: no COOP / COEP headers needed)
for f in web_nothreads_release.zip web_nothreads_debug.zip; do [[ -e "$here/$f" ]] && cp -f "$here/$f" "$template_dir/"; done

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

# net11.0 projects need the .NET 11 SDK and its wasm-tools workload (a newer SDK would need wasm-tools-net11).
sdk_major=$(dotnet --version | cut -d. -f1)
if (( sdk_major < 11 )); then echo "Error: .NET 11 SDK required, found $(dotnet --version)." >&2; exit 1; fi
if (( sdk_major > 11 )); then workload=wasm-tools-net11; else workload=wasm-tools; fi
echo "Installing workload $workload..."
dotnet workload install "$workload" || echo "Warning: workload install failed; try again with sudo." >&2

echo "Done. If export fails with NETSDK1147, run 'dotnet workload repair'."
