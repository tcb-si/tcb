require_relative '../test_helper'

module TCB
  class EventBusLifecycleTest < Minitest::Test
    include EventBusDSL

    def setup
      create_event_bus
    end

    # Test: Bus starts in accepting state
    def test_bus_initially_accepting_events
      assert_bus_accepting_events
    end

    # Test: Graceful shutdown processes queued events
    def test_graceful_shutdown_drains_queue
      subscribe_to(UserRegistered) { |event| sleep 0.1 }
        .publish_events(
          UserRegistered.new(id: 1, email: "user1@example.com"),
          UserRegistered.new(id: 2, email: "user2@example.com"),
          UserRegistered.new(id: 3, email: "user3@example.com")
        )
        .shutdown_bus(drain: true, timeout: 2.0)
        .assert_shutdown_initiated_event_published
        .assert_events_drained_before_shutdown(UserRegistered, 3)
        .assert_shutdown_completed_event_published
        .assert_bus_shutdown
    end

    # Test: Shutdown rejects new events
    def test_shutdown_rejects_new_events
      subscribe_to(UserRegistered) { |event| }
        .shutdown_bus(drain: true, timeout: 1.0)
        .assert_bus_shutdown
        .assert_rejects_events_after_shutdown
    end

    # Test: Force shutdown skips queue processing
    def test_force_shutdown_does_not_drain
      subscribe_to(UserRegistered) { |event| sleep 0.5 }
        .publish_events(
          UserRegistered.new(id: 1, email: "user1@example.com"),
          UserRegistered.new(id: 2, email: "user2@example.com")
        )
        .force_shutdown_bus
        .assert_shutdown_duration_within(0.2)
        .assert_events_not_drained(UserRegistered)
        .assert_bus_shutdown
    end

    # Test: Shutdown with timeout forces termination
    def test_shutdown_timeout_forces_termination
      subscribe_to(UserRegistered) { |event| sleep 2.0 }
        .publish_events(
          UserRegistered.new(id: 1, email: "user1@example.com"),
          UserRegistered.new(id: 2, email: "user2@example.com")
        )
        .shutdown_bus(drain: true, timeout: 0.3)
        .assert_shutdown_timeout_exceeded
        .assert_bus_shutdown
    end

    # Test: Publish after shutdown raises error
    def test_publish_after_shutdown_raises_error
      shutdown_bus(drain: false)
        .assert_raises_shutdown_error do
          publish_event(UserRegistered.new(id: 1, email: "test@example.com"))
        end
    end

    # Test: Empty queue shuts down immediately
    def test_empty_queue_shutdown_immediate
      subscribe_to(UserRegistered) { |event| }
        .shutdown_bus(drain: true, timeout: 1.0)
        .assert_shutdown_duration_within(0.2)
        .assert_shutdown_completed_event_published
        .assert_bus_shutdown
    end

    # Test: Multiple event types drain correctly
    def test_multiple_event_types_drain_on_shutdown
      subscribe_to(UserRegistered) { |event| sleep 0.05 }
        .subscribe_to(OrderPlaced) { |event| sleep 0.05 }
        .subscribe_to(PaymentProcessed) { |event| sleep 0.05 }
        .publish_events(
          UserRegistered.new(id: 1, email: "user@example.com"),
          OrderPlaced.new(order_id: 1, total: 100.0),
          PaymentProcessed.new(order_id: 1, amount: 100.0)
        )
        .shutdown_bus(drain: true, timeout: 1.0)
        .assert_events_drained_before_shutdown(UserRegistered, 1)
        .assert_events_drained_before_shutdown(OrderPlaced, 1)
        .assert_events_drained_before_shutdown(PaymentProcessed, 1)
        .assert_bus_shutdown
    end

    # Test: Handlers with errors during shutdown
    def test_handlers_with_errors_during_shutdown
      subscribe_to(UserRegistered) { |event| raise StandardError, "Handler error" }
        .subscribe_to(UserRegistered) { |event| }
        .publish_event(UserRegistered.new(id: 1, email: "test@example.com"))
        .shutdown_bus(drain: true, timeout: 1.0)
        .assert_other_handlers_executed(UserRegistered, 1)
        .assert_subscriber_invocation_failed_published(UserRegistered, expected_count: 1)
        .assert_bus_shutdown
    end

    # Test: Shutdown emits lifecycle events in order
    def test_shutdown_lifecycle_events_order
      subscribe_to(UserRegistered) { |event| sleep 0.1 }
        .publish_event(UserRegistered.new(id: 1, email: "test@example.com"))
        .shutdown_bus(drain: true, timeout: 1.0)
        .assert_shutdown_initiated_event_published
        .assert_shutdown_completed_event_published
        .assert_captured_events(TCB::EventBusShutdown) do |events|
          assert_equal 2, events.size
          assert_equal :initiated, events.first.status
          assert_equal :completed, events.last.status
        end
    end

    # Test: Shutdown with no subscribers completes immediately
    def test_shutdown_with_no_subscribers
      publish_events(
          UserRegistered.new(id: 1, email: "user1@example.com"),
          UserRegistered.new(id: 2, email: "user2@example.com")
        )
        .shutdown_bus(drain: true, timeout: 1.0)
        .assert_shutdown_duration_within(0.2)
        .assert_bus_shutdown
    end

    # Test: Graceful shutdown with concurrent handlers
    def test_graceful_shutdown_with_concurrent_handlers
      subscribe_to(UserRegistered) { |event| sleep 0.1 }
        .subscribe_to(UserRegistered) { |event| sleep 0.1 }
        .subscribe_to(UserRegistered) { |event| sleep 0.1 }
        .publish_event(UserRegistered.new(id: 1, email: "test@example.com"))
        .shutdown_bus(drain: true, timeout: 1.0)
        .assert_handler_called_times(UserRegistered, 3)
        .assert_bus_shutdown
    end

    # Test: Force shutdown stops accepting immediately
    def test_force_shutdown_stops_accepting_immediately
      force_shutdown_bus
        .assert_bus_shutdown
        .assert_rejects_events_after_shutdown
    end

    # Test: Shutdown timeout event contains metadata
    def test_shutdown_timeout_event_metadata
      subscribe_to(UserRegistered) { |event| sleep 10.0 }
        .publish_event(UserRegistered.new(id: 1, email: "test@example.com"))
        .shutdown_bus(drain: true, timeout: 0.2)
        .assert_captured_events(TCB::EventBusShutdown) do |events|
          timeout_event = events.find { |e| e.status == :timeout_exceeded }
          assert timeout_event, "Expected timeout event"
          assert_equal true, timeout_event.drain_requested
          assert_equal 0.2, timeout_event.timeout_seconds
          assert timeout_event.occurred_at.is_a?(Time)
        end
    end

    # Test: Graceful shutdown with ample timeout
    def test_graceful_shutdown_with_ample_timeout
      subscribe_to(UserRegistered) { |event| sleep 0.05 }
        .publish_events(
          UserRegistered.new(id: 1, email: "user1@example.com"),
          UserRegistered.new(id: 2, email: "user2@example.com")
        )
        .shutdown_bus(drain: true, timeout: 5.0)
        .assert_events_drained_before_shutdown(UserRegistered, 2)
        .assert_shutdown_completed_event_published
        .assert_bus_shutdown
    end

    # Test: force_shutdown — dispatcher thread je mrtev po vrnitvi
    def test_force_shutdown_dispatcher_thread_dead_after_return
      force_shutdown_bus
        .assert_dispatcher_thread_dead
    end

    # Test: graceful shutdown timeout — dispatcher thread je mrtev po vrnitvi
    def test_shutdown_timeout_dispatcher_thread_dead_after_return
      subscribe_to(UserRegistered) { |event| sleep 10.0 }
        .publish_event(UserRegistered.new(id: 1, email: "test@example.com"))
        .shutdown_bus(drain: true, timeout: 0.1)
        .assert_dispatcher_thread_dead
    end
  end
end
