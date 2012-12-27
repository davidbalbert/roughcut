require 'pp'

class Lisp
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

  class Sexp < Array
    def to_s
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
      :apply => lambda { |f, *args, arg_list| eval(Sexp.new([f] + args + arg_list)) },
      :def => lambda do |env, name, val|
        val = eval(val, env)
        # for functions and macros
        if val.respond_to?(:name=)
          val.name = name
        end

        @env[name.to_sym] = val
      end,

      :cons => lambda { |val, list| Sexp.new([val] + list) },
      :concat => lambda { |*lists| Sexp.new(lists.reduce(:+)) },

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

      :if => lambda do |env, condition, yes, no|
        if condition
          eval(yes, env)
        else
          eval(no, env)
        end
      end
    }

    @env[:env] = @env

    @env[:load].call("stdlib.lisp")
  end

  def repl
    loop do
      print "lisp.rb> "

      input = gets.chomp
      next if input.empty?
      break if input == " "

      begin
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
      rescue StandardError => e
        STDERR.puts("#{e.class}: #{e.message}")
        #STDERR.puts(e.backtrace)
      rescue SyntaxError => e
        STDERR.puts("#{e.class}: #{e.message}")
      end
    end
  end

  def lex(input)
    # add space around parens and remove comments that start with a semicolon
    input = input.gsub(/;.*?$/, "").strip
    tokens = []
    until input.empty?
      input = input.lstrip

      if md = /\A(['`~()])/.match(input)
        tokens << Id.new(md[1].to_sym)
        input = input[md[1].length..-1]
      elsif md = /\A(-?\d+)/.match(input)
        tokens << md[1].to_i
        input = input[md[1].length..-1]
      elsif md = /\A("(.*?)")/.match(input)
        tokens << md[2]
        input = input[md[1].length..-1]
      elsif md = /\A(nil)/.match(input)
        tokens << nil
        input = input[md[1].length..-1]
      elsif md = /\A(true)/.match(input)
        tokens << true
        input = input[md[1].length..-1]
      elsif md = /\A(false)/.match(input)
        tokens << false
        input = input[md[1].length..-1]
      elsif md = /\A((::)?[^\s()"'`~:]+(::[^\s()"'`~:]+)*)/.match(input)
        tokens << Id.new(md[1].to_sym)
        input = input[md[1].length..-1]
      elsif md =/\A(:([^\s()"'`~:]*))/.match(input)
        tokens << md[2].to_sym
        input = input[md[1].length..-1]
      else
        raise SyntaxError, "Error at input: #{input}"
      end

    end

    tokens
  end

  def eval(sexp, env=@env)
    if sexp.is_a?(Sexp) && sexp.empty?
      sexp # () should return the empty list
    elsif sexp.is_a?(Sexp)
      case sexp[0].to_sym
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
    elsif sexp.is_a?(Array) # Top level
      sexp.map { |s| eval(s, env) }.last
    elsif sexp.is_a?(Id)
      if env.has_key?(sexp.to_sym)
        env[sexp.to_sym]
      else
        raise NameError, "#{sexp} is undefined"
      end
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
      Sexp.new([Id.new(:quasiquote), parse_val(tokens)])
    elsif tokens.first == :~
      tokens.shift
      Sexp.new([Id.new(:unquote), parse_val(tokens)])
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
      else
        Sexp.new(sexp.map { |el| process_unquotes(el, env) })
      end
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

  def macroexpand_1(sexp)
    if sexp.is_a?(Sexp) && (macro = eval(sexp[0])).is_a?(Macro)
      macro.call(*sexp[1..-1])
    else
      sexp
    end
  end
end

Lisp.new.repl
