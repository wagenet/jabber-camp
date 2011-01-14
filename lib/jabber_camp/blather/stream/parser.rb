module Blather # :nodoc:
  class Stream # :nodoc:
    class Parser
      def error(msg)
        JabberCamp.logger.error "ParseError: #{msg}\nBACKTRACE:\n#{caller.join("\n")}"
      end
    end
  end
end
