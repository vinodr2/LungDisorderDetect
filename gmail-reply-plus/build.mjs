// Build script for Gmail Reply+ (Manifest V3, TypeScript, ES modules).
// Uses esbuild to bundle each entry point and copies static assets into dist/.
//
//   node build.mjs           -> one-off production build
//   node build.mjs --watch   -> rebuild on change (dev)
//
// No framework, no 90-line webpack config: esbuild keeps builds sub-second.

import { build, context } from "esbuild";
import { cpSync, mkdirSync, rmSync, existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = __dirname;
const outdir = resolve(root, "dist");
const watch = process.argv.includes("--watch");

const shared = {
  bundle: true,
  sourcemap: watch ? "inline" : false,
  minify: !watch,
  target: ["chrome110"],
  logLevel: "info",
  legalComments: "none",
};

// The content script must be a classic script (IIFE) — MV3 content scripts do
// not support native ES module `import`. The service worker is a module worker.
// Options/popup are normal extension pages and load their JS as modules.
const entries = [
  { in: "src/content/index.ts", out: "content", format: "iife" },
  { in: "src/background/service-worker.ts", out: "service-worker", format: "esm" },
  { in: "src/options/options.ts", out: "options", format: "esm" },
  { in: "src/popup/popup.ts", out: "popup", format: "esm" },
];

/** Copy the static, non-bundled assets Chrome loads directly. */
function copyStatic() {
  mkdirSync(resolve(outdir, "icons"), { recursive: true });
  const files = [
    ["manifest.json", "manifest.json"],
    ["src/styles/content.css", "content.css"],
    ["src/options/options.html", "options.html"],
    ["src/options/options.css", "options.css"],
    ["src/popup/popup.html", "popup.html"],
    ["src/popup/popup.css", "popup.css"],
  ];
  for (const [from, to] of files) {
    const src = resolve(root, from);
    if (existsSync(src)) cpSync(src, resolve(outdir, to));
  }
  if (existsSync(resolve(root, "icons"))) {
    cpSync(resolve(root, "icons"), resolve(outdir, "icons"), { recursive: true });
  }
}

async function run() {
  rmSync(outdir, { recursive: true, force: true });
  mkdirSync(outdir, { recursive: true });

  const configs = entries.map((e) => ({
    ...shared,
    entryPoints: [resolve(root, e.in)],
    outfile: resolve(outdir, `${e.out}.js`),
    format: e.format,
  }));

  if (watch) {
    copyStatic();
    const ctxs = await Promise.all(configs.map((c) => context(c)));
    await Promise.all(ctxs.map((c) => c.watch()));
    console.log("👀 watching for changes — reload the extension in chrome://extensions after edits");
  } else {
    await Promise.all(configs.map((c) => build(c)));
    copyStatic();
    console.log("✅ build complete -> dist/");
  }
}

run().catch((err) => {
  console.error(err);
  process.exit(1);
});
