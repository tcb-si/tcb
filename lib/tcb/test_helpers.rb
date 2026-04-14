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
          wait_until(within) { captured[arg].any? }
          raise Minitest::Assertion, "Expected #{arg} to be published, but it was not" unless captured[arg].any?
        else
          event_class = arg.class
          wait_until(within) { captured[event_class].any? { |e| e == arg } }
          unless captured[event_class].any? { |e| e == arg }
            raise Minitest::Assertion, "Expected #{arg.inspect} to be published, but it was not"
          end
        end
      end
    ensure
      subscriptions.each { |sub| TCB.config.event_bus.unsubscribe(sub) }
    end

    private

    def wait_until(timeout, interval: 0.05)
      deadline = Time.now + timeout
      loop do
        return if yield
        break if Time.now >= deadline
        sleep interval
      end
    end
  end
end
