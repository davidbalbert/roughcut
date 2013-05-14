class Roughcut
  module Helpers
    def q(name)
      Id.intern(name)
    end

    def s(*args)
      Roughcut::List.build(*args)
    end

    def list?(o)
      o.is_a?(List) || o.is_a?(EmptyList)
    end
  end
end
