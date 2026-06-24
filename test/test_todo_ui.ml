open Core

module Apple = Bonsai_apple
module Backend = Apple.For_testing.Backend
module Renderer = Apple.Renderer.Make (Backend)
module Todos = Todo_core

let failf fmt = Printf.ksprintf failwith fmt

let assert_contains label text ~substring =
  if not (String.is_substring text ~substring)
  then failf "%s: expected output to contain %S, got:\n%s" label substring text
;;

let todo ?(completed = false) ~id ~title ~created_at_ms () : Todos.Todo.t =
  { id; title; completed; created_at_ms }
;;

let render ?(controls = Todo_ui.default_controls) model =
  Backend.reset ();
  let controller : Todos.Controller.t =
    { model; dispatch = (fun _action -> Bonsai.Effect.Ignore) }
  in
  let mounted =
    Renderer.mount
      ~schedule_event:(fun _ -> ())
      (Todo_ui.view controller ~controls)
  in
  Backend.show (Renderer.view mounted)
;;

let test_empty_model_renders_split_view_composer_and_search () =
  let output = render Todos.Model.initial in
  assert_contains "all route" output ~substring:"Tasks";
  assert_contains "active route" output ~substring:"Active";
  assert_contains "completed route" output ~substring:"Completed";
  assert_contains "searchable" output ~substring:"searchable";
  assert_contains "composer" output ~substring:"placeholder=\"New task\""
;;

let test_loaded_model_renders_split_view_and_tasks () =
  let model =
    { Todos.Model.initial with
      todos =
        [ todo ~id:"todo-1" ~title:"iOS UI" ~created_at_ms:10 ()
        ; todo ~id:"todo-2" ~title:"Mac desktop" ~created_at_ms:20 ~completed:true ()
        ]
    }
  in
  let output = render model in
  assert_contains "split title" output ~substring:"Tasks";
  assert_contains "active task" output ~substring:"iOS UI";
  assert_contains "completed task" output ~substring:"Mac desktop";
  assert_contains "counts" output ~substring:"1 active, 1 completed"
;;

let test_search_filters_visible_tasks () =
  let model =
    { Todos.Model.initial with
      todos =
        [ todo ~id:"todo-1" ~title:"iOS UI" ~created_at_ms:10 ()
        ; todo ~id:"todo-2" ~title:"Web worker" ~created_at_ms:20 ()
        ]
    }
  in
  let controls = { Todo_ui.default_controls with search = "web" } in
  let output = render model ~controls in
  assert_contains "matching task" output ~substring:"Web worker";
  if String.is_substring output ~substring:"iOS UI"
  then failf "filtered output should not contain iOS UI, got:\n%s" output
;;

let () =
  test_empty_model_renders_split_view_composer_and_search ();
  test_loaded_model_renders_split_view_and_tasks ();
  test_search_filters_visible_tasks ()
;;
