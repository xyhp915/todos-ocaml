open! Core

module Apple = Bonsai_apple
module Todos = Todo_core
module Screen = Todos.Screen
module Route = Screen.Route

type controls =
  { route : Route.t
  ; search : string
  ; selected_todo_id : string
  ; set_route : Route.t -> unit Bonsai.Effect.t
  ; set_search : string -> unit Bonsai.Effect.t
  ; set_selected_todo_id : string -> unit Bonsai.Effect.t
  }

let default_controls =
  { route = Route.All
  ; search = ""
  ; selected_todo_id = ""
  ; set_route = (fun _ -> Bonsai.Effect.Ignore)
  ; set_search = (fun _ -> Bonsai.Effect.Ignore)
  ; set_selected_todo_id = (fun _ -> Bonsai.Effect.Ignore)
  }
;;

let next_todo = Screen.next_todo

let empty_state title =
  Apple.vstack
    ~spacing:8.
    [ Apple.text ~style:Title3 ~weight:Semibold title
    ; Apple.text ~color:Secondary "Nothing here right now."
    ]
  |> Apple.padding
;;

let add_bar ?field_width model ~dispatch =
  let field =
    Apple.text_field
      ~text:model.Todos.Model.draft
      ~placeholder:"New task"
      ~on_change:(fun draft -> dispatch (Todos.Action.Set_draft draft))
      ()
  in
  let field =
    match field_width with
    | None -> field
    | Some width -> Apple.frame ~width field
  in
  Apple.hstack
    ~spacing:8.
    [ field
    ; Apple.button "Add" ~on_click:(dispatch (Todos.Action.Submit_new (next_todo model)))
    ]
;;

let todo_row ~dispatch ?on_select (todo : Todos.Todo.t) =
  let leading_button : Apple.row_leading_button =
    { system_image = "circle"
    ; selected_system_image = Some "checkmark.circle.fill"
    ; selected = todo.completed
    ; accessibility_label =
        (if todo.completed then "Mark incomplete" else "Mark complete")
    ; on_click = dispatch (Todos.Action.Toggle todo.id)
    }
  in
  let delete_action : Apple.row_action =
    { title = "Delete"
    ; system_image = Some "trash"
    ; style = Destructive
    ; on_click = dispatch (Todos.Action.Delete todo.id)
    }
  in
  Apple.list_row
    { title = todo.title
    ; subtitle = Some [%string "Created %{todo.created_at_ms#Int}"]
    ; trailing_text = (if todo.completed then Some "Done" else None)
    ; title_strikethrough = todo.completed
    ; on_click = Option.map on_select ~f:(fun on_select -> on_select todo.id)
    ; leading_button = Some leading_button
    ; swipe_actions = [ delete_action ]
    }
;;

let route_row ~selected ~on_select route =
  let title = Route.title route in
  Apple.list_row
    { title
    ; subtitle = None
    ; trailing_text = (if Route.equal route selected then Some "Selected" else None)
    ; title_strikethrough = false
    ; on_click = Some (on_select route)
    ; leading_button = None
    ; swipe_actions = []
    }
;;

let sidebar ~route ~set_route =
  Apple.list
    [ Route.All; Active; Completed ]
    ~key:Route.id
    ~row:(route_row ~selected:route ~on_select:set_route)
;;

let content_list model ~route ~search ~set_selected_todo_id ~dispatch =
  let todos = Screen.visible_todos ~route ~search model.Todos.Model.todos in
  match todos with
  | [] -> empty_state "No matching tasks"
  | todos ->
    Apple.list
      todos
      ~key:(fun (todo : Todos.Todo.t) -> todo.id)
      ~row:(todo_row ~dispatch ~on_select:set_selected_todo_id)
;;

let detail_view screen =
  match screen.Screen.selected_todo with
  | None ->
    Apple.vstack
      ~spacing:8.
      [ Apple.text ~style:Title3 ~weight:Semibold "Select a task"
      ; Apple.text ~color:Secondary "Choose a task from the list."
      ]
    |> Apple.padding
  | Some todo ->
    Apple.vstack
      ~spacing:12.
      [ Apple.text ~style:Title2 ~weight:Semibold todo.title
      ; Apple.text ~color:Secondary (if todo.completed then "Completed" else "Active")
      ; Apple.text ~color:Secondary [%string "Created %{todo.created_at_ms#Int}"]
      ]
    |> Apple.padding
;;

let split_view model controls ~dispatch =
  let screen =
    Screen.create
      model
      ~route:controls.route
      ~search:controls.search
      ~selected_todo_id:controls.selected_todo_id
  in
  Apple.navigation_split
    ~sidebar:(sidebar ~route:controls.route ~set_route:controls.set_route)
    ~content:
      (Apple.vstack
         ~spacing:16.
         [ Apple.vstack
             ~spacing:4.
             [ Apple.text ~style:Title2 ~weight:Semibold screen.title
             ; Apple.text
                 ~color:Secondary
                 [%string
                   "%{screen.active_count#Int} active, %{screen.completed_count#Int} completed"]
             ]
         ; add_bar ~field_width:420. model ~dispatch
         ; (match model.error with
            | None -> Apple.text ""
            | Some error -> Apple.text ~color:Secondary error)
         ; content_list
             model
             ~route:controls.route
             ~search:controls.search
             ~set_selected_todo_id:controls.set_selected_todo_id
             ~dispatch
         ]
       |> Apple.padding)
    ~detail:(detail_view screen)
  |> Apple.searchable ~text:controls.search ~on_change:controls.set_search
  |> Apple.toolbar
       [ Apple.toolbar_item
           ~id:"add"
           ~title:"Add"
           ~on_click:(dispatch (Todos.Action.Submit_new (next_todo model)))
       ; Apple.toolbar_item ~id:"reload" ~title:"Reload" ~on_click:(dispatch Todos.Action.Load)
       ]
;;

let view ?(controls = default_controls) ({ model; dispatch } : Todos.Controller.t) =
  split_view model controls ~dispatch
;;

let component ?(run_command = Todos.Controller.ignore_command) graph =
  let open Bonsai.Let_syntax in
  let controller = Todos.Controller.component ~run_command graph in
  let route, set_route = Bonsai.state Route.All graph in
  let search, set_search = Bonsai.state "" graph in
  let selected_todo_id, set_selected_todo_id = Bonsai.state "" graph in
  let on_activate =
    let%arr controller in
    let open Bonsai.Effect.Let_syntax in
    let%bind () = controller.dispatch Todos.Action.Load in
    controller.dispatch
      (Todos.Action.Subscribe_query { id = "todos"; query = Todos.Query.List_todos })
  in
  let on_deactivate =
    let%arr controller in
    controller.dispatch (Todos.Action.Unsubscribe_query "todos")
  in
  Bonsai.Edge.lifecycle ~on_activate ~on_deactivate graph;
  let%arr controller
  and route
  and set_route
  and search
  and set_search
  and selected_todo_id
  and set_selected_todo_id in
  view
    controller
    ~controls:
      { route; search; selected_todo_id; set_route; set_search; set_selected_todo_id }
;;
