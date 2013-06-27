#!/usr/bin/ruby -Ilib -w
require 'rubygems'
require 'mechanize'
require 'scrapethissite'
require 'yaml'

if ARGV.length > 1
  STDERR.puts "usage: #{$0} [sts.yaml]"
  exit 1
end

filename = ARGV[0] || 'sts.yaml'
config = YAML.load_file(filename)

destinations = []
config['destinations'].each { |c|
  case c['type']
    when 'Evernote'
      destinations << ScrapeThisSite::Evernote::new(c['token'], c['host'])
    else
      puts "unsupported destination: #{c['type']}"
  end
}

config['accounts'].each { |c|
  mech = Mechanize.new { |agent|
    agent.user_agent_alias = 'Linux Mozilla'
  }

  args = c['args'] || {}
  case c['type']
    when 'ThriftSavingsPlan'
      @account = ScrapeThisSite::ThriftSavingsPlan.new(mech, args)
    else
      puts "unsupported account: #{c['type']}"
      next
  end

  history = c['history'] || []
  (@account.statements - history).each { |stmt|
    puts stmt
    destinations.each { |destination|
      destination.save( @account.statement(stmt) )
    }

    history << stmt
    c['history'] = history

    File.open(".#{filename}", 'w') { |file|
      file.write( config.to_yaml )
    }
    File.rename(".#{filename}", filename)
  }
}

