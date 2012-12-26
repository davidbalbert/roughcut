- define macroexpand-all
- define defmacro
- define defn
- add names to functions and macros
- implement let as a macro
- make an id type and allow :symbols to be ruby symbols
- add `send` special form
- fix arg counts functions defined in ruby that take an implicit env

    lisp.rb> (def asdf 1 2)
    ArgumentError: wrong number of arguments (4 for 3)

    # Should read (3 for 2)
