open! Todo_std

module Codec = Datascript_melange_storage
module Store = Todo_core.Store

external install_worker : (string -> unit) -> unit = "installTodoWorker"
[@@mel.module "./sqlite_worker_runtime.js"]

external post_message : string -> unit = "postTodoWorkerMessage"
[@@mel.module "./sqlite_worker_runtime.js"]

external storage_store_payload : string -> string -> unit = "storeStoragePayload"
[@@mel.module "./sqlite_worker_runtime.js"]

external storage_restore_payload : string -> string = "restoreStoragePayload"
[@@mel.module "./sqlite_worker_runtime.js"]

external storage_list_addresses : unit -> string array = "listStorageAddresses"
[@@mel.module "./sqlite_worker_runtime.js"]

external storage_delete_payload : string -> unit = "deleteStoragePayload"
[@@mel.module "./sqlite_worker_runtime.js"]

let storage : Datascript.storage =
  {
    storage_store =
      (fun entries ->
        List.iter entries ~f:(fun (address, payload) ->
            storage_store_payload address (Codec.encode payload)));
    storage_restore =
      (fun address ->
        match storage_restore_payload address with
        | "" -> None
        | payload -> Some (Codec.decode payload));
    storage_list_addresses = (fun () -> storage_list_addresses () |> Array.to_list);
    storage_delete = (fun addresses -> List.iter addresses ~f:storage_delete_payload);
  }

let store_ref : Store.t option ref = ref None

let store () =
  match !store_ref with
  | Some store -> store
  | None ->
      let store = Store.restore_or_create storage in
      store_ref := Some store;
      store

let set_store store = store_ref := Some store

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

let json_todo (todo : Todo_core.Todo.t) =
  Printf.sprintf
    {|{"id":"%s","title":"%s","completed":%b,"createdAtMs":%d}|}
    (json_escape todo.id) (json_escape todo.title) todo.completed
    todo.created_at_ms

let todos_payload store =
  store |> Store.list |> List.map ~f:json_todo |> String.concat ","
  |> Printf.sprintf "[%s]"

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

let parse_int value =
  match int_of_string_opt value with
  | Some value -> value
  | None -> failwith ("invalid integer: " ^ value)

let loaded payload = post_message ("loaded:" ^ payload)
let failed message = post_message ("failed:" ^ message)

let apply_write write =
  let store = Store.apply_write (store ()) write in
  set_store store;
  loaded (todos_payload store)

let handle_message message =
  try
    match String.split_on_char '\t' message with
    | [ "load" ] -> loaded (todos_payload (store ()))
    | [ "add"; id; created_at_ms; title ] ->
        apply_write
          (Store.Add
             {
               id = protocol_unescape id;
               title = protocol_unescape title |> String.strip;
               completed = false;
               created_at_ms = parse_int created_at_ms;
             })
    | [ "toggle"; id ] -> apply_write (Store.Toggle (protocol_unescape id))
    | [ "delete"; id ] -> apply_write (Store.Delete (protocol_unescape id))
    | [ "update-title"; id; title ] ->
        apply_write
          (Store.Update_title
             {
               id = protocol_unescape id;
               title = protocol_unescape title |> String.strip;
             })
    | _ -> failed ("Unknown worker command: " ^ message)
  with exn -> failed (Exn.to_string exn)

let () = install_worker handle_message
