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
      (attr_title, schema_attr ~indexed:true ~value_type:StringType ());
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
        let left_key = (left.created_at_ms, left.id) in
        let right_key = (right.created_at_ms, right.id) in
        compare left_key right_key)

  let page_of_seq ~limit ~offset seq =
    let limit = max 0 limit in
    let offset = max 0 offset in
    let rec drop remaining seq =
      if remaining = 0 then seq
      else
        match seq () with
        | Seq.Nil -> Seq.empty
        | Cons (_, seq) -> drop (remaining - 1) seq
    in
    let rec take remaining seq acc =
      if remaining = 0 then List.rev acc
      else
        match seq () with
        | Seq.Nil -> List.rev acc
        | Cons (value, seq) -> take (remaining - 1) seq (value :: acc)
    in
    let rows = take (limit + 1) (drop offset seq) [] in
    let todos = take limit (List.to_seq rows) [] in
    let has_more = List.length rows > limit in
    (todos, has_more)

  let list_page db ~limit ~offset =
    Ds.datoms db Aevt ~a:attr_created_at_ms ()
    |> Seq.filter_map (fun datom -> Ds.entity db (Entity_id datom.Ds.e))
    |> Seq.filter_map todo_of_entity
    |> page_of_seq ~limit ~offset

  let normalized value = value |> String.strip |> String.lowercase

  let title_search_page db ~limit ~offset ~search =
    let search = normalized search in
    if String.is_empty search then list_page db ~limit ~offset
    else
      Ds.datoms db Aevt ~a:attr_title ()
      |> Seq.filter_map (fun datom ->
          match datom.Ds.v with
          | Ds.String title
            when String.is_substring (normalized title) ~substring:search ->
              Some datom.Ds.e
          | _ -> None)
      |> Seq.filter_map (fun entity_id -> Ds.entity db (Entity_id entity_id))
      |> Seq.filter_map todo_of_entity
      |> page_of_seq ~limit ~offset
end

module Command = struct
  type target = Background
  type page = { limit : int; offset : int; search : string }
  type request = Load_page of page | Persist of Store_write.t
  type t = { target : target; request : request }
end

module Action = struct
  type new_todo = { id : string; created_at_ms : int }

  type loaded_page = {
    todos : Todo.t list;
    has_more : bool;
    offset : int;
    search : string;
  }

  type t =
    | Load_page of Command.page
    | Loaded_page of loaded_page
    | Store_failed of string
    | Persisted of Store_write.t
    | Set_draft of string
    | Submit_new of new_todo
    | Update_title of { id : string }
    | Toggle of string
    | Delete of string
end

module Model = struct
  type t = {
    draft : string;
    todos : Todo.t list;
    loaded_count : int;
    current_search : string;
    has_more : bool;
    is_loading : bool;
    error : string option;
  }

  let initial =
    {
      draft = "";
      todos = [];
      loaded_count = 0;
      current_search = "";
      has_more = false;
      is_loading = false;
      error = None;
    }

  let max_model_todos = 240

  let keep_recent_todos todos =
    let extra = List.length todos - max_model_todos in
    if extra <= 0 then todos
    else
      let rec drop remaining todos =
        match (remaining, todos) with
        | 0, todos | _, ([] as todos) -> todos
        | remaining, _ :: todos -> drop (remaining - 1) todos
      in
      drop extra todos

  let background request : Command.t = { target = Background; request }

  let apply_write_to_todos todos = function
    | Store_write.Add todo ->
        todos @ [ todo ]
        |> List.sort ~compare:(fun (left : Todo.t) (right : Todo.t) ->
            let left_key = (left.created_at_ms, left.id) in
            let right_key = (right.created_at_ms, right.id) in
            compare left_key right_key)
    | Toggle id ->
        List.map todos ~f:(fun (todo : Todo.t) ->
            if String.equal todo.id id then
              { todo with completed = not todo.completed }
            else todo)
    | Delete id ->
        List.filter todos ~f:(fun (todo : Todo.t) ->
            not (String.equal todo.id id))
    | Update_title { id; title } ->
        List.map todos ~f:(fun (todo : Todo.t) ->
            if String.equal todo.id id then { todo with title } else todo)

  let update model (action : Action.t) =
    match action with
    | Action.Load_page ({ Command.limit; offset; _ } as page) ->
        ( { model with is_loading = true; error = None },
          [
            background
              (Load_page
                 { page with limit = max 0 limit; offset = max 0 offset });
          ] )
    | Action.Loaded_page { todos; has_more; offset; search } ->
        let page_count = List.length todos in
        let todos =
          if offset = 0 || not (String.equal search model.current_search) then
            todos
          else model.todos @ todos
        in
        let loaded_count = max 0 offset + page_count in
        ( {
            model with
            todos = keep_recent_todos todos;
            loaded_count;
            current_search = search;
            has_more;
            is_loading = false;
            error = None;
          },
          [] )
    | Action.Persisted _write -> (model, [])
    | Action.Store_failed error ->
        ({ model with is_loading = false; error = Some error }, [])
    | Action.Set_draft draft -> ({ model with draft }, [])
    | Action.Submit_new { id; created_at_ms } ->
        let title = String.strip model.draft in
        if String.is_empty title then (model, [])
        else
          let todo = { Todo.id; title; completed = false; created_at_ms } in
          ( {
              model with
              draft = "";
              error = None;
              todos =
                apply_write_to_todos model.todos (Add todo) |> keep_recent_todos;
              loaded_count = model.loaded_count + 1;
            },
            [ background (Persist (Add todo)) ] )
    | Action.Update_title { id } ->
        let title = String.strip model.draft in
        if String.is_empty title then (model, [])
        else
          ( {
              model with
              draft = "";
              error = None;
              todos =
                apply_write_to_todos model.todos (Update_title { id; title })
                |> keep_recent_todos;
            },
            [ background (Persist (Update_title { id; title })) ] )
    | Action.Toggle id ->
        ( { model with todos = apply_write_to_todos model.todos (Toggle id) },
          [ background (Persist (Toggle id)) ] )
    | Action.Delete id ->
        ( { model with todos = apply_write_to_todos model.todos (Delete id) },
          [ background (Persist (Delete id)) ] )
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
  type 'action t = { model : Model.t; dispatch : Action.t -> 'action }
end
