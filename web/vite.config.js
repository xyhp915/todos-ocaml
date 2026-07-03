import { defineConfig } from "vite";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(fileURLToPath(import.meta.url));
const generatedNodeModules = path.join(root, "dist", "node_modules");

export default defineConfig({
  server: {
    headers: {
      "Cross-Origin-Opener-Policy": "same-origin",
      "Cross-Origin-Embedder-Policy": "require-corp",
      "Cross-Origin-Resource-Policy": "same-origin",
    },
  },
  resolve: {
    alias: {
      melange: path.join(generatedNodeModules, "melange"),
      "melange-edn": path.join(generatedNodeModules, "melange-edn"),
      "melange-transit": path.join(generatedNodeModules, "melange-transit"),
      "melange-transit-melange": path.join(
        generatedNodeModules,
        "melange-transit-melange",
      ),
      "melange.js": path.join(generatedNodeModules, "melange.js"),
    },
  },
});
