import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { defineConfig } from "vite";

// The Gleam compiler emits ES modules under build/dev/javascript/.
// `main.js` imports the compiled entry and Vite bundles the module graph.
// Static assets (css/, audio/) are served from public/ — symlinked to the
// adarkroom-js/ originals — so the existing stylesheets apply unchanged.
export default defineConfig({
  server: {
    port: process.env.PORT ? Number(process.env.PORT) : 5173,
    strictPort: false,
  },
  build: {
    outDir: "dist",
    emptyOutDir: true,
  },
  plugins: [precacheServiceWorker()],
});

// The service worker can only make the first visit playable offline if it
// knows the hashed bundle's name up front. After the build, list the shell
// (page, bundle, stylesheets, icons) into dist/sw.js and derive the cache
// version from their contents, so each release installs a fresh cache and
// drops the last one. Audio and language catalogs stay runtime-cached: they
// are large, and only the ones a player actually uses are worth keeping.
function precacheServiceWorker() {
  let outDir;
  return {
    name: "precache-service-worker",
    apply: "build",
    configResolved(config) {
      outDir = path.resolve(config.root, config.build.outDir);
    },
    closeBundle() {
      const swPath = path.join(outDir, "sw.js");
      if (!fs.existsSync(swPath)) return;
      const shell = [];
      const walk = (dir) => {
        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
          const full = path.join(dir, entry.name);
          const rel = "/" + path.relative(outDir, full).split(path.sep).join("/");
          if (entry.isDirectory()) {
            if (rel === "/assets" || rel === "/css") walk(full);
          } else if (!["/sw.js", "/CNAME", "/index.html"].includes(rel)) {
            shell.push(rel);
          }
        }
      };
      walk(outDir);
      shell.sort();
      const hash = crypto.createHash("sha256");
      for (const file of shell) {
        hash.update(file);
        hash.update(fs.readFileSync(path.join(outDir, file)));
      }
      const version = "adr-" + hash.digest("hex").slice(0, 12);
      const sw = fs
        .readFileSync(swPath, "utf8")
        .replace(/const VERSION = "[^"]*";/, `const VERSION = "${version}";`)
        .replace(/const PRECACHE = \[[^\]]*\];/, `const PRECACHE = ${JSON.stringify(shell)};`);
      fs.writeFileSync(swPath, sw);
    },
  };
}
