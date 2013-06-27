#!/usr/bin/ruby -Ilib -w
require 'rubygems'
require 'mechanize'
require 'scrapethissite'

unless ARGV.length == 3
  STDERR.puts "usage: #{$0} <TSP username> <TSP password> <Evernote Developer Token>"
  STDERR.puts
  STDERR.puts "Evernote Developer Tokens are available with no human interaction from:"
  STDERR.puts "  https://sandbox.evernote.com/api/DeveloperToken.action"
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

evernote = ScrapeThisSite::Evernote.new(ARGV[2])


tsp.statements.each { |stmt|
  puts stmt
  evernote.save( tsp.statement(stmt) )
}

