#!/bin/sh
set -eu

npm --prefix web run build
opam exec -- dune build app/tauri_store.exe

mkdir -p src-tauri/resources
cp _build/default/app/tauri_store.exe src-tauri/resources/tauri_store
chmod 755 src-tauri/resources/tauri_store

if [ -e src-tauri/target/release/tauri_store ]; then
  chmod u+w src-tauri/target/release/tauri_store
fi
