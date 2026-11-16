import { spawn } from "node:child_process";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";

function findChrome() {
  if (process.env.CHROME_PATH && fs.existsSync(process.env.CHROME_PATH)) {
    return process.env.CHROME_PATH;
  }
  const candidates = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/usr/bin/google-chrome",
    "/usr/bin/google-chrome-stable",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
    "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
    "C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe",
  ];
  for (const c of candidates) {
    if (fs.existsSync(c)) return c;
  }
  throw new Error("Chrome/Chromium binary not found. Set CHROME_PATH environment variable.");
}

const CHROME = findChrome();
const SHADER_PATH = path.resolve("./public/gemini_video2glsl.glsl");
const OUT_DIR = path.resolve("./raw_clips/shader_renders");
const JSON_OUT = path.resolve("./raw_clips/gpu_eval_latest.json");
fs.mkdirSync(OUT_DIR, { recursive: true });

const shaderBody = fs.readFileSync(SHADER_PATH, "utf8");

const HTML = `<!doctype html>
<html>
<body style="margin:0;background:#000;overflow:hidden">
<canvas id="gl" width="1280" height="720"></canvas>
<script>
const canvas = document.getElementById('gl');
const gl = canvas.getContext('webgl2', {
  preserveDrawingBuffer: true,
  antialias: false,
  powerPreference: 'high-performance'
});
window.SH_SOURCE = ${JSON.stringify(shaderBody)};
const syncPx = new Uint8Array(4);

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
    const err = gl.getShaderInfoLog(vs);
    gl.deleteShader(vs);
    throw new Error('VS: ' + err);
  }
  const fs = gl.createShader(gl.FRAGMENT_SHADER);
  gl.shaderSource(fs, fsSrc);
  gl.compileShader(fs);
  if (!gl.getShaderParameter(fs, gl.COMPILE_STATUS)) {
    const err = gl.getShaderInfoLog(fs);
    gl.deleteShader(vs);
    gl.deleteShader(fs);
    throw new Error('FS: ' + err);
  }
  const prog = gl.createProgram();
  gl.attachShader(prog, vs);
  gl.attachShader(prog, fs);
  gl.linkProgram(prog);
  if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
    const err = gl.getProgramInfoLog(prog);
    gl.deleteShader(vs);
    gl.deleteShader(fs);
    gl.deleteProgram(prog);
    throw new Error('LINK: ' + err);
  }
  gl.deleteShader(vs);
  gl.deleteShader(fs);
  const uniforms = {
    iResolution: gl.getUniformLocation(prog, 'iResolution'),
    iTime: gl.getUniformLocation(prog, 'iTime'),
    iTimeDelta: gl.getUniformLocation(prog, 'iTimeDelta'),
    iFrameRate: gl.getUniformLocation(prog, 'iFrameRate'),
    iFrame: gl.getUniformLocation(prog, 'iFrame'),
    iMouse: gl.getUniformLocation(prog, 'iMouse'),
    iDate: gl.getUniformLocation(prog, 'iDate'),
  };
  return { prog, uniforms, compileMs: performance.now() - t0 };
}

window.progs = {};
window.renderAt = function(timeSec, debugMode = 0, quality = 2, frame = 1, captureImage = false) {
  const key = debugMode + '_' + quality;
  if (!window.progs[key]) {
    window.progs[key] = buildProgram(debugMode, quality);
  }
  const { prog, uniforms, compileMs } = window.progs[key];
  gl.viewport(0, 0, canvas.width, canvas.height);
  gl.useProgram(prog);
  gl.uniform3f(uniforms.iResolution, canvas.width, canvas.height, 1.0);
  gl.uniform1f(uniforms.iTime, timeSec);
  gl.uniform1f(uniforms.iTimeDelta, 1.0 / 60.0);
  gl.uniform1f(uniforms.iFrameRate, 60.0);
  gl.uniform1i(uniforms.iFrame, frame);
  gl.uniform4f(uniforms.iMouse, 0, 0, 0, 0);
  gl.uniform4f(uniforms.iDate, 2026, 10, 19, 0);

  // Force true GPU pipeline completion via 1x1 readPixels synchronization (unlike gl.finish in Chromium)
  const t0 = performance.now();
  gl.drawArrays(gl.TRIANGLES, 0, 3);
  gl.readPixels(0, 0, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, syncPx);
  const drawMs = performance.now() - t0;

  const dbgExt = gl.getExtension('WEBGL_debug_renderer_info');
  return {
    compileMs,
    drawMs,
    renderer: gl.getParameter(dbgExt ? dbgExt.UNMASKED_RENDERER_WEBGL : gl.RENDERER),
    dataUrl: captureImage ? canvas.toDataURL('image/png') : null
  };
};

window.benchTier = function(quality) {
  const acts = [
    { name: 'act1', t: 2.0 },
    { name: 'act2', t: 7.0 },
    { name: 'act3', t: 12.0 },
    { name: 'act4', t: 17.0 },
  ];
  const warm = window.renderAt(2.0, 0, quality, 1, false);
  const perAct = {};
  const all = [];
  for (const act of acts) {
    window.renderAt(act.t, 0, quality, 1, false);
    window.renderAt(act.t + 0.05, 0, quality, 2, false);
    const samples = [];
    for (let i = 0; i < 9; i++) {
      const r = window.renderAt(act.t + i * 0.04, 0, quality, i + 3, false);
      samples.push(r.drawMs);
      all.push(r.drawMs);
    }
    samples.sort((a, b) => a - b);
    const p50 = samples[Math.floor(samples.length * 0.5)];
    const p95 = samples[Math.min(samples.length - 1, Math.floor(samples.length * 0.95))];
    perAct[act.name] = {
      p50DrawMs: +p50.toFixed(2),
      p95DrawMs: +p95.toFixed(2),
      estFps: +(1000 / Math.max(p50, 0.01)).toFixed(1),
    };
  }
  all.sort((a, b) => a - b);
  const p50 = all[Math.floor(all.length * 0.5)];
  const p95 = all[Math.min(all.length - 1, Math.floor(all.length * 0.95))];
  const avg = all.reduce((a, b) => a + b, 0) / all.length;
  return {
    compileMs: +warm.compileMs.toFixed(1),
    avgDrawMs: +avg.toFixed(2),
    p50DrawMs: +p50.toFixed(2),
    p95DrawMs: +p95.toFixed(2),
    estFps: +(1000 / Math.max(p50, 0.01)).toFixed(1),
    perAct,
  };
};

window.verifyLoopSeam = function() {
  function grab(t, frame) {
    window.renderAt(t, 0, 2, frame, false);
    const px = new Uint8Array(canvas.width * canvas.height * 4);
    gl.readPixels(0, 0, canvas.width, canvas.height, gl.RGBA, gl.UNSIGNED_BYTE, px);
    return px;
  }
  function compare(a, b) {
    let maxDiff = 0;
    let sumDiff = 0;
    const channels = (a.length / 4) * 3;
    for (let i = 0; i < a.length; i += 4) {
      for (let c = 0; c < 3; c++) {
        const d = Math.abs(a[i + c] - b[i + c]);
        if (d > maxDiff) maxDiff = d;
        sumDiff += d;
      }
    }
    return { maxChannelDiff: maxDiff, meanAbsDiff: +(sumDiff / channels).toFixed(3) };
  }

  const f0 = grab(0.0, 0);
  const f20Same = grab(20.0, 0);
  const f20Adv = grab(20.0, 1200);
  const f19999 = grab(19.999, 1199);
  const f19967 = grab(19.9667, 1198);

  return {
    t0_vs_t20_sameFrame: compare(f0, f20Same),
    t0_vs_t20_advancingFrame: compare(f0, f20Adv),
    t19_999_vs_t0: compare(f19999, f0),
    t19_967_vs_t0: compare(f19967, f0),
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
const proc = spawn(
  CHROME,
  [
    "--headless=new",
    "--remote-debugging-port=0",
    `--user-data-dir=${userDataDir}`,
    "--enable-webgl",
    "--ignore-gpu-blocklist",
    "--window-size=1280,720",
    "--no-first-run",
    "--no-default-browser-check",
    `http://127.0.0.1:${port}/`,
  ],
  { stdio: ["ignore", "pipe", "pipe"] }
);

