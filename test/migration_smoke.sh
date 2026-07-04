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
    echo "Missing required file: $1" >&2
    exit 1
  fi
}

require_contains() {
  pattern=$1
  path=$2
  message=$3
  if ! grep -q "$pattern" "$path"; then
    echo "$message" >&2
    exit 1
  fi
}

require_any_contains() {
  path=$1
  message=$2
  shift 2
  for pattern in "$@"; do
    if grep -q "$pattern" "$path"; then
      return 0
    fi
  done
  echo "$message" >&2
  exit 1
}

require_any_file_contains() {
  message=$1
  shift
  while [ "$#" -gt 1 ]; do
    path=$1
    pattern=$2
    if [ -s "$path" ] && grep -q "$pattern" "$path"; then
      return 0
    fi
    shift 2
  done
  echo "$message" >&2
  exit 1
}

if grep -R "bonsai_web\\|js_of_ocaml\\|bonsai.ppx_bonsai" dune-project todos_ocaml.opam lib/dune web/dune >/dev/null; then
  echo "Dune/opam config should not depend on Bonsai Web, js_of_ocaml, or Bonsai ppx" >&2
  exit 1
fi

if grep -ER 'ppx_jane|core_kernel|"core"|\(core([[:space:]]|\))|^[[:space:]]*core([[:space:]]|\))' dune-project todos_ocaml.opam lib/dune app/dune test/dune >/dev/null; then
  echo "Dune/opam config should not depend on ppx_jane or Core" >&2
  exit 1
fi

if ! grep -R "melange-transit" dune-project todos_ocaml.opam >/dev/null; then
  echo "Dune/opam config should depend on melange-transit" >&2
  exit 1
fi

if ! grep -R "melange-transit" web/dune >/dev/null; then
  echo "Web demo should link melange-transit" >&2
  exit 1
fi

if ! grep -R "datascript_ocaml" web/dune >/dev/null; then
  echo "Web demo should link datascript-ocaml" >&2
  exit 1
fi

if ! grep -R "datascript_ocaml.melange_storage" web/dune >/dev/null; then
  echo "Web demo should link the datascript melange storage codec" >&2
  exit 1
fi

if ! grep -R "todos_ocaml.core" web/dune >/dev/null; then
  echo "Web demo should link the shared todo core in Melange" >&2
  exit 1
fi

for generated_package in \
  "datascript_ocaml" \
  "datascript_ocaml.melange_storage" \
  "persistent_sorted_set_ocaml" \
  "todos_ocaml.core"
do
  if ! grep -R "\"$generated_package\"" web/vite.config.js >/dev/null; then
    echo "Vite should alias generated package $generated_package from dist/node_modules" >&2
    exit 1
  fi
done

if [ -e lib/todo_datascript_sqlite_stubs.c ]; then
  echo "SQLite C stubs should live in datascript_ocaml.sqlite, not the app" >&2
  exit 1
fi

if rg -n "foreign_stubs|c_library_flags" lib/dune >/dev/null; then
  echo "App library should not own SQLite foreign stubs or C linker flags" >&2
  exit 1
fi

if ! grep -R "datascript_ocaml.sqlite" lib/dune >/dev/null; then
  echo "App library should link datascript_ocaml.sqlite" >&2
  exit 1
fi

