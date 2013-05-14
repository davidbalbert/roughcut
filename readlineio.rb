require 'readline'

module Roughcut
  class ReadlineIO
    def initialize(prompt, secondary_prompt = "")
      @primary_prompt = prompt
      @secondary_prompt = secondary_prompt

      @prompt = @primary_prompt

      @buffer = ""

      @lines_read = []
    end

    def getc
      if @buffer.size > 0
        c = @buffer[0]
        @buffer = @buffer[1..-1]

        c
      else
        line = Readline.readline(@prompt)
        @prompt = @secondary_prompt

        if line.nil?
          nil
        else
          @lines_read << line
          @buffer = @buffer + line
          getc
        end
      end
    end

    def ungetc(ch)
      @buffer.unshift(ch)
    end

    def reset_prompt!
      @prompt = @primary_prompt
    end
  end
end
