type task_form =
  { title : string
  ; date : string
  ; time : string
  }

type action =
  | Toggle of int
  | Delete of int
  | Save_new of task_form
  | Save_existing of int * task_form
  | Search_changed of string

type t

val initial : t
val create : ?store:Todo_store.t -> ?search_query:string -> unit -> t
val apply : t -> action -> t
val store : t -> Todo_store.t
val todos : t -> Todo_store.todo list
val search_query : t -> string
