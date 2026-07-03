#!/bin/sh
set -eu

repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$repo_root" ] || [ ! -f "$repo_root/web/package.json" ]; then
  script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
  repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
fi
cd "$repo_root"

require_file() {
  if [ ! -s "$1" ]; then
    echo "Missing required Tauri integration file: $1" >&2
    exit 1
  fi
}

require_file package.json
require_file src-tauri/Cargo.toml
require_file src-tauri/build.rs
require_file src-tauri/tauri.conf.json
require_file src-tauri/capabilities/default.json
require_file src-tauri/icons/icon.png
require_file src-tauri/src/main.rs
require_file app/tauri_store.ml
require_file web/vite.config.js

require_pattern() {
  pattern=$1
  path=$2
  message=$3
  if ! rg -q "$pattern" "$path"; then
    echo "$message" >&2
    exit 1
  fi
}

node <<'NODE'
const fs = require("node:fs");

function readJson(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

const rootPackage = readJson("package.json");
assert(rootPackage.private === true, "root package must be private");
assert(
  rootPackage.scripts?.["tauri:dev"] === "tauri dev",
  "root package must expose tauri:dev",
);
assert(
  rootPackage.scripts?.["tauri:build"] === "tauri build",
  "root package must expose tauri:build",
);
assert(
  rootPackage.devDependencies?.["@tauri-apps/cli"],
  "root package must depend on the Tauri CLI",
);

const webPackage = readJson("web/package.json");
assert(
  webPackage.scripts?.build === "opam exec -- dune build @web-demo",
  "web build must keep using the OCaml/Melange build",
);
assert(
  webPackage.scripts?.dev === "vite --host 127.0.0.1 --port 1420 --strictPort",
  "web dev server must match the Tauri dev URL",
);

const tauriConfig = readJson("src-tauri/tauri.conf.json");
assert(tauriConfig.productName === "Todos OCaml", "Tauri product name is wrong");
assert(
  tauriConfig.identifier === "dev.todos-ocaml.app",
  "Tauri identifier is wrong",
);
assert(
  tauriConfig.build?.beforeBuildCommand ===
    "npm --prefix web run build && opam exec -- dune build app/tauri_store.exe",
  "Tauri build must invoke the existing OCaml/Melange web build and native OCaml store build",
);
assert(
  tauriConfig.build?.beforeDevCommand ===
    "opam exec -- dune build app/tauri_store.exe && npm --prefix web run dev",
  "Tauri dev must build the native OCaml store before starting the React dev server",
);
assert(
  tauriConfig.build?.devUrl === "http://127.0.0.1:1420",
  "Tauri dev URL must match the Vite server",
);
assert(
  tauriConfig.build?.frontendDist === "../web",
  "Tauri frontendDist must reuse the existing web app assets",
);
assert(
  tauriConfig.app?.withGlobalTauri === true,
  "Tauri must expose global invoke APIs to the Melange React UI",
);
assert(
  tauriConfig.app?.windows?.[0]?.title === "Todos OCaml",
  "Tauri main window title is wrong",
);

const capability = readJson("src-tauri/capabilities/default.json");
assert(
  capability.windows?.includes("main"),
  "Tauri default capability must apply to the main window",
);
assert(
  capability.permissions?.includes("core:default"),
  "Tauri default capability must include core defaults",
);
NODE

require_pattern 'tauri::Builder::default\(\)' src-tauri/src "Tauri builder is missing"
require_pattern '#\[tauri::command\]' src-tauri/src "Tauri commands are missing"
require_pattern 'tauri_store' src-tauri/src "Rust bridge must launch the OCaml store daemon"
require_pattern 'Command::new' src-tauri/src "Rust bridge must spawn a native process"
require_pattern 'struct TauriStoreDaemon' src-tauri/src "Rust bridge must keep a daemon state object"
require_pattern 'Mutex<TauriStoreDaemon>' src-tauri/src "Rust bridge must protect the daemon with a mutex"
require_pattern 'child_stdin' src-tauri/src "Rust bridge must keep the daemon stdin open"
require_pattern 'BufReader' src-tauri/src "Rust bridge must read daemon stdout incrementally"
require_pattern 'send_command' src-tauri/src "Rust bridge must send commands to the daemon"
require_pattern '\.manage\(' src-tauri/src "Tauri app must manage the daemon state"
require_pattern 'tauri_build::build\(\)' src-tauri/build.rs "Tauri build script is missing"
require_pattern '\(name tauri_store\)' app/dune "Dune must build the OCaml Tauri store"
require_pattern 'todos_ocaml' app/dune "OCaml Tauri store must link shared todo runtime"
require_pattern 'Store.open_sqlite' app/tauri_store.ml "OCaml daemon must open the SQLite store"
require_pattern 'Store.apply_write' app/tauri_store.ml "OCaml daemon must apply shared todo writes"
require_pattern 'Store.list' app/tauri_store.ml "OCaml daemon must return todos from the shared store"
require_pattern 'read_line' app/tauri_store.ml "OCaml store must read daemon commands from stdin"
require_pattern 'daemon-loop' app/tauri_store.ml "OCaml store must run as a daemon loop"
require_pattern 'Tauri_store' web/todos_web.ml "Melange UI must include the Tauri store adapter"
require_pattern 'Web_store' web/todos_web.ml "Melange UI must keep the browser store adapter"
require_pattern 'melange-transit-melange' web/vite.config.js "Vite must alias the generated melange-transit package name"

if rg -n "React|todos_web|Todo_ui|Bonsai" src-tauri/src >/dev/null; then
  echo "Tauri shell must not duplicate the OCaml UI or business logic" >&2
  exit 1
fi
