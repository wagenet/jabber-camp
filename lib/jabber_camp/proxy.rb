module JabberCamp
  class Proxy

    attr_reader :jabber_client
    attr_reader :state


    def self.run(*args)
      jc = self.new(*args)
      jc.run
      jc
    end

    def run
      @jabber_client.run
    end

    def initialize(*args)
      setup_jabber(*args)
    end

    private

      def setup_jabber(*args)
        @jabber_client = Blather::Client.setup(*args)

        @jabber_client.register_handler(:ready){ handle_ready }
        @jabber_client.register_handler(:disconnected) { handle_disconnect }

        @jabber_client.register_handler(:subscription, :request?){|s| handle_subscription(s) }
        @jabber_client.register_handler(:message, :chat?, :body){|m| handle_chat(m) }
        @jabber_client.register_handler(:presence){|p| handle_presence(p) }
      end


      def handle_ready
        @state = :ready
        JabberCamp.logger.info "Jabber Connected. Send messages to #{@jabber_client.jid.inspect}"
      end

      def handle_disconnect
        if @state == :ready
          JabberCamp.logger.info "Disconnected from Jabber. Reconnecting..."
          @state = :reconnecting
          @jabber_client.connect
        else
          JabberCamp.logger.error "Unable to connect."
          EM.stop if EM.reactor_running?
          @state = :disconnected
        end
      end

      def handle_subscription(s)
        # Auto approve
        jid = s.from.to_s.split('/').first
        user = JabberCamp::User.find(jid)
        if user
          @jabber_client.write s.approve!
        else
          @jabber_client.write s.deny!
        end
      end

      def handle_chat(m)
        jid = m.from.to_s.split('/').first
        user = JabberCamp::User.find(jid)
        if user
          # Pass to Campfire
          user.connect unless user.connected?
          user.campfire_room.speak m.body
        else
          @jabber_client.write Blather::Stanza::Message.new(jid, "Access Denied")
        end
      end

      def handle_presence(p)
        jid = p.from.to_s.split('/').first
        user = JabberCamp::User.find(jid)
        if (user)
          if !p.type
            # Available
            JabberCamp.logger.info "#{jid} connected"
            user.connect
            campfire_listen(user) unless JabberCamp::User.listener
          elsif p.unavailable?
            # Unavailable
            JabberCamp.logger.info "#{jid} disconnected"
            user.disconnect
          end
        end
      end

      def campfire_listen(listen_user)
        JabberCamp.logger.debug "campfire_listen: #{listen_user.jabber_user}"

        listen_user.listen{|msg| process_msg(msg) }

        listen_user.after_stop_listening do |user|
          JabberCamp.logger.debug "after_stop_listening: #{user.jabber_user}"

          listen_user.clear_after_stop_listening

          new_user = JabberCamp::User.connected.first
          campfire_listen(new_user) if new_user
        end
      end

      def process_message(msg)
        for user in JabberCamp::User.users
          text = nil

          case msg['type']
          when 'TextMessage'
            if msg['user']['email_address'] != user.campfire_user['email_address']
              text = msg['user']['name']+': '+msg['body']
            end
          when 'EnterMessage'
            text = "**#{msg['user']['name']} entered the room**"
          when 'KickMessage'
            text = "**#{msg['user']['name']} left the room**"
          when 'TimestampMessage'
            # Ignore
          else
            JabberCamp.logger.debug "Unknown Message Type: #{msg.inspect}"
          end

          if text
            JabberCamp.logger.debug "Sending: \"#{text}\" to #{user.jabber_user}"
            @jabber_client.write Blather::Stanza::Message.new(user.jabber_user, text)
          end
        end
      end

  end
end
