#!/usr/bin/env bash
# godot-enhanced installer / updater (Linux, macOS)
#   curl -fsSL https://raw.githubusercontent.com/joygram/godot-enhanced/main/install.sh | bash               # GDScript editor + web templates
#   curl -fsSL https://raw.githubusercontent.com/joygram/godot-enhanced/main/install.sh | bash -s -- csharp  # C# (.NET 11) editor + C# web templates + NuGet
# Run the same command again to update to the latest release (already-installed releases are skipped).
# Env: GODOT_ENHANCED_HOME (default ~/.godot-enhanced), GODOT_ENHANCED_BIN (default ~/.local/bin), GODOT_ENHANCED_TAG (pin a release tag)
set -euo pipefail

REPO="${GODOT_ENHANCED_REPO:-joygram/godot-enhanced}"
ROOT="${GODOT_ENHANCED_HOME:-$HOME/.godot-enhanced}"
BIN="${GODOT_ENHANCED_BIN:-$HOME/.local/bin}"
mode="${1:-editor}"
say() { printf '\033[1;36m[godot-enhanced]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[godot-enhanced]\033[0m %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "'$1' is required."; }
need curl; need unzip

case "$(uname -s)" in
	Linux) os=linux; plat=linuxbsd; data="${XDG_DATA_HOME:-$HOME/.local/share}/godot" ;;
	Darwin) os=macos; plat=macos; data="$HOME/Library/Application Support/Godot" ;;
	*) die "Unsupported OS $(uname -s). On Windows use install.ps1." ;;
esac
case "$(uname -m)" in aarch64|arm64) arch=arm64 ;; x86_64|amd64) arch=x86_64 ;; *) die "Unsupported CPU $(uname -m)." ;; esac

# Newest release whose tag starts with $1 and that has an asset ending with $2
latest() {
	local prefix="$1" suffix="$2" json tag
	[ -n "${GODOT_ENHANCED_TAG:-}" ] && { echo "$GODOT_ENHANCED_TAG"; return; }
	json=$(curl -fsSL -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$REPO/releases?per_page=50") || die "GitHub API request failed."
	# Split per release; keep the first (newest) one with the tag prefix and the asset.
	tag=$(printf '%s' "$json" | tr -d '\n' | sed 's/"tag_name"/\n"tag_name"/g' \
		| grep "^\"tag_name\": *\"$prefix" | grep -F "$suffix\"" | head -1 | sed -E 's/^"tag_name": *"([^"]+)".*/\1/')
	[ -n "$tag" ] || die "No release $prefix* with *$suffix for $os/$arch."
	echo "$tag"
}
fetch() { # tag asset dest
	say "download $2"
	curl -fL --retry 3 --progress-bar -o "$3" "https://github.com/$REPO/releases/download/$1/$2"
}
link() { # target
	mkdir -p "$BIN"
	ln -sf "$1" "$BIN/godot-enhanced"
	say "command: $BIN/godot-enhanced → $1"
	case ":$PATH:" in *":$BIN:"*) ;; *) say "add to PATH: export PATH=\"$BIN:\$PATH\"" ;; esac
}
# Export templates folder the editor looks for = its version without the commit hash
template_dir() { # editor binary
	local v; v=$("$1" --headless --version 2>/dev/null | tail -1)
	echo "$data/export_templates/${v%.*}"
}

install_editor() {
	local farch=$arch; [ "$os" = macos ] && farch=universal
	local tag; tag=$(latest editor- ".$plat.editor.$farch.zip")
	local dir="$ROOT/$tag" exe
	if [ -f "$dir/.installed" ]; then say "$tag already installed"
	else
		rm -rf "$dir"; mkdir -p "$dir"
		local zip="$dir/editor.zip"; fetch "$tag" "godot-${tag#editor-}-enhanced.$plat.editor.$farch.zip" "$zip"
		unzip -qo "$zip" -d "$dir"; rm -f "$zip"
		[ "$os" = macos ] && xattr -dr com.apple.quarantine "$dir/Godot.app" 2>/dev/null || true
		touch "$dir/.installed"
	fi
	if [ "$os" = macos ]; then exe="$dir/Godot.app/Contents/MacOS/Godot"; else exe="$dir/godot.linuxbsd.editor.$arch"; fi
	chmod +x "$exe"
	link "$exe"
	# Web export templates (GDScript): threads / nothreads × static / dlink
	local wtag; wtag=$(latest web-template- "godot.web.template_release.wasm32.zip")
	local tdir; tdir=$(template_dir "$exe")
	if [ "$(cat "$tdir/.web-template" 2>/dev/null)" = "$wtag" ]; then say "web templates $wtag already installed"
	else
		mkdir -p "$tdir"
		for pair in wasm32.zip:web_release.zip wasm32.nothreads.zip:web_nothreads_release.zip \
			wasm32.dlink.zip:web_dlink_release.zip wasm32.nothreads.dlink.zip:web_dlink_nothreads_release.zip; do
			fetch "$wtag" "godot.web.template_release.${pair%%:*}" "$tdir/${pair##*:}"
		done
		echo "$wtag" > "$tdir/.web-template"
	fi
	say "✔ editor $tag, web templates $wtag → $tdir"
}

install_csharp() {
	need dotnet
	local karch=$arch; [ "$os" = macos ] && karch=arm64
	local tag; tag=$(latest dotnet-web- ".dotnet-web.$os-$karch.zip")
	local dir="$ROOT/$tag" kit exe
	if [ -f "$dir/.installed" ]; then say "$tag already installed"
	else
		rm -rf "$dir"; mkdir -p "$dir"
		local zip="$dir/kit.zip"; fetch "$tag" "godot-${tag#dotnet-web-}-enhanced.dotnet-web.$os-$karch.zip" "$zip"
		unzip -qo "$zip" -d "$dir"; rm -f "$zip"
		kit=$(find "$dir" -maxdepth 1 -mindepth 1 -type d | head -1)
		[ "$os" = macos ] && xattr -dr com.apple.quarantine "$kit" 2>/dev/null || true
		(cd "$kit" && bash install.sh)   # NuGet source + wasm-tools workload
		touch "$dir/.installed"
	fi
	kit=$(find "$dir" -maxdepth 1 -mindepth 1 -type d | head -1)
	if [ "$os" = macos ]; then exe="$kit/Godot.app/Contents/MacOS/Godot"; else exe=$(ls "$kit"/godot.linuxbsd.editor.*.mono | head -1); fi
	chmod +x "$exe"
	local tdir; tdir=$(template_dir "$exe"); mkdir -p "$tdir"
	cp -f "$kit"/web_*.zip "$tdir/"
	link "$exe"
	say "✔ C# kit $tag, templates → $tdir"
	say "project: <TargetFramework>net11.0</TargetFramework>, copy $kit/Program.cs to the project root if it has none"
}

case "$mode" in
	editor|update|"") install_editor ;;
	csharp|dotnet) install_csharp ;;
	*) die "usage: install.sh [editor|csharp]" ;;
esac
