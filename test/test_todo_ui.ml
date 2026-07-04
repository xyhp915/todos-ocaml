open Todo_std
module Apple = Bonsai_apple
module Backend = Apple.For_testing.Backend
module Renderer = Apple.Renderer.Make (Backend)
module App = Apple.App.Make (Backend)
module Todos = Todo_core

let failf fmt = Printf.ksprintf failwith fmt

let assert_contains label text ~substring =
  if not (String.is_substring text ~substring) then
    failf "%s: expected output to contain %S, got:\n%s" label substring text

let assert_not_contains label text ~substring =
  if String.is_substring text ~substring then
    failf "%s: expected output not to contain %S, got:\n%s" label substring text

let count_substring text ~substring =
  let text_length = String.length text in
  let substring_length = String.length substring in
  let rec loop index count =
    if substring_length = 0 || index + substring_length > text_length then count
    else if String.sub text index substring_length = substring then
      loop (index + substring_length) (count + 1)
    else loop (index + 1) count
  in
  loop 0 0

let assert_occurrences label text ~substring ~count =
  let actual = count_substring text ~substring in
  if actual <> count then
    failf "%s: expected %d occurrences of %S, got %d:\n%s" label count substring
      actual text

let assert_no_empty_label label text =
  let has_empty_label =
    String.split_lines text
    |> List.exists ~f:(fun line ->
        String.is_substring line ~substring:"label#"
        && String.is_substring line ~substring:"text=\"\"")
  in
  if has_empty_label then
    failf "%s: expected output not to contain an empty label, got:\n%s" label
      text

let todo ?(completed = false) ~id ~title ~created_at_ms () : Todos.Todo.t =
  { id; title; completed; created_at_ms }

let render ?(controls = Todo_ui.default_controls) model =
  Backend.reset ();
  let controller : unit Apple.Action.t Todos.Controller.t =
    { model; dispatch = (fun _action -> Apple.Action.ignore) }
  in
  let mounted =
    Renderer.mount
      ~schedule_event:(fun _ -> ())
      (Todo_ui.view controller ~controls)
  in
  Backend.show (Renderer.view mounted)

let render_mobile ?(controls = Todo_ui.default_controls) model =
  Backend.reset ();
  let controller : unit Apple.Action.t Todos.Controller.t =
    { model; dispatch = (fun _action -> Apple.Action.ignore) }
  in
  let mounted =
    Renderer.mount
      ~schedule_event:(fun _ -> ())
      (Todo_ui.mobile_view controller ~controls)
  in
  Backend.show (Renderer.view mounted)

let render_adaptive ?(controls = Todo_ui.default_controls) model =
  Backend.reset ();
  let controller : unit Apple.Action.t Todos.Controller.t =
    { model; dispatch = (fun _action -> Apple.Action.ignore) }
  in
  let mounted =
    Renderer.mount
      ~schedule_event:(fun _ -> ())
      (Todo_ui.adaptive_view controller ~controls)
  in
  Backend.show (Renderer.view mounted)

let interactive_mobile_app ?(dispatched_commands = ref []) initial_model =
  Backend.reset ();
  let component graph =
    let model, set_model = Apple.state graph ~key:"model" initial_model in
    let route, set_route =
      Apple.state graph ~key:"route" Todos.Screen.Route.All
    in
    let search, set_search = Apple.state graph ~key:"search" "" in
    let selected_todo_id, set_selected_todo_id =
      Apple.state graph ~key:"selected-todo-id" ""
    in
    let mobile_tab, set_mobile_tab =
      Apple.state graph ~key:"mobile-tab" "today"
    in
    let mobile_new_task_presented, set_mobile_new_task_presented =
      Apple.state graph ~key:"mobile-new-task-presented" false
    in
    let editing_todo_id, set_editing_todo_id =
      Apple.state graph ~key:"editing-todo-id" ""
    in
    let visible_todo_limit, set_visible_todo_limit =
      Apple.state graph ~key:"visible-todo-limit"
        Todo_ui.default_controls.visible_todo_limit
    in
    let dispatch action () =
      let next_model, commands = Todos.Model.update model action in
      List.iter commands ~f:(fun command ->
          dispatched_commands := command :: !dispatched_commands);
      set_model next_model ()
    in
    Todo_ui.mobile_view { model; dispatch }
      ~controls:
        {
          route;
          search;
          selected_todo_id;
          mobile_tab;
          mobile_new_task_presented;
          editing_todo_id;
          visible_todo_limit;
          set_route;
          set_search;
          set_selected_todo_id;
          set_mobile_tab;
          set_mobile_new_task_presented;
          set_editing_todo_id;
          set_visible_todo_limit;
        }
  in
  let app = App.create component in
  App.flush_and_render app;
  match App.view app with
  | Some root -> root
  | None -> failwith "app did not render"

