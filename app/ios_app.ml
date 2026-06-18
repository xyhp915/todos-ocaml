open! Core

module Swiftui = Bonsai_apple_swiftui

let app = ref None
let window = ref None

let install_root_view ~time_source app_delegate _application _launch_options =
  let swiftui_app = Swiftui.App.create ~time_source Todos.Todo_ui.component in
  Swiftui.App.flush_and_render swiftui_app;
  let root = Option.value_exn (Swiftui.App.view swiftui_app) in
  let root_window = Swiftui.window root in
  app := Some swiftui_app;
  window := Some root_window;
  ignore app_delegate;
  true
;;

let () =
  Swiftui.run_application
    (install_root_view ~time_source:(Bonsai.Time_source.create ~start:Time_ns.epoch))
;;
