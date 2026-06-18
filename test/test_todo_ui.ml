open Core
open Todos

module Apple = Bonsai_apple
module Backend = Apple.For_testing.Backend
module Renderer = Apple.Renderer.Make (Backend)
module Test_app = Apple.App.Make (Backend)

let failf fmt = Printf.ksprintf failwith fmt

let assert_contains label text ~substring =
  if not (String.is_substring text ~substring)
  then failf "%s: expected output to contain %S, got:\n%s" label substring text
;;

let assert_not_contains label text ~substring =
  if String.is_substring text ~substring
  then failf "%s: expected output not to contain %S, got:\n%s" label substring text
;;

let render ?(model = Todo_ui.initial_model) () =
  Backend.reset ();
  let mounted =
    Renderer.mount
      ~schedule_event:(fun _ -> ())
      (Todo_ui.view model ~dispatch:(fun _action -> Bonsai.Effect.Ignore))
  in
  Backend.show (Renderer.view mounted)
;;

let test_renders_todos_tabs_and_dashboard () =
  let output = render () in
  assert_contains
    "tabs"
    output
    ~substring:
      "tabs=[today:Today:sun.max,upcoming:Upcoming:calendar,add:Add:plus,search:Search:magnifyingglass:search]";
  assert_contains "greeting" output ~substring:"Good morning";
  assert_contains
    "greeting font"
    output
    ~substring:"text_attributes=((style Title2) (weight Semibold) (color Primary))";
  assert_contains
    "section font"
    output
    ~substring:"text_attributes=((style Headline) (weight Semibold) (color Secondary))";
  assert_contains "today task" output ~substring:"Design onboarding flow";
  assert_contains "upcoming task" output ~substring:"Prepare presentation";
  assert_contains "native row" output ~substring:"list-row#";
  assert_contains
    "swipe actions"
    output
    ~substring:"actions=[Edit:default,Delete:destructive]";
  assert_contains "completed strikethrough" output ~substring:"strikethrough=true"
;;

let test_add_tab_opens_editor_without_selecting_add () =
  let model = Todo_ui.apply Todo_ui.initial_model (Select_tab "add") in
  let output = render ~model () in
  assert_contains "selected tab" output ~substring:"selected=today";
  assert_contains "editor sheet" output ~substring:"sheet:";
  assert_contains "new task title" output ~substring:"New Task"
;;

let test_list_tabs_do_not_install_search_fields () =
  let output = render () in
  assert_not_contains
    "today tab has no inline search field"
    output
    ~substring:"key=today modifiers=[searchable]";
  assert_not_contains
    "upcoming tab has no inline search field"
    output
    ~substring:"key=upcoming modifiers=[searchable]";
  let output =
    render
      ~model:(Todo_ui.apply Todo_ui.initial_model (Select_tab "search"))
      ()
  in
  assert_contains
    "search tab owns search field"
    output
    ~substring:"key=search modifiers=[searchable]"
;;

let test_component_updates_search_query_through_backend_event () =
  Backend.reset ();
  let app =
    Test_app.create
      ~time_source:(Bonsai.Time_source.create ~start:Time_ns.epoch)
      Todo_ui.component
  in
  Test_app.flush_and_render app;
  let root = Option.value_exn (Test_app.view app) in
  Backend.select_tab_exn root ~id:"search";
  Backend.change_search_exn root ~path:[ 3 ] ~text:"client";
  let output = Backend.show root in
  assert_contains "selected search tab" output ~substring:"selected=search";
  assert_contains "search query" output ~substring:"Reply to client email";
  assert_contains "search modifier" output ~substring:"key=search modifiers=[searchable"
;;

let () =
  test_renders_todos_tabs_and_dashboard ();
  test_add_tab_opens_editor_without_selecting_add ();
  test_list_tabs_do_not_install_search_fields ();
  test_component_updates_search_query_through_backend_event ()
;;
