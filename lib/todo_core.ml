open! Core

module Todo = struct
  type t =
    { id : string
    ; title : string
    ; completed : bool
    ; created_at_ms : int
    }
end

module Store_write = struct
  type t =
    | Add of Todo.t
    | Toggle of string
    | Delete of string
    | Update_title of
        { id : string
        ; title : string
        }
end

module Store = struct
  module Ds = Datascript

  type t = Ds.db
  type write = Store_write.t =
    | Add of Todo.t
    | Toggle of string
    | Delete of string
    | Update_title of
        { id : string
        ; title : string
        }

  let attr_id = "todo/id"
  let attr_title = "todo/title"
  let attr_completed = "todo/completed"
  let attr_created_at_ms = "todo/created-at-ms"

  let schema_attr ?unique ?(indexed = false) ?value_type () : Ds.schema_attr =
    { cardinality = One
    ; unique
    ; indexed = indexed || Option.is_some unique
    ; is_component = false
    ; no_history = false
    ; doc = None
    ; value_type
    ; tuple_attrs = None
    ; tuple_types = None
    }
  ;;

  let schema : Ds.schema =
    [ attr_id, schema_attr ~unique:Identity ~value_type:StringType ()
    ; attr_title, schema_attr ~value_type:StringType ()
    ; attr_completed, schema_attr ()
    ; attr_created_at_ms, schema_attr ~indexed:true ~value_type:NumberType ()
    ]
  ;;

  let empty ?storage () = Ds.empty_db ~schema ?storage ()

  let restore_or_create storage =
    match Ds.restore storage with
    | Some db -> db
    | None ->
      (match storage.storage_list_addresses () with
       | [] ->
         let db = empty ~storage () in
         Ds.store ~storage db;
         db
       | addresses ->
         failwithf
           "Unable to restore non-empty todo storage (%d payloads)"
           (List.length addresses)
           ())
  ;;

  let lookup id = Ds.Lookup_ref (attr_id, Ds.String id)

  let transact db tx_ops =
    let report = Ds.transact db tx_ops in
    (match Ds.storage report.db_after with
     | None -> ()
     | Some storage -> Ds.store ~storage report.db_after);
    report.db_after
  ;;

  let add_todo_ops (todo : Todo.t) =
    let entity = Ds.Temp_id todo.id in
    [ Ds.Add (entity, attr_id, String todo.id)
    ; Ds.Add (entity, attr_title, String todo.title)
    ; Ds.Add (entity, attr_completed, Bool todo.completed)
    ; Ds.Add (entity, attr_created_at_ms, Int todo.created_at_ms)
    ]
  ;;

  let entity_for_id db id = Ds.entity db (lookup id)

  let one_string entity attr =
    match Ds.entity_attr entity attr with
    | Some (One_value (String value)) -> Some value
    | _ -> None
  ;;

  let one_bool entity attr =
    match Ds.entity_attr entity attr with
    | Some (One_value (Bool value)) -> Some value
    | _ -> None
  ;;

  let one_int entity attr =
    match Ds.entity_attr entity attr with
    | Some (One_value (Int value)) -> Some value
    | _ -> None
  ;;

  let todo_of_entity entity : Todo.t option =
    let open Option.Let_syntax in
    let%bind id = one_string entity attr_id in
    let%bind title = one_string entity attr_title in
    let completed = Option.value (one_bool entity attr_completed) ~default:false in
    let%bind created_at_ms = one_int entity attr_created_at_ms in
    Some { Todo.id; title; completed; created_at_ms }
  ;;

  let apply_write db = function
    | Add todo -> transact db (add_todo_ops todo)
    | Toggle id ->
      (match entity_for_id db id |> Option.bind ~f:todo_of_entity with
       | None -> db
       | Some todo ->
         transact db [ Ds.Add (lookup id, attr_completed, Bool (not todo.completed)) ])
    | Delete id -> transact db [ Ds.RetractEntity (lookup id) ]
    | Update_title { id; title } ->
      (match entity_for_id db id with
       | None -> db
       | Some _ -> transact db [ Ds.Add (lookup id, attr_title, String title) ])
  ;;

  let list db =
    Ds.datoms db Aevt ~a:attr_id ()
    |> Seq.filter_map (fun datom -> Ds.entity db (Entity_id datom.Ds.e))
    |> Seq.filter_map todo_of_entity
    |> Stdlib.List.of_seq
    |> List.sort ~compare:(fun left right ->
      Comparable.lift
        [%compare: bool * int * string]
        ~f:(fun (todo : Todo.t) -> todo.completed, todo.created_at_ms, todo.id)
        left
        right)
  ;;
