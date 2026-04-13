# frozen_string_literal: true

module TCB
  class StreamId < Data.define(:context, :id)
    SEPARATOR = "|"
    NAMESPACE_SEPARATOR = "/"

    class << self
      def build(context, id)
        new(context: context.to_s.downcase, id: id.to_s)
      end

      def context_from_module(mod)
        DomainContext.from_module(mod).to_s
      end

      def parse(string)
        string = string.to_s
        parts = string.split(SEPARATOR, 2)

        if parts.size != 2 || parts.any?(&:empty?)
          raise ArgumentError, "Invalid StreamId format: #{string.inspect}. Expected \"context#{SEPARATOR}id\""
        end

        new(context: parts[0], id: parts[1])
      end
    end

    def to_s
      "#{context}#{SEPARATOR}#{id}"
    end
  end
end