# frozen_string_literal: true

require_relative '../test_helper'

module TCB
  class TestHelpersTest < Minitest::Test
    include TCB::MinitestHelpers

    def setup
      TCB.configure do |c|
        c.event_bus = TCB::EventBus.new
      end
    end

    def teardown
      TCB.reset!
    end

    # class argument

    def test_assert_published_passes_when_event_class_published
      assert_published(OrderPlaced) do
        TCB.publish(OrderPlaced.new(order_id: 1, total: 10.0))
      end
    end

    def test_assert_published_fails_when_event_class_not_published
      assert_raises(Minitest::Assertion) do
        assert_published(OrderPlaced, within: 0.05) do
          TCB.publish(UserRegistered.new(id: 1, email: "test@example.com"))
        end
      end
    end

    def test_assert_published_passes_with_multiple_event_classes
      assert_published(OrderPlaced, UserRegistered) do
        TCB.publish(OrderPlaced.new(order_id: 1, total: 10.0))
        TCB.publish(UserRegistered.new(id: 1, email: "test@example.com"))
      end
    end

    def test_assert_published_fails_when_one_of_multiple_classes_missing
      assert_raises(Minitest::Assertion) do
        assert_published(OrderPlaced, UserRegistered, within: 0.05) do
          TCB.publish(OrderPlaced.new(order_id: 1, total: 10.0))
        end
      end
    end

    # instance argument

    def test_assert_published_passes_when_exact_instance_matches
      assert_published(OrderPlaced.new(order_id: 42, total: 99.99)) do
        TCB.publish(OrderPlaced.new(order_id: 42, total: 99.99))
      end
    end

    def test_assert_published_fails_when_instance_does_not_match
      assert_raises(Minitest::Assertion) do
        assert_published(OrderPlaced.new(order_id: 42, total: 99.99), within: 0.05) do
          TCB.publish(OrderPlaced.new(order_id: 1, total: 10.0))
        end
      end
    end

    # cleanup

    def test_unsubscribes_after_assertion
      assert_published(OrderPlaced) do
        TCB.publish(OrderPlaced.new(order_id: 1, total: 10.0))
      end

      subscription_count_before = TCB.config.event_bus.registry.handlers_for(OrderPlaced).size

      assert_published(OrderPlaced) do
        TCB.publish(OrderPlaced.new(order_id: 2, total: 20.0))
      end

      subscription_count_after = TCB.config.event_bus.registry.handlers_for(OrderPlaced).size

      assert_equal subscription_count_before, subscription_count_after
    end

    def test_unsubscribes_even_when_assertion_fails
      assert_raises(Minitest::Assertion) do
        assert_published(OrderPlaced, within: 0.05) do
          # nothing published, so assertion will fail
        end
      end

      assert_empty TCB.config.event_bus.registry.handlers_for(OrderPlaced)
    end

    # poll_assert

    def test_poll_assert_passes_when_condition_met_immediately
      assert_silent do
        poll_assert("condition") { true }
      end
    end

    def test_poll_assert_passes_when_condition_met_within_timeout
      flag = false
      Thread.new { sleep 0.05; flag = true }

      assert_silent do
        poll_assert("flag set", within: 0.5) { flag }
      end
    end

    def test_poll_assert_fails_when_condition_not_met
      assert_raises(Minitest::Assertion) do
        poll_assert("never true", within: 0.05) { false }
      end
    end

    def test_poll_assert_failure_message_contains_description
      error = assert_raises(Minitest::Assertion) do
        poll_assert("order was placed", within: 0.05) { false }
      end

      assert_includes error.message, "order was placed"
    end

    def test_poll_assert_failure_message_contains_timeout
      error = assert_raises(Minitest::Assertion) do
        poll_assert("something", within: 0.05) { false }
      end

      assert_includes error.message, "0.05"
    end
  end
end