end

module Storage_codec = struct
  module Ds = Datascript
  module PSet = Persistent_sorted_set
  module Transit = Todos_transit

  open Ds

  let schema_attr_default : Ds.schema_attr =
    { cardinality = One
    ; unique = None
    ; indexed = false
    ; is_component = false
    ; no_history = false
    ; doc = None
    ; value_type = None
    ; tuple_attrs = None
    ; tuple_types = None
    }
  ;;

  let string_of_transit_key = function
    | Transit.Keyword value | Transit.String value -> Some value
    | _ -> None
  ;;

  let keyword_of_transit = function
    | Transit.Keyword value -> Some value
    | _ -> None
  ;;

  let bool_of_transit = function
    | Transit.Bool value -> Some value
    | _ -> None
  ;;

  let string_of_transit = function
    | Transit.String value -> Some value
    | _ -> None
  ;;

  let int_of_transit_value = function
    | Transit.Int value -> Some value
    | Transit.Int64 value ->
      if Int64.compare value (Int64.of_int Int.min_value) >= 0
         && Int64.compare value (Int64.of_int Int.max_value) <= 0
      then Some (Int64.to_int_exn value)
      else None
    | _ -> None
  ;;

  let lookup_transit_key key entries =
    List.find_map entries ~f:(fun (entry_key, value) ->
      match string_of_transit_key entry_key with
      | Some entry_key when String.equal entry_key key -> Some value
      | _ -> None)
  ;;

  let transit_of_cardinality = function
    | One -> Transit.Keyword "db.cardinality/one"
    | Many -> Transit.Keyword "db.cardinality/many"
  ;;

  let cardinality_of_transit = function
    | Transit.Keyword "db.cardinality/many" -> Many
    | Transit.Keyword "db.cardinality/one" -> One
    | _ -> One
  ;;

  let transit_of_unique = function
    | Value -> Transit.Keyword "db.unique/value"
    | Identity -> Transit.Keyword "db.unique/identity"
  ;;

  let unique_of_transit = function
    | Transit.Keyword "db.unique/value" -> Some Value
    | Transit.Keyword "db.unique/identity" -> Some Identity
    | _ -> None
  ;;

  let transit_of_value_type = function
    | RefType -> Transit.Keyword "db.type/ref"
    | StringType -> Transit.Keyword "db.type/string"
    | KeywordType -> Transit.Keyword "db.type/keyword"
    | NumberType -> Transit.Keyword "db.type/number"
    | UuidType -> Transit.Keyword "db.type/uuid"
    | InstantType -> Transit.Keyword "db.type/instant"
    | TupleType -> Transit.Keyword "db.type/tuple"
  ;;

  let value_type_of_transit = function
    | Transit.Keyword "db.type/ref" -> Some RefType
    | Transit.Keyword "db.type/string" -> Some StringType
    | Transit.Keyword "db.type/keyword" -> Some KeywordType
    | Transit.Keyword "db.type/number" -> Some NumberType
    | Transit.Keyword "db.type/uuid" -> Some UuidType
    | Transit.Keyword "db.type/instant" -> Some InstantType
    | Transit.Keyword "db.type/tuple" -> Some TupleType
    | _ -> None
  ;;

  let transit_of_ref_type = function
    | PSet.Strong -> Transit.Keyword "strong"
    | PSet.Weak -> Transit.Keyword "weak"
  ;;

  let ref_type_of_transit = function
    | Transit.Keyword "soft" -> PSet.Weak
    | Transit.Keyword "weak" -> PSet.Weak
    | Transit.Keyword "strong" | _ -> PSet.Strong
  ;;

  let address_to_transit address = Transit.String address

  let address_of_transit label = function
    | Transit.String address -> address
    | Transit.Int address -> Int.to_string address
    | Transit.Int64 address -> Int64.to_string address
    | _ -> invalid_arg (label ^ " must be a storage address")
  ;;

  let transit_of_tuple_attrs attrs =
    Transit.Array (List.map attrs ~f:(fun attr -> Transit.Keyword attr))
  ;;

  let transit_of_tuple_types types = Transit.Array (List.map types ~f:transit_of_value_type)

  let schema_attr_to_transit attr =
    let entries = ref [] in
    let add key value = entries := (Transit.Keyword key, value) :: !entries in
    (match attr.cardinality with
     | One -> ()
     | Many -> add "db/cardinality" (transit_of_cardinality attr.cardinality));
    Option.iter attr.unique ~f:(fun unique -> add "db/unique" (transit_of_unique unique));
    if attr.indexed then add "db/index" (Transit.Bool true);
    if attr.is_component then add "db/isComponent" (Transit.Bool true);
    if attr.no_history then add "db/noHistory" (Transit.Bool true);
    Option.iter attr.doc ~f:(fun doc -> add "db/doc" (Transit.String doc));
    Option.iter attr.value_type ~f:(fun value_type ->
      add "db/valueType" (transit_of_value_type value_type));
    Option.iter attr.tuple_attrs ~f:(fun attrs ->
      add "db/tupleAttrs" (transit_of_tuple_attrs attrs));
    Option.iter attr.tuple_types ~f:(fun types ->
      add "db/tupleTypes" (transit_of_tuple_types types));
    Transit.Map (List.rev !entries)
  ;;

  let schema_to_transit schema =
    Transit.Map
      (List.map schema ~f:(fun (attr, schema_attr) ->
         Transit.Keyword attr, schema_attr_to_transit schema_attr))
  ;;

  let tuple_attrs_of_transit = function
    | Transit.Array values | Transit.List values -> Some (List.filter_map values ~f:keyword_of_transit)
    | _ -> None
  ;;

  let tuple_types_of_transit = function
    | Transit.Array values | Transit.List values ->
      let types = List.filter_map values ~f:value_type_of_transit in
      if List.length types = List.length values then Some types else None
    | _ -> None
  ;;

  let schema_attr_of_transit = function
    | Transit.Map props ->
      List.fold props ~init:schema_attr_default ~f:(fun schema (key, value) ->
        match keyword_of_transit key with
        | Some "db/cardinality" ->
          { schema with cardinality = cardinality_of_transit value }
        | Some "db/unique" -> { schema with unique = unique_of_transit value }
        | Some "db/index" ->
          { schema with indexed = Option.value (bool_of_transit value) ~default:false }
        | Some "db/isComponent" ->
          { schema with is_component = Option.value (bool_of_transit value) ~default:false }
        | Some "db/noHistory" ->
          { schema with no_history = Option.value (bool_of_transit value) ~default:false }
        | Some "db/doc" -> { schema with doc = string_of_transit value }
        | Some "db/valueType" ->
          { schema with value_type = value_type_of_transit value }
        | Some "db/tupleAttrs" ->
          { schema with tuple_attrs = tuple_attrs_of_transit value }
        | Some "db/tupleTypes" ->
          { schema with tuple_types = tuple_types_of_transit value }
        | Some _ | None -> schema)
    | _ -> schema_attr_default
  ;;

  let schema_of_transit = function
    | Transit.Map entries ->
      List.filter_map entries ~f:(fun (attr, schema_attr) ->
        match keyword_of_transit attr with
        | Some attr -> Some (attr, schema_attr_of_transit schema_attr)
        | None -> None)
    | _ -> []
  ;;

  let rec value_to_transit = function
    | Ds.Nil -> Transit.Null
    | Int value -> Transit.Int value
    | Float value -> Transit.Float value
    | String value -> Transit.String value
    | Symbol value -> Transit.Symbol value
    | Bool value -> Transit.Bool value
    | Keyword value -> Transit.Keyword value
    | Uuid value -> Transit.Tagged ("u", Transit.String value)
    | Instant value -> Transit.Tagged ("m", Transit.Int value)
    | Regex value -> Transit.Tagged ("regex", Transit.String value)
    | Ref entity_id -> Transit.Int entity_id
    | List values -> Transit.List (List.map values ~f:value_to_transit)
    | Vector values -> Transit.Array (List.map values ~f:value_to_transit)
    | Map entries ->
      Transit.Map
        (List.map entries ~f:(fun (key, value) ->
           value_to_transit key, value_to_transit value))
    | Set values -> Transit.Set (List.map values ~f:value_to_transit)
    | Tuple values ->
      Transit.Array
        (List.map values ~f:(function
           | None -> Transit.Null
           | Some value -> value_to_transit value))
    | TxRef -> Transit.Keyword "db/current-tx"
    | Ref_to _ -> invalid_arg "storage payload cannot contain unresolved refs"
  ;;

  let rec value_of_transit = function
    | Transit.Null -> Ds.Nil
    | Bool value -> Bool value
    | String value -> String value
    | Int value -> Int value
    | Int64 value ->
      if Int64.compare value (Int64.of_int Int.min_value) >= 0
         && Int64.compare value (Int64.of_int Int.max_value) <= 0
      then Int (Int64.to_int_exn value)
      else Instant (Int64.to_int_exn value)
    | Float value -> Float value
    | Keyword value -> Keyword value
    | Symbol value -> Symbol value
    | Array values -> Vector (List.map values ~f:value_of_transit)
    | Map entries ->
      Map
        (List.map entries ~f:(fun (key, value) ->
           value_of_transit key, value_of_transit value))
    | Set values -> Set (List.map values ~f:value_of_transit)
    | List values -> List (List.map values ~f:value_of_transit)
    | Tagged ("u", Transit.String value) -> Uuid value
    | Tagged ("m", Transit.Int value) -> Instant value
    | Tagged ("m", Transit.Int64 value) -> Instant (Int64.to_int_exn value)
    | Tagged ("regex", Transit.String value) -> Regex value
    | Tagged (tag, value) -> Vector [ String tag; value_of_transit value ]
  ;;

  let datom_to_transit datom =
    let tx = if datom.Ds.added then datom.tx else -datom.tx in
    Transit.Array
      [ Transit.Int datom.e
      ; Transit.Keyword datom.a
      ; value_to_transit datom.v
      ; Transit.Int tx
      ]
  ;;

  let int_of_transit label value =
    match int_of_transit_value value with
    | Some value -> value
    | None -> invalid_arg (label ^ " must be a Transit integer")
  ;;

  let datom_of_transit = function
    | Transit.Array [ entity; attr; value; tx ] ->
      let e = int_of_transit "datom entity" entity in
      let a =
        match keyword_of_transit attr with
        | Some attr -> attr
        | None -> invalid_arg "datom attr must be a Transit keyword"
      in
      let tx = int_of_transit "datom tx" tx in
      Ds.datom ~e ~a ~v:(value_of_transit value) ~tx:(abs tx) ~added:(tx >= 0) ()
    | _ -> invalid_arg "storage datom must be [e a v tx]"
  ;;

  let datoms_to_transit datoms = Transit.Array (List.map datoms ~f:datom_to_transit)

  let datoms_of_transit = function
    | Transit.Array datoms | Transit.List datoms -> List.map datoms ~f:datom_of_transit
    | _ -> invalid_arg "storage datoms must be a Transit array"
  ;;

  let storage_root_to_transit root =
    Transit.Map
      [ Transit.Keyword "schema", schema_to_transit root.storage_schema
      ; Transit.Keyword "max-eid", Transit.Int root.storage_max_eid
      ; Transit.Keyword "max-tx", Transit.Int root.storage_max_tx
      ; Transit.Keyword "eavt", address_to_transit root.storage_eavt
      ; Transit.Keyword "aevt", address_to_transit root.storage_aevt
      ; Transit.Keyword "avet", address_to_transit root.storage_avet
      ; Transit.Keyword "duplicate-datoms", datoms_to_transit root.storage_duplicate_datoms
      ; Transit.Keyword "max-addr", Transit.Int root.storage_max_addr
      ; Transit.Keyword "branching-factor", Transit.Int root.storage_branching_factor
      ; Transit.Keyword "ref-type", transit_of_ref_type root.storage_ref_type
      ]
  ;;

  let storage_node_to_transit = function
    | PSet.Leaf datoms ->
      Transit.Map
        [ Transit.Keyword "keys", datoms_to_transit datoms ]
    | PSet.Branch (keys, child_addresses) ->
      Transit.Map
        [ Transit.Keyword "keys", datoms_to_transit keys
        ; ( Transit.Keyword "children"
          , Transit.Array (List.map child_addresses ~f:address_to_transit) )
        ]
  ;;

  let storage_tail_to_transit groups =
    Transit.Array (List.map groups ~f:(fun group -> datoms_to_transit group))
  ;;

  let payload_to_transit = function
    | Ds.Storage_root root -> storage_root_to_transit root
    | Storage_node node -> storage_node_to_transit node
    | Storage_tail groups -> storage_tail_to_transit groups
  ;;

  let require_key key entries =
    match lookup_transit_key key entries with
    | Some value -> value
    | None -> invalid_arg ("storage payload is missing :" ^ key)
  ;;

  let optional_datoms key entries =
    match lookup_transit_key key entries with
    | None -> []
    | Some value -> datoms_of_transit value
  ;;

  let storage_root_of_transit entries =
    { Ds.storage_schema = schema_of_transit (require_key "schema" entries)
    ; storage_max_eid = int_of_transit "storage root :max-eid" (require_key "max-eid" entries)
    ; storage_max_tx = int_of_transit "storage root :max-tx" (require_key "max-tx" entries)
    ; storage_eavt = address_of_transit "storage root :eavt" (require_key "eavt" entries)
    ; storage_aevt = address_of_transit "storage root :aevt" (require_key "aevt" entries)
    ; storage_avet = address_of_transit "storage root :avet" (require_key "avet" entries)
    ; storage_duplicate_datoms = optional_datoms "duplicate-datoms" entries
    ; storage_max_addr = int_of_transit "storage root :max-addr" (require_key "max-addr" entries)
    ; storage_branching_factor =
        int_of_transit "storage root :branching-factor" (require_key "branching-factor" entries)
    ; storage_ref_type = ref_type_of_transit (require_key "ref-type" entries)
    }
  ;;

  let child_addresses_of_transit = function
    | Transit.Array values | Transit.List values ->
      List.map values ~f:(address_of_transit "storage node :children")
    | _ -> invalid_arg "storage node :children must be a Transit array"
  ;;

  let storage_node_of_transit entries =
    let keys = datoms_of_transit (require_key "keys" entries) in
    match lookup_transit_key "children" entries with
    | None -> PSet.Leaf keys
    | Some children -> PSet.Branch (keys, child_addresses_of_transit children)
  ;;

  let storage_tail_of_transit = function
    | Transit.Array groups | Transit.List groups -> List.map groups ~f:datoms_of_transit
    | _ -> invalid_arg "storage tail must be a Transit array"
  ;;

  let payload_of_transit = function
    | Transit.Map entries ->
      if Option.is_some (lookup_transit_key "schema" entries)
      then Ds.Storage_root (storage_root_of_transit entries)
      else if Option.is_some (lookup_transit_key "keys" entries)
      then Storage_node (storage_node_of_transit entries)
      else invalid_arg "unknown storage payload map"
    | (Transit.Array _ | Transit.List _) as tail -> Storage_tail (storage_tail_of_transit tail)
    | _ -> invalid_arg "unknown storage payload"
  ;;

  let encode payload = payload |> payload_to_transit |> Transit.to_string
  let decode content = content |> Transit.of_string |> payload_of_transit