let take values ~count =
  let rec loop remaining values acc =
    match (remaining, values) with
    | 0, _ | _, [] -> List.rev acc
    | remaining, value :: values -> loop (remaining - 1) values (value :: acc)
  in
  if count <= 0 then [] else loop count values []

let drop values ~count =
  let rec loop remaining values =
    match (remaining, values) with
    | 0, values | _, ([] as values) -> values
    | remaining, _ :: values -> loop (remaining - 1) values
  in
  if count <= 0 then values else loop count values

let runtime_backed_mobile_app all_todos =
  Backend.reset ();
  let dispatched_commands = ref [] in
  let run_command ~dispatch command () =
    dispatched_commands := command :: !dispatched_commands;
    match command.Todos.Command.request with
    | Load_page { limit; offset; search } ->
        let search = String.strip search |> String.lowercase in
        let source =
          if String.is_empty search then all_todos
          else
            List.filter all_todos ~f:(fun todo ->
                String.is_substring
                  (String.lowercase todo.Todos.Todo.title)
                  ~substring:search)
        in
        dispatch
          (Todos.Action.Loaded_page
             {
               todos = source |> drop ~count:offset |> take ~count:limit;
               has_more = List.length source > offset + limit;
               offset;
               search;
             })
          ()
    | Persist _ -> ()
  in
  let component graph =
    let controller = Todo_ui.controller_component ~run_command graph in
    let route, set_route =
      Apple.state graph ~key:"route" Todos.Screen.Route.All
    in
    let search, set_search = Apple.state graph ~key:"search" "" in
    let selected_todo_id, set_selected_todo_id =
      Apple.state graph ~key:"selected-todo-id" ""
    in
    let mobile_tab, set_mobile_tab =
      Apple.state graph ~key:"mobile-tab" "today"
    in
    let mobile_new_task_presented, set_mobile_new_task_presented =
      Apple.state graph ~key:"mobile-new-task-presented" false
    in
    let editing_todo_id, set_editing_todo_id =
      Apple.state graph ~key:"editing-todo-id" ""
    in
    let visible_todo_limit, set_visible_todo_limit =
      Apple.state graph ~key:"visible-todo-limit"
        Todo_ui.default_controls.visible_todo_limit
    in
    let (_ : unit) =
      Bonsai_native.Graph.subscribe graph ~key:"todos-query-lifecycle"
        ~default:() (fun ~emit:_ ->
          controller.dispatch
            (Todos.Action.Load_page
               { limit = visible_todo_limit; offset = 0; search })
            ();
          fun () -> ())
    in
    Todo_ui.mobile_view controller
      ~controls:
        {
          route;
          search;
          selected_todo_id;
          mobile_tab;
          mobile_new_task_presented;
          editing_todo_id;
          visible_todo_limit;
          set_route;
          set_search;
          set_selected_todo_id;
          set_mobile_tab;
          set_mobile_new_task_presented;
          set_editing_todo_id;
          set_visible_todo_limit;
        }
  in
  let app = App.create component in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  (root, dispatched_commands)

