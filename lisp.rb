require 'readline'
require 'pp'

class Lisp
  HISTORY_FILE = File.expand_path("~/.lisprb_history")

  class Exit < StandardError; end

  class Id
    def initialize(sym)
      @sym = sym
    end

    def ==(other)
      @sym == other.to_sym
    end

    def to_s
      @sym.to_s
    end
    alias to_str to_s

    def inspect
      "id:#{@sym.to_s}"
    end

    def to_sym
      @sym
    end
  end

  class LazyRange
    def initialize(start, stop, exclusive=false)
      @start = start
      @stop = stop
      @exclusive = exclusive
    end

    def to_range(lisp, env)
      Range.new(lisp.eval(@start, env), lisp.eval(@stop, env), @exclusive)
    end

    def to_s
      if @exclusive
        "#{@start}...#{@stop}"
      else
        "#{@start}..#{@stop}"
      end
    end
  end

  class Sexp < Array
    def to_s
      if first.is_a?(Id) && first == :quote
        "'#{self[1].to_s}"
      elsif first.is_a?(Id) && first == :quasiquote
        "`#{self[1].to_s}"
      elsif first.is_a?(Id) && first == :unquote
        "~#{self[1].to_s}"
      elsif first.is_a?(Id) && first == :"unquote-splicing"
        "~@#{self[1].to_s}"
      else
        "(#{reduce("") do |out, o|
          if o.is_a?(String)
            o = "\"#{o}\""
          elsif o.is_a?(Symbol)
            o = o.inspect
          elsif o.nil?
            o = "nil"
          end
          out << o.to_s + " "
        end.strip})"
      end
    end

    def inspect
      to_s
    end
  end

  class Function
    def initialize(args, expressions, &block)
      @sexp = Sexp.new([Id.new(:fn), args, *expressions])
      @block = lambda &block
    end

    def name=(name)
      # once named, functions cannot be renamed
      unless @name
        @name = name
        set_sexp_with_name!
      end

      name
    end

    def call(*args)
      @block.call(*args)
    end

    def to_s
      @sexp.to_s
    end

    def inspect
      to_s
    end

    private

    def set_sexp_with_name!
      @sexp = Sexp.new([Id.new(:defn), @name, *@sexp[1..-1]])
    end
  end

  class Macro < Function
    def initialize(args, body, &block)
      @sexp = Sexp.new([Id.new(:macro), args, body])
      @block = lambda &block
    end

    private

    def set_sexp_with_name!
      @sexp = Sexp.new([Id.new(:defmacro), @name, *@sexp[1..-1]])
    end
  end

  attr_reader :env

  def initialize
    @stack = []

    @env = {
      :p => lambda do |*args|
        out = args.map do |a|
          if a.is_a?(Id)
            a.to_s
          else
            a.inspect
          end
        end
        puts out

        nil
      end,

      :puts => lambda do |*args|
        out = args.map { |a| a.to_s }.join(" ")
        puts out

        nil
      end,

      :send => lambda do |receiver, method=nil, *args|
        if method
          receiver.send(method, *args)
        else
          receiver
        end
      end,

      :quasiquote => lambda { |env, list| process_unquotes(list, env) },
      :"macroexpand-1" => lambda { |sexp| macroexpand_1(sexp) },
      :apply => lambda { |f, *args, arg_list| f.call(*(args + arg_list)) },

      :def => lambda do |env, name, val|
        val = eval(val, env)
        # for functions and macros
        if val.respond_to?(:name=)
          val.name = name
        end

        @env[name.to_sym] = val
      end,

      :fn => lambda do |env, arg_names, *expressions|
        if expressions.empty?
          raise SyntaxError, "wrong number of arguments (1 for 2)"
        end
        min_args, max_args = parse_argument_list(arg_names)

        Function.new(arg_names, expressions) do |*args|
          check_arg_count(args, min_args, max_args)

          expressions.map do |expr|
            eval(expr, env.merge(zip_args(arg_names, args)))
          end.last
        end
      end,

      :macro => lambda do |env, arg_names, body|
        min_args, max_args = parse_argument_list(arg_names)

        Macro.new(arg_names, body) do |*args|
          check_arg_count(args, min_args, max_args)

          eval(body, env.merge(zip_args(arg_names, args)))
        end
      end,

      :load => lambda do |filename|
        eval(parse(File.read(File.expand_path(filename))))
        true
      end,

      :if => lambda do |env, condition, yes, no=nil|
        if condition
          eval(yes, env)
        else
          eval(no, env)
        end
      end
    }

    @env[:load].call("stdlib.lisp")
  end

  def repl
    @old_history = Readline::HISTORY.to_a
    clear_history!

    if File.exists?(HISTORY_FILE)
      history = File.read(HISTORY_FILE).split("\n")
      load_history(history)
    end

    @env[:env] = @env

    loop do
      input = Readline.readline("lisp.rb> ")
      next if input.empty?
      break if input == " "

      begin
        if Readline::HISTORY.size == 0 || Readline::HISTORY[-1] != input
          Readline::HISTORY << input
        end

        out = eval(parse(input))
        @env[:_] = out

        print "=> "
        if out.is_a?(Sexp)
          p out
        elsif out.is_a?(Id)
          puts out
        else
          pp out
        end
      rescue Exit
        break
      rescue StandardError => e
        STDERR.puts("#{e.class}: #{e.message}")
        puts backtrace
        clear_stack!
        #STDERR.puts(e.backtrace)
      rescue SyntaxError => e
        STDERR.puts("#{e.class}: #{e.message}")
        puts backtrace
        clear_stack!
      end
    end
  ensure
    File.open(HISTORY_FILE, "w") do |f|
      f.write(Readline::HISTORY.to_a.join("\n") + "\n")
    end

    clear_history!
    load_history(@old_history)
  end

  def lex(input)
    # remove comments
    input = input.gsub(/;.*?$/, "").strip
    tokens = []
    until input.empty?
      input = input.lstrip

      if md = /\A(~@)/.match(input)
        tokens << Id.new(md[1].to_sym)
      elsif md = /\A(['`~()])/.match(input)
        tokens << Id.new(md[1].to_sym)
      elsif md = /\A(([^\s()"'`~:]+|-?\d+)(\.\.\.?)([^\s()"'`~:]+|-?\d+))/.match(input)
        first = md[2].to_i.to_s == md[2] ? md[2].to_i : Id.new(md[2].to_sym)
        last = md[4].to_i.to_s == md[4] ? md[4].to_i : Id.new(md[4].to_sym)

        tokens << if md[3].length == 2
          LazyRange.new(first, last, false)
        else
          LazyRange.new(first, last, true)
        end
      elsif md = /\A(-?\d+\.\d+)/.match(input)
        tokens << md[1].to_f
      elsif md = /\A(-?\d+)/.match(input)
        tokens << md[1].to_i
      elsif md = /\A(\/(\/|\S.*?\/)[a-z]*)/.match(input)
        # Regexp syntax. Due to limitations with our lexer, the first character
        # of the regexp body must not be whitespace
        tokens << BasicObject.new.instance_eval(md[1])
      elsif md = /\A(%r\{.*?\}[a-z]*)/.match(input)
        # alternative regexp syntax: %r{body}options
        # works even with a leading space
        tokens << BasicObject.new.instance_eval(md[1])
      elsif md = /\A("(.*?)")/.match(input)
        tokens << md[2]
      elsif md = /\A(nil)/.match(input)
        tokens << nil
      elsif md = /\A(true)/.match(input)
        tokens << true
      elsif md = /\A(false)/.match(input)
        tokens << false
      elsif md = /\A((::)?[^\s()"'`~:]+(::[^\s()"'`~:]+)*)/.match(input)
        tokens << Id.new(md[1].to_sym)
      elsif md =/\A(:([^\s()"'`~:]*))/.match(input)
        tokens << md[2].to_sym
      else
        raise SyntaxError, "Error at input: #{input}"
      end
      input = input[md[1].length..-1]

    end

    tokens
  end

  def eval(sexp, env=@env)
    if sexp.is_a?(Sexp) && sexp.empty?
      sexp # () should return the empty list
    elsif sexp.is_a?(Sexp)
      func = sexp[0].respond_to?(:to_sym) ? sexp[0].to_sym : sexp[0]

      @stack.unshift(func)

      result = case func
      when :quote
        eval(sexp[0], env).call(*sexp[1..-1])
      when :quasiquote
        eval(sexp[0], env).call(env, *sexp[1..-1])
      when :def
        eval(sexp[0], env).call(env, *sexp[1..-1])
      when :fn
        eval(sexp[0], env).call(env, *sexp[1..-1])
      when :macro
        eval(sexp[0], env).call(env, *sexp[1..-1])
      when :if
        eval(sexp[0], env).call(env, eval(sexp[1], env), *sexp[2..-1])
      when :send
        # send is a special form that evals it's second argument as ruby code
        receiver = sexp[1]
        if receiver.is_a?(Id) && env.has_key?(receiver.to_sym)
          receiver = env[receiver.to_sym]
        elsif receiver.is_a?(Id)
          receiver = super(receiver)
        elsif receiver.is_a?(Sexp) || receiver.is_a?(LazyRange)
          receiver = eval(receiver, env)
        end

        eval(sexp[0], env).call(receiver, *sexp[2..-1].map { |o| eval(o, env) })
      else
        f = eval(sexp[0], env)
        if f.is_a?(Macro)
          eval(f.call(*sexp[1..-1]), env)
        else
          f.call(*sexp[1..-1].map { |o| eval(o, env) })
        end
      end

      @stack.shift

      result
    elsif sexp.is_a?(Array) # Top level
      sexp.map { |s| eval(s, env) }.last
    elsif sexp.is_a?(Id)
      if env.has_key?(sexp.to_sym)
        env[sexp.to_sym]
      else
        raise NameError, "#{sexp} is undefined"
      end
    elsif sexp.is_a?(LazyRange)
      sexp.to_range(self, env)
    else
      sexp
    end
  end

  def parse(input)
    tokens = lex(input)

    expressions = parse_vals(tokens)

    expect_done(tokens)

    expressions
  end

  private

  def parse_vals(tokens)
    vals = []
    until tokens.empty? || tokens.first == :")"
      vals << parse_val(tokens)
    end

    vals
  end

  def parse_val(tokens)
    if tokens.first == :"'"
      tokens.shift
      Sexp.new([Id.new(:quote), parse_val(tokens)])
    elsif tokens.first == :`
      tokens.shift
      sexp = Sexp.new([Id.new(:quasiquote), parse_val(tokens)])

      if sexp[1].is_a?(Sexp) && sexp[1][0] == :"unquote-splicing"
        raise SyntaxError, "You cannot use unquote-splicing outside of a list"
      end

      sexp
    elsif tokens.first == :~
      tokens.shift
      Sexp.new([Id.new(:unquote), parse_val(tokens)])
    elsif tokens.first == :"~@"
      tokens.shift
      Sexp.new([Id.new(:"unquote-splicing"), parse_val(tokens)])
    elsif tokens.first == :"("
      parse_sexp(tokens)
    else
      tokens.shift
    end
  end

  def parse_sexp(tokens)
    expect(:"(", tokens)

    sexp = Sexp.new(parse_vals(tokens))

    expect(:")", tokens)

    sexp
  end

  def expect(type, tokens)
    t = tokens.shift
    raise SyntaxError, "Expecting #{type}, got a '#{t}'" unless t == type
    t
  end

  def expect_done(tokens)
    raise SyntaxError, "Expected end of input but got a '#{tokens.first}'" unless tokens.empty?
  end

  def process_unquotes(sexp, env)
    if sexp.is_a?(Sexp)
      if sexp.first == :unquote
        eval(*sexp[1..-1], env)
      elsif sexp.first == :"unquote-splicing"
        Sexp.new([sexp[0], *eval(*sexp[1..-1], env)])
      else
        sexp = Sexp.new(sexp.map { |el| process_unquotes(el, env) })
        splice(sexp)
      end
    else
      sexp
    end
  end

  def splice(sexp)
    if sexp.is_a?(Sexp)
      spliced = Sexp.new
      sexp.each do |o|
        if o.is_a?(Sexp) && o[0] == :"unquote-splicing"
          spliced.concat(o[1..-1])
        else
          spliced << o
        end
      end

      spliced
    else
      sexp
    end
  end

  # returns [min_args, max_args]
  def parse_argument_list(arg_names)
    if arg_names.include?(:&)
      unless arg_names.count(:&) == 1 && arg_names.index(:&) == arg_names.size - 2
        raise SyntaxError, "'&' can only be found in the second to last position of an argument list"
      end

      [arg_names.size - 2, -1]
    else
      [arg_names.size, arg_names.size]
    end
  end

  def check_arg_count(args, min_args, max_args)
    if args.size < min_args
      raise ArgumentError, "wrong number of arguments (#{args.size} for #{min_args})"
    elsif max_args != -1 && args.size > max_args
      raise ArgumentError, "wrong number of arguments (#{args.size} for #{max_args})"
    end
  end

  def zip_args(arg_names, args)
    arg_names = arg_names.map(&:to_sym)
    if arg_names.include?(:&)
      required = arg_names.size - 2
      Hash[arg_names[0..required].zip(args[0..required]) + [[arg_names[-1], Sexp.new(args[required..-1])]]]
    else
      Hash[arg_names.zip(args)]
    end
  end

  def exists_in_env?(name)
    name = name.to_sym if name.respond_to?(:to_sym)
    @env.has_key?(name)
  end

  def macroexpand_1(sexp)
    if (sexp.is_a?(Sexp) &&
        exists_in_env?(sexp[0]) &&
        (macro = eval(sexp[0])).is_a?(Macro))

      macro.call(*sexp[1..-1])
    else
      sexp
    end
  end

  def clear_history!
    Readline::HISTORY.shift until Readline::HISTORY.empty?
  end

  def load_history(history)
    history.each do |line|
      Readline::HISTORY << line
    end
  end

  def backtrace
    @stack.map { |func| "\tin '#{func}'" }.join("\n")
  end

  def clear_stack!
    @stack = []
  end
end

Lisp.new.repl