end

module Query = struct
  type t = List_todos [@@deriving equal, sexp_of]
end

module Command = struct
  type target = Background

  type request =
    | Load_all
    | Persist of Store_write.t
    | Subscribe_query of
        { id : string
        ; query : Query.t
        }
    | Unsubscribe_query of string

  type t =
    { target : target
    ; request : request
    }
end

module Action = struct
  type new_todo =
    { id : string
    ; created_at_ms : int
    }

  type t =
    | Load
    | Loaded of Todo.t list
    | Store_failed of string
    | Set_draft of string
    | Submit_new of new_todo
    | Update_title of
        { id : string
        }
    | Toggle of string
    | Delete of string
    | Subscribe_query of
        { id : string
        ; query : Query.t
        }
    | Unsubscribe_query of string
end

module Model = struct
  type t =
    { draft : string
    ; todos : Todo.t list
    ; is_loading : bool
    ; error : string option
    }

  let initial = { draft = ""; todos = []; is_loading = false; error = None }
  let background request : Command.t = { target = Background; request }

  let update model (action : Action.t) =
    match action with
    | Action.Load -> { model with is_loading = true; error = None }, [ background Load_all ]
    | Action.Loaded todos -> { model with todos; is_loading = false; error = None }, []
    | Action.Store_failed error -> { model with is_loading = false; error = Some error }, []
    | Action.Set_draft draft -> { model with draft }, []
    | Action.Submit_new { id; created_at_ms } ->
      let title = String.strip model.draft in
      if String.is_empty title
      then model, []
      else (
        let todo = { Todo.id; title; completed = false; created_at_ms } in
        { model with draft = ""; error = None }, [ background (Persist (Add todo)) ])
    | Action.Update_title { id } ->
      let title = String.strip model.draft in
      if String.is_empty title
      then model, []
      else
        ( { model with draft = ""; error = None }
        , [ background (Persist (Update_title { id; title })) ] )
    | Action.Toggle id -> model, [ background (Persist (Toggle id)) ]
    | Action.Delete id -> model, [ background (Persist (Delete id)) ]
    | Action.Subscribe_query { id; query } ->
      model, [ background (Subscribe_query { id; query }) ]
    | Action.Unsubscribe_query id -> model, [ background (Unsubscribe_query id) ]
  ;;
