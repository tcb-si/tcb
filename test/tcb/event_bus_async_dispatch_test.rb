require_relative '../test_helper'

module TCB
  class EventBusAsyncDispatchTest < Minitest::Test
    include EventBusDSL

    def setup
      create_event_bus
    end

    # Test: Dispatch events asynchronously in a background thread
    def test_events_dispatched_asynchronously
      main_thread_id = Thread.current.object_id
      handler_thread_id = nil

      subscribe_to(UserRegistered) { |event| handler_thread_id = Thread.current.object_id }
        .publish_event(UserRegistered.new(id: 1, email: "async@example.com"))

      # Handler should execute in different thread
      sleep 0.1
      refute_nil handler_thread_id, "Handler should have been called"
      refute_equal main_thread_id, handler_thread_id,
        "Handler should execute in background thread, not main thread"
    end

    # Test: Multiple events dispatched concurrently
    def test_multiple_events_dispatched_concurrently
      execution_times = []
      mutex = Mutex.new

      # Subscribe slow handler
      subscribe_to(UserRegistered) do |event|
        sleep 0.2
        mutex.synchronize { execution_times << Time.now }
      end

      # Publish 3 events quickly
      start_time = Time.now
      publish_events(
        UserRegistered.new(id: 1, email: "user1@example.com"),
        UserRegistered.new(id: 2, email: "user2@example.com"),
        UserRegistered.new(id: 3, email: "user3@example.com")
      )

      sleep 0.3 # Wait for all to complete (should finish in ~0.2s if concurrent)

      # If sequential, would take 0.6s+. If concurrent, should be ~0.2s
      total_time = Time.now - start_time
      assert total_time < 0.45,
        "Events should be dispatched concurrently (took #{total_time}s, expected < 0.45s)"
      assert_equal 3, execution_times.size
    end

    # Test: Publish returns immediately without blocking
    def test_publish_returns_immediately
      subscribe_to(UserRegistered) { |event| sleep 0.5 }

      start_time = Time.now
      returned_event = publish_event(UserRegistered.new(id: 1, email: "immediate@example.com"))
        .last_published_event
      publish_time = Time.now - start_time

      assert publish_time < 0.1,
        "Publish should return immediately (took #{publish_time}s)"
      assert_equal 1, returned_event.id
    end

    # Test: Handler execution doesn't block subsequent publishes
    def test_slow_handler_does_not_block_publishes
      slow_handler_started = false
      fast_handler_executed = false

      subscribe_to(UserRegistered) do |event|
        if event.id == 1
          slow_handler_started = true
          sleep 0.3
        end
      end

      subscribe_to(OrderPlaced) { |event| fast_handler_executed = true }

      # Publish slow event first
      publish_event(UserRegistered.new(id: 1, email: "slow@example.com"))
      sleep 0.05 # Give it time to start

      # Publish fast event - should not be blocked
      publish_event(OrderPlaced.new(order_id: 1, total: 10.0))
      sleep 0.1

      assert slow_handler_started, "Slow handler should have started"
      assert fast_handler_executed, "Fast handler should have executed despite slow handler"
    end

    # Test: Background dispatcher thread is running
    def test_dispatcher_thread_exists
      # Give dispatcher time to start
      sleep 0.1

      dispatcher_threads = Thread.list.select do |t|
        t != Thread.current && t.status == "sleep"
      end

      assert dispatcher_threads.any?,
        "Background dispatcher thread should be running"
    end
  end
end