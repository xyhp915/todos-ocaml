(lang dune 3.17)
(using melange 0.1)

(name todos_ocaml)

(pin
 (url "git+https://github.com/logseq/datascript-ocaml.git#b4c201f573ed6fd51a85aa190a064c489ee2a5b6")
 (package (name datascript_ocaml)))

(pin
 (url "git+https://github.com/logseq/persistent-sorted-set-ocaml.git#074401d81ca22b9d44c725d7f171a67d69765a31")
 (package (name persistent_sorted_set_ocaml)))

(pin
 (url "git+https://github.com/RCmerci/melange-edn.git#bdc79c1d1d6edc9b0874113759bee29ce45f53f5")
 (package (name melange-edn)))

(pin
 (url "git+https://github.com/RCmerci/melange-transit.git#f8388857a1e2c8d53b00dc968ad7bb333be882c3")
 (package (name melange-transit)))

(pin
 (url "git+https://github.com/logseq/bonsai-native.git#2e60dc9264ceb6c6624f3c11d004515925bb25d7")
 (package (name bonsai_native)))

(pin
 (url "git+https://github.com/logseq/bonsai-native.git#2e60dc9264ceb6c6624f3c11d004515925bb25d7")
 (package (name bonsai_apple)))

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
