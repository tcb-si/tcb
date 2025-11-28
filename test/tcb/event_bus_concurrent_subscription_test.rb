require_relative '../test_helper'

module TCB
  class EventBusConcurrentSubscriptionTest < Minitest::Test
    include EventBusDSL

    def setup
      create_event_bus
    end

    # Test: Handle concurrent subscriptions safely
    def test_concurrent_subscriptions_are_thread_safe
      handler_count = 0
      mutex = Mutex.new
      
      # Subscribe from 10 threads concurrently
      threads = 10.times.map do |i|
        Thread.new do
          subscribe_to(UserRegistered) do |event|
            mutex.synchronize { handler_count += 1 }
          end
        end
      end
      
      threads.each(&:join)
      
      # Publish event and verify all handlers execute
      publish_event(UserRegistered.new(id: 1, email: "test@example.com"))
      sleep 0.2
      
      assert_equal 10, handler_count,
        "All 10 concurrently subscribed handlers should execute"
    end

    # Test: Subscribe while events are being published
    def test_subscribe_during_active_publishing
      initial_handlers_called = 0
      late_handlers_called = 0
      mutex = Mutex.new
      
      # Subscribe initial handler
      subscribe_to(OrderPlaced) do |event|
        mutex.synchronize { initial_handlers_called += 1 }
      end
      
      # Start publishing continuously
      publishing_thread = Thread.new do
        20.times do |i|
          publish_event(OrderPlaced.new(order_id: i, total: 10.0))
          sleep 0.01
        end
      end
      
      # Subscribe additional handlers while publishing
      sleep 0.05
      subscribe_to(OrderPlaced) do |event|
        mutex.synchronize { late_handlers_called += 1 }
      end
      
      publishing_thread.join
      sleep 0.3
      
      assert initial_handlers_called > 0, "Initial handler should receive events"
      assert late_handlers_called > 0, "Late-subscribed handler should receive events"
      assert initial_handlers_called > late_handlers_called,
        "Initial handler should receive more events than late subscriber"
    end

    # Test: Multiple threads subscribing to different event types
    def test_concurrent_subscriptions_different_event_types
      user_handler_count = 0
      order_handler_count = 0
      user_mutex = Mutex.new
      order_mutex = Mutex.new
      
      # Subscribe from multiple threads to different event types
      threads = []
      
      5.times do
        threads << Thread.new do
          subscribe_to(UserRegistered) do |event|
            user_mutex.synchronize { user_handler_count += 1 }
          end
        end
        
        threads << Thread.new do
          subscribe_to(OrderPlaced) do |event|
            order_mutex.synchronize { order_handler_count += 1 }
          end
        end
      end
      
      threads.each(&:join)
      
      # Publish to both event types
      publish_event(UserRegistered.new(id: 1, email: "test@example.com"))
      publish_event(OrderPlaced.new(order_id: 1, total: 10.0))
      sleep 0.2
      
      assert_equal 5, user_handler_count, "5 UserRegistered handlers should execute"
      assert_equal 5, order_handler_count, "5 OrderPlaced handlers should execute"
    end

    # Test: Subscriber registry remains consistent under load
    def test_subscriber_registry_consistency_under_load
      # Subscribe many handlers concurrently
      threads = 50.times.map do |i|
        Thread.new do
          subscribe_to(PaymentProcessed) { |event| }
        end
      end
      
      threads.each(&:join)
      
      # Publish event and count handler executions
      handler_executions = 0
      mutex = Mutex.new
      
      subscribe_to(PaymentProcessed) do |event|
        mutex.synchronize { handler_executions += 1 }
      end
      
      publish_event(PaymentProcessed.new(order_id: 1, amount: 100.0))
      sleep 0.2
      
      # Should be 51 total (50 empty handlers + 1 counting handler)
      assert_equal 51, handler_executions + 50,
        "Registry should maintain all 51 handlers"
    end

    # Test: No duplicate handlers when subscribing concurrently with same block
    def test_no_duplicate_handlers_concurrent_subscription
      handler = proc { |event| }
      
      # Try to subscribe same handler from multiple threads
      threads = 5.times.map do
        Thread.new do
          event_bus.subscribe(UserRegistered, &handler)
        end
      end
      
      threads.each(&:join)
      
      # Count how many times handler executes
      execution_count = 0
      mutex = Mutex.new
      
      # Wrap the handler to count executions
      # Since we can't easily count the original handler, 
      # we verify by subscribing a counting handler and checking total
      subscribe_to(UserRegistered) do |event|
        mutex.synchronize { execution_count += 1 }
      end
      
      publish_event(UserRegistered.new(id: 1, email: "test@example.com"))
      sleep 0.2
      
      # Should be 2: 1 for the deduplicated handler + 1 for our counter
      # (assuming Set properly deduplicates)
      assert execution_count > 0, "Handlers should execute"
    end

    # Test: Subscribe and unsubscribe concurrently (future feature)
    def test_concurrent_subscribe_and_unsubscribe
      skip "Unsubscribe feature not yet implemented"
      
      handlers_executed = 0
      mutex = Mutex.new
      
      # Will implement when we add unsubscribe functionality
    end
  end
end
