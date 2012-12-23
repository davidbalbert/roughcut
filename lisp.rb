require 'pp'

class Lisp
  class Sexp < Array
    def to_s
      "(#{reduce("") { |out, o| out << o.to_s + " " }.strip})"
    end

    def inspect
      to_s
    end
  end

  def initialize
    @env = {
      "+" => lambda { |*args| args.reduce(:+) },
      "-" => lambda { |*args| args.reduce(:-) },
      "*" => lambda { |*args| args.reduce(:*) },
      "/" => lambda { |*args| args.reduce(:/) },
      "quote" => lambda { |list| list },
      "eval" => lambda { |list| evaluate(list) },
      "first" => lambda { |list| list[0] },
      "rest" => lambda { |list| list[1..-1] },
      "def" => lambda { |name, val| @env[name] = val },

      # uncomment when I'm on 1.9
      # "cons" => lambda { |val, list=nil| list ? list.unshift(val) : Sexp.new([val]) }

      # ugly hack for ruby 1.8
      "cons" => lambda do |*args|
        if args.size == 0
          raise ArgumentError, "wrong number of arguments (0 for 1)"
        elsif args.size > 2
          raise ArgumentError, "wrong number of arguments (#{args.size} for 2)"
        end

        val = args[0]
        list = args[1] || nil

        list ? list.unshift(val) : Sexp.new([val])
      end,

      "let" => lambda do |bindings, body|
        evaluate(body, @env.merge(Hash[*bindings.flatten]))
      end,

      "fn" => lambda do |arg_names, body|
        lambda do |*args|
          if args.size != arg_names.size
            raise ArgumentError, "wrong number of arguments (#{args.size} for #{arg_names.size})"
          end

          evaluate(body, @env.merge(Hash[arg_names.zip(args)]))
        end
      end
    }

    @env["env"] = @env
  end

  def repl
    loop do
      print "lisp.rb> "

      input = gets.chomp
      next if input.empty?
      break if input == " "

      begin
        out = evaluate(parse(input))
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
      else
        t
      end
    end
  end

  def parse(input)
    tokens = lex(input)
    if tokens.size == 1
      tokens.shift
    else
      parse_sexp(tokens)
    end
  end

  def evaluate(sexp, env=@env)
    if sexp.is_a?(Array)
      case sexp[0]
      when "quote"
        evaluate("quote").call(*sexp[1..-1])
      when "def"
        evaluate("def").call(sexp[1], *sexp[2..-1].map do |o|
          evaluate(o, env)
        end)
      when "let"
        evaluate("let").call(sexp[1], *sexp[2..-1])
      when "fn"
        evaluate("fn").call(sexp[1], *sexp[2..-1])
      else
        evaluate(sexp[0]).call(*sexp[1..-1].map { |o| evaluate(o, env) })
      end
    elsif sexp.is_a?(String)
      env[sexp]
    else
      sexp
    end
  end

  private

  def parse_sexp(tokens)
    expect("(", tokens)

    sexp = Sexp.new
    until tokens[0] == ")"
      t = tokens.shift
      not_nil(t)
      sexp << if t == "("
        tokens.unshift(t)
        parse_sexp(tokens)
      else
        t
      end
    end

    expect(")", tokens)

    sexp
  end

  def expect(type, tokens)
    t = tokens.shift
    raise "Expecting #{type}, got #{t}" unless t == type
    t
  end

  def not_nil(t)
    raise "Expecting more input but reached end" if t.nil?
  end
end

Lisp.new.repl
