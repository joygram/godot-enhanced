// 빌드 에이전트: 원격 머신(macOS·Linux)에서 상주. 신호(HTTP)를 받으면 받은 커밋으로 SCons 빌드.
// 실행: BUILD_AGENT_TOKEN=<토큰> node misc/scripts/build_agent.mjs
// 환경: BUILD_AGENT_TOKEN (필수), BUILD_AGENT_PORT (기본 8790), BUILD_AGENT_HOST (기본 0.0.0.0, Tailscale IP 권장),
//       BUILD_AGENT_PRE (빌드 전 셸, 예: "source ~/emsdk/emsdk_env.sh")
// API: POST /build?sha=<커밋>&args=<scons 인자> (본문 = 푸시 전 커밋 git bundle, 없으면 빈 본문)
//        → 로그 스트림, 끝줄 "@@FILES <json>"
//      GET /result/<job>, /log/<job>, /files/<job>/<파일>, /status
import { spawn } from "node:child_process";
import { createReadStream, createWriteStream, existsSync, mkdirSync, readdirSync, readFileSync, statSync, copyFileSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { dirname, join, resolve } from "node:path";
import { homedir } from "node:os";
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

const sh = (script, log) => new Promise((done) => {
	const child = spawn("bash", ["-lc", script], { cwd: root });
	child.stdout.on("data", (d) => log.write(d));
	child.stderr.on("data", (d) => log.write(d));
	child.on("close", (code) => done(code));
});

createServer(async (req, res) => {
	const url = new URL(req.url, "http://x");
	if (req.headers.authorization !== `Bearer ${token}`) { res.writeHead(401).end(); return; }
	if (url.pathname === "/status") { res.end(busy ? "busy" : "idle"); return; }
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
	const dir = join(out, job);
	mkdirSync(dir, { recursive: true });
	res.on("error", () => {});
	res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
	// 로그 = 파일 + (연결이 살아 있으면) 응답
	const file = createWriteStream(join(dir, "log.txt"));
	const log = { write: (d) => { file.write(d); if (!res.destroyed) res.write(d); } };
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
		const build = args ? ` && ${pre}${emsdk}scons ${args} -j${jobs}` : "";
		let code = await sh(`git fetch -q origin && ${fetchBundle}git checkout -q -f ${sha} && touch "${dir}/.start"${build}`, log);
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
			const c = await sh(`${pre}JOB_DIR="${dir}" bash misc/scripts/agent_tests/${t}.sh`, log);
			checks[t] = c === 0 ? "pass" : "fail";
			if (c !== 0) code = c;
		}
		for (const f of readdirSync(dir)) if (!files.includes(f) && /\.(png|json|txt)$/.test(f) && !["result.json", "log.txt"].includes(f)) files.push(f);
		if (code === 0 && release) {
			log.write(`\n[agent] ── 릴리스 ${release}\n`);
			code = await sh(`JOB_DIR="${dir}" bash misc/scripts/agent_release.sh ${release}`, log);
		}
		result = { code, job, files, checks, release: release && code === 0 ? release : null };
	} catch (e) {
		result = { code: 1, job, files: [], error: String(e) };
	} finally {
		busy = false;
		writeFileSync(join(dir, "result.json"), JSON.stringify(result));
		file.end();
		if (!res.destroyed) res.end(`\n@@FILES ${JSON.stringify(result)}\n`);
		// 작업 중 체크아웃으로 에이전트 코드가 바뀌었으면 종료 → 서비스(launchd/systemd)가 새 코드로 재시작
		if (readFileSync(self, "utf8") !== selfSource) { console.log("[agent] 코드 갱신 → 재시작"); setTimeout(() => process.exit(0), 1000); }
	}
}).listen(port, host, () => console.log(`[agent] ${host}:${port} 대기 (소스 ${root})`));
