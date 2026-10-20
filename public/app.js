const LOOP_SECONDS = 20.0;

const ACT_LABELS = [
  "ACT I · EMERALD CAUSTIC LAGOON & OBSIDIAN RING",
  "ACT II · SUNLIT ALPINE CANYON & CYAN OBELISK",
  "ACT III · BLUE-HOUR SKYLINE ORBIT & ART-DECO SPIRE",
  "ACT IV · BASALT SANCTUARY & TOTAL SOLAR ECLIPSE",
];

const DEBUG_LABELS = [
  "LIVE GPU FRAGMENT SHADER · 0 TEXTURES",
  "DEBUG 1 · SIGNED DISTANCE FIELD CONTOURS",
  "DEBUG 2 · WORLD-SPACE 3D NORMALS",
  "DEBUG 3 · PROCEDURAL MATERIAL IDS",
  "DEBUG 4 · RAYMARCH STEP HEATMAP",
  "DEBUG 5 · OPTICAL / MIST / FACADE MASKS",
  "DEBUG 6 · DIRECT SUNLIGHT & AO SPLIT",
];

const videoEl = document.getElementById("source-video");
const canvas = document.getElementById("glsl-canvas");
const viewportGrid = document.getElementById("viewport-grid");
const wipeDivider = document.getElementById("wipe-divider");
const compileOverlay = document.getElementById("compile-overlay");
const compileStatusText = document.getElementById("compile-status-text");
const activeActReadout = document.getElementById("active-act-readout");
const shaderPassBadge = document.getElementById("shader-pass-badge");
const orbitHint = document.getElementById("orbit-hint");

const timelineSlider = document.getElementById("timeline-slider");
const timecodeDisplay = document.getElementById("timecode-display");
const playToggleBtn = document.getElementById("play-toggle-btn");
const restartBtn = document.getElementById("restart-btn");
const loopWrapBtn = document.getElementById("loop-wrap-btn");
const syncModeBtn = document.getElementById("sync-mode-btn");
const resetOrbitBtn = document.getElementById("reset-orbit-btn");

const statShaderSize = document.getElementById("stat-shader-size");
const statShaderLines = document.getElementById("stat-shader-lines");
const statGpuFps = document.getElementById("stat-gpu-fps");
const statGpuRenderer = document.getElementById("stat-gpu-renderer");

const codeView = document.getElementById("glsl-code-view");
const copyGlslBtn = document.getElementById("copy-glsl-btn");

const gl = canvas.getContext("webgl2", {
  antialias: false,
  alpha: false,
  depth: false,
  stencil: false,
  powerPreference: "high-performance",
  preserveDrawingBuffer: true,
});

if (!gl) {
  compileStatusText.textContent = "WEBGL2 UNAVAILABLE";
  throw new Error("WebGL2 is required to run this shader.");
}

const parallelExt = gl.getExtension("KHR_parallel_shader_compile");
const dbgRendererExt = gl.getExtension("WEBGL_debug_renderer_info");
const gpuName = dbgRendererExt
  ? gl.getParameter(dbgRendererExt.UNMASKED_RENDERER_WEBGL)
  : gl.getParameter(gl.RENDERER);
statGpuRenderer.textContent = String(gpuName)
  .replace(/^ANGLE \(Apple,\s*/i, "")
  .replace(/,\s*Unspecified Version\)$/i, "")
  .slice(0, 38);

const state = {
  bundledSource: "",
  authorSource: "",
  showingFile: "bundled",
  viewMode: "side",
  quality: 2,
  debugMode: 0,
  syncToVideo: true,
  isPlaying: true,
  isScrubbing: false,
  standaloneTime: 0.0,
  lastFrameNow: performance.now(),
  frameIndex: 0,
  fpsAccum: 0,
  fpsFrames: 0,
  fpsLastUpdate: performance.now(),
  wipePct: 50,
  mouse: { x: 0, y: 0, clickX: 0, clickY: 0, dragging: false, hasOffset: false, accumX: 0, accumY: 0 },
  programs: new Map(),
  activeKey: null,
  pendingCompile: null,
};

const VERTEX_SHADER = `#version 300 es
void main() {
  vec2 p = vec2((gl_VertexID == 1) ? 3.0 : -1.0, (gl_VertexID == 2) ? 3.0 : -1.0);
  gl_Position = vec4(p, 0.0, 1.0);
}`;

