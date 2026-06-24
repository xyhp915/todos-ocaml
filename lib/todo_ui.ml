open! Core

module Apple = Bonsai_apple
module Todos = Todo_core
module Screen = Todos.Screen
module Route = Screen.Route

type controls =
  { route : Route.t
  ; search : string
  ; selected_todo_id : string
  ; mobile_tab : string
  ; mobile_new_task_presented : bool
  ; editing_todo_id : string
  ; set_route : Route.t -> unit Bonsai.Effect.t
  ; set_search : string -> unit Bonsai.Effect.t
  ; set_selected_todo_id : string -> unit Bonsai.Effect.t
  ; set_mobile_tab : string -> unit Bonsai.Effect.t
  ; set_mobile_new_task_presented : bool -> unit Bonsai.Effect.t
  ; set_editing_todo_id : string -> unit Bonsai.Effect.t
  }

let today_tab = "today"
let upcoming_tab = "upcoming"
let add_tab = "add"
let search_tab = "search"

let default_controls =
  { route = Route.All
  ; search = ""
  ; selected_todo_id = ""
  ; mobile_tab = today_tab
  ; mobile_new_task_presented = false
  ; editing_todo_id = ""
  ; set_route = (fun _ -> Bonsai.Effect.Ignore)
  ; set_search = (fun _ -> Bonsai.Effect.Ignore)
  ; set_selected_todo_id = (fun _ -> Bonsai.Effect.Ignore)
  ; set_mobile_tab = (fun _ -> Bonsai.Effect.Ignore)
  ; set_mobile_new_task_presented = (fun _ -> Bonsai.Effect.Ignore)
  ; set_editing_todo_id = (fun _ -> Bonsai.Effect.Ignore)
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

let add_bar model ~dispatch =
  let field =
    Apple.text_field
      ~text:model.Todos.Model.draft
      ~placeholder:"New task"
      ~on_change:(fun draft -> dispatch (Todos.Action.Set_draft draft))
      ()
  in
  Apple.hstack
    ~spacing:8.
    [ field
    ; Apple.button "Add" ~on_click:(dispatch (Todos.Action.Submit_new (next_todo model)))
    ]
;;

let todo_row ~dispatch ?on_select ?on_edit (todo : Todos.Todo.t) =
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
  let edit_actions =
    match on_edit with
    | None -> []
    | Some on_edit ->
      [ ({ title = "Edit"
        ; system_image = Some "pencil"
        ; style = Default
        ; on_click = on_edit todo
        } : Apple.row_action)
      ]
  in
  Apple.list_row
    { title = todo.title
    ; subtitle = Some [%string "Created %{todo.created_at_ms#Int}"]
    ; trailing_text = (if todo.completed then Some "Done" else None)
    ; title_strikethrough = todo.completed
    ; on_click = Option.map on_select ~f:(fun on_select -> on_select todo.id)
    ; leading_button = Some leading_button
    ; swipe_actions = edit_actions @ [ delete_action ]
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

let content_list ?on_edit model ~route ~search ~set_selected_todo_id ~dispatch =
  let todos = Screen.visible_todos ~route ~search model.Todos.Model.todos in
  match todos with
  | [] -> empty_state "No matching tasks"
  | todos ->
    Apple.list
      todos
      ~key:(fun (todo : Todos.Todo.t) -> todo.id)
      ~row:(todo_row ~dispatch ~on_select:set_selected_todo_id ?on_edit)
;;

let route_content model controls ~route ~dispatch =
  let screen =
    Screen.create
      model
      ~route
      ~search:controls.search
      ~selected_todo_id:controls.selected_todo_id
  in
  Apple.vstack
    ~spacing:8.
    (List.concat
       [ [ Apple.vstack
             ~spacing:4.
             [ Apple.text ~style:Title2 ~weight:Semibold screen.title
             ; Apple.text
                 ~color:Secondary
                 [%string
                   "%{screen.active_count#Int} active, %{screen.completed_count#Int} completed"]
             ]
         ; add_bar model ~dispatch
         ]
       ; (match model.error with
          | None -> []
          | Some error -> [ Apple.text ~color:Secondary error ])
       ; [ content_list
             model
             ~route
             ~search:controls.search
             ~set_selected_todo_id:controls.set_selected_todo_id
             ~dispatch
         ]
       ])
  |> Apple.padding
;;

let mobile_screen_padding node =
  Apple.padding
    ~insets:{ Apple.top = 28.; leading = 24.; bottom = 112.; trailing = 24. }
    node
;;

let mobile_scroll_screen node = Apple.scroll_view (mobile_screen_padding node)

let mobile_task_screen model controls ~route ~dispatch =
  let on_edit todo =
    Bonsai.Effect.Many
      [ dispatch (Todos.Action.Set_draft todo.Todos.Todo.title)
      ; controls.set_editing_todo_id todo.id
      ]
  in
  content_list
    model
    ~route
    ~search:controls.search
    ~set_selected_todo_id:controls.set_selected_todo_id
    ~on_edit
    ~dispatch
  |> mobile_scroll_screen
;;

let mobile_dashboard model controls ~dispatch =
  let on_edit todo =
    Bonsai.Effect.Many
      [ dispatch (Todos.Action.Set_draft todo.Todos.Todo.title)
      ; controls.set_editing_todo_id todo.id
      ]
  in
  Apple.vstack
    ~spacing:32.
    [ Apple.vstack
        ~spacing:4.
        [ Apple.text ~style:Title2 ~weight:Semibold "Good morning"
        ; Apple.text ~color:Secondary "Let's get things done."
        ]
    ; content_list
        model
        ~route:Route.All
        ~search:controls.search
        ~set_selected_todo_id:controls.set_selected_todo_id
        ~on_edit
        ~dispatch
    ]
  |> mobile_scroll_screen
;;

let new_task_sheet model controls ~dispatch =
  Apple.vstack
    ~spacing:12.
    [ Apple.text ~style:Title3 ~weight:Semibold "New Task"
    ; Apple.text_field
        ~text:model.Todos.Model.draft
        ~placeholder:"Task title"
        ~on_change:(fun draft -> dispatch (Todos.Action.Set_draft draft))
        ()
    ; Apple.hstack
        ~spacing:12.
        [ Apple.button
            "Cancel"
            ~on_click:(controls.set_mobile_new_task_presented false)
        ; Apple.button
            "Save"
            ~on_click:
              (Bonsai.Effect.Many
                 [ dispatch (Todos.Action.Submit_new (next_todo model))
                 ; controls.set_mobile_new_task_presented false
                 ])
        ]
    ]
    |> Apple.padding
;;

let editing_todo model controls =
  List.find model.Todos.Model.todos ~f:(fun (todo : Todos.Todo.t) ->
    String.equal todo.id controls.editing_todo_id)
;;

let edit_task_sheet model controls ~dispatch todo =
  Apple.vstack
    ~spacing:12.
    [ Apple.text ~style:Title3 ~weight:Semibold "Edit Task"
    ; Apple.text_field
        ~text:model.Todos.Model.draft
        ~placeholder:"Task title"
        ~on_change:(fun draft -> dispatch (Todos.Action.Set_draft draft))
        ()
    ; Apple.hstack
        ~spacing:12.
        [ Apple.button "Cancel" ~on_click:(controls.set_editing_todo_id "")
        ; Apple.button
            "Save"
            ~on_click:
              (Bonsai.Effect.Many
                 [ dispatch (Todos.Action.Update_title { id = todo.Todos.Todo.id })
                 ; controls.set_editing_todo_id ""
                 ])
        ]
    ]
    |> Apple.padding
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
    ~content:(route_content model controls ~route:controls.route ~dispatch)
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

let mobile_view ?(controls = default_controls) ({ model; dispatch } : Todos.Controller.t) =
  let select_mobile_tab tab_id =
    match tab_id with
    | tab_id when String.equal tab_id add_tab ->
      controls.set_mobile_new_task_presented true
    | tab_id ->
      let route =
        if String.equal tab_id upcoming_tab then Route.Active else Route.All
      in
      Bonsai.Effect.Many [ controls.set_mobile_tab tab_id; controls.set_route route ]
  in
  let tabs =
    Apple.tab_view
      ~selected:controls.mobile_tab
      ~on_select:select_mobile_tab
      [ Apple.tab
          ~id:today_tab
          ~title:"Today"
          ~system_image:"sun.max"
          (mobile_dashboard model controls ~dispatch)
      ; Apple.tab
          ~id:upcoming_tab
          ~title:"Upcoming"
          ~system_image:"calendar"
          (mobile_task_screen model controls ~route:Route.Active ~dispatch)
      ; Apple.tab ~id:add_tab ~title:"Add" ~system_image:"plus" (Apple.vstack [])
      ; Apple.tab
          ~id:search_tab
          ~title:"Search"
          ~system_image:"magnifyingglass"
          ~role:Apple.Search
          (mobile_task_screen model controls ~route:Route.All ~dispatch
           |> Apple.searchable ~text:controls.search ~on_change:controls.set_search)
      ]
  in
  tabs
  |> Apple.sheet
       ~is_presented:controls.mobile_new_task_presented
       ~content:(new_task_sheet model controls ~dispatch)
       ~on_dismiss:(controls.set_mobile_new_task_presented false)
  |> Apple.sheet
       ~is_presented:(Option.is_some (editing_todo model controls))
       ~content:
         (match editing_todo model controls with
          | None -> Apple.vstack []
          | Some todo -> edit_task_sheet model controls ~dispatch todo)
       ~on_dismiss:(controls.set_editing_todo_id "")
;;

let adaptive_view ?(controls = default_controls) controller =
  Apple.adaptive_layout
    ~compact:(mobile_view controller ~controls)
    ~regular:(view controller ~controls)
;;

let component_with_view ?(run_command = Todos.Controller.ignore_command) render graph =
  let open Bonsai.Let_syntax in
  let controller = Todos.Controller.component ~run_command graph in
  let route, set_route = Bonsai.state Route.All graph in
  let search, set_search = Bonsai.state "" graph in
  let selected_todo_id, set_selected_todo_id = Bonsai.state "" graph in
  let mobile_tab, set_mobile_tab = Bonsai.state today_tab graph in
  let mobile_new_task_presented, set_mobile_new_task_presented =
    Bonsai.state false graph
  in
  let editing_todo_id, set_editing_todo_id = Bonsai.state "" graph in
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
  and set_selected_todo_id
  and mobile_tab
  and set_mobile_tab
  and mobile_new_task_presented
  and set_mobile_new_task_presented
  and editing_todo_id
  and set_editing_todo_id in
  render
    controller
    ~controls:
      { route
      ; search
      ; selected_todo_id
      ; mobile_tab
      ; mobile_new_task_presented
      ; editing_todo_id
      ; set_route
      ; set_search
      ; set_selected_todo_id
      ; set_mobile_tab
      ; set_mobile_new_task_presented
      ; set_editing_todo_id
      }
;;

let component ?run_command graph =
  component_with_view ?run_command (fun controller ~controls -> view controller ~controls) graph
;;

let adaptive_component ?run_command graph =
  component_with_view
    ?run_command
    (fun controller ~controls -> adaptive_view controller ~controls)
    graph
;;
