// 릴리스: 빌드 경로에 따라 분기.
//   로컬 빌드 → 바로 GitHub 릴리스 업로드
//   원격 빌드(빌드 에이전트) → 산출물 회수 후 바로 업로드
//   ci → GitHub Actions 워크플로 실행
// 사용: node misc/scripts/release.mjs <kind> <via> [scons 인자...]
//   kind: editor | web-template | dotnet-web
//   via:  local | ci | <에이전트 호스트>
//   예) node misc/scripts/release.mjs editor b1-w01 platform=linuxbsd target=editor
//       node misc/scripts/release.mjs web-template local platform=web target=template_release threads=no
//       node misc/scripts/release.mjs editor ci
// 태그: <kind>-<Godot 버전>-<ENHANCED_VERSION> (예: editor-4.7.2-0.1.1)
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const [kind, via, ...sconsArgs] = process.argv.slice(2);
const workflows = { editor: "enhanced_editor_release.yml", "web-template": "enhanced_web_template.yml", "dotnet-web": "enhanced_dotnet_release.yml" };
if (!workflows[kind] || !via || (via !== "ci" && sconsArgs.length === 0)) {
	console.error("사용: node misc/scripts/release.mjs <editor|web-template|dotnet-web> <local|ci|호스트> [scons 인자...]");
	process.exit(2);
}
const run = (cmd, args, opts = {}) => {
	const r = spawnSync(cmd, args, { cwd: root, stdio: "inherit", shell: process.platform === "win32" && cmd === "scons", ...opts });
	if (r.status !== 0) { console.error(`[release] ✘ ${cmd} ${args.join(" ")}`); process.exit(r.status ?? 1); }
};

// CI 경로
if (via === "ci") {
	run("gh", ["workflow", "run", workflows[kind], "--ref", "main"]);
	console.log(`[release] ✔ CI 실행: ${workflows[kind]} (gh run list --workflow ${workflows[kind]})`);
	process.exit(0);
}

// 버전·태그
const ver = readFileSync(join(root, "version.py"), "utf8");
const pick = (k) => ver.match(new RegExp(`^${k}\\s*=\\s*(\\d+)`, "m"))[1];
const version = `${pick("major")}.${pick("minor")}.${pick("patch")}-${readFileSync(join(root, "ENHANCED_VERSION"), "utf8").trim()}`;
const tag = `${kind}-${version}`;
const sha = spawnSync("git", ["rev-parse", "HEAD"], { cwd: root, encoding: "utf8" }).stdout.trim();

// 빌드
let files;
if (via === "local") {
	const stamp = join(root, "bin", ".release_start");
	writeFileSync(stamp, "");
	const started = statSync(stamp).mtimeMs;
	run(process.platform === "win32" ? "python" : "scons", process.platform === "win32" ? ["-m", "SCons", ...sconsArgs] : sconsArgs);
	files = readdirSync(join(root, "bin"))
		.map((f) => join(root, "bin", f))
		.filter((p) => statSync(p).isFile() && statSync(p).mtimeMs > started && /\.(zip|exe|app|x86_64|arm64)$|\.editor\./.test(p) && !/\.(lib|exp|pdb)$/.test(p));
} else {
	run(process.execPath, [join("misc", "scripts", "remote_build.mjs"), via, ...sconsArgs, "--wait"]);
	const dir = join(root, "bin", "remote", via);
	files = readdirSync(dir).map((f) => join(dir, f)).filter((p) => statSync(p).isFile() && statSync(p).mtimeMs > Date.now() - 6 * 3600e3);
}
if (!files.length) { console.error("[release] ✘ 올릴 산출물 없음"); process.exit(1); }

// 업로드 (릴리스 없으면 생성)
const exists = spawnSync("gh", ["release", "view", tag], { cwd: root, stdio: "ignore" }).status === 0;
if (!exists) run("gh", ["release", "create", tag, "--target", sha, "--title", `${kind} ${version} (godot-enhanced)`, "--notes", `godot-enhanced ${version} — ${kind}. Built ${via === "local" ? "locally" : `on ${via}`} from ${sha.slice(0, 10)}.`]);
run("gh", ["release", "upload", tag, ...files, "--clobber"]);
console.log(`[release] ✔ ${tag} ← ${files.length}개 (${via})\n  ${files.map((f) => f.slice(root.length + 1)).join("\n  ")}`);
