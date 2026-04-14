# frozen_string_literal: true

require_relative "test_helpers/shared"

module TCB
  module MinitestHelpers
    include TestHelpers::Shared

    def assert_published(*expected, within: 1.0, &block)
      event_classes = expected.map { |arg| arg.is_a?(Class) ? arg : arg.class }.uniq

      with_subscriptions(*event_classes) do |captured|
        block.call

        expected.each do |arg|
          if arg.is_a?(Class)
            met = poll_until(within: within) { captured[arg].any? }
            raise Minitest::Assertion, "Expected #{arg} to be published, but it was not" unless met
          else
            event_class = arg.class
            met = poll_until(within: within) { captured[event_class].any? { |e| e == arg } }
            raise Minitest::Assertion, "Expected #{arg.inspect} to be published, but it was not" unless met
          end
        end
      end
    end

    def poll_assert(message = nil, within: 1.0, interval: 0.001, &block)
      met = poll_until(within: within, interval: interval, &block)
      return if met

      failure_message = "Condition not met within #{within}s"
      failure_message += ": \"#{message}\"" if message
      raise Minitest::Assertion, failure_message
    end
  end
end
