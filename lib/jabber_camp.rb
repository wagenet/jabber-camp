require 'blather/client/client'
require 'tinder'
require 'logger'
require 'yaml'
require 'erb'

require File.expand_path(File.dirname(__FILE__)+'/jabber_camp/user')
require File.expand_path(File.dirname(__FILE__)+'/jabber_camp/tinder/room')
require File.expand_path(File.dirname(__FILE__)+'/jabber_camp/proxy')

module JabberCamp
  @@campfire_subdomain = nil

  def self.campfire_subdomain=(val)
    @@campfire_subdomain = val
  end

  def self.campfire_subdomain
    @@campfire_subdomain
  end


  @@logger = Logger.new(STDOUT)
  @@logger.level = Logger::INFO

  def self.logger=(val)
    @@logger = val
  end

  def self.logger
    @@logger
  end


  def self.run(config_file)

    config = YAML.load(ERB.new(File.read(config_file)).result)

    if config['log']
      log_target = nil
      if config['log']['file']
        log_target = config['log']['file']
      elsif config['log']['stream']
        log_target = case config['log']['stream'].downcase
          when 'stdout' then STDOUT
          when 'stderr' then STDERR
          else               nil
        end
      end

      if log_target
        age = config['log']['age']
        size = config['log']['size']
        age = age.to_i if size
        JabberCamp.logger = Logger.new(log_target, age, size)
      end

      if config['log']['level']
        log_level = Logger.const_get(config['log']['level'].upcase) rescue nil
        JabberCamp.logger.level = log_level if log_level
      end
    end

    JabberCamp.logger.debug config.inspect

    JabberCamp.campfire_subdomain = config['campfire_subdomain']

    for user in config['users']
      JabberCamp::User.register user['jid'], user['campfire_token']
    end

    EM.error_handler do |e|
      JabberCamp.logger.error "Error raised during event loop: #{e.message}"
    end

    EventMachine.run do
      jid = config['jabber_user']['jid']
      pass = config['jabber_user']['password']
      server = config['jabber_user']['server']
      port = config['jabber_user']['port']

      args = [jid, pass]

      if server
        args << server
        if port
          args << port
        end
      end

      JabberCamp::Proxy.run(*args)
    end

  end


end

