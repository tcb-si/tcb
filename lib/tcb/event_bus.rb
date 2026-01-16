# frozen_string_literal: true

require 'set'
require_relative 'event_bus/running_strategy'
require_relative 'event_bus/shutdown_strategy'
require_relative 'event_bus/termination_signal_handler'

module TCB
  class EventBus
    class ShutdownError < StandardError; end

    attr_reader :queue, :subscribers, :subscriber_metadata, :mutex,
                :active_dispatches, :dispatcher, :events_processed_during_shutdown

    def initialize(
      handle_signals: false,
      shutdown_timeout: 30.0,
      shutdown_signals: [:TERM, :INT],
      on_signal: nil
    )
      @queue = Queue.new
      @subscribers = Hash.new { |h, k| h[k] = Set.new }
      @subscriber_metadata = {}
      @mutex = Mutex.new
      @active_dispatches = 0
      @events_processed_during_shutdown = 0
      @execution_strategy = RunningStrategy.new(self)

      @dispatcher = Thread.new do
        loop do
          event = @queue.pop
          break if event == :shutdown_sentinel

          # Dispatch directly in this thread (no wrapper thread)
          dispatch(event)
        end
      end

      if handle_signals
        @termination_signal_handler = TerminationSignalHandler.new(
          event_bus: self,
          shutdown_timeout: shutdown_timeout,
          signals: shutdown_signals,
          on_signal: on_signal
        )
        @termination_signal_handler.install
      end
    end

    # Subscribe to a specific event class
    def subscribe(event_class, &block)
      @execution_strategy.subscribe(event_class, &block)
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
    def dispatch(event)
      @mutex.synchronize { @active_dispatches += 1 }

      @events_processed_during_shutdown += 1 if shutdown?
      handlers = @mutex.synchronize { @subscribers[event.class].dup }

      # Execute handlers sequentially in the dispatcher thread
      handlers.each do |handler|
        execute_handler(handler, event)
      end
    ensure
      @mutex.synchronize { @active_dispatches -= 1 }
    end

    private

    def execute_handler(handler, event)
      handler.call(event)
    rescue => e
      # Don't publish SubscriberInvocationFailed if we're already handling one
      # This prevents infinite loops
      return if event.is_a?(SubscriberInvocationFailed)

      # Use the builder to create failure event
      failure_event = SubscriberInvocationFailed.build(
        handler: handler,
        original_event: event,
        error: e
      )

      # During shutdown, dispatch directly instead of queueing
      if shutdown?
        dispatch(failure_event)
      else
        publish(failure_event)
      end
    end
  end
end
