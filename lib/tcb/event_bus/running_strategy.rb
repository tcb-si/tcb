# frozen_string_literal: true

module TCB
  class EventBus
    class RunningStrategy
      def initialize(event_bus, sync: false)
        @event_bus = event_bus
        @sync = sync
      end

      def publish(event)
        if @sync
          @event_bus.dispatch(event)
        else
          @event_bus.queue << event
        end
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