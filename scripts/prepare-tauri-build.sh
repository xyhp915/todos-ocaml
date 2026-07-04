#!/bin/sh
set -eu

npm --prefix web run build
opam exec -- dune build app/tauri_store.exe

mkdir -p src-tauri/resources
cp _build/default/app/tauri_store.exe src-tauri/resources/tauri_store
chmod 755 src-tauri/resources/tauri_store

for target_resource in src-tauri/target/debug/tauri_store src-tauri/target/release/tauri_store; do
  if [ -e "$target_resource" ]; then
    chmod u+w "$target_resource"
  fi
done
