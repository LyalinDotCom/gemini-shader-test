import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC_DIR = path.join(ROOT, "public");
const RAW_CLIPS_DIR = path.join(ROOT, "raw_clips");
const SHADERS_DIR = path.join(ROOT, "shaders");
const PORT = Number(process.env.PORT || 4173);

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".mjs": "application/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".glsl": "text/plain; charset=utf-8",
  ".mp4": "video/mp4",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
};

function countLines(text) {
  if (!text) return 0;
  const trimmed = text.endsWith("\n") ? text.slice(0, -1) : text;
  return trimmed.length === 0 ? 0 : trimmed.split("\n").length;
}

function readJsonSafe(filePath) {
  if (!fs.existsSync(filePath)) return null;
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return null;
  }
}

function resolveSafePath(urlPath) {
  let clean;
  try {
    clean = decodeURIComponent(urlPath.split("?")[0]);
  } catch {
    return { status: 400, filePath: null };
  }

  if (clean.includes("\0")) {
    return { status: 400, filePath: null };
  }
  if (clean === "/" || clean === "") {
    return { status: 200, filePath: path.join(PUBLIC_DIR, "index.html") };
  }

  if (clean.startsWith("/raw_clips/")) {
    const candidate = path.resolve(RAW_CLIPS_DIR, clean.slice("/raw_clips/".length));
    if (candidate.startsWith(RAW_CLIPS_DIR + path.sep)) {
      return { status: 200, filePath: candidate };
    }
    return { status: 403, filePath: null };
  }

  if (clean.startsWith("/shaders/")) {
    const candidate = path.resolve(SHADERS_DIR, clean.slice("/shaders/".length));
    if (candidate.startsWith(SHADERS_DIR + path.sep)) {
      return { status: 200, filePath: candidate };
    }
    return { status: 403, filePath: null };
  }

  const relPublic = clean.replace(/^\/+/, "");
  const pubCandidate = path.resolve(PUBLIC_DIR, relPublic);
  if (pubCandidate.startsWith(PUBLIC_DIR + path.sep)) {
    return { status: 200, filePath: pubCandidate };
  }
  return { status: 403, filePath: null };
}

function parseByteRange(rangeHeader, fileSize) {
  if (fileSize <= 0) return { valid: false };
  const match = /^bytes=(\d*)-(\d*)$/.exec(rangeHeader.trim());
  if (!match) return { valid: false };

  const [, startStr, endStr] = match;
  if (startStr === "" && endStr === "") return { valid: false };

  let start;
  let end;
  if (startStr === "") {
    // Suffix byte range: bytes=-N (last N bytes)
    const suffixLen = Number.parseInt(endStr, 10);
    if (!Number.isFinite(suffixLen) || suffixLen <= 0) return { valid: false };
    start = Math.max(0, fileSize - suffixLen);
    end = fileSize - 1;
  } else {
    start = Number.parseInt(startStr, 10);
    end = endStr === "" ? fileSize - 1 : Math.min(Number.parseInt(endStr, 10), fileSize - 1);
    if (!Number.isFinite(start) || !Number.isFinite(end) || start < 0 || start >= fileSize || start > end) {
      return { valid: false };
    }
  }
  return { valid: true, start, end };
}

const server = http.createServer((req, res) => {
  if (req.method !== "GET" && req.method !== "HEAD") {
    res.writeHead(405, { "Content-Type": "text/plain; charset=utf-8", Allow: "GET, HEAD" });
    res.end("Method Not Allowed");
    return;
  }

  const reqUrl = req.url || "/";
  if (reqUrl.split("?")[0] === "/api/telemetry") {
    const bundledPath = path.join(PUBLIC_DIR, "gemini_video2glsl.glsl");
    const srcPath = path.join(SHADERS_DIR, "gemini_video2glsl.src.glsl");
    const vidPath = path.join(PUBLIC_DIR, "gemini-source-20s.mp4");
    const metricsPath = path.join(RAW_CLIPS_DIR, "metrics_latest.json");
    const gpuEvalPath = path.join(RAW_CLIPS_DIR, "gpu_eval_latest.json");

    const bundledStat = fs.existsSync(bundledPath) ? fs.statSync(bundledPath) : null;
    const srcText = fs.existsSync(srcPath) ? fs.readFileSync(srcPath, "utf8") : "";
    const bundledText = bundledStat ? fs.readFileSync(bundledPath, "utf8") : "";
    const vidStat = fs.existsSync(vidPath) ? fs.statSync(vidPath) : null;
    const metrics = readJsonSafe(metricsPath);
    const gpuEval = readJsonSafe(gpuEvalPath);

    const payload = JSON.stringify({
      bundledBytes: bundledStat?.size ?? 0,
      bundledKB: bundledStat ? +(bundledStat.size / 1024).toFixed(1) : 0,
      bundledLines: countLines(bundledText),
      authoringLines: countLines(srcText),
      videoBytes: vidStat?.size ?? 0,
      videoMB: vidStat ? +(vidStat.size / (1024 * 1024)).toFixed(2) : 0,
      loopSeconds: 20.0,
      texturesUsed: 0,
      videoFramesInShader: 0,
      bakedBitmapsInShader: 0,
      metrics,
      gpuEval,
    });

    res.writeHead(200, {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "Content-Length": Buffer.byteLength(payload),
    });
    res.end(req.method === "HEAD" ? undefined : payload);
    return;
  }

  const resolved = resolveSafePath(reqUrl);
  if (resolved.status === 400) {
    res.writeHead(400, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Bad Request");
    return;
  }
  if (resolved.status === 403) {
    res.writeHead(403, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Forbidden");
    return;
  }

  const filePath = resolved.filePath;
  if (!filePath || !fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
    res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Not found");
    return;
  }

  const stat = fs.statSync(filePath);
  const ext = path.extname(filePath).toLowerCase();
  const contentType = MIME[ext] || "application/octet-stream";
  const range = req.headers.range;

  // RFC 7233 HTTP 206 Byte-Range support (including suffix ranges & 416 handling)
  if (range) {
    const parsed = parseByteRange(range, stat.size);
    if (!parsed.valid) {
      res.writeHead(416, {
        "Content-Range": `bytes */${stat.size}`,
        "Accept-Ranges": "bytes",
        "Content-Type": "text/plain; charset=utf-8",
      });
      res.end("Range Not Satisfiable");
      return;
    }
    const { start, end } = parsed;
    res.writeHead(206, {
      "Content-Range": `bytes ${start}-${end}/${stat.size}`,
      "Accept-Ranges": "bytes",
      "Content-Length": end - start + 1,
      "Content-Type": contentType,
      "Cache-Control": "no-cache",
    });
    if (req.method === "HEAD") {
      res.end();
    } else {
      fs.createReadStream(filePath, { start, end }).pipe(res);
    }
    return;
  }

  res.writeHead(200, {
    "Content-Length": stat.size,
    "Content-Type": contentType,
    "Accept-Ranges": "bytes",
    "Cache-Control": "no-cache",
  });
  if (req.method === "HEAD") {
    res.end();
  } else {
    fs.createReadStream(filePath).pipe(res);
  }
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`Gemini Video-2-GLSL Studio running at http://localhost:${PORT}`);
});
