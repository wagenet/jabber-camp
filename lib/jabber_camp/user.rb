module JabberCamp
  class User

    @@users = []

    attr_reader :jabber_user
    attr_reader :campfire_token
    attr_reader :campfire_connection
    attr_reader :campfire_room
    attr_reader :campfire_user

    class << self

      def register(*args)
        user = self.new(*args)
        @@users << user
        user
      end

      def users
        @@users
      end

      def connected
        users.select{|u| u.connected? }
      end

      def listener
        users.find{|u| u.listening? }
      end

      def find(jid)
        users.find{|u| u.jabber_user == jid }
      end

    end

    def initialize(jabber_user, campfire_token)
      @jabber_user = jabber_user
      @campfire_token = campfire_token
      @connected = false;
    end

    def connected?
      !!@connected
    end

    def listening?
      campfire_room && campfire_room.listening?
    end

    def connect
      return if connected?

      @campfire_connection = ::Tinder::Campfire.new(JabberCamp.campfire_subdomain, :token => campfire_token)

      @campfire_room = @campfire_connection.rooms.first
      @campfire_room.join

      @campfire_user = @campfire_connection.me

      @connected = true
    end

    def disconnect
      return unless connected?

      @connected = false

      stop_listening

      @campfire_connection = nil

      @campfire_room.leave
      @campfire_room = nil

      @campfire_user = nil
    end

    def listen(&block)
      raise unless connected?
      return if listening?
      campfire_room.listen_without_run(&block)
    end

    def stop_listening
      JabberCamp.logger.debug "stop_listening: #{listening?}"

      return unless listening?

      campfire_room.stop_listening

      if @after_stop_listening
        @after_stop_listening.call(self)
      end
    end

    def after_stop_listening(&block)
      @after_stop_listening = block
    end

    def clear_after_stop_listening
      @after_stop_listening = nil
    end

  end
end
