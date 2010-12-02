require 'date'

module JabberCamp
  class Proxy

    @@campfire_id_map = {}

    attr_reader :jabber_client
    attr_reader :state


    class << self

      def run(*args)
        jc = self.new(*args)
        jc.run
        jc
      end

      def lookup_campfire_user(id, connection)
        unless @@campfire_id_map[id]
          begin
            @@campfire_id_map[id] = connection.get("/users/#{id}.json")["user"]
          rescue => e
            JabberCamp.logger.error("Unable to get user data for: #{id}")
          end
        end
        @@campfire_id_map[id]
      end

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
          user.connect unless user.connected?

          if m.body[0] == '@'
            process_campfire_command(user, m.body[1..-1])
          else
            user.campfire_room.speak m.body
          end
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

        listen_user.listen do |msg|
          JabberCamp::User.connected.each{|u| process_message(u, msg) }
        end

        listen_user.after_stop_listening do |user|
          JabberCamp.logger.debug "after_stop_listening: #{user.jabber_user}"

          listen_user.clear_after_stop_listening

          new_user = JabberCamp::User.connected.first
          campfire_listen(new_user) if new_user
        end
      end

      def send_message(to, text)
        JabberCamp.logger.debug "Sending: \"#{text}\" to #{to.jabber_user}"
        @jabber_client.write Blather::Stanza::Message.new(to.jabber_user, text)
      end

      def process_message(user, msg)
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

        send_message(user, text) if text
      end

      def process_campfire_command(user, cmd)
        cmd, *args = cmd.downcase.split(/\s+/)

        case cmd
        when 'get'

          # Defaults
          date = 'today'
          limit = 50

          # Set up
          if args.length == 2
            date, limit = args
          elsif args.length == 1
            if args[0] =~ /^\d+$/
              limit = args[0]
            else
              date = args[0]
            end
          end

          # Create date
          date = case date
            when 'today'     then Date.today
            when 'yesterday' then Date.today - 1
            else                  Date.parse(date) rescue nil
          end

          limit = limit.to_i

          if date && limit
            messages = []
            user.campfire_room.transcript(date).reverse.each do |msg|
              if msg[:message] && msg[:user_id]
                msg_user = JabberCamp::Proxy.lookup_campfire_user(msg[:user_id], user.campfire_connection.connection)
                if msg_user
                  messages.unshift msg_user[:name]+': '+msg[:message]
                  break if messages.length >= limit
                end
              end
            end

            if messages.length > 0
              send_message(user, messages.join("\n"))
            else
              send_message(user, "**No messages**")
            end
          else
            send_message(user, "**Invalid Date**")
          end
        else
          send_message(user, "**Invalid command**")
        end
      end

  end
end