let test_empty_model_renders_split_view_composer_and_search () =
  let output = render Todos.Model.initial in
  assert_contains "all route" output ~substring:"Tasks";
  assert_contains "active route" output ~substring:"Active";
  assert_contains "completed route" output ~substring:"Completed";
  assert_contains "searchable" output ~substring:"searchable";
  assert_contains "composer" output ~substring:"placeholder=\"New task\"";
  assert_contains "split root" output ~substring:"navigation-split"

let test_loaded_model_renders_split_view_and_tasks () =
  let model =
    {
      Todos.Model.initial with
      todos =
        [
          todo ~id:"todo-1" ~title:"iOS UI" ~created_at_ms:10 ();
          todo ~id:"todo-2" ~title:"Mac desktop" ~created_at_ms:20
            ~completed:true ();
        ];
    }
  in
  let output = render model in
  assert_contains "split title" output ~substring:"Tasks";
  assert_contains "active task" output ~substring:"iOS UI";
  assert_contains "completed task" output ~substring:"Mac desktop";
  assert_contains "counts" output ~substring:"1 active, 1 completed"

let test_mobile_model_renders_tabbed_phone_ui () =
  let model =
    {
      Todos.Model.initial with
      todos =
        [
          todo ~id:"todo-1" ~title:"iOS UI" ~created_at_ms:10 ();
          todo ~id:"todo-2" ~title:"Done task" ~created_at_ms:20 ~completed:true
            ();
        ];
    }
  in
  let output = render_mobile model in
  assert_contains "mobile tabs" output ~substring:"tab-view";
  assert_contains "today tab" output ~substring:"today:Today:sun.max";
  assert_contains "upcoming tab" output ~substring:"upcoming:Upcoming:calendar";
  assert_contains "add tab" output ~substring:"add:Add:plus";
  assert_contains "search tab" output
    ~substring:"search:Search:magnifyingglass:search";
  assert_contains "dashboard greeting" output ~substring:"Good morning";
  assert_contains "dashboard subtitle" output
    ~substring:"Let's get things done.";
  assert_contains "shared row" output ~substring:"iOS UI";
  assert_contains "mobile uses native list" output ~substring:"list#";
  assert_contains "mobile uses native list rows" output ~substring:"list-row#";
  assert_occurrences "mobile root has one sheet modifier" output
    ~substring:"sheet" ~count:1;
  assert_not_contains "mobile does not show inline composer" output
    ~substring:"placeholder=\"New task\"";
  assert_not_contains "mobile fixed input width" output
    ~substring:"modifiers=[frame]";
  assert_no_empty_label "mobile empty error gap" output;
  if String.is_substring output ~substring:"navigation-split" then
    failf "mobile output should not render navigation-split, got:\n%s" output

let test_mobile_search_tab_owns_searchable_modifier () =
  let controls =
    { Todo_ui.default_controls with route = Todos.Screen.Route.Completed }
  in
  let output = render_mobile Todos.Model.initial ~controls in
  assert_contains "search tab exists" output
    ~substring:"search:Search:magnifyingglass:search";
  assert_not_contains "inactive search tab is not built eagerly" output
    ~substring:"searchable"

let test_mobile_selected_search_tab_keeps_searchable_on_search_content () =
  let controls = { Todo_ui.default_controls with mobile_tab = "search" } in
  let output = render_mobile Todos.Model.initial ~controls in
  assert_contains "search tab selected" output
    ~substring:"tab-view#1 selected=search";
  assert_contains "search tab content owns searchable" output
    ~substring:"key=search modifiers=[searchable"

let test_mobile_rows_support_edit_and_delete_swipes () =
  let model =
    {
      Todos.Model.initial with
      todos = [ todo ~id:"todo-1" ~title:"Editable task" ~created_at_ms:10 () ];
    }
  in
  let output = render_mobile model in
  assert_contains "row edit action" output ~substring:"actions=[Edit";
  assert_contains "row delete action" output ~substring:"Delete:destructive"

