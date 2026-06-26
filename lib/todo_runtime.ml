open! Todo_std
include Todo_core

module Store = struct
  include Todo_core.Store

  let open_sqlite ~path =
    let sqlite = Datascript_sqlite.open_session path in
    let storage = Datascript_sqlite.storage sqlite in
    restore_or_create storage
end

module Runtime = struct
  type subscriber = { query : Query.t; on_change : Action.t -> unit }

  type session = {
    path : string;
    store : Store.t ref;
    mutex : Mutex.t;
    subscribers : (string, subscriber) Hashtbl.t;
  }

  let default_db_path () =
    match Sys.getenv_opt "BONSAI_TODOS_DB" with
    | Some path -> path
    | None ->
        Stdlib.Filename.concat
          (Stdlib.Filename.get_temp_dir_name ())
          "todos-ocaml.sqlite3"

  let sessions : (string, session) Hashtbl.t = Hashtbl.create ()
  let sessions_mutex = Mutex.create ()

  let session ~path =
    Mutex.lock sessions_mutex;
    let result =
      match Hashtbl.find sessions path with
      | Some session -> session
      | None ->
          let session =
            {
              path;
              store = ref (Store.open_sqlite ~path);
              mutex = Mutex.create ();
              subscribers = Hashtbl.create ();
            }
          in
          Hashtbl.set sessions ~key:path ~data:session;
          session
    in
    Mutex.unlock sessions_mutex;
    result

  let with_session session ~f =
    Mutex.lock session.mutex;
    try
      let result = f !(session.store) in
      Mutex.unlock session.mutex;
      result
    with exn ->
      Mutex.unlock session.mutex;
      raise exn

  let query_action store = function
    | Query.List_todos -> Action.Loaded (Store.list store)

  let affected_queries = function
    | Store_write.Add _ | Toggle _ | Delete _ | Update_title _ ->
        [ Query.List_todos ]

  let subscriber_notifications session store queries =
    Hashtbl.data session.subscribers
    |> List.filter_map ~f:(fun subscriber ->
        if List.exists queries ~f:(Query.equal subscriber.query) then
          Some (subscriber.on_change, query_action store subscriber.query)
        else None)

  let notify notifications =
    List.iter notifications ~f:(fun (on_change, action) -> on_change action)

  let subscribe_query ~path ~id ~query ~on_change =
    let session = session ~path in
    let initial =
      with_session session ~f:(fun store ->
          Hashtbl.set session.subscribers ~key:id ~data:{ query; on_change };
          query_action store query)
    in
    on_change initial

  let unsubscribe_query ~path ~id =
    let session = session ~path in
    with_session session ~f:(fun _store ->
        Hashtbl.remove session.subscribers id)

  let execute_command_with_session ?(notify_subscribers = true) session
      (command : Command.t) =
    let action, notifications =
      with_session session ~f:(fun store ->
          match command.request with
          | Load_all -> (Action.Loaded (Store.list store), [])
          | Persist write ->
              let store = Store.apply_write store write in
              session.store := store;
              let action = Action.Loaded (Store.list store) in
              let notifications =
                if notify_subscribers then
                  subscriber_notifications session store
                    (affected_queries write)
                else []
              in
              (action, notifications)
          | Subscribe_query { id; query } ->
              Hashtbl.set session.subscribers ~key:id
                ~data:{ query; on_change = (fun _ -> ()) };
              (query_action store query, [])
          | Unsubscribe_query id ->
              Hashtbl.remove session.subscribers id;
              (query_action store Query.List_todos, []))
    in
    notify notifications;
    action

  let execute_command ?(notify_subscribers = true) ~path command =
    try execute_command_with_session ~notify_subscribers (session ~path) command
    with exn -> Action.Store_failed (Exn.to_string exn)

  let action ~path command () =
    let session = session ~path in
    try execute_command_with_session session command
    with exn -> Action.Store_failed (Exn.to_string exn)

  let run_command ~path ~dispatch command =
    match command.Command.request with
    | Subscribe_query { id; query } ->
        Bonsai_native.Action.of_thunk (fun () ->
            subscribe_query ~path ~id ~query ~on_change:(fun action ->
                dispatch action ()))
    | Unsubscribe_query id ->
        Bonsai_native.Action.of_thunk (fun () -> unsubscribe_query ~path ~id)
    | Load_all | Persist _ ->
        Bonsai_native.Action.of_thunk (fun () ->
            let run () = dispatch (action ~path command ()) () in
            ignore (Thread.create run ()))
end
