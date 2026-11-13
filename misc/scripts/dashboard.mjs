// 빌드 러너 대시보드 (로컬): 에이전트별 상태, 진행 단계, 실시간 로그, 작업 이력
// 실행: node misc/scripts/dashboard.mjs  → http://127.0.0.1:8791
// 러너 목록·토큰: ~/.config/godot-enhanced/agents.json (IP 키는 같은 토큰의 이름 키와 합침). 토큰은 브라우저로 안 보냄
import { createServer } from "node:http";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const port = Number(process.env.DASHBOARD_PORT || 8791);
const agentPort = Number(process.env.BUILD_AGENT_PORT || 8790);
const agentsFile = join(homedir(), ".config", "godot-enhanced", "agents.json");
const loadAgents = () => {
	const all = existsSync(agentsFile) ? JSON.parse(readFileSync(agentsFile, "utf8")) : {};
	const byToken = new Map();
	for (const [host, token] of Object.entries(all)) {
		const isIp = /^\d+\.\d+\.\d+\.\d+$/.test(host);
		if (!byToken.has(token) || (!isIp && /^\d/.test(byToken.get(token)))) byToken.set(token, host);
	}
	return [...byToken].map(([token, host]) => ({ host, token }));
};
const call = async (a, path, opts = {}) => {
	const r = await fetch(`http://${a.host}:${agentPort}${path}`, { ...opts, headers: { Authorization: `Bearer ${a.token}` }, signal: AbortSignal.timeout(4000) });
	return r;
};

async function state() {
	return Promise.all(loadAgents().map(async (a) => {
		try {
			const info = await call(a, "/info").then((r) => (r.ok ? r.json() : null)).catch(() => null);
			const status = info ? (info.busy ? `busy ${info.job}` : "idle") : await call(a, "/status").then((r) => r.text());
			const jobs = await call(a, "/jobs?n=12").then((r) => (r.ok ? r.json() : [])).catch(() => []);
			return { host: a.host, online: true, status, info, jobs, legacy: !info };
		} catch (e) { return { host: a.host, online: false, error: String(e.cause?.code || e.name || e) }; }
	}));
}

