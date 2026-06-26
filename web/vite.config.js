import { defineConfig } from "vite";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(fileURLToPath(import.meta.url));
const generatedNodeModules = path.join(root, "dist", "node_modules");

export default defineConfig({
  resolve: {
    alias: {
      bonsai_native: path.join(generatedNodeModules, "bonsai_native"),
      melange: path.join(generatedNodeModules, "melange"),
      "melange-edn": path.join(generatedNodeModules, "melange-edn"),
      "melange-transit": path.join(generatedNodeModules, "melange-transit"),
      "melange.js": path.join(generatedNodeModules, "melange.js"),
    },
  },
});
