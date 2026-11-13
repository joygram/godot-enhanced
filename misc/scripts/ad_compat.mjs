// 광고 호환 검사: 헤더 3종(없음 / COEP require-corp / COEP credentialless) × 브라우저
// → 광고 스크립트(AdSense) 로드, 광고 iframe 로드, 스레드(SharedArrayBuffer·crossOriginIsolated) 가능 여부
// 사용: node misc/scripts/ad_compat.mjs [결과 json]   환경: BROWSER = safari | chrome, CHROME, AD_COMPAT_PORT
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { existsSync, readdirSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { tmpdir } from "node:os";

const outJson = resolve(process.argv[2] ?? "ad-compat.json");
const port = Number(process.env.AD_COMPAT_PORT ?? 8796);
const browserName = process.env.BROWSER || (process.platform === "darwin" ? "safari" : "chrome");
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const MODES = {
	none: {},
	"require-corp": { "Cross-Origin-Opener-Policy": "same-origin", "Cross-Origin-Embedder-Policy": "require-corp" },
	credentialless: { "Cross-Origin-Opener-Policy": "same-origin", "Cross-Origin-Embedder-Policy": "credentialless" },
};
const PAGE = `<!doctype html><html><body><script>
window.__r={script:"pending",iframe:"pending",img:"pending"};
</script>
<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js" onload="__r.script='ok'" onerror="__r.script='blocked'"></script>
<iframe src="https://googleads.g.doubleclick.net/pagead/html/r20250101/r20190131/zrt_lookup.html" onload="__r.iframe='loaded'" style="width:1px;height:1px"></iframe>
<img src="https://www.gstatic.com/images/branding/googlelogo/1x/googlelogo_color_92x30dp.png" onload="__r.img='ok'" onerror="__r.img='blocked'">
</body></html>`;
const probe = "return {script: __r.script, iframe: __r.iframe, img: __r.img, adsbygoogle: typeof window.adsbygoogle !== 'undefined', isolated: !!self.crossOriginIsolated, sab: typeof SharedArrayBuffer !== 'undefined'}";

const server = createServer((req, res) => {
	const mode = new URL(req.url, "http://x").pathname.slice(1);
	if (!MODES[mode]) { res.writeHead(404).end(); return; }
	res.writeHead(200, { "Content-Type": "text/html", ...MODES[mode] }).end(PAGE);
}).listen(port);

let open, run, close;
if (browserName === "safari") {
	spawn("osascript", ["-e", 'quit app "Safari"']); await wait(3000);
	const wdPort = port + 1;
	const sd = spawn("safaridriver", ["-p", String(wdPort)]);
	const wd = async (m, p, b) => (await (await fetch(`http://127.0.0.1:${wdPort}${p}`, { method: m, headers: { "Content-Type": "application/json" }, body: b && JSON.stringify(b) })).json()).value;
	let s;
	for (let i = 0, t = 0; i < 60 && !s && t < 3; i++) {
		try { const v = await wd("POST", "/session", { capabilities: { alwaysMatch: { browserName: "safari" } } }); if (v.sessionId) s = v.sessionId; else { t++; await wait(5000); } } catch { await wait(500); }
	}
	if (!s) { console.error("✘ Safari 세션 실패"); sd.kill(); server.close(); process.exit(1); }
	open = (u) => wd("POST", `/session/${s}/url`, { url: u });
	run = () => wd("POST", `/session/${s}/execute/sync`, { script: probe, args: [] });
	close = async () => { await wd("DELETE", `/session/${s}`).catch(() => {}); sd.kill(); };
} else {
	const pwDir = join(process.env.HOME || "", ".cache", "ms-playwright");
	const pw = existsSync(pwDir) ? readdirSync(pwDir).filter((d) => d.startsWith("chromium-")).map((d) => join(pwDir, d, "chrome-linux", "chrome")) : [];
	const chrome = [process.env.CHROME, "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", "/usr/bin/google-chrome", "/usr/bin/chromium", "C:/Program Files/Google/Chrome/Application/chrome.exe", ...pw].find((p) => p && existsSync(p));
	if (!chrome) { console.error("✘ Chrome 없음"); server.close(); process.exit(1); }
	const b = spawn(chrome, ["--headless=new", "--no-sandbox", `--remote-debugging-port=${port + 1}`, `--user-data-dir=${join(tmpdir(), `ad-compat-${process.pid}`)}`, "about:blank"]);
	let ws; let id = 0; const pend = new Map();
	for (let i = 0; i < 60 && !ws; i++) {
		try { const t = (await (await fetch(`http://127.0.0.1:${port + 1}/json`)).json()).find((p) => p.type === "page"); const w = new WebSocket(t.webSocketDebuggerUrl); await new Promise((r, j) => { w.addEventListener("open", r); w.addEventListener("error", j); }); ws = w; } catch { await wait(250); }
	}
	ws.addEventListener("message", (m) => { const d = JSON.parse(m.data); if (d.id && pend.has(d.id)) { pend.get(d.id)(d); pend.delete(d.id); } });
	const call = (method, params = {}) => new Promise((r) => { const i = ++id; pend.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
	open = (u) => call("Page.navigate", { url: u });
	run = async () => (await call("Runtime.evaluate", { returnByValue: true, expression: `(()=>{${probe}})()` })).result?.result?.value ?? {};
	close = async () => b.kill();
}

const results = {};
for (const mode of Object.keys(MODES)) {
	await open(`http://127.0.0.1:${port}/${mode}`);
	await wait(8000);
	results[mode] = await run().catch((e) => ({ error: String(e) }));
	const r = results[mode];
	console.log(`[${browserName}] ${mode.padEnd(14)} 광고스크립트=${r.script} adsbygoogle=${r.adsbygoogle} 광고iframe=${r.iframe} 외부이미지=${r.img} 스레드가능=${r.isolated && r.sab}`);
}
writeFileSync(outJson, JSON.stringify({ browser: browserName, results }, null, 2));
await close(); server.close();
