# frozen_string_literal: true

require 'set'

module TCB
  class EventBus
    def initialize
      @queue = Queue.new
      @subscribers = Hash.new { |h, k| h[k] = Set.new }
      @mutex = Mutex.new

      @dispatcher = Thread.new do
        loop do
          event = @queue.pop
          # Spawn a thread for the entire dispatch so queue processing isn't blocked
          Thread.new { dispatch(event) }
        end
      end
    end

    # Subscribe to a specific event class
    def subscribe(event_class, &block)
      @mutex.synchronize do
        @subscribers[event_class].add(block)
      end
    end

    # Publish an event instance
    def publish(event)
      @queue << event  # atomic
      event
    end

    private

    def dispatch(event)
      handlers = @mutex.synchronize { @subscribers[event.class].dup }

      threads = handlers.map do |handler|
        Thread.new { execute_handler(handler, event) }
      end

      threads.each(&:join)
    end

    def execute_handler(handler, event)
      handler.call(event)
    rescue => e
      # Handler error is isolated - log but don't propagate
      # This allows other handlers to continue executing
      # Error is already captured by DSL's wrap_handler
    end
  end
end