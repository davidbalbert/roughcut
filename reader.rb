require 'stringio'
require 'singleton'

require './helpers'

class Roughcut
  class ReadError < StandardError; end

  class EOF; end

  class Reader
    include Helpers

    MACROS = {
      "(" => lambda { |reader| reader.send(:read_list) },
      "\"" => lambda { |reader| reader.send(:read_string) },
      ":" => lambda { |reader| reader.send(:read_symbol) },
      "'" => lambda { |reader| reader.send(:read_quote) },
      "`" => lambda { |reader| reader.send(:read_quasiquote) },
      "~" => lambda { |reader| reader.send(:read_unquote) },
      ";" => lambda { |reader| reader.send(:read_comment) },
      "/" => lambda { |reader| reader.send(:read_regexp) },
      "%" => lambda { |reader| reader.send(:read_percent_regexp) }
    }

    FLOAT_REGEXP = /\A[+-]?([0-9]|[1-9][0-9]*)(\.[0-9]+)([eE][+-]?[0-9]+)?\z/
    INT_REGEXP = /\A[+-]?([0-9]|[1-9][0-9]*)\z/

    def initialize(input)
      if input.is_a?(String)
        @io = StringIO.new(input)
      else
        @io = input
      end
    end

    def read_all
      results = []

      loop do
        out = read(false)
        break if out == EOF
        results << out
      end

      results
    end

    def read(should_raise_on_eof=true)
      @continue_parsing = false

      loop do
        ch = @io.getc

        while is_whitespace?(ch)
          ch = @io.getc
        end

        if ch.nil?
          if should_raise_on_eof
            raise ReadError, "Reader reached EOF" if ch.nil?
          else
            return EOF
          end
        end

        if ch == "."
          ch2 = @io.getc

          if is_whitespace?(ch2) || ch2.nil?
            raise ReadError, "Unexpected '.' outside dotted pair"
          end

          @io.ungetc(ch2)
        end

        if "0123456789".include?(ch)
          @io.ungetc(ch)
          return read_number
        end

        if "+-".include?(ch)
          ch2 = @io.getc

          if "0123456789".include?(ch2)
            @io.ungetc(ch2)
            @io.ungetc(ch)
            return read_number
          end

          @io.ungetc(ch2)
        end

        if MACROS.has_key?(ch)
          ret = MACROS[ch].call(self)

          if ret == @io
            next
          elsif @continue_parsing == true
            @continue_parsing = false
          else
            return ret
          end
        end

        @io.ungetc(ch)
        return parse_token(read_token)
      end
    end

    private
    def read_list
      @continue_parsing = false

      vals = []

      loop do
        ch = @io.getc

        while is_whitespace?(ch)
          ch = @io.getc
        end

        raise ReadError, "Reader reached EOF, expecting ')'" if ch.nil?

        if ch == "."
          ch2 = @io.getc

          if is_whitespace?(ch2)
            # read a dotted pair
            @io.ungetc(ch2)

            tail = read

            ch2 = @io.getc
            while is_whitespace?(ch2)
              ch2 = @io.getc
            end

            raise ReadError, "Reader reached EOF, expecting ')'" if ch2.nil?
            raise ReadError, "More than one object follows '.' in list" unless ch2 == ")"

            return vals.reverse.reduce(tail) do |rest, v|
              List.new(v, rest)
            end
          elsif ch2.nil?
            raise ReadError, "Reader reached EOF"
          else
            @io.ungetc(ch2)
          end
        end

        break if ch == ")"

        if "0123456789".include?(ch)
          @io.ungetc(ch)
          vals << read_number
          next
        end

        if "+-".include?(ch)
          ch2 = @io.getc

          if "0123456789".include?(ch2)
            @io.ungetc(ch2)
            @io.ungetc(ch)
            vals << read_number
            next
          end

          @io.ungetc(ch2)
        end


        if MACROS.has_key?(ch)
          ret = MACROS[ch].call(self)

          if ret == @io
            next
          elsif @continue_parsing == true
            @continue_parsing = false
          else
            vals << ret
            next
          end
        end

        @io.ungetc(ch)
        vals << parse_token(read_token)
      end

      List.build(*vals)
    end

    def read_string
      s = ""

      loop do
        ch = @io.getc

        raise ReadError, "Reader reached EOF, expecting '\"'" if ch.nil?

        break if ch == "\""

        s << ch
      end

      s
    end

    def read_number
      s = ""

      loop do
        ch = @io.getc

        break if ch.nil?

        if is_whitespace?(ch) || is_delimeter?(ch)
          @io.ungetc(ch)
          break
        end

        s << ch
      end

      case s
      when FLOAT_REGEXP
        s.to_f
      when INT_REGEXP
        s.to_i
      else
        raise ReadError, "`#{s}' is not a valid number"
      end
    end

    def read_symbol
      ch = @io.getc

      # we're looking for a second colon for a leading ::
      if ch == ":"
        @io.ungetc(":")

        @continue_parsing = true
        return nil
      end

      @io.ungetc(ch)
      read_token.intern
    end

    def read_quote
      List.build(Id.intern("quote"), read)
    end

    def read_quasiquote
      l = List.build(Id.intern("quasiquote"), read)

      if list?(l.rest.first) && l.rest.first.first == Id.intern("unquote-splicing")
        raise SyntaxError, "You cannot use unquote-splicing outside of a list"
      end

      l
    end

    def read_unquote
      ch = @io.getc
      if ch == "@"
        List.build(Id.intern("unquote-splicing"), read)
      else
        @io.ungetc(ch)
        List.build(Id.intern("unquote"), read)
      end
    end

    def read_comment
      loop do
        ch = @io.getc
        break if ch.nil? || ch == "\n"
      end

      @io
    end

    def read_regexp
      ch = @io.getc

      if is_whitespace?(ch)
        return Id.intern("/")
      end

      @io.ungetc(ch)
      body = ""

      loop do
        ch = @io.getc

        raise ReadError, "Reader reached EOF, expecting end of Regexp ('/')" if ch.nil?

        break if ch == "/"

        body << ch
      end

      option_chars = ""

      loop do
        ch = @io.getc

        if ch.nil? || is_whitespace?(ch) || is_delimeter?(ch)
          @io.ungetc(ch)
          break
        end

        option_chars << ch
      end

      build_regexp(body, option_chars)
    end

    def read_percent_regexp
      ch1 = @io.getc
      ch2 = @io.getc

      if ch1 != "r" || ch2 != "{"
        @io.ungetc(ch2)
        @io.ungetc(ch1)

        @continue_parsing = true

        return nil
      end

      body = ""

      loop do
        ch = @io.getc

        raise ReadError, "Reader reached EOF, expecting end of Regexp ('}')" if ch.nil?

        break if ch == "}"

        body << ch
      end

      option_chars = ""

      loop do
        ch = @io.getc

        if ch.nil? || is_whitespace?(ch) || is_delimeter?(ch)
          @io.ungetc(ch)
          break
        end

        option_chars << ch
      end

      build_regexp(body, option_chars)
    end

    def build_regexp(body, option_chars)
      options = 0
      bad_options = ""
      option_chars.each_char do |ch|
        case ch
        when "i"
          options |= Regexp::IGNORECASE
        when "x"
          options |= Regexp::EXTENDED
        when "m"
          options |= Regexp::MULTILINE
        else
          bad_options << ch
        end
      end

      unless bad_options.empty?
        raise ReadError, "unknown regexp options - #{bad_options}"
      end

      Regexp.new(body, options)
    end

    def read_token
      s = ""
      loop do
        ch = @io.getc

        break if ch.nil?

        if is_whitespace?(ch) || is_delimeter?(ch)
          @io.ungetc(ch)
          break
        end

        s << ch
      end

      s
    end

    def parse_token(token)
      case token
      when "nil"
        nil
      when "true"
        true
      when "false"
        false
      else
        Id.intern(token)
      end
    end

    def is_whitespace?(ch)
      !ch.nil? && " \t\r\n\f".include?(ch)
    end

    def is_delimeter?(ch)
      !ch.nil? && ")".include?(ch)
    end
  end

  class Id
    class << self
      private :new

      def intern(name)
        @symbol_table ||= {}

        @symbol_table[name] ||= new(name)
      end
    end

    def initialize(str)
      @str = str
    end

    def ==(other)
      if other.is_a?(Id)
        @str == other.str
      else
        false
      end
    end

    def eql?(other)
      if other.is_a?(Id)
        @str.eql?(other.str)
      else
        false
      end
    end

    def hash
      @str.hash
    end

    def to_s
      @str
    end

    def inspect
      "#<Roughcut::Id: #{to_s}>"
    end

    protected
    def str
      @str
    end
  end

  class EmptyList
    include Enumerable
    include Singleton

    def first
      nil
    end

    def rest
      self
    end

    def ==(other)
      other.is_a?(EmptyList)
    end

    def empty?
      true
    end

    def size
      0
    end

    def index
      nil
    end

    def concat(other)
      other
    end

    def each
      return to_enum unless block_given?

      self
    end

    def each_node
      return to_enum(:each_node) unless block_given?

      self
    end

    def to_a
      []
    end

    def to_s
      "()"
    end

    def inspect
      "#<Roughcut::EmptyList: ()>"
    end
  end

  class List
    include Enumerable
    include Helpers

    attr_accessor :first, :rest

    def self.build(*args)
      if args.empty?
        EmptyList.instance
      else
        List.new(args[0], build(*args[1..-1]))
      end
    end

    def initialize(first, rest=EmptyList.instance)
      @first = first
      @rest = rest
    end

    def ==(other)
      if other.is_a?(List)
        first == other.first && rest == other.rest
      else
        false
      end
    end

    def empty?
      false
    end

    def size
      inject(0) { |acc, o| acc + 1 }
    end

    alias index find_index

    def concat(other)
      # TODO: this could be more efficient we iterate across both lists, but all we really need to do is iterate across the first one
      List.build(*self, *other)
    end

    def each
      return to_enum unless block_given?

      each_node do |n|
        yield n.first
      end

      self
    end

    def each_node
      return to_enum(:each_node) unless block_given?

      l = self
      until l.is_a?(EmptyList)
        yield l

        # for dotted pairs
        break unless l.respond_to?(:rest)
        l = l.rest
      end

      self
    end

    def to_a
      map { |o| o }
    end

    def to_s
      elements = each_node.map do |n|
        if !n.respond_to?(:first)
          # dotted pairs
          ". #{n}"
        elsif n.first.nil?
          "nil"
        elsif list?(n.first) || n.first.is_a?(Id)
          n.first.to_s
        else
          n.first.inspect
        end
      end.join(" ")

      "(#{elements})"
    end

    def inspect
      "#<Roughcut::List: #{to_s}>"
    end
  end
