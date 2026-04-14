# frozen_string_literal: true

require_relative '../test_helper'

module TCB
  class TestHelpersTest < Minitest::Test
    include TCB::TestHelpers

    def setup
      config = TCB::Configuration.new
      config.event_bus = TCB::EventBus.new
      TCB.instance_variable_set(:@config, config)
    end

    def teardown
      TCB.config.event_bus.force_shutdown
      TCB.instance_variable_set(:@config, nil)
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
  end
end
