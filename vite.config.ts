import { defineConfig } from "vite";

export default defineConfig({
  root: "web",                        // index.html lives in web/
  publicDir: "public",                // wasm file served from web/public/

  build: {
    outDir: "../dist",
    emptyOutDir: true,
  },

  server: {
    port: 5173,
    headers: {
      "Cross-Origin-Opener-Policy": "same-origin",
      "Cross-Origin-Embedder-Policy": "require-corp",
    },
  },
});