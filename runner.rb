require 'rubygems'
require "bundler/setup"

require File.expand_path('lib/jabber_camp')

JabberCamp.run('config.yml')
