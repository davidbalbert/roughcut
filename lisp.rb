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
    def initialize(expressions, args, &block)
      @sexp = Sexp.new([:fn, args, *expressions])
      @block = lambda &block
    end

    def to_proc
      @block
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
  end

  def initialize
    @env = {
      :+ => lambda { |*args| args.reduce(:+) },
      :- => lambda { |*args| args.reduce(:-) },
      :* => lambda { |*args| args.reduce(:*) },
      :/ => lambda { |*args| args.reduce(:/) },
      :puts => lambda { |*args| args.each { |a| p a }; nil },

      :quote => lambda { |list| list },
      :eval => lambda { |list| eval(list) },
      :first => lambda { |list| list[0] },
      :rest => lambda { |list| list[1..-1] },
      :def => lambda { |name, val| @env[name] = val },

      # uncomment when I'm on 1.9
      # "cons" => lambda { |val, list=nil| list ? list.unshift(val) : Sexp.new([val]) }

      # ugly hack for ruby 1.8
      :cons => lambda do |*args|
        if args.size == 0
          raise ArgumentError, "wrong number of arguments (0 for 1)"
        elsif args.size > 2
          raise ArgumentError, "wrong number of arguments (#{args.size} for 2)"
        end

        val = args[0]
        list = args[1] || nil

        list ? list.unshift(val) : Sexp.new([val])
      end,

      :let => lambda do |bindings, *expressions|
        expressions.map do |expr|
          eval(expr, @env.merge(Hash[*bindings.flatten]))
        end.last
      end,

      :fn => lambda do |arg_names, *expressions|
        Function.new(expressions, arg_names) do |*args|
          if args.size != arg_names.size
            raise ArgumentError, "wrong number of arguments (#{args.size} for #{arg_names.size})"
          end

          expressions.map do |expr|
            eval(expr, @env.merge(Hash[arg_names.zip(args)]))
          end.last
        end
      end,

      :load => lambda do |filename|
        eval(parse(File.read(File.expand_path(filename)).gsub("\n", "")))
      end,


      :if => lambda do |condition, yes, no|
        if condition
          eval(yes)
        else
          eval(no)
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
      end
    end
  end

  def lex(input)
    tokens = input.gsub("(", " ( ").gsub(")", " ) ").split
    tokens = tokens.map do |t|
      if md = /^\d+$/.match(t)
        md[0].to_i
      elsif md = /^'(.*)'$/.match(t)
        md[1]
      elsif md = /^"(.*)"$/.match(t)
        md[1]
      elsif t == "nil"
        nil
      elsif t == "true"
        true
      elsif t == "false"
        false
      else
        t.to_sym
      end
    end
  end

  def parse(input)
    tokens = lex(input)
    parse_expressions(tokens)
  end

  def eval(sexp, env=@env)
    if sexp.is_a?(Sexp)
      case sexp[0]
      when :quote
        eval(:quote).call(*sexp[1..-1])
      when :def
        eval(:def).call(sexp[1], *sexp[2..-1].map do |o|
          eval(o, env)
        end)
      when :let
        eval(:let).call(*sexp[1..-1])
      when :fn
        eval(:fn).call(*sexp[1..-1])
      when :if
        eval(:if).call(eval(sexp[1]), *sexp[2..-1])
      else
        eval(sexp[0]).call(*sexp[1..-1].map { |o| eval(o, env) })
      end
    elsif sexp.is_a?(Array) # Top level
      sexp.map { |s| eval(s) }.last
    elsif sexp.is_a?(Symbol)
      env[sexp]
    else
      sexp
    end
  end

  private

  def parse_expressions(tokens)
    expressions = []
    until tokens.empty?
      if tokens.first == :"("
        expressions << parse_sexp(tokens)
      elsif tokens.first == :")"
        break
      else
        expressions << tokens.shift
      end
    end

    expressions
  end

  def parse_sexp(tokens)
    expect(:"(", tokens)

    sexp = Sexp.new

    until tokens.first == :")"
      expect_more(tokens)
      t = tokens.shift
      sexp << if t == :"("
        tokens.unshift(t)
        parse_sexp(tokens)
      else
        t
      end
    end

    expect(:")", tokens)

    sexp
  end

  def expect(type, tokens)
    t = tokens.shift
    raise "Expecting #{type}, got #{t}" unless t == type
    t
  end

  def expect_more(tokens)
    raise "Expecting more input but reached end" if tokens.empty?
  end
end

Lisp.new.repl
