(lang dune 3.17)

(name todos_ocaml)

(package
 (name todos_ocaml)
 (synopsis "Liquid-style iOS todo app built with DataScript OCaml and Bonsai Native")
 (description
  "A native iOS todo app whose domain state is stored in datascript-ocaml and rendered with bonsai-native.")
 (depends
  (ocaml (and (>= 5.2.1) (< 5.3.0)))
  (dune (>= 3.17))
  datascript_ocaml
  (bonsai (= v0.18~preview.130.100+614))
  (core (= v0.18~preview.130.100+614))
  (ppx_jane (= v0.18~preview.130.100+614))
  bonsai_native
  bonsai_apple))
