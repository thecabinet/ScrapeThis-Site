#!/usr/bin/ruby -Ilib -w
require 'rubygems'
require 'mechanize'
require 'scrapethissite'

unless ARGV.length == 2
  STDERR.puts "usage: #{$0} <TSP username> <TSP password>"
  exit 1
end

mech = Mechanize.new { |agent|
  agent.user_agent_alias = 'Linux Mozilla'
}

tsp = ScrapeThisSite::ThriftSavingsPlan.new(
          mech,
          {
            'username' => ARGV[0],
            'password' => ARGV[1]
          }
        )

tsp.statements.each { |stmt|
  puts stmt

  scrape = tsp.statement(stmt)

  File.open(scrape.name, 'wb') { |file|
    file.syswrite(scrape.attachment)
  }
}

