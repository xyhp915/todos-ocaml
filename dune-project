(lang dune 3.17)
(using melange 0.1)

(name todos_ocaml)

(package
 (name todos_ocaml)
 (synopsis "Cross-platform todo app built with DataScript OCaml and Bonsai Native")
 (description
  "A cross-platform todo app whose shared OCaml state is stored in datascript-ocaml and rendered with Bonsai Native or Melange React.")
 (depends
  (ocaml (>= 5.4.1))
  (dune (>= 3.17))
  datascript_ocaml
  melange
  melange-transit
  bonsai_native
  bonsai_apple))
