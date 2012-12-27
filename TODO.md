- Have anonymous functions stopped working? I have to fix that
  ((fn (a) (+ 1 a)) 5)
  NoMethodError: undefined method 'to_sym' for (fn (a) (* 2 a)):Lisp::Sexp
- add range literals
  Use this for `rest`
- Look into macroexpand-1 inside a let. Will this work?
  (let (foo (macro ...)) (macroexpand-1) foo)
- Can quasiquote be written in lisp?
- add nice lisp backtraces
  Make them work with lisp functions that call ruby methods
- fix arg counts functions defined in ruby that take an implicit env

```
lisp.rb> (def asdf 1 2)
ArgumentError: wrong number of arguments (4 for 3) # should read (3 for 2)
```
