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
require_file src-tauri/src/native_sidebar.rs
require_file src-tauri/src/native_sidebar.swift
require_file app/tauri_store.ml
require_file web/vite.config.js
require_file scripts/prepare-tauri-build.sh

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
  webPackage.scripts?.build === "opam exec -- dune build @web-demo && vite build",
  "web build must build OCaml/Melange output and isolated Tauri assets",
);
assert(
  webPackage.scripts?.dev === "vite --host 127.0.0.1 --port 1420 --strictPort",
  "web dev server must match the Tauri dev URL",
);

const tauriConfig = readJson("src-tauri/tauri.conf.json");
assert(tauriConfig.productName === "Todos OCaml", "Tauri product name is wrong");
assert(
  tauriConfig.identifier === "dev.todos-ocaml.desktop",
  "Tauri identifier is wrong",
);
assert(
  tauriConfig.build?.beforeBuildCommand ===
    "sh scripts/prepare-tauri-build.sh",
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
  tauriConfig.build?.frontendDist === "../web/tauri-dist",
  "Tauri frontendDist must use isolated production assets",
);
assert(
  tauriConfig.app?.withGlobalTauri === true,
  "Tauri must expose global invoke APIs to the Melange React UI",
);
assert(
  tauriConfig.app?.windows?.[0]?.title === "Todos OCaml",
  "Tauri main window title is wrong",
);
assert(
  tauriConfig.bundle?.resources?.["resources/tauri_store"] === "tauri_store",
  "Tauri bundle must include the staged OCaml store daemon",
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
command_count=$(rg -n '#\[tauri::command\]' src-tauri/src | wc -l | tr -d ' ')
if [ "$command_count" != "2" ]; then
  echo "Rust should expose the generic OCaml command and one native menu chrome command" >&2
  exit 1
fi
require_pattern 'fn ocaml_request' src-tauri/src "Rust bridge must expose one generic ocaml_request command"
require_pattern 'fn show_todo_context_menu' src-tauri/src "Rust bridge must expose a native todo context menu command"
require_pattern 'generate_handler!\[' src-tauri/src "Tauri handler must register commands"
require_pattern 'ocaml_request,\s*$' src-tauri/src "Tauri handler must register OCaml IPC"
require_pattern 'show_todo_context_menu' src-tauri/src "Tauri handler must register native menu chrome"
if rg -n 'fn (load_todos|add_todo|toggle_todo|delete_todo)|"load_todos"|"add_todo"|"toggle_todo"|"delete_todo"' src-tauri/src web/todos_web.ml >/dev/null; then
  echo "Todo operations must not be duplicated as Rust Tauri commands" >&2
  exit 1
fi
require_pattern 'tauri_store' src-tauri/src "Rust bridge must launch the OCaml store daemon"
require_pattern 'Command::new' src-tauri/src "Rust bridge must spawn a native process"
require_pattern 'struct TauriStoreDaemon' src-tauri/src "Rust bridge must keep a daemon state object"
require_pattern 'Mutex<TauriStoreDaemon>' src-tauri/src "Rust bridge must protect the daemon with a mutex"
require_pattern 'child_stdin' src-tauri/src "Rust bridge must keep the daemon stdin open"
require_pattern 'BufReader' src-tauri/src "Rust bridge must read daemon stdout incrementally"
require_pattern 'send_command' src-tauri/src "Rust bridge must send commands to the daemon"
require_pattern '\.manage\(' src-tauri/src "Tauri app must manage the daemon state"
require_pattern 'tauri_build::build\(\)' src-tauri/build.rs "Tauri build script is missing"
require_pattern 'native_sidebar::install' src-tauri/src/lib.rs "Tauri setup must install the native AppKit sidebar"
require_pattern 'compile_native_swift' src-tauri/build.rs "Tauri build script must compile Swift native chrome helpers"
require_pattern 'native_search.swift' src-tauri/build.rs "Tauri build script must compile native search Swift"
require_pattern 'native_sidebar.swift' src-tauri/build.rs "Tauri build script must compile native sidebar Swift"
require_pattern 'NSSplitViewController' src-tauri/src/native_sidebar.swift "Native sidebar must use an actual NSSplitViewController"
require_pattern 'todos_native_sidebar_install' src-tauri/src/native_sidebar.rs "Rust sidebar bridge must call the Swift sidebar installer"
require_pattern '\(name tauri_store\)' app/dune "Dune must build the OCaml Tauri store"
require_pattern 'todos_ocaml' app/dune "OCaml Tauri store must link shared todo runtime"
require_pattern 'Store.open_sqlite' app/tauri_store.ml "OCaml daemon must open the SQLite store"
require_pattern 'Store.apply_write' app/tauri_store.ml "OCaml daemon must apply shared todo writes"
require_pattern 'Store.list' app/tauri_store.ml "OCaml daemon must return todos from the shared store"
require_pattern 'read_line' app/tauri_store.ml "OCaml store must read daemon commands from stdin"
require_pattern 'handle_request' app/tauri_store.ml "OCaml daemon must own request dispatch"
require_pattern 'daemon-loop' app/tauri_store.ml "OCaml store must run as a daemon loop"
require_pattern 'Tauri_store' web/todos_web.ml "Melange UI must include the Tauri store adapter"
require_pattern 'Web_store' web/todos_web.ml "Melange UI must keep the browser store adapter"
require_pattern 'setup_native_sidebar' web/todos_web.ml "Melange UI must connect native sidebar updates"
require_pattern 'show_todo_context_menu' web/todos_web.ml "Melange UI must request native todo context menus"
require_pattern 'tauri-native-sidebar' web/src/styles.css "Tauri web UI must hide its web sidebar when native sidebar is installed"
require_pattern 'melange-transit-melange' web/vite.config.js "Vite must alias the generated melange-transit package name"

if rg -n "React|todos_web|Todo_ui|Bonsai" src-tauri/src >/dev/null; then
  echo "Tauri shell must not duplicate the OCaml UI or business logic" >&2
  exit 1
fi
