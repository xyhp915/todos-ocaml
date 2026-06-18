open Todos

let failf fmt = Printf.ksprintf failwith fmt

let assert_equal_string label expected actual =
  if expected <> actual then failf "%s: expected %s, got %s" label expected actual
;;

let assert_equal_bool label expected actual =
  if expected <> actual then
    failf "%s: expected %b, got %b" label expected actual
;;

let assert_equal_int label expected actual =
  if expected <> actual then failf "%s: expected %d, got %d" label expected actual
;;

let find_todo_by_title state title =
  Todo_app_state.todos state
  |> List.find_opt (fun todo -> todo.Todo_store.title = title)
  |> function
  | Some todo -> todo
  | None -> failf "todo not found: %s" title
;;

let test_search_change_does_not_rewrite_tasks () =
  let state =
    Todo_app_state.apply Todo_app_state.initial (Search_changed "client")
  in
  assert_equal_string "query" "client" (Todo_app_state.search_query state);
  assert_equal_int "todo count" 10 (List.length (Todo_app_state.todos state))
;;

let test_toggle_updates_task_status () =
  let initial = Todo_app_state.create ~store:(Todo_store.empty ()) () in
  let state =
    Todo_app_state.apply
      initial
      (Save_new { title = "Ship app"; date = "Today"; time = "9:00 AM" })
  in
  let todo = find_todo_by_title state "Ship app" in
  let state = Todo_app_state.apply state (Toggle todo.id) in
  let todo = find_todo_by_title state "Ship app" in
  assert_equal_bool "completed" true todo.completed
;;

let test_delete_removes_task () =
  let initial = Todo_app_state.create ~store:(Todo_store.empty ()) () in
  let state =
    Todo_app_state.apply
      initial
      (Save_new { title = "Archive notes"; date = "Tomorrow"; time = "" })
  in
  let todo = find_todo_by_title state "Archive notes" in
  let state = Todo_app_state.apply state (Delete todo.id) in
  assert_equal_int "remaining todos" 0 (List.length (Todo_app_state.todos state))
;;

let test_save_new_preserves_date_and_time () =
  let initial = Todo_app_state.create ~store:(Todo_store.empty ()) () in
  let state =
    Todo_app_state.apply
      initial
      (Save_new { title = "Design review"; date = "Jun 19"; time = "2:30 PM" })
  in
  let todo = find_todo_by_title state "Design review" in
  assert_equal_string "date" "Jun 19" todo.date;
  assert_equal_string "time" "2:30 PM" todo.time
;;

let test_save_existing_updates_title_date_and_time () =
  let initial = Todo_app_state.create ~store:(Todo_store.empty ()) () in
  let state =
    Todo_app_state.apply
      initial
      (Save_new { title = "Draft"; date = "Today"; time = "8:00 AM" })
  in
  let todo = find_todo_by_title state "Draft" in
  let state =
    Todo_app_state.apply
      state
      (Save_existing
         ( todo.id
         , { title = "Final draft"; date = "Jun 20"; time = "4:15 PM" } ))
  in
  let todo = find_todo_by_title state "Final draft" in
  assert_equal_string "date" "Jun 20" todo.date;
  assert_equal_string "time" "4:15 PM" todo.time
;;

let () =
  test_search_change_does_not_rewrite_tasks ();
  test_toggle_updates_task_status ();
  test_delete_removes_task ();
  test_save_new_preserves_date_and_time ();
  test_save_existing_updates_title_date_and_time ()
;;
