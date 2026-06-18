module Apple = Bonsai_apple
module App_state = Todo_app_state
module Presentation = Todo_presentation
module Store = Todo_store

type editor_mode =
  | New_task
  | Edit_task of int

type editor =
  { mode : editor_mode
  ; title : string
  ; date : string
  ; time : string
  }

type model =
  { app_state : App_state.t
  ; selected_tab : string
  ; editor : editor option
  }

type action =
  | App_action of App_state.action
  | Select_tab of string
  | Open_new_task
  | Open_editor of Store.todo
  | Update_editor_title of string
  | Update_editor_date of string
  | Update_editor_time of string
  | Close_editor
  | Save_editor

let today_tab = "today"
let upcoming_tab = "upcoming"
let add_tab = "add"
let search_tab = "search"

let initial_model =
  { app_state = App_state.initial; selected_tab = today_tab; editor = None }
;;

let new_editor = { mode = New_task; title = ""; date = "Today"; time = "" }

let editor_of_todo (todo : Store.todo) =
  { mode = Edit_task todo.id; title = todo.title; date = todo.date; time = todo.time }
;;

let update_editor t ~f =
  match t.editor with
  | None -> t
  | Some editor -> { t with editor = Some (f editor) }
;;

let save_editor t editor =
  let form : App_state.task_form =
    { title = editor.title; date = editor.date; time = editor.time }
  in
  let action =
    match editor.mode with
    | New_task -> App_state.Save_new form
    | Edit_task id -> App_state.Save_existing (id, form)
  in
  { t with app_state = App_state.apply t.app_state action; editor = None }
;;

let apply t = function
  | App_action action -> { t with app_state = App_state.apply t.app_state action }
  | Select_tab tab when String.equal tab add_tab -> { t with editor = Some new_editor }
  | Select_tab tab -> { t with selected_tab = tab }
  | Open_new_task -> { t with editor = Some new_editor }
  | Open_editor todo -> { t with editor = Some (editor_of_todo todo) }
  | Update_editor_title title ->
    update_editor t ~f:(fun editor -> { editor with title })
  | Update_editor_date date ->
    update_editor t ~f:(fun editor -> { editor with date })
  | Update_editor_time time ->
    update_editor t ~f:(fun editor -> { editor with time })
  | Close_editor -> { t with editor = None }
  | Save_editor ->
    (match t.editor with
     | None -> t
     | Some editor -> save_editor t editor)
;;

let effect dispatch action = dispatch action

let section_heading_insets =
  { Apple.top = 0.; leading = 12.; bottom = 0.; trailing = 0. }
;;

let header title =
  if String.equal title ""
  then []
  else
    [ Apple.text ~style:Apple.Headline ~weight:Apple.Semibold ~color:Apple.Secondary title
      |> Apple.padding ~insets:section_heading_insets
    ]
;;

let todo_row dispatch (todo : Store.todo) =
  let metadata = Presentation.todo_metadata todo |> String.trim in
  Apple.list_row
    { title = todo.title
    ; subtitle = None
    ; trailing_text = (if String.equal metadata "" then None else Some metadata)
    ; title_strikethrough = todo.completed
    ; leading_button =
        Some
          { system_image = "circle"
          ; selected_system_image = Some "checkmark.circle.fill"
          ; selected = todo.completed
          ; accessibility_label =
              (if todo.completed then "Mark incomplete" else "Mark complete")
          ; on_click = effect dispatch (App_action (App_state.Toggle todo.id))
          }
    ; swipe_actions =
        [ { title = "Edit"
          ; system_image = Some "pencil"
          ; style = Apple.Default
          ; on_click = effect dispatch (Open_editor todo)
          }
        ; { title = "Delete"
          ; system_image = Some "trash"
          ; style = Apple.Destructive
          ; on_click = effect dispatch (App_action (App_state.Delete todo.id))
          }
        ]
    }
;;

let section_view ~mode dispatch (section : Presentation.section) =
  let title =
    Presentation.header_title
      ~mode
      ~section_title:section.title
      ~todo_count:(List.length section.todos)
  in
  Apple.vstack
    ~spacing:8.
    (header title
     @ [ Apple.list
           section.todos
           ~key:(fun todo -> Int.to_string todo.Store.id)
           ~row:(todo_row dispatch)
       ])