end

if __FILE__ == $0
  require 'minitest/autorun'

  include Roughcut::Helpers

  class Roughcut
    class TestList < MiniTest::Unit::TestCase

      def test_empty_to_a
        assert_equal [], s().to_a
      end

      def test_to_a
        assert_equal [1, 2, 3], s(1, 2, 3).to_a
      end

      def test_concat
        assert_equal s(1), s().concat(s(1))
        assert_equal s(1), s(1).concat(s())
        assert_equal s(1, 2, 3), s(1, 2).concat(s(3))
      end
    end

    class TestReader < MiniTest::Unit::TestCase
      def test_nothing
        assert_raises(ReadError) { Reader.new("").read }
      end

      def test_whitespace
        assert_raises(ReadError) { Reader.new(" \t").read }
      end

      def test_nil
        assert_equal nil, Reader.new("nil").read
      end

      def test_true
        assert_equal true, Reader.new("true").read
      end

      def test_false
        assert_equal false, Reader.new("false").read
      end

      def test_sym
        assert_equal q("foo"), Reader.new("foo").read
      end

      def test_extra_chars
        assert_equal q("foo"), Reader.new("foo bar baz").read
      end

      def test_integer
        result = Reader.new("123").read
        assert_equal 123, result
        assert_kind_of Fixnum, result
      end

      def test_positive_integer
        result = Reader.new("+123").read
        assert_equal 123, result
        assert_kind_of Fixnum, result
      end

      def test_negative_integer
        result = Reader.new("-123").read
        assert_equal -123, result
        assert_kind_of Fixnum, result
      end

      def test_float
        assert_equal 3.14, Reader.new("3.14").read
      end

      def test_exponent
        assert_equal 1.23e5, Reader.new("1.23e5").read
      end

      def test_exponent_with_pos_and_neg
        assert_equal -1.23e+5, Reader.new("-1.23e+5").read
      end

      def test_sym_with_plus_and_minus
        assert_equal q("+z-+"), Reader.new("+z-+").read
      end

      def test_bad_number
        assert_raises(ReadError) { Reader.new("+3a2").read }
      end

      def test_string
        assert_equal "foo bar", Reader.new('"foo bar"').read
      end

      def test_incomplete_string
        assert_raises(ReadError) { Reader.new('"foo bar').read }
      end

      def test_ruby_symbol
        assert_equal :foo, Reader.new(":foo").read
      end

      def test_const_lookup_operator
        assert_equal q("Foo::Bar"), Reader.new("Foo::Bar").read
      end

      def test_absolute_const_lookup_operator
        assert_equal q("::Foo::Bar"), Reader.new("::Foo::Bar").read
      end

      def test_complicated_ruby_symbol
        assert_equal :"foo-bar", Reader.new(":foo-bar").read
      end

      def test_empty_list
        assert_equal s(), Reader.new("()").read
      end

      def test_list
        assert_equal s(q("foo"), q("bar"), q("baz")), Reader.new("(foo bar baz)").read
      end

      def test_list_with_nil_and_numbers
        assert_equal s(q("foo"), nil, 50, 2.34e5, q("bar")), Reader.new("(foo nil 50 2.34e5 bar)").read
      end

      def test_nested_list
        assert_equal s(q("foo"), s(q("bar"), q("baz"))), Reader.new("(foo (bar baz))").read
      end

      def test_quoted_sym
        assert_equal s(q("quote"), q("foo")), Reader.new("'foo").read
      end

      def test_quoteed_sym_with_quote
        assert_equal s(q("quote"), q("foo'bar")), Reader.new("'foo'bar").read
      end

      def test_quoted_number
        assert_equal s(q("quote"), 3.14), Reader.new("'3.14").read
      end

      def test_quoted_list
        assert_equal s(q("quote"), s(q("foo"), q("bar"))), Reader.new("'(foo bar)").read
      end

      def test_quasiquoted_sym
        assert_equal s(q("quasiquote"), q("foo")), Reader.new("`foo").read
      end

      def test_quasiquoted_list
        assert_equal s(q("quasiquote"), s(q("foo"))), Reader.new("`(foo)").read
      end

      def test_unquote_sym
        assert_equal s(q("unquote"), q("foo")), Reader.new("~foo").read
      end

      def test_unquote_list
        assert_equal s(q("unquote"), s(q("foo"))), Reader.new("~(foo)").read
      end

      def test_unquote_splicing_sym
        assert_equal s(q("unquote-splicing"), q("foo")), Reader.new("~@foo").read
      end

      def test_unquote_splicing_list
        assert_equal s(q("unquote-splicing"), s(q("foo"))), Reader.new("~@(foo)").read
      end

      def test_unquote_splicing_no_list
        assert_raises(SyntaxError) { Reader.new("`~@foo").read }
      end

      def test_comment
        assert_raises(ReadError) { Reader.new("; foo bar baz").read }
      end

      def test_expr_and_comment
        assert_equal s(q("+"), 1, 2), Reader.new("(+ 1 2) ; foo bar baz").read
      end

      def test_comment_inside_expr
        assert_equal s(q("+"), 1, 2), Reader.new("(+ 1 ; foo bar\n2)").read
      end

      def test_comment_inside_list_at_end
        assert_equal s(1, 2), Reader.new("(1 2 ;foo\n)").read
      end

      def test_slash_regexp
        assert_equal /foo/i, Reader.new("/foo/i").read
      end

      def test_only_percent
        assert_equal q("/"), Reader.new("/ foo/").read
      end

      def test_bad_regexp_options
        assert_raises(ReadError) { Reader.new("/foo/abcd").read }
      end

      def test_percent_regexp
        assert_equal %r{foo}i, Reader.new("%r{foo}i").read
      end

      def test_regexp_in_list
        assert_equal s(/foo/), Reader.new("(/foo/)").read
      end

      def test_regexp_with_option_in_list
        assert_equal s(/foo/i), Reader.new("(/foo/i)").read
      end

      def test_percent_regexp_in_list
        assert_equal s(/foo/), Reader.new("(%r{foo})").read
      end

      def test_percent_regexp_with_option_in_list
        assert_equal s(/foo/i), Reader.new("(%r{foo}i)").read
      end

      def test_percent_sym
        assert_equal q("%rufus"), Reader.new("%rufus").read
      end

      def test_percent
        assert_equal q("%"), Reader.new("%").read
      end

      def test_dotted_pair_to_s
        assert_equal "(1 2 . 3)", List.new(1, List.new(2, 3)).to_s
      end

      def test_read_dotted_pair
        assert_equal List.new(1, List.new(2, 3)), Reader.new("(1 2 . 3)").read
      end

      def test_bad_dotted_pair
        assert_raises(ReadError) { Reader.new("(1 2 . 3 4").read }
      end

      def test_unfinished_dotted_pair
        assert_raises(ReadError) { Reader.new("(1 .").read }
        assert_raises(ReadError) { Reader.new("(1 . ").read }
        assert_raises(ReadError) { Reader.new("(1 . 2").read }
      end

      def test_regular_list_dotted_pair
        assert_equal s(1, 2, 3), Reader.new("(1 . (2 . (3 . ())))").read
      end

      def test_sym_with_leading_dot
        assert_equal q(".foo"), Reader.new(".foo").read
      end

      def test_dot_alone
        assert_raises(ReadError) { Reader.new(" . ").read }
      end
    end
  end
end
