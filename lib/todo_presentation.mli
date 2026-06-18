type mode =
  | Dashboard
  | Upcoming
  | Search

type section =
  { title : string
  ; todos : Todo_store.todo list
  }

val sections_for : mode:mode -> query:string -> Todo_store.todo list -> section list
val header_title : mode:mode -> section_title:string -> todo_count:int -> string
val todo_metadata : Todo_store.todo -> string
