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
          dispatch(event)
        end
      end
    end

    # Subscribe to a specific event class
    def subscribe(event_class, &block)
      @mutex.synchronize do
        @subscribers[event_class] << block
      end
    end

    # Publish an event instance
    def publish(event)
      @queue << event  # atomic
      event
    end

    private

    def dispatch(event)
      handlers = nil

      @mutex.synchronize do
        handlers = @subscribers[event.class].dup
      end

      handlers.each { |h| h.call(event) }
    end
  end
end
