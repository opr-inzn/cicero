#!/usr/bin/env node
// Draws docs/screenshot.png, the README's picture of Cicero, from the website's showcase: the live
// window on its warm grey panel, as cicero-website's showcase.js builds it, so it shows whatever the
// website's window shows. Update that window first when Cicero's look changes, then run this.
//
//     scripts/make-screenshot.mjs path/to/cicero-website [out.png]
//
// Builds the website into a temporary folder, serves it, and captures the panel at 2x in headless
// Chrome (CHROME overrides its path), in light mode and with reduced motion so the window stays on the
// grid it starts with, the page around the panel transparent so its rounded corners are see-through.
// Then it crops to the rows the panel covers and, if ImageOptim is installed, compresses the PNG with it.
// Needs Node 22 or newer (its fetch, WebSocket and zlib.crc32) and nothing else.
import { execFileSync, spawn } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { dirname, extname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { crc32, deflateSync, inflateSync } from "node:zlib";

const repo = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const [website, out = join(repo, "docs", "screenshot.png")] = process.argv.slice(2);
if (!website || !existsSync(join(website, "src", "scripts", "showcase.js"))) {
  console.error("Usage: scripts/make-screenshot.mjs path/to/cicero-website [out.png]");
  process.exit(1);
}
const chrome = process.env.CHROME ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const work = mkdtempSync(join(tmpdir(), "cicero-screenshot-"));
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

let server, browser;
try {
  const dist = join(work, "dist");
  try {
    execFileSync("npx", ["astro", "build", "--outDir", dist], { cwd: website, stdio: "pipe" });
  } catch (error) {
    process.stderr.write(error.stdout ?? "");
    process.stderr.write(error.stderr ?? "");
    throw new Error("The website didn't build.");
  }

  server = await serve(dist);
  const profile = join(work, "chrome");
  browser = spawn(chrome, ["--headless=new", "--remote-debugging-port=0", `--user-data-dir=${profile}`,
    "--hide-scrollbars", "--no-first-run", "--no-default-browser-check", "about:blank"], { stdio: "ignore" });
  const port = await debuggingPort(profile);

  const raw = await capture(port, `http://127.0.0.1:${server.address().port}/`);
  const png = cropToPanel(raw);
  writeFileSync(out, png.data);
  console.log(`Wrote ${out}, ${png.width}×${png.height}`);
  await optimize(out);
} finally {
  browser?.kill();
  server?.close();
  await wait(500);
  rmSync(work, { recursive: true, force: true });
}

// Serves the built website on a free port.
function serve(root) {
  const types = { ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript", ".css": "text/css",
    ".json": "application/json", ".svg": "image/svg+xml", ".png": "image/png", ".jpg": "image/jpeg",
    ".webp": "image/webp", ".ico": "image/x-icon", ".woff2": "font/woff2", ".woff": "font/woff",
    ".ttf": "font/ttf", ".otf": "font/otf", ".txt": "text/plain", ".xml": "application/xml" };
  const server = createServer((request, response) => {
    let path = join(root, decodeURIComponent(new URL(request.url, "http://localhost").pathname));
    if (!path.startsWith(root)) path = root;
    if (existsSync(path) && statSync(path).isDirectory()) path = join(path, "index.html");
    if (!existsSync(path)) return response.writeHead(404).end();
    response.writeHead(200, { "Content-Type": types[extname(path)] ?? "application/octet-stream" });
    response.end(readFileSync(path));
  });
  return new Promise((r) => server.listen(0, "127.0.0.1", () => r(server)));
}

// Chrome writes the port it picked to DevToolsActivePort in its profile.
async function debuggingPort(profile) {
  const file = join(profile, "DevToolsActivePort");
  for (let i = 0; i < 100; i++) {
    if (existsSync(file)) {
      const port = readFileSync(file, "utf8").split("\n")[0];
      if (port) return port;
    }
    await wait(100);
  }
  throw new Error(`Chrome didn't start (${chrome}).`);
}

// Loads the page and captures the showcase panel, with a couple of rows to spare above and below.
async function capture(port, url) {
  const target = await (await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: "PUT" })).json();
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((r) => ws.addEventListener("open", r, { once: true }));
  let id = 0;
  const pending = new Map();
  const listeners = [];
  ws.addEventListener("message", (event) => {
    const message = JSON.parse(event.data);
    if (message.id && pending.has(message.id)) {
      const { resolve, reject } = pending.get(message.id);
      pending.delete(message.id);
      message.error ? reject(new Error(JSON.stringify(message.error))) : resolve(message.result);
    } else if (message.method) listeners.forEach((listener) => listener(message));
  });
  const send = (method, params = {}) => new Promise((resolve, reject) => {
    pending.set(++id, { resolve, reject });
    ws.send(JSON.stringify({ id, method, params }));
  });
  const evaluate = async (expression) => {
    const result = await send("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true });
    if (result.exceptionDetails) throw new Error(JSON.stringify(result.exceptionDetails));
    return result.result.value;
  };

  await send("Page.enable");
  await send("Runtime.enable");
  await send("Emulation.setDeviceMetricsOverride", { width: 1440, height: 2400, deviceScaleFactor: 2, mobile: false });
  await send("Emulation.setEmulatedMedia", { features: [
    { name: "prefers-reduced-motion", value: "reduce" },
    { name: "prefers-color-scheme", value: "light" },
  ] });
  const loaded = new Promise((r) => listeners.push((m) => m.method === "Page.loadEventFired" && r()));
  await send("Page.navigate", { url });
  await loaded;
  await evaluate("document.fonts.ready.then(() => new Promise((r) => setTimeout(r, 2500)))");
  const rect = await evaluate(`(() => {
    const style = document.createElement("style");
    style.textContent = "html, body { background: transparent !important; }";
    document.head.append(style);
    const panel = document.querySelector("[data-stage]").parentElement;
    // The window's shadow runs past the panel's bottom; on the page it's lost in the white, here it would show.
    panel.style.overflow = "hidden";
    const r = panel.getBoundingClientRect();
    return { x: r.x + scrollX, y: r.y + scrollY, width: r.width, height: r.height };
  })()`);
  await send("Emulation.setDefaultBackgroundColorOverride", { color: { r: 0, g: 0, b: 0, a: 0 } });
  await wait(500);
  const shot = await send("Page.captureScreenshot", {
    format: "png",
    clip: { x: rect.x, y: Math.floor(rect.y) - 2, width: rect.width, height: Math.ceil(rect.height) + 4, scale: 1 },
    captureBeyondViewport: true,
  });
  ws.close();
  return Buffer.from(shot.data, "base64");
}

