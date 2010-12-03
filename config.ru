require 'rubygems'
require "bundler/setup"

require File.expand_path('lib/jabber_camp')

module JabberCamp
  class Rack
    JabberCamp.run('heroku-config.yml')
  end
end

JabberCamp.new
