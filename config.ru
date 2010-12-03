require 'rubygems'
require "bundler/setup"

require File.expand_path('lib/jabber_camp')

module JabberCamp
  class Rack
    def call(env)
      if env['REQUEST_URI'] == '/start'
        JabberCamp.run('heroku-config.yml')
        [200, {'Content-Type' => 'text/html'}, 'Starting...']
      else
        [200, {'Content-Type' => 'text/html'}, 'Nothing to see here']
      end
    end
  end
end

JabberCamp.new
