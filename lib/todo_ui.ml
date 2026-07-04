open! Todo_std
module Apple = Bonsai_apple
module Todos = Todo_core
module Screen = Todos.Screen
module Route = Screen.Route

type controls = {
  route : Route.t;
  search : string;
  selected_todo_id : string;
  mobile_tab : string;
  mobile_new_task_presented : bool;
  editing_todo_id : string;
  visible_todo_limit : int;
  set_route : Route.t -> unit Apple.Action.t;
  set_search : string -> unit Apple.Action.t;
  set_selected_todo_id : string -> unit Apple.Action.t;
  set_mobile_tab : string -> unit Apple.Action.t;
  set_mobile_new_task_presented : bool -> unit Apple.Action.t;
  set_editing_todo_id : string -> unit Apple.Action.t;
  set_visible_todo_limit : int -> unit Apple.Action.t;
}

let today_tab = "today"
let upcoming_tab = "upcoming"
let add_tab = "add"
let search_tab = "search"
let initial_visible_todo_limit = 80
let visible_todo_limit_step = 80
let max_visible_todo_limit = 240

let default_controls =
  {
    route = Route.All;
    search = "";
    selected_todo_id = "";
    mobile_tab = today_tab;
    mobile_new_task_presented = false;
    editing_todo_id = "";
    visible_todo_limit = initial_visible_todo_limit;
    set_route = (fun _ -> Apple.Action.ignore);
    set_search = (fun _ -> Apple.Action.ignore);
    set_selected_todo_id = (fun _ -> Apple.Action.ignore);
    set_mobile_tab = (fun _ -> Apple.Action.ignore);
    set_mobile_new_task_presented = (fun _ -> Apple.Action.ignore);
    set_editing_todo_id = (fun _ -> Apple.Action.ignore);
    set_visible_todo_limit = (fun _ -> Apple.Action.ignore);
  }

let next_todo = Screen.next_todo

type controller = unit Apple.Action.t Todos.Controller.t

type run_command =
  dispatch:(Todos.Action.t -> unit Apple.Action.t) ->
  Todos.Command.t ->
  unit Apple.Action.t

let ignore_command : run_command = fun ~dispatch:_ _command -> Apple.Action.ignore

let controller_component ?(run_command : run_command = ignore_command) graph =
  let model, set_model = Apple.state graph ~key:"model" Todos.Model.initial in
  let rec dispatch action () =
    let next_model, commands = Todos.Model.update model action in
    set_model next_model ();
    List.iter commands ~f:(fun command -> run_command ~dispatch command ())
  in
  ({ model; dispatch } : controller)

type visible_todo_item =
  | Todo_item of Todos.Todo.t
  | Load_more_item of { next_offset : int }

let take values ~count =
  let rec loop remaining values acc =
    match (remaining, values) with
    | 0, _ | _, [] -> List.rev acc
    | remaining, value :: values -> loop (remaining - 1) values (value :: acc)
  in
  if count <= 0 then [] else loop count values []

let empty_state title =
  Apple.vstack ~spacing:8.
    [
      Apple.text ~style:Title3 ~weight:Semibold title;
      Apple.text ~color:Secondary "Nothing here right now.";
    ]
  |> Apple.padding

let add_bar model ~dispatch =
  let field =
    Apple.text_field ~text:model.Todos.Model.draft ~placeholder:"New task"
      ~on_change:(fun draft -> dispatch (Todos.Action.Set_draft draft))
      ()
  in
  Apple.hstack ~spacing:8.
    [
      field;
      Apple.button "Add"
        ~on_click:(dispatch (Todos.Action.Submit_new (next_todo model)));
    ]

let todo_row ~dispatch ?on_select ?on_edit (todo : Todos.Todo.t) =
  let leading_button : Apple.row_leading_button =
    {
      system_image = "circle";
      selected_system_image = Some "checkmark.circle.fill";
      selected = todo.completed;
      accessibility_label =
        (if todo.completed then "Mark incomplete" else "Mark complete");
      on_click = dispatch (Todos.Action.Toggle todo.id);
    }
  in
  let delete_action : Apple.row_action =
    {
      title = "Delete";
      system_image = Some "trash";
      style = Destructive;
      on_click = dispatch (Todos.Action.Delete todo.id);
    }
  in
  let edit_actions =
    match on_edit with
    | None -> []
    | Some on_edit ->
        [
          ({
             title = "Edit";
             system_image = Some "pencil";
             style = Default;
             on_click = on_edit todo;
           }
            : Apple.row_action);
        ]
  in
  Apple.list_row
    {
      title = todo.title;
      subtitle = Some (Printf.sprintf "Created %d" todo.created_at_ms);
      trailing_text = (if todo.completed then Some "Done" else None);
      leading_system_image = None;
      preview_image_path = None;
      content_style = Standard;
      accessory = No_accessory;
      title_strikethrough = todo.completed;
      on_click = Option.map on_select ~f:(fun on_select -> on_select todo.id);
      leading_button = Some leading_button;
      swipe_actions = edit_actions @ [ delete_action ];
      menu_actions = [];
    }

