require 'fiber'

Token = Struct.new(:type, :value)

class Lexer
  class LexError < StandardError; end

  def initialize(input)
    @input = input
    @start = 0
    @pos = 0
    @done = false

    @lex_fiber = Fiber.new do
      lex_func = lex_start
      while lex_func
        lex_func = lex_func.call
      end
    end
  end

=begin
  def <<(more_input)
    @input = @input + more_input
  end
=end

  def done?
    @done
  end

  def next_token
    if @lex_fiber.alive?
      @lex_fiber.resume
    else
      nil
    end
  end

  private
  def lex_start
    lambda {
      case next_char
      when "("
        emit(:lparen)
        lex_start
      when ")"
        emit(:rparen)
        lex_start
      when "'"
        emit(:quote)
        lex_start
      when "`"
        emit(:quasiquote)
        lex_start
      when "~"
        lex_unquote
      when "\t", "\n", " ", "\r"
        ignore_whitespace
      when :eof
        @done = true
        emit(:eof)
      else
        backup
        raise LexError, "Unexpected input character: '#{@input[@pos]}'"
      end
    }
  end

  def lex_unquote
    lambda {
      if peek == "@"
        @pos += 1
        emit(:"unquote-splicing")
      else
        emit(:unquote)
      end

      lex_start
    }
  end

  def ignore_whitespace
    lambda {
      loop do
        c = peek
        break if c == :eof || !("\t\n\r ".include?(c))
        next_char
      end
      ignore

      lex_start
    }
  end

  def emit(type)
    Fiber.yield(Token.new(type, @input[@start...@pos]))
    @start = @pos
  end

  def ignore
    @start = @pos
  end

  def peek
    c = next_char
    backup

    c
  end

  def next_char
    if @pos >= @input.length
      c = :eof
    else
      c = @input[@pos]
    end
    @pos += 1

    c
  end

  def backup
    @pos -= 1
  end
end

require 'pp'

#lexer = Lexer.new(%{(foo bar-baz 5 -3.2 +4 .3 "foo" 'bar' nil nil-asdf (+ 1 2 3))})
lexer = Lexer.new("()'`~~@")
#lexer = Lexer.new(" \t(    \n\n) ")
until lexer.done?
  pp lexer.next_token
end
