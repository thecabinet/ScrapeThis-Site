#!/usr/bin/ruby -Ilib
require 'rubygems'
require 'highline/import'
require 'mechanize'
require 'optparse'
require 'scrapethissite'
require 'yaml'

SALT = 'ScpTh|St'

def get_password(options)
  password = options[:password] || nil
  filename = options[:filename]

  if File.size?(filename).nil?
    password1 = password || '1'
    password2 = password || '2'
    while password1 != password2
      password1 = ask("Choose a password for ScrapeThis|Site: ") { |q| q.echo = '*' }
      password2 = ask("Confirm your ScrapeThis|Site password: ") { |q| q.echo = '*' }
    end
    password = password1
  else
    begin
      password = options[:password] ||
                 ask("Enter your ScrapeThis|Site password: ") { |q|
                   q.echo = '*'
                 }
      begin
        decrypter = make_decrypter password
        yaml = decrypter.update File.read(filename)
        yaml << decrypter.final
        config = YAML.load(yaml)
      rescue OpenSSL::Cipher::CipherError => e
        puts "  Wrong password!"
        options[:password] = nil
      end
    end while options[:password].nil?
  end

  return options[:password] = password
end

def make_encrypter(password)
  encrypter = OpenSSL::Cipher::Cipher.new 'AES-128-CBC'
  encrypter.encrypt
  encrypter.pkcs5_keyivgen password, SALT

  return encrypter
end

def make_decrypter(password)
  decrypter = OpenSSL::Cipher::Cipher.new 'AES-128-CBC'
  decrypter.decrypt
  decrypter.pkcs5_keyivgen password, SALT

  return decrypter
end

def list(options)
  filename = options[:filename]

  if File.size?(filename).nil?
    STDERR.puts("you need to --add some sites first!")
    exit 1
  end

  password = get_password(options)
  decrypter = make_decrypter(password)

  yaml = decrypter.update File.read(options[:filename])
  yaml << decrypter.final
  config = YAML.load(yaml)

  pp(config)

  exit 0
end

def die_add(name, sources, sinks)
  if name.is_a?(String)
    STDERR.puts "Unknown source or sink: #{name}"
    STDERR.puts
  end

  STDERR.puts 'ScrapeThis|Site supports the following sources:'
  sources.keys.sort.each { |key|
    STDERR.puts " * #{key} - #{sources[key].url}"
  }
  STDERR.puts
  STDERR.puts 'ScrapeThis|Site supports the following sinks:'
  sinks.keys.sort.each { |key|
    STDERR.puts " * #{key} - #{sinks[key].url}"
  }
  STDERR.puts

  exit 1
end

def add(options)
  name = options[:add]

  sources = ScrapeThisSite::Sources.all
  sinks   = ScrapeThisSite::Sinks.all
  clazz = sources[name] || sinks[name]
  die_add(name, sources, sinks) if clazz.nil?

  password = get_password(options)
  decrypter = make_decrypter(password)

  filename = options[:filename]
  config = if File.size?(filename).nil?
             {'sources' => [], 'sinks' => []}
           else
             yaml = decrypter.update File.read(filename)
             yaml << decrypter.final
             YAML.load(yaml)
           end

  settings = {}
  service = {
    'class' => clazz.name,
    'settings' => settings
  }

  puts "Please answer the following questions to configure access to #{name}:"
  clazz.questions.each { |question|
    answer = ask("  #{question.prompt} ") { |q|
      q.echo = '*' if question.sensitive?
    }
    settings[question.key] = answer
  }

  # FIXME Test credentials before saving them

  config['sources'] << service if clazz.source?
  config['sinks']   << service if clazz.sink?

  encrypter = make_encrypter(password)
  File.open(".#{filename}", 'w') { |file|
    file.write(encrypter.update(config.to_yaml))
    file.write(encrypter.final)
  }
  File.rename(".#{filename}", filename)

  exit 0
end

def run(options)
  filename = options[:filename]
  if File.size?(filename).nil?
    STDERR.puts("you need to --add some sites first!")
    exit 1
  end

  password = get_password(options)
  decrypter = make_decrypter(password)
  yaml = decrypter.update File.read(filename)
  yaml << decrypter.final
  config = YAML.load(yaml)

  sinks = []
  config['sinks'].each { |c|
    clazz = c['class'].sub(/.*:/, '')
    begin
      sinks << ScrapeThisSite::Sinks.const_get(clazz).new(c['settings'])
    rescue NameError => e
      puts "unsupported sink: #{clazz}"
      puts e.inspect
    end
  }

  encrypter = make_encrypter(password)
  config['sources'].each { |c|
    mech = Mechanize.new { |agent|
      agent.user_agent_alias = 'Linux Mozilla'
    }

    clazz = c['class'].sub(/.*:/, '')
    source = nil
    begin
      source = ScrapeThisSite::Sources.const_get(clazz).new(mech, c['settings'])
    rescue NameError => e
      puts "unsupported source: #{clazz}"
      puts e.inspect
      next
    end

    history = c['history'] || []
    (source.statements - history).each { |stmt|
      puts stmt
      sinks.each { |sink|
        sink.save( source.statement(stmt) )
      }

      history << stmt
      c['history'] = history

      encrypter.reset
      File.open(".#{filename}", 'w') { |file|
        file.write(encrypter.update(config.to_yaml))
        file.write(encrypter.final)
      }
      File.rename(".#{filename}", filename)
    }
  }
end

options = {
  :filename => 'sts.cf'
}
opts = OptionParser.new { |opts|
  opts.banner = "usage: #{$0} [options]"

  opts.separator ''
  opts.separator 'Modes:'

  opts.on('-r', '--run', 'runs ScrapeThis|Site') {
    options[:run] = true
  }

  opts.on('-l', '--list', 'prints the current configuration') {
    options[:list] = true
  }

  opts.on('-a', '--add [WEBSITE]', 'adds a new source or sink') { |s|
    options[:add] = s
  }

  opts.separator ''
  opts.separator 'Shared options:'

  opts.on('-h', '--help', 'prints this usage statement') {
    puts opts
    exit 0
  }

  opts.on('-f', '--filename', "specifies the config file to use,", "defaults to #{options[:filename]}") { |filename|
    options[:filename] = filename
  }

  opts.on('-p', '--password PASSWORD', "your ScrapeThis|Site password") { |password|
    options[:password] = password
  }
}
opts.parse!

if options[:list]
  list(options)
elsif options.has_key?(:add)
  add(options)
elsif options[:run]
  run(options)
end

STDERR.puts opts.help
exit 1

