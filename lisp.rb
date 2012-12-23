require 'pp'

class Lisp
  class Sexp < Array
    def inspect
      "(#{join(" ")})"
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
    }
  end

  def repl
    loop do
      print "lisp.rb> "

      input = gets.chomp
      next if input.empty?
      break if input == " "

      begin
        print "=> "
        pp evaluate(parse(input))
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

  def evaluate(sexp)
    if sexp.is_a?(Array)
      case sexp[0]
      when "quote"
        @env[sexp[0]].call(*sexp[1..-1])
      when "def"
        @env[sexp[0]].call(sexp[1], *sexp[2..-1].map do |o|
          evaluate(o)
        end)
      else
        @env[sexp[0]].call(*sexp[1..-1].map { |o| evaluate(o) })
      end
    elsif sexp.is_a?(String)
      if sexp == "env"
        @env
      else
        @env[sexp]
      end
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
