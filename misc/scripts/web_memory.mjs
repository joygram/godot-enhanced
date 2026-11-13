// 웹 빌드 메모리 측정: 정적 서버(COOP/COEP) + headless Chrome → wasm 힙·JS 힙 표본, 예외 검사, 화면 캡처
// 사용: node misc/scripts/web_memory.mjs <웹 빌드 폴더> [초=30] [결과 json 경로]
// 환경: CHROME (Chrome 실행 파일), WEB_MEMORY_PORT (기본 8798)
// 출력: { wasm_heap_peak_mb, js_heap_mb, samples, errors, ready } + 같은 이름 .png 캡처. 예외·중단 시 종료 코드 1
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, extname, join, resolve } from "node:path";
import { tmpdir } from "node:os";

const web = resolve(process.argv[2] ?? ".");
const seconds = Number(process.argv[3] ?? 30);
const outJson = resolve(process.argv[4] ?? join(web, "web-memory.json"));
const port = Number(process.env.WEB_MEMORY_PORT ?? 8798);
const chrome = [process.env.CHROME, "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", "/usr/bin/google-chrome",
	"/usr/bin/google-chrome-stable", "/usr/bin/chromium", "/usr/bin/chromium-browser", "/snap/bin/chromium",
	"C:/Program Files/Google/Chrome/Application/chrome.exe"].find((p) => p && existsSync(p));
if (!existsSync(join(web, "index.html"))) { console.error(`✘ ${web}/index.html 없음`); process.exit(1); }
if (!chrome) { console.error("✘ Chrome 없음 → CHROME 지정"); process.exit(1); }
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const MIME = { ".html": "text/html", ".js": "text/javascript", ".wasm": "application/wasm" };

const server = createServer((req, res) => {
	const file = join(web, decodeURIComponent(new URL(req.url, "http://x").pathname));
	if (!file.startsWith(web) || !existsSync(file)) { res.writeHead(404).end(); return; }
	res.writeHead(200, { "Content-Type": MIME[extname(file)] || "application/octet-stream",
		"Cross-Origin-Opener-Policy": "same-origin", "Cross-Origin-Embedder-Policy": "require-corp" });
	res.end(readFileSync(file));
}).listen(port);

const profile = join(tmpdir(), `web-memory-${process.pid}`);
const browser = spawn(chrome, ["--headless=new", "--no-sandbox", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
	"--enable-precise-memory-info", "--window-size=960,540", `--remote-debugging-port=${port + 1}`, `--user-data-dir=${profile}`, "about:blank"]);

let ws; let id = 0; const pending = new Map(); const logs = [];
for (let i = 0; i < 60 && !ws; i++) {
	try {
		const page = (await (await fetch(`http://127.0.0.1:${port + 1}/json`)).json()).find((p) => p.type === "page");
		const w = new WebSocket(page.webSocketDebuggerUrl);
		await new Promise((r, j) => { w.addEventListener("open", r); w.addEventListener("error", j); });
		ws = w;
	} catch { await wait(250); }
}
if (!ws) { console.error("✘ DevTools 연결 실패"); browser.kill(); server.close(); process.exit(1); }
ws.addEventListener("message", (m) => {
	const d = JSON.parse(m.data);
	if (d.id && pending.has(d.id)) { pending.get(d.id)(d); pending.delete(d.id); }
	else if (d.method === "Runtime.consoleAPICalled") logs.push(d.params.args.map((a) => a.value ?? a.description ?? "").join(" "));
	else if (d.method === "Runtime.exceptionThrown") logs.push(`EXC ${d.params.exceptionDetails.exception?.description ?? d.params.exceptionDetails.text}`);
});
const call = (method, params = {}) => new Promise((r) => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
await call("Runtime.enable"); await call("Performance.enable"); await call("Page.enable");
await call("Page.addScriptToEvaluateOnNewDocument", { source: `(()=>{const M=WebAssembly.Memory;globalThis.__mems=[];
	WebAssembly.Memory=function(d){const m=new M(d);globalThis.__mems.push(m);return m};WebAssembly.Memory.prototype=M.prototype;})();` });
await call("Page.navigate", { url: `http://127.0.0.1:${port}/index.html` });

const MB = (b) => Math.round(b / 1048576 * 10) / 10;
const samples = [];
const t0 = Date.now();
while ((Date.now() - t0) / 1000 < seconds) {
	await wait(5000);
	const e = await call("Runtime.evaluate", { returnByValue: true, expression: "Math.max(0,...(globalThis.__mems||[]).map(m=>m.buffer.byteLength))" });
	const pm = Object.fromEntries((await call("Performance.getMetrics")).result.metrics.map((x) => [x.name, x.value]));
	samples.push({ t: Math.round((Date.now() - t0) / 1000), wasm_mb: MB(e.result?.result?.value ?? 0), js_mb: MB(pm.JSHeapUsedSize) });
	console.log(`t=${samples.at(-1).t}s wasm=${samples.at(-1).wasm_mb}MB js=${samples.at(-1).js_mb}MB`);
}
const shot = await call("Page.captureScreenshot", { format: "png" });
mkdirSync(dirname(outJson), { recursive: true });
writeFileSync(outJson.replace(/\.json$/, ".png"), Buffer.from(shot.result.data, "base64"));
const errors = logs.filter((l) => /^EXC|SCRIPT ERROR|Aborted\(|RuntimeError|Unhandled exception|out of memory/i.test(l));
const result = {
	wasm_heap_peak_mb: Math.max(0, ...samples.map((s) => s.wasm_mb)), js_heap_mb: samples.at(-1)?.js_mb ?? 0,
	ready: logs.some((l) => /boot ok|Godot Engine/.test(l)), errors: errors.slice(0, 10), samples,
	marks: logs.filter((l) => /memstat|boot ok|peak/i.test(l)).slice(-10),
};
writeFileSync(outJson, JSON.stringify(result, null, 2));
console.log(`wasm 힙 최대 ${result.wasm_heap_peak_mb}MB, 오류 ${errors.length}건 → ${outJson}`);
browser.kill(); server.close();
process.exit(errors.length || !result.wasm_heap_peak_mb ? 1 : 0);
