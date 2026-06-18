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
  { app_state : Todo_app_state.t
  ; selected_tab : string
  ; editor : editor option
  }

type action =
  | App_action of Todo_app_state.action
  | Select_tab of string
  | Open_new_task
  | Open_editor of Todo_store.todo
  | Update_editor_title of string
  | Update_editor_date of string
  | Update_editor_time of string
  | Close_editor
  | Save_editor

val initial_model : model
val apply : model -> action -> model
val view : model -> dispatch:(action -> unit Bonsai.Effect.t) -> Bonsai_apple.node
val component : Bonsai.graph -> Bonsai_apple.node Bonsai.t