const page = `<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>빌드 러너</title><style>
:root{--bg:#f6f7f9;--card:#fff;--fg:#1d2330;--mut:#6b7280;--line:#e5e7eb;--ok:#1a7f37;--bad:#cf222e;--run:#bf8700;--skip:#8c959f;--log:#0d1117;--logfg:#d1d7e0}
@media (prefers-color-scheme:dark){:root{--bg:#0d1117;--card:#161b22;--fg:#e6edf3;--mut:#8b949e;--line:#30363d;--log:#010409}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.45 system-ui,-apple-system,"Segoe UI",sans-serif}
header{display:flex;align-items:center;gap:12px;padding:14px 20px;border-bottom:1px solid var(--line);background:var(--card);position:sticky;top:0;z-index:2}
h1{font-size:16px;margin:0}.mut{color:var(--mut)}main{padding:16px 20px;display:grid;gap:16px;grid-template-columns:repeat(auto-fit,minmax(min(100%,560px),1fr))}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;overflow:hidden;min-width:0}
.head{display:flex;align-items:center;gap:10px;padding:12px 14px;border-bottom:1px solid var(--line)}
.dot{width:10px;height:10px;border-radius:50%;flex:none}.idle{background:var(--ok)}.busy{background:var(--run);animation:p 1.2s infinite}.off{background:var(--bad)}
@keyframes p{50%{opacity:.35}}.host{font-weight:600}.meta{font-size:12px;color:var(--mut);padding:8px 14px;border-bottom:1px solid var(--line);display:flex;flex-wrap:wrap;gap:4px 14px}
.steps{display:flex;flex-wrap:wrap;gap:6px;padding:10px 14px}.st{font-size:12px;padding:3px 8px;border-radius:12px;border:1px solid var(--line);white-space:nowrap}
.st.pass{color:var(--ok);border-color:var(--ok)}.st.fail{color:var(--bad);border-color:var(--bad)}.st.running{color:var(--run);border-color:var(--run)}.st.skip,.st.pending{color:var(--skip)}
pre{margin:0;background:var(--log);color:var(--logfg);font:12px/1.4 ui-monospace,Menlo,Consolas,monospace;padding:10px 14px;height:260px;overflow:auto;white-space:pre-wrap;word-break:break-all}
table{width:100%;border-collapse:collapse;font-size:12px}td,th{padding:6px 14px;border-top:1px solid var(--line);text-align:left;vertical-align:top}th{color:var(--mut);font-weight:500}
tr.j{cursor:pointer}tr.j:hover{background:color-mix(in srgb,var(--fg) 5%,transparent)}tr.sel{background:color-mix(in srgb,var(--run) 12%,transparent)}
.b{font-weight:600}.b.success{color:var(--ok)}.b.fail{color:var(--bad)}.b.running{color:var(--run)}.b.cancelled,.b.unknown{color:var(--skip)}
button{font:inherit;font-size:12px;padding:4px 10px;border-radius:6px;border:1px solid var(--line);background:var(--card);color:var(--fg);cursor:pointer;margin-left:auto}
.warn{padding:8px 14px;font-size:12px;color:var(--run)}
</style></head><body><header><h1>빌드 러너</h1><span class="mut" id="t"></span></header><main id="m"></main><script>
const sel={};const fmt=ms=>{if(ms==null)return"";const s=Math.round(ms/1000);return s<60?s+"초":Math.floor(s/60)+"분 "+(s%60)+"초"};
const when=t=>t?new Date(t).toLocaleTimeString("ko-KR",{hour12:false}):"";const esc=s=>String(s??"").replace(/[&<>]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;"}[c]));
const logs={};
async function load(){const s=await (await fetch("/api/state")).json();document.getElementById("t").textContent="갱신 "+when(Date.now());
const m=document.getElementById("m");for(const r of s){let c=document.getElementById("c-"+r.host);if(!c){c=document.createElement("section");c.className="card";c.id="c-"+r.host;m.append(c)}
const busy=r.online&&r.status.startsWith("busy");const cur=(r.jobs||[]).find(j=>j.status==="running");const pick=sel[r.host]||cur?.job||(busy?r.status.split(" ")[1]:null)||r.jobs?.[0]?.job;
const job=(r.jobs||[]).find(j=>j.job===pick);const i=r.info;
c.innerHTML=\`<div class="head"><span class="dot \${!r.online?"off":busy?"busy":"idle"}"></span><span class="host">\${esc(r.host)}</span>
<span class="mut">\${!r.online?"연결 안 됨 ("+esc(r.error)+")":busy?"작업 중":"대기"}</span>\${busy?\`<button onclick="cancelJob('\${r.host}')">취소</button>\`:""}</div>
\${i?\`<div class="meta"><span>\${esc(i.platform)}/\${esc(i.arch)}</span><span>CPU \${i.cpus}개 · 부하 \${i.load.map(x=>x.toFixed(1)).join(" ")}</span><span>메모리 \${i.mem_free_gb}/\${i.mem_total_gb}GB 여유</span><span>소스 \${esc(i.head)}</span><span>node \${esc(i.node)}</span></div>\`:""}
\${r.legacy&&r.online?'<div class="warn">에이전트 갱신 전 (다음 작업 후 자동 재시작 → 단계·정보 표시)</div>':""}
\${job?\`<div class="meta"><span class="b \${job.status}">\${esc(job.status)}</span><span>job \${job.job}</span><span>\${esc(job.sha?.slice(0,10)||"")}</span><span>\${esc(job.args||"(빌드 없음)")}</span><span>\${when(job.started)} · \${fmt((job.ended||Date.now())-job.started)}</span></div>
<div class="steps">\${(job.steps||[]).map(x=>\`<span class="st \${x.status}">\${x.status==="pass"?"✔":x.status==="fail"?"✘":x.status==="running"?"●":"○"} \${esc(x.name)} \${x.start?fmt((x.end||Date.now())-x.start):""}</span>\`).join("")}</div>\`:""}
<pre id="log-\${r.host}">\${esc(logs[r.host+pick]||"")}</pre>
<table><tr><th>작업</th><th>결과</th><th>내용</th><th>시간</th></tr>\${(r.jobs||[]).map(j=>\`<tr class="j \${j.job===pick?"sel":""}" onclick="sel['\${r.host}']='\${j.job}';load()"><td>\${when(j.started)}</td><td class="b \${j.status}">\${esc(j.status)}</td><td>\${esc(j.args||"")} \${j.tests?.length?"→ "+esc(j.tests.join(",")):""}\${j.release?" → 릴리스":""}</td><td>\${j.ended?fmt(j.ended-j.started):j.status==="running"?"진행 중":""}</td></tr>\`).join("")}</table>\`;
if(pick&&r.online){const t=await (await fetch(\`/api/log?host=\${r.host}&job=\${pick}\`)).text();logs[r.host+pick]=t;const p=document.getElementById("log-"+r.host);const end=p.scrollTop+p.clientHeight>=p.scrollHeight-20;p.textContent=t;if(end||busy)p.scrollTop=p.scrollHeight}}}
async function cancelJob(h){if(confirm(h+" 진행 중 작업 취소?"))await fetch("/api/cancel?host="+h,{method:"POST"});load()}
load();setInterval(load,2000);
</script></body></html>`;

createServer(async (req, res) => {
	const url = new URL(req.url, "http://x");
	try {
		if (url.pathname === "/") { res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" }).end(page); return; }
		if (url.pathname === "/api/state") { res.writeHead(200, { "Content-Type": "application/json" }).end(JSON.stringify(await state())); return; }
		const a = loadAgents().find((x) => x.host === url.searchParams.get("host"));
		if (!a) { res.writeHead(404).end(); return; }
		if (url.pathname === "/api/log") {
			const t = await (await call(a, `/log/${url.searchParams.get("job").replace(/\D/g, "")}`)).text();
			res.writeHead(200, { "Content-Type": "text/plain; charset=utf-8" }).end(t.replace(/​\n/g, "").slice(-60000));
			return;
		}
		if (url.pathname === "/api/cancel" && req.method === "POST") { res.end(await (await call(a, "/cancel", { method: "POST" })).text()); return; }
		res.writeHead(404).end();
	} catch (e) { res.writeHead(502).end(String(e)); }
}).listen(port, "127.0.0.1", () => console.log(`[dashboard] http://127.0.0.1:${port}`));