// Keeps the rows that are opaque in the middle, where the panel covers them fully: its top and bottom
// edges fall between pixels, so the rows they cross are only partly covered.
function cropToPanel(png) {
  const chunks = [];
  for (let at = 8; at < png.length;) {
    const length = png.readUInt32BE(at);
    chunks.push({ type: png.toString("latin1", at + 4, at + 8), data: png.subarray(at + 8, at + 8 + length) });
    at += 12 + length;
  }
  const header = chunks.find((c) => c.type === "IHDR").data;
  const width = header.readUInt32BE(0), height = header.readUInt32BE(4);
  if (header[8] !== 8 || header[9] !== 6 || header[12] !== 0) throw new Error("Expected an 8-bit RGBA PNG.");
  const filtered = inflateSync(Buffer.concat(chunks.filter((c) => c.type === "IDAT").map((c) => c.data)));
  const stride = width * 4;

  // Undo each row's filter (PNG's None, Sub, Up, Average and Paeth) to read the pixels.
  const pixels = Buffer.alloc(stride * height);
  for (let y = 0; y < height; y++) {
    const filter = filtered[y * (stride + 1)];
    const row = filtered.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    for (let i = 0; i < stride; i++) {
      const a = i >= 4 ? pixels[y * stride + i - 4] : 0;
      const b = y > 0 ? pixels[(y - 1) * stride + i] : 0;
      const c = i >= 4 && y > 0 ? pixels[(y - 1) * stride + i - 4] : 0;
      const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
      const predictor = [0, a, b, (a + b) >> 1, pa <= pb && pa <= pc ? a : pb <= pc ? b : c][filter];
      pixels[y * stride + i] = (row[i] + predictor) & 0xff;
    }
  }
  const middle = Math.floor(width / 2) * 4 + 3;
  const opaque = [...Array(height).keys()].filter((y) => pixels[y * stride + middle] === 255);
  const top = opaque[0], bottom = opaque.at(-1) + 1;
  if (opaque.length !== bottom - top) throw new Error("The panel isn't opaque all the way down.");

  // Each row keeps its filtered bytes, as they only refer to the row above, except the first, which
  // has no row above any more and is written unfiltered.
  const rows = [Buffer.concat([Buffer.from([0]), pixels.subarray(top * stride, (top + 1) * stride)])];
  rows.push(filtered.subarray((top + 1) * (stride + 1), bottom * (stride + 1)));
  const croppedHeader = Buffer.from(header);
  croppedHeader.writeUInt32BE(bottom - top, 4);
  const chunk = (type, data) => {
    const length = Buffer.alloc(4), crc = Buffer.alloc(4);
    length.writeUInt32BE(data.length);
    crc.writeUInt32BE(crc32(data, crc32(type)));
    return Buffer.concat([length, Buffer.from(type, "latin1"), data, crc]);
  };
  const data = Buffer.concat([png.subarray(0, 8), chunk("IHDR", croppedHeader),
    chunk("IDAT", deflateSync(Buffer.concat(rows), { level: 9 })), chunk("IEND", Buffer.alloc(0))]);
  return { data, width, height: bottom - top };
}

// Hands the file to ImageOptim, in the background, and waits until its tools have finished with it.
async function optimize(file) {
  if (!existsSync("/Applications/ImageOptim.app")) {
    console.log("ImageOptim isn't installed; the PNG is left as captured.");
    return;
  }
  const running = () => {
    try { execFileSync("pgrep", ["-x", "ImageOptim"]); return true; } catch { return false; }
  };
  const busy = () => {
    try { execFileSync("pgrep", ["-f", "ImageOptim.app/Contents/.*(pngquant|oxipng|zopfli|advpng|pngcrush|pngout)"]); return true; } catch { return false; }
  };
  const wasRunning = running();
  const before = statSync(file).size;
  execFileSync("open", ["-g", "-a", "ImageOptim", file]);
  let size = -1;
  for (const start = Date.now(); Date.now() - start < 240_000;) {
    await wait(5000);
    const now = statSync(file).size;
    // It may take a while to open; a file it couldn't make smaller stays the same size throughout.
    if (now === size && !busy() && (now !== before || Date.now() - start > 60_000)) break;
    size = now;
  }
  if (!wasRunning) execFileSync("osascript", ["-e", 'quit app "ImageOptim"']);
  console.log(`ImageOptim: ${Math.round(before / 1024)} KB → ${Math.round(statSync(file).size / 1024)} KB`);
}
