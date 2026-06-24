# todos-ocaml

Cross-platform todo app built with `datascript-ocaml` for shared domain state,
`bonsai-native` for Apple UI, and `bonsai_web`/`js_of_ocaml` for the web UI.

## What is included

- Shared todo state, actions, screen model, and DataScript store in
  `lib/todo_core.ml`.
- Native SQLite runtime adapter in `lib/todo_runtime.ml`.
- Native Apple UI in `lib/todo_ui.ml`.
- iOS SwiftUI entrypoint in `app/ios_app.ml`.
- macOS SwiftUI desktop entrypoint in `app/mac_app.ml`.
- Web UI and SQLite wasm worker in `web/`.
- Focused tests in `test/`.

## Local dependencies

The opam file pins the upgraded dependency revisions:

- `persistent_sorted_set_ocaml`: `83a3483bc6406337a1c0f60ac1813d8339a94c42`
- `datascript_ocaml`: `40308e1cd6573cdfa840a28518ed0fcac7f8832e`
- `bonsai_native` / `bonsai_apple`: `9a87d81f925ca617755cf3eb341cfd287a0750b3`

```sh
opam install . --deps-only --with-test
```

## Test

```sh
opam exec --switch=simulator -- dune runtest --workspace dune-workspace.simulator \
  _build/simulator/test/test_todo_ui.exe \
  _build/simulator/test/test_todo_model.exe
```

## Build iOS

Prepare the `simulator` switch using the Bonsai Native Apple build notes, then run:

```sh
IOS_TARGET=arm64-apple-ios17.0-simulator \
IOS_ARCH=arm64 \
IOS_SDKROOT=$(xcrun --sdk iphonesimulator --show-sdk-path) \
opam exec --switch=simulator -- dune build --workspace dune-workspace.simulator \
  _build/simulator.ios/app/Todos.app
```

For a physical device, prepare the `device` switch and build with the iphoneos
SDK:

```sh
IOS_TARGET=arm64-apple-ios17.0 \
IOS_ARCH=arm64 \
IOS_SDKROOT=$(xcrun --sdk iphoneos --show-sdk-path) \
opam exec --switch=device -- dune build --workspace dune-workspace.device \
  _build/device.ios/app/Todos.app
```

## Build macOS Desktop

```sh
opam exec --switch=simulator -- dune build --workspace dune-workspace.simulator \
  _build/simulator/app/mac_app.exe
```

## Build Web

```sh
opam exec -- dune build @web/build_web_static
python3 web/server.py
```
