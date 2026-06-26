module Native = Bonsai_native
module App = Native.App
module Transit_json = Transit.Json

type renderer

external create_renderer :
  string ->
  (unit -> string) ->
  (int -> unit) ->
  (int -> string -> unit) ->
  renderer = "createRenderer"
[@@mel.module "./react_runtime.js"]

external render : renderer -> unit = "render" [@@mel.send]

type todo_store

external create_todo_store : (string -> unit) -> todo_store = "createTodoStore"
[@@mel.module "./db_worker_client.js"]

external post_store_message : todo_store -> string -> unit = "post" [@@mel.send]

type todo = { id : int; title : string; completed : bool }

let todos = ref []
let renderer_ref : renderer option ref = ref None

let todo_to_transit todo =
  Transit_json.Map
    [
      (Transit_json.Keyword "todo/id", Transit_json.Int todo.id);
      (Transit_json.Keyword "todo/title", Transit_json.String todo.title);
      (Transit_json.Keyword "todo/completed", Transit_json.Bool todo.completed);
    ]

let field key entries =
  List.find_map
    (fun (entry_key, value) ->
      match entry_key with
      | Transit_json.Keyword entry_key when String.equal entry_key key ->
          Some value
      | Transit_json.String entry_key when String.equal entry_key key ->
          Some value
      | _ -> None)
    entries

let int_field key entries =
  match field key entries with
  | Some (Transit_json.Int value) -> Some value
  | Some (Transit_json.Int64 value) -> Some (Int64.to_int value)
  | _ -> None

let string_field key entries =
  match field key entries with
  | Some (Transit_json.String value) -> Some value
  | _ -> None

let bool_field key entries =
  match field key entries with
  | Some (Transit_json.Bool value) -> Some value
  | _ -> None

let todo_of_transit = function
  | Transit_json.Map entries -> (
      match
        (int_field "todo/id" entries, string_field "todo/title" entries)
      with
      | Some id, Some title ->
          Some
            {
              id;
              title;
              completed =
                (match bool_field "todo/completed" entries with
                | Some completed -> completed
                | None -> false);
            }
      | _ -> None)
  | _ -> None

let todos_to_transit todos = Transit_json.Array (List.map todo_to_transit todos)

let todos_of_transit = function
  | Transit_json.Array values | Transit_json.List values ->
      List.filter_map todo_of_transit values
  | _ -> []

let encode_todos todos = Transit_json.to_string (todos_to_transit todos)

let decode_todos payload =
  if String.equal payload "" then []
  else try payload |> Transit_json.of_string |> todos_of_transit with _ -> []

let rerender () =
  match !renderer_ref with None -> () | Some renderer -> render renderer

let handle_store_message message =
  if String.starts_with ~prefix:"loaded:" message then (
    let payload = String.sub message 7 (String.length message - 7) in
    todos := decode_todos payload;
    rerender ())
  else if String.starts_with ~prefix:"failed:" message then rerender ()
  else ()

let store = create_todo_store handle_store_message
let persist_todos value = post_store_message store ("save:" ^ encode_todos value)
let load_todos () = post_store_message store "load"

let next_id todos =
  todos |> List.map (fun todo -> todo.id) |> List.fold_left max 0 |> ( + ) 1

let active_todos todos = List.filter (fun todo -> not todo.completed) todos
let completed_todos todos = List.filter (fun todo -> todo.completed) todos

let todo_row graph todo =
  let toggle () =
    let updated =
      !todos
      |> List.map (fun current ->
          if current.id = todo.id then
            { current with completed = not current.completed }
          else current)
    in
    todos := updated;
    persist_todos updated;
    rerender ()
  in
  let delete () =
    let updated =
      !todos |> List.filter (fun current -> current.id <> todo.id)
    in
    todos := updated;
    persist_todos updated;
    rerender ()
  in
  Native.scope graph ~key:(string_of_int todo.id) (fun _graph ->
      Native.hstack ~spacing:8.
        [
          Native.button
            (if todo.completed then "Undo" else "Done")
            ~on_click:toggle;
          Native.text todo.title;
          Native.button "Delete" ~on_click:delete;
        ])

let todo_list graph ~title todos =
  Native.vstack ~spacing:8.
    [
      Native.text title;
      (match todos with
      | [] -> Native.text "Nothing here right now."
      | todos ->
          Native.list todos
            ~key:(fun todo -> string_of_int todo.id)
            ~row:(todo_row graph));
    ]

let component graph =
  let draft, set_draft = Native.Graph.state graph ~key:"draft" "" in
  let next_id_state, set_next_id =
    Native.Graph.state graph ~key:"next-id" (next_id !todos)
  in
  let add_todo () =
    let title = String.trim draft in
    if title <> "" then (
      let next_id = max next_id_state (next_id !todos) in
      let updated = { id = next_id; title; completed = false } :: !todos in
      todos := updated;
      persist_todos updated;
      set_next_id (next_id + 1) ();
      set_draft "" ();
      rerender ())
  in
  let active = active_todos !todos in
  let completed = completed_todos !todos in
  Native.vstack ~spacing:16.
    [
      Native.text "Todos";
      Native.hstack ~spacing:8.
        [
          Native.text_field ~text:draft ~placeholder:"New task"
            ~on_change:set_draft ();
          Native.button "Add" ~on_click:add_todo;
        ];
      Native.text
        (Printf.sprintf "%d active, %d completed" (List.length active)
           (List.length completed));
      Native.hstack ~spacing:24.
        [
          todo_list graph ~title:"Active" active;
          todo_list graph ~title:"Done" completed;
        ];
    ]
  |> Native.padding

let app = App.create component

let renderer =
  create_renderer "app"
    (fun () -> App.render_json app)
    (fun event_id -> App.dispatch_click app event_id)
    (fun event_id text -> App.dispatch_change app event_id ~text)

let () =
  renderer_ref := Some renderer;
  render renderer;
  load_todos ()
