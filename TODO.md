- Fix Lisp#parse to be able to parse multiple expressions

  ```ruby
    def parse()
      expressions = []
      while_more_input do
        expressions << parse_expression()
      end
    end
  ```
- Make nested lets work
- Make functions closures (will the previous step do this automatically? probably not)
- test reduce
- define map and filter in terms of reduce
- define unquote
- define defmacro?
- define defn
- implement let as a macro