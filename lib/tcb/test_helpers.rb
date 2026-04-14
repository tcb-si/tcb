# frozen_string_literal: true

module TCB
  module TestHelpers
    def assert_published(*expected, within: 1.0, &block)
      captured = Hash.new { |h, k| h[k] = [] }
      subscriptions = []

      event_classes = expected.map { |arg| arg.is_a?(Class) ? arg : arg.class }.uniq

      event_classes.each do |event_class|
        subscription = TCB.config.event_bus.subscribe(event_class) do |event|
          captured[event_class] << event
        end
        subscriptions << subscription
      end

      block.call

      expected.each do |arg|
        if arg.is_a?(Class)
          poll_assert("#{arg} to be published", within: within) { captured[arg].any? }
        else
          event_class = arg.class
          poll_assert("#{event_class} matching #{arg.inspect} to be published", within: within) do
            captured[event_class].any? { |e| e == arg }
          end
        end
      end
    ensure
      subscriptions.each { |sub| TCB.config.event_bus.unsubscribe(sub) }
    end

    def poll_assert(message = nil, within: 1.0, interval: 0.001, &block)
      deadline = Time.now + within

      loop do
        return if block.call

        if Time.now >= deadline
          failure_message = "Condition not met within #{within}s"
          failure_message += ": \"#{message}\"" if message
          raise Minitest::Assertion, failure_message
        end

        sleep interval
      end
    end
  end
end