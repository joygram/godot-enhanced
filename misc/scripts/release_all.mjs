// 한 버전(ENHANCED_VERSION)의 릴리스 3종을 로컬·빌드 에이전트로 전부 빌드·업로드하고, 빠진 자산이 없는지 확인 (CI 없이)
// 사용: node misc/scripts/release_all.mjs [editor] [web] [csharp] [--check]   (기본 = 셋 다, --check = 빌드 없이 확인만)
//   editor  → editor-<버전>      편집기 Windows·Linux(x86_64·arm64) + macOS universal   (build_editors.mjs)
//   web     → web-template-<버전> GDScript 웹 템플릿 4종 (threads·nothreads × 정적+SQLite·dlink) — linux 에이전트
//   csharp  → dotnet-web-<버전>  C# 웹 템플릿 4종 + 키트 (windows-x86_64·linux-x86_64·macos-arm64)
// 세 릴리스는 같은 버전이어야 함: 편집기는 자기 버전 폴더(…enhanced-<버전>)에서만 템플릿을 찾음
// 에이전트 = 별칭 linux·mac (~/.config/godot-enhanced/agents.json, 저장소에 내부망 주소 금지)
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const REPO = "joygram/godot-enhanced";
const ver = readFileSync(join(root, "version.py"), "utf8");
const pick = (k) => ver.match(new RegExp(`^${k}\\s*=\\s*(\\d+)`, "m"))[1];
const version = `${pick("major")}.${pick("minor")}.${pick("patch")}-${readFileSync(join(root, "ENHANCED_VERSION"), "utf8").trim()}`;
const node = (...args) => spawnSync(process.execPath, args, { cwd: root, stdio: "inherit" }).status === 0;
const remote = (host, ...args) => node(join("misc", "scripts", "remote_build.mjs"), host, ...args, "--wait");
const flags = ["accesskit=no", "debug_symbols=no"];

// 릴리스별 있어야 할 자산 (설치기 install.sh·install.ps1 와 소비 프로젝트가 찾는 이름)
const expected = {
	[`editor-${version}`]: ["windows.editor.x86_64", "windows.editor.arm64", "linuxbsd.editor.x86_64", "linuxbsd.editor.arm64", "macos.editor.universal"]
		.map((p) => `godot-${version}-enhanced.${p}.zip`),
	[`web-template-${version}`]: ["", ".nothreads", ".dlink", ".nothreads.dlink"].map((s) => `godot.web.template_release.wasm32${s}.zip`),
	[`dotnet-web-${version}`]: [
		...["template_release", "template_debug"].flatMap((t) => ["", ".nothreads"].map((s) => `godot.web.${t}.wasm32${s}.mono.zip`)),
		...["windows-x86_64", "linux-x86_64", "macos-arm64"].map((k) => `godot-${version}-enhanced.dotnet-web.${k}.zip`),
	],
};

const steps = {
	editor: () => node(join("misc", "scripts", "build_editors.mjs")),
	// 정적 템플릿 = SQLite 내장(module_sqlite_enabled), dlink 템플릿 = GDExtension 용
	web: () => [
		["module_sqlite_enabled=yes"], ["module_sqlite_enabled=yes", "threads=no"], ["dlink_enabled=yes"], ["dlink_enabled=yes", "threads=no"],
	].every((v) => remote("linux", "platform=web", "target=template_release", ...v, "--release", "web-template")),
	csharp: () =>
		// linux: C# 편집기 → 웹 템플릿 4종 업로드 → linux 키트
		remote("linux", "platform=linuxbsd", "arch=x86_64", "target=editor", "module_mono_enabled=yes", ...flags, "--test", "dotnet-web-templates,dotnet-kit")
		// mac: C# 편집기 arm64 → 키트
		&& remote("mac", "platform=macos", "arch=arm64", "target=editor", "module_mono_enabled=yes", "vulkan=no", "angle=no", ...flags, "--test", "dotnet-kit")
		// windows(이 PC): C# 편집기 → 키트 (Git Bash 로 dotnet_kit.sh)
		&& windowsKit(),
};

function windowsKit() {
	if (process.platform !== "win32") { console.error("[release-all] windows 키트는 Windows PC 에서"); return false; }
	const scons = spawnSync("python", ["-m", "SCons", "platform=windows", "arch=x86_64", "target=editor", "module_mono_enabled=yes", "d3d12=no", ...flags], { cwd: root, stdio: "inherit" });
	if (scons.status !== 0) return false;
	const bash = ["C:\\Program Files\\Git\\bin\\bash.exe", "C:\\Program Files (x86)\\Git\\bin\\bash.exe"].find(existsSync);
	if (!bash) { console.error("[release-all] Git Bash 없음 (Git for Windows 필요)"); return false; }
	return spawnSync(bash, ["misc/scripts/dotnet_kit.sh"], { cwd: root, stdio: "inherit" }).status === 0;
}

function check() {
	let ok = true;
	console.log(`\n[release-all] 자산 확인 (${version})`);
	for (const [tag, names] of Object.entries(expected)) {
		// 조회 실패가 네트워크(TLS) 탓일 수 있어 3번까지
		let r;
		for (let i = 0; i < 3; i++) if ((r = spawnSync("gh", ["release", "view", tag, "--repo", REPO, "--json", "assets", "--jq", ".assets[].name"], { encoding: "utf8" })).status === 0) break;
		const have = new Set(r.status === 0 ? r.stdout.split(/\r?\n/).filter(Boolean) : []);
		const missing = names.filter((n) => !have.has(n));
		ok &&= missing.length === 0;
		console.log(`  ${missing.length ? "✘" : "✔"} ${tag}${r.status !== 0 ? " (릴리스 없음)" : ""}${missing.length ? `\n      빠짐: ${missing.join("\n            ")}` : ""}`);
	}
	return ok;
}

const args = process.argv.slice(2);
const only = args.filter((a) => !a.startsWith("--"));
const unknown = only.filter((s) => !steps[s]);
if (unknown.length) { console.error(`알 수 없는 단계: ${unknown.join(", ")} (가능: editor · web · csharp)`); process.exit(2); }
if (!args.includes("--check")) {
	for (const s of only.length ? only : Object.keys(steps)) {
		console.log(`\n[release-all] ── ${s} (${version})`);
		if (!steps[s]()) console.error(`[release-all] ✘ ${s} 실패 — 이어서 다음 단계`);
	}
}
process.exit(check() ? 0 : 1);
