type mode =
  | Dashboard
  | Upcoming
  | Search

type section =
  { title : string
  ; todos : Todo_store.todo list
  }

let take n values =
  let rec loop n values acc =
    match n, values with
    | 0, _ | _, [] -> List.rev acc, values
    | n, value :: rest -> loop (n - 1) rest (value :: acc)
  in
  loop n values []

let normalized value = value |> String.trim |> String.lowercase_ascii

let contains ~substring value =
  let value_length = String.length value in
  let substring_length = String.length substring in
  let rec loop index =
    if index + substring_length > value_length
    then false
    else if String.sub value index substring_length = substring
    then true
    else loop (index + 1)
  in
  substring_length = 0 || loop 0

let filtered_todos ~query todos =
  match normalized query with
  | "" -> todos
  | query ->
    List.filter
      (fun todo -> contains (normalized todo.Todo_store.title) ~substring:query)
      todos

let section title todos = { title; todos }

let non_empty_sections sections =
  List.filter (fun section -> section.todos <> []) sections

let sections_for ~mode ~query todos =
  let todos = filtered_todos ~query todos |> List.rev in
  let active, completed =
    List.partition (fun todo -> not todo.Todo_store.completed) todos
  in
  let today, upcoming = take 3 active in
  (match mode with
   | Dashboard ->
     [ section "Today" today; section "Upcoming" upcoming; section "Completed" completed ]
   | Upcoming -> [ section "Upcoming" upcoming ]
   | Search ->
     [ section "Today" today; section "Upcoming" upcoming; section "Completed" completed ])
  |> non_empty_sections

let header_title ~mode ~section_title ~todo_count =
  match mode, section_title with
  | Upcoming, "Upcoming" -> ""
  | Search, "Today" -> ""
  | Dashboard, ("Today" | "Upcoming" | "Completed") ->
    Printf.sprintf "%s  %d" section_title todo_count
  | _ -> Printf.sprintf "%s  %d" section_title todo_count

let todo_metadata todo =
  match String.trim todo.Todo_store.time, String.trim todo.date with
  | time, _ when time <> "" -> time
  | _, date -> date
