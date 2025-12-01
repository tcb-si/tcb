# frozen_string_literal: true

require 'set'

module TCB
  class EventBus
    def initialize
      @queue = Queue.new
      @subscribers = Hash.new { |h, k| h[k] = Set.new }
      @subscriber_metadata = {} # Maps handler object_id to metadata
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
        # Store metadata for this handler
        @subscriber_metadata[block.object_id] = extract_subscriber_metadata(block)
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
      # Don't publish SubscriberInvocationFailed if we're already handling one
      # This prevents infinite loops
      return if event.is_a?(SubscriberInvocationFailed)

      # Publish failure event
      publish_failure_event(handler, event, e)
    end

    def publish_failure_event(handler, original_event, error)
      metadata = @mutex.synchronize { @subscriber_metadata[handler.object_id] } || {}

      failure_event = SubscriberInvocationFailed.new(
        original_event: original_event,
        subscriber_type: metadata[:subscriber_type] || :unknown,
        subscriber_class: metadata[:subscriber_class] || "Unknown",
        subscriber_location: metadata[:subscriber_location],
        subscriber_source: metadata[:subscriber_source],
        error_class: error.class.name,
        error_message: error.message,
        error_backtrace: error.backtrace,
        occurred_at: Time.now
      )

      publish(failure_event)
    end

    def extract_subscriber_metadata(handler)
      if handler.is_a?(Proc)
        extract_proc_metadata(handler)
      else
        extract_class_metadata(handler)
      end
    end

    def extract_proc_metadata(proc_handler)
      file, line = proc_handler.source_location
      location = file ? "#{file}:#{line}" : nil
      source = extract_source(proc_handler)

      {
        subscriber_type: :block,
        subscriber_class: "Proc",
        subscriber_location: location,
        subscriber_source: source
      }
    end

    def extract_class_metadata(handler_instance)
      file, line = handler_instance.class.source_location
      location = file ? "#{file}:#{line}" : nil
      source = extract_method_source(handler_instance, :call)

      {
        subscriber_type: :class,
        subscriber_class: handler_instance.class.name,
        subscriber_location: location,
        subscriber_source: source
      }
    end

    def extract_source(proc_or_method)
      return nil unless defined?(MethodSource) # TODO/TBD: We'd need to extract the source of the block

      proc_or_method.source
    rescue MethodSource::SourceNotFoundError, LoadError
      nil
    end

    def extract_method_source(handler_instance, method_name)
      return nil unless defined?(MethodSource)

      handler_instance.method(method_name).source
    rescue MethodSource::SourceNotFoundError, LoadError, NameError
      nil
    end
  end
end
