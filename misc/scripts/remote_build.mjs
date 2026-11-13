// 원격 빌드 신호: 이 PC의 현재 커밋을 빌드 에이전트(build_agent.mjs)로 보내 빌드 → 산출물 회수.
// SSH 접속 없음. 푸시 전 커밋은 그것만 묶어(git bundle) 보냄, 나머지는 에이전트가 origin 에서 받음.
// 사용: node misc/scripts/remote_build.mjs <host> <scons 인자...>
//       node misc/scripts/remote_build.mjs <host> --resume <job>   (연결이 끊긴 빌드의 결과 받기)
//   예) node misc/scripts/remote_build.mjs 100.94.13.67 platform=macos target=editor arch=arm64
// 토큰: ~/.config/godot-enhanced/agents.json {"<host>": "<토큰>"}, 없으면 BUILD_AGENT_TOKEN. 포트: BUILD_AGENT_PORT (기본 8790)
// 산출물: bin/remote/<host>/
import { spawnSync } from "node:child_process";
import { appendFileSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { homedir, tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const [host, ...rest] = process.argv.slice(2);
// 토큰: ~/.config/godot-enhanced/agents.json {"<host>": "<토큰>"} → 없으면 BUILD_AGENT_TOKEN
const agentsFile = join(homedir(), ".config", "godot-enhanced", "agents.json");
const agents = existsSync(agentsFile) ? JSON.parse(readFileSync(agentsFile, "utf8")) : {};
const token = agents[host] || process.env.BUILD_AGENT_TOKEN;
if (!host || rest.length === 0 || !token) {
	// 예) ... b1-w01 platform=linuxbsd target=editor --test smoke-editor --release editor
	console.error("사용: BUILD_AGENT_TOKEN=<토큰> node misc/scripts/remote_build.mjs <host> <scons 인자...> | --resume <job>");
	process.exit(2);
}
const base = `http://${host}:${process.env.BUILD_AGENT_PORT || 8790}`;
const auth = { Authorization: `Bearer ${token}` };
const git = (...args) => spawnSync("git", args, { cwd: root, encoding: "utf8" });
const sleep = (ms) => new Promise((done) => setTimeout(done, ms));

// 이 PC 로그 파일 경로
function localLog(job) {
	const dir = join(root, "bin", "remote", host);
	mkdirSync(dir, { recursive: true });
	return join(dir, `job-${job}.log`);
}

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
	if (result.checks && Object.keys(result.checks).length) console.log(`[remote-build] 검사: ${Object.entries(result.checks).map(([k, v]) => `${k}=${v}`).join(", ")}`);
	if (result.release) console.log(`[remote-build] 릴리스 업로드: ${result.release}`);
}

// 상태·취소
if (rest[0] === "--status" || rest[0] === "--cancel") {
	const r = await fetch(`${base}/${rest[0].slice(2)}`, { method: rest[0] === "--cancel" ? "POST" : "GET", headers: auth });
	console.log(`[remote-build] ${host}: ${await r.text()}`);
	process.exit(0);
}

// 진행 로그 따라 보기: 원격 로그를 bin/remote/<host>/job-<번호>.log 로 받으며 화면에도 출력, 끝나면 결과 수신
if (rest[0] === "--follow") {
	const job = rest[1] || (await (await fetch(`${base}/status`, { headers: auth })).text()).split(" ")[1];
	if (!job) { console.error(`[remote-build] ${host}: 진행 중 작업 없음`); process.exit(1); }
	const file = localLog(job);
	console.log(`[remote-build] ${host} job ${job} → ${file}`);
	let shown = 0;
	for (;;) {
		const text = await (await fetch(`${base}/log/${job}`, { headers: auth })).text();
		if (text.length > shown) { process.stdout.write(text.slice(shown)); shown = text.length; writeFileSync(file, text); }
		const r = await fetch(`${base}/result/${job}`, { headers: auth });
		if (r.status === 200) { await download(await r.json()); process.exit(0); }
		if (r.status !== 202) { console.error(`[remote-build] ✘ job ${job} 없음 (${r.status})`); process.exit(1); }
		await sleep(5000);
	}
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
// --test a,b (misc/scripts/agent_tests/<이름>.sh), --release <kind> (검사 통과 시 에이전트가 GitHub 릴리스 업로드)
const opt = (name) => { const i = rest.indexOf(name); if (i < 0) return ""; const v = rest[i + 1] ?? ""; rest.splice(i, 2); return v; };
const waitAll = rest.includes("--wait") && (rest.splice(rest.indexOf("--wait"), 1), true);
const test = opt("--test");
const release = opt("--release");
const sconsArgs = rest;
console.log(`[remote-build] ${host} ← ${sha.slice(0, 10)} (${pushed ? "푸시됨" : `미푸시 묶음 ${(body.length / 1048576).toFixed(1)}MB`}) : scons ${sconsArgs.join(" ") || "(없음)"}${test ? ` → 검사 ${test}` : ""}${release ? ` → 릴리스 ${release}` : ""}`);
const q = new URLSearchParams({ sha, args: sconsArgs.join(" "), test, release });
// --env KEY=VAL (검사에 넘김, 에이전트 허용 목록: WEB_URL, BROWSER). 여러 번 가능
for (let i; (i = sconsArgs.indexOf("--env")) >= 0;) { q.append("env", sconsArgs[i + 1] ?? ""); sconsArgs.splice(i, 2); }
q.set("args", sconsArgs.join(" "));
const res = await fetch(`${base}/build?${q}`, { method: "POST", headers: auth, body });
if (!res.ok) { console.error(`[remote-build] ✘ ${res.status} ${await res.text()}`); process.exit(1); }

// 로그 스트림 → 끝줄 @@FILES. 끊기면 --resume 안내
let tail = "";
let job = "";
let logFile = "";
const decoder = new TextDecoder();
try {
	for await (const chunk of res.body) {
		const text = decoder.decode(chunk, { stream: true }).replace(/​\n/g, "");
		tail = (tail + text).slice(-4000);
		if (!job && (job = tail.match(/\[agent\] job (\d+)/)?.[1] ?? "")) {
			logFile = localLog(job);
			console.log(`[remote-build] 로그 파일: ${logFile}`);
			writeFileSync(logFile, "");
		}
		if (logFile) appendFileSync(logFile, text);
		// 기본 = 작업 번호만 받고 바로 반환 (에이전트는 계속). --wait 면 끝까지 따라감
		if (job && !waitAll) {
			console.log(`[remote-build] 보냄: ${host} job ${job} — 진행: --follow ${job} | 상태: --status | 취소: --cancel`);
			process.exit(0);
		}
		process.stdout.write(text.replace(/\n@@FILES .*\n?$/s, ""));
	}
} catch { /* 연결 끊김 */ }
const done = tail.match(/@@FILES (\{.*\})/s);
if (!done) {
	console.error(`\n[remote-build] 연결 끊김 — 빌드는 계속될 수 있음. 이어 보기: node misc/scripts/remote_build.mjs ${host} --follow ${job}`);
	process.exit(3);
}
await download(JSON.parse(done[1]));
