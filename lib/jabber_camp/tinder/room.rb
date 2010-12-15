require 'json'

module JabberCamp
  module Tinder
    module RoomExtensions
      def listen_without_run(options = {})
        raise ArgumentError, "no block provided" unless block_given?

        join # you have to be in the room to listen

        require 'twitter/json_stream'

        auth = connection.basic_auth_settings
        options = {
          :host => "streaming.#{::Tinder::Connection::HOST}",
          :path => room_url_for(:live),
          :auth => "#{auth[:username]}:#{auth[:password]}",
          :timeout => 6,
          :ssl => connection.options[:ssl]
        }.merge(options)

        @stream = ::Twitter::JSONStream.connect(options)

        @stream.on_error do |e|
          JabberCamp.logger.error "Campfire Listening Error: #{e} - #{@stream.inspect}"
          @error_handler.call(e) if @error_handler
        end

        @stream.each_item do |message|
          JabberCamp.logger.debug "Incoming Campfire Message: #{message}"
          message = HashWithIndifferentAccess.new(::JSON.parse(message))
          message[:user] = user(message.delete(:user_id))
          message[:created_at] = Time.parse(message[:created_at])
          yield(message)
        end
      end

    end

    def on_error(&block)
      @error_handler = block
    end

  end
end

Tinder::Room.send :include, JabberCamp::Tinder::RoomExtensions