let route_row ~selected ~on_select route =
  let title = Route.title route in
  Apple.list_row
    {
      title;
      subtitle = None;
      trailing_text =
        (if Route.equal route selected then Some "Selected" else None);
      leading_system_image = None;
      preview_image_path = None;
      content_style = Standard;
      accessory = No_accessory;
      title_strikethrough = false;
      on_click = Some (on_select route);
      leading_button = None;
      swipe_actions = [];
      menu_actions = [];
    }

let sidebar ~route ~set_route =
  Apple.list
    [ Route.All; Active; Completed ]
    ~key:Route.id
    ~row:(route_row ~selected:route ~on_select:set_route)

let visible_todo_item_key = function
  | Todo_item todo -> todo.Todos.Todo.id
  | Load_more_item { next_offset } -> Printf.sprintf "load-more-%d" next_offset

let load_page ~limit ~offset ~search =
  Todos.Action.Load_page { limit; offset; search }

let change_search controls ~dispatch search =
  Apple.Action.many
    [
      controls.set_search search;
      controls.set_visible_todo_limit initial_visible_todo_limit;
      dispatch (load_page ~limit:initial_visible_todo_limit ~offset:0 ~search);
    ]

let load_more_row controls ~next_offset ~dispatch =
  Apple.text ~color:Secondary "Loading more..."
  |> Apple.on_appear
       ~on_appear:
         (Apple.Action.many
            [
              controls.set_visible_todo_limit
                (min max_visible_todo_limit
                   (controls.visible_todo_limit + visible_todo_limit_step));
              dispatch
                (load_page ~limit:visible_todo_limit_step ~offset:next_offset
                   ~search:controls.search);
            ])

let content_list ?on_edit model controls ~route ~search ~set_selected_todo_id
    ~dispatch =
  let all_todos = Screen.visible_todos ~route ~search model.Todos.Model.todos in
  let todos = take all_todos ~count:controls.visible_todo_limit in
  match todos with
  | [] -> empty_state "No matching tasks"
  | todos ->
      let total_count = List.length all_todos in
      let has_more =
        model.Todos.Model.has_more || total_count > controls.visible_todo_limit
      in
      let next_offset =
        if model.Todos.Model.loaded_count > 0 then model.loaded_count
        else controls.visible_todo_limit
      in
      let rows =
        List.map todos ~f:(fun todo -> Todo_item todo)
        @ if has_more then [ Load_more_item { next_offset } ] else []
      in
      Apple.vstack ~spacing:8.
        [
          Apple.list rows ~key:visible_todo_item_key ~row:(function
            | Todo_item todo ->
                todo_row ~dispatch ~on_select:set_selected_todo_id ?on_edit todo
            | Load_more_item { next_offset } ->
                load_more_row controls ~next_offset ~dispatch);
        ]

let route_content model controls ~route ~dispatch =
  let screen =
    Screen.create model ~route ~search:controls.search
      ~selected_todo_id:controls.selected_todo_id
  in
  Apple.vstack ~spacing:8.
    (List.concat
       [
         [
           Apple.vstack ~spacing:4.
             [
               Apple.text ~style:Title2 ~weight:Semibold screen.title;
               Apple.text ~color:Secondary
                 (Printf.sprintf "%d active, %d completed" screen.active_count
                    screen.completed_count);
             ];
           add_bar model ~dispatch;
         ];
         (match model.error with
         | None -> []
         | Some error -> [ Apple.text ~color:Secondary error ]);
         [
           content_list model controls ~route ~search:controls.search
             ~set_selected_todo_id:controls.set_selected_todo_id ~dispatch;
         ];
       ])
  |> Apple.padding

let mobile_header node =
  Apple.padding
    ~insets:{ Apple.top = 28.; leading = 24.; bottom = 20.; trailing = 24. }
    node

let mobile_empty_screen node =
  Apple.padding
    ~insets:{ Apple.top = 28.; leading = 24.; bottom = 112.; trailing = 24. }
    node

let mobile_task_screen model controls ~route ~dispatch =
  let on_edit todo =
    Apple.Action.many
      [
        dispatch (Todos.Action.Set_draft todo.Todos.Todo.title);
        controls.set_editing_todo_id todo.id;
      ]
  in
  match
    Screen.visible_todos ~route ~search:controls.search model.Todos.Model.todos
  with
  | [] -> empty_state "No matching tasks" |> mobile_empty_screen
  | _ ->
      content_list model controls ~route ~search:controls.search
        ~set_selected_todo_id:controls.set_selected_todo_id ~on_edit ~dispatch

