open! Todo_std
module Todos = Todos.Todo_runtime

let fail message = failwith message

let require_equal_string actual expect =
  if not (String.equal actual expect) then
    failwith
      (Printf.sprintf "strings differ: actual=%S expect=%S" actual expect)

let require_equal_int actual expect =
  if actual <> expect then
    failwith (Printf.sprintf "ints differ: actual=%d expect=%d" actual expect)

let require_equal_bool actual expect =
  if actual <> expect then
    failwith (Printf.sprintf "bools differ: actual=%b expect=%b" actual expect)

let require_one_background_command commands =
  match commands with
  | [ { Todos.Command.target = Background; request } ] -> request
  | _ -> failwith "expected one background command"

let require_no_commands commands =
  match commands with [] -> () | _ -> failwith "expected no commands"

let todo ?(completed = false) ~id ~title ~created_at_ms () : Todos.Todo.t =
  { id; title; completed; created_at_ms }

let require_todo actual expected =
  require_equal_string actual.Todos.Todo.id expected.Todos.Todo.id;
  require_equal_string actual.title expected.title;
  require_equal_bool actual.completed expected.completed;
  require_equal_int actual.created_at_ms expected.created_at_ms

let require_todos actual expected =
  require_equal_int (List.length actual) (List.length expected);
  List.iter2_exn actual expected ~f:require_todo

let test_load_schedules_background_query () =
  let model, commands =
    Todos.Model.update Todos.Model.initial Todos.Action.Load
  in
  require_equal_bool model.is_loading true;
  require_equal_string (Option.value model.error ~default:"") "";
  match require_one_background_command commands with
  | Load_all -> ()
  | Persist _ | Subscribe_query _ | Unsubscribe_query _ ->
      fail "load must not issue a write"

let test_submit_trims_and_schedules_background_write () =
  let model =
    { Todos.Model.initial with draft = "  Ship cross-platform todos  " }
  in
  let model, commands =
    Todos.Model.update model
      (Todos.Action.Submit_new { id = "todo-1"; created_at_ms = 42 })
  in
  require_equal_string model.draft "";
  match require_one_background_command commands with
  | Persist (Add new_todo) ->
      require_todo new_todo
        (todo ~id:"todo-1" ~title:"Ship cross-platform todos" ~created_at_ms:42
           ())
  | Load_all | Persist _ | Subscribe_query _ | Unsubscribe_query _ ->
      fail "submit must issue an add write"

let test_blank_submit_is_ignored () =
  let model = { Todos.Model.initial with draft = "   " } in
  let model, commands =
    Todos.Model.update model
      (Todos.Action.Submit_new { id = "ignored"; created_at_ms = 1 })
  in
  require_equal_string model.draft "   ";
  require_no_commands commands

let test_toggle_and_delete_schedule_background_writes () =
  let existing = todo ~id:"todo-1" ~title:"Write tests" ~created_at_ms:10 () in
  let model, _ =
    Todos.Model.update Todos.Model.initial (Todos.Action.Loaded [ existing ])
  in
  let _, toggle_commands =
    Todos.Model.update model (Todos.Action.Toggle "todo-1")
  in
  (match require_one_background_command toggle_commands with
  | Persist (Toggle "todo-1") -> ()
  | _ -> fail "toggle must issue a toggle write");
  let _, delete_commands =
    Todos.Model.update model (Todos.Action.Delete "todo-1")
  in
  match require_one_background_command delete_commands with
  | Persist (Delete "todo-1") -> ()
  | _ -> fail "delete must issue a delete write"

let test_update_title_trims_and_schedules_background_write () =
  let model = { Todos.Model.initial with draft = "  Edited title  " } in
  let model, commands =
    Todos.Model.update model (Todos.Action.Update_title { id = "todo-1" })
  in
  require_equal_string model.draft "";
  match require_one_background_command commands with
  | Persist (Update_title { id = "todo-1"; title = "Edited title" }) -> ()
  | _ -> fail "update title must issue an update write"

let test_subscribe_and_unsubscribe_schedule_background_query_commands () =
  let model, commands =
    Todos.Model.update Todos.Model.initial
      (Todos.Action.Subscribe_query
         { id = "todos"; query = Todos.Query.List_todos })
  in
  require_todos model.todos [];
  (match require_one_background_command commands with
  | Subscribe_query { id = "todos"; query = Todos.Query.List_todos } -> ()
  | _ -> fail "subscribe must issue a query subscription command");
  let model, commands =
    Todos.Model.update model (Todos.Action.Unsubscribe_query "todos")
  in
  require_todos model.todos [];
  match require_one_background_command commands with
  | Unsubscribe_query "todos" -> ()
  | _ -> fail "unsubscribe must issue an unsubscribe command"

