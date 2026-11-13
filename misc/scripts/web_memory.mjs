// 웹 빌드 메모리 측정: 정적 서버(COOP/COEP) + 브라우저 → wasm 힙 표본, 오류 검사, 화면 캡처
// 사용: node misc/scripts/web_memory.mjs <웹 빌드 폴더> [초=30] [결과 json 경로]
// 환경: BROWSER = safari (macOS 기본, 시스템 safaridriver) | chrome (그 외 기본, CDP)
//       CHROME (Chrome 실행 파일), WEB_MEMORY_PORT (기본 8798)
// 출력: { browser, wasm_heap_peak_mb, js_heap_mb, samples, errors, marks } + 같은 이름 .png. 오류 시 종료 코드 1
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, extname, join, resolve } from "node:path";
import { tmpdir } from "node:os";

const web = resolve(process.argv[2] ?? ".");
const seconds = Number(process.argv[3] ?? 30);
const outJson = resolve(process.argv[4] ?? join(web, "web-memory.json"));
const port = Number(process.env.WEB_MEMORY_PORT ?? 8798);
const browserName = process.env.BROWSER || (process.platform === "darwin" ? "safari" : "chrome");
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const MB = (b) => Math.round(b / 1048576 * 10) / 10;
if (!existsSync(join(web, "index.html"))) { console.error(`✘ ${web}/index.html 없음`); process.exit(1); }

// 페이지에 넣는 측정 훅: WebAssembly.Memory 수집 + 콘솔·오류 기록 (모든 브라우저 공통)
const HOOK = `<script>(()=>{if(globalThis.__mems)return;const M=WebAssembly.Memory;globalThis.__mems=[];
WebAssembly.Memory=function(d){const m=new M(d);globalThis.__mems.push(m);return m};WebAssembly.Memory.prototype=M.prototype;
const grab=r=>{const i=r&&(r.instance||r);if(i&&i.exports)for(const v of Object.values(i.exports))if(v instanceof M&&!globalThis.__mems.includes(v))globalThis.__mems.push(v);return r};
for(const k of["instantiate","instantiateStreaming"]){const f=WebAssembly[k];if(f)WebAssembly[k]=(...a)=>f.apply(WebAssembly,a).then(grab)}
const I=WebAssembly.Instance;WebAssembly.Instance=function(m,imp){return grab(new I(m,imp))};WebAssembly.Instance.prototype=I.prototype;
const L=globalThis.__logs=[];for(const k of["log","warn","error"]){const o=console[k].bind(console);console[k]=(...a)=>{L.push(a.join(" "));o(...a)}}
addEventListener("error",e=>L.push("EXC "+(e.message||e.error)));addEventListener("unhandledrejection",e=>L.push("EXC "+e.reason));})();</script>`;
const MIME = { ".html": "text/html", ".js": "text/javascript", ".wasm": "application/wasm" };
const server = createServer((req, res) => {
	const file = join(web, decodeURIComponent(new URL(req.url, "http://x").pathname));
	if (!file.startsWith(web) || !existsSync(file)) { res.writeHead(404).end(); return; }
	let body = readFileSync(file);
	if (file.endsWith("index.html")) body = body.toString().replace("<head>", `<head>${HOOK}`);
	res.writeHead(200, { "Content-Type": MIME[extname(file)] || "application/octet-stream",
		"Cross-Origin-Opener-Policy": "same-origin", "Cross-Origin-Embedder-Policy": "require-corp" });
	res.end(body);
}).listen(port);
const page = `http://127.0.0.1:${port}/index.html`;
const probe = "return {wasm: Math.max(0,...(globalThis.__mems||[]).map(m=>m.buffer.byteLength)), js: performance.memory ? performance.memory.usedJSHeapSize : 0, logs: globalThis.__logs||[]}";