let mobile_dashboard model controls ~dispatch =
  let on_edit todo =
    Apple.Action.many
      [
        dispatch (Todos.Action.Set_draft todo.Todos.Todo.title);
        controls.set_editing_todo_id todo.id;
      ]
  in
  let header =
    Apple.vstack ~spacing:4.
      [
        Apple.text ~style:Title2 ~weight:Semibold "Good morning 🌈";
        Apple.text ~color:Secondary "Let's get things done.";
      ]
    |> mobile_header
  in
  match
    Screen.visible_todos ~route:Route.All ~search:controls.search
      model.Todos.Model.todos
  with
  | [] ->
      Apple.vstack ~spacing:12.
        [ header; empty_state "No matching tasks" |> mobile_empty_screen ]
  | _ ->
      Apple.vstack ~spacing:0.
        [
          header;
          content_list model controls ~route:Route.All ~search:controls.search
            ~set_selected_todo_id:controls.set_selected_todo_id ~on_edit
            ~dispatch;
        ]

let new_task_sheet model controls ~dispatch =
  Apple.vstack ~spacing:12.
    [
      Apple.text ~style:Title3 ~weight:Semibold "New Task";
      Apple.text_field ~text:model.Todos.Model.draft ~placeholder:"Task title"
        ~on_change:(fun draft -> dispatch (Todos.Action.Set_draft draft))
        ();
      Apple.hstack ~spacing:12.
        [
          Apple.button "Cancel"
            ~on_click:(controls.set_mobile_new_task_presented false);
          Apple.button "Save"
            ~on_click:
              (Apple.Action.many
                 [
                   dispatch (Todos.Action.Submit_new (next_todo model));
                   controls.set_mobile_new_task_presented false;
                 ]);
        ];
    ]
  |> Apple.padding

let editing_todo model controls =
  List.find model.Todos.Model.todos ~f:(fun (todo : Todos.Todo.t) ->
      String.equal todo.id controls.editing_todo_id)

let edit_task_sheet model controls ~dispatch todo =
  Apple.vstack ~spacing:12.
    [
      Apple.text ~style:Title3 ~weight:Semibold "Edit Task";
      Apple.text_field ~text:model.Todos.Model.draft ~placeholder:"Task title"
        ~on_change:(fun draft -> dispatch (Todos.Action.Set_draft draft))
        ();
      Apple.hstack ~spacing:12.
        [
          Apple.button "Cancel" ~on_click:(controls.set_editing_todo_id "");
          Apple.button "Save"
            ~on_click:
              (Apple.Action.many
                 [
                   dispatch
                     (Todos.Action.Update_title { id = todo.Todos.Todo.id });
                   controls.set_editing_todo_id "";
                 ]);
        ];
    ]
  |> Apple.padding

let detail_view screen =
  match screen.Screen.selected_todo with
  | None ->
      Apple.vstack ~spacing:8.
        [
          Apple.text ~style:Title3 ~weight:Semibold "Select a task";
          Apple.text ~color:Secondary "Choose a task from the list.";
        ]
      |> Apple.padding
  | Some todo ->
      Apple.vstack ~spacing:12.
        [
          Apple.text ~style:Title2 ~weight:Semibold todo.title;
          Apple.text ~color:Secondary
            (if todo.completed then "Completed" else "Active");
          Apple.text ~color:Secondary
            (Printf.sprintf "Created %d" todo.created_at_ms);
        ]
      |> Apple.padding

let split_view model controls ~dispatch =
  let screen =
    Screen.create model ~route:controls.route ~search:controls.search
      ~selected_todo_id:controls.selected_todo_id
  in
  Apple.navigation_split
    ~sidebar:(sidebar ~route:controls.route ~set_route:controls.set_route)
    ~content:(route_content model controls ~route:controls.route ~dispatch)
    ~detail:(detail_view screen)
  |> Apple.searchable ~text:controls.search
       ~on_change:(change_search controls ~dispatch)
  |> Apple.toolbar
       [
         Apple.toolbar_item ~id:"add" ~title:"Add"
           ~on_click:(dispatch (Todos.Action.Submit_new (next_todo model)))
           ();
         Apple.toolbar_item ~id:"reload" ~title:"Reload"
           ~on_click:
             (dispatch
                (load_page ~limit:controls.visible_todo_limit ~offset:0
                   ~search:controls.search))
           ();
       ]

let view ?(controls = default_controls)
    ({ model; dispatch } : controller) =
  split_view model controls ~dispatch

