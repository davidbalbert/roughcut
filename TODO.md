- Fix Lisp#parse to be able to parse multiple expressions
  ```
  parse()
    expressions = []
    while_more_input
      expressions << parse_expression()
- test reduce
- define map and filter in terms of reduce
- define unquote
- define defmacro?