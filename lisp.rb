require 'pp'

class Lisp
  class Sexp < Array
    def to_s
      "(#{reduce("") do |out, o|
        o = "\"#{o}\"" if o.is_a?(String)
        o = "nil" if o.nil?
        out << o.to_s + " "
      end.strip})"
    end

    def inspect
      to_s
    end
  end

  class Function
    def initialize(args, expressions, &block)
      @sexp = Sexp.new([:fn, args, *expressions])
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
      @sexp = Sexp.new([:defn, @name, *@sexp[1..-1]])
    end
  end

  class Macro < Function
    def initialize(args, body, &block)
      @sexp = Sexp.new([:macro, args, body])
      @block = lambda &block
    end

    private

    def set_sexp_with_name!
      @sexp = Sexp.new([:defmacro, @name, *@sexp[1..-1]])
    end
  end

  def initialize
    @env = {
      :+ => lambda { |*args| args.reduce(:+) },
      :- => lambda { |*args| args.reduce(:-) },
      :* => lambda { |*args| args.reduce(:*) },
      :/ => lambda { |*args| args.reduce(:/) },
      :mod => lambda { |a, b| a % b },

      :"=" => lambda { |a, b| a == b },
      :not => lambda { |a| !a },

      :p => lambda { |*args| args.each { |a| p a } },
      :puts => lambda do |*args|
        args.each do |a|
          if a.is_a?(Sexp)
            p a
          else
            puts a
          end
        end

        nil
      end,

      :eval => lambda { |list| eval(list) },
      :quote => lambda { |list| list },
      :quasiquote => lambda { |env, list| process_unquotes(list, env) },
      :"macroexpand-1" => lambda { |sexp| macroexpand_1(sexp) },
      :first => lambda { |list| list[0] },
      :rest => lambda { |list| list[1..-1] || Sexp.new },
      :apply => lambda { |f, *args, arg_list| eval(Sexp.new([f] + args + arg_list)) },
      :def => lambda do |env, name, val|
        val = eval(val, env)
        # for functions and macros
        if val.respond_to?(:name=)
          val.name = name
        end

        @env[name] = val
      end,

      :cons => lambda { |val, list| list.unshift(val) },
      :list? => lambda { |o| o.is_a?(Sexp) },
      :empty? => lambda { |list| list.empty? },
      :concat => lambda { |*lists| Sexp.new(lists.reduce(:+)) },

      :let => lambda do |env, bindings, *expressions|
        expressions.map do |expr|
          eval(expr, env.merge(Hash[*bindings.flatten]))
        end.last
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
        eval(parse(File.read(File.expand_path(filename)).gsub("\n", "")))
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
        print "=> "
        if out.is_a?(Sexp)
          p out
        else
          pp out
        end
      rescue StandardError => e
        STDERR.puts("#{e.class}: #{e.message}")
        #STDERR.puts(e.backtrace)
      end
    end
  end

  def lex(input)
    input = input.gsub("(", " ( ").gsub(")", " ) ").strip
    tokens = []
    until input.empty?
      input = input.lstrip

      if md = /^(\d+)/.match(input)
        tokens << md[1].to_i
        input = input[md[1].length..-1]
      elsif md = /^(['`~])/.match(input)
        tokens << md[1].to_sym
        input = input[md[1].length..-1]
      elsif md = /^("(.*?)")/.match(input)
        tokens << md[2]
        input = input[md[1].length..-1]
      elsif md = /^(nil)/.match(input)
        tokens << nil
        input = input[md[1].length..-1]
      elsif md = /^(true)/.match(input)
        tokens << true
        input = input[md[1].length..-1]
      elsif md = /^(false)/.match(input)
        tokens << false
        input = input[md[1].length..-1]
      elsif md = /^(\S*)\s?/.match(input)
        tokens << md[1].to_sym
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
      case sexp[0]
      when :quote
        eval(:quote, env).call(*sexp[1..-1])
      when :quasiquote
        eval(:quasiquote, env).call(env, *sexp[1..-1])
      when :def
        eval(:def, env).call(env, *sexp[1..-1])
      when :let
        eval(:let, env).call(env, *sexp[1..-1])
      when :fn
        eval(:fn, env).call(env, *sexp[1..-1])
      when :macro
        eval(:macro, env).call(env, *sexp[1..-1])
      when :if
        eval(:if, env).call(env, eval(sexp[1], env), *sexp[2..-1])
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
    elsif sexp.is_a?(Symbol)
      if env.has_key?(sexp)
        env[sexp]
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
      Sexp.new([:quote, parse_val(tokens)])
    elsif tokens.first == :`
      tokens.shift
      Sexp.new([:quasiquote, parse_val(tokens)])
    elsif tokens.first == :~
      tokens.shift
      Sexp.new([:unquote, parse_val(tokens)])
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
    raise "Expecting #{type}, got a '#{t}'" unless t == type
    t
  end

  def expect_more(tokens)
    raise "Expecting more input but reached end" if tokens.empty?
  end

  def expect_done(tokens)
    raise "Expected end of input but got a '#{tokens.first}'" unless tokens.empty?
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
