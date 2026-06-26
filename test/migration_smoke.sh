#!/bin/sh
set -eu

repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$repo_root" ] || [ ! -f "$repo_root/web/package.json" ]; then
  script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
  repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
fi
cd "$repo_root"

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

if rg -n "Bonsai_native|Native\\.|render_json|hstack|vstack" web/todos_web.ml web/dune >/dev/null; then
  echo "Web UI should render with Melange React directly, not Bonsai Native nodes" >&2
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

test -s web/dist/web/todos_web.js
test -s web/dist/web/todos_db_worker.js

grep -q "New task" web/dist/web/todos_web.js
grep -q "Todos" web/dist/web/todos_web.js
grep -q "createRoot" web/dist/web/todos_web.js
if [ -e web/dist/web/react_runtime.js ] || [ -e web/dist/web/db_worker_client.js ]; then
  echo "Web dist should not include hand-written JS bridges outside worker runtime" >&2
  exit 1
fi
grep -q "@sqlite.org/sqlite-wasm" web/sqlite_worker_runtime.js
grep -q "melange-transit.melange/transit.js" web/dist/web/todos_web.js
test -s web/dist/node_modules/datascript_ocaml.melange_storage/datascript_melange_storage.js
grep -q "melange-transit.melange/transit.js" web/dist/node_modules/datascript_ocaml.melange_storage/datascript_melange_storage.js
grep -q "transit-js" web/dist/node_modules/melange-transit/transit.js
