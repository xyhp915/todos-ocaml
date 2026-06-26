open! Todo_std

module Todo = struct
  type t = {
    id : string;
    title : string;
    completed : bool;
    created_at_ms : int;
  }
end

module Store_write = struct
  type t =
    | Add of Todo.t
    | Toggle of string
    | Delete of string
    | Update_title of { id : string; title : string }
end

module Store = struct
  module Ds = Datascript

  type t = Ds.db

  type write = Store_write.t =
    | Add of Todo.t
    | Toggle of string
    | Delete of string
    | Update_title of { id : string; title : string }

  let attr_id = "todo/id"
  let attr_title = "todo/title"
  let attr_completed = "todo/completed"
  let attr_created_at_ms = "todo/created-at-ms"

  let schema_attr ?unique ?(indexed = false) ?value_type () : Ds.schema_attr =
    {
      cardinality = One;
      unique;
      indexed = indexed || Option.is_some unique;
      is_component = false;
      no_history = false;
      doc = None;
      value_type;
      tuple_attrs = None;
      tuple_types = None;
    }

  let schema : Ds.schema =
    [
      (attr_id, schema_attr ~unique:Identity ~value_type:StringType ());
      (attr_title, schema_attr ~value_type:StringType ());
      (attr_completed, schema_attr ());
      (attr_created_at_ms, schema_attr ~indexed:true ~value_type:NumberType ());
    ]

  let empty ?storage () = Ds.empty_db ~schema ?storage ()

  let restore_or_create storage =
    match Ds.restore storage with
    | Some db -> db
    | None -> (
        match storage.storage_list_addresses () with
        | [] ->
            let db = empty ~storage () in
            Ds.store ~storage db;
            db
        | addresses ->
            failwithf "Unable to restore non-empty todo storage (%d payloads)"
              (List.length addresses))

  let lookup id = Ds.Lookup_ref (attr_id, Ds.String id)

  let transact db tx_ops =
    let report = Ds.transact db tx_ops in
    (match Ds.storage report.db_after with
    | None -> ()
    | Some storage -> Ds.store ~storage report.db_after);
    report.db_after

  let add_todo_ops (todo : Todo.t) =
    let entity = Ds.Temp_id todo.id in
    [
      Ds.Add (entity, attr_id, String todo.id);
      Ds.Add (entity, attr_title, String todo.title);
      Ds.Add (entity, attr_completed, Bool todo.completed);
      Ds.Add (entity, attr_created_at_ms, Int todo.created_at_ms);
    ]

  let entity_for_id db id = Ds.entity db (lookup id)

  let one_string entity attr =
    match Ds.entity_attr entity attr with
    | Some (One_value (String value)) -> Some value
    | _ -> None

  let one_bool entity attr =
    match Ds.entity_attr entity attr with
    | Some (One_value (Bool value)) -> Some value
    | _ -> None

  let one_int entity attr =
    match Ds.entity_attr entity attr with
    | Some (One_value (Int value)) -> Some value
    | _ -> None

  let todo_of_entity entity : Todo.t option =
    match
      ( one_string entity attr_id,
        one_string entity attr_title,
        one_int entity attr_created_at_ms )
    with
    | Some id, Some title, Some created_at_ms ->
        let completed =
          Option.value (one_bool entity attr_completed) ~default:false
        in
        Some { Todo.id; title; completed; created_at_ms }
    | _ -> None

  let apply_write db = function
    | Add todo -> transact db (add_todo_ops todo)
    | Toggle id -> (
        match entity_for_id db id |> Option.bind ~f:todo_of_entity with
        | None -> db
        | Some todo ->
            transact db
              [ Ds.Add (lookup id, attr_completed, Bool (not todo.completed)) ])
    | Delete id -> transact db [ Ds.RetractEntity (lookup id) ]
    | Update_title { id; title } -> (
        match entity_for_id db id with
        | None -> db
        | Some _ -> transact db [ Ds.Add (lookup id, attr_title, String title) ]
        )

  let list db =
    Ds.datoms db Aevt ~a:attr_id ()
    |> Seq.filter_map (fun datom -> Ds.entity db (Entity_id datom.Ds.e))
    |> Seq.filter_map todo_of_entity
    |> Stdlib.List.of_seq
    |> List.sort ~compare:(fun (left : Todo.t) (right : Todo.t) ->
        let left_key = (left.completed, left.created_at_ms, left.id) in
        let right_key = (right.completed, right.created_at_ms, right.id) in
        compare left_key right_key)
end

module Query = struct
  type t = List_todos

  let equal left right =
    match (left, right) with List_todos, List_todos -> true
end

module Command = struct
  type target = Background

  type request =
    | Load_all
    | Persist of Store_write.t
    | Subscribe_query of { id : string; query : Query.t }
    | Unsubscribe_query of string

  type t = { target : target; request : request }
end

