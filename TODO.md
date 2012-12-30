- add nice lisp backtraces
  Make them work with lisp functions that call ruby methods
- fix arg counts functions defined in ruby that take an implicit env
- ``~foo should return the id foo, not eval foo. Only ``~~foo should eval foo

```
lisp.rb> (def asdf 1 2)
ArgumentError: wrong number of arguments (4 for 3) # should read (3 for 2)
```
