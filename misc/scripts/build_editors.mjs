// 편집기 전부 로컬·빌드 에이전트로 빌드 → 릴리스 editor-<Godot>-<ENHANCED_VERSION> 업로드 (CI 없이)
// 사용: node misc/scripts/build_editors.mjs [대상...]   (기본 = 전부)
//   대상: windows-x86_64 · windows-arm64 · linux-x86_64 · linux-arm64 · mac-universal
// 에이전트 = 별칭 linux·mac. 주소·토큰은 ~/.config/godot-enhanced/agents.json 에만 (저장소에 내부망 주소 금지)
// 자산 이름 = 설치기·CI 와 같음: godot-<버전>-enhanced.<platform>.editor.<arch>.zip
import { spawnSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, rmSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const node = process.execPath;
const enhanced = readFileSync(join(root, "ENHANCED_VERSION"), "utf8").trim();
const flags = ["target=editor", "accesskit=no", "debug_symbols=no"];
const run = (args) => spawnSync(node, args, { cwd: root, stdio: "inherit" }).status === 0;
const release = (via, ...args) => run([join("misc", "scripts", "release.mjs"), "editor", via, ...args]);
const remote = (host, ...args) => run([join("misc", "scripts", "remote_build.mjs"), host, ...args, "--wait"]);

// 로컬 Windows: 버전 헤더가 바뀌어도 다시 컴파일 안 된 오브젝트가 이전 버전을 박는 일 → 바이너리 버전 확인, 어긋나면 그 오브젝트 지우고 재빌드
function windows(arch) {
	const exe = join(root, "bin", `godot.windows.editor.${arch}.exe`);
	const args = ["platform=windows", `arch=${arch}`, "d3d12=no", ...flags];
	for (let attempt = 0; attempt < 2; attempt++) {
		const stale = existsSync(exe) && !readFileSync(exe).includes(`enhanced-${enhanced}`);
		if (stale || attempt > 0) {
			const objs = join(root, "bin", "obj");
			const walk = (d) => readdirSync(d, { withFileTypes: true }).flatMap((e) => e.isDirectory() ? walk(join(d, e.name)) : [join(d, e.name)]);
			for (const f of walk(objs)) {
				if (!f.includes(`.windows.editor.${arch}.`)) continue;
				const b = readFileSync(f);
				if (b.includes("enhanced-") && !b.includes(`enhanced-${enhanced}`)) rmSync(f);
			}
		}
		// 늘 다시 링크 — release.mjs 는 이번 빌드에 새로 생긴 파일만 올림
		for (const f of readdirSync(join(root, "bin"))) if (f.startsWith(`godot.windows.editor.${arch}`)) rmSync(join(root, "bin", f), { force: true });
		if (!release("local", ...args)) return false;
		if (readFileSync(exe).includes(`enhanced-${enhanced}`)) return true;
		console.error(`[build-editors] ${arch} 바이너리 버전이 enhanced-${enhanced} 아님 → 오래된 오브젝트 지우고 다시`);
	}
	return false;
}

const targets = {
	"windows-x86_64": () => windows("x86_64"),
	"windows-arm64": () => windows("arm64"),
	"linux-x86_64": () => release("linux", "platform=linuxbsd", "arch=x86_64", ...flags),
	// x86_64 에이전트에서 크로스 빌드 (에이전트에 g++-aarch64-linux-gnu 필요, platform/linuxbsd/detect.py)
	"linux-arm64": () => release("linux", "platform=linuxbsd", "arch=arm64", ...flags),
	// macOS = arm64·x86_64 빌드 → 에이전트에서 lipo 로 Godot.app universal (agent_tests/macos-universal.sh)
	"mac-universal": () => ["arm64", "x86_64"].every((arch) => remote("mac", "platform=macos", `arch=${arch}`, "vulkan=no", "angle=no", ...flags))
		&& remote("mac", "--test", "macos-universal"),
};

const wanted = process.argv.slice(2).length ? process.argv.slice(2) : Object.keys(targets);
const unknown = wanted.filter((t) => !targets[t]);
if (unknown.length) { console.error(`알 수 없는 대상: ${unknown.join(", ")} (가능: ${Object.keys(targets).join(" · ")})`); process.exit(2); }
const results = wanted.map((t) => { console.log(`\n[build-editors] ── ${t}`); return [t, targets[t]()]; });
console.log("\n[build-editors] 결과");
for (const [t, ok] of results) console.log(`  ${ok ? "✔" : "✘"} ${t}`);
process.exit(results.every(([, ok]) => ok) ? 0 : 1);
