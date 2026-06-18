open Todos

let failf fmt = Printf.ksprintf failwith fmt

let assert_equal_string label expected actual =
  if expected <> actual then failf "%s: expected %s, got %s" label expected actual

let assert_equal_strings label expected actual =
  if expected <> actual then
    failf "%s: expected [%s], got [%s]" label (String.concat "; " expected) (String.concat "; " actual)

let section_titles sections =
  List.map (fun section -> section.Todo_presentation.title) sections

let todo_titles todos =
  List.map (fun todo -> todo.Todo_store.title) todos

let test_dashboard_sections_match_current_ios_home () =
  let sections =
    Todo_store.demo ()
    |> Todo_store.all
    |> Todo_presentation.sections_for ~mode:Dashboard ~query:""
  in
  assert_equal_strings "dashboard section titles" [ "Today"; "Upcoming"; "Completed" ] (section_titles sections);
  match sections with
  | today :: upcoming :: completed :: [] ->
    assert_equal_strings
      "today items"
      [ "Design onboarding flow"; "Reply to client email"; "Team stand-up meeting" ]
      (todo_titles today.todos);
    assert_equal_strings
      "upcoming items"
      [ "Prepare presentation"; "User research review"; "Update documentation"; "Marketing sync" ]
      (todo_titles upcoming.todos);
    assert_equal_strings
      "completed items"
      [ "Workout"; "Grocery shopping"; "Review new designs" ]
      (todo_titles completed.todos)
  | _ -> failwith "expected three dashboard sections"

let test_upcoming_mode_has_no_visible_header () =
  let sections =
    Todo_store.demo ()
    |> Todo_store.all
    |> Todo_presentation.sections_for ~mode:Upcoming ~query:""
  in
  assert_equal_strings "upcoming section titles" [ "Upcoming" ] (section_titles sections);
  assert_equal_string
    "hidden upcoming header"
    ""
    (Todo_presentation.header_title ~mode:Upcoming ~section_title:"Upcoming" ~todo_count:4)

let test_search_filters_and_hides_today_header () =
  let store =
    Todo_store.empty ()
    |> Todo_store.add ~title:"Design Liquid Search" ~date:"Today" ~time:""
    |> Todo_store.add ~title:"Buy milk" ~date:"Today" ~time:""
    |> Todo_store.add ~title:"liquid glass polish" ~date:"Tomorrow" ~time:""
  in
  let sections =
    Todo_store.all store
    |> Todo_presentation.sections_for ~mode:Search ~query:" LIQUID "
  in
  assert_equal_strings "search sections" [ "Today" ] (section_titles sections);
  assert_equal_string
    "hidden search today header"
    ""
    (Todo_presentation.header_title ~mode:Search ~section_title:"Today" ~todo_count:2)

let test_metadata_prefers_time_over_date () =
  let with_time =
    Todo_store.empty ()
    |> Todo_store.add ~title:"Call" ~date:"Today" ~time:"9:30 AM"
    |> Todo_store.all
    |> List.hd
  in
  let with_date =
    Todo_store.empty ()
    |> Todo_store.add ~title:"Write" ~date:"Tomorrow" ~time:""
    |> Todo_store.all
    |> List.hd
  in
  assert_equal_string "time metadata" "9:30 AM" (Todo_presentation.todo_metadata with_time);
  assert_equal_string "date metadata" "Tomorrow" (Todo_presentation.todo_metadata with_date)

let () =
  test_dashboard_sections_match_current_ios_home ();
  test_upcoming_mode_has_no_visible_header ();
  test_search_filters_and_hides_today_header ();
  test_metadata_prefers_time_over_date ()
