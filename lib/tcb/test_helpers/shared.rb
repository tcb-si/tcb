# frozen_string_literal: true

module TCB
  module TestHelpers
    module Shared
      def poll_until(within: 1.0, interval: 0.001, &block)
        deadline = Time.now + within
        loop do
          return true if block.call
          return false if Time.now >= deadline
          sleep interval
        end
      end

      def with_subscriptions(*event_classes)
        captured = Hash.new { |h, k| h[k] = [] }
        subscriptions = event_classes.map do |event_class|
          TCB.config.event_bus.subscribe(event_class) do |event|
            captured[event_class] << event
          end
        end
        yield captured
      ensure
        subscriptions.each { |sub| TCB.config.event_bus.unsubscribe(sub) }
      end
    end
  end
end

