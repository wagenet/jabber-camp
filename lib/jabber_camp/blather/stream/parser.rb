module Blather # :nodoc:
  class Stream # :nodoc:
    class Parser
      def error(msg)
        JabberCamp.logger.error "ParseError: #{msg}"
      end
    end
  end
end
