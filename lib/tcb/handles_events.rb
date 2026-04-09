# frozen_string_literal: true

module TCB
  module HandlesEvents
    def self.included(base)
      base.extend(ClassMethods)
      base.instance_variable_set(:@event_handler_registrations, [])
    end

    module ClassMethods
      def on(event_class, handlers)
        @event_handler_registrations << {
          event_class: event_class,
          handlers: handlers
        }
      end

      def execute(*handlers)
        handlers
      end

      def event_handler_registrations
        @event_handler_registrations
      end
    end
  end
end