let test_loaded_and_failed_update_controller_state () =
  let loaded =
    [
      todo ~id:"todo-2" ~title:"Desktop UI" ~created_at_ms:20 ();
      todo ~id:"todo-1" ~title:"iOS UI" ~created_at_ms:10 ();
    ]
  in
  let model, commands =
    Todos.Model.update Todos.Model.initial (Todos.Action.Loaded loaded)
  in
  require_no_commands commands;
  require_equal_bool model.is_loading false;
  require_todos model.todos loaded;
  let model, commands =
    Todos.Model.update model (Todos.Action.Store_failed "sqlite failed")
  in
  require_no_commands commands;
  require_equal_bool model.is_loading false;
  require_equal_string (Option.value_exn model.error) "sqlite failed"

let test_datascript_store_roundtrip () =
  let open Todos.Store in
  let store = empty () in
  let store =
    apply_write store
      (Add (todo ~id:"todo-1" ~title:"iOS app" ~created_at_ms:10 ()))
  in
  let store =
    apply_write store
      (Add (todo ~id:"todo-2" ~title:"Mac app" ~created_at_ms:20 ()))
  in
  let store = apply_write store (Toggle "todo-2") in
  require_todos (list store)
    [
      todo ~id:"todo-1" ~title:"iOS app" ~created_at_ms:10 ();
      todo ~id:"todo-2" ~title:"Mac app" ~completed:true ~created_at_ms:20 ();
    ];
  let store = apply_write store (Delete "todo-1") in
  require_todos (list store)
    [ todo ~id:"todo-2" ~title:"Mac app" ~completed:true ~created_at_ms:20 () ]

let test_restore_or_create_reports_unreadable_non_empty_storage () =
  let storage : Todos.Store.Ds.storage =
    {
      storage_store = (fun _ -> ());
      storage_restore = (fun _ -> None);
      storage_list_addresses = (fun () -> [ "0" ]);
      storage_delete = (fun _ -> ());
    }
  in
  match Result.try_with (fun () -> Todos.Store.restore_or_create storage) with
  | Error _ -> ()
  | Ok _ -> fail "non-empty unreadable storage must not be recreated as empty"

let test_screen_model_filters_routes_search_and_selection () =
  let todos =
    [
      todo ~id:"todo-1" ~title:"iOS UI" ~created_at_ms:10 ();
      todo ~id:"todo-2" ~title:"Desktop UI" ~completed:true ~created_at_ms:20 ();
      todo ~id:"todo-3" ~title:"Web worker" ~created_at_ms:30 ();
    ]
  in
  let model = { Todos.Model.initial with todos } in
  let screen =
    Todos.Screen.create model ~route:Todos.Screen.Route.All ~search:"ui"
      ~selected_todo_id:"todo-2"
  in
  require_equal_string screen.title "Tasks";
  require_equal_int screen.active_count 2;
  require_equal_int screen.completed_count 1;
  require_todos screen.visible_todos
    [ List.nth_exn todos 0; List.nth_exn todos 1 ];
  (match screen.selected_todo with
  | Some selected -> require_todo selected (List.nth_exn todos 1)
  | None -> fail "selected todo missing");
  let active_screen =
    Todos.Screen.create model ~route:Todos.Screen.Route.Active ~search:""
      ~selected_todo_id:""
  in
  require_equal_string active_screen.title "Active";
  require_todos active_screen.visible_todos
    [ List.nth_exn todos 0; List.nth_exn todos 2 ];
  let completed_screen =
    Todos.Screen.create model ~route:Todos.Screen.Route.Completed ~search:""
      ~selected_todo_id:""
  in
  require_equal_string completed_screen.empty_title "No matching tasks";
  require_todos completed_screen.visible_todos [ List.nth_exn todos 1 ];
  let next = Todos.Screen.next_todo model in
  require_equal_string next.id "todo-31";
  require_equal_int next.created_at_ms 31

