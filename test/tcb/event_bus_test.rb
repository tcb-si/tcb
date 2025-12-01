require_relative '../test_helper'

module TCB
  class EventBusTest < Minitest::Test
    include EventBusDSL

    def setup
      create_event_bus
    end

    # Test: Subscribe handlers to specific event types
    def test_subscribe_to_specific_event_type
      subscribe_to(UserRegistered) { |event| }
        .publish_event(UserRegistered.new(id: 1, email: "user@example.com"))
        .assert_event_delivered_to_handler(UserRegistered, id: 1, email: "user@example.com")
    end

    # Test: Publish events to the bus
    def test_publish_event_to_bus
      subscribe_to(OrderPlaced) { |event| }
        .publish_event(OrderPlaced.new(order_id: 42, total: 99.99))
        .assert_event_delivered_to_handler(OrderPlaced, order_id: 42)
    end

    # Test: Deliver events to all subscribed handlers for that event type
    def test_deliver_to_all_subscribed_handlers
      subscribe_to(UserRegistered) { |event| }
        .subscribe_to(UserRegistered) { |event| }
        .subscribe_to(UserRegistered) { |event| }
        .publish_event(UserRegistered.new(id: 1, email: "test@example.com"))
        .assert_handler_called_times(UserRegistered, 3)
    end

    # Test: Return the published event immediately to the caller
    def test_return_published_event_immediately
      publish_event(UserRegistered.new(id: 5, email: "immediate@example.com"))
        .assert_last_published_event_matches(id: 5, email: "immediate@example.com")
    end

    # Test: Support multiple handlers per event type
    def test_multiple_handlers_per_event_type
      subscribe_to(UserRegistered) { |event| }
        .subscribe_to(UserRegistered) { |event| }
        .subscribe_to(UserRegistered) { |event| }
        .publish_event(UserRegistered.new(id: 10, email: "multi@example.com"))
        .assert_handler_called_times(UserRegistered, 3)
        .assert_captured_events(UserRegistered) do |events|
          assert_equal 3, events.size
          assert events.all? { |e| e.id == 10 }
          assert events.all? { |e| e.email == "multi@example.com" }
        end
    end

    # Test: Different event types are delivered to correct handlers only
    def test_event_type_isolation
      subscribe_to(UserRegistered) { |event| }
        .subscribe_to(OrderPlaced) { |event| }
        .publish_event(UserRegistered.new(id: 1, email: "test@example.com"))
        .publish_event(OrderPlaced.new(order_id: 100, total: 200.0))
        .assert_event_delivered_to_handler(UserRegistered, id: 1)
        .assert_event_delivered_to_handler(OrderPlaced, order_id: 100)
        .assert_captured_events(UserRegistered) do |events|
          assert_equal 1, events.size
          assert_instance_of UserRegistered, events.first
        end
        .assert_captured_events(OrderPlaced) do |events|
          assert_equal 1, events.size
          assert_instance_of OrderPlaced, events.first
        end
    end

    # Test: Multiple events published and delivered correctly
    def test_publish_multiple_events
      subscribe_to(PaymentProcessed) { |event| }
        .publish_events(
          PaymentProcessed.new(order_id: 1, amount: 10.0),
          PaymentProcessed.new(order_id: 2, amount: 20.0),
          PaymentProcessed.new(order_id: 3, amount: 30.0)
        )
        .assert_handler_called_times(PaymentProcessed, 3)
        .assert_captured_events(PaymentProcessed) do |events|
          assert_equal 3, events.size
          assert_equal [10.0, 20.0, 30.0].sort, events.map(&:amount).sort
        end
    end

    # Test: No handlers registered means no delivery
    def test_no_handlers_means_no_delivery
      publish_event(UserRegistered.new(id: 99, email: "nobody@example.com"))
        .assert_event_not_delivered(UserRegistered)
    end
  end
end
