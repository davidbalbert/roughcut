# Roughcut - A Short Pamphlet

Roughcut is a little Lisp with lots of imperfections, written in Ruby.

## Motivation

I'd never written a proper language before, so I decided to try. This is my first attempt. I also wanted to get a better understanding of macros, so Roughcut has those too.

## Design goals

Roughcut has three major design goals:

1. The environment should be transparent. I want it to be easy to see what makes Roughcut tick. There should not be a strong divide between the implementer and the user.
2. As much as possible, Roughcut should be written in Roughcut. This helps satisfy goal one, but it also satisfies my silly little obsession with self referential things.
3. Roughcut is just Ruby. Things that work in Ruby should work in Roughcut. You should be able to use Ruby literals and call Ruby code. Roughcut should also play nice with existing Ruby environments.

## Overview

Roughcut works like Common Lisp, is implemented like Scheme, and looks a bit like Clojure. From Common Lisp it takes the macro system. From Scheme it takes a very small set of fundamental forms and a single namespace for functions and variables. From Clojure, Roughcut takes names (`def`, `defn`, `defmacro`, `first`, `second`, `rest`) and ideas about interacting with an underlying language runtime.

### Examples

To start Roughcut, just run it with Ruby:

```
$ ruby roughcut.rb
roughcut>
```

You can use Roughcut like most other Lisps:

```lisp
roughcut> (+ 1 2 3 4 5)
=> 15
```

It has comments:

```lisp
roughcut> (+ 1 2) ; this doesn't really require any explanation
=> 3
```

variables:

```lisp
roughcut> (def greeting "Hello, world!")
=> "Hello, world!"
roughcut> greeting
=> "Hello, world!"
roughcut> (def number 42)
=> 42
roughcut> number
=> 42
```

lists:

```lisp
roughcut> (cons 1 (cons 2 (cons 3 ())))
=> (1 2 3)
roughcut> (list 4 5 6)
=> (4 5 6)
```

quoting:

```lisp
roughcut> (first '(4 5 6))
=> 4
roughcut> (rest '(4 5 6))
=> (5 6)
```

dotted pairs:

```lisp
roughcut> (cons 1 2)
=> (1 . 2)
roughcut> (first '(1 . 2))
=> 1
roughcut> (rest '(1 . 2))
=> 2
```

functions:

```lisp
roughcut> (defn inc (i) (+ i 1))
=> (defn inc (i) (+ i 1))
roughcut> (inc 3)
=> 4
```

anonymous functions:

```lisp
roughcut> ((fn (i) (- i 1)) 2)
=> 1
```

higher order functions:

```lisp
roughcut> (map (fn (i) (* i i)) '(1 2 3 4 5))
=> (1 4 9 16 25)
```

and closures:

```lisp
roughcut> (let (a 10) (defn get-a () a))
=> (defn get-a () a)
roughcut> (get-a)
=> 10
roughcut> a
NameError: a is undefined
```

It also supports loading source files with the `load` function:

```lisp
roughcut> (load "foobar.lisp")
=> true
```

## Transparency

As much as possible, the string representations of objects in Roughcut are eval-able. This is similar to Python's idea of `repr`.

Like most languages, numbers, strings, symbols, and other literals evaluate to themselves:

```lisp
roughcut> 100
=> 100
roughcut> 3.141
=> 3.141
roughcut> "Greetings, earthling"
=> "Greetings, earthling"
roughcut> :name
=> :name
```

Unlike most languages (but like Emacs Lisp), the string representations of functions and macros also can be eval'd. This is the case for both anonymous functions:

```lisp
roughcut> (fn (i) (* i 2))
=> (fn (i) (* i 2))
```

named functions:

```lisp
roughcut> even?
=> (defn even? (n) (= 0 (mod n 2)))
```

anonymous macros (this is an implementation of `when`):