module Action = struct
  type new_todo = { id : string; created_at_ms : int }

  type t =
    | Load
    | Loaded of Todo.t list
    | Store_failed of string
    | Set_draft of string
    | Submit_new of new_todo
    | Update_title of { id : string }
    | Toggle of string
    | Delete of string
    | Subscribe_query of { id : string; query : Query.t }
    | Unsubscribe_query of string
end

module Model = struct
  type t = {
    draft : string;
    todos : Todo.t list;
    is_loading : bool;
    error : string option;
  }

  let initial = { draft = ""; todos = []; is_loading = false; error = None }
  let background request : Command.t = { target = Background; request }

  let update model (action : Action.t) =
    match action with
    | Action.Load ->
        ({ model with is_loading = true; error = None }, [ background Load_all ])
    | Action.Loaded todos ->
        ({ model with todos; is_loading = false; error = None }, [])
    | Action.Store_failed error ->
        ({ model with is_loading = false; error = Some error }, [])
    | Action.Set_draft draft -> ({ model with draft }, [])
    | Action.Submit_new { id; created_at_ms } ->
        let title = String.strip model.draft in
        if String.is_empty title then (model, [])
        else
          let todo = { Todo.id; title; completed = false; created_at_ms } in
          ( { model with draft = ""; error = None },
            [ background (Persist (Add todo)) ] )
    | Action.Update_title { id } ->
        let title = String.strip model.draft in
        if String.is_empty title then (model, [])
        else
          ( { model with draft = ""; error = None },
            [ background (Persist (Update_title { id; title })) ] )
    | Action.Toggle id -> (model, [ background (Persist (Toggle id)) ])
    | Action.Delete id -> (model, [ background (Persist (Delete id)) ])
    | Action.Subscribe_query { id; query } ->
        (model, [ background (Subscribe_query { id; query }) ])
    | Action.Unsubscribe_query id ->
        (model, [ background (Unsubscribe_query id) ])
end

module Screen = struct
  module Route = struct
    type t = All | Active | Completed

    let all_id = "all"
    let active_id = "active"
    let completed_id = "completed"

    let equal left right =
      match (left, right) with
      | All, All | Active, Active | Completed, Completed -> true
      | _ -> false

    let id = function
      | All -> all_id
      | Active -> active_id
      | Completed -> completed_id

    let of_id = function
      | "active" -> Active
      | "completed" -> Completed
      | _ -> All

    let title = function
      | All -> "Tasks"
      | Active -> "Active"
      | Completed -> "Completed"
  end

  type t = {
    title : string;
    empty_title : string;
    active_count : int;
    completed_count : int;
    visible_todos : Todo.t list;
    active_todos : Todo.t list;
    completed_todos : Todo.t list;
    selected_todo : Todo.t option;
  }

  let active_todos todos =
    List.filter todos ~f:(fun todo -> not todo.Todo.completed)

  let completed_todos todos =
    List.filter todos ~f:(fun todo -> todo.Todo.completed)

  let normalized value = value |> String.strip |> String.lowercase

  let matches_search ~search (todo : Todo.t) =
    match normalized search with
    | "" -> true
    | search -> String.is_substring (normalized todo.title) ~substring:search

  let visible_todos ~route ~search todos =
    todos
    |> List.filter ~f:(matches_search ~search)
    |> List.filter ~f:(fun (todo : Todo.t) ->
        match route with
        | Route.All -> true
        | Active -> not todo.completed
        | Completed -> todo.completed)

  let selected_todo model ~selected_todo_id =
    List.find model.Model.todos ~f:(fun (todo : Todo.t) ->
        String.equal todo.id selected_todo_id)

  let next_todo model =
    let created_at_ms =
      model.Model.todos
      |> List.map ~f:(fun todo -> todo.Todo.created_at_ms)
      |> List.max_elt ~compare:Int.compare
      |> Option.value ~default:0 |> ( + ) 1
    in
    { Action.id = Printf.sprintf "todo-%d" created_at_ms; created_at_ms }

  let create model ~route ~search ~selected_todo_id =
    let active_todos = active_todos model.Model.todos in
    let completed_todos = completed_todos model.todos in
    {
      title = Route.title route;
      empty_title = "No matching tasks";
      active_count = List.length active_todos;
      completed_count = List.length completed_todos;
      visible_todos = visible_todos ~route ~search model.todos;
      active_todos;
      completed_todos;
      selected_todo = selected_todo model ~selected_todo_id;
    }
end

module Controller = struct
  module Native = Bonsai_native

  type t = { model : Model.t; dispatch : Action.t -> Native.Action.t }

  type run_command =
    dispatch:(Action.t -> Native.Action.t) -> Command.t -> Native.Action.t

  let ignore_command ~dispatch:_ _command = Native.Action.ignore

  let component ?(run_command = ignore_command) graph =
    let model, set_model =
      Native.Graph.state graph ~key:"model" Model.initial
    in
    let rec dispatch action () =
      let next_model, commands = Model.update model action in
      set_model next_model ();
      List.iter commands ~f:(fun command -> run_command ~dispatch command ())
    in
    { model; dispatch }
end
