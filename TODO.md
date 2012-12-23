- Fix Lisp#parse to be able to parse multiple expressions
  ```ruby
  def parse()
    expressions = []
    while_more_input do
      expressions << parse_expression()
    end
  end
  ```
- test reduce
- define map and filter in terms of reduce
- define unquote
- define defmacro?