- make an id type and allow :symbols to be ruby symbols
- add `send` special form
- add nice lisp backtraces
  Make them work with lisp functions that call ruby methods
- fix arg counts functions defined in ruby that take an implicit env

```
lisp.rb> (def asdf 1 2)
ArgumentError: wrong number of arguments (4 for 3) # should read (3 for 2)
```
