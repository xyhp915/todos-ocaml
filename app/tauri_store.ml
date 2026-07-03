open! Todo_std
module Todos = Todos.Todo_runtime

let usage () =
  prerr_endline "usage: tauri_store <db-path>";
  exit 2

let json_escape value =
  let buffer = Buffer.create (String.length value + 8) in
  String.iter
    (function
      | '"' -> Buffer.add_string buffer "\\\""
      | '\\' -> Buffer.add_string buffer "\\\\"
      | '\b' -> Buffer.add_string buffer "\\b"
      | '\012' -> Buffer.add_string buffer "\\f"
      | '\n' -> Buffer.add_string buffer "\\n"
      | '\r' -> Buffer.add_string buffer "\\r"
      | '\t' -> Buffer.add_string buffer "\\t"
      | char when Char.code char < 0x20 ->
          Buffer.add_string buffer (Printf.sprintf "\\u%04x" (Char.code char))
      | char -> Buffer.add_char buffer char)
    value;
  Buffer.contents buffer

let json_todo (todo : Todos.Todo.t) =
  Printf.sprintf
    {|{"id":"%s","title":"%s","completed":%b,"createdAtMs":%d}|}
    (json_escape todo.id) (json_escape todo.title) todo.completed
    todo.created_at_ms

let print_todos store =
  let payload =
    store |> Todos.Store.list |> List.map ~f:json_todo |> String.concat ","
  in
  Printf.sprintf "[%s]" payload

let protocol_escape value =
  let buffer = Buffer.create (String.length value) in
  String.iter
    (function
      | '\\' -> Buffer.add_string buffer "\\\\"
      | '\t' -> Buffer.add_string buffer "\\t"
      | '\n' -> Buffer.add_string buffer "\\n"
      | '\r' -> Buffer.add_string buffer "\\r"
      | char -> Buffer.add_char buffer char)
    value;
  Buffer.contents buffer

let protocol_unescape value =
  let buffer = Buffer.create (String.length value) in
  let rec loop index =
    if index >= String.length value then Buffer.contents buffer
    else if Char.equal value.[index] '\\' && index + 1 < String.length value
    then (
      (match value.[index + 1] with
      | '\\' -> Buffer.add_char buffer '\\'
      | 't' -> Buffer.add_char buffer '\t'
      | 'n' -> Buffer.add_char buffer '\n'
      | 'r' -> Buffer.add_char buffer '\r'
      | char -> Buffer.add_char buffer char);
      loop (index + 2))
    else (
      Buffer.add_char buffer value.[index];
      loop (index + 1))
  in
  loop 0

let respond_ok payload = Printf.printf "ok\t%s\n%!" payload
let respond_error message = Printf.printf "err\t%s\n%!" (protocol_escape message)

let parse_int value =
  match int_of_string_opt value with
  | Some value -> value
  | None -> failwith ("invalid integer: " ^ value)

let handle_request store line =
  match String.split_on_char '\t' line with
  | [ "load" ] -> (store, print_todos store)
  | [ "add"; id; created_at_ms; title ] ->
      let store =
        Todos.Store.apply_write store
          (Todos.Store.Add
             {
               id = protocol_unescape id;
               title = protocol_unescape title |> String.strip;
               completed = false;
               created_at_ms = parse_int created_at_ms;
             })
      in
      (store, print_todos store)
  | [ "toggle"; id ] ->
      let store =
        Todos.Store.apply_write store (Todos.Store.Toggle (protocol_unescape id))
      in
      (store, print_todos store)
  | [ "delete"; id ] ->
      let store =
        Todos.Store.apply_write store (Todos.Store.Delete (protocol_unescape id))
      in
      (store, print_todos store)
  | [ "update-title"; id; title ] ->
      let store =
        Todos.Store.apply_write store
          (Todos.Store.Update_title
             {
               id = protocol_unescape id;
               title = protocol_unescape title |> String.strip;
             })
      in
      (store, print_todos store)
  | _ -> failwith "unknown tauri_store command"

let rec daemon_loop store =
  (* daemon-loop *)
  match read_line () with
  | line -> (
      match Result.try_with (fun () -> handle_request store line) with
      | Ok (store, payload) ->
          respond_ok payload;
          daemon_loop store
      | Error exn ->
          respond_error (Exn.to_string exn);
          daemon_loop store)
  | exception End_of_file -> ()

let run argv =
  match Array.to_list argv with
  | [ _; path ] -> Todos.Store.open_sqlite ~path |> daemon_loop
  | _ -> usage ()

let () =
  try run Sys.argv
  with exn ->
    prerr_endline (Exn.to_string exn);
    exit 1
