import { spawn } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";

const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const SHADER_PATH = path.resolve("./public/gemini_video2glsl.glsl");
const OUT_DIR = path.resolve("./raw_clips/shader_renders");
fs.mkdirSync(OUT_DIR, { recursive: true });

const shaderBody = fs.readFileSync(SHADER_PATH, "utf8");

const HTML = `<!doctype html>
<html>
<body style="margin:0;background:#000;overflow:hidden">
<canvas id="gl" width="1280" height="720"></canvas>
<script>
const canvas = document.getElementById('gl');
const gl = canvas.getContext('webgl2', { preserveDrawingBuffer: true, antialias: false });
window.SH_SOURCE = ${JSON.stringify(shaderBody)};

function buildProgram(debugMode, quality) {
  const src = window.SH_SOURCE
    .replace(/^#define\\s+DEBUG_MODE\\s+\\d+/m, '#define DEBUG_MODE ' + debugMode)
    .replace(/^#define\\s+QUALITY\\s+\\d+/m, '#define QUALITY ' + quality);
  const vsSrc = \`#version 300 es
    void main() {
      vec2 p = vec2((gl_VertexID == 1) ? 3.0 : -1.0, (gl_VertexID == 2) ? 3.0 : -1.0);
      gl_Position = vec4(p, 0.0, 1.0);
    }\`;
  const fsSrc = \`#version 300 es
    precision highp float;
    precision highp int;
    precision mediump sampler3D;
    uniform vec3 iResolution;
    uniform float iTime;
    uniform float iTimeDelta;
    uniform float iFrameRate;
    uniform int iFrame;
    uniform vec4 iMouse;
    uniform vec4 iDate;
    out vec4 st_FragColor;
    \` + src + \`
    void main() { mainImage(st_FragColor, gl_FragCoord.xy); st_FragColor.a = 1.0; }\`;

  const t0 = performance.now();
  const vs = gl.createShader(gl.VERTEX_SHADER);
  gl.shaderSource(vs, vsSrc);
  gl.compileShader(vs);
  if (!gl.getShaderParameter(vs, gl.COMPILE_STATUS)) {
    throw new Error('VS: ' + gl.getShaderInfoLog(vs));
  }
  const fs = gl.createShader(gl.FRAGMENT_SHADER);
  gl.shaderSource(fs, fsSrc);
  gl.compileShader(fs);
  if (!gl.getShaderParameter(fs, gl.COMPILE_STATUS)) {
    throw new Error('FS: ' + gl.getShaderInfoLog(fs));
  }
  const prog = gl.createProgram();
  gl.attachShader(prog, vs);
  gl.attachShader(prog, fs);
  gl.linkProgram(prog);
  if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
    throw new Error('LINK: ' + gl.getProgramInfoLog(prog));
  }
  return { prog, compileMs: performance.now() - t0 };
}

window.progs = {};
window.renderAt = function(timeSec, debugMode = 0, quality = 2, frame = 1) {
  const key = debugMode + '_' + quality;
  if (!window.progs[key]) {
    window.progs[key] = buildProgram(debugMode, quality);
  }
  const { prog, compileMs } = window.progs[key];
  gl.viewport(0, 0, canvas.width, canvas.height);
  gl.useProgram(prog);
  gl.uniform3f(gl.getUniformLocation(prog, 'iResolution'), canvas.width, canvas.height, 1.0);
  gl.uniform1f(gl.getUniformLocation(prog, 'iTime'), timeSec);
  gl.uniform1f(gl.getUniformLocation(prog, 'iTimeDelta'), 1.0 / 60.0);
  gl.uniform1f(gl.getUniformLocation(prog, 'iFrameRate'), 60.0);
  gl.uniform1i(gl.getUniformLocation(prog, 'iFrame'), frame);
  gl.uniform4f(gl.getUniformLocation(prog, 'iMouse'), 0, 0, 0, 0);
  gl.uniform4f(gl.getUniformLocation(prog, 'iDate'), 2026, 10, 19, 0);
  const t0 = performance.now();
  gl.drawArrays(gl.TRIANGLES, 0, 3);
  gl.finish();
  const drawMs = performance.now() - t0;
  return {
    compileMs,
    drawMs,
    renderer: gl.getParameter(gl.getExtension('WEBGL_debug_renderer_info')?.UNMASKED_RENDERER_WEBGL || gl.RENDERER),
    dataUrl: canvas.toDataURL('image/png')
  };
};
window.READY = true;
</script>
</body>
</html>`;

