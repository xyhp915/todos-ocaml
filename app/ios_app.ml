open! Core
open UIKit
open Runtime

module App_state = Todos.Todo_app_state
module Presentation = Todos.Todo_presentation
module Store = Todos.Todo_store

type view_model =
  { state : App_state.t
  ; dispatch : App_state.action -> unit Bonsai.Effect.t
  }

let window = ref None
let root_controller = ref None
let table_views = ref []
let app_driver : view_model Bonsai_driver.t option ref = ref None
let current_state = ref App_state.initial

let table_tag = 1001

let app_component graph =
  let open Bonsai.Let_syntax in
  let state, dispatch =
    Bonsai.state_machine
      ~default_model:App_state.initial
      ~apply_action:(fun _context model action -> App_state.apply model action)
      graph
  in
  let%arr state and dispatch in
  { state; dispatch }
;;

type tab_spec =
  { title : string
  ; icon : string
  ; identifier : string
  }

let today_tab_spec = { title = "Today"; icon = "sun.max"; identifier = "today" }
let upcoming_tab_spec = { title = "Upcoming"; icon = "calendar"; identifier = "upcoming" }
let add_tab_spec = { title = "Add"; icon = "plus"; identifier = "add" }

let make_tab spec controller =
  Native_ui.Tab.item
    ~title:spec.title
    ~icon:spec.icon
    ~identifier:spec.identifier
    controller
;;

let sections_for ~mode ~query () =
  Presentation.sections_for ~mode ~query (App_state.todos !current_state)
;;

let reload_table () = List.iter !table_views ~f:Native_ui.Todo_list.reload

let reload_table_animated () =
  match !table_views with
  | [] -> ()
  | tables -> List.iter tables ~f:Native_ui.Todo_list.reload_animated
;;

let flush_bonsai ?(reload = false) ?(animated = false) () =
  match !app_driver with
  | None -> ()
  | Some driver ->
    Bonsai_driver.flush driver;
    let view_model = Bonsai_driver.result driver in
    current_state := view_model.state;
    Bonsai_driver.trigger_lifecycles driver;
    if reload
    then if animated then reload_table_animated () else reload_table ()
;;

let dispatch ?(animated = false) action =
  match !app_driver with
  | None -> ()
  | Some driver ->
    Bonsai_driver.flush driver;
    let view_model = Bonsai_driver.result driver in
    Bonsai_driver.schedule_event driver (view_model.dispatch action);
    flush_bonsai ~reload:true ~animated ()
;;

let form_value values key = Map.find values key |> Option.value ~default:""

let save_task ?todo values =
  let form =
    { App_state.title = form_value values "title"
    ; date = form_value values "date"
    ; time = form_value values "time"
    }
  in
  match todo with
  | None -> dispatch (App_state.Save_new form)
  | Some todo -> dispatch (App_state.Save_existing (todo.Store.id, form))
;;

let present_editor ?todo () =
  match !root_controller with
  | None -> ()
  | Some controller ->
    let title, primary_action, initial_title, initial_date, initial_time =
      match todo with
      | None -> "New Task", "Add", "", "Today", ""
      | Some todo -> "Edit Task", "Save", todo.Store.title, todo.Store.date, todo.Store.time
    in
    Native_ui.Form.present
      controller
      ~title
      ~primary_action
      ~fields:
        [ Native_ui.Form.text
            ~key:"title"
            ~placeholder:"Task title"
            ~value:initial_title
        ; Native_ui.Form.date_picker
            ~key:"date"
            ~placeholder:"Date"
            ~value:initial_date
            ~mode:_UIDatePickerModeDate
            ~format:"MMM d"
        ; Native_ui.Form.date_picker
            ~key:"time"
            ~placeholder:"Time"
            ~value:initial_time
            ~mode:_UIDatePickerModeTime
            ~format:"h:mm a"
        ]
      ~on_submit:(save_task ?todo)
;;

let install_tab_delegate tab_controller =
  Native_ui.Tab.intercept
    tab_controller
    ~should_intercept:(fun tab -> String.equal (Native_ui.Tab.identifier tab) "add")
    ~on_intercept:present_editor
;;

let todo_row todo =
  { Native_ui.Todo_list.id = todo.Store.id
  ; title = todo.Store.title
  ; secondary = Presentation.todo_metadata todo
  ; completed = todo.Store.completed
  ; on_toggle = (fun () -> dispatch ~animated:true (App_state.Toggle todo.Store.id))
  ; on_edit = (fun () -> present_editor ~todo ())
  ; on_delete = (fun () -> dispatch (App_state.Delete todo.Store.id))
  }
;;

let todo_sections ~mode ~query =
  sections_for ~mode ~query ()
  |> List.map ~f:(fun (section : Presentation.section) ->
    let title =
      Presentation.header_title
        ~mode
        ~section_title:section.title
        ~todo_count:(List.length section.todos)
      |> fun title -> Option.some_if (not (String.is_empty title)) title
    in
    { Native_ui.Todo_list.title; rows = List.map section.todos ~f:todo_row })
