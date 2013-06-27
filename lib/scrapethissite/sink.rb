module ScrapeThisSite

  module Sinks
    def self.all
      sinks = {}
      constants.select { |sym|
        const_get(sym).is_a?(Class)
      }.each { |sym|
        sink = const_get(sym)
        sinks[sink.friendly_name] = sink
      }
      return sinks
    end
  end

  class Sink
    def self.source?
      false
    end

    def self.sink?
      true
    end

    def self.friendly_name
      return name.sub(/^.*:/, '')
    end
  end

end
