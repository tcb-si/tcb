require_relative '../test_helper'

module TCB
  class EventBusTest < Minitest::Test
    include EventBusDSL

    def setup
      create_event_bus
    end

    # Test: Subscribe handlers to specific event types
    def test_subscribe_to_specific_event_type
      received_event = nil

      subscribe_to(UserRegistered) { |event| received_event = event }
        .publish_event(UserRegistered.new(id: 1, email: "user@example.com"))
        .assert_event_delivered_to_handler(UserRegistered, id: 1, email: "user@example.com")

      sleep 0.1 # Wait for dispatch
      assert_equal 1, received_event.id
      assert_equal "user@example.com", received_event.email
    end

    # Test: Publish events to the bus
    def test_publish_event_to_bus
      subscribe_to(OrderPlaced) { |event| }
        .publish_event(OrderPlaced.new(order_id: 42, total: 99.99))
        .assert_event_delivered_to_handler(OrderPlaced, order_id: 42)
    end

    # Test: Deliver events to all subscribed handlers for that event type
    def test_deliver_to_all_subscribed_handlers
      handler1_called = false
      handler2_called = false
      handler3_called = false

      subscribe_to(UserRegistered) { |event| handler1_called = true }
      subscribe_to(UserRegistered) { |event| handler2_called = true }
      subscribe_to(UserRegistered) { |event| handler3_called = true }

      publish_event(UserRegistered.new(id: 1, email: "test@example.com"))
        .assert_handler_called_times(UserRegistered, 3)

      sleep 0.1
      assert handler1_called, "Handler 1 should have been called"
      assert handler2_called, "Handler 2 should have been called"
      assert handler3_called, "Handler 3 should have been called"
    end

    # Test: Return the published event immediately to the caller
    def test_return_published_event_immediately
      event = UserRegistered.new(id: 5, email: "immediate@example.com")

      publish_event(event)

      returned_event = last_published_event
      assert_equal event, returned_event
      assert_equal 5, returned_event.id
      assert_equal "immediate@example.com", returned_event.email
    end

    # Test: Support multiple handlers per event type
    def test_multiple_handlers_per_event_type
      emails_sent = []
      logs_recorded = []
      analytics_tracked = []

      subscribe_to(UserRegistered) { |event| emails_sent << event.email }
      subscribe_to(UserRegistered) { |event| logs_recorded << event.id }
      subscribe_to(UserRegistered) { |event| analytics_tracked << "user_#{event.id}" }

      publish_event(UserRegistered.new(id: 10, email: "multi@example.com"))
        .assert_handler_called_times(UserRegistered, 3)

      sleep 0.1
      assert_equal ["multi@example.com"], emails_sent
      assert_equal [10], logs_recorded
      assert_equal ["user_10"], analytics_tracked
    end

    # Test: Different event types are delivered to correct handlers only
    def test_event_type_isolation
      user_events = []
      order_events = []

      subscribe_to(UserRegistered) { |event| user_events << event }
      subscribe_to(OrderPlaced) { |event| order_events << event }

      publish_event(UserRegistered.new(id: 1, email: "test@example.com"))
      publish_event(OrderPlaced.new(order_id: 100, total: 200.0))

      assert_event_delivered_to_handler(UserRegistered, id: 1)
        .assert_event_delivered_to_handler(OrderPlaced, order_id: 100)

      sleep 0.1
      assert_equal 1, user_events.size
      assert_equal 1, order_events.size
      assert_instance_of UserRegistered, user_events.first
      assert_instance_of OrderPlaced, order_events.first
    end

    # Test: Multiple events published and delivered correctly
    def test_publish_multiple_events
      events_received = []

      subscribe_to(PaymentProcessed) { |event| events_received << event }

      publish_events(
        PaymentProcessed.new(order_id: 1, amount: 10.0),
        PaymentProcessed.new(order_id: 2, amount: 20.0),
        PaymentProcessed.new(order_id: 3, amount: 30.0)
      ).assert_handler_called_times(PaymentProcessed, 3)

      sleep 0.1
      assert_equal 3, events_received.size
      assert_equal [10.0, 20.0, 30.0].sort, events_received.map(&:amount).sort
    end

    # Test: No handlers registered means no delivery
    def test_no_handlers_means_no_delivery
      # Don't subscribe any handlers
      publish_event(UserRegistered.new(id: 99, email: "nobody@example.com"))
        .assert_event_not_delivered(UserRegistered)
    end
  end
end