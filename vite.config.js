import { defineConfig } from "vite";

// The Gleam compiler emits ES modules under build/dev/javascript/.
// `main.js` imports the compiled entry and Vite bundles the module graph.
// Static assets (css/, img/) are served from public/ — symlinked to the
// repo-root originals — so the existing stylesheet applies unchanged.
export default defineConfig({
  server: {
    port: process.env.PORT ? Number(process.env.PORT) : 5173,
    strictPort: false,
  },
  build: {
    outDir: "dist",
    emptyOutDir: true,
  },
});
