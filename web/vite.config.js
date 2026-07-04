import { defineConfig } from "vite";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(fileURLToPath(import.meta.url));
const generatedNodeModules = path.join(root, "dist", "node_modules");

export default defineConfig({
  base: "./",
  server: {
    headers: {
      "Cross-Origin-Opener-Policy": "same-origin",
      "Cross-Origin-Embedder-Policy": "require-corp",
      "Cross-Origin-Resource-Policy": "same-origin",
    },
  },
  resolve: {
    alias: {
      datascript_ocaml: path.join(generatedNodeModules, "datascript_ocaml"),
      "datascript_ocaml.melange_storage": path.join(
        generatedNodeModules,
        "datascript_ocaml.melange_storage",
      ),
      "datascript_ocaml.types": path.join(
        generatedNodeModules,
        "datascript_ocaml.types",
      ),
      melange: path.join(generatedNodeModules, "melange"),
      "melange-edn": path.join(generatedNodeModules, "melange-edn"),
      "melange-edn-melange": path.join(
        generatedNodeModules,
        "melange-edn-melange",
      ),
      "melange-transit": path.join(generatedNodeModules, "melange-transit"),
      "melange-transit-melange": path.join(
        generatedNodeModules,
        "melange-transit-melange",
      ),
      "melange.js": path.join(generatedNodeModules, "melange.js"),
      persistent_sorted_set_ocaml: path.join(
        generatedNodeModules,
        "persistent_sorted_set_ocaml",
      ),
      "todos_ocaml.core": path.join(
        generatedNodeModules,
        "todos_ocaml.core",
      ),
    },
  },
  optimizeDeps: {
    exclude: ["@sqlite.org/sqlite-wasm"],
  },
  build: {
    outDir: "tauri-dist",
    emptyOutDir: true,
  },
});
