require 'blather/client/client'
require 'tinder'

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
end

