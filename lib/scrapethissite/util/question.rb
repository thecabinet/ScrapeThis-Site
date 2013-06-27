module ScrapeThisSite
module Util

  class Question
    attr_reader :key, :prompt

    def initialize(key, prompt, sensitive=false)
      @key = key
      @prompt = prompt
      @sensitive = sensitive
    end

    def sensitive?
      return @sensitive
    end
  end

end
end