;;

let task_sections ~mode ~query model =
  App_state.todos model.app_state
  |> Presentation.sections_for ~mode ~query
;;

let screen_padding node =
  Apple.padding
    ~insets:{ top = 28.; leading = 24.; bottom = 112.; trailing = 24. }
    node
;;

let scroll_screen node = Apple.scroll_view (screen_padding node)

let task_screen ~mode ~query model dispatch =
  let sections = task_sections ~mode ~query model in
  let content =
    Apple.vstack ~spacing:20. (List.map (section_view ~mode dispatch) sections)
  in
  scroll_screen content
;;

let dashboard model dispatch =
  let query = App_state.search_query model.app_state in
  let mode = if String.equal query "" then Presentation.Dashboard else Presentation.Search in
  let sections =
    task_sections ~mode ~query model
    |> List.map (section_view ~mode dispatch)
  in
  Apple.vstack
    ~spacing:32.
    [ Apple.vstack
        ~spacing:4.
        [ Apple.text ~style:Apple.Title2 ~weight:Apple.Semibold "Good morning"
        ; Apple.text ~style:Apple.Body ~color:Apple.Secondary "Let's get things done."
        ]
    ; Apple.vstack ~spacing:18. sections
    ]
  |> scroll_screen
;;

let search model dispatch =
  task_screen
    ~mode:Presentation.Search
    ~query:(App_state.search_query model.app_state)
    model
    dispatch
  |> Apple.searchable
       ~text:(App_state.search_query model.app_state)
       ~on_change:(fun query -> dispatch (App_action (App_state.Search_changed query)))
;;

let editor_title = function
  | New_task -> "New Task"
  | Edit_task _ -> "Edit Task"
;;

let editor_view dispatch editor =
  Apple.vstack
    ~spacing:12.
    [ Apple.text (editor_title editor.mode)
    ; Apple.text_field
        ~text:editor.title
        ~placeholder:"Task title"
        ~on_change:(fun title -> dispatch (Update_editor_title title))
        ()
    ; Apple.text_field
        ~text:editor.date
        ~placeholder:"Date"
        ~on_change:(fun date -> dispatch (Update_editor_date date))
        ()
    ; Apple.text_field
        ~text:editor.time
        ~placeholder:"Time"
        ~on_change:(fun time -> dispatch (Update_editor_time time))
        ()
    ; Apple.hstack
        ~spacing:12.
        [ Apple.button "Cancel" ~on_click:(dispatch Close_editor)
        ; Apple.button "Save" ~on_click:(dispatch Save_editor)
        ]
    ]
;;

let root model dispatch =
  let search_query = App_state.search_query model.app_state in
  Apple.tab_view
    ~selected:model.selected_tab
    ~on_select:(fun tab -> dispatch (Select_tab tab))
    [ Apple.tab
        ~id:today_tab
        ~title:"Today"
        ~system_image:"sun.max"
        (dashboard model dispatch)
    ; Apple.tab
        ~id:upcoming_tab
        ~title:"Upcoming"
        ~system_image:"calendar"
        (task_screen ~mode:Presentation.Upcoming ~query:search_query model dispatch)
    ; Apple.tab
        ~id:add_tab
        ~title:"Add"
        ~system_image:"plus"
        (Apple.text "")
    ; Apple.tab
        ~id:search_tab
        ~title:"Search"
        ~system_image:"magnifyingglass"
        ~role:Apple.Search
        (search model dispatch)
    ]
;;

let view model ~dispatch =
  match model.editor with
  | None -> root model dispatch
  | Some editor ->
    root model dispatch
    |> Apple.sheet
         ~is_presented:true
         ~content:(editor_view dispatch editor)
         ~on_dismiss:(dispatch Close_editor)
;;

let component graph =
  let open Bonsai.Let_syntax in
  let model, dispatch =
    Bonsai.state_machine
      ~default_model:initial_model
      ~apply_action:(fun _context model action -> apply model action)
      graph
  in
  let%arr model and dispatch in
  view model ~dispatch
;;