let driver; // { sample(), shot(), close() }
if (browserName === "safari") {
	// 시스템 Safari (WebDriver). 1회 설정: Safari → 설정 → 개발자 → '원격 자동화 허용'
	const wdPort = port + 1;
	// 열려 있는 Safari 와 자동화 창 충돌 방지 → 먼저 종료
	spawn("osascript", ["-e", 'quit app "Safari"']);
	await wait(3000);
	const sd = spawn("safaridriver", ["-p", String(wdPort)]);
	const wd = async (method, path, body) => (await (await fetch(`http://127.0.0.1:${wdPort}${path}`, { method, headers: { "Content-Type": "application/json" }, body: body && JSON.stringify(body) })).json()).value;
	let session;
	for (let i = 0, tries = 0; i < 60 && !session && tries < 3; i++) {
		try {
			const v = await wd("POST", "/session", { capabilities: { alwaysMatch: { browserName: "safari" } } });
			if (v.sessionId) session = v.sessionId;
			else { tries++; console.error(`safaridriver 시도 ${tries}/3: ${v.message ?? JSON.stringify(v)}`); await wait(5000); }
		} catch { await wait(500); }
	}
	if (!session) { console.error("✘ Safari 세션 실패 → Safari 설정 → 개발자 → '원격 자동화 허용' 확인"); sd.kill(); server.close(); process.exit(1); }
	await wd("POST", `/session/${session}/url`, { url: page });
	driver = {
		sample: () => wd("POST", `/session/${session}/execute/sync`, { script: probe, args: [] }),
		shot: async () => Buffer.from(await wd("GET", `/session/${session}/screenshot`), "base64"),
		close: async () => { await wd("DELETE", `/session/${session}`).catch(() => {}); sd.kill(); },
	};
} else {
	// 리눅스: Playwright 가 받은 Chromium (~/.cache/ms-playwright/chromium-*/chrome-linux/chrome)
	const pwDir = join(process.env.HOME || "", ".cache", "ms-playwright");
	const pwChrome = existsSync(pwDir) ? readdirSync(pwDir).filter((d) => d.startsWith("chromium-")).sort().reverse().map((d) => join(pwDir, d, "chrome-linux", "chrome")) : [];
	const chrome = [process.env.CHROME, "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", "/usr/bin/google-chrome",
		"/usr/bin/google-chrome-stable", "/usr/bin/chromium", "/usr/bin/chromium-browser", "C:/Program Files/Google/Chrome/Application/chrome.exe", ...pwChrome]
		.find((p) => p && existsSync(p));
	if (!chrome) { console.error("✘ Chrome 없음 → CHROME 지정"); server.close(); process.exit(1); }
	const browser = spawn(chrome, ["--headless=new", "--no-sandbox", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
		"--enable-precise-memory-info", "--window-size=960,540", `--remote-debugging-port=${port + 1}`, `--user-data-dir=${join(tmpdir(), `web-memory-${process.pid}`)}`, "about:blank"]);
	let ws; let id = 0; const pending = new Map();
	for (let i = 0; i < 60 && !ws; i++) {
		try {
			const target = (await (await fetch(`http://127.0.0.1:${port + 1}/json`)).json()).find((p) => p.type === "page");
			const w = new WebSocket(target.webSocketDebuggerUrl);
			await new Promise((r, j) => { w.addEventListener("open", r); w.addEventListener("error", j); });
			ws = w;
		} catch { await wait(250); }
	}
	if (!ws) { console.error("✘ DevTools 연결 실패"); browser.kill(); server.close(); process.exit(1); }
	ws.addEventListener("message", (m) => { const d = JSON.parse(m.data); if (d.id && pending.has(d.id)) { pending.get(d.id)(d); pending.delete(d.id); } });
	const call = (method, params = {}) => new Promise((r) => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
	await call("Page.enable");
	await call("Page.navigate", { url: page });
	driver = {
		sample: async () => (await call("Runtime.evaluate", { returnByValue: true, expression: `(()=>{${probe}})()` })).result?.result?.value ?? {},
		shot: async () => Buffer.from((await call("Page.captureScreenshot", { format: "png" })).result.data, "base64"),
		close: async () => browser.kill(),
	};
}

const samples = [];
let logs = [];
const t0 = Date.now();
while ((Date.now() - t0) / 1000 < seconds) {
	await wait(5000);
	const v = await driver.sample().catch(() => ({}));
	logs = v.logs ?? logs;
	samples.push({ t: Math.round((Date.now() - t0) / 1000), wasm_mb: MB(v.wasm ?? 0), js_mb: MB(v.js ?? 0) });
	console.log(`[${browserName}] t=${samples.at(-1).t}s wasm=${samples.at(-1).wasm_mb}MB${v.js ? ` js=${samples.at(-1).js_mb}MB` : ""}`);
}
mkdirSync(dirname(outJson), { recursive: true });
try { writeFileSync(outJson.replace(/\.json$/, ".png"), await driver.shot()); } catch (e) { console.error(`캡처 실패: ${e.message}`); }
const errors = logs.filter((l) => /^EXC|SCRIPT ERROR|Aborted\(|RuntimeError|Unhandled exception|out of memory/i.test(l));
const result = {
	browser: browserName, wasm_heap_peak_mb: Math.max(0, ...samples.map((s) => s.wasm_mb)), js_heap_mb: samples.at(-1)?.js_mb ?? 0,
	errors: errors.slice(0, 10), marks: logs.filter((l) => /boot ok|memstat|peak/i.test(l)).slice(-10), samples,
};
writeFileSync(outJson, JSON.stringify(result, null, 2));
console.log(`[${browserName}] wasm 힙 최대 ${result.wasm_heap_peak_mb}MB, 오류 ${errors.length}건 ${result.marks.at(-1) ?? ""} → ${outJson}`);
await driver.close(); server.close();
process.exit(errors.length || !result.wasm_heap_peak_mb ? 1 : 0);