let test_mobile_large_dataset_renders_initial_window_only () =
  let todos =
    Stdlib.List.init 10_000 (fun index ->
        let created_at_ms = index + 1 in
        todo
          ~id:(Printf.sprintf "todo-%05d" created_at_ms)
          ~title:(Printf.sprintf "Task %05d" created_at_ms)
          ~created_at_ms ())
  in
  let output = render_mobile { Todos.Model.initial with todos } in
  assert_contains "first visible task" output ~substring:"Task 00001";
  assert_contains "last initial task" output ~substring:"Task 00080";
  assert_not_contains "outside initial task window" output
    ~substring:"Task 00081";
  assert_occurrences "initial mobile rows" output ~substring:"list-row#"
    ~count:80

let test_mobile_large_dataset_toggles_first_visible_row_in_place () =
  let todos =
    Stdlib.List.init 100 (fun index ->
        let created_at_ms = index + 1 in
        todo
          ~id:(Printf.sprintf "todo-%05d" created_at_ms)
          ~title:(Printf.sprintf "Task %05d" created_at_ms)
          ~created_at_ms ())
  in
  let root = interactive_mobile_app { Todos.Model.initial with todos } in
  Backend.click_row_leading_exn root ~path:[ 0; 1; 0; 0 ];
  let output = Backend.show root in
  assert_contains "toggled row remains visible" output
    ~substring:"title=\"Task 00001\"";
  assert_contains "toggled row is completed" output
    ~substring:"trailing=\"Done\"";
  assert_contains "toggled row has selected leading button" output
    ~substring:"leading=circle:true"

let test_mobile_edit_sheet_save_updates_title () =
  let root =
    interactive_mobile_app
      {
        Todos.Model.initial with
        todos =
          [ todo ~id:"todo-1" ~title:"Editable task" ~created_at_ms:10 () ];
      }
  in
  Backend.click_row_action_exn root ~path:[ 0; 1; 0; 0 ] ~title:"Edit";
  Backend.change_sheet_text_exn root ~path:[] ~sheet_path:[ 1 ]
    ~text:"Renamed task";
  Backend.click_sheet_exn root ~path:[] ~sheet_path:[ 2; 1 ];
  let output = Backend.show root in
  assert_contains "edited title visible" output ~substring:"Renamed task";
  assert_not_contains "old title replaced" output ~substring:"Editable task"

let test_mobile_loads_more_when_bottom_sentinel_appears () =
  let dispatched_commands = ref [] in
  let todos =
    Stdlib.List.init 200 (fun index ->
        let created_at_ms = index + 1 in
        todo
          ~id:(Printf.sprintf "todo-%05d" created_at_ms)
          ~title:(Printf.sprintf "Task %05d" created_at_ms)
          ~created_at_ms ())
  in
  let root =
    interactive_mobile_app ~dispatched_commands
      { Todos.Model.initial with todos }
  in
  assert_occurrences "initial rows" (Backend.show root) ~substring:"list-row#"
    ~count:80;
  Backend.appear_exn root ~path:[ 0; 1; 0; 80 ];
  (match !dispatched_commands with
  | {
      Todos.Command.request = Load_page { limit = 80; offset = 80; search = "" };
      _;
    }
    :: _ ->
      ()
  | _ -> failf "load-more should dispatch the next fixed-size page");
  let output = Backend.show root in
  assert_contains "newly visible page" output ~substring:"Task 00160";
  assert_occurrences "rows after sentinel appears" output ~substring:"list-row#"
    ~count:160

