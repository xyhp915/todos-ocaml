open! Core

include Todo_core

module Ds = Datascript

module Store = struct
  include Todo_core.Store

  module Sqlite_storage = struct
    external sqlite_store : string -> (string * string) list -> unit =
      "todos_ocaml_todos_sqlite_store"
    ;;

    external sqlite_restore : string -> string -> string option =
      "todos_ocaml_todos_sqlite_restore"
    ;;

    external sqlite_list_addresses : string -> string list =
      "todos_ocaml_todos_sqlite_list_addresses"
    ;;

    external sqlite_delete : string -> string list -> unit =
      "todos_ocaml_todos_sqlite_delete"
    ;;

    let store path entries =
      sqlite_store
        path
        (List.map entries ~f:(fun (address, payload) ->
           address, Storage_codec.encode payload))
    ;;

    let restore path address =
      Option.map (sqlite_restore path address) ~f:Storage_codec.decode
    ;;

    let create path : Ds.storage =
      { storage_store = store path
      ; storage_restore = restore path
      ; storage_list_addresses = (fun () -> sqlite_list_addresses path)
      ; storage_delete = sqlite_delete path
      }
    ;;
  end

  let open_sqlite ~path =
    let storage = Sqlite_storage.create path in
    restore_or_create storage
  ;;
end

module Runtime = struct
  type subscriber =
    { query : Query.t
    ; on_change : Action.t -> unit
    }

  type session =
    { path : string
    ; store : Store.t ref
    ; mutex : Caml_threads.Mutex.t
    ; subscribers : (string, subscriber) Hashtbl.t
    }

  let default_db_path () =
    match Sys.getenv "BONSAI_TODOS_DB" with
    | Some path -> path
    | None ->
      Stdlib.Filename.concat
        (Stdlib.Filename.get_temp_dir_name ())
        "todos-ocaml.sqlite3"
  ;;

  let sessions : (string, session) Hashtbl.t = Hashtbl.create (module String)
  let sessions_mutex = Caml_threads.Mutex.create ()

  let session ~path =
    Caml_threads.Mutex.lock sessions_mutex;
    let result =
      match Hashtbl.find sessions path with
      | Some session -> session
      | None ->
        let session =
          { path
          ; store = ref (Store.open_sqlite ~path)
          ; mutex = Caml_threads.Mutex.create ()
          ; subscribers = Hashtbl.create (module String)
          }
        in
        Hashtbl.set sessions ~key:path ~data:session;
        session
    in
    Caml_threads.Mutex.unlock sessions_mutex;
    result
  ;;

  let with_session session ~f =
    Caml_threads.Mutex.lock session.mutex;
    try
      let result = f !(session.store) in
      Caml_threads.Mutex.unlock session.mutex;
      result
    with
    | exn ->
      Caml_threads.Mutex.unlock session.mutex;
      raise exn
  ;;

  let query_action store = function
    | Query.List_todos -> Action.Loaded (Store.list store)
  ;;

  let affected_queries = function
    | Store_write.Add _ | Toggle _ | Delete _ | Update_title _ -> [ Query.List_todos ]
  ;;

  let subscriber_notifications session store queries =
    Hashtbl.data session.subscribers
    |> List.filter_map ~f:(fun subscriber ->
      if List.exists queries ~f:(Query.equal subscriber.query)
      then Some (subscriber.on_change, query_action store subscriber.query)
      else None)
  ;;

  let notify notifications =
    List.iter notifications ~f:(fun (on_change, action) -> on_change action)
  ;;

  let subscribe_query ~path ~id ~query ~on_change =
    let session = session ~path in
    let initial =
      with_session session ~f:(fun store ->
        Hashtbl.set session.subscribers ~key:id ~data:{ query; on_change };
        query_action store query)
    in
    on_change initial
  ;;

  let unsubscribe_query ~path ~id =
    let session = session ~path in
    with_session session ~f:(fun _store -> Hashtbl.remove session.subscribers id)
  ;;

  let execute_command_with_session ?(notify_subscribers = true) session (command : Command.t) =
    let action, notifications =
      with_session session ~f:(fun store ->
      match command.request with
      | Load_all -> Action.Loaded (Store.list store), []
      | Persist write ->
        let store = Store.apply_write store write in
        session.store := store;
        let action = Action.Loaded (Store.list store) in
        let notifications =
          if notify_subscribers
          then subscriber_notifications session store (affected_queries write)
          else []
        in
        action, notifications
      | Subscribe_query { id; query } ->
        Hashtbl.set
          session.subscribers
          ~key:id
          ~data:{ query; on_change = (fun _ -> ()) };
        query_action store query, []
      | Unsubscribe_query id ->
        Hashtbl.remove session.subscribers id;
        query_action store Query.List_todos, [])
    in
    notify notifications;
    action
  ;;

  let execute_command ?(notify_subscribers = true) ~path command =
    try execute_command_with_session ~notify_subscribers (session ~path) command with
    | exn -> Action.Store_failed (Exn.to_string exn)
  ;;

  let effect ~path command =
    Bonsai.Effect.Expert.of_fun ~f:(fun ~callback ~on_exn:_ ->
      let session = session ~path in
      let run () =
        callback
          (try execute_command_with_session session command with
           | exn -> Action.Store_failed (Exn.to_string exn))
      in
      ignore (Caml_threads.Thread.create run ()))
  ;;

  let run_command ~path ~dispatch command =
    match command.Command.request with
    | Subscribe_query { id; query } ->
      Bonsai.Effect.Expert.of_fun ~f:(fun ~callback ~on_exn ->
        subscribe_query
          ~path
          ~id
          ~query
          ~on_change:(fun action ->
            Bonsai.Effect.Expert.handle
              (dispatch action)
              ~on_exn);
        callback ())
    | Unsubscribe_query id ->
      Bonsai.Effect.Expert.of_fun ~f:(fun ~callback ~on_exn:_ ->
        unsubscribe_query ~path ~id;
        callback ())
    | Load_all ->
      let open Bonsai.Effect.Let_syntax in
      let%bind action = effect ~path command in
      dispatch action
    | Persist _ ->
      let open Bonsai.Effect.Let_syntax in
      let%bind action = effect ~path command in
      dispatch action
  ;;
end
