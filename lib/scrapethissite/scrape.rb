module ScrapeThisSite
  class Scrape
    attr_reader :url, :title, :html, :data, :mime, :name

    def initialize(args={})
      @url   = args[:url]
      @title = args[:title]
      @html  = args[:html] || ''
      @data  = args[:data]
      @mime  = args[:mime]
      @name  = args[:name]
    end
  end
end