let test_mobile_runtime_backed_load_more_loads_next_window () =
  let all_todos =
    Stdlib.List.init 10_000 (fun index ->
        let created_at_ms = index + 1 in
        todo
          ~id:(Printf.sprintf "todo-%05d" created_at_ms)
          ~title:(Printf.sprintf "Task %05d" created_at_ms)
          ~created_at_ms ())
  in
  let root, dispatched_commands = runtime_backed_mobile_app all_todos in
  let initial_output = Backend.show root in
  assert_contains "initial window last task" initial_output
    ~substring:"Task 00080";
  assert_contains "initial sentinel is keyed by next page" initial_output
    ~substring:"key=load-more-80";
  assert_not_contains "initial window excludes next page" initial_output
    ~substring:"Task 00081";
  assert_occurrences "initial runtime-backed rows" initial_output
    ~substring:"list-row#" ~count:80;
  Backend.appear_exn root ~path:[ 0; 1; 0; 80 ];
  (match !dispatched_commands with
  | {
      Todos.Command.request = Load_page { limit = 80; offset = 80; search = "" };
      _;
    }
    :: _ ->
      ()
  | _ -> failf "runtime-backed load-more should request the second page");
  let output = Backend.show root in
  assert_contains "loaded next window" output ~substring:"Task 00160";
  assert_contains "next sentinel is remounted for the following window" output
    ~substring:"key=load-more-160";
  assert_not_contains "does not render beyond requested window" output
    ~substring:"Task 00161";
  assert_not_contains "never renders full dataset" output
    ~substring:"Task 10000";
  assert_occurrences "runtime-backed rows after load-more" output
    ~substring:"list-row#" ~count:160;
  Backend.appear_exn root ~path:[ 0; 1; 0; 160 ];
  (match !dispatched_commands with
  | {
      Todos.Command.request =
        Load_page { limit = 80; offset = 160; search = "" };
      _;
    }
    :: _ ->
      ()
  | _ -> failf "second runtime-backed load-more should request the third page");
  let output = Backend.show root in
  assert_contains "loaded third window" output ~substring:"Task 00240";
  assert_contains "third sentinel is remounted for the following window" output
    ~substring:"key=load-more-240";
  assert_not_contains "third window stays bounded" output
    ~substring:"Task 00241";
  assert_occurrences "runtime-backed rows after second load-more" output
    ~substring:"list-row#" ~count:240

let test_mobile_runtime_backed_load_more_keeps_rendered_rows_capped () =
  let all_todos =
    Stdlib.List.init 10_000 (fun index ->
        let created_at_ms = index + 1 in
        todo
          ~id:(Printf.sprintf "todo-%05d" created_at_ms)
          ~title:(Printf.sprintf "Task %05d" created_at_ms)
          ~created_at_ms ())
  in
  let root, dispatched_commands = runtime_backed_mobile_app all_todos in
  let load_more () =
    let output = Backend.show root in
    let row_count = count_substring output ~substring:"list-row#" in
    Backend.appear_exn root ~path:[ 0; 1; 0; row_count ]
  in
  for _ = 1 to 8 do
    load_more ()
  done;
  let output = Backend.show root in
  assert_contains "later page remains visible" output ~substring:"Task 00720";
  assert_not_contains "oldest rows are trimmed from render tree" output
    ~substring:"Task 00001";
  assert_occurrences "rendered rows stay capped after many pages" output
    ~substring:"list-row#" ~count:240;
  match !dispatched_commands with
  | {
      Todos.Command.request =
        Load_page { limit = 80; offset = 640; search = "" };
      _;
    }
    :: _ ->
      ()
  | _ -> failf "load-more should keep requesting fixed-size pages"

let test_component_initial_load_uses_bounded_window_only () =
  Backend.reset ();
  let commands = ref [] in
  let run_command ~dispatch:_ command () = commands := command :: !commands in
  let app = App.create (Todo_ui.adaptive_component ~run_command) in
  App.flush_and_render app;
  match !commands with
  | [
   { Todos.Command.request = Load_page { limit; offset = 0; search = "" }; _ };
  ]
    when limit = Todo_ui.default_controls.visible_todo_limit ->
      ()
  | commands ->
      let rendered =
        commands
        |> List.map ~f:(fun command ->
            match command.Todos.Command.request with
            | Load_page { limit; offset; search } ->
                Printf.sprintf "Load_page %d offset=%d search=%S" limit offset
                  search
            | Persist _ -> "Persist")
        |> Stdlib.String.concat ", "
      in
      failf "initial load should only use a bounded page, got: %s" rendered

let test_search_change_dispatches_bounded_db_query () =
  Backend.reset ();
  let commands = ref [] in
  let run_command ~dispatch:_ command () = commands := command :: !commands in
  let app = App.create (Todo_ui.component ~run_command) in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  Backend.change_search_exn root ~path:[] ~text:"needle";
  match !commands with
  | {
      Todos.Command.request =
        Load_page { limit = 80; offset = 0; search = "needle" };
      _;
    }
    :: _ ->
      ()
  | _ -> failf "search change should dispatch a bounded DB search query"

