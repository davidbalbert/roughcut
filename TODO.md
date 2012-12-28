- add range literals
  Use this for `rest`
- Can quasiquote be written in lisp?
- add nice lisp backtraces
- make quote and quasiquote print better
  Make them work with lisp functions that call ruby methods
- fix arg counts functions defined in ruby that take an implicit env

```
lisp.rb> (def asdf 1 2)
ArgumentError: wrong number of arguments (4 for 3) # should read (3 for 2)
```
