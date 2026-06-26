external install_worker : (string -> unit) -> unit = "installTodoWorker"
[@@mel.module "./sqlite_worker_runtime.js"]

external post_message : string -> unit = "postTodoWorkerMessage"
[@@mel.module "./sqlite_worker_runtime.js"]

external load_stored_payload : (string -> unit) -> (string -> unit) -> unit
  = "loadStoredPayload"
[@@mel.module "./sqlite_worker_runtime.js"]

external save_stored_payload :
  string -> (string -> unit) -> (string -> unit) -> unit = "saveStoredPayload"
[@@mel.module "./sqlite_worker_runtime.js"]

let loaded payload = post_message ("loaded:" ^ payload)
let failed message = post_message ("failed:" ^ message)

let handle_message message =
  if String.equal message "load" then load_stored_payload loaded failed
  else if String.starts_with ~prefix:"save:" message then
    let payload = String.sub message 5 (String.length message - 5) in
    save_stored_payload payload loaded failed
  else failed ("Unknown worker command: " ^ message)

let () = install_worker handle_message
