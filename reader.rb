require 'stringio'

class Roughcut
  class ReadError < StandardError; end

  class Reader
    MACROS = {
      "(" => lambda { |reader| reader.send(:read_list) }
    }

    def initialize(input)
      @io = StringIO.new(input)
    end

    def read
      loop do
        ch = @io.getc

        while is_whitespace?(ch)
          ch = @io.getc
        end

        raise ReadError, "Reader reached EOF" if ch.nil?

        if MACROS.has_key?(ch)
          return MACROS[ch].call(self)
        end

        @io.ungetc(ch)
        return read_sym
      end
    end

    private
    def read_list
      list = node = last_node = List.new(nil)

      loop do
        ch = @io.getc

        while is_whitespace?(ch)
          ch = @io.getc
        end

        raise ReadError, "Reader reached EOF" if ch.nil?

        if ch == ")"
          last_node.rest = nil
          break
        end

        @io.ungetc(ch)
        last_node = node
        node.first = read
        node = node.rest = List.new(nil)
      end

      list
    end

    def read_sym
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

      Sym.intern(s)
    end

    def is_whitespace?(ch)
      !ch.nil? && " \t\r\n\f".include?(ch)
    end

    def is_delimeter?(ch)
      !ch.nil? && ")".include?(ch)
    end
  end

  class Sym
    class << self
      alias intern new
    end

    def initialize(str)
      @str = str
    end

    def ==(other)
      if other.is_a?(Sym)
        @str == other.str
      else
        false
      end
    end

    def to_s
      @str
    end

    def inspect
      "#<Roughcut::Sym: #{to_s}>"
    end

    protected
    def str
      @str
    end
  end

  class List
    attr_accessor :first, :rest
    include Enumerable

    def self.build(*args)
      if args.empty?
        nil
      else
        List.new(args[0], build(*args[1..-1]))
      end
    end

    def initialize(first, rest=nil)
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

    def each
      unless block_given?
        to_enum
      else
        l = self
        until l.nil?
          yield l.first
          l = l.rest
        end
      end

      self
    end

    def to_s
      "(" + map { |el| el.to_s }.join(" ") + ")"
    end

    def inspect
      "#<Roughcut::List: #{to_s}>"
    end
  end
end

if __FILE__ == $0
  require 'minitest/autorun'

  def q(name)
    Roughcut::Sym.intern(name)
  end

  def s(*args)
    Roughcut::List.build(*args)
  end

  class Roughcut
    class TestReader < MiniTest::Unit::TestCase
      def test_read_nothing
        assert_raises(ReadError) { Reader.new("").read }
      end

      def test_read_whitespace
        assert_raises(ReadError) { Reader.new(" \t").read }
      end

      def test_read_sym
        assert_equal Sym.intern("foo"), Reader.new("foo").read
      end

      def test_read_extra_chars
        assert_equal Sym.intern("foo"), Reader.new("foo bar baz").read
      end

      def test_read_list
        out = Reader.new("(foo bar baz)").read
        assert_equal s(q("foo"), q("bar"), q("baz")), Reader.new("(foo bar baz)").read
      end
    end
  end
end
