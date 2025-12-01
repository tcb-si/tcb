require_relative '../test_helper'

module TCB
  class EventBusAsyncDispatchTest < Minitest::Test
    include EventBusDSL

    def setup
      create_event_bus
    end

    # Test: Dispatch events asynchronously in a background thread
    def test_events_dispatched_asynchronously
      subscribe_to(UserRegistered) { |event| }
        .publish_event(UserRegistered.new(id: 1, email: "async@example.com"))
        .assert_handler_executed_asynchronously(UserRegistered)
    end

    # Test: Multiple events dispatched concurrently
    def test_multiple_events_dispatched_concurrently
      subscribe_to(UserRegistered) { |event| sleep 0.2 }
        .publish_events(
          UserRegistered.new(id: 1, email: "user1@example.com"),
          UserRegistered.new(id: 2, email: "user2@example.com"),
          UserRegistered.new(id: 3, email: "user3@example.com")
        )
        .assert_events_dispatched_concurrently(UserRegistered, 3, 0.45)
    end

    # Test: Publish returns immediately without blocking
    def test_publish_returns_immediately
      subscribe_to(UserRegistered) { |event| sleep 0.5 }
        .publish_event(UserRegistered.new(id: 1, email: "immediate@example.com"))
        .assert_publish_returns_immediately(0.1)
        .assert_last_published_event_matches(id: 1)
    end

    # Test: Handler execution doesn't block subsequent publishes
    def test_slow_handler_does_not_block_publishes
      subscribe_to(UserRegistered) { |event| sleep 0.3 if event.id == 1 }
        .subscribe_to(OrderPlaced) { |event| }
        .publish_event(UserRegistered.new(id: 1, email: "slow@example.com"))
        .publish_event(OrderPlaced.new(order_id: 1, total: 10.0))
        .wait_for_handlers_to_complete(UserRegistered, 1)
        .wait_for_handlers_to_complete(OrderPlaced, 1)
        .assert_handler_called_times(UserRegistered, 1)
        .assert_handler_called_times(OrderPlaced, 1)
    end

    # Test: Background dispatcher thread is running
    def test_dispatcher_thread_exists
      assert_dispatcher_thread_running
    end
  end
end
