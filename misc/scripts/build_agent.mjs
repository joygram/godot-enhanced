// 빌드 에이전트: 원격 머신(macOS·Linux)에서 상주. 신호(HTTP)를 받으면 받은 커밋으로 SCons 빌드.
// 실행: BUILD_AGENT_TOKEN=<토큰> node misc/scripts/build_agent.mjs
// 환경: BUILD_AGENT_TOKEN (필수), BUILD_AGENT_PORT (기본 8790), BUILD_AGENT_HOST (기본 0.0.0.0, Tailscale IP 권장),
//       BUILD_AGENT_PRE (빌드 전 셸, 예: "source ~/emsdk/emsdk_env.sh")
// API: POST /build?args=<scons 인자> (본문 = git bundle) → 로그 스트림, 끝줄 "@@FILES <json>"
//      GET /files/<job>/<파일> → 산출물, GET /status → idle|busy
import { spawn } from "node:child_process";
import { createReadStream, createWriteStream, existsSync, mkdirSync, readdirSync, statSync, copyFileSync } from "node:fs";
import { createServer } from "node:http";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const token = process.env.BUILD_AGENT_TOKEN;
if (!token) { console.error("BUILD_AGENT_TOKEN 필요"); process.exit(2); }
const port = Number(process.env.BUILD_AGENT_PORT || 8790);
const host = process.env.BUILD_AGENT_HOST || "0.0.0.0";
const pre = process.env.BUILD_AGENT_PRE ? `${process.env.BUILD_AGENT_PRE} && ` : "";
const out = join(root, "bin", "agent-jobs");
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
	if (req.method !== "POST" || url.pathname !== "/build") { res.writeHead(404).end(); return; }
	if (busy) { res.writeHead(409).end("busy"); return; }
	busy = true;
	const job = `${Date.now()}`;
	const dir = join(out, job);
	mkdirSync(dir, { recursive: true });
	res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" });
	try {
		const bundle = join(dir, "src.bundle");
		await new Promise((done) => req.pipe(createWriteStream(bundle)).on("finish", done));
		const args = (url.searchParams.get("args") || "").replace(/[^\w=.,+\- ]/g, "");
		const jobs = "$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu)";
		res.write(`[agent] job ${job}: scons ${args}\n`);
		const code = await sh(
			`git fetch -q "${bundle}" HEAD:refs/heads/agent-build -f && git checkout -q -f agent-build && touch "${dir}/.start" && ${pre}scons ${args} -j${jobs}`,
			res,
		);
		const files = code === 0
			? readdirSync(join(root, "bin")).filter((f) => { const p = join(root, "bin", f); return statSync(p).isFile() && statSync(p).mtimeMs > statSync(join(dir, ".start")).mtimeMs; })
			: [];
		for (const f of files) copyFileSync(join(root, "bin", f), join(dir, f));
		res.end(`\n@@FILES ${JSON.stringify({ code, job, files })}\n`);
	} catch (e) {
		res.end(`\n@@FILES ${JSON.stringify({ code: 1, job, files: [], error: String(e) })}\n`);
	} finally { busy = false; }
}).listen(port, host, () => console.log(`[agent] ${host}:${port} 대기 (소스 ${root})`));
