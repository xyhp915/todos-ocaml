module Transit_json = Transit_melange.Transit.Json

module React = struct
  type node
  type props

  external create_element : string -> props -> node array -> node
    = "createElement"
  [@@mel.module "react"] [@@mel.variadic]

  external text : string -> node = "%identity"
  external empty_props : unit -> props = "" [@@mel.obj]
  external class_props : className:string -> unit -> props = "" [@@mel.obj]
  external key_class_props : key:string -> className:string -> unit -> props = ""
  [@@mel.obj]

  external button_props :
    className:string -> onClick:(unit -> unit) -> unit -> props = ""
  [@@mel.obj]

  external form_props : className:string -> onSubmit:('event -> unit) -> unit -> props
    = ""
  [@@mel.obj]

  external input_props :
    value:string ->
    placeholder:string ->
    onChange:('event -> unit) ->
    unit ->
    props = ""
  [@@mel.obj]

  external event_target : 'event -> 'target = "target" [@@mel.get]
  external target_value : 'target -> string = "value" [@@mel.get]
  external prevent_default : 'event -> unit = "preventDefault" [@@mel.send]

  let element tag ?(props = empty_props ()) children =
    create_element tag props (Array.of_list children)

  let event_value event = event |> event_target |> target_value
end

module React_dom = struct
  type root
  type dom_element

  external document_get_element_by_id : string -> dom_element
    = "getElementById"
  [@@mel.scope "document"]

  external create_root : dom_element -> root = "createRoot"
  [@@mel.module "react-dom/client"]

  external render : root -> React.node -> unit = "render" [@@mel.send]
end

module Web_worker = struct
  type t
  type options = { type_ : string [@mel.as "type"] }
  type message_event

  external create : string -> options -> t = "Worker" [@@mel.new]
  external post_message : t -> string -> unit = "postMessage" [@@mel.send]
  external set_on_message : t -> (message_event -> unit) -> unit = "onmessage"
  [@@mel.set]

  external event_data : message_event -> string = "data" [@@mel.get]

  let start ~on_message =
    let worker = create "./dist/web/todos_db_worker.js" { type_ = "module" } in
    set_on_message worker (fun event -> on_message (event_data event));
    worker
end

module Tauri_runtime = struct
  type args

  external is_available : unit -> bool = "isTauriRuntime"
  [@@mel.module "./tauri_runtime.js"]

  external invoke_string :
    string -> args -> (string -> unit) -> (string -> unit) -> unit
    = "invokeString"
  [@@mel.module "./tauri_runtime.js"]

  external request_args : payload:string -> unit -> args = "" [@@mel.obj]
end

module Json = struct
  type native_todo

  external parse_todos : string -> native_todo array = "parse"
  [@@mel.scope "JSON"]

  external id : native_todo -> string = "id" [@@mel.get]
  external title : native_todo -> string = "title" [@@mel.get]
  external completed : native_todo -> bool = "completed" [@@mel.get]
  external created_at_ms : native_todo -> int = "createdAtMs" [@@mel.get]
end

module Clock = struct
  external now : unit -> float = "now" [@@mel.scope "Date"]
end

type todo = {
  id : string;
  title : string;
  completed : bool;
  created_at_ms : int;
}

let todos = ref []
let draft = ref ""
let root_ref : React_dom.root option ref = ref None
let worker_ref : Web_worker.t option ref = ref None

let todo_to_transit todo =
  Transit_json.Map
    [
      (Transit_json.Keyword "todo/id", Transit_json.String todo.id);
      (Transit_json.Keyword "todo/title", Transit_json.String todo.title);
      (Transit_json.Keyword "todo/completed", Transit_json.Bool todo.completed);
      ( Transit_json.Keyword "todo/created-at-ms",
        Transit_json.Int todo.created_at_ms );
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

let id_field key entries =
  match field key entries with
  | Some (Transit_json.String value) -> Some value
  | Some (Transit_json.Int value) -> Some (string_of_int value)
  | Some (Transit_json.Int64 value) -> Some (Int64.to_string value)
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
        (id_field "todo/id" entries, string_field "todo/title" entries)
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
              created_at_ms =
                (match int_field "todo/created-at-ms" entries with
                | Some created_at_ms -> created_at_ms
                | None -> 0);
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

let decode_native_todos payload =
  if String.equal payload "" then []
  else
    try
      payload |> Json.parse_todos |> Array.to_list
      |> List.map (fun todo ->
             {
               id = Json.id todo;
               title = Json.title todo;
               completed = Json.completed todo;
               created_at_ms = Json.created_at_ms todo;
             })
    with _ -> []

let active_todos todos = List.filter (fun todo -> not todo.completed) todos
let completed_todos todos = List.filter (fun todo -> todo.completed) todos

let current_time_ms () = int_of_float (Clock.now ())

let next_id () = "todo-" ^ string_of_int (current_time_ms ())

let checkbox_class completed =
  "icon-button" ^ if completed then " checked" else ""

let protocol_escape value =
  value |> String.split_on_char '\\' |> String.concat "\\\\"
  |> String.split_on_char '\t' |> String.concat "\\t"
  |> String.split_on_char '\n' |> String.concat "\\n"
  |> String.split_on_char '\r' |> String.concat "\\r"

module Web_store = struct
  let post message =
    match !worker_ref with
    | None -> ()
    | Some worker -> Web_worker.post_message worker message

  let start ~on_message =
    worker_ref := Some (Web_worker.start ~on_message)

  let save value = post ("save:" ^ encode_todos value)
  let load () = post "load"
end

module Tauri_store = struct
  let request payload ~on_loaded ~on_error =
    Tauri_runtime.invoke_string "ocaml_request"
      (Tauri_runtime.request_args ~payload ()) on_loaded on_error

  let load ~on_loaded ~on_error =
    request "load" ~on_loaded ~on_error

  let add todo ~on_loaded ~on_error =
    request
      (String.concat "\t"
         [
           "add";
           protocol_escape todo.id;
           string_of_int todo.created_at_ms;
           protocol_escape todo.title;
         ])
      ~on_loaded ~on_error

  let toggle id ~on_loaded ~on_error =
    request
      (String.concat "\t" [ "toggle"; protocol_escape id ])
      ~on_loaded ~on_error

  let delete id ~on_loaded ~on_error =
    request
      (String.concat "\t" [ "delete"; protocol_escape id ])
      ~on_loaded ~on_error
end

let use_tauri_store () = Tauri_runtime.is_available ()

let rec rerender () =
  match !root_ref with
  | None -> ()
  | Some root -> React_dom.render root (app_view ())

and set_draft value =
  draft := value;
  rerender ()

and handle_loaded_todos loaded =
  todos := loaded;
  rerender ()

and handle_tauri_payload payload = handle_loaded_todos (decode_native_todos payload)

and handle_store_error _message = rerender ()

and add_todo () =
  let title = String.trim !draft in
  if not (String.equal title "") then (
    let todo =
      {
        id = next_id ();
        title;
        completed = false;
        created_at_ms = current_time_ms ();
      }
    in
    draft := "";
    if use_tauri_store () then (
      Tauri_store.add todo ~on_loaded:handle_tauri_payload
        ~on_error:handle_store_error;
      rerender ())
    else
      let updated = todo :: !todos in
      todos := updated;
      Web_store.save updated;
      rerender ())

and toggle_todo id =
  if use_tauri_store () then
    Tauri_store.toggle id ~on_loaded:handle_tauri_payload
      ~on_error:handle_store_error
  else (
    let updated =
      !todos
      |> List.map (fun todo ->
             if todo.id = id then { todo with completed = not todo.completed }
             else todo)
    in
    todos := updated;
    Web_store.save updated;
    rerender ())

and delete_todo id =
  if use_tauri_store () then
    Tauri_store.delete id ~on_loaded:handle_tauri_payload
      ~on_error:handle_store_error
  else (
    let updated = !todos |> List.filter (fun todo -> todo.id <> id) in
    todos := updated;
    Web_store.save updated;
    rerender ())

and todo_row todo =
  React.element "li"
    ~props:
      (React.key_class_props ~key:todo.id
         ~className:("todo-row" ^ if todo.completed then " completed" else "")
         ())
    [
      React.element "button"
        ~props:
          (React.button_props ~className:(checkbox_class todo.completed)
             ~onClick:(fun () -> toggle_todo todo.id)
             ())
        [];
      React.element "span" [ React.text todo.title ];
      React.element "button"
        ~props:(React.button_props ~className:"delete-button" ~onClick:(fun () -> delete_todo todo.id) ())
        [ React.text "Delete" ];
    ]

and todo_column ~title ~empty_text todos =
  React.element "section"
    [
      React.element "h2" [ React.text title ];
      (match todos with
      | [] ->
          React.element "p" ~props:(React.class_props ~className:"muted" ())
            [ React.text empty_text ]
      | todos -> React.element "ul" (List.map todo_row todos));
    ]

and app_view () =
  let active = active_todos !todos in
  let completed = completed_todos !todos in
  React.element "main" ~props:(React.class_props ~className:"app-shell" ())
    [
      React.element "aside" ~props:(React.class_props ~className:"sidebar" ())
        [
          React.element "h1" [ React.text "Todos" ];
          React.element "p" ~props:(React.class_props ~className:"counter" ())
            [ React.text (Printf.sprintf "%d active" (List.length active)) ];
          React.element "p"
            ~props:(React.class_props ~className:"counter muted" ())
            [
              React.text
                (Printf.sprintf "%d completed" (List.length completed));
            ];
        ];
      React.element "section" ~props:(React.class_props ~className:"workspace" ())
        [
          React.element "form"
            ~props:
              (React.form_props ~className:"composer"
                 ~onSubmit:(fun event ->
                   React.prevent_default event;
                   add_todo ())
                 ())
            [
              React.element "input"
                ~props:
                  (React.input_props ~value:!draft ~placeholder:"New task"
                     ~onChange:(fun event -> set_draft (React.event_value event))
                     ())
                [];
              React.element "button" [ React.text "Add" ];
            ];
          React.element "div" ~props:(React.class_props ~className:"columns" ())
            [
              todo_column ~title:"Active" ~empty_text:"Nothing active right now."
                active;
              todo_column ~title:"Done" ~empty_text:"Nothing completed yet."
                completed;
            ];
        ];
    ]

let handle_store_message message =
  if String.starts_with ~prefix:"loaded:" message then (
    let payload = String.sub message 7 (String.length message - 7) in
    handle_loaded_todos (decode_todos payload))
  else if String.starts_with ~prefix:"failed:" message then handle_store_error message
  else ()

let () =
  let root =
    React_dom.create_root (React_dom.document_get_element_by_id "app")
  in
  root_ref := Some root;
  if use_tauri_store () then (
    rerender ();
    Tauri_store.load ~on_loaded:handle_tauri_payload
      ~on_error:handle_store_error)
  else (
    Web_store.start ~on_message:handle_store_message;
    rerender ();
    Web_store.load ())