let test_sqlite_storage_roundtrip () =
  let open Todos.Store in
  let db_path = Stdlib.Filename.temp_file "todos-ocaml" ".sqlite" in
  Stdlib.Sys.remove db_path;
  let store = open_sqlite ~path:db_path in
  let store =
    apply_write store
      (Add (todo ~id:"todo-1" ~title:"Persist me" ~created_at_ms:100 ()))
  in
  require_todos (list store)
    [ todo ~id:"todo-1" ~title:"Persist me" ~created_at_ms:100 () ];
  let restored = open_sqlite ~path:db_path in
  require_todos (list restored)
    [ todo ~id:"todo-1" ~title:"Persist me" ~created_at_ms:100 () ];
  Stdlib.Sys.remove db_path

let test_runtime_executes_commands_against_sqlite () =
  let db_path = Stdlib.Filename.temp_file "todos-ocaml-runtime" ".sqlite" in
  Stdlib.Sys.remove db_path;
  let todo = todo ~id:"todo-1" ~title:"Runtime write" ~created_at_ms:500 () in
  (match
     Todos.Runtime.execute_command ~path:db_path
       { Todos.Command.target = Background; request = Persist (Add todo) }
   with
  | Loaded [ actual ] -> require_todo actual todo
  | _ -> fail "unexpected action");
  (match
     Todos.Runtime.execute_command ~path:db_path
       { Todos.Command.target = Background; request = Load_all }
   with
  | Loaded [ actual ] -> require_todo actual todo
  | _ -> fail "unexpected action");
  Stdlib.Sys.remove db_path

let test_runtime_notifies_query_subscribers_after_write () =
  let db_path = Stdlib.Filename.temp_file "todos-ocaml-subscribe" ".sqlite" in
  Stdlib.Sys.remove db_path;
  let received = ref [] in
  Todos.Runtime.subscribe_query ~path:db_path ~id:"test"
    ~query:Todos.Query.List_todos ~on_change:(fun action ->
      received := action :: !received);
  (match !received with
  | [ Loaded [] ] -> ()
  | _ -> fail "subscription must receive initial query result");
  let first =
    todo ~id:"todo-1" ~title:"Subscribed write" ~created_at_ms:700 ()
  in
  (match
     Todos.Runtime.execute_command ~path:db_path
       { Todos.Command.target = Background; request = Persist (Add first) }
   with
  | Loaded [ actual ] -> require_todo actual first
  | _ -> fail "unexpected action");
  (match !received with
  | [ Loaded [ actual ]; Loaded [] ] -> require_todo actual first
  | _ -> fail "subscription must receive updated query result");
  Todos.Runtime.unsubscribe_query ~path:db_path ~id:"test";
  let second = todo ~id:"todo-2" ~title:"No subscriber" ~created_at_ms:701 () in
  ignore
    (Todos.Runtime.execute_command ~path:db_path
       { Todos.Command.target = Background; request = Persist (Add second) }
      : Todos.Action.t);
  (match !received with
  | [ Loaded [ actual ]; Loaded [] ] -> require_todo actual first
  | _ -> fail "unsubscribed query must not receive updates");
  Stdlib.Sys.remove db_path

let () =
  [
    ("load schedules background query", test_load_schedules_background_query);
    ( "submit trims and writes in background",
      test_submit_trims_and_schedules_background_write );
    ("blank submit is ignored", test_blank_submit_is_ignored);
    ( "toggle and delete are background writes",
      test_toggle_and_delete_schedule_background_writes );
    ( "update title trims and writes in background",
      test_update_title_trims_and_schedules_background_write );
    ( "subscribe and unsubscribe are background query commands",
      test_subscribe_and_unsubscribe_schedule_background_query_commands );
    ( "loaded and failed update controller state",
      test_loaded_and_failed_update_controller_state );
    ("DataScript store roundtrip", test_datascript_store_roundtrip);
    ( "restore_or_create reports unreadable non-empty storage",
      test_restore_or_create_reports_unreadable_non_empty_storage );
    ( "screen model filters routes search and selection",
      test_screen_model_filters_routes_search_and_selection );
    ("SQLite storage roundtrip", test_sqlite_storage_roundtrip);
    ( "Runtime executes commands against SQLite",
      test_runtime_executes_commands_against_sqlite );
    ( "Runtime notifies query subscribers after write",
      test_runtime_notifies_query_subscribers_after_write );
  ]
  |> List.iter ~f:(fun (name, test) ->
      try test ()
      with exn ->
        Printf.eprintf "FAILED: %s\n%s\n" name (Exn.to_string exn);
        raise exn)
