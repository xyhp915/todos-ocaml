module Todos = Todo_core

type controls =
  { route : Todos.Screen.Route.t
  ; search : string
  ; selected_todo_id : string
  ; mobile_tab : string
  ; mobile_new_task_presented : bool
  ; editing_todo_id : string
  ; set_route : Todos.Screen.Route.t -> unit Bonsai.Effect.t
  ; set_search : string -> unit Bonsai.Effect.t
  ; set_selected_todo_id : string -> unit Bonsai.Effect.t
  ; set_mobile_tab : string -> unit Bonsai.Effect.t
  ; set_mobile_new_task_presented : bool -> unit Bonsai.Effect.t
  ; set_editing_todo_id : string -> unit Bonsai.Effect.t
  }

val default_controls : controls
val view : ?controls:controls -> Todos.Controller.t -> Bonsai_apple.node
val mobile_view : ?controls:controls -> Todos.Controller.t -> Bonsai_apple.node
val adaptive_view : ?controls:controls -> Todos.Controller.t -> Bonsai_apple.node
val component
  :  ?run_command:
       (dispatch:(Todos.Action.t -> unit Bonsai.Effect.t)
        -> Todos.Command.t
        -> unit Bonsai.Effect.t)
  -> Bonsai.graph
  -> Bonsai_apple.node Bonsai.t
val adaptive_component
  :  ?run_command:
       (dispatch:(Todos.Action.t -> unit Bonsai.Effect.t)
        -> Todos.Command.t
        -> unit Bonsai.Effect.t)
  -> Bonsai.graph
  -> Bonsai_apple.node Bonsai.t
