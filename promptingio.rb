class Roughcut
  class PromptingIO
    def initialize(prompt, io = STDIN)
      @prompt = prompt
      @io = io
      @needs_prompt = true
    end

    def getc
      print @prompt if @needs_prompt
      @needs_prompt = false

      @io.getc
    end

    def ungetc(ch)
      @io.ungetc(ch)
    end

    def reset_prompt!
      @needs_prompt = true
    end
  end
end
