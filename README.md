# todos-ocaml

Cross-platform todo app built with `datascript-ocaml` for shared domain state,
`bonsai-native` for Apple UI, and Melange React for the web UI.

## What is included

- Shared todo state, actions, screen model, and DataScript store in
  `lib/todo_core.ml`.
- Native SQLite runtime adapter in `lib/todo_runtime.ml`.
- Native Apple UI in `lib/todo_ui.ml`.
- iOS SwiftUI entrypoint in `app/ios_app.ml`.
- macOS SwiftUI desktop entrypoint in `app/mac_app.ml`.
- Web UI in `web/`, with a SQLite wasm worker and Transit JSON codecs.
- Focused tests in `test/`.

## Local dependencies

The opam file pins the upgraded dependency revisions:

- `persistent_sorted_set_ocaml`: `074401d81ca22b9d44c725d7f171a67d69765a31`
- `datascript_ocaml`: `77994f1859acb36420de919e3f6487f9236ce92e`
- `bonsai_native` / `bonsai_apple`: `e8b6e13db0fba9ebf49a35591204e14f3e3b32e6`

```sh
opam install . --deps-only --with-test
```

## Test

```sh
opam exec --switch=simulator-5.4.1 -- dune runtest --workspace dune-workspace.simulator \
  _build/simulator/test/test_todo_ui.exe \
  _build/simulator/test/test_todo_model.exe
```

## Build iOS

Prepare the `simulator-5.4.1` switch using the Bonsai Native Apple build notes, then run:

```sh
IOS_TARGET=arm64-apple-ios17.0-simulator \
IOS_ARCH=arm64 \
IOS_SDKROOT=$(xcrun --sdk iphonesimulator --show-sdk-path) \
opam exec --switch=simulator-5.4.1 -- dune build --workspace dune-workspace.simulator \
  _build/simulator.ios/app/Todos.app
```

For a physical device, prepare the `device-5.4.1` switch and build with the iphoneos
SDK:

```sh
IOS_TARGET=arm64-apple-ios17.0 \
IOS_ARCH=arm64 \
IOS_SDKROOT=$(xcrun --sdk iphoneos --show-sdk-path) \
opam exec --switch=device-5.4.1 -- dune build --workspace dune-workspace.device \
  _build/device.ios/app/Todos.app
```

## Build macOS Desktop

```sh
opam exec --switch=simulator-5.4.1 -- dune build --workspace dune-workspace.simulator \
  _build/simulator/app/mac_app.exe
```

## Build Web

```sh
opam exec -- dune build @web-demo
cd web
npm install
npm run dev
```
