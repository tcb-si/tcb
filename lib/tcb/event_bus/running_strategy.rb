# frozen_string_literal: true

module TCB
  class EventBus
    class RunningStrategy
      def initialize(event_bus)
        @event_bus = event_bus
      end

      def publish(event)
        @event_bus.queue << event
        event
      end

      def subscribe(event_class, &block)
        @event_bus.registry.add(event_class, block)
      end

      def shutdown?
        false
      end
    end
  end
end