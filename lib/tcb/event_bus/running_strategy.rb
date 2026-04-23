# frozen_string_literal: true

module TCB
  class EventBus
    class RunningStrategy
      def initialize(event_bus, sync: false)
        @event_bus = event_bus
        @sync = sync
      end

      def start
        return if @sync

        @event_bus.dispatcher = Thread.new do
          loop do
            event = @event_bus.queue.pop
            break if event == :shutdown_sentinel

            @event_bus.dispatch(event)
            @event_bus.dispatch(build_pressure_event) if @event_bus.high_water_mark_reached?
          end
        end
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

      private

      def build_pressure_event
        EventBusQueuePressure.new(
          queue_size: @event_bus.queue.size,
          max_queue_size: @event_bus.max_queue_size,
          occupancy: @event_bus.queue.size.to_f / @event_bus.max_queue_size,
          occurred_at: Time.now
        )
      end
    end
  end
end