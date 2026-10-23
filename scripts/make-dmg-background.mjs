#!/usr/bin/env node
// Draws the picture behind the DMG's window, Resources/DMG/background.png and its @2x, in the website's
// type and colours: a line that says what to do, and the two wells make-dmg.sh puts Cicero and the
// Applications folder into, an arrow between them. Run it again when the wording or the layout changes;
// the sizes here, the wells and the window and icon positions in dmg-settings.py go together.
//
//     scripts/make-dmg-background.mjs path/to/cicero-website
//
// Takes Mischief and ABC Areal from the website and renders the page in headless Chrome (CHROME
// overrides its path). Needs Node 22 or newer and nothing else.
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repo = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const [website] = process.argv.slice(2);
const fonts = website && join(website, "src", "assets", "fonts");
if (!fonts || !existsSync(join(fonts, "Mischief-Regular.woff2"))) {
  console.error("Usage: scripts/make-dmg-background.mjs path/to/cicero-website");
  process.exit(1);
}
const chrome = process.env.CHROME ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const font = (file) => `url(data:font/woff2;base64,${readFileSync(join(fonts, file)).toString("base64")}) format("woff2")`;

// In points. The layout keeps to the top 400, which the window always shows below the Finder's title and
// tab bars. The picture runs on in paper to the window's full height, so it fills the window whether or
// not the path and status bars are turned on, and Finder's white never shows below it.
const WIDTH = 660, LAYOUT = 400, HEIGHT = 68 + LAYOUT + 56;

const page = `<!doctype html>
<meta charset="utf-8">
<style>
  @font-face { font-family: Mischief; src: ${font("Mischief-Regular.woff2")}; }
  @font-face { font-family: Areal; src: ${font("ABCAreal-Regular.woff2")}; }
  html, body { margin: 0; width: ${WIDTH}px; height: ${HEIGHT}px; overflow: hidden; }
  body {
    position: relative; background: #fafaf8; color: #141413; text-align: center;
    -webkit-font-smoothing: antialiased; font-feature-settings: "liga" 1;
  }
  h1 { position: absolute; top: 40px; left: 0; right: 0; margin: 0; font: 32px/1.12 Mischief; letter-spacing: -.02em; }
  .lede { position: absolute; top: 88px; left: 0; right: 0; margin: 0; font: 14px/1.3 Areal; color: #6b6a66; }
  .well {
    position: absolute; top: 132px; width: 200px; height: 184px; border-radius: 24px;
    background: linear-gradient(#f1f0ec, #e6e5e0);
  }
  .arrow { position: absolute; top: 210px; left: 306px; }
  .needs { position: absolute; top: ${LAYOUT - 42}px; left: 0; right: 0; margin: 0; font: 12px/1 Areal; color: #a5a49f; }
</style>
<h1>Drag Cicero into Applications.</h1>
<p class="lede">Then open it from your Applications folder.</p>
<div class="well" style="left: 90px"></div>
<div class="well" style="left: 370px"></div>
<svg class="arrow" width="48" height="12" viewBox="0 0 48 12" fill="none" stroke="#a5a49f" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
  <path d="M1 6h45M41 1l5 5-5 5"/>
</svg>
<p class="needs">Requires macOS 15 or later on Apple silicon</p>
`;

const work = mkdtempSync(join(tmpdir(), "cicero-dmg-background-"));
try {
  const html = join(work, "background.html");
  writeFileSync(html, page);
  const out = join(repo, "Resources", "DMG");
  mkdirSync(out, { recursive: true });
  for (const [scale, name] of [[1, "background.png"], [2, "background@2x.png"]]) {
    const png = join(out, name);
    execFileSync(chrome, ["--headless=new", `--user-data-dir=${join(work, "chrome")}`, "--hide-scrollbars",
      "--no-first-run", "--no-default-browser-check", "--virtual-time-budget=5000",
      `--window-size=${WIDTH},${HEIGHT}`, `--force-device-scale-factor=${scale}`,
      `--screenshot=${png}`, `file://${html}`], { stdio: "pipe" });
    console.log(`Wrote ${png}`);
  }
} finally {
  rmSync(work, { recursive: true, force: true });
}