let test_mobile_search_queries_full_runtime_dataset () =
  let all_todos =
    Stdlib.List.init 10_000 (fun index ->
        let created_at_ms = index + 1 in
        let title =
          if created_at_ms = 9_999 then "Needle from title index"
          else Printf.sprintf "Task %05d" created_at_ms
        in
        todo
          ~id:(Printf.sprintf "todo-%05d" created_at_ms)
          ~title ~created_at_ms ())
  in
  let root, _dispatched_commands = runtime_backed_mobile_app all_todos in
  Backend.select_tab_exn root ~id:"search";
  Backend.change_search_exn root ~path:[ 3 ] ~text:"needle";
  let output = Backend.show root in
  assert_contains "search result outside initial app state" output
    ~substring:"Needle from title index";
  assert_not_contains "search does not keep first window" output
    ~substring:"Task 00001"

let test_mobile_search_is_cleared_when_leaving_search_tab () =
  let all_todos =
    [
      todo ~id:"todo-1" ~title:"Needle task" ~created_at_ms:1 ();
      todo ~id:"todo-2" ~title:"Regular task" ~created_at_ms:2 ();
    ]
  in
  let root, dispatched_commands = runtime_backed_mobile_app all_todos in
  Backend.select_tab_exn root ~id:"search";
  Backend.change_search_exn root ~path:[ 3 ] ~text:"needle";
  Backend.select_tab_exn root ~id:"today";
  (match !dispatched_commands with
  | {
      Todos.Command.request = Load_page { limit = 80; offset = 0; search = "" };
      _;
    }
    :: _ ->
      ()
  | _ -> failf "leaving search should reload the default unfiltered page");
  Backend.select_tab_exn root ~id:"search";
  let output = Backend.show root in
  assert_not_contains "search input is cleared after leaving search tab" output
    ~substring:"needle"

let test_mobile_edit_action_opens_editor_sheet () =
  Backend.reset ();
  let existing =
    todo ~id:"todo-1" ~title:"Editable task" ~created_at_ms:10 ()
  in
  let component graph =
    let model, set_model =
      Apple.state graph ~key:"model"
        { Todos.Model.initial with todos = [ existing ] }
    in
    let route, set_route =
      Apple.state graph ~key:"route" Todos.Screen.Route.All
    in
    let search, set_search = Apple.state graph ~key:"search" "" in
    let selected_todo_id, set_selected_todo_id =
      Apple.state graph ~key:"selected-todo-id" ""
    in
    let mobile_tab, set_mobile_tab =
      Apple.state graph ~key:"mobile-tab" "today"
    in
    let mobile_new_task_presented, set_mobile_new_task_presented =
      Apple.state graph ~key:"mobile-new-task-presented" false
    in
    let editing_todo_id, set_editing_todo_id =
      Apple.state graph ~key:"editing-todo-id" ""
    in
    let dispatch action () =
      let next_model, (_commands : Todos.Command.t list) =
        Todos.Model.update model action
      in
      set_model next_model ()
    in
    Todo_ui.mobile_view { model; dispatch }
      ~controls:
        {
          route;
          search;
          selected_todo_id;
          mobile_tab;
          mobile_new_task_presented;
          editing_todo_id;
          visible_todo_limit = Todo_ui.default_controls.visible_todo_limit;
          set_route;
          set_search;
          set_selected_todo_id;
          set_mobile_tab;
          set_mobile_new_task_presented;
          set_editing_todo_id;
          set_visible_todo_limit =
            Todo_ui.default_controls.set_visible_todo_limit;
        }
  in
  let app = App.create component in
  App.flush_and_render app;
  let root =
    match App.view app with
    | Some root -> root
    | None -> failwith "app did not render"
  in
  Backend.click_row_action_exn root ~path:[ 0; 1; 0; 0 ] ~title:"Edit";
  let output = Backend.show root in
  assert_contains "edit sheet opens from row action" output
    ~substring:"Edit Task";
  assert_contains "edit sheet receives row title" output
    ~substring:"text=\"Editable task\" placeholder=\"Task title\""

