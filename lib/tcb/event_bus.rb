# frozen_string_literal: true

require "set"
require_relative "event_bus/running_strategy"
require_relative "event_bus/shutdown_strategy"
require_relative "event_bus/termination_signal_handler"
require_relative "event_bus/subscriber_registry"

module TCB
  class EventBus
    class ShutdownError < StandardError; end

    attr_reader :queue, :registry, :mutex, :active_dispatches, :events_processed_during_shutdown, :max_queue_size
    attr_accessor :dispatcher

    def initialize(
      handle_signals: false,
      shutdown_timeout: 30.0,
      shutdown_signals: [:TERM, :INT],
      on_signal: nil,
      max_queue_size: nil,
      high_water_mark: nil,
      sync: false
    )
      @sync = sync
      @queue = max_queue_size ? SizedQueue.new(max_queue_size) : Queue.new
      @max_queue_size = max_queue_size
      @pressure_monitor = QueuePressureMonitor.for(max_queue_size:, high_water_mark:)
      @registry = SubscriberRegistry.new
      @mutex = Mutex.new
      @active_dispatches = 0
      @events_processed_during_shutdown = 0
      @execution_strategy = RunningStrategy.new(self, sync: @sync)
      @execution_strategy.start
      install_signal_handlers(shutdown_timeout:, shutdown_signals:, on_signal:) if handle_signals
    end

    # Subscribe to a specific event class
    def subscribe(event_class, &block)
      @execution_strategy.subscribe(event_class, &block)
    end

    # Unsubscribe using a subscription token
    def unsubscribe(subscription)
      @registry.remove(subscription)
    end

    # Publish an event instance
    def publish(event)
      @execution_strategy.publish(event)
    end

    # Graceful shutdown - drains queue with timeout
    def shutdown(drain: true, timeout: 5.0)
      @execution_strategy = ShutdownStrategy.new(
        event_bus: self,
        drain: drain,
        timeout: timeout
      )
      @execution_strategy.execute
    end

    # Force shutdown - immediate, no draining
    def force_shutdown
      shutdown(drain: false, timeout: 0)
    end

    # Check if bus is shut down
    def shutdown?
      @execution_strategy.shutdown?
    end

    # Public for strategy access
    def dispatch(event_or_envelope)
      @mutex.synchronize { @active_dispatches += 1 }
      envelope = TCB::Envelope.coerce(event_or_envelope)

      @events_processed_during_shutdown += 1 if shutdown?
      handlers = @registry.handlers_for(envelope.event.class)

      handlers.each do |handler|
        execute_handler(handler, envelope)
      end
    ensure
      @mutex.synchronize { @active_dispatches -= 1 }
    end

    def high_water_mark_reached? = @pressure_monitor.check?(@queue.size)

    private

    def execute_handler(handler, envelope)
      handler.call(envelope)
    rescue => e
      return if envelope.event.is_a?(SubscriberInvocationFailed)

      failure_event = SubscriberInvocationFailed.build(
        handler:        handler,
        original_event: envelope.event,
        error:          e
      )

      if shutdown?
        dispatch(failure_event)
      else
        publish(failure_event)
      end
    end

    def install_signal_handlers(shutdown_timeout:, shutdown_signals:, on_signal:)
      @termination_signal_handler = TerminationSignalHandler.new(
        event_bus: self,
        shutdown_timeout: shutdown_timeout,
        signals: shutdown_signals,
        on_signal: on_signal
      )
      @termination_signal_handler.install
    end
  end
end
