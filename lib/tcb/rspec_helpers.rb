# frozen_string_literal: true

require_relative "test_helpers/shared"

module TCB
  module RSpecHelpers
    include TestHelpers::Shared

    def self.included(base)
      base.extend(Matchers)
    end

    module Matchers
    end

    RSpec::Matchers.define :have_published do |*expected, within: 1.0|
      match do |block|
        event_classes = expected.map { |arg| arg.is_a?(Class) ? arg : arg.class }.uniq
        @missed = []

        helper = Object.new.extend(TCB::TestHelpers::Shared)

        helper.with_subscriptions(*event_classes) do |captured|
          block.call

          expected.each do |arg|
            if arg.is_a?(Class)
              met = helper.poll_until(within: within) { captured[arg].any? }
              @missed << arg unless met
            else
              event_class = arg.class
              met = helper.poll_until(within: within) { captured[event_class].any? { |e| e == arg } }
              @missed << arg unless met
            end
          end
        end

        @missed.empty?
      end

      failure_message do
        @missed.map { |arg| "Expected #{arg.inspect} to be published, but it was not" }.join("\n")
      end

      supports_block_expectations
    end

    RSpec::Matchers.define :poll_match do |within: 1.0, interval: 0.001|
      match do |block|
        helper = Object.new.extend(TCB::TestHelpers::Shared)
        helper.poll_until(within: within, interval: interval) { block.call }
      end

      failure_message do
        "Condition not met within #{within}s"
      end

      supports_block_expectations
    end
  end
end