let test_mobile_edit_flow_uses_sheet_editor () =
  let model =
    {
      Todos.Model.initial with
      draft = "Editable task";
      todos = [ todo ~id:"todo-1" ~title:"Editable task" ~created_at_ms:10 () ];
    }
  in
  let controls = { Todo_ui.default_controls with editing_todo_id = "todo-1" } in
  let output = render_mobile model ~controls in
  assert_contains "edit sheet" output ~substring:"sheet:";
  assert_contains "edit task title" output ~substring:"Edit Task";
  assert_contains "edit task field" output
    ~substring:"text=\"Editable task\" placeholder=\"Task title\"";
  assert_contains "edit cancel" output ~substring:"Cancel";
  assert_contains "edit save" output ~substring:"Save"

let test_mobile_add_flow_uses_sheet_editor () =
  let controls =
    { Todo_ui.default_controls with mobile_new_task_presented = true }
  in
  let output = render_mobile Todos.Model.initial ~controls in
  assert_contains "add sheet" output ~substring:"sheet:";
  assert_contains "new task title" output ~substring:"New Task";
  assert_contains "sheet task field" output
    ~substring:"placeholder=\"Task title\"";
  assert_contains "sheet cancel" output ~substring:"Cancel";
  assert_contains "sheet save" output ~substring:"Save";
  assert_not_contains "no inline composer" output
    ~substring:"placeholder=\"New task\""

let test_adaptive_model_contains_phone_and_regular_layouts () =
  let output = render_adaptive Todos.Model.initial in
  assert_contains "adaptive root" output ~substring:"adaptive-layout";
  assert_contains "phone tabs" output ~substring:"tab-view";
  assert_contains "phone search" output ~substring:"searchable";
  assert_contains "regular split" output ~substring:"navigation-split"

let test_search_filters_visible_tasks () =
  let model =
    {
      Todos.Model.initial with
      todos =
        [
          todo ~id:"todo-1" ~title:"iOS UI" ~created_at_ms:10 ();
          todo ~id:"todo-2" ~title:"Web worker" ~created_at_ms:20 ();
        ];
    }
  in
  let controls = { Todo_ui.default_controls with search = "web" } in
  let output = render model ~controls in
  assert_contains "matching task" output ~substring:"Web worker";
  if String.is_substring output ~substring:"iOS UI" then
    failf "filtered output should not contain iOS UI, got:\n%s" output

let () =
  test_empty_model_renders_split_view_composer_and_search ();
  test_loaded_model_renders_split_view_and_tasks ();
  test_mobile_model_renders_tabbed_phone_ui ();
  test_mobile_search_tab_owns_searchable_modifier ();
  test_mobile_selected_search_tab_keeps_searchable_on_search_content ();
  test_mobile_rows_support_edit_and_delete_swipes ();
  test_mobile_large_dataset_renders_initial_window_only ();
  test_mobile_large_dataset_toggles_first_visible_row_in_place ();
  test_mobile_edit_sheet_save_updates_title ();
  test_mobile_loads_more_when_bottom_sentinel_appears ();
  test_mobile_runtime_backed_load_more_loads_next_window ();
  test_mobile_runtime_backed_load_more_keeps_rendered_rows_capped ();
  test_component_initial_load_uses_bounded_window_only ();
  test_search_change_dispatches_bounded_db_query ();
  test_mobile_search_queries_full_runtime_dataset ();
  test_mobile_search_is_cleared_when_leaving_search_tab ();
  test_mobile_edit_action_opens_editor_sheet ();
  test_mobile_edit_flow_uses_sheet_editor ();
  test_mobile_add_flow_uses_sheet_editor ();
  test_adaptive_model_contains_phone_and_regular_layouts ();
  test_search_filters_visible_tasks ()
