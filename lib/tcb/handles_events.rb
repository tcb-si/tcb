# frozen_string_literal: true

module TCB
  module HandlesEvents
    EventHandlerRegistration = Data.define(:event_class, :handlers)
    PersistRegistration = Data.define(:event_classes, :stream_id_from_event, :context)

    def self.included(base)
      base.extend(ClassMethods)
      base.instance_variable_set(:@event_handler_registrations, [])
      base.instance_variable_set(:@persist_registrations, [])
    end

    module ClassMethods
      def react_with(*handlers)
        EventHandlerRegistration.new(event_class: :undefined, handlers: handlers)
      end

      def on(event_class, registration)
        @event_handler_registrations << registration.with(event_class: event_class)
      end

      def persist(registration)
        @persist_registrations << registration
      end

      def events(*event_classes, stream_id_from_event:)
        PersistRegistration.new(
          event_classes: event_classes,
          stream_id_from_event: stream_id_from_event,
          context: nil
        )
      end

      def event_handler_registrations
        @event_handler_registrations
      end

      def persist_registrations
        @persist_registrations
      end
    end
  end
end