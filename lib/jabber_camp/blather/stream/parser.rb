module Blather # :nodoc:
  class Stream # :nodoc:
    class Parser
      def error(msg)
        JabberCamp::Logger.error "ParseError: #{msg}"
      end
    end
  end
end
