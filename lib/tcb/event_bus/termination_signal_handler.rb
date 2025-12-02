# frozen_string_literal: true

module TCB
  class EventBus
    class TerminationSignalHandler
      def initialize(event_bus:, shutdown_timeout:, signals:, on_signal:)
        @event_bus = event_bus
        @shutdown_timeout = shutdown_timeout
        @signals = signals
        @on_signal = on_signal
        @shutdown_thread = nil
        @original_handlers = {}
      end

      def install
        @signals.each do |sig|
          @original_handlers[sig] = Signal.trap(sig) { handle_signal(sig) }
        end
      end

      private

      def handle_signal(sig)
        if shutdown_in_progress?
          handle_force_shutdown(sig)
        else
          handle_graceful_shutdown(sig)
        end
      end

      def shutdown_in_progress?
        @shutdown_thread&.alive?
      end

      def handle_graceful_shutdown(sig)
        @shutdown_thread = Thread.new do
          @on_signal&.call(sig) if @on_signal
          @event_bus.shutdown(drain: true, timeout: @shutdown_timeout)
          restore_and_reraise(sig)
        end
      end

      def handle_force_shutdown(sig)
        @shutdown_thread.kill
        @event_bus.force_shutdown
        restore_and_reraise(sig)
      end

      def restore_and_reraise(sig)
        Signal.trap(sig, @original_handlers[sig])
        Process.kill(sig, Process.pid)
      end
    end
  end
end