let mobile_view ?(controls = default_controls)
    ({ model; dispatch } : controller) =
  let clear_search_on_exit =
    if
      String.equal controls.mobile_tab search_tab
      && not (String.is_empty controls.search)
    then
      [
        controls.set_search "";
        controls.set_visible_todo_limit initial_visible_todo_limit;
        dispatch
          (load_page ~limit:initial_visible_todo_limit ~offset:0 ~search:"");
      ]
    else []
  in
  let select_mobile_tab tab_id =
    match tab_id with
    | tab_id when String.equal tab_id add_tab ->
        Apple.Action.many
          (clear_search_on_exit
          @ [ controls.set_mobile_new_task_presented true ])
    | tab_id ->
        let route =
          if String.equal tab_id upcoming_tab then Route.Active else Route.All
        in
        Apple.Action.many
          (clear_search_on_exit
          @ [ controls.set_mobile_tab tab_id; controls.set_route route ])
  in
  let tabs =
    Apple.tab_view ~selected:controls.mobile_tab ~on_select:select_mobile_tab
      [
        Apple.tab ~id:today_tab ~title:"Today" ~system_image:"sun.max"
          (if String.equal controls.mobile_tab today_tab then
             mobile_dashboard model controls ~dispatch
           else Apple.vstack []);
        Apple.tab ~id:upcoming_tab ~title:"Upcoming" ~system_image:"calendar"
          (if String.equal controls.mobile_tab upcoming_tab then
             mobile_task_screen model controls ~route:Route.Active ~dispatch
           else Apple.vstack []);
        Apple.tab ~id:add_tab ~title:"Add" ~system_image:"plus"
          (Apple.vstack []);
        Apple.tab ~id:search_tab ~title:"Search" ~system_image:"magnifyingglass"
          ~role:Apple.Search
          (if String.equal controls.mobile_tab search_tab then
             mobile_task_screen model controls ~route:Route.All ~dispatch
             |> Apple.searchable ~text:controls.search
                  ~on_change:(change_search controls ~dispatch)
           else Apple.vstack []);
      ]
  in
  let editing_todo = editing_todo model controls in
  tabs
  |> Apple.sheet
       ~is_presented:
         (controls.mobile_new_task_presented || Option.is_some editing_todo)
       ~content:
         (match editing_todo with
         | Some todo -> edit_task_sheet model controls ~dispatch todo
         | None ->
             if controls.mobile_new_task_presented then
               new_task_sheet model controls ~dispatch
             else Apple.vstack [])
       ~on_dismiss:
         (Apple.Action.many
            [
              controls.set_mobile_new_task_presented false;
              controls.set_editing_todo_id "";
            ])

let adaptive_view ?(controls = default_controls) controller =
  Apple.adaptive_layout
    ~compact:(mobile_view controller ~controls)
    ~regular:(view controller ~controls)

let component_with_view ?(run_command : run_command = ignore_command) render graph =
  let controller = controller_component ~run_command graph in
  let route, set_route = Apple.state graph ~key:"route" Route.All in
  let search, set_search = Apple.state graph ~key:"search" "" in
  let selected_todo_id, set_selected_todo_id =
    Apple.state graph ~key:"selected-todo-id" ""
  in
  let mobile_tab, set_mobile_tab =
    Apple.state graph ~key:"mobile-tab" today_tab
  in
  let mobile_new_task_presented, set_mobile_new_task_presented =
    Apple.state graph ~key:"mobile-new-task-presented" false
  in
  let editing_todo_id, set_editing_todo_id =
    Apple.state graph ~key:"editing-todo-id" ""
  in
  let visible_todo_limit, set_visible_todo_limit =
    Apple.state graph ~key:"visible-todo-limit" initial_visible_todo_limit
  in
  let (_ : unit) =
    Bonsai_native.Graph.subscribe graph ~key:"todos-query-lifecycle" ~default:()
      (fun ~emit:_ ->
        controller.dispatch
          (load_page ~limit:visible_todo_limit ~offset:0 ~search)
          ();
        fun () -> ())
  in
  render controller
    ~controls:
      {
        route;
        search;
        selected_todo_id;
        mobile_tab;
        mobile_new_task_presented;
        editing_todo_id;
        visible_todo_limit;
        set_route;
        set_search;
        set_selected_todo_id;
        set_mobile_tab;
        set_mobile_new_task_presented;
        set_editing_todo_id;
        set_visible_todo_limit;
      }

let component ?run_command graph =
  component_with_view ?run_command
    (fun controller ~controls -> view controller ~controls)
    graph

let adaptive_component ?run_command graph =
  component_with_view ?run_command
    (fun controller ~controls -> adaptive_view controller ~controls)
    graph
