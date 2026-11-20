// 소스에서 엔진 빌드: 환경 확인 → 자동 설치(가능한 것) → 빌드. npm run doctor | setup | build | build:web | build:csharp
// 사용: node misc/scripts/dev.mjs <doctor|setup|build> [editor|web|csharp] [scons 인자...]
//   doctor  필요한 도구 확인만
//   setup   빠진 도구 설치 (scons·Emscripten·.NET = 사용자 영역 자동, 컴파일러 = 명령 안내 또는 확인 후 설치)
//   build   setup 후 빌드. editor = 이 PC 용 편집기, web = 웹 템플릿 4종, csharp = C# 편집기 + GodotSharp
// 수동 단계·원리 = BUILDING.md
import { spawnSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { cpus, homedir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const WIN = process.platform === "win32", MAC = process.platform === "darwin";
const plat = WIN ? "windows" : MAC ? "macos" : "linuxbsd";
const arch = process.arch === "arm64" ? "arm64" : "x86_64";
// emsdk 위치: EMSDK_DIR → EMSDK(emsdk_env 가 설정) → ~/emsdk (없으면 setup 이 여기에 설치)
const EMSDK = process.env.EMSDK_DIR || process.env.EMSDK || join(homedir(), "emsdk");
const EMSDK_VERSION = readFileSync(join(root, "misc", "scripts", "emscripten-version"), "utf8").trim();
const DOTNET_DIR = join(homedir(), ".dotnet");
const enhanced = readFileSync(join(root, "ENHANCED_VERSION"), "utf8").trim();
const [cmd = "doctor", what = "editor", ...extra] = process.argv.slice(2);
const say = (m) => console.log(`\x1b[36m[dev]\x1b[0m ${m}`);
const sh = (c, a, o = {}) => spawnSync(c, a, { cwd: root, encoding: "utf8", shell: WIN, ...o });
const ok = (c, a) => { try { return sh(c, a).status === 0; } catch { return false; } };
const run = (c, a, o = {}) => { say(`$ ${c} ${a.join(" ")}`); return sh(c, a, { stdio: "inherit", ...o }).status === 0; };
const PY = ["python3", "python"].find((p) => ok(p, ["--version"])) ?? null;

// ── 도구 확인: { 이름, 있나, 고치는 법(auto = 자동 설치 함수 | manual = 안내) }
function vswhere() {
	const exe = join(process.env["ProgramFiles(x86)"] || "C:\\Program Files (x86)", "Microsoft Visual Studio", "Installer", "vswhere.exe");
	if (!existsSync(exe)) return null;
	const r = spawnSync(exe, ["-latest", "-products", "*", "-requires", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64", "-property", "installationPath"], { encoding: "utf8" });
	return r.stdout.trim() || null;
}
const LINUX_PKGS = ["build-essential", "pkg-config", "libx11-dev", "libxcursor-dev", "libxinerama-dev", "libgl1-mesa-dev", "libglu1-mesa-dev",
	"libasound2-dev", "libpulse-dev", "libudev-dev", "libxi-dev", "libxrandr-dev", "libwayland-dev"];
function checks(target) {
	const list = [
		{ name: "git", have: ok("git", ["--version"]), manual: "https://git-scm.com/downloads" },
		{ name: "Python 3.8+", have: !!PY, manual: WIN ? "winget install Python.Python.3.12" : MAC ? "brew install python" : "sudo apt install python3 python3-pip" },
		{ name: "SCons", have: !!PY && ok(PY, ["-m", "SCons", "--version"]), auto: () => run(PY, ["-m", "pip", "install", "--user", "scons==4.11.1"]) },
	];
	if (WIN) list.push({ name: "Visual Studio C++ (MSVC)", have: !!vswhere(),
		manual: "winget install Microsoft.VisualStudio.2022.BuildTools --override \"--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --passive\"" });
	else if (MAC) list.push({ name: "Xcode Command Line Tools", have: ok("xcode-select", ["-p"]), auto: () => run("xcode-select", ["--install"]) && false });
	else {
		const missing = LINUX_PKGS.filter((p) => !ok("dpkg", ["-s", p]));
		list.push({ name: `Linux 빌드 패키지${missing.length ? ` (없음: ${missing.join(" ")})` : ""}`, have: missing.length === 0,
			auto: () => run("sudo", ["apt-get", "install", "-y", ...missing]), manual: `sudo apt-get install -y ${missing.join(" ")}` });
	}
	if (target === "web") list.push({ name: `Emscripten ${EMSDK_VERSION} (${EMSDK})`, have: emsdkReady(), auto: installEmsdk });
	if (target === "csharp") list.push({ name: ".NET 11 SDK + wasm-tools", have: dotnetReady(), auto: installDotnet });
	return list;
}

function emsdkReady() {
	const v = join(EMSDK, "upstream", "emscripten", "emscripten-version.txt");
	return existsSync(v) && readFileSync(v, "utf8").includes(EMSDK_VERSION);
}
function installEmsdk() {
	if (!existsSync(EMSDK) && !run("git", ["clone", "https://github.com/emscripten-core/emsdk.git", EMSDK], { cwd: homedir() })) return false;
	const e = join(EMSDK, WIN ? "emsdk.bat" : "emsdk");
	return run(e, ["install", EMSDK_VERSION], { cwd: EMSDK }) && run(e, ["activate", EMSDK_VERSION], { cwd: EMSDK });
}
function dotnetExe() {
	const local = join(DOTNET_DIR, WIN ? "dotnet.exe" : "dotnet");
	return existsSync(local) ? local : "dotnet";
}
function dotnetReady() {
	const r = sh(dotnetExe(), ["--list-sdks"]);
	return r.status === 0 && /^11\./m.test(r.stdout) && /wasm-tools/.test(sh(dotnetExe(), ["workload", "list"]).stdout ?? "");
}
function installDotnet() {
	if (!/^11\./m.test(sh(dotnetExe(), ["--list-sdks"]).stdout ?? "")) {
		const okInstall = WIN
			? run("powershell", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command",
				`&([scriptblock]::Create((irm https://dot.net/v1/dotnet-install.ps1))) -Channel 11.0 -InstallDir '${DOTNET_DIR}'`])
			: run("bash", ["-c", `curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 11.0 --install-dir '${DOTNET_DIR}'`]);
		if (!okInstall) return false;
	}
	return run(dotnetExe(), ["workload", "install", "wasm-tools"], { env: { ...process.env, DOTNET_ROOT: DOTNET_DIR } });
}

function doctor(target, fix) {
	let all = true;
	say(`환경 확인 — ${target} (${plat}/${arch})`);
	for (const c of checks(target)) {
		if (c.have) { console.log(`  ✔ ${c.name}`); continue; }
		if (fix && c.auto) { console.log(`  … ${c.name} 설치`); if (c.auto()) { console.log(`  ✔ ${c.name}`); continue; } }
		all = false;
		console.log(`  ✘ ${c.name}${c.manual ? `\n      → ${c.manual}` : ""}`);
	}
	if (!all) say("✘ 위 항목을 설치한 뒤 다시 실행 (수동 단계 = BUILDING.md)");
	return all;
}

// ── 빌드
const flags = ["accesskit=no", "debug_symbols=no", ...(MAC ? ["vulkan=no", "angle=no"] : WIN ? ["d3d12=no"] : [])];
const jobs = Math.max(1, cpus().length - 1);
const scons = (args) => run(PY, ["-m", "SCons", `platform=${plat}`, ...args.list, `-j${jobs}`, ...extra]);
function inEmsdk(args) {
	// emsdk 환경을 올린 셸에서 scons
	const line = `${PY} -m SCons ${args.join(" ")} -j${jobs}`;
	return WIN ? run("cmd", ["/c", `call "${join(EMSDK, "emsdk_env.bat")}" >nul && ${line}`])
		: run("bash", ["-c", `source '${join(EMSDK, "emsdk_env.sh")}' >/dev/null && ${line}`]);
}
function editorPath(mono) {
	const base = `godot.${plat}.editor.${arch}${mono ? ".mono" : ""}`;
	return join(root, "bin", WIN ? `${base}.exe` : base);
}
function checkVersion(exe) {
	const v = sh(exe, ["--headless", "--version"]).stdout?.trim().split(/\r?\n/).pop() ?? "";
	// 버전 헤더가 바뀌어도 다시 컴파일 안 된 오브젝트가 이전 버전을 박는 경우 있음
	if (!v.includes(`enhanced-${enhanced}`)) { say(`⚠ ${exe} 버전 ${v} ≠ enhanced-${enhanced} → bin/obj 지우고 다시 빌드`); return false; }
	say(`✔ ${exe}\n      ${v}`);
	return true;
}

const builds = {
	editor: () => scons({ list: ["target=editor", `arch=${arch}`, ...flags] }) && checkVersion(editorPath(false)),
	// 웹 템플릿 4종 (릴리스와 같은 구성): 정적(SQLite 내장) threads·nothreads, dlink threads·nothreads
	web: () => [["module_sqlite_enabled=yes"], ["module_sqlite_enabled=yes", "threads=no"], ["dlink_enabled=yes"], ["dlink_enabled=yes", "threads=no"]]
		.every((v) => inEmsdk(["platform=web", "target=template_release", ...v, ...extra])) && (say("✔ bin/godot.web.template_release.wasm32*.zip"), true),
	// C# 편집기 → glue → GodotSharp·NuGet
	csharp: () => {
		const env = { ...process.env, DOTNET_ROOT: DOTNET_DIR, PATH: `${DOTNET_DIR}${WIN ? ";" : ":"}${process.env.PATH}` };
		if (!scons({ list: ["target=editor", `arch=${arch}`, "module_mono_enabled=yes", ...flags] })) return false;
		const exe = editorPath(true);
		return run(exe, ["--headless", "--quit", "--generate-mono-glue", "modules/mono/glue"], { env })
			&& run(PY, ["modules/mono/build_scripts/build_assemblies.py", "--godot-output-dir=./bin", "--push-nupkgs-local", "./bin/nuget"], { env })
			&& checkVersion(exe);
	},
};

// ── 로컬 설치: 방금 빌드한 편집기·웹 템플릿을 install.sh·install.ps1 와 같은 자리에 (~/.godot-enhanced/local, 명령 godot-enhanced)
function installLocal(mono) {
	const exe = editorPath(mono);
	if (!existsSync(exe)) { say(`✘ 빌드된 편집기 없음: ${exe} → npm run build`); return false; }
	if (!checkVersion(exe)) return false;
	const home = process.env.GODOT_ENHANCED_HOME || join(homedir(), ".godot-enhanced");
	const dir = join(home, "local");
	rmSync(dir, { recursive: true, force: true });
	mkdirSync(dir, { recursive: true });
	const base = basename(exe).replace(/\.exe$/, "");
	for (const f of readdirSync(join(root, "bin"))) if (f.startsWith(base) && (mono || !f.includes(".mono")) && !/\.(lib|exp|pdb)$/.test(f)) cpSync(join(root, "bin", f), join(dir, f));
	if (mono && existsSync(join(root, "bin", "GodotSharp"))) cpSync(join(root, "bin", "GodotSharp"), join(dir, "GodotSharp"), { recursive: true });
	const installed = join(dir, basename(exe));
	// 명령 godot-enhanced
	if (WIN) {
		const bin = join(home, "bin"); mkdirSync(bin, { recursive: true });
		writeFileSync(join(bin, "godot-enhanced.cmd"), `@"${installed}" %*\r\n`);
		say(`command: ${join(bin, "godot-enhanced.cmd")} (PATH 에 ${bin} — install.ps1 이 한 번 추가)`);
	} else {
		const bin = process.env.GODOT_ENHANCED_BIN || join(homedir(), ".local", "bin"); mkdirSync(bin, { recursive: true });
		rmSync(join(bin, "godot-enhanced"), { force: true }); symlinkSync(installed, join(bin, "godot-enhanced"));
		say(`command: ${join(bin, "godot-enhanced")}`);
	}
	// 웹 템플릿: 편집기가 찾는 버전 폴더에 릴리스 이름으로
	const v = sh(installed, ["--headless", "--version"]).stdout.trim().split(/\r?\n/).pop();
	const data = WIN ? join(process.env.APPDATA, "Godot") : MAC ? join(homedir(), "Library", "Application Support", "Godot")
		: join(process.env.XDG_DATA_HOME || join(homedir(), ".local", "share"), "godot");
	const tdir = join(data, "export_templates", v.slice(0, v.lastIndexOf(".")));
	mkdirSync(tdir, { recursive: true });
	const names = mono
		? { "template_release.wasm32.mono.zip": "web_release.zip", "template_release.wasm32.nothreads.mono.zip": "web_nothreads_release.zip",
			"template_debug.wasm32.mono.zip": "web_debug.zip", "template_debug.wasm32.nothreads.mono.zip": "web_nothreads_debug.zip" }
		: { "template_release.wasm32.zip": "web_release.zip", "template_release.wasm32.nothreads.zip": "web_nothreads_release.zip",
			"template_release.wasm32.dlink.zip": "web_dlink_release.zip", "template_release.wasm32.nothreads.dlink.zip": "web_dlink_nothreads_release.zip" };
	let n = 0;
	for (const [src, dst] of Object.entries(names)) {
		const p = join(root, "bin", `godot.web.${src}`);
		if (existsSync(p)) { cpSync(p, join(tdir, dst)); n++; }
	}
	say(`✔ 로컬 설치 ${installed}\n      웹 템플릿 ${n}/${Object.keys(names).length} → ${tdir}${n < 4 ? ` (빠진 것 = npm run build:web${mono ? " (C#: release_all csharp)" : ""})` : ""}`);
	return true;
}

if (cmd === "install") process.exit(installLocal(what === "csharp") ? 0 : 1);
if (!["doctor", "setup", "build"].includes(cmd) || !builds[what]) {
	console.error("사용: node misc/scripts/dev.mjs <doctor|setup|build|install> [editor|web|csharp] [scons 인자...]");
	process.exit(2);
}
if (cmd === "doctor") process.exit(doctor(what, false) ? 0 : 1);
if (!doctor(what, true)) process.exit(1);
if (cmd === "setup") process.exit(0);
process.exit(builds[what]() ? 0 : 1);
