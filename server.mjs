import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC_DIR = path.join(ROOT, "public");
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

function resolveSafePath(urlPath) {
  const clean = decodeURIComponent(urlPath.split("?")[0]);
  if (clean === "/" || clean === "") {
    return path.join(PUBLIC_DIR, "index.html");
  }
  if (clean.startsWith("/raw_clips/") || clean.startsWith("/shaders/")) {
    const candidate = path.resolve(ROOT, "." + clean);
    if (candidate.startsWith(ROOT + path.sep)) return candidate;
    return null;
  }
  const pubCandidate = path.resolve(PUBLIC_DIR, "." + clean);
  if (pubCandidate.startsWith(PUBLIC_DIR + path.sep)) return pubCandidate;
  return null;
}

const server = http.createServer((req, res) => {
  if (req.url?.startsWith("/api/telemetry")) {
    const bundledPath = path.join(PUBLIC_DIR, "gemini_video2glsl.glsl");
    const srcPath = path.join(ROOT, "shaders", "gemini_video2glsl.src.glsl");
    const vidPath = path.join(PUBLIC_DIR, "gemini-source-20s.mp4");
    const metricsPath = path.join(ROOT, "raw_clips", "metrics_latest.json");

    const bundledStat = fs.existsSync(bundledPath) ? fs.statSync(bundledPath) : null;
    const srcText = fs.existsSync(srcPath) ? fs.readFileSync(srcPath, "utf8") : "";
    const bundledText = bundledStat ? fs.readFileSync(bundledPath, "utf8") : "";
    const vidStat = fs.existsSync(vidPath) ? fs.statSync(vidPath) : null;
    const metrics = fs.existsSync(metricsPath) ? JSON.parse(fs.readFileSync(metricsPath, "utf8")) : null;

    res.writeHead(200, {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    });
    res.end(
      JSON.stringify({
        bundledBytes: bundledStat?.size ?? 0,
        bundledKB: bundledStat ? +(bundledStat.size / 1024).toFixed(1) : 0,
        bundledLines: bundledText ? bundledText.split("\n").length : 0,
        authoringLines: srcText ? srcText.split("\n").length : 0,
        videoBytes: vidStat?.size ?? 0,
        videoMB: vidStat ? +(vidStat.size / (1024 * 1024)).toFixed(2) : 0,
        loopSeconds: 20.0,
        texturesUsed: 0,
        videoFramesInShader: 0,
        metrics,
      })
    );
    return;
  }

  const filePath = resolveSafePath(req.url || "/");
  if (!filePath || !fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
    res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Not found");
    return;
  }

  const stat = fs.statSync(filePath);
  const ext = path.extname(filePath).toLowerCase();
  const contentType = MIME[ext] || "application/octet-stream";
  const range = req.headers.range;

  // Full RFC 7233 HTTP 206 Byte-Range support for instant frame-accurate HTML5 <video> seeking & seamless looping
  if (range) {
    const match = range.match(/bytes=(\d*)-(\d*)/);
    if (match) {
      const start = match[1] ? parseInt(match[1], 10) : 0;
      const end = match[2] ? Math.min(parseInt(match[2], 10), stat.size - 1) : stat.size - 1;
      if (start <= end && start < stat.size) {
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
    }
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
