# frozen_string_literal: true

module TCB
  class EventBus
    class SubscriberRegistry
      Subscription = Data.define(:event_class, :handler)

      def initialize
        @subscribers = Hash.new { |h, k| h[k] = Set.new }
        @metadata = {}
        @mutex = Mutex.new
      end

      def add(event_class, handler)
        subscription = Subscription.new(event_class: event_class, handler: handler)
        @mutex.synchronize do
          @subscribers[event_class].add(handler)
          @metadata[handler.object_id] = SubscriberMetadataExtractor.new(handler).extract
        end
        subscription
      end

      def remove(subscription)
        @mutex.synchronize do
          @subscribers[subscription.event_class].delete(subscription.handler)
          @metadata.delete(subscription.handler.object_id)
        end
      end

      def handlers_for(event_class)
        @mutex.synchronize { @subscribers[event_class].dup.freeze }
      end

      def metadata_for(subscription)
        @mutex.synchronize { @metadata[subscription.handler.object_id] }
      end

      def clear
        @mutex.synchronize do
          @subscribers.clear
          @metadata.clear
        end
      end
    end
  end
end
