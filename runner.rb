require 'rubygems'
require "bundler/setup"

require File.expand_path('lib/jabber_camp')

JabberCamp.campfire_subdomain = 'strobe'

JabberCamp::User.register 'peterw@strobecorp.com', 'CAMPFIRE_TOKEN'

EventMachine.run do
  JabberCamp::Proxy.run('jabber@strobecorp.com', 'PASSWORD', 'talk.google.com')
end