end

module Screen = struct
  module Route = struct
    type t =
      | All
      | Active
      | Completed
    [@@deriving equal]

    let all_id = "all"
    let active_id = "active"
    let completed_id = "completed"

    let id = function
      | All -> all_id
      | Active -> active_id
      | Completed -> completed_id
    ;;

    let of_id = function
      | "active" -> Active
      | "completed" -> Completed
      | _ -> All
    ;;

    let title = function
      | All -> "Tasks"
      | Active -> "Active"
      | Completed -> "Completed"
    ;;
  end

  type t =
    { title : string
    ; empty_title : string
    ; active_count : int
    ; completed_count : int
    ; visible_todos : Todo.t list
    ; active_todos : Todo.t list
    ; completed_todos : Todo.t list
    ; selected_todo : Todo.t option
    }

  let active_todos todos = List.filter todos ~f:(fun todo -> not todo.Todo.completed)
  let completed_todos todos = List.filter todos ~f:(fun todo -> todo.Todo.completed)
  let normalized value = value |> String.strip |> String.lowercase

  let matches_search ~search (todo : Todo.t) =
    match normalized search with
    | "" -> true
    | search -> String.is_substring (normalized todo.title) ~substring:search
  ;;

  let visible_todos ~route ~search todos =
    todos
    |> List.filter ~f:(matches_search ~search)
    |> List.filter ~f:(fun (todo : Todo.t) ->
      match route with
      | Route.All -> true
      | Active -> not todo.completed
      | Completed -> todo.completed)
  ;;

  let selected_todo model ~selected_todo_id =
    List.find model.Model.todos ~f:(fun (todo : Todo.t) ->
      String.equal todo.id selected_todo_id)
  ;;

  let next_todo model =
    let created_at_ms =
      model.Model.todos
      |> List.map ~f:(fun todo -> todo.Todo.created_at_ms)
      |> List.max_elt ~compare:Int.compare
      |> Option.value ~default:0
      |> Int.( + ) 1
    in
    { Action.id = [%string "todo-%{created_at_ms#Int}"]; created_at_ms }
  ;;

  let create model ~route ~search ~selected_todo_id =
    let active_todos = active_todos model.Model.todos in
    let completed_todos = completed_todos model.todos in
    { title = Route.title route
    ; empty_title = "No matching tasks"
    ; active_count = List.length active_todos
    ; completed_count = List.length completed_todos
    ; visible_todos = visible_todos ~route ~search model.todos
    ; active_todos
    ; completed_todos
    ; selected_todo = selected_todo model ~selected_todo_id
    }
  ;;
end

module Controller = struct
  type t =
    { model : Model.t
    ; dispatch : Action.t -> unit Bonsai.Effect.t
    }

  let ignore_command ~dispatch:_ _command = Bonsai.Effect.Ignore

  let component ?(run_command = ignore_command) graph =
    let open Bonsai.Let_syntax in
    let model, dispatch =
      Bonsai.state_machine
        ~default_model:Model.initial
        ~apply_action:(fun context model action ->
          let dispatch = Bonsai.Apply_action_context.inject context in
          let next_model, commands = Model.update model action in
          List.iter commands ~f:(fun command ->
            Bonsai.Apply_action_context.schedule_event
              context
              (run_command ~dispatch command));
          next_model)
        graph
    in
    let%arr model and dispatch in
    { model; dispatch }
  ;;
end