if rg -n "Storage_codec|Todos_transit|todos_transit" lib test/*.ml >/dev/null; then
  echo "Transit storage codecs should live in datascript packages, not the app" >&2
  exit 1
fi

if rg -n "Storage_codec|external sqlite_|todos_ocaml_todos_sqlite" lib/todo_runtime.ml >/dev/null; then
  echo "Runtime should use datascript_ocaml.sqlite instead of app-level SQLite codecs or externals" >&2
  exit 1
fi

if rg -n "persistent_sorted_set_ocaml" dune-project todos_ocaml.opam lib/dune app/dune web/dune >/dev/null; then
  echo "App should not depend directly on persistent_sorted_set_ocaml" >&2
  exit 1
fi

if grep -R "localStorage\\|getItem\\|setItem" web/todos_web.ml >/dev/null; then
  echo "Web UI should not persist state directly in localStorage" >&2
  exit 1
fi

if rg -n "encode_todos|decode_todos|todos_to_transit|todo_to_transit|Transit_json" web/todos_web.ml >/dev/null; then
  echo "Browser web UI should not persist a serialized todo list; it should use the DataScript-backed worker store" >&2
  exit 1
fi

if rg -n "module Store = struct" web/todos_db_worker.ml >/dev/null; then
  echo "Browser web worker should use Todo_core.Store directly, not a local store facade" >&2
  exit 1
fi

if ! rg -n "Todo_core\\.Store\\.restore_or_create|Store\\.restore_or_create" web/todos_db_worker.ml >/dev/null; then
  echo "Browser web worker should restore the shared Todo_core.Store" >&2
  exit 1
fi

if ! rg -n "Todo_core\\.Store\\.apply_write|Store\\.apply_write" web/todos_db_worker.ml >/dev/null; then
  echo "Browser web worker should apply writes through the shared Todo_core.Store" >&2
  exit 1
fi

if ! rg -n "Todo_core\\.Store\\.list|Store\\.list" web/todos_db_worker.ml >/dev/null; then
  echo "Browser web worker should return todos from the shared Todo_core.Store" >&2
  exit 1
fi

if ! rg -n "storage_store|storage_restore|storage_list_addresses|Datascript_melange_storage\\.encode|Datascript_melange_storage\\.decode" web/todos_db_worker.ml >/dev/null; then
  echo "Browser web worker should expose SQLite wasm as a DataScript storage backend" >&2
  exit 1
fi

if rg -n "Bonsai_native|Native\\.|render_json|hstack|vstack" web/todos_web.ml web/dune >/dev/null; then
  echo "Web UI should render with Melange React directly, not Bonsai Native nodes" >&2
  exit 1
fi

if rg -n 'React\.text \(if todo\.completed then "✓"|â|œ|“' web/todos_web.ml web/dist/web/todos_web.js >/dev/null; then
  echo "Completed checkbox state should be rendered with CSS, not a text glyph" >&2
  exit 1
fi

if [ -e web/react_runtime.js ] || [ -e web/db_worker_client.js ]; then
  echo "Web should not keep hand-written JS bridges outside worker runtime" >&2
  exit 1
fi

if ! grep -R "todos_db_worker" web/dune web/todos_web.ml >/dev/null; then
  echo "Web demo should build and start the SQLite worker" >&2
  exit 1
fi

if ! grep -R "@sqlite.org/sqlite-wasm" web/package.json >/dev/null; then
  echo "Web demo should depend on SQLite wasm" >&2
  exit 1
fi

if rg -n "todos_ocaml_kv" lib web >/dev/null; then
  echo "SQLite storage table should be named kvs" >&2
  exit 1
fi

if ! rg -n "create table if not exists kvs" lib web >/dev/null; then
  echo "SQLite storage should create the kvs table" >&2
  exit 1
fi

if rg -n '/Users/|git\\+file|file://' dune-project todos_ocaml.opam app/dune lib/dune web/dune web/package.json README.md web/README.md >/dev/null; then
  echo "Project config and docs should not reference local filesystem dependencies" >&2
  exit 1
fi

if rg -n 'git\\+https://github.com/[^\"#]+\\.git\"' todos_ocaml.opam >/dev/null; then
  echo "GitHub pin-depends should include immutable commit hashes" >&2
  exit 1
fi

if ! grep -q '%{lib:bonsai_apple:' app/dune; then
  echo "Apple app should load Swift sources from installed bonsai_apple package data" >&2
  exit 1
fi

require_file web/dist/web/todos_web.js
require_file web/dist/web/todos_db_worker.js

require_contains "New task" web/dist/web/todos_web.js "Web dist should contain the task input placeholder"
require_contains "Todos" web/dist/web/todos_web.js "Web dist should contain the app title"
require_contains "createRoot" web/dist/web/todos_web.js "Web dist should render through React createRoot"
if [ -e web/dist/web/react_runtime.js ] || [ -e web/dist/web/db_worker_client.js ]; then
  echo "Web dist should not include hand-written JS bridges outside worker runtime" >&2
  exit 1
fi
require_contains "@sqlite.org/sqlite-wasm" web/sqlite_worker_runtime.js "SQLite worker runtime should import sqlite-wasm"
require_contains "optimizeDeps" web/vite.config.js "Vite config should customize dependency optimization"
require_contains "@sqlite.org/sqlite-wasm" web/vite.config.js "Vite config should exclude sqlite-wasm from dependency optimization"
require_any_file_contains "Web dist should import the generated melange-transit package" \
  web/dist/web/todos_web.js "melange-transit-melange/transit.js" \
  web/dist/web/todos_web.js "melange-transit.melange/transit.js" \
  web/dist/web/todos_db_worker.js "melange-transit-melange/transit.js" \
  web/dist/web/todos_db_worker.js "melange-transit.melange/transit.js" \
  web/dist/node_modules/datascript_ocaml.melange_storage/datascript_melange_storage.js "melange-transit-melange/transit.js" \
  web/dist/node_modules/datascript_ocaml.melange_storage/datascript_melange_storage.js "melange-transit.melange/transit.js"
require_any_contains web/dist/web/todos_db_worker.js \
  "Web worker dist should import the generated DataScript storage package" \
  "datascript_ocaml.melange_storage/datascript_melange_storage.js"
require_file web/dist/node_modules/datascript_ocaml.melange_storage/datascript_melange_storage.js
require_any_contains web/dist/node_modules/datascript_ocaml.melange_storage/datascript_melange_storage.js \
  "Datascript melange storage should import the generated melange-transit package" \
  "melange-transit-melange/transit.js" \
  "melange-transit.melange/transit.js"
require_any_file_contains "Generated melange-transit package should import transit-js" \
  web/dist/node_modules/melange-transit-melange/transit.js "transit-js" \
  web/dist/node_modules/melange-transit.melange/transit.js "transit-js"
