# frozen_string_literal: true

module TCB
  module HandlesCommands
    CommandHandlerRegistration = Data.define(:command_class, :handler)

    def self.included(base)
      base.extend(ClassMethods)
      base.instance_variable_set(:@command_handler_registrations, [])
    end

    module ClassMethods
      def handle(command_class, handler)
        @command_handler_registrations << CommandHandlerRegistration.new(
          command_class: command_class,
          handler: handler
        )
      end

      def with(*handlers)
        raise ArgumentError, "command accepts exactly one handler" unless handlers.compact.size == 1

        handlers.first
      end

      def command_handler_registrations
        @command_handler_registrations
      end
    end
  end
end
