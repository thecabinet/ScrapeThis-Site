module ScrapeThisSite

  module Sources
    def self.all
      sources = {}
      constants.select { |sym|
        const_get(sym).is_a?(Class)
      }.each { |sym|
        source = const_get(sym)
        sources[source.friendly_name] = source
      }
      return sources
    end
  end

  class Source
    def self.source?
      true
    end

    def self.sink?
      false
    end

    def self.friendly_name
      return name.sub(/^.*:/, '')
    end
  end

end
