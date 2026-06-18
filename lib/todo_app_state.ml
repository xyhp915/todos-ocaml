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

type t =
  { store : Todo_store.t
  ; search_query : string
  }

let create ?(store = Todo_store.demo ()) ?(search_query = "") () =
  { store; search_query }
;;

let initial = create ()

let apply_form store form =
  Todo_store.add store ~title:form.title ~date:form.date ~time:form.time
;;

let rename_from_form store ~id form =
  Todo_store.rename store ~id ~title:form.title ~date:form.date ~time:form.time
;;

let apply t = function
  | Toggle id -> { t with store = Todo_store.toggle t.store ~id }
  | Delete id -> { t with store = Todo_store.delete t.store ~id }
  | Save_new form -> { t with store = apply_form t.store form }
  | Save_existing (id, form) -> { t with store = rename_from_form t.store ~id form }
  | Search_changed search_query -> { t with search_query }
;;

let store t = t.store
let todos t = Todo_store.all t.store
let search_query t = t.search_query