;;

let install_search_controller controller =
  Native_ui.Search.install
    controller
    ~placeholder:"Search"
    ~on_change:(fun query -> dispatch (App_state.Search_changed query))
    ~on_cancel:(fun () -> dispatch (App_state.Search_changed ""))
;;

let layout_table_view self =
  Native_ui.View.fill_tagged_subview self ~tag:table_tag
;;

let install_table_view ~mode ~query ?(show_header = false) self =
  if not (Native_ui.View.has_tag self ~tag:table_tag)
  then (
    let header =
      Option.some_if
        show_header
        { Native_ui.Todo_list.title = "Good morning"
        ; subtitle = "Let's get things done."
        }
    in
    let table =
      Native_ui.Todo_list.install
        self
        ~tag:table_tag
        ~header
        ~sections:(fun () -> todo_sections ~mode ~query:(query ()))
    in
    table_views := table :: !table_views;
    layout_table_view self);
  self
;;

type table_screen =
  { class_name : string
  ; mode : Presentation.mode
  ; query : unit -> string
  ; show_header : bool
  }

let dashboard_screen =
  { class_name = "TodosDashboardView"
  ; mode = Presentation.Dashboard
  ; query = (fun () -> "")
  ; show_header = true
  }

let upcoming_screen =
  { class_name = "TodosUpcomingView"
  ; mode = Presentation.Upcoming
  ; query = (fun () -> "")
  ; show_header = false
  }

let search_screen =
  { class_name = "TodosSearchView"
  ; mode = Presentation.Search
  ; query = (fun () -> App_state.search_query !current_state)
  ; show_header = false
  }

let register_table_screen screen =
  Native_ui.View.register
    ~class_name:screen.class_name
    ~did_move_to_superview:(fun self ->
      ignore
        (install_table_view
           ~mode:screen.mode
           ~query:screen.query
           ~show_header:screen.show_header
           self))
    ~layout_subviews:layout_table_view
;;

let register_views () =
  [ dashboard_screen; upcoming_screen; search_screen ]
  |> List.iter ~f:register_table_screen
;;

let make_table_controller ~tab ~class_name ~screen_bounds =
  Native_ui.Controller.view_class_screen
    ~title:tab.title
    ~icon:tab.icon
    ~class_name
    ~frame:screen_bounds
;;

let install_root_view ~time_source app_delegate _application _launch_options =
  register_views ();
  let screen_bounds = UIScreen.self |> UIScreenClass.mainScreen |> UIScreen.bounds in
  let background_color = UIColor.self |> UIColorClass.systemGroupedBackgroundColor in
  let win = UIWindow.self |> alloc |> UIWindow.initWithFrame screen_bounds in
  UIView.setBackgroundColor background_color win;
  table_views := [];
  let instrumentation = Bonsai_driver.Instrumentation.default_for_test_handles () in
  let driver = Bonsai_driver.create ~instrumentation ~time_source app_component in
  app_driver := Some driver;
  flush_bonsai ();
  let tab_controller = UITabBarController.self |> alloc |> init in
  (let today_controller, _today_navigation =
     make_table_controller
       ~tab:today_tab_spec
       ~class_name:dashboard_screen.class_name
       ~screen_bounds
   in
     let upcoming_controller, _upcoming_navigation =
       make_table_controller
         ~tab:upcoming_tab_spec
         ~class_name:upcoming_screen.class_name
         ~screen_bounds
     in
     let search_controller, search_navigation =
       make_table_controller
         ~tab:{ title = "Search"; icon = "magnifyingglass"; identifier = "search" }
         ~class_name:search_screen.class_name
         ~screen_bounds
     in
     install_search_controller search_controller;
     let today_tab = make_tab today_tab_spec today_controller in
     let upcoming_tab = make_tab upcoming_tab_spec upcoming_controller in
     let add_controller = UIViewController.self |> alloc |> init in
     let add_tab = make_tab add_tab_spec add_controller in
     let search_tab = Native_ui.Tab.search search_navigation in
     Native_ui.Tab.set_items tab_controller [ today_tab; upcoming_tab; add_tab; search_tab ];
     Native_ui.Tab.set_selected tab_controller today_tab;
     root_controller := Some tab_controller;
     install_tab_delegate tab_controller;
     UIWindow.setRootViewController tab_controller win);
  UIWindow.makeKeyAndVisible win;
  window := Some win;
  ignore app_delegate;
  true
;;

let main ~time_source =
  Native_ui.Application.run
    ~delegate_class:"TodosAppDelegate"
    ~did_finish_launching:(install_root_view ~time_source)
;;

let () = main ~time_source:(Bonsai.Time_source.create ~start:Time_ns.epoch)
