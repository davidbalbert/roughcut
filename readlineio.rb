require 'readline'

class Roughcut
  class ReadlineIO
    def initialize(prompt, secondary_prompt = "", history_file = nil)
      @primary_prompt = prompt
      @secondary_prompt = secondary_prompt
      @history_file = history_file

      @prompt = @primary_prompt

      @buffer = ""

      @old_history = Readline::HISTORY.to_a
      clear_history!

      if @history_file
        if File.exists?(@history_file)
          history = File.read(@history_file).split("\n")
          load_history(history)
        end
      end
    end

    def getc
      if @buffer.size > 0
        ch = @buffer[0]
        @buffer = @buffer[1..-1]

        ch
      else
        line = Readline.readline(@prompt)
        @prompt = @secondary_prompt

        if should_append_to_history?(line)
          Readline::HISTORY << line
        end

        if line.nil?
          nil
        else
          @buffer = @buffer + line + "\n"
          getc
        end
      end
    end

    def ungetc(ch)
      @buffer = ch + @buffer

      nil
    end

    def reset_prompt!
      @prompt = @primary_prompt
    end

    def clear_and_save_history!
      if @history_file
        File.open(@history_file, "w") do |f|
          f.write(Readline::HISTORY.to_a.join("\n") + "\n")
        end
      end

      clear_history!
      load_history(@old_history)
    end

    private
    def clear_history!
      Readline::HISTORY.shift until Readline::HISTORY.empty?
    end

    def load_history(history)
      history.each do |line|
        Readline::HISTORY << line
      end
    end

    def should_append_to_history?(line)
      line &&
        line != "" &&
        (Readline::HISTORY.size == 0 ||
         Readline::HISTORY[-1] != line)
    end
  end
end
