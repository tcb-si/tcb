# frozen_string_literal: true

module TCB
  class EventBus
    class ShutdownStrategy
      def initialize(event_bus:, drain:, timeout:)
        @event_bus = event_bus
        @drain = drain
        @timeout = timeout
        @start_time = Time.now
      end

      def publish(event)
        raise ShutdownError, "Cannot publish events after shutdown"
      end

      def subscribe(event_class, &block)
        raise ShutdownError, "Cannot subscribe after shutdown"
      end

      def shutdown?
        true
      end

      def execute
        emit_shutdown_event(:initiated)

        if @drain
          drain_with_timeout
        else
          force_terminate
        end
      end

      private

      def drain_with_timeout
        deadline = @start_time + @timeout

        # Wait for queue to drain AND all active dispatches to complete
        loop do
          queue_empty = @event_bus.queue.size == 0
          active_work = @event_bus.mutex.synchronize { @event_bus.active_dispatches }

          if queue_empty && active_work == 0
            # All work complete
            terminate_dispatcher
            emit_shutdown_event(:completed)
            return
          end

          if Time.now >= deadline
            # Timeout exceeded, force shutdown
            force_terminate
            emit_shutdown_event(:timeout_exceeded)
            return
          end

          sleep 0.01 # Small poll interval
        end
      end

      def force_terminate
        @event_bus.queue << :shutdown_sentinel
        @event_bus.dispatcher.kill if @event_bus.dispatcher.alive?
        @event_bus.dispatcher.join(0.1)
      end

      def terminate_dispatcher
        @event_bus.queue << :shutdown_sentinel
        @event_bus.dispatcher.join(0.5)
      end

      def emit_shutdown_event(status)
        shutdown_event = EventBusShutdown.new(
          status: status,
          drain_requested: @drain,
          timeout_seconds: @timeout,
          events_drained: @event_bus.events_processed_during_shutdown,
          occurred_at: Time.now
        )

        # Dispatch directly, bypassing queue
        @event_bus.dispatch(shutdown_event)
      end
    end
  end
end