```lisp
roughcut> (macro (condition & exprs) `(if ,condition (do ,@exprs)))
=> (macro (condition & exprs) `(if ,condition (do ,@exprs)))
```

and named macros:

```lisp
roughcut> defn
=> (defmacro defn (name args & expressions) `(def ,name (fn ,args ,@expressions)))
```

The ability to see the implementation of any function or macro helps blur the line between user and implementer. The system is not perfect though. Functions defined in Ruby are not yet transparent. This is something I hope to change in the future:

```lisp
roughcut> apply
=> #<Proc:0x007ffbabe6e4d0@roughcut.rb:163 (lambda)>
```

## Functions and Macros

Functions are first class objects created with `fn`. Named functions can be created with `defn`. Functions are called by evaluating a list with the function name in the first position:

```lisp
roughcut> (defn double (i) (* 2 i))
=> (defn double (i) (* 2 i))
roughcut> (double 5)
=> 10
```

### Quoting

If you want a list, rather than the result of a function evaluation, you can quote the list:

```lisp
roughcut> '(double 5)
=> (double 5)
```

If you need to interpolate values into a quoted list, you can use `quasiquote` (backtick) with `unquote` (comma) instead:

```lisp
roughcut> (def lucky-number 1337)
=> 1337
roughcut> `(double ,lucky-number)
=> (double 1337)
```

If you want to evaluate the contents of your list, treating `double` as a function once more, you can use the `eval` function:

```lisp
roughcut> (eval `(double ,lucky-number))
=> 2674
```

You can also splice arguments into a list using `unquote-splicing`. This is similar to the `*` operator in Ruby or Python:

```lisp
roughcut> `(1 2 ,@(list 3 4))
=> (1 2 3 4)
```

### Arity

Right now, Roughcut supports single-arity functions and variable-arity functions by using `&` in the argument list:

```lisp
roughcut> (defn f (first & rest) (puts first) (puts rest))
=> (defn f (first & rest) (puts first) (puts rest))
roughcut> (f 1)
1
()
=> nil
roughcut> (f 1 2)
1
(2)
=> nil
roughcut> (f 1 2 3)
1
(2 3)
=> nil
roughcut> (f)
ArgumentError: wrong number of arguments (0 for 1)
        in 'f'
```

Roughcut does not support argument destructuring or multi-arity functions, but I would very much like it to.

### Macros

Roughcut macros are functions that return Roughcut code. When a macro is called, its arguments are passed in unevaluated and it's return value is eval'd after the macro completes. Anonymous macros can be created with `macro` and named macros with `defmacro`.

Consider the `unless` macro, which is the opposite of `if`:

```lisp
roughcut> unless
=> (defmacro unless (condition & branches) `(if (not ,condition) ,@branches))
```

You can use it like this:

```lisp
roughcut> (unless false (puts "yay!") (puts "boo!"))
yay!
=> nil
```

Notice that only `(puts "yay!")` was evaluated, not `(puts "boo!")`.

If you want to see the code that `unless` generates, you can use `macroexpand`:

```lisp
roughcut> (macroexpand '(unless false (puts "yay!") (puts "boo!")))
=> (if (not false) (puts "yay!") (puts "boo!"))
```

Some macros are recursively defined. For instance `or` is defined in terms of itself:

```lisp
roughcut> or
=> (defmacro or (condition & args) (if (empty? args) `(if ,condition ,condition false) `(if ,condition ,condition (or ,@args))))
roughcut> (macroexpand '(or foo bar baz))
=> (if foo foo (or bar baz))
```

You can expand `or` fully using `macroexpand-all`:

```lisp
roughcut> (macroexpand-all '(or foo bar baz))
=> (if foo foo (if bar bar (if baz baz false)))
```

Roughcut macros are evaluated at runtime, not compile time. It would be better for performance if they were evaluated at compile time, but runtime macros were easier to write. This is the next feature I'd like to work on.

## Variables and scope

Roughcut has both global and local variables. Global variables are defined using the `def` special form and are avaiable anywhere in your program:

```lisp
roughcut> (def name "Rupert")
=> "Rupert"
roughcut> name
=> "Rupert"
roughcut> ((fn () (puts name)))
Rupert
=> nil
```

Local variables are just function arguments. A local scope is introduced by calling a function. When the function is called, a new scope is created and the function's arguments are bound to values. Local variables will shadow both global variables and function arguments in outer scopes:

```lisp
roughcut> ((fn ()
               (puts name)
               ((fn (name)
                    (puts name)
                    ((fn (name)
                         (puts name)) "Alice"))
                "Bob")))
Rupert
Bob
Alice
=> nil
```

You can also use the `let` family of macros (`let`, `let*`, and `letrec`) to introduce new scopes and local bindings, but these are really just functions in disguise.

```lisp
roughcut> (let (a 1 b 2) (+ a b))
=> 3
roughcut> (macroexpand '(let (a 1 b 2) (+ a b)))
=> ((fn (a b) (+ a b)) 1 2)
```

```lisp
roughcut> (let* (a 1 b (+ a 1)) (list a b))
=> (1 2)
roughcut> (macroexpand-all '(let* (a 1 b (+ a 1)) (list a b)))
=> ((fn (a) ((fn (b) (list a b)) (+ a 1))) 1)
```

```lisp
roughcut> (letrec (odd?
                   (fn (n) (if (zero? n) false (even? (- n 1))))
                   even?
                   (fn (n) (if (zero? n) true (odd? (- n 1)))))
            (odd? 10))
=> false
roughcut> (macroexpand-all '(letrec (odd?
                                     (fn (n) (if (zero? n) false (even? (- n 1))))
                                     even?
                                     (fn (n) (if (zero? n) true (odd? (- n 1)))))
                              (odd? 10)))
; formatted for readability
=> ((fn (odd? even?)
        (set! odd? (fn (n) (if (zero? n) false (even? (- n 1)))))
        (set! even? (fn (n) (if (zero? n) true (odd? (- n 1)))))
        (odd? 10))
    nil nil)
```

### Mutating varialbes

Function application only lets you shadow variables in outer scopes. Once the function finishes, these variables will be back to their old values. Roughcut has two ways of perminantly changing the value of a variable.

If your variable is global, you can use the `def` special form to redefine it:

```lisp
roughcut> (def planet "Mars")
=> "Mars"
roughcut> planet
=> "Mars"
roughcut> (def planet "Jupiter")
=> "Jupiter"
roughcut> planet
=> "Jupiter"
```

If you have a local variable, you can use `set!` to redefine it:

```lisp
roughcut> (let (name "Holly")
               (puts name)
               (set! name "Molly")
               (puts name))
Holly
Molly
=> nil
```

`set!` only works on variables that already exist. It searches for the variable named in its first argument, starting at the innermost scope and working its way out. If it can't find an existing binding, it throws an exception:

```lisp
roughcut> (set! not-here 100)
NameError: Undefined variable 'not-here'
        in 'set!'
```

You can, of course, use `set!` on globals:

```lisp
roughcut> (set! planet "Pluto")
=> "Pluto"
roughcut> planet
=> "Pluto"
```

## Read-eval-print loop

Roughcut has a nice little REPL. It uses Readline to provide line editing, navigation, command history, and history lookup. It saves history between invocations in `~/.roughcut_history`. Roughcut preserves whatever history existed before its REPL started and restores it after it ends. This means that Roughcut plays nice from within IRB or Pry:

```
$ pry
[1] pry(main)> load 'roughcut.rb'
=> true
[2] pry(main)> Roughcut.new.repl
roughcut> (+ 1 2)
=> 3
roughcut> ; use the up arrow to get to the last line we eval'd
roughcut> (+ 1 2)
=> 3
roughcut> (exit)
=> nil
[3] pry(main)> # use the up arrow to get to the last line we ran in our Ruby REPL
[3] pry(main)> load 'roughcut.rb'
=> true
[4] pry(main)> Roughcut.new.repl
roughcut.rb:5: warning: already initialized constant HISTORY_FILE
roughcut> ; use the up arrow twice to get (+ 1 2) again.
roughcut> (+ 1 2)
=> 3
```

The Roughcut REPL has two special global variables, `_` and `env`.

For convenience, the value of the last line to be evaluated is stored in `_`:

```lisp
roughcut> (fn (i) (* -1 i))
=> (fn (i) (* -1 i))
roughcut> _
=> (fn (i) (* -1 i))
roughcut> (_ 50)
=> -50
```

`env` is a special variable that stores the entire current environment. It's useful for debugging the Roughcut interpreter. `env` contains an array of Ruby hashes, one per scope, and stores all variables and functions:

```
roughcut> (def phone-number "212-555-1212")
=> "212-555-1212"
roughcut> env
=> #<Roughcut::Env:0x007fe333098be8
 @envs=
  [{#<Roughcut::Id: p>=>#<Proc:0x007fe333099598@roughcut.rb:157 (lambda)>,
    #<Roughcut::Id: puts>=>#<Proc:0x007fe3330994a8@roughcut.rb:170 (lambda)>,
    #<Roughcut::Id: send>=>#<Proc:0x007fe333099408@roughcut.rb:177 (lambda)>,
    #<Roughcut::Id: quote>=>#<Proc:0x007fe3330992c8@roughcut.rb:185 (lambda)>,
    #<Roughcut::Id: quasiquote>=>
     #<Proc:0x007fe3330991d8@roughcut.rb:186 (lambda)>,
    #<Roughcut::Id: apply>=>#<Proc:0x007fe333099138@roughcut.rb:187 (lambda)>,
    #<Roughcut::Id: def>=>#<Proc:0x007fe333099098@roughcut.rb:189 (lambda)>,
    #<Roughcut::Id: set!>=>#<Proc:0x007fe333098fa8@roughcut.rb:199 (lambda)>,
    #<Roughcut::Id: fn>=>#<Proc:0x007fe333098ee0@roughcut.rb:203 (lambda)>,
    #<Roughcut::Id: macro>=>#<Proc:0x007fe333098df0@roughcut.rb:211 (lambda)>,
    #<Roughcut::Id: load>=>#<Proc:0x007fe333098d28@roughcut.rb:215 (lambda)>,
    #<Roughcut::Id: if>=>#<Proc:0x007fe333098c88@roughcut.rb:221 (lambda)>,
    #<Roughcut::Id: VERSION>=>"0.0.0",
    #<Roughcut::Id: defmacro>=>
     (defmacro defmacro (name args body) `(def ,name (macro ,args ,body))),
    #<Roughcut::Id: defn>=>
    ...snip...
    #<Roughcut::Id: env>=>#<Roughcut::Env:0x007fe333098be8 ...>,
    #<Roughcut::Id: _>=>#<Roughcut::Env:0x007fe333098be8 ...>,
    #<Roughcut::Id: phone-number>=>"212-555-1212"}]>
```

### REPL Options

The default Roughcut REPL uses Readline for line editing and history. The `--simple` flag will bypass Readline and read directly from `STDIN`:

```
$ ruby roughcut.rb --simple
roughcut> (+ 1 2 3)
=> 6
roughcut> ; up arrow does nothing
```

Additionally, the `--no-prompt` flag disables the Roughcut prompt entirely:

```
$ ruby roughcut.rb --no-prompt
(+ 1 2 3)
6
; you could enter more expressions here
```

I'm not sure why I added `--no-prompt`, but I have a hunch it might be useful at some point.

## Ruby

Roughcut is just Ruby. All objects in Roughcut are Ruby objects. You can use the `type` function to see what kind of object you have:

```lisp
roughcut> (type 42)
=> Fixnum
roughcut> (type 100000000000000000000000000000)
=> Bignum
roughcut> (type 3.141)
=> Float
roughcut> (type "Hello")
=> String
roughcut> (type :name)
=> Symbol
roughcut> (type /foo/i)
=> Regexp
```

### Regular expression caveats

While Roughcut does support Ruby regular expression literals, there is a small caveat. Because `/` is a valid function name, Roughcut cannot support standard regular expression literals with leading whitespace. To illustrate the problem, consider how would you interpret `(match / foo / " foo ")`. At first glance it looks like match is taking two arguments: the regexp `/ foo /` and the string `" foo "`, but in reality, match is taking four arguments: `/`, `foo`, `/`, and `" foo "`. To get around this problem, Roughcut also supports Ruby's alternative regexp literal syntax: `%r{}`. You can use this to write a regexp with leading whitespace:

```lisp
roughcut> %r{ foo }
=> / foo /
```

## Special forms

Roughcut has a number of special forms that don't follow the normal rules of evaluation. These are `def`, `set!`, `fn`, `macro`, `if`, `quote`, `quasiquote`, `unquote`, `unquote-splicing`, and `send`. Unlike most other Lisps, many of these are implemented as functions and some are even implemented in Roughcut itself. Only `unquote` and `unquote-splicing` are not not defined as functions. This means you can redefine core pieces of the language at will. Remember: with great power comes great responsibility. Use this feature wisely.

### `send`

Roughcut defines one new special form called `send`. This is similar to Clojure's dot operator and can be used to call into Ruby. `send` takes a receiver, an optional method name as a symbol, and optional method arguments. If a method name is given, `send` calls `Kernel#send` on the receiver with the given arguments. If no method name is given, `send` simply returns the receiver. If the receiver is not found in the current environment, it is eval'd as Ruby code. Here are some examples:

```lisp
roughcut> (send Object)
=> Object
roughcut> (send _ :new)
=> #<Object:0x007f8c6b0d6d68>
roughcut> (send [1,2,3,4,5] :inject :+)
=> 15
```

`send` allows Roughcut to be implemented almost entirely in itself rather than in Ruby. For instance, all of Roughcut's math, logic, string and list manipulation functions are implemented in Roughcut.

## Internals

For better or worse, Roughcut's interpreter is mostly of my own devising. Roughcut's reader, on the other hand, shares a fair amount of DNA with Clojure's reader. I'm not sure how I feel about this. Once upon a time, Roughcut had a lexer and parser that I came up with on my own. The [lexer] [1] was a gross birdsnest of regular expressions that I had trouble reading mere days after I wrote it. Certainly the new reader is better than the old lexer/parser combination, however part of me wishes it didn't turn out so similar to the Clojure reader.

[1]: https://github.com/davidbalbert/roughcut/blob/9e4b7014ca63eb78a9c8491a6ec07eea503a4c40/roughcut.rb#L316-L368

## Imperfections

Roughcut is full of flaws. Here are some I'd like to correct in no particular order:

- No block literals.
- No source information in backtraces.
- No ruby method information in backtraces.
- Functions defined in Ruby do not evaluate to their source.
- Some functions defined in Ruby (`def`, `fn`, `macro`, `if`) report an incorrect arity when called with the wrong number of arguments.
- No multi-arity functions.
- No argument destructuring.
- The source could be cleaner, shorter, and less gross.
- Runtime macros are slow.

## Requirements

Roughcut requires Ruby 1.9 compiled with Readline support in the standard library.

## Shamless plug

If you like Roughcut, you might like [Hacker School](https://www.hackerschool.com/), a school I run with some of my friends.

## Thanks

My thanks to [Zach](https://github.com/zachallaun) and [Allison](https://github.com/akaptur) for challenging me to implement `map`, `filter`, and `reduce` in a language of my choosing, eventually sending me down this rabbit hole, [Alan](https://github.com/happy4crazy) for feedback on my macro system, [David](https://github.com/swannodette) for encouraging me to explore the Clojure reader, and Zach again for his help with `letrec` and `set!`.

## License

Roughcut is copyright 2013 David Albert and is licensed under the terms of the GNU GPLv3. See COPYING for more details.
