require_relative '../test_helper'

module TCB
  class EventBusConcurrentSubscriptionTest < Minitest::Test
    include EventBusDSL

    def setup
      create_event_bus
    end

    # Test: Handle concurrent subscriptions safely
    def test_concurrent_subscriptions_are_thread_safe
      subscribe_concurrently(UserRegistered, 10) { |event| }
        .publish_event(UserRegistered.new(id: 1, email: "test@example.com"))
        .assert_handler_called_times(UserRegistered, 10)
    end

    # Test: Subscribe multiple handlers concurrently then publish
    def test_subscribe_multiple_handlers_then_publish
      subscribe_concurrently(OrderPlaced, 10) { |event| }
        .publish_event(OrderPlaced.new(order_id: 1, total: 10.0))
        .assert_handler_called_times(OrderPlaced, 10)
    end

    # Test: Multiple threads subscribing to different event types
    def test_concurrent_subscriptions_different_event_types
      subscribe_concurrently(UserRegistered, 5) { |event| }
        .subscribe_concurrently(OrderPlaced, 5) { |event| }
        .publish_event(UserRegistered.new(id: 1, email: "test@example.com"))
        .publish_event(OrderPlaced.new(order_id: 1, total: 10.0))
        .assert_handler_called_times(UserRegistered, 5)
        .assert_handler_called_times(OrderPlaced, 5)
    end

    # Test: Subscriber registry remains consistent under load
    def test_subscriber_registry_consistency_under_load
      subscribe_concurrently(PaymentProcessed, 50) { |event| }
        .subscribe_to(PaymentProcessed) { |event| }
        .publish_event(PaymentProcessed.new(order_id: 1, amount: 100.0))
        .assert_handler_called_times(PaymentProcessed, 51)
    end
  end
end
