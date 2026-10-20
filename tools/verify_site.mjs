import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const OUT_DIR = path.resolve("./raw_clips/site_screenshots");
fs.mkdirSync(OUT_DIR, { recursive: true });

const userDataDir = "/tmp/chrome-site-verify-" + process.pid;
const proc = spawn(
  CHROME,
  [
    "--headless=new",
    "--remote-debugging-port=0",
    `--user-data-dir=${userDataDir}`,
    "--enable-webgl",
    "--ignore-gpu-blocklist",
    "--autoplay-policy=no-user-gesture-required",
    "--window-size=1540,1080",
    "--force-device-scale-factor=2",
    "--no-first-run",
    "--no-default-browser-check",
    "http://localhost:4173/",
  ],
  { stdio: ["ignore", "pipe", "pipe"] }
);

const wsUrl = await new Promise((resolve, reject) => {
  let buf = "";
  proc.stderr.on("data", (d) => {
    buf += d.toString();
    const m = buf.match(/DevTools listening on (ws:\/\/[^\s]+)/);
    if (m) resolve(m[1]);
  });
  setTimeout(() => reject(new Error("Chrome launch timeout:\n" + buf)), 10000);
});

const baseHttp = wsUrl.replace(/^ws:/, "http:").replace(/\/devtools\/browser\/.*$/, "");
let pages = [];
for (let i = 0; i < 30; i++) {
  pages = await (await fetch(`${baseHttp}/json/list`)).json();
  if (pages.find((p) => p.type === "page" && p.webSocketDebuggerUrl)) break;
  await new Promise((r) => setTimeout(r, 100));
}

const pageWs = new WebSocket(pages.find((p) => p.type === "page").webSocketDebuggerUrl);
await new Promise((r) => pageWs.addEventListener("open", r));

let msgId = 1;
const consoleErrors = [];
pageWs.addEventListener("message", (ev) => {
  const msg = JSON.parse(ev.data);
  if (msg.method === "Runtime.exceptionThrown") {
    consoleErrors.push(msg.params.exceptionDetails);
  }
});

function cdp(method, params = {}) {
  const id = msgId++;
  return new Promise((resolve, reject) => {
    const onMsg = (ev) => {
      const msg = JSON.parse(ev.data);
      if (msg.id === id) {
        pageWs.removeEventListener("message", onMsg);
        if (msg.error) reject(new Error(JSON.stringify(msg.error)));
        else resolve(msg.result);
      }
    };
    pageWs.addEventListener("message", onMsg);
    pageWs.send(JSON.stringify({ id, method, params }));
  });
}

async function evalJs(expression) {
  const res = await cdp("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true });
  if (res.exceptionDetails) throw new Error(JSON.stringify(res.exceptionDetails, null, 2));
  return res.result.value;
}

await cdp("Runtime.enable");
await cdp("Page.enable");

// Wait for shader program compilation & video readiness
for (let i = 0; i < 60; i++) {
  const ready = await evalJs(`(() => {
    const v = document.getElementById('source-video');
    const st = document.getElementById('compile-status-text')?.textContent || '';
    return v && v.readyState >= 3 && st.includes('COMPILED');
  })()`);
  if (ready) break;
  await new Promise((r) => setTimeout(r, 150));
}
await new Promise((r) => setTimeout(r, 600));

async function capturePng(filename) {
  const shot = await cdp("Page.captureScreenshot", { format: "png" });
  fs.writeFileSync(path.join(OUT_DIR, filename), Buffer.from(shot.data, "base64"));
}

// 1. Capture Hero + Side-by-Side Synchronized View (Act I at t = 1.6s)
await evalJs(`(() => {
  document.getElementById('play-toggle-btn').click();
  const v = document.getElementById('source-video');
  v.currentTime = 1.6;
  return new Promise(r => setTimeout(r, 350));
})()`);
await capturePng("01_hero_side_by_side.png");

// 2. Capture Split-Curtain Wipe Mode at Act III (t = 10.6s)
await evalJs(`(() => {
  document.getElementById('mode-wipe-btn').click();
  const v = document.getElementById('source-video');
  v.currentTime = 10.6;
  return new Promise(r => setTimeout(r, 350));
})()`);
await capturePng("02_wipe_curtain_act3.png");

// 3. Switch back to Side-by-Side + Enable DEBUG_MODE 2 (3D World Normals) on Act IV (t = 16.8s)
await evalJs(`(async () => {
  document.getElementById('mode-side-btn').click();
  const v = document.getElementById('source-video');
  v.currentTime = 16.8;
  document.getElementById('dbg-2-btn').click();
  for (let i = 0; i < 40; i++) {
    const st = document.getElementById('compile-status-text').textContent;
    if (st.includes('COMPILED')) break;
    await new Promise(r => setTimeout(r, 100));
  }
  await new Promise(r => setTimeout(r, 250));
})()`);
await capturePng("03_debug_normals_act4.png");

// 4. Scroll down to Raw Clips + Syntax-Highlighted GLSL Code Inspector
await evalJs(`(() => {
  document.getElementById('clips-anchor').scrollIntoView({ behavior: 'instant' });
  return new Promise(r => setTimeout(r, 250));
})()`);
await capturePng("04_raw_clips_and_code.png");

const uiState = await evalJs(`({
  shaderSize: document.getElementById('stat-shader-size').textContent,
  shaderLines: document.getElementById('stat-shader-lines').textContent,
  fps: document.getElementById('stat-gpu-fps').textContent,
  gpu: document.getElementById('stat-gpu-renderer').textContent,
  compileStatus: document.getElementById('compile-status-text').textContent,
})`);

console.log(JSON.stringify({ consoleErrors, uiState }, null, 2));

pageWs.close();
proc.kill("SIGKILL");
fs.rmSync(userDataDir, { recursive: true, force: true });