let pageWs = null;
try {
  const wsUrl = await new Promise((resolve, reject) => {
    let buf = "";
    proc.stderr.on("data", (d) => {
      buf += d.toString();
      const m = buf.match(/DevTools listening on (ws:\/\/[^\s]+)/);
      if (m) resolve(m[1]);
    });
    setTimeout(() => reject(new Error("Timed out waiting for Chrome DevTools:\n" + buf)), 15000);
  });

  const baseHttp = wsUrl.replace(/^ws:/, "http:").replace(/\/devtools\/browser\/.*$/, "");
  let pages = [];
  for (let i = 0; i < 40; i++) {
    pages = await (await fetch(`${baseHttp}/json/list`)).json();
    if (pages.find((p) => p.type === "page" && p.webSocketDebuggerUrl)) break;
    await new Promise((r) => setTimeout(r, 100));
  }
  pageWs = new WebSocket(pages.find((p) => p.type === "page").webSocketDebuggerUrl);
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

  // Render 12 timestamps at Q3 and save PNGs
  const timestamps = [0.0, 2.0, 4.0, 5.5, 7.0, 9.0, 10.5, 12.0, 14.0, 15.5, 17.0, 19.5];
  const stats = [];
  for (const t of timestamps) {
    const r = await evalJs(`window.renderAt(${t}, 0, 3, ${Math.round(t * 60)}, true)`);
    const pngBuf = Buffer.from(r.dataUrl.split(",")[1], "base64");
    const outFile = path.join(OUT_DIR, `shader_t${t.toFixed(2).padStart(5, "0")}.png`);
    fs.writeFileSync(outFile, pngBuf);
    stats.push({ t, compileMs: +r.compileMs.toFixed(1), drawMs: +r.drawMs.toFixed(2), renderer: r.renderer });
  }

  // Honest readPixels-synchronized per-act benchmarks for Q1, Q2, and Q3
  const bench_Q1 = await evalJs("window.benchTier(1)");
  const bench_Q2 = await evalJs("window.benchTier(2)");
  const bench_Q3 = await evalJs("window.benchTier(3)");

  // Non-tautological seamless loop verification across wrap boundary
  const loopCheck = await evalJs("window.verifyLoopSeam()");

  const result = {
    renderer: stats[0].renderer,
    resolution: "1280x720",
    compileMs_Q1: bench_Q1.compileMs,
    compileMs_Q2: bench_Q2.compileMs,
    compileMs_Q3: stats[0].compileMs,
    bench_Q1,
    bench_Q2,
    bench_Q3,
    loopCheck,
    framesRendered: stats.length,
  };

  fs.writeFileSync(JSON_OUT, JSON.stringify(result, null, 2) + "\n");
  console.log(JSON.stringify(result, null, 2));
} finally {
  if (pageWs) pageWs.close();
  proc.kill("SIGKILL");
  server.close();
  fs.rmSync(userDataDir, { recursive: true, force: true });
}
