// 원격 빌드 신호: 이 PC의 현재 커밋을 빌드 에이전트(build_agent.mjs)로 보내 빌드 → 산출물 회수.
// SSH 접속 없음. GitHub 거치지 않음 (푸시 전 커밋도 가능).
// 사용: node misc/scripts/remote_build.mjs <host> <scons 인자...>
//   예) node misc/scripts/remote_build.mjs joy-mac platform=macos target=editor arch=arm64
// 환경: BUILD_AGENT_TOKEN (필수), BUILD_AGENT_PORT (기본 8790)
// 산출물: bin/remote/<host>/
import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const [host, ...sconsArgs] = process.argv.slice(2);
const token = process.env.BUILD_AGENT_TOKEN;
if (!host || sconsArgs.length === 0 || !token) {
	console.error("사용: BUILD_AGENT_TOKEN=<토큰> node misc/scripts/remote_build.mjs <host> <scons 인자...>");
	process.exit(2);
}
const base = `http://${host}:${process.env.BUILD_AGENT_PORT || 8790}`;
const auth = { Authorization: `Bearer ${token}` };

// 현재 커밋 묶음 (git bundle)
const bundle = join(tmpdir(), `godot-enhanced-${process.pid}.bundle`);
const b = spawnSync("git", ["bundle", "create", bundle, "HEAD"], { cwd: root, stdio: ["ignore", "ignore", "inherit"] });
if (b.status !== 0) process.exit(1);
const body = readFileSync(bundle);
rmSync(bundle);

const sha = spawnSync("git", ["rev-parse", "--short=10", "HEAD"], { cwd: root, encoding: "utf8" }).stdout.trim();
console.log(`[remote-build] ${host} ← ${sha} (${(body.length / 1048576).toFixed(1)}MB) : scons ${sconsArgs.join(" ")}`);
const res = await fetch(`${base}/build?args=${encodeURIComponent(sconsArgs.join(" "))}`, { method: "POST", headers: auth, body });
if (!res.ok) { console.error(`[remote-build] ✘ ${res.status} ${await res.text()}`); process.exit(1); }

// 로그 스트림 → 끝줄 @@FILES
let tail = "";
const decoder = new TextDecoder();
for await (const chunk of res.body) {
	const text = decoder.decode(chunk, { stream: true });
	tail = (tail + text).slice(-4000);
	process.stdout.write(text.replace(/\n@@FILES .*\n?$/s, ""));
}
const result = JSON.parse(tail.match(/@@FILES (\{.*\})/s)[1]);
if (result.code !== 0) { console.error(`[remote-build] ✘ 빌드 실패 (${result.code})`); process.exit(1); }

const local = join(root, "bin", "remote", host);
mkdirSync(local, { recursive: true });
for (const f of result.files) {
	const r = await fetch(`${base}/files/${result.job}/${encodeURIComponent(f)}`, { headers: auth });
	writeFileSync(join(local, f), Buffer.from(await r.arrayBuffer()));
}
console.log(`[remote-build] ✔ ${result.files.length}개 → bin/remote/${host}/\n  ${result.files.join("\n  ")}`);