const server = http.createServer((req, res) => {
  res.writeHead(200, { "Content-Type": "text/html" });
  res.end(HTML);
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const port = server.address().port;

const userDataDir = "/tmp/chrome-shader-eval-" + process.pid;
const proc = spawn(CHROME, [
  "--headless=new",
  "--remote-debugging-port=0",
  `--user-data-dir=${userDataDir}`,
  "--enable-webgl",
  "--ignore-gpu-blocklist",
  "--window-size=1280,720",
  "--no-first-run",
  "--no-default-browser-check",
  `http://127.0.0.1:${port}/`,
], { stdio: ["ignore", "pipe", "pipe"] });

const wsUrl = await new Promise((resolve, reject) => {
  let buf = "";
  proc.stderr.on("data", (d) => {
    buf += d.toString();
    const m = buf.match(/DevTools listening on (ws:\/\/[^\s]+)/);
    if (m) resolve(m[1]);
  });
  setTimeout(() => reject(new Error("Timed out waiting for Chrome DevTools:\n" + buf)), 10000);
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
  if (res.exceptionDetails) {
    throw new Error(JSON.stringify(res.exceptionDetails, null, 2));
  }
  return res.result.value;
}

for (let i = 0; i < 50; i++) {
  const ok = await evalJs("Boolean(window.READY)");
  if (ok) break;
  await new Promise((r) => setTimeout(r, 100));
}

// Render 12 timestamps matching extracted frames (t = 0.0, 2.0, 4.0, 5.5, 7.0, 9.0, 10.5, 12.0, 14.0, 15.5, 17.0, 19.5) + all debug modes!
const timestamps = [0.0, 2.0, 4.0, 5.5, 7.0, 9.0, 10.5, 12.0, 14.0, 15.5, 17.0, 19.5];
const stats = [];
for (const t of timestamps) {
  const r = await evalJs(`window.renderAt(${t}, 0, 3, ${Math.round(t * 60)})`);
  const pngBuf = Buffer.from(r.dataUrl.split(",")[1], "base64");
  const outFile = path.join(OUT_DIR, `shader_t${t.toFixed(2).padStart(5, "0")}.png`);
  fs.writeFileSync(outFile, pngBuf);
  stats.push({ t, compileMs: +r.compileMs.toFixed(1), drawMs: +r.drawMs.toFixed(2), renderer: r.renderer });
}

// Benchmark interactive QUALITY=2 frame rate across 20 frames
const bench = await evalJs(`(() => {
  window.renderAt(1.0, 0, 2, 1); // warmup compile
  const times = [];
  for (let i = 0; i < 20; i++) {
    const r = window.renderAt(i * 1.0, 0, 2, i + 1);
    times.push(r.drawMs);
  }
  const avg = times.reduce((a,b)=>a+b,0) / times.length;
  return { avgDrawMs: +avg.toFixed(2), estFps: +(1000 / Math.max(avg, 0.1)).toFixed(1) };
})()`);

// Verify seamless loop pixel identity: t = 0.000 vs t = 20.000!
const loopCheck = await evalJs(`(() => {
  window.renderAt(0.0, 0, 2, 0);
  const a = new Uint8Array(1280 * 720 * 4);
  gl.readPixels(0, 0, 1280, 720, gl.RGBA, gl.UNSIGNED_BYTE, a);
  window.renderAt(20.0, 0, 2, 0);
  const b = new Uint8Array(1280 * 720 * 4);
  gl.readPixels(0, 0, 1280, 720, gl.RGBA, gl.UNSIGNED_BYTE, b);
  let maxDiff = 0;
  for (let i = 0; i < a.length; i++) maxDiff = Math.max(maxDiff, Math.abs(a[i] - b[i]));
  return { maxChannelDiff_t0_vs_t20: maxDiff };
})()`);

console.log(JSON.stringify({ renderer: stats[0].renderer, compileMs_Q3: stats[0].compileMs, bench_Q2: bench, loopCheck, framesRendered: stats.length }, null, 2));

pageWs.close();
proc.kill("SIGKILL");
server.close();
fs.rmSync(userDataDir, { recursive: true, force: true });