function buildFragmentSource(debugMode, quality) {
  const patched = state.bundledSource
    .replace(/^#define\s+DEBUG_MODE\s+\d+/m, `#define DEBUG_MODE ${debugMode}`)
    .replace(/^#define\s+QUALITY\s+\d+/m, `#define QUALITY ${quality}`);

  return `#version 300 es
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
${patched}
void main() {
  mainImage(st_FragColor, gl_FragCoord.xy);
  st_FragColor.a = 1.0;
}`;
}

function getUniformLocations(prog) {
  return {
    iResolution: gl.getUniformLocation(prog, "iResolution"),
    iTime: gl.getUniformLocation(prog, "iTime"),
    iTimeDelta: gl.getUniformLocation(prog, "iTimeDelta"),
    iFrameRate: gl.getUniformLocation(prog, "iFrameRate"),
    iFrame: gl.getUniformLocation(prog, "iFrame"),
    iMouse: gl.getUniformLocation(prog, "iMouse"),
    iDate: gl.getUniformLocation(prog, "iDate"),
  };
}

function compileProgramAsync(debugMode, quality) {
  const key = `${debugMode}_${quality}`;
  if (state.programs.has(key)) {
    state.activeKey = key;
    compileOverlay.classList.remove("is-visible");
    return;
  }

  compileOverlay.classList.add("is-visible");
  compileStatusText.textContent = `COMPILING Q${quality} / DBG ${debugMode}...`;

  const tStart = performance.now();
  const vs = gl.createShader(gl.VERTEX_SHADER);
  gl.shaderSource(vs, VERTEX_SHADER);
  gl.compileShader(vs);

  const fs = gl.createShader(gl.FRAGMENT_SHADER);
  gl.shaderSource(fs, buildFragmentSource(debugMode, quality));
  gl.compileShader(fs);

  const prog = gl.createProgram();
  gl.attachShader(prog, vs);
  gl.attachShader(prog, fs);
  gl.linkProgram(prog);

  state.pendingCompile = { key, prog, vs, fs, tStart };
}

function pollPendingCompile() {
  if (!state.pendingCompile) return;
  const { key, prog, vs, fs, tStart } = state.pendingCompile;
  if (parallelExt) {
    const done = gl.getProgramParameter(prog, parallelExt.COMPLETION_STATUS_KHR);
    if (!done) return;
  }
  state.pendingCompile = null;
  compileOverlay.classList.remove("is-visible");

  if (!gl.getShaderParameter(fs, gl.COMPILE_STATUS)) {
    const log = gl.getShaderInfoLog(fs);
    console.error("Fragment compile error:", log);
    compileStatusText.textContent = "SHADER COMPILE ERROR";
    return;
  }
  if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
    console.error("Program link error:", gl.getProgramInfoLog(prog));
    compileStatusText.textContent = "SHADER LINK ERROR";
    return;
  }

  gl.deleteShader(vs);
  gl.deleteShader(fs);
  const ms = Math.round(performance.now() - tStart);
  state.programs.set(key, { prog, uniforms: getUniformLocations(prog), compileMs: ms });
  state.activeKey = key;
  compileStatusText.textContent = `COMPILED IN ${ms}ms · 0 ERRORS`;
}

function resizeCanvasIfNeeded() {
  const rect = canvas.getBoundingClientRect();
  const baseDpr = window.devicePixelRatio || 1;
  const dpr = state.quality >= 3 ? Math.min(baseDpr, 2.0) : state.quality === 2 ? Math.min(baseDpr, 1.15) : 0.75;
  const targetW = Math.max(320, Math.round(rect.width * dpr));
  const targetH = Math.max(180, Math.round(rect.height * dpr));
  if (canvas.width !== targetW || canvas.height !== targetH) {
    canvas.width = targetW;
    canvas.height = targetH;
  }
}

function getCurrentTimelineSeconds(dt) {
  if (state.syncToVideo && videoEl.readyState >= 1) {
    return videoEl.currentTime % LOOP_SECONDS;
  }
  if (state.isPlaying && !state.isScrubbing) {
    state.standaloneTime = (state.standaloneTime + dt) % LOOP_SECONDS;
  }
  return state.standaloneTime;
}

function updateTimelineUI(t) {
  const pct = (t / LOOP_SECONDS) * 100;
  if (!state.isScrubbing) {
    timelineSlider.value = t.toFixed(2);
  }
  timelineSlider.style.setProperty("--progress-pct", `${pct.toFixed(2)}%`);
  timecodeDisplay.textContent = `${t.toFixed(2).padStart(5, "0")}s / 20.00s`;

  const actIdx = Math.min(3, Math.floor(t / 5.0));
  activeActReadout.textContent = ACT_LABELS[actIdx];
  document.querySelectorAll(".act-btn").forEach((btn, idx) => {
    btn.classList.toggle("is-current", idx === actIdx);
  });
}

function renderLoop(now) {
  requestAnimationFrame(renderLoop);
  pollPendingCompile();

  const dt = Math.min(0.1, Math.max(0.0001, (now - state.lastFrameNow) / 1000));
  state.lastFrameNow = now;

  const entry = state.activeKey ? state.programs.get(state.activeKey) : null;
  if (!entry) return;

  resizeCanvasIfNeeded();
  const t = getCurrentTimelineSeconds(dt);
  updateTimelineUI(t);

  gl.viewport(0, 0, canvas.width, canvas.height);
  gl.useProgram(entry.prog);

  const u = entry.uniforms;
  gl.uniform3f(u.iResolution, canvas.width, canvas.height, 1.0);
  gl.uniform1f(u.iTime, t);
  gl.uniform1f(u.iTimeDelta, dt);
  gl.uniform1f(u.iFrameRate, 1.0 / dt);
  gl.uniform1i(u.iFrame, state.frameIndex++);

  // Support persistent 3D orbit angle even after releasing mouse button
  if (state.mouse.dragging || state.mouse.hasOffset) {
    const cx = canvas.width * 0.5;
    const cy = canvas.height * 0.5;
    gl.uniform4f(
      u.iMouse,
      cx + state.mouse.accumX * canvas.width,
      cy + state.mouse.accumY * canvas.height,
      cx,
      cy
    );
  } else {
    gl.uniform4f(u.iMouse, 0, 0, 0, 0);
  }

  const d = new Date();
  gl.uniform4f(
    u.iDate,
    d.getFullYear(),
    d.getMonth() + 1,
    d.getDate(),
    d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds()
  );

  gl.drawArrays(gl.TRIANGLES, 0, 3);

  state.fpsFrames++;
  state.fpsAccum += dt;
  if (now - state.fpsLastUpdate > 450) {
    const fps = state.fpsFrames / Math.max(state.fpsAccum, 1e-4);
    statGpuFps.textContent = `${Math.round(fps)} FPS`;
    state.fpsFrames = 0;
    state.fpsAccum = 0;
    state.fpsLastUpdate = now;
  }
}

// ---- Interactive 3D Camera Orbit on GLSL Canvas ----
let lastPtrX = 0;
let lastPtrY = 0;

canvas.addEventListener("pointerdown", (e) => {
  if (state.viewMode === "wipe") return; // In wipe mode, pointer drags the curtain
  canvas.setPointerCapture(e.pointerId);
  state.mouse.dragging = true;
  state.mouse.hasOffset = true;
  lastPtrX = e.clientX;
  lastPtrY = e.clientY;
});

canvas.addEventListener("pointermove", (e) => {
  if (!state.mouse.dragging) return;
  const rect = canvas.getBoundingClientRect();
  const dx = (e.clientX - lastPtrX) / Math.max(rect.width, 1);
  const dy = (e.clientY - lastPtrY) / Math.max(rect.height, 1);
  lastPtrX = e.clientX;
  lastPtrY = e.clientY;
  state.mouse.accumX = Math.max(-0.48, Math.min(0.48, state.mouse.accumX + dx));
  state.mouse.accumY = Math.max(-0.35, Math.min(0.35, state.mouse.accumY - dy));
  orbitHint.textContent = `3D Orbit Δ(${(state.mouse.accumX * 150).toFixed(0)}°, ${(state.mouse.accumY * 80).toFixed(0)}°) · Double-click to reset`;
});

window.addEventListener("pointerup", () => {
  state.mouse.dragging = false;
});

function resetOrbit() {
  state.mouse.accumX = 0;
  state.mouse.accumY = 0;
  state.mouse.hasOffset = false;
  orbitHint.textContent = "Drag to orbit 3D camera · Double-click to reset";
}

canvas.addEventListener("dblclick", resetOrbit);
resetOrbitBtn.addEventListener("click", resetOrbit);

// ---- Split-Curtain Wipe Interaction ----
let wipeDragging = false;
function updateWipeFromClientX(clientX) {
  const rect = viewportGrid.getBoundingClientRect();
  const pct = Math.max(2, Math.min(98, ((clientX - rect.left) / Math.max(rect.width, 1)) * 100));
  state.wipePct = pct;
  viewportGrid.style.setProperty("--wipe-pct", `${pct.toFixed(2)}%`);
}

wipeDivider.addEventListener("pointerdown", (e) => {
  wipeDragging = true;
  e.preventDefault();
});

viewportGrid.addEventListener("pointerdown", (e) => {
  if (state.viewMode !== "wipe") return;
  wipeDragging = true;
  updateWipeFromClientX(e.clientX);
});

window.addEventListener("pointermove", (e) => {
  if (!wipeDragging || state.viewMode !== "wipe") return;
  updateWipeFromClientX(e.clientX);
});

window.addEventListener("pointerup", () => {
  wipeDragging = false;
});

// ---- Controls: View Mode, Quality, Debug Mode, Playback & Seeking ----
function seekTo(seconds) {
  const clamped = ((seconds % LOOP_SECONDS) + LOOP_SECONDS) % LOOP_SECONDS;
  state.standaloneTime = clamped;
  if (videoEl.readyState >= 1) {
    videoEl.currentTime = clamped;
  }
  updateTimelineUI(clamped);
}

function setPlaying(playing) {
  state.isPlaying = playing;
  playToggleBtn.textContent = playing ? "Pause" : "Play";
  if (state.syncToVideo) {
    if (playing) {
      videoEl.play().catch(() => {});
    } else {
      videoEl.pause();
    }
  }
}

playToggleBtn.addEventListener("click", () => setPlaying(!state.isPlaying));
restartBtn.addEventListener("click", () => {
  seekTo(0.0);
  setPlaying(true);
});

loopWrapBtn.addEventListener("click", () => {
  seekTo(19.0);
  setPlaying(true);
});

syncModeBtn.addEventListener("click", () => {
  state.syncToVideo = !state.syncToVideo;
  if (state.syncToVideo) {
    syncModeBtn.textContent = "Clock: Video-Synced";
    videoEl.currentTime = state.standaloneTime;
    if (state.isPlaying) videoEl.play().catch(() => {});
  } else {
    state.standaloneTime = videoEl.currentTime % LOOP_SECONDS;
    videoEl.pause();
    syncModeBtn.textContent = "Clock: Pure GLSL Math (Video Paused)";
  }
});

timelineSlider.addEventListener("input", () => {
  state.isScrubbing = true;
  seekTo( parseFloat(timelineSlider.value) );
});

timelineSlider.addEventListener("change", () => {
  state.isScrubbing = false;
});

document.querySelectorAll(".act-btn").forEach((btn) => {
  btn.addEventListener("click", () => {
    seekTo(parseFloat(btn.dataset.seek || "0"));
  });
});

document.getElementById("view-mode-group").addEventListener("click", (e) => {
  const btn = e.target.closest("button[data-mode]");
  if (!btn) return;
  state.viewMode = btn.dataset.mode;
  document.querySelectorAll("#view-mode-group button").forEach((b) => b.classList.toggle("is-active", b === btn));
  viewportGrid.classList.toggle("mode-wipe", state.viewMode === "wipe");
  viewportGrid.classList.toggle("mode-solo", state.viewMode === "solo");
  resizeCanvasIfNeeded();
});

document.getElementById("quality-group").addEventListener("click", (e) => {
  const btn = e.target.closest("button[data-quality]");
  if (!btn) return;
  state.quality = Number(btn.dataset.quality);
  document.querySelectorAll("#quality-group button").forEach((b) => b.classList.toggle("is-active", b === btn));
  compileProgramAsync(state.debugMode, state.quality);
});

document.getElementById("debug-mode-group").addEventListener("click", (e) => {
  const btn = e.target.closest("button[data-debug]");
  if (!btn) return;
  state.debugMode = Number(btn.dataset.debug);
  shaderPassBadge.textContent = DEBUG_LABELS[state.debugMode] || DEBUG_LABELS[0];
  document.querySelectorAll("#debug-mode-group button").forEach((b) => b.classList.toggle("is-active", b === btn));
  compileProgramAsync(state.debugMode, state.quality);
});

window.addEventListener("keydown", (e) => {
  if (e.target && /^(INPUT|TEXTAREA)$/.test(e.target.tagName)) return;
  if (e.code === "Space") {
    e.preventDefault();
    setPlaying(!state.isPlaying);
  }
});

// ---- Raw Source Clips Hover Preview + Click Jump ----
[0, 1, 2, 3].forEach((idx) => {
  const card = document.getElementById(`raw-card-${idx + 1}`);
  const vid = document.getElementById(`raw-vid-${idx + 1}`);
  card.addEventListener("mouseenter", () => vid.play().catch(() => {}));
  card.addEventListener("mouseleave", () => {
    vid.pause();
    vid.currentTime = 0;
  });
  card.addEventListener("click", () => {
    seekTo(idx * 5.0 + 0.5);
    document.getElementById("stage-anchor").scrollIntoView({ behavior: "smooth" });
  });
});

// ---- Lightweight GLSL Syntax Highlighter & Code Switcher ----
function escapeHtml(str) {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function highlightGlsl(source) {
  return escapeHtml(source)
    .split("\n")
    .map((line, i) => {
      const ln = String(i + 1).padStart(4, " ");
      const commentIdx = line.indexOf("//");
      let codePart = commentIdx >= 0 ? line.slice(0, commentIdx) : line;
      const commentPart = commentIdx >= 0 ? `<span class="tok-comment">${line.slice(commentIdx)}</span>` : "";

      if (/^\s*#/.test(codePart)) {
        codePart = `<span class="tok-pre">${codePart}</span>`;
      } else {
        codePart = codePart
          .replace(
            /\b(const|void|float|int|bool|vec2|vec3|vec4|mat2|mat3|mat4|in|out|inout|if|else|for|return|break|continue|struct|uniform)\b/g,
            '<span class="tok-kw">$1</span>'
          )
          .replace(/\b(\d+\.\d+|\d+e[+-]?\d+|\d+)\b/g, '<span class="tok-num">$1</span>');
      }
      return `<span class="tok-comment">${ln} │ </span>${codePart}${commentPart}`;
    })
    .join("\n");
}

function renderCodePanel() {
  const raw = state.showingFile === "bundled" ? state.bundledSource : state.authorSource;
  codeView.innerHTML = highlightGlsl(raw);
}

document.getElementById("code-file-group").addEventListener("click", (e) => {
  const btn = e.target.closest("button[data-file]");
  if (!btn) return;
  state.showingFile = btn.dataset.file;
  document.querySelectorAll("#code-file-group button").forEach((b) => b.classList.toggle("is-active", b === btn));
  renderCodePanel();
});

document.querySelectorAll("button[data-find]").forEach((btn) => {
  btn.addEventListener("click", () => {
    const needle = btn.dataset.find;
    const raw = state.showingFile === "bundled" ? state.bundledSource : state.authorSource;
    const lines = raw.split("\n");
    const lineIdx = lines.findIndex((l) => l.includes(needle));
    if (lineIdx >= 0) {
      const ratio = lineIdx / Math.max(lines.length, 1);
      codeView.scrollTop = codeView.scrollHeight * ratio;
    }
  });
});

copyGlslBtn.addEventListener("click", async () => {
  await navigator.clipboard.writeText(state.bundledSource);
  const orig = copyGlslBtn.textContent;
  copyGlslBtn.textContent = "Copied Paste-Ready GLSL";
  setTimeout(() => {
    copyGlslBtn.textContent = orig;
  }, 1800);
});

// ---- Boot Application ----
async function init() {
  const [bundledRes, authorRes, telemetryRes] = await Promise.all([
    fetch("/gemini_video2glsl.glsl"),
    fetch("/shaders/gemini_video2glsl.src.glsl"),
    fetch("/api/telemetry"),
  ]);

  state.bundledSource = await bundledRes.text();
  state.authorSource = await authorRes.text();
  const telemetry = await telemetryRes.json();

  statShaderSize.textContent = `${telemetry.bundledKB} KB`;
  statShaderLines.textContent = `${telemetry.bundledLines.toLocaleString()} lines · 0 glslang errors`;

  renderCodePanel();
  compileProgramAsync(state.debugMode, state.quality);
  requestAnimationFrame(renderLoop);

  videoEl.play().catch(() => {
    // Fallback if autoplay needs gesture: shader still plays immediately!
    state.syncToVideo = false;
    syncModeBtn.textContent = "Clock: Pure GLSL Math (Autoplay Fallback)";
  });
}

init();
