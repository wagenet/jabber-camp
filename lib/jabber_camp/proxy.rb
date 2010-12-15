require 'date'

module JabberCamp
  class Proxy

    @@campfire_id_map = {}

    attr_reader :jabber_client
    attr_reader :jabber_state
    attr_reader :jabber_keepalive

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
        @jabber_state = :ready
        @jabber_keepalive = EM::PeriodicTimer.new(60) { @jabber_client.send(:stream).send_data ' ' }
        JabberCamp.logger.info "Jabber Connected. Send messages to #{@jabber_client.jid.inspect}"
      end

      def handle_disconnect
        if @jabber_state == :ready
          JabberCamp.logger.info "Disconnected from Jabber. Reconnecting..."
          @jabber_state = :reconnecting
          @jabber_keepalive.cancel
          @jabber_client.connect
        else
          JabberCamp.logger.error "Unable to connect."
          EM.stop if EM.reactor_running?
          @jabber_state = :disconnected
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

          if m.body[0..0] == '@'
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

      def send_message(to, text, xhtml=false)
        JabberCamp.logger.debug "Sending: \"#{text}\" to #{to.jabber_user}"
        msg = Blather::Stanza::Message.new(to.jabber_user)
        if xhtml
          msg.xhtml = text
        else
          msg.body = text
        end
        @jabber_client.write msg
      end

      def process_message(user, msg)
        JabberCamp.logger.debug "Processing Message for #{user.campfire_user['name']}: #{msg.inspect}"

        is_current = msg['user'] && msg['user']['email_address'] == user.campfire_user['email_address']

        text = nil
        xhtml = false

        case msg['type']
        when 'TextMessage'
          text = msg['user']['name']+': '+msg['body'] unless is_current
        when 'PasteMessage'
          unless is_current
            text = "#{msg['user']['name']}<br/>" +
                   "<font face='monospace' style='font-family: monospace'>#{msg['body'].gsub(/\n/, '<br/>')}</font>"
            xhtml = true
          end
        when 'EnterMessage'
          text = "**#{msg['user']['name']} entered the room**"
        when 'KickMessage'
          text = "**#{msg['user']['name']} left the room**"
        when 'SoundMessage'
          text = "**#{msg['user']['name']} played: #{msg['body']}**" unless is_current
        when 'TimestampMessage'
          # Ignore
        else
          JabberCamp.logger.debug "Unknown Message Type: #{msg.inspect}"
        end

        send_message(user, text, xhtml) if text
      end

      def process_campfire_command(user, cmd)
        cmd, data = cmd.split(/\s+/, 2)

        case cmd.downcase
        when 'get'
          process_get_command(user, *data.downcase.split(/\s+/))
        when 'users'
          process_users_command(user)
        when 'link'
          process_link_command(user)
        when 'paste'
          process_paste_command(user, data)
        when 'play'
          process_play_command(user, data)
        when 'tweet'
          process_tweet_command(user, data)
        else
          send_message(user, "**Invalid command**")
        end
      end

      def process_get_command(user, *args)
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
      end

      def process_users_command(user)
        current_users = user.campfire_room.users.map{|u| "- #{u['name']}" }
        if current_users.length > 0
          send_message(user, "**Current Users**\n#{current_users.join("\n")}")
        else
          send_message(user, "**No Users**")
        end
      end

      def process_link_command(user)
        send_message(user, "http://#{JabberCamp.campfire_subdomain}.campfirenow.com/room/#{user.campfire_room.id}")
      end

      def process_paste_command(user, text)
        user.campfire_room.paste(text)
      end

      def process_play_command(user, sound)
        user.campfire_room.play(sound)
      end

      def process_tweet_command(user, url)
        user.campfire_room.tweet(url)
      end

  end
end
