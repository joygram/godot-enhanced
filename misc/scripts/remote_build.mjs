// 원격 빌드 신호: 이 PC의 현재 커밋을 빌드 에이전트(build_agent.mjs)로 보내 빌드 → 산출물 회수.
// SSH 접속 없음. 푸시 전 커밋은 그것만 묶어(git bundle) 보냄, 나머지는 에이전트가 origin 에서 받음.
// 사용: node misc/scripts/remote_build.mjs <host> <scons 인자...>
//       node misc/scripts/remote_build.mjs <host> --resume <job>   (연결이 끊긴 빌드의 결과 받기)
//   예) node misc/scripts/remote_build.mjs 100.94.13.67 platform=macos target=editor arch=arm64
// 환경: BUILD_AGENT_TOKEN (필수), BUILD_AGENT_PORT (기본 8790)
// 산출물: bin/remote/<host>/
import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const [host, ...rest] = process.argv.slice(2);
const token = process.env.BUILD_AGENT_TOKEN;
if (!host || rest.length === 0 || !token) {
	console.error("사용: BUILD_AGENT_TOKEN=<토큰> node misc/scripts/remote_build.mjs <host> <scons 인자...> | --resume <job>");
	process.exit(2);
}
const base = `http://${host}:${process.env.BUILD_AGENT_PORT || 8790}`;
const auth = { Authorization: `Bearer ${token}` };
const git = (...args) => spawnSync("git", args, { cwd: root, encoding: "utf8" });
const sleep = (ms) => new Promise((done) => setTimeout(done, ms));

async function download(result) {
	if (result.code !== 0) {
		const log = await (await fetch(`${base}/log/${result.job}`, { headers: auth })).text();
		console.error(log.split("\n").slice(-30).join("\n"));
		console.error(`[remote-build] ✘ 빌드 실패 (${result.code}) job ${result.job}`);
		process.exit(1);
	}
	const local = join(root, "bin", "remote", host);
	mkdirSync(local, { recursive: true });
	for (const f of result.files) {
		const r = await fetch(`${base}/files/${result.job}/${encodeURIComponent(f)}`, { headers: auth });
		writeFileSync(join(local, f), Buffer.from(await r.arrayBuffer()));
	}
	console.log(`[remote-build] ✔ ${result.files.length}개 → bin/remote/${host}/\n  ${result.files.join("\n  ")}`);
}

// 끊긴 빌드 이어 받기
if (rest[0] === "--resume") {
	const job = rest[1];
	for (;;) {
		const r = await fetch(`${base}/result/${job}`, { headers: auth });
		if (r.status === 200) { await download(await r.json()); process.exit(0); }
		if (r.status !== 202) { console.error(`[remote-build] ✘ job ${job} 없음 (${r.status})`); process.exit(1); }
		await sleep(15000);
	}
}

// 푸시 전 커밋만 묶음
const sha = git("rev-parse", "HEAD").stdout.trim();
git("fetch", "-q", "origin");
const pushed = git("merge-base", "--is-ancestor", "HEAD", "origin/main").status === 0;
let body = Buffer.alloc(0);
if (!pushed) {
	const bundle = join(tmpdir(), `godot-enhanced-${process.pid}.bundle`);
	const b = spawnSync("git", ["bundle", "create", bundle, "origin/main..HEAD"], { cwd: root, stdio: ["ignore", "ignore", "inherit"] });
	if (b.status !== 0) process.exit(1);
	body = readFileSync(bundle);
	rmSync(bundle);
}
const sconsArgs = rest;
console.log(`[remote-build] ${host} ← ${sha.slice(0, 10)} (${pushed ? "푸시됨" : `미푸시 묶음 ${(body.length / 1048576).toFixed(1)}MB`}) : scons ${sconsArgs.join(" ")}`);
const res = await fetch(`${base}/build?sha=${sha}&args=${encodeURIComponent(sconsArgs.join(" "))}`, { method: "POST", headers: auth, body });
if (!res.ok) { console.error(`[remote-build] ✘ ${res.status} ${await res.text()}`); process.exit(1); }

// 로그 스트림 → 끝줄 @@FILES. 끊기면 --resume 안내
let tail = "";
let job = "";
const decoder = new TextDecoder();
try {
	for await (const chunk of res.body) {
		const text = decoder.decode(chunk, { stream: true });
		tail = (tail + text).slice(-4000);
		job ||= tail.match(/\[agent\] job (\d+)/)?.[1] ?? "";
		process.stdout.write(text.replace(/\n@@FILES .*\n?$/s, ""));
	}
} catch { /* 연결 끊김 */ }
const done = tail.match(/@@FILES (\{.*\})/s);
if (!done) {
	console.error(`\n[remote-build] 연결 끊김 — 빌드는 계속됨. 결과 받기: node misc/scripts/remote_build.mjs ${host} --resume ${job}`);
	process.exit(3);
}
await download(JSON.parse(done[1]));
