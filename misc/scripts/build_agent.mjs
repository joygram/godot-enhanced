// 빌드 에이전트: 원격 머신(macOS·Linux)에서 상주. 신호(HTTP)를 받으면 받은 커밋으로 SCons 빌드.
// 실행: BUILD_AGENT_TOKEN=<토큰> node misc/scripts/build_agent.mjs
// 환경: BUILD_AGENT_TOKEN (필수), BUILD_AGENT_PORT (기본 8790), BUILD_AGENT_HOST (기본 0.0.0.0, Tailscale IP 권장),
//       BUILD_AGENT_PRE (빌드 전 셸, 예: "source ~/emsdk/emsdk_env.sh")
// API: POST /build?sha=<커밋>&args=<scons 인자> (본문 = 푸시 전 커밋 git bundle, 없으면 빈 본문)
//        → 로그 스트림, 끝줄 "@@FILES <json>"
//      GET /result/<job>, /log/<job>, /files/<job>/<파일>, /status
import { spawn, spawnSync } from "node:child_process";
import { createReadStream, createWriteStream, existsSync, mkdirSync, readdirSync, readFileSync, statSync, copyFileSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { dirname, join, resolve } from "node:path";
import { cpus, freemem, homedir, hostname, loadavg, totalmem, uptime } from "node:os";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const token = process.env.BUILD_AGENT_TOKEN;
if (!token) { console.error("BUILD_AGENT_TOKEN 필요"); process.exit(2); }
const port = Number(process.env.BUILD_AGENT_PORT || 8790);
const host = process.env.BUILD_AGENT_HOST || "0.0.0.0";
const pre = process.env.BUILD_AGENT_PRE ? `${process.env.BUILD_AGENT_PRE} && ` : "";
const out = join(root, "bin", "agent-jobs");
const self = fileURLToPath(import.meta.url);
const selfSource = readFileSync(self, "utf8");
let busy = false;
let current = null; // { job, child }

// 단계별 시간 제한 (초): 빌드 BUILD_AGENT_BUILD_TIMEOUT 기본 7200, 검사 BUILD_AGENT_CHECK_TIMEOUT 기본 1800
const sh = (script, log, seconds = 7200) => new Promise((done) => {
	const child = spawn("bash", ["-lc", script], { cwd: root, detached: true });
	if (current) current.child = child;
	const timer = setTimeout(() => { log.write(`\n[agent] ✘ 시간 초과 ${seconds}s → 중단\n`); try { process.kill(-child.pid, "SIGKILL"); } catch {} }, seconds * 1000);
	child.stdout.on("data", (d) => log.write(d));
	child.stderr.on("data", (d) => log.write(d));
	child.on("close", (code) => { clearTimeout(timer); done(code ?? 124); });
});

createServer(async (req, res) => {
	const url = new URL(req.url, "http://x");
	if (req.headers.authorization !== `Bearer ${token}`) { res.writeHead(401).end(); return; }
	if (url.pathname === "/status") { res.end(busy ? `busy ${current?.job ?? ""}` : "idle"); return; }
	// 대시보드: 머신 정보, 최근 작업 목록
	if (url.pathname === "/info") {
		const head = spawnSync("git", ["rev-parse", "--short=10", "HEAD"], { cwd: root, encoding: "utf8" }).stdout.trim();
		res.setHeader("Content-Type", "application/json");
		res.end(JSON.stringify({ host: hostname(), platform: process.platform, arch: process.arch, cpus: cpus().length, load: loadavg(),
			mem_total_gb: Math.round(totalmem() / 1e9), mem_free_gb: Math.round(freemem() / 1e9 * 10) / 10, uptime_h: Math.round(uptime() / 360) / 10,
			busy, job: current?.job ?? null, head, node: process.version }));
		return;
	}
	if (url.pathname === "/jobs") {
		const list = existsSync(out) ? readdirSync(out).filter((d) => /^\d+$/.test(d)).sort().reverse().slice(0, Number(url.searchParams.get("n") || 15)) : [];
		const jobsOut = list.map((j) => {
			const m = join(out, j, "meta.json"), r = join(out, j, "result.json");
			if (existsSync(m)) return JSON.parse(readFileSync(m, "utf8"));
			const rr = existsSync(r) ? JSON.parse(readFileSync(r, "utf8")) : null;
			return { job: j, status: rr ? (rr.code === 0 ? "success" : "fail") : "unknown", started: Number(j), steps: [], checks: rr?.checks, files: rr?.files };
		});
		res.setHeader("Content-Type", "application/json");
		res.end(JSON.stringify(jobsOut));
		return;
	}
	// 진행 중 작업 취소
	if (req.method === "POST" && url.pathname === "/cancel") {
		if (current?.child) { try { process.kill(-current.child.pid, "SIGKILL"); } catch {} res.end(`cancel ${current.job}`); }
		else res.end("idle");
		return;
	}
	if (req.method === "GET" && url.pathname.startsWith("/files/")) {
		const file = resolve(out, decodeURIComponent(url.pathname.slice(7)));
		if (!file.startsWith(out) || !existsSync(file)) { res.writeHead(404).end(); return; }
		res.writeHead(200, { "Content-Length": statSync(file).size });
		createReadStream(file).pipe(res);
		return;
	}
	// 끊긴 뒤 다시 받기: GET /result/<job> → 결과 JSON (진행 중이면 202), GET /log/<job> → 로그
	if (req.method === "GET" && /^\/(result|log)\/\d+$/.test(url.pathname)) {
		const [, kind, job] = url.pathname.split("/");
		const file = join(out, job, kind === "result" ? "result.json" : "log.txt");
		if (!existsSync(file)) { res.writeHead(kind === "result" && existsSync(join(out, job)) ? 202 : 404).end(); return; }
		createReadStream(file).pipe(res);
		return;
	}
	if (req.method !== "POST" || url.pathname !== "/build") { res.writeHead(404).end(); return; }
	if (busy) { res.writeHead(409).end("busy"); return; }
	busy = true;
	const job = `${Date.now()}`;
	current = { job, child: null };
	const dir = join(out, job);
	mkdirSync(dir, { recursive: true });
	res.on("error", () => {});
	res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
	// 로그 = 파일 + (연결이 살아 있으면) 응답
	const file = createWriteStream(join(dir, "log.txt"));
	const log = { write: (d) => { file.write(d); if (!res.destroyed) res.write(d); } };
	// 조용한 단계(다운로드 등)에도 연결 유지: 30초마다 빈 줄 신호
	const beat = setInterval(() => { if (!res.destroyed) res.write("​\n"); }, 30000);
	res.on("close", () => clearInterval(beat));
	let result;
	try {
		const bundle = join(dir, "src.bundle");
		await new Promise((done) => req.pipe(createWriteStream(bundle)).on("finish", done));
		const sha = (url.searchParams.get("sha") || "").replace(/[^0-9a-f]/g, "");
		const args = (url.searchParams.get("args") || "").replace(/[^\w=.,+\- ]/g, "");
		// 검사 = 저장소의 misc/scripts/agent_tests/<이름>.sh 만 (목록 밖 명령 실행 안 함)
		const tests = (url.searchParams.get("test") || "").split(",").map((t) => t.replace(/[^a-z0-9-]/g, "")).filter(Boolean);
		const release = (url.searchParams.get("release") || "").replace(/[^a-z-]/g, "");
		const jobs = "$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu)";
		log.write(`[agent] job ${job}: ${sha.slice(0, 10)} scons ${args || "(없음)"} test=${tests.join(",") || "-"} release=${release || "-"}\n`);
		// 원격 이력은 origin 에서, 푸시 전 커밋만 묶음(bundle)으로 받음
		const fetchBundle = statSync(bundle).size > 0 ? `git fetch -q "${bundle}" HEAD:refs/heads/agent-build -f && ` : "";
		// 웹 빌드: ~/emsdk 있으면 자동 활성화
		// (macOS 기본 python 3.9 → brew python@3.12 있으면 EMSDK_PYTHON 지정)
		const emsdk = /platform=web/.test(args) && existsSync(join(homedir(), "emsdk", "emsdk_env.sh"))
			? `{ command -v brew >/dev/null && [ -x "$(brew --prefix python@3.12 2>/dev/null)/bin/python3.12" ] && export EMSDK_PYTHON="$(brew --prefix python@3.12)/bin/python3.12"; true; } && source ~/emsdk/emsdk_env.sh >/dev/null 2>&1 && `
			: "";
		// 단계 기록 (대시보드용): meta.json = { 작업 정보, steps: [{ name, status, start, end }] }
		const meta = { job, sha, args, tests, release, status: "running", started: Date.now(), ended: null,
			steps: [{ name: "소스" }, ...(args ? [{ name: "빌드" }] : []), ...tests.map((t) => ({ name: `검사 ${t}` })), ...(release ? [{ name: `릴리스 ${release}` }] : [])]
				.map((s) => ({ ...s, status: "pending", start: null, end: null })) };
		const saveMeta = () => writeFileSync(join(dir, "meta.json"), JSON.stringify(meta));
		const step = async (name, run) => {
			const s = meta.steps.find((x) => x.name === name);
			s.status = "running"; s.start = Date.now(); meta.current = name; saveMeta();
			const c = await run();
			s.status = c === 0 ? "pass" : "fail"; s.end = Date.now(); saveMeta();
			return c;
		};
		saveMeta();
		let code = await step("소스", () => sh(`git fetch -q origin && ${fetchBundle}git checkout -q -f ${sha} && touch "${dir}/.start"`, log, 600));
		if (code === 0 && args) code = await step("빌드", () => sh(`${pre}${emsdk}scons ${args} -j${jobs}`, log, Number(process.env.BUILD_AGENT_BUILD_TIMEOUT || 7200)));
		const files = code === 0 && args
			? readdirSync(join(root, "bin")).filter((f) => { const p = join(root, "bin", f); return statSync(p).isFile() && statSync(p).mtimeMs > statSync(join(dir, ".start")).mtimeMs; })
			: [];
		for (const f of files) copyFileSync(join(root, "bin", f), join(dir, f));
		// 빌드 → 검사 → 통과 시 릴리스 업로드
		const checks = {};
		for (const t of tests) {
			if (code !== 0) break;
			if (!existsSync(join(root, "misc", "scripts", "agent_tests", `${t}.sh`))) { log.write(`[agent] ✘ 검사 없음: ${t}\n`); code = 2; break; }
			log.write(`\n[agent] ── 검사 ${t}\n`);
			const c = await step(`검사 ${t}`, () => sh(`${pre}JOB_DIR="${dir}" bash misc/scripts/agent_tests/${t}.sh`, log, Number(process.env.BUILD_AGENT_CHECK_TIMEOUT || 1800)));
			checks[t] = c === 0 ? "pass" : "fail";
			if (c !== 0) code = c;
		}
		for (const f of readdirSync(dir)) if (!files.includes(f) && /\.(png|json|txt)$/.test(f) && !["result.json", "log.txt", "meta.json"].includes(f)) files.push(f);
		if (code === 0 && release) {
			log.write(`\n[agent] ── 릴리스 ${release}\n`);
			code = await step(`릴리스 ${release}`, () => sh(`JOB_DIR="${dir}" bash misc/scripts/agent_release.sh ${release}`, log));
		}
		for (const s of meta.steps) if (s.status === "pending") s.status = "skip";
		meta.status = code === 0 ? "success" : code === 137 || code === 124 ? "cancelled" : "fail";
		meta.ended = Date.now(); meta.current = null; meta.checks = checks; meta.files = files; saveMeta();
		result = { code, job, files, checks, release: release && code === 0 ? release : null };
	} catch (e) {
		result = { code: 1, job, files: [], error: String(e) };
	} finally {
		busy = false;
		current = null;
		clearInterval(beat);
		writeFileSync(join(dir, "result.json"), JSON.stringify(result));
		file.end();
		if (!res.destroyed) res.end(`\n@@FILES ${JSON.stringify(result)}\n`);
		// 작업 중 체크아웃으로 에이전트 코드가 바뀌었으면 종료 → 서비스(launchd/systemd)가 새 코드로 재시작
		if (readFileSync(self, "utf8") !== selfSource || existsSync(join(dir, ".restart"))) { console.log("[agent] 코드·도구 갱신 → 재시작"); setTimeout(() => process.exit(0), 1000); }
	}
}).listen(port, host, () => console.log(`[agent] ${host}:${port} 대기 (소스 ${root})`));
