#!/usr/bin/ruby -Ilib
require 'base64'
require 'optparse'
require 'yaml'

require 'rubygems'
require 'highline/import'
require 'mechanize'
require 'scrapethissite'

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
    options.merge! YAML.load(File.read(filename))
    begin
      password = options[:password] ||
                 ask("Enter your ScrapeThis|Site password: ") { |q|
                   q.echo = '*'
                 }
      begin
        options[:password] = password
        decrypt(options)
      rescue OpenSSL::Cipher::CipherError => e
        puts "  Wrong password!"
        options[:password] = nil
      end
    end while options[:password].nil?
  end
end

def make_key(options)
  pbkdf2 = options[:encryption][:pbkdf2]
  if pbkdf2[:digest] == 'SHA1'
    return OpenSSL::PKCS5.pbkdf2_hmac_sha1(
               options[:password],
               Base64.decode64(pbkdf2[:salt]),
               pbkdf2[:iter],
               options[:encryption][:alg].split(/-/)[1].to_i
             )
  else
    return OpenSSL::PKCS5.pbkdf2_hmac(
               options[:password],
               Base64.decode64(pbkdf2[:salt]),
               pbkdf2[:iter],
               options[:encryption][:alg].split(/-/)[1].to_i,
               pbkdf2[:digest]
             )
  end
end

def encrypt(options)
  encrypter = OpenSSL::Cipher.new options[:encryption][:alg]
  encrypter.encrypt
  encrypter.key = make_key options
  encrypter.random_iv

  output = {
    :encryption => {
      :alg => options[:encryption][:alg],
      :iv => nil,
      :pbkdf2 => {
        :salt => options[:encryption][:pbkdf2][:salt],
        :iter => options[:encryption][:pbkdf2][:iter],
        :digest => options[:encryption][:pbkdf2][:digest]
      }
    },
    :encrypted => nil
  }

  encrypter = OpenSSL::Cipher.new options[:encryption][:alg]
  encrypter.encrypt
  encrypter.key = make_key options
  output[:encryption][:iv] = Base64.encode64 encrypter.random_iv

  output[:encrypted] = Base64.encode64(
      encrypter.update(options[:decrypted].to_yaml) + encrypter.final
    )

  filename = options[:filename]
  File.open(".#{filename}", 'w') { |file|
    file.write output.to_yaml
  }
  File.rename(".#{filename}", filename)
end

def decrypt(options)
  decrypter = OpenSSL::Cipher.new options[:encryption][:alg]
  decrypter.decrypt
  decrypter.key = make_key options
  decrypter.iv = Base64.decode64 options[:encryption][:iv]

  options[:decrypted] = YAML.load(
      decrypter.update(
        Base64.decode64(options[:encrypted])
      ) + decrypter.final
    )
end

def list(options)
  filename = options[:filename]

  if File.size?(filename).nil?
    STDERR.puts("you need to --add some sites first!")
    exit 1
  end

  get_password(options)
  decrypt(options)

  pp(options[:decrypted])

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

  get_password(options)

  filename = options[:filename]
  if File.size?(filename).nil?
    options[:decrypted] = {'sources' => [], 'sinks' => []}
  else
    options.merge! YAML.load(File.read(filename))
    decrypt(options)
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

  options[:decrypted]['sources'] << service if clazz.source?
  options[:decrypted]['sinks']   << service if clazz.sink?

  encrypt(options)

  exit 0
end

def run(options)
  filename = options[:filename]
  if File.size?(filename).nil?
    STDERR.puts("you need to --add some sites first!")
    exit 1
  end

  get_password(options)
  decrypt(options)

  sinks = []
  options[:decrypted]['sinks'].each { |c|
    clazz = c['class'].sub(/.*:/, '')
    begin
      sinks << ScrapeThisSite::Sinks.const_get(clazz).new(c['settings'])
    rescue NameError => e
      puts "unsupported sink: #{clazz}"
      puts e.inspect
    end
  }

  options[:decrypted]['sources'].each { |c|
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

      encrypt(options)
    }
  }
end

options = {
  :filename => 'sts.cf',
  :encryption => {
    :alg => 'AES-256-CBC',
    :iv => nil,
    :pbkdf2 => {
      :salt => Base64.encode64(Random.new.bytes(8)),
      :iter => 5000,
      :digest => 'SHA1'
    }
  }
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

