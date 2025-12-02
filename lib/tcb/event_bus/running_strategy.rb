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
        @event_bus.mutex.synchronize do
          @event_bus.subscribers[event_class].add(block)
          # Store metadata for this handler
          metadata = SubscriberMetadataExtractor.new(block).extract
          @event_bus.subscriber_metadata[block.object_id] = {
            subscriber_type: metadata.subscriber_type,
            subscriber_class: metadata.subscriber_class,
            subscriber_location: metadata.subscriber_location,
            subscriber_source: metadata.subscriber_source
          }
        end
      end

      def shutdown?
        false
      end
    end
  end
end
