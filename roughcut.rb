require 'readline'
require 'pp'

require './reader'
require './helpers'

class Roughcut
  HISTORY_FILE = File.expand_path("~/.roughcut_history")

  class Exit < StandardError; end

  include Helpers

  class Function
    include Helpers

    def initialize(interpreter, arg_names, expressions, env)
      @sexp = List.build(q("fn"), arg_names, *expressions)
      @interpreter = interpreter
      @arg_names = arg_names
      @expressions = expressions
      @env = env
      @min_args, @max_args = parse_argument_list
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
      check_arg_count!(args)

      merged_env = @env.merge(zip_args(@arg_names, args))
      @expressions.map do |expr|
        @interpreter.eval(expr, merged_env)
      end.last
    end

    def to_s
      @sexp.to_s
    end

    def inspect
      to_s
    end

    private

    def set_sexp_with_name!
      @sexp = List.build(q("defn"), @name, *@sexp.rest)
    end

    # returns [min_args, max_args]
    def parse_argument_list
      if @arg_names.include?(q("&"))
        unless @arg_names.count(q("&")) == 1 && @arg_names.index(q("&")) == @arg_names.size - 2
          raise SyntaxError, "'&' can only be found in the second to last position of an argument list"
        end

        [@arg_names.size - 2, -1]
      else
        [@arg_names.size, @arg_names.size]
      end
    end

    def check_arg_count!(args)
      if args.size < @min_args
        raise ArgumentError, "wrong number of arguments (#{args.size} for #{@min_args})"
      elsif @max_args != -1 && args.size > @max_args
        raise ArgumentError, "wrong number of arguments (#{args.size} for #{@max_args})"
      end
    end

    def zip_args(arg_names, args)
      if arg_names.include?(q("&"))
        arg_names = arg_names.to_a
        required = arg_names.size - 2
        Hash[arg_names[0...required].zip(args[0...required]) + [[arg_names[-1], List.build(*args[required..-1])]]]
      else
        Hash[arg_names.zip(args)]
      end
    end
  end

  class Macro < Function
    def initialize(interpreter, arg_names, body, env)
      @sexp = List.build(q("macro"), arg_names, body)
      @interpreter = interpreter
      @arg_names = arg_names
      @body = body
      @env = env
      @min_args, @max_args = parse_argument_list
    end

    def call(*args)
      check_arg_count!(args)

      @interpreter.eval(@body, @env.merge(zip_args(@arg_names, args)))
    end

    private

    def set_sexp_with_name!
      @sexp = List.build(q("defmacro"), @name, *@sexp.rest)
    end
  end

  class Env
    def initialize(*envs)
      @envs = envs

      if @envs.empty?
        @envs[0] = {}
      end
    end

    def merge(other)
      Env.new(other, *@envs)
    end

    def [](key)
      @envs.each do |e|
        return e[key] if e.has_key?(key)
      end

      nil
    end

    def []=(key, value)
      @envs[0][key] = value
    end

    def has_key?(key)
      !!@envs.find { |e| e.has_key?(key) }
    end

    def set!(key, value)
      e = @envs.find { |e| e.has_key?(key) }

      raise NameError, "Undefined variable '#{key}'" unless e

      e[key] = value
    end
  end

  attr_reader :env

  def initialize
    @stack = []

    @env = Env.new({
      q("p") => lambda do |*args|
        out = args.map do |a|
          if a.is_a?(Id) || list?(a)
            a.to_s
          else
            a.inspect
          end
        end
        puts out

        List.build(*args)
      end,

      q("puts") => lambda do |*args|
        out = args.map { |a| a.to_s }.join(" ")
        puts out

        nil
      end,

      q("send") => lambda do |receiver, method=nil, *args|
        if method
          receiver.send(method, *args)
        else
          receiver
        end
      end,

      q("quote") => lambda { |env, list| list },
      q("quasiquote") => lambda { |env, list| process_unquotes(list, env) },
      q("apply") => lambda { |f, *args, arg_list| f.call(*(args.to_a + arg_list.to_a)) },

      q("def") => lambda do |env, name, val|
        val = eval(val, env)
        # for functions and macros
        if val.respond_to?(:name=)
          val.name = name
        end

        @env[name] = val
      end,

      q("set!") => lambda do |env, name, val|
        env.set!(name, eval(val, env))
      end,

      q("fn") => lambda do |env, arg_names, *expressions|
        if expressions.empty?
          raise SyntaxError, "wrong number of arguments (1 for 2)"
        end

        Function.new(self, arg_names, expressions, env)
      end,

      q("macro") => lambda do |env, arg_names, body|
        Macro.new(self, arg_names, body, env)
      end,

      q("load") => lambda do |filename|
        sexps = Reader.new(File.read(File.expand_path(filename))).read_all
        sexps.each {|sexp| eval(sexp) }
        true
      end,

      q("if") => lambda do |env, condition, yes, no=nil|
        if condition
          eval(yes, env)
        else
          eval(no, env)
        end
      end
    })

    @env[q("load")].call("stdlib.lisp")
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
      input = Readline.readline("roughcut> ")
      break if input.nil? || input == " "
      next if input.gsub(/;.*?$/, "").strip.empty?

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

  def simple_repl
    @env[q("env")] = @env

    reader = Reader.new(STDIN)

    print "roughcut> "

    loop do
      begin
        saw_newline = reader.skip_whitespace_through_newline!

        unless saw_newline
          expr = reader.read(false)

          if expr == EOF
            puts
            break
          end

          out = eval(expr)

          print "=> "

          case out
          when List, EmptyList, Id
            puts out
          else
            pp out
          end
        end
      rescue Exit
        break
      rescue StandardError => e
        STDERR.puts("#{e.class}: #{e.message}")
        puts backtrace
        clear_stack!
      rescue SyntaxError => e
        STDERR.puts("#{e.class}: #{e.message}")
        puts backtrace
        clear_stack!
      end

      print "roughcut> " if reader.at_line_start?
    end
  end

  def eval(o, env=@env)
    if o.is_a?(Id)
      if env.has_key?(o)
        env[o]
      else
        raise NameError, "#{o} is undefined"
      end
    elsif list?(o)
      if o.empty?
        o # () should return the empty list
      else
        func_name = o.first
        func = eval(func_name, env)

        @stack.unshift(func_name)

        result = case func_name
        when q("quote"), q("quasiquote"), q("def"), q("set!"), q("fn"), q("macro")
          func.call(env, *o.rest)
        when q("if")
          func.call(env,
                    eval(o.rest.first, env),
                    o.rest.rest.first,
                    o.rest.rest.rest.first)
        when q("send")
          # send is a special form that evals it's second argument as ruby code
          receiver = o.rest.first
          if receiver.is_a?(Id) && env.has_key?(receiver)
            receiver = env[receiver]
          elsif receiver.is_a?(Id)
            receiver = super(receiver.to_s)
          elsif list?(receiver)
            receiver = eval(receiver, env)
          end

          func.call(receiver, *o.rest.rest.map { |obj| eval(obj, env) })
        else
          if func.is_a?(Macro)
            eval(func.call(*o.rest), env)
          else
            func.call(*o.rest.map { |obj| eval(obj, env) })
          end
        end

        @stack.shift

        result
      end
    else
      o
    end
  end

  # TODO: I think process_unquotes and splice are both kind of hard to read and
  # should probably be rewritten.
  def process_unquotes(o, env)
    if list?(o)
      if o.first == q("unquote")
        fail "unquote expects only one operand" unless o.size == 2
        eval(o.rest.first, env)
      elsif o.first == q("unquote-splicing")
        fail "unquote-splicing expects only one operand" unless o.size == 2
        List.build(o.first, *eval(o.rest.first, env))
      else
        o = List.build(*o.map { |el| process_unquotes(el, env) })

        # splice in the results of evaling unquote-splicing. We don't have to
        # worry about splicing at the top level because `~@foo is invalid and
        # will be caugt by the reader. TODO: Maybe refactor this?
        splice(o)
      end
    else
      o
    end
  end

  def splice(o)
    if list?(o)
      spliced = []
      o.each do |obj|
        if list?(obj) && obj.first == q("unquote-splicing")
          spliced.concat(obj.rest.to_a)
        else
          spliced << obj
        end
      end

      List.build(*spliced)
    else
      o
    end
  end

  def macroexpand_1(o)
    if (list?(o) &&
        @env.has_key?(o.first) &&
        (macro = eval(o.first)).is_a?(Macro))

      macro.call(*o.rest)
    else
      o
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

if __FILE__ == $0
  Roughcut.new.simple_repl
end
